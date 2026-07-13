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

usage() {
  cat <<'EOF'
FU-Students Wi-Fi Fix setup

What this script does:
  - Installs iwd when possible.
  - Configures NetworkManager to use iwd as the Wi-Fi backend.
  - Creates iwd 802.1x profiles for:
      * FU-Students
      * FU-Students Alpha
      * FU-Students_6G
  - Uses the same PEAP/MSCHAPV2 username and password for all three profiles.
  - Restarts iwd and NetworkManager.
  - Records rollback state for rollback.sh.

Usage:
  sudo ./setup.sh
  sudo ./setup.sh --check
  sudo ./setup.sh --update-credentials
  sudo ./setup.sh --help

Options:
  --check                Check generated iwd profiles for missing files or blank credential fields.
  --update-credentials   Prompt again and rewrite all FU-Students iwd profiles with new credentials.
  -h, --help             Show this help.

Troubleshooting:
  - If you mistyped your username or password:
      sudo ./setup.sh --update-credentials
  - If you want to check whether profile files and credential fields exist:
      sudo ./setup.sh --check
  - If you created broken profiles from the OS Wi-Fi dialog, remove them:
      nmcli connection delete FU-Students
      nmcli connection delete 'FU-Students Alpha'
      nmcli connection delete FU-Students_6G
  - Do not recreate these networks from the OS Wi-Fi dialog after setup.
  - Check logs with:
      journalctl -u iwd -b
      journalctl -u NetworkManager -b
EOF
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "run this script as root, for example: sudo ./setup.sh"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

is_iwd_installed() {
  command -v iwd >/dev/null 2>&1 || command -v iwctl >/dev/null 2>&1
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
    {
      printf 'SSIDS=('
      for ssid in "${SSIDS[@]}"; do
        printf ' %q' "${ssid}"
      done
      printf ' )\n'
    } >>"${STATE_FILE}"
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
    printf 'SSIDS=('
    for ssid in "${SSIDS[@]}"; do
      printf ' %q' "${ssid}"
    done
    printf ' )\n'
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

write_iwd_profile() {
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

  log "Profile check failed. Run: sudo ./setup.sh --update-credentials"
  return 1
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

main() {
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    --check)
      require_root
      check_iwd_profiles
      exit $?
      ;;
    --update-credentials|--fix-credentials)
      update_credentials
      exit 0
      ;;
    "")
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac

  require_root
  require_command systemctl
  require_command date
  require_command cp

  record_initial_state
  install_iwd
  write_networkmanager_config
  write_iwd_profile
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
  log "  sudo ./rollback.sh"
}

main "$@"
