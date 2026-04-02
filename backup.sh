#!/usr/bin/env bash
# ==============================================================================
#  VPS Backup & Restore Utility  |  backup.sh
#  Purpose: Configuration Snapshots & Full System Backups (Timeshift Style)
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
warn()    { echo -e "  ${YELLOW}⚠${NC} ${1}"; }
die()     { error "$1"; exit 1; }

# ── Actions ───────────────────────────────────────────────────────────────────

cmd_config_backup() {
  local timestamp; timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_name="config_snapshot_${timestamp}.tar.gz"
  local target_path="${BACKUP_DIR}/${backup_name}"

  info "Creating config-only snapshot..."
  
  if [[ ! -f "$STATE_FILE" ]] && [[ ! -d "$CONFIG_BASE" ]]; then
    die "Nothing to backup! No state file or config directory found."
  fi

  tar -czf "$target_path" \
      -C "$SCRIPT_DIR" ".vps_state.json" \
      -C "$HOME" ".config/personal-server" \
      2>/dev/null || true

  success "${BOLD}Config backup created:${NC} ${backup_name}"
}

cmd_system_backup() {
  local timestamp; timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_name="system_full_${timestamp}.tar.gz"
  local target_path="${BACKUP_DIR}/${backup_name}"
  
  info "Preparing FULL SYSTEM snapshot (Timeshift style)..."
  warn "This will capture the entire OS root (excluding media/tmp)."
  
  # Get sudo early
  sudo -v

  local exclude_file; exclude_file=$(mktemp)
  cat > "$exclude_file" <<EOF
/proc/*
/sys/*
/dev/*
/run/*
/tmp/*
/var/tmp/*
/var/lib/docker/containers/*
/var/lib/docker/overlay2/*
/mnt/*
/media/*
${BACKUP_DIR}/*
/swapfile
/lost+found
EOF

  info "Starting compression... this may take a few minutes."
  sudo tar -czpf "$target_path" --exclude-from="$exclude_file" / 2>/dev/null || true
  
  rm -f "$exclude_file"
  success "${BOLD}Full system backup created:${NC} ${backup_name}"
}

cmd_restore() {
  local backups; backups=($(ls -t "${BACKUP_DIR}"/*.tar.gz 2>/dev/null || true))
  
  if [[ ${#backups[@]} -eq 0 ]]; then
    die "No backups found in ${BACKUP_DIR}"
  fi

  echo
  echo -e "  ${MAUVE}${BOLD}Available Snapshots:${NC}"
  echo -e "  ${SUBTEXT}─────────────────────────────────${NC}"
  
  local i=1
  for b in "${backups[@]}"; do
    local label="[Config]"
    [[ "$(basename "$b")" == system_* ]] && label="[SYSTEM]"
    printf "  ${MAUVE}%2d)${NC} %-10s %s\n" "$i" "$label" "$(basename "$b")"
    ((i++))
  done
  echo

  printf "  ${MAUVE}?${NC} ${BOLD}Select snapshot to RESTORE (or 0 to cancel)${NC}: "
  read -r choice

  if [[ "$choice" == "0" || -z "$choice" ]]; then return; fi
  
  local idx=$((choice - 1))
  local selected="${backups[$idx]:-}"
  
  [[ -n "$selected" ]] || die "Invalid selection."

  warn "This will overwrite your current environment with data from $(basename "$selected")"
  printf "  ${YELLOW}?${NC} ${BOLD}Proceed with rollback?${NC} [y/n]: "
  read -r ans
  [[ "$ans" =~ ^[Yy]$ ]] || die "Restore aborted."

  if [[ "$(basename "$selected")" == system_* ]]; then
    info "Initiating FULL SYSTEM restore..."
    warn "This is a major operation. Ensure you are connected via SSH."
    sudo tar -xzpf "$selected" -C /
    success "System restoration complete. Rebooting is recommended."
  else
    info "Restoring configuration state..."
    docker stop $(docker ps -q) &>/dev/null || true
    rm -f "$STATE_FILE"
    rm -rf "$CONFIG_BASE"
    tar -xzf "$selected" -C "$SCRIPT_DIR" ".vps_state.json"
    mkdir -p "$CONFIG_BASE"
    tar -xzf "$selected" -C "$HOME" ".config/personal-server"
    success "Config state restored."
  fi
}

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
  echo -e "  ${MAUVE}1)${NC} ${BOLD}Config Snapshot${NC}     ${DIM}(Fast, apps only)${NC}"
  echo -e "  ${MAUVE}2)${NC} ${BOLD}Full System Backup${NC}  ${DIM}(Timeshift style)${NC}"
  echo -e "  ${MAUVE}3)${NC} ${BOLD}Rollback / Restore${NC}"
  echo -e "  ${MAUVE}0)${NC} Exit"
  echo
  printf "  ${MAUVE}?${NC} ${BOLD}Selection${NC}: "
  read -r CHOICE

  case "${CHOICE:-}" in
    1) cmd_config_backup ;;
    2) cmd_system_backup ;;
    3) cmd_restore ;;
    0) exit 0 ;;
    *) error "Invalid option." ; sleep 1; main ;;
  esac
}

# CLI support
case "${1:-}" in
  config) cmd_config_backup ;;
  system) cmd_system_backup ;;
  restore) cmd_restore ;;
  *)       main ;;
esac
