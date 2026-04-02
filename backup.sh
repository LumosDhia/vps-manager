#!/usr/bin/env bash
# ==============================================================================
#  VPS Backup & Restore Utility  |  backup.sh
#  Purpose: Snapshot and Rollback server configurations and state
# ==============================================================================
set -euo pipefail

# ── Aesthetics ────────────────────────────────────────────────────────────────
MAUVE='\e[38;2;136;57;239m'
RED='\e[38;2;210;15;57m'
GREEN='\e[38;2;64;160;43m'
SKY='\e[38;2;4;165;229m'
YELLOW='\e[38;2;223;142;29m'
SUBTEXT='\e[38;2;92;95;119m'
NC='\e[0m'
BOLD='\e[1m'
DIM='\e[2m'

# ── Configuration ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.vps_state.json"
CONFIG_BASE="${HOME}/.config/personal-server"
BACKUP_DIR="${SCRIPT_DIR}/backups"

mkdir -p "$BACKUP_DIR"

# ── UI Helpers ────────────────────────────────────────────────────────────────
info()    { echo -e "  ${SKY}›${NC} ${1}"; }
success() { echo -e "  ${GREEN}✔${NC} ${1}"; }
error()   { echo -e "  ${RED}✖${NC} ${1}" >&2; }
die()     { error "$1"; exit 1; }

# ── Actions ───────────────────────────────────────────────────────────────────

cmd_backup() {
  local timestamp; timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_name="vps_snapshot_${timestamp}.tar.gz"
  local target_path="${BACKUP_DIR}/${backup_name}"

  info "Creating system snapshot..."
  
  if [[ ! -f "$STATE_FILE" ]] && [[ ! -d "$CONFIG_BASE" ]]; then
    die "Nothing to backup! No state file or config directory found."
  fi

  # Stop any running docker operations to ensure config consistency (optional but safer)
  # info "Note: This captures the current files on disk."

  tar -czf "$target_path" \
      -C "$SCRIPT_DIR" ".vps_state.json" \
      -C "$HOME" ".config/personal-server" \
      2>/dev/null || true

  success "${BOLD}Backup created:${NC} ${backup_name}"
  info "Saved to: ${target_path}"
}

cmd_restore() {
  local backups; backups=($(ls -t "${BACKUP_DIR}"/*.tar.gz 2>/dev/null || true))
  
  if [[ ${#backups[@]} -eq 0 ]]; then
    die "No backups found in ${BACKUP_DIR}"
  fi

  echo
  echo -e "  ${MAUVE}${BOLD}Available Backups (Newest First):${NC}"
  echo -e "  ${SUBTEXT}─────────────────────────────────${NC}"
  
  local i=1
  for b in "${backups[@]}"; do
    printf "  ${MAUVE}%2d)${NC} %s\n" "$i" "$(basename "$b")"
    ((i++))
  done
  echo

  printf "  ${MAUVE}?${NC} ${BOLD}Select backup to RESTORE (or 0 to cancel)${NC}: "
  read -r choice

  if [[ "$choice" == "0" || -z "$choice" ]]; then return; fi
  
  local idx=$((choice - 1))
  local selected="${backups[$idx]:-}"
  
  [[ -n "$selected" ]] || die "Invalid selection."

  echo -e "  ${RED}${BOLD}WARNING:${NC} This will overwrite current configs and rollback status!"
  printf "  ${YELLOW}?${NC} ${BOLD}Proceed with rollback?${NC} [y/n]: "
  read -r ans
  [[ "$ans" =~ ^[Yy]$ ]] || die "Restore aborted."

  info "Stopping all containers before restore..."
  docker stop $(docker ps -q) &>/dev/null || true

  info "Extracting snapshot..."
  # Clean current state to avoid conflicts
  rm -f "$STATE_FILE"
  rm -rf "$CONFIG_BASE"

  # Extract configs and state
  tar -xzf "$selected" -C "$SCRIPT_DIR" ".vps_state.json"
  mkdir -p "$CONFIG_BASE"
  tar -xzf "$selected" -C "$HOME" ".config/personal-server"

  success "${BOLD}Rollback successful!${NC}"
  info "System state restored to: $(basename "$selected")"
  echo
  warn "Run './manager.sh status' to check which services to restart."
}

warn() { echo -e "  ${YELLOW}⚠${NC} ${1}"; }

# ── Main Menu ─────────────────────────────────────────────────────────────────

show_header() {
  clear
  echo
  echo -e "  ${MAUVE}${BOLD}VPS Snapshot & Rollback Utility${NC}"
  echo -e "  ${SUBTEXT}─────────────────────────────────${NC}"
  echo
}

main() {
  show_header
  echo -e "  ${MAUVE}1)${NC} ${BOLD}Create Snapshot${NC}   ${DIM}(Backup)${NC}"
  echo -e "  ${MAUVE}2)${NC} ${BOLD}Rollback State${NC}    ${DIM}(Restore)${NC}"
  echo -e "  ${MAUVE}0)${NC} Exit"
  echo
  printf "  ${MAUVE}?${NC} ${BOLD}Selection${NC}: "
  read -r CHOICE

  case "${CHOICE:-}" in
    1) cmd_backup ;;
    2) cmd_restore ;;
    0) exit 0 ;;
    *) error "Invalid option." ; sleep 1; main ;;
  esac
}

# CLI support
case "${1:-}" in
  backup)  cmd_backup ;;
  restore) cmd_restore ;;
  *)       main ;;
esac
