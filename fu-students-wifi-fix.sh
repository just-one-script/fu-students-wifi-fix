#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/NetworkManager/conf.d/wifi_backend.conf"
BACKUP_DIR="/var/backups/fu-students-wifi-fix"
STATE_DIR="/var/lib/fu-students-wifi-fix"
STATE_FILE="${STATE_DIR}/state"
IWD_STATE_DIR="/var/lib/iwd"
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
  --check                Check generated iwd profiles for missing files or blank credential fields.
  --update-credentials   Prompt again and rewrite all FU-Students iwd profiles with new credentials.
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
  mkdir -p "${IWD_STATE_DIR}"

  printf '[main]\niwd-config-path=\n\n[device]\nwifi.backend=iwd\nwifi.iwd.autoconnect=true\n' >"${CONFIG_FILE}"
  chmod 0644 "${CONFIG_FILE}"
  log "Configured NetworkManager to use iwd: ${CONFIG_FILE}"
}

iwd_profile_file_for_ssid() {
  local ssid="$1"

  printf '%s/%s.8021x' "${IWD_STATE_DIR}" "${ssid}"
}

prompt_yes_no() {
  local prompt="$1"
  local default="$2"
  local answer=""

  if [[ ! -t 0 ]]; then
    [[ "${default}" == "yes" ]]
    return
  fi

  if [[ "${default}" == "yes" ]]; then
    read -r -p "${prompt} [Y/n] " answer
    case "${answer}" in
      n|N|no|NO|No) return 1 ;;
      *) return 0 ;;
    esac
  fi

  read -r -p "${prompt} [y/N] " answer
  case "${answer}" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
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

write_iwd_profiles_with_credentials() {
  local username="$1"
  local password="$2"
  local ssid=""
  local profile_file=""

  mkdir -p "${IWD_STATE_DIR}"

  for ssid in "${SSIDS[@]}"; do
    profile_file="$(iwd_profile_file_for_ssid "${ssid}")"

    {
      printf '[Security]\n'
      printf 'EAP-Method=PEAP\n'
      printf 'EAP-Identity=%s\n' "${username}"
      printf 'EAP-PEAP-Phase2-Method=MSCHAPV2\n'
      printf 'EAP-PEAP-Phase2-Identity=%s\n' "${username}"
      printf 'EAP-PEAP-Phase2-Password=%s\n' "${password}"
      printf '\n[Settings]\n'
      printf 'AutoConnect=true\n'
    } >"${profile_file}"

    chmod 0600 "${profile_file}"
    log "Created iwd profile: ${profile_file}"
  done
}

write_iwd_profiles_interactive() {
  local username=""
  local password=""

  if ! prompt_yes_no "Create iwd 802.1x profiles for FU-Students Wi-Fi networks now?" "yes"; then
    log "Skipped iwd profile creation."
    log "You will need to create iwd profiles manually before these networks can connect reliably."
    return
  fi

  if ! prompt_credentials username password; then
    log "Skipped iwd profile creation because credentials were not provided."
    log "Run this script from an interactive terminal so it can ask for your username and password."
    return
  fi

  write_iwd_profiles_with_credentials "${username}" "${password}"
  append_state_value "IWD_PROFILE_CREATED" "1"
}

profile_key_has_value() {
  local profile_file="$1"
  local key="$2"
  local line=""
  local value=""

  while IFS= read -r line; do
    if [[ "${line}" == "${key}="* ]]; then
      value="${line#*=}"
      [[ -n "${value}" ]]
      return
    fi
  done <"${profile_file}"

  return 1
}

check_iwd_profiles() {
  local ssid=""
  local profile_file=""
  local failed=0
  local key=""
  local required_keys=(
    "EAP-Identity"
    "EAP-PEAP-Phase2-Identity"
    "EAP-PEAP-Phase2-Password"
  )

  for ssid in "${SSIDS[@]}"; do
    profile_file="$(iwd_profile_file_for_ssid "${ssid}")"

    if [[ ! -f "${profile_file}" ]]; then
      log "Missing profile: ${profile_file}"
      failed=1
      continue
    fi

    if [[ ! -s "${profile_file}" ]]; then
      log "Empty profile: ${profile_file}"
      failed=1
      continue
    fi

    for key in "${required_keys[@]}"; do
      if ! profile_key_has_value "${profile_file}" "${key}"; then
        log "Profile ${profile_file} has missing or blank ${key}."
        failed=1
      fi
    done
  done

  if [[ "${failed}" -eq 0 ]]; then
    log "All FU-Students iwd profiles exist and have non-empty credential fields."
    return 0
  fi

  log "Profile check failed. Run: sudo ./$(script_name) --update-credentials"
  return 1
}

enable_iwd() {
  log "Enabling and starting iwd..."
  systemctl enable --now iwd
}

restart_iwd() {
  log "Restarting iwd..."
  systemctl restart iwd
}

restart_networkmanager() {
  log "Restarting NetworkManager..."
  systemctl restart NetworkManager
}

setup_wifi() {
  require_root
  require_command systemctl
  require_command date
  require_command cp

  ensure_iwd_can_be_installed
  record_initial_state
  install_iwd
  write_networkmanager_config
  write_iwd_profiles_interactive
  enable_iwd
  restart_iwd
  restart_networkmanager

  log ""
  log "Done. NetworkManager is configured to use iwd, and iwd is responsible for the FU-Students Wi-Fi profiles."
  log "Do not create these networks again from the OS Wi-Fi dialog unless you are debugging."
  log "iwd should connect automatically if the credentials are correct and one of the configured networks is visible."
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

  record_initial_state

  if ! prompt_credentials username password; then
    die "credentials were not provided. Run this command from an interactive terminal."
  fi

  write_iwd_profiles_with_credentials "${username}" "${password}"
  append_state_value "IWD_PROFILE_CREATED" "1"
  check_iwd_profiles

  restart_iwd
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

  load_state
  restore_networkmanager_config
  restore_iwd_profiles
  restore_iwd_state
  restart_networkmanager
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
      check_iwd_profiles
      ;;
    --update-credentials|--fix-credentials)
      update_credentials
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
