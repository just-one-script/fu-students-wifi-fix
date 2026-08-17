#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/NetworkManager/conf.d/wifi_backend.conf"
BACKUP_DIR="/var/backups/fu-students-wifi-fix"
STATE_DIR="/var/lib/fu-students-wifi-fix"
STATE_FILE="${STATE_DIR}/state"
IWD_STATE_DIR="/var/lib/iwd"
PROFILE_PREFIX="fu-students-wifi-fix"
CA_CERT_FILE="${STATE_DIR}/fun-DC-CA.pem"
AUTH_DOMAIN="fun.cantho"
SSIDS=("FU-Students" "FU-Students Alpha" "FU-Students_6G")

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

script_name() {
  printf '%s' "${0##*/}"
}

usage() {
  cat <<EOF
Usage:
  sudo ./$(script_name) [option]

Make sure you have read the README carefully before running this script.
If no option is provided, this help is shown and no system changes are made.

Options:
  --setup                Configure the FU-Students Wi-Fi fix.
  --rollback             Revert changes made by --setup.
  --check                Check generated NetworkManager profiles and credential fields.
  --update-credentials   Prompt again and update all FU-Students NetworkManager profiles.
  --ca-cert FILE|system  Use an official CA file, or return to the system CA bundle.
  -h, --help             Show this help.
EOF
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "run this script as root, for example: sudo ./$(script_name) --setup"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

is_iwd_installed() {
  command -v iwd >/dev/null 2>&1 || command -v iwctl >/dev/null 2>&1
}

has_supported_package_manager() {
  command -v dnf >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1
}

ensure_iwd_can_be_installed() {
  if is_iwd_installed || has_supported_package_manager; then
    return
  fi

  die "iwd is not installed and no supported package manager was found. Install iwd manually, then run this script again."
}

install_iwd() {
  if is_iwd_installed; then
    log "iwd is already installed."
    return
  fi

  if command -v dnf >/dev/null 2>&1; then
    log "Installing iwd with dnf..."
    dnf install -y iwd
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    log "Installing iwd with apt-get..."
    apt-get update
    apt-get install -y iwd
    return
  fi

  die "iwd is not installed and no supported package manager was found. Install iwd manually, then run this script again."
}

systemctl_is_enabled() {
  systemctl is-enabled "$1" >/dev/null 2>&1
}

systemctl_is_active() {
  systemctl is-active "$1" >/dev/null 2>&1
}

write_ssids_to_state() {
  local ssid=""

  printf 'SSIDS=('
  for ssid in "${SSIDS[@]}"; do
    printf ' %q' "${ssid}"
  done
  printf ' )\n'
}

record_initial_state() {
  local iwd_was_enabled=0
  local iwd_was_active=0
  local config_existed=0
  local backup_file=""
  local iwd_profile_backup_dir=""
  local iwd_profile_files=()
  local ssid=""

  mkdir -p "${BACKUP_DIR}" "${STATE_DIR}"

  if [[ -f "${STATE_FILE}" ]]; then
    log "Existing rollback state found at ${STATE_FILE}; preserving it."
    write_ssids_to_state >>"${STATE_FILE}"
    return
  fi

  if systemctl_is_enabled iwd; then
    iwd_was_enabled=1
  fi

  if systemctl_is_active iwd; then
    iwd_was_active=1
  fi

  if [[ -f "${CONFIG_FILE}" ]]; then
    config_existed=1
    backup_file="${BACKUP_DIR}/wifi_backend.conf.$(date +%Y%m%d%H%M%S)"
    cp -a "${CONFIG_FILE}" "${backup_file}"
    log "Backed up existing config to ${backup_file}"
  fi

  if [[ -d "${IWD_STATE_DIR}" ]]; then
    for ssid in "${SSIDS[@]}"; do
      shopt -s nullglob
      iwd_profile_files+=("${IWD_STATE_DIR}/${ssid}".*)
      shopt -u nullglob
    done

    if (( ${#iwd_profile_files[@]} > 0 )); then
      iwd_profile_backup_dir="${BACKUP_DIR}/iwd-profiles.$(date +%Y%m%d%H%M%S)"
      mkdir -p "${iwd_profile_backup_dir}"
      cp -a "${iwd_profile_files[@]}" "${iwd_profile_backup_dir}/"
      log "Backed up existing iwd profile files to ${iwd_profile_backup_dir}"
    fi
  fi

  {
    printf 'CONFIG_FILE=%q\n' "${CONFIG_FILE}"
    printf 'CONFIG_EXISTED=%q\n' "${config_existed}"
    printf 'BACKUP_FILE=%q\n' "${backup_file}"
    printf 'IWD_WAS_ENABLED=%q\n' "${iwd_was_enabled}"
    printf 'IWD_WAS_ACTIVE=%q\n' "${iwd_was_active}"
    printf 'IWD_STATE_DIR=%q\n' "${IWD_STATE_DIR}"
    write_ssids_to_state
    printf 'IWD_PROFILE_BACKUP_DIR=%q\n' "${iwd_profile_backup_dir}"
    printf 'IWD_PROFILE_CREATED=%q\n' "0"
    printf 'NM_PROFILES_MANAGED=%q\n' "0"
  } >"${STATE_FILE}"
}

append_state_value() {
  local key="$1"
  local value="$2"

  if [[ -f "${STATE_FILE}" ]]; then
    printf '%s=%q\n' "${key}" "${value}" >>"${STATE_FILE}"
  fi
}

write_networkmanager_config() {
  mkdir -p "$(dirname "${CONFIG_FILE}")"

  printf '[device]\nwifi.backend=iwd\nwifi.iwd.autoconnect=false\n' >"${CONFIG_FILE}"
  chmod 0644 "${CONFIG_FILE}"
  log "Configured NetworkManager to use iwd: ${CONFIG_FILE}"
}

networkmanager_profile_id_for_ssid() {
  local ssid="$1"

  printf '%s:%s' "${PROFILE_PREFIX}" "${ssid}"
}

prompt_credentials() {
  local username_var="$1"
  local password_var="$2"
  local entered_username=""
  local entered_password=""

  if [[ ! -t 0 ]]; then
    return 1
  fi

  read -r -p "FU-Students username/student ID: " entered_username
  read -r -s -p "FU-Students password: " entered_password
  log ""

  if [[ -z "${entered_username}" || -z "${entered_password}" ]]; then
    return 1
  fi

  printf -v "${username_var}" '%s' "${entered_username}"
  printf -v "${password_var}" '%s' "${entered_password}"
}

networkmanager_profile_exists() {
  nmcli --get-values connection.id connection show "$1" >/dev/null 2>&1
}

system_ca_bundle() {
  local candidate=""

  for candidate in \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/pki/tls/certs/ca-bundle.crt \
    /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem; do
    if [[ -r "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return
    fi
  done

  return 1
}

active_ca_certificate() {
  if [[ -r "${CA_CERT_FILE}" ]]; then
    printf '%s' "${CA_CERT_FILE}"
    return
  fi

  system_ca_bundle
}

write_networkmanager_profiles_with_credentials() {
  local username="$1"
  local password="$2"
  local ssid=""
  local profile_id=""
  local ca_cert=""

  ca_cert="$(active_ca_certificate)" || die "no supported system CA bundle was found; provide one with --ca-cert FILE"

  for ssid in "${SSIDS[@]}"; do
    profile_id="$(networkmanager_profile_id_for_ssid "${ssid}")"

    if networkmanager_profile_exists "${profile_id}"; then
      nmcli connection modify "${profile_id}" \
        connection.autoconnect yes \
        connection.autoconnect-priority 100 \
        wifi.ssid "${ssid}" \
        wifi.mode infrastructure \
        wifi-sec.key-mgmt wpa-eap \
        802-1x.eap peap \
        802-1x.identity "${username}" \
        802-1x.phase2-auth mschapv2 \
        802-1x.password "${password}" \
        802-1x.system-ca-certs no \
        802-1x.ca-cert "${ca_cert}" \
        802-1x.domain-suffix-match "${AUTH_DOMAIN}" \
        ipv4.method auto \
        ipv6.method auto
      log "Updated NetworkManager profile: ${profile_id}"
      continue
    fi

    nmcli connection add \
      type wifi \
      ifname "*" \
      con-name "${profile_id}" \
      ssid "${ssid}" \
      autoconnect yes \
      -- \
      connection.autoconnect-priority 100 \
      wifi-sec.key-mgmt wpa-eap \
      802-1x.eap peap \
      802-1x.identity "${username}" \
      802-1x.phase2-auth mschapv2 \
      802-1x.password "${password}" \
      802-1x.system-ca-certs no \
      802-1x.ca-cert "${ca_cert}" \
      802-1x.domain-suffix-match "${AUTH_DOMAIN}"
    log "Created NetworkManager profile: ${profile_id}"
  done
}

networkmanager_profile_field_has_value() {
  local profile_id="$1"
  local field="$2"
  local value=""

  value="$(nmcli --show-secrets --get-values "${field}" connection show "${profile_id}" 2>/dev/null)"
  [[ -n "${value}" ]]
}

networkmanager_profile_field_equals() {
  local profile_id="$1"
  local field="$2"
  local expected="$3"
  local value=""

  value="$(nmcli --show-secrets --get-values "${field}" connection show "${profile_id}" 2>/dev/null)"
  [[ "${value}" == "${expected}" ]]
}

check_networkmanager_profiles() {
  local ssid=""
  local profile_id=""
  local failed=0
  local field=""
  local required_fields=(
    "802-1x.identity"
    "802-1x.password"
  )

  for ssid in "${SSIDS[@]}"; do
    profile_id="$(networkmanager_profile_id_for_ssid "${ssid}")"

    if ! networkmanager_profile_exists "${profile_id}"; then
      log "Missing NetworkManager profile: ${profile_id}"
      failed=1
      continue
    fi

    for field in "${required_fields[@]}"; do
      if ! networkmanager_profile_field_has_value "${profile_id}" "${field}"; then
        log "Profile ${profile_id} has missing or blank ${field}."
        failed=1
      fi
    done

    if ! networkmanager_profile_field_has_value "${profile_id}" "802-1x.ca-cert"; then
      log "Profile ${profile_id} has no CA certificate configured."
      failed=1
    fi

    if ! networkmanager_profile_field_equals "${profile_id}" "802-1x.system-ca-certs" "no"; then
      log "Profile ${profile_id} uses system-ca-certs, which is unsupported by the iwd backend."
      failed=1
    fi

    if ! networkmanager_profile_field_equals "${profile_id}" "802-1x.domain-suffix-match" "${AUTH_DOMAIN}"; then
      log "Profile ${profile_id} does not validate the authentication domain ${AUTH_DOMAIN}."
      failed=1
    fi
  done

  if [[ "${failed}" -eq 0 ]]; then
    log "All FU-Students NetworkManager profiles have credentials, CA validation, and the expected authentication domain."
    return 0
  fi

  log "Profile check failed. Use --update-credentials or --ca-cert as indicated above."
  return 1
}

install_ca_certificate() {
  local source_file="$1"
  local temp_dir=""
  local candidate=""
  local extracted=""
  local constraints=""

  [[ -f "${source_file}" && -r "${source_file}" ]] || return 1

  mkdir -p "${STATE_DIR}"
  temp_dir="$(mktemp -d "${STATE_DIR}/ca.XXXXXX")"
  candidate="${temp_dir}/ca.pem"
  extracted="${temp_dir}/pkcs12.pem"

  if openssl x509 -in "${source_file}" -out "${candidate}" 2>/dev/null; then
    :
  elif openssl x509 -inform DER -in "${source_file}" -out "${candidate}" 2>/dev/null; then
    :
  else
    if ! openssl pkcs12 -in "${source_file}" -cacerts -nokeys -passin pass: -out "${extracted}" 2>/dev/null; then
      if [[ ! -t 0 ]]; then
        rm -rf "${temp_dir}"
        return 1
      fi
      log "The PKCS#12 file may require its import password."
      if ! openssl pkcs12 -in "${source_file}" -cacerts -nokeys -out "${extracted}"; then
        rm -rf "${temp_dir}"
        return 1
      fi
    fi
    if ! openssl x509 -in "${extracted}" -out "${candidate}"; then
      rm -rf "${temp_dir}"
      return 1
    fi
  fi

  constraints="$(openssl x509 -in "${candidate}" -noout -ext basicConstraints 2>/dev/null || true)"
  if [[ "${constraints}" != *"CA:TRUE"* ]] || ! openssl x509 -in "${candidate}" -checkend 0 -noout >/dev/null; then
    rm -rf "${temp_dir}"
    return 1
  fi

  cp "${candidate}" "${CA_CERT_FILE}"
  chmod 0644 "${CA_CERT_FILE}"
  rm -rf "${temp_dir}"

  log "Installed CA certificate: ${CA_CERT_FILE}"
  openssl x509 -in "${CA_CERT_FILE}" -noout -subject -issuer -fingerprint -sha256
}

apply_ca_certificate_to_profiles() {
  local ca_cert="$1"
  local ssid=""
  local profile_id=""

  for ssid in "${SSIDS[@]}"; do
    profile_id="$(networkmanager_profile_id_for_ssid "${ssid}")"
    nmcli connection modify "${profile_id}" \
      802-1x.system-ca-certs no \
      802-1x.ca-cert "${ca_cert}" \
      802-1x.domain-suffix-match "${AUTH_DOMAIN}"
    log "Updated CA validation for: ${profile_id}"
  done
}

configure_ca_certificate() {
  local source_file="$1"
  local ca_cert=""
  local ssid=""
  local profile_id=""

  require_root
  require_command nmcli
  require_command rm

  for ssid in "${SSIDS[@]}"; do
    profile_id="$(networkmanager_profile_id_for_ssid "${ssid}")"
    networkmanager_profile_exists "${profile_id}" || die "missing profile ${profile_id}; run --setup first"
  done

  if [[ "${source_file}" == "system" ]]; then
    ca_cert="$(system_ca_bundle)" || die "no supported system CA bundle was found"
    apply_ca_certificate_to_profiles "${ca_cert}"
    rm -f "${CA_CERT_FILE}"
    log "Using the system CA bundle: ${ca_cert}"
  else
    require_command openssl
    require_command mktemp
    require_command cp
    require_command chmod
    install_ca_certificate "${source_file}" || die "the CA file is unreadable, expired, unsupported, or is not a CA certificate"
    apply_ca_certificate_to_profiles "${CA_CERT_FILE}"
  fi

  check_networkmanager_profiles
  log "Reconnect to FU-Students so the new certificate validation takes effect."
}

enable_iwd() {
  log "Enabling and starting iwd..."
  systemctl enable --now iwd
}

restart_networkmanager() {
  log "Restarting NetworkManager..."
  systemctl restart NetworkManager
}

setup_wifi() {
  local username=""
  local password=""

  require_root
  require_command systemctl
  require_command date
  require_command cp
  require_command nmcli

  ensure_iwd_can_be_installed
  active_ca_certificate >/dev/null || die "no supported system CA bundle was found; provide one with --ca-cert FILE"

  if ! prompt_credentials username password; then
    die "credentials were not provided. No system changes were made."
  fi

  record_initial_state
  install_iwd
  write_networkmanager_config
  enable_iwd
  restart_networkmanager
  append_state_value "NM_PROFILES_MANAGED" "1"
  append_state_value "IWD_PROFILE_CREATED" "1"
  write_networkmanager_profiles_with_credentials "${username}" "${password}"
  check_networkmanager_profiles

  log ""
  log "Done. NetworkManager owns all Wi-Fi profiles and uses iwd only as its Wi-Fi backend."
  log "Normal home, hotspot, and captive-portal networks can be managed from the OS Wi-Fi dialog."
  log "FU-Students networks should connect automatically when visible."
  log "CA validation uses: $(active_ca_certificate)"
  log "If FPT uses its private CA, download it and run: sudo ./$(script_name) --ca-cert FILE"
  log ""
  log "If connection still fails, try:"
  log "  journalctl -u iwd -b"
  log "  journalctl -u NetworkManager -b"
  log ""
  log "To undo these changes, run:"
  log "  sudo ./$(script_name) --rollback"
}

update_credentials() {
  local username=""
  local password=""

  require_root
  require_command systemctl
  require_command date
  require_command cp
  require_command nmcli

  active_ca_certificate >/dev/null || die "no supported system CA bundle was found; provide one with --ca-cert FILE"
  record_initial_state

  if ! prompt_credentials username password; then
    die "credentials were not provided. Run this command from an interactive terminal."
  fi

  append_state_value "NM_PROFILES_MANAGED" "1"
  append_state_value "IWD_PROFILE_CREATED" "1"
  write_networkmanager_profiles_with_credentials "${username}" "${password}"
  check_networkmanager_profiles

  restart_networkmanager

  log ""
  log "Credential update complete."
  log "If the old failed connection state remains visible, reboot before testing again."
}

load_state() {
  if [[ ! -f "${STATE_FILE}" ]]; then
    die "state file not found: ${STATE_FILE}. Nothing to rollback."
  fi

  # shellcheck source=/dev/null
  source "${STATE_FILE}"

  CONFIG_FILE="${CONFIG_FILE:-/etc/NetworkManager/conf.d/wifi_backend.conf}"
  CONFIG_EXISTED="${CONFIG_EXISTED:-0}"
  BACKUP_FILE="${BACKUP_FILE:-}"
  IWD_WAS_ENABLED="${IWD_WAS_ENABLED:-0}"
  IWD_WAS_ACTIVE="${IWD_WAS_ACTIVE:-0}"
  IWD_STATE_DIR="${IWD_STATE_DIR:-/var/lib/iwd}"
  if ! declare -p SSIDS >/dev/null 2>&1; then
    if [[ -n "${SSID:-}" ]]; then
      SSIDS=("${SSID}")
    else
      SSIDS=("FU-Students" "FU-Students Alpha" "FU-Students_6G")
    fi
  fi
  IWD_PROFILE_BACKUP_DIR="${IWD_PROFILE_BACKUP_DIR:-}"
  IWD_PROFILE_CREATED="${IWD_PROFILE_CREATED:-0}"
  NM_PROFILES_MANAGED="${NM_PROFILES_MANAGED:-0}"
}

remove_networkmanager_profiles() {
  local ssid=""
  local profile_id=""

  if [[ "${NM_PROFILES_MANAGED}" != "1" ]]; then
    return
  fi

  for ssid in "${SSIDS[@]}"; do
    profile_id="$(networkmanager_profile_id_for_ssid "${ssid}")"
    if networkmanager_profile_exists "${profile_id}"; then
      nmcli connection delete "${profile_id}"
      log "Removed NetworkManager profile created by setup: ${profile_id}"
    fi
  done
}

restore_networkmanager_config() {
  if [[ "${CONFIG_EXISTED}" == "1" ]]; then
    if [[ -z "${BACKUP_FILE}" || ! -f "${BACKUP_FILE}" ]]; then
      die "backup file is missing; refusing to overwrite current config: ${BACKUP_FILE:-<empty>}"
    fi

    cp -a "${BACKUP_FILE}" "${CONFIG_FILE}"
    log "Restored previous NetworkManager config from ${BACKUP_FILE}"
    return
  fi

  if [[ -f "${CONFIG_FILE}" ]]; then
    rm -f "${CONFIG_FILE}"
    log "Removed NetworkManager config created by setup: ${CONFIG_FILE}"
  else
    log "NetworkManager config already absent: ${CONFIG_FILE}"
  fi
}

restore_iwd_state() {
  if [[ "${IWD_WAS_ACTIVE}" != "1" ]]; then
    log "Stopping iwd because it was not active before setup..."
    systemctl stop iwd || true
  fi

  if [[ "${IWD_WAS_ENABLED}" != "1" ]]; then
    log "Disabling iwd because it was not enabled before setup..."
    systemctl disable iwd || true
  fi
}

restore_iwd_profiles() {
  local current_profiles=()
  local ssid=""
  local profile_file=""

  if [[ -z "${IWD_PROFILE_BACKUP_DIR}" ]]; then
    if [[ "${IWD_PROFILE_CREATED}" == "1" ]]; then
      for ssid in "${SSIDS[@]}"; do
        profile_file="${IWD_STATE_DIR}/${ssid}.8021x"
        if [[ -f "${profile_file}" ]]; then
          rm -f "${profile_file}"
          log "Removed iwd profile created by setup: ${profile_file}"
        fi
      done
      return
    fi

    log "No pre-existing iwd profile backup was recorded."
    return
  fi

  if [[ ! -d "${IWD_PROFILE_BACKUP_DIR}" ]]; then
    die "iwd profile backup directory is missing: ${IWD_PROFILE_BACKUP_DIR}"
  fi

  mkdir -p "${IWD_STATE_DIR}"

  for ssid in "${SSIDS[@]}"; do
    shopt -s nullglob
    current_profiles+=("${IWD_STATE_DIR}/${ssid}".*)
    shopt -u nullglob
  done

  if (( ${#current_profiles[@]} > 0 )); then
    rm -f "${current_profiles[@]}"
  fi

  cp -a "${IWD_PROFILE_BACKUP_DIR}/." "${IWD_STATE_DIR}/"
  log "Restored previous iwd profile files from ${IWD_PROFILE_BACKUP_DIR}"
}

remove_state_file() {
  rm -f "${STATE_FILE}"
  log "Removed rollback state file: ${STATE_FILE}"
}

prompt_reboot() {
  local answer=""

  log ""

  if [[ ! -t 0 ]]; then
    log "Reboot is recommended now, but no interactive terminal is available."
    log "Reboot later with: sudo systemctl reboot"
    return
  fi

  read -r -p "Reboot now to fully reset Wi-Fi backend state? [y/N] " answer

  case "${answer}" in
    y|Y|yes|YES|Yes)
      log "Rebooting now..."
      systemctl reboot
      ;;
    *)
      log "Reboot skipped. Reboot later before testing Wi-Fi again."
      ;;
  esac
}

rollback_wifi() {
  require_root
  require_command systemctl
  require_command cp
  require_command rm
  require_command nmcli

  load_state
  restore_networkmanager_config
  remove_networkmanager_profiles
  restore_iwd_profiles
  restore_iwd_state
  restart_networkmanager
  if [[ -f "${CA_CERT_FILE}" ]]; then
    rm -f "${CA_CERT_FILE}"
    log "Removed CA certificate installed by setup: ${CA_CERT_FILE}"
  fi
  remove_state_file

  log ""
  log "Rollback complete."
  prompt_reboot
}

main() {
  case "${1:-}" in
    ""|-h|--help)
      usage
      ;;
    --setup)
      setup_wifi
      ;;
    --rollback)
      rollback_wifi
      ;;
    --check)
      require_root
      require_command nmcli
      check_networkmanager_profiles
      ;;
    --update-credentials|--fix-credentials)
      update_credentials
      ;;
    --ca-cert)
      [[ $# -eq 2 ]] || die "--ca-cert requires a certificate path or the value 'system'"
      configure_ca_certificate "$2"
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
