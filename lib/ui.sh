#!/usr/bin/env bash
# ==============================================================================
#  lib/ui.sh  —  Aesthetics, Colors & UI Components
#  Catppuccin Latte palette via TrueColor ANSI escapes
# ==============================================================================

# ── Color Palette ─────────────────────────────────────────────────────────────
ROSEWATER='\e[38;2;220;138;120m'
FLAMINGO='\e[38;2;221;120;120m'
PINK='\e[38;2;234;118;203m'
MAUVE='\e[38;2;136;57;239m'
RED='\e[38;2;210;15;57m'
MAROON='\e[38;2;230;69;83m'
PEACH='\e[38;2;254;100;11m'
YELLOW='\e[38;2;223;142;29m'
GREEN='\e[38;2;64;160;43m'
TEAL='\e[38;2;23;146;153m'
SKY='\e[38;2;4;165;229m'
SAPPHIRE='\e[38;2;32;159;181m'
BLUE='\e[38;2;30;102;245m'
LAVENDER='\e[38;2;114;135;253m'
TEXT='\e[38;2;76;79;105m'
SUBTEXT='\e[38;2;92;95;119m'
NC='\e[0m'
BOLD='\e[1m'
DIM='\e[2m'

# ── Icons ─────────────────────────────────────────────────────────────────────
OK="✔"
ERR="✖"
WARN="⚠"
ARR="›"

# ── Layout ────────────────────────────────────────────────────────────────────
show_header() {
  clear
  echo
  echo -e "  ${MAUVE}${BOLD}  VPS Home Server Manager${NC}  ${DIM}${SUBTEXT}v2.1${NC}"
  echo -e "  ${SUBTEXT}────────────────────────────────────────────────${NC}"
  echo
}

show_footer() {
  echo
  echo -e "  ${DIM}${SUBTEXT}Log: ${LOG_FILE}${NC}"
  echo -e "  ${SUBTEXT}────────────────────────────────────────────────${NC}"
}

separator() { echo -e "  ${DIM}${SUBTEXT}────────────────────────────────────────────────${NC}"; }
label()     { echo -e "  ${LAVENDER}${BOLD}${1}${NC}"; }

# ── Logging ───────────────────────────────────────────────────────────────────
info()    { echo -e "  ${SKY}${ARR}${NC} ${TEXT}${1}${NC}";           echo "[INFO]    $(date '+%F %T') | ${1}" >> "$LOG_FILE"; }
success() { echo -e "  ${GREEN}${OK}${NC} ${TEXT}${1}${NC}";          echo "[SUCCESS] $(date '+%F %T') | ${1}" >> "$LOG_FILE"; }
warn()    { echo -e "  ${YELLOW}${WARN}${NC} ${TEXT}${1}${NC}";       echo "[WARN]    $(date '+%F %T') | ${1}" >> "$LOG_FILE"; }
error()   { echo -e "  ${RED}${ERR}${NC} ${TEXT}${1}${NC}" >&2;       echo "[ERROR]   $(date '+%F %T') | ${1}" >> "$LOG_FILE"; }
die()     { error "$1"; pause; exit 1; }

# ── Interaction ───────────────────────────────────────────────────────────────
prompt() {
  local msg=$1 var=$2
  printf "  ${MAUVE}?${NC} ${BOLD}${msg}${NC}: "
  read -r "$var"
}

confirm() {
  local msg=$1
  printf "  ${YELLOW}?${NC} ${BOLD}${msg}${NC} [${GREEN}y${NC}/${RED}n${NC}]: "
  read -r ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

pause() {
  echo
  echo -e "  ${GREEN}${BOLD}Finished!${NC} ${TEXT}Task completed successfully.${NC}"
  printf "  ${MAUVE}──${NC} ${BOLD}Press [Enter] for Main Menu or [0] to Exit to Terminal${NC}: "
  read -r choice
  if [[ "$choice" == "0" ]]; then
    echo -e "\n  ${SUBTEXT}Goodbye.${NC}\n"
    exit 0
  fi
  return 0
}

# ── Task Runner ───────────────────────────────────────────────────────────────
run_task() {
  local msg="$1"
  local cmd="$2"

  info "$msg..."
  echo -e "  ${DIM}┌────────────────────────────────────────────────────────┐${NC}"

  set +e
  eval "$cmd" 2>&1 | while IFS= read -r line; do
    printf "  ${DIM}│${NC} %-54s ${DIM}│${NC}\n" "${line:0:54}"
  done
  local exit_code=${PIPESTATUS[0]}
  set -e

  if [[ $exit_code -eq 0 ]]; then
    echo -e "  ${DIM}└────────────────────────────────────────────────────────┘${NC}"
    return 0
  else
    echo -e "  ${RED}└──────────────────────────────────────────── FAILED ────┘${NC}"
    return $exit_code
  fi
}
