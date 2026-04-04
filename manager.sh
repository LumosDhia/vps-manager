#!/usr/bin/env bash
# ==============================================================================
#  VPS Home Server Manager  |  manager.sh  (entry point)
#  Optimized for: Ubuntu 22.04+ / Debian 12+
#  Usage: ./manager.sh [init|up|down|status|doctor|clean|purge|proxy]
#
#  Modules:
#    lib/ui.sh       — Colors, print helpers, run_task
#    lib/state.sh    — JSON state management
#    lib/infra.sh    — Docker, network, firewall, media, reverse proxy
#    lib/services.sh — Service catalog & deployment engine
#    lib/commands.sh — Interactive menu commands
# ==============================================================================
set -euo pipefail

# ── Globals ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.vps_state.json"
LOG_FILE="${SCRIPT_DIR}/manager.log"
DOCKER_FILES_DIR="${SCRIPT_DIR}/docker-files"
CONFIG_BASE="${HOME}/.config/personal-server"
MEDIA_DIR="/mnt/media"
PROXY_NETWORK="proxy-nw"

# ── Load Modules ──────────────────────────────────────────────────────────────
LIB_DIR="${SCRIPT_DIR}/lib"
for module in ui state infra services commands; do
  # shellcheck source=/dev/null
  source "${LIB_DIR}/${module}.sh"
done

# ── Bootstrap ─────────────────────────────────────────────────────────────────
touch "$LOG_FILE"
state_init

# Pre-flight user check (skip when re-invoked as child)
if [[ "${1:-}" != "--child" ]]; then
  handle_user "$@"
fi

# ── CLI Dispatch ──────────────────────────────────────────────────────────────
case "${1:-}" in
  init)   cmd_initialize; main_menu ;;
  up)     cmd_up;         main_menu ;;
  down)   cmd_down "${2:-}"; main_menu ;;
  status) cmd_status;     main_menu ;;
  doctor) cmd_doctor;     main_menu ;;
  clean)  cmd_clean;      main_menu ;;
  purge)  cmd_purge;      main_menu ;;
  proxy)  cmd_proxy;      main_menu ;;
  --child|"") main_menu ;;
  *)
    echo -e "\n  ${BOLD}Usage:${NC} ./manager.sh [command]\n"
    echo -e "  Commands: init | up | down <name> | status | doctor | clean | purge | proxy"
    echo
    exit 1
    ;;
esac
