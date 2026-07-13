#!/usr/bin/env bash
set -euo pipefail

DEFAULT_CONFIG_FILE="/etc/NetworkManager/conf.d/wifi_backend.conf"
STATE_FILE="/var/lib/fu-students-wifi-fix/state"
DEFAULT_IWD_STATE_DIR="/var/lib/iwd"
DEFAULT_SSIDS=("FU-Students" "FU-Students Alpha" "FU-Students_6G")

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
FU-Students Wi-Fi Fix rollback

What this script does:
  - Restores the NetworkManager config that existed before setup, if backed up.
  - Removes the setup-created NetworkManager config if no previous config existed.
  - Restores previous iwd profiles for FU-Students networks, if backed up.
  - Removes generated iwd profiles if setup created them from scratch.
  - Restores the previous iwd service enabled/running state when possible.
  - Restarts NetworkManager.
  - Prompts whether to reboot immediately.

Usage:
  sudo ./rollback.sh
  sudo ./rollback.sh --help

Options:
  -h, --help   Show this help.

Troubleshooting:
  - Reboot after rollback before testing Wi-Fi again.
  - If rollback says the state file is missing, setup did not record rollback state
    or rollback already ran.
  - Check logs with:
      journalctl -u iwd -b
      journalctl -u NetworkManager -b
EOF
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "run this script as root, for example: sudo ./rollback.sh"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

load_state() {
  if [[ ! -f "${STATE_FILE}" ]]; then
    die "state file not found: ${STATE_FILE}. Nothing to rollback."
  fi

  # shellcheck source=/dev/null
  source "${STATE_FILE}"

  CONFIG_FILE="${CONFIG_FILE:-${DEFAULT_CONFIG_FILE}}"
  CONFIG_EXISTED="${CONFIG_EXISTED:-0}"
  BACKUP_FILE="${BACKUP_FILE:-}"
  IWD_WAS_ENABLED="${IWD_WAS_ENABLED:-0}"
  IWD_WAS_ACTIVE="${IWD_WAS_ACTIVE:-0}"
  IWD_STATE_DIR="${IWD_STATE_DIR:-${DEFAULT_IWD_STATE_DIR}}"
  if ! declare -p SSIDS >/dev/null 2>&1; then
    if [[ -n "${SSID:-}" ]]; then
      SSIDS=("${SSID}")
    else
      SSIDS=("${DEFAULT_SSIDS[@]}")
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

restart_networkmanager() {
  log "Restarting NetworkManager..."
  systemctl restart NetworkManager
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

main() {
  case "${1:-}" in
    -h|--help)
      usage
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

main "$@"
