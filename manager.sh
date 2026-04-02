#!/usr/bin/env bash
# ==============================================================================
#  VPS Home Server Manager  |  manager.sh
#  Optimized for: Ubuntu 22.04+ / Debian 12+
#  Usage: ./manager.sh [up|down|status|doctor|clean]
# ==============================================================================
set -euo pipefail

# ── Phase 0: Aesthetics (Catppuccin Latte) ───────────────────────────────────
# TrueColor: \e[38;2;R;G;Bm
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

OK="✔"
ERR="✖"
WARN="⚠"
ARR="›"

# ── Globals ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.vps_state.json"
LOG_FILE="${SCRIPT_DIR}/manager.log"
DOCKER_FILES_DIR="${SCRIPT_DIR}/docker-files"   # pre-built compose files
CONFIG_BASE="${HOME}/.config/personal-server"    # per-service configs
MEDIA_DIR="/mnt/media"                           # shared media volume
PROXY_NETWORK="proxy-nw"

# ── UI Components ─────────────────────────────────────────────────────────────
show_header() {
  clear
  echo
  echo -e "  ${MAUVE}${BOLD}  VPS Home Server Manager${NC}  ${DIM}${SUBTEXT}v2.0${NC}"
  echo -e "  ${SUBTEXT}────────────────────────────────────────────────${NC}"
  echo
}

show_footer() {
  echo
  echo -e "  ${DIM}${SUBTEXT}Log: ${LOG_FILE}${NC}"
  echo -e "  ${SUBTEXT}────────────────────────────────────────────────${NC}"
}

label()   { echo -e "  ${LAVENDER}${BOLD}${1}${NC}"; }
info()    { echo -e "  ${SKY}${ARR}${NC} ${TEXT}${1}${NC}"; echo "[INFO]    $(date '+%F %T') | ${1}" >> "$LOG_FILE"; }
success() { echo -e "  ${GREEN}${OK}${NC} ${TEXT}${1}${NC}"; echo "[SUCCESS] $(date '+%F %T') | ${1}" >> "$LOG_FILE"; }
warn()    { echo -e "  ${YELLOW}${WARN}${NC} ${TEXT}${1}${NC}"; echo "[WARN]    $(date '+%F %T') | ${1}" >> "$LOG_FILE"; }
error()   { echo -e "  ${RED}${ERR}${NC} ${TEXT}${1}${NC}" >&2; echo "[ERROR]   $(date '+%F %T') | ${1}" >> "$LOG_FILE"; }
die()     { error "$1"; exit 1; }

prompt()  {
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

pause() { echo; printf "  ${DIM}${SUBTEXT}Press Enter to continue...${NC}"; read -r; }

separator() { echo -e "  ${DIM}${SUBTEXT}────────────────────────────────────────────────${NC}"; }

# ── State Management ──────────────────────────────────────────────────────────
state_init() {
  [[ -f "$STATE_FILE" ]] || echo '{"services":{}}' > "$STATE_FILE"
}

state_get() {
  jq -r "${1} // empty" "$STATE_FILE" 2>/dev/null || true
}

state_set() {
  local key=$1 val=$2
  local tmp; tmp=$(mktemp)
  jq "${key} = \"${val}\"" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

state_set_service() {
  local name=$1 port=$2 status=$3
  local tmp; tmp=$(mktemp)
  jq --arg n "$name" --arg p "$port" --arg s "$status" \
    '.services[$n] = {port: $p, status: $s, deployed_at: (now | todate)}' \
    "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

state_remove_service() {
  local tmp; tmp=$(mktemp)
  jq --arg n "$1" 'del(.services[$n])' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# ── Phase 1: Environment Validation & User Pre-flight ─────────────────────────

validate_os() {
  [[ -f /etc/os-release ]] || die "Cannot detect OS."
  # shellcheck source=/dev/null
  source /etc/os-release
  [[ "$ID" == "ubuntu" || "$ID" == "debian" ]] \
    || die "Unsupported OS: ${ID}. This script requires Ubuntu 22.04+ or Debian 12+."
  local arch; arch=$(uname -m)
  [[ "$arch" == "x86_64" || "$arch" == "aarch64" ]] \
    || die "Unsupported architecture: ${arch}."
  success "OS: ${PRETTY_NAME} (${arch})"
}

install_deps() {
  local deps=("curl" "git" "jq" "gawk" "openssl" "ufw")
  local missing=()
  for dep in "${deps[@]}"; do
    command -v "$dep" &>/dev/null || missing+=("$dep")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    info "Installing missing dependencies: ${missing[*]}"
    sudo apt-get update -qq &>> "$LOG_FILE"
    sudo apt-get install -y "${missing[@]}" &>> "$LOG_FILE"
  fi
  success "All dependencies satisfied."
}

handle_user() {
  if [[ $EUID -eq 0 ]]; then
    warn "Running as root. A non-root sudo user is required."
    prompt "Enter deployment username" TARGET_USER

    if id "$TARGET_USER" &>/dev/null; then
      info "User '${TARGET_USER}' exists. Ensuring sudo access..."
      usermod -aG sudo "$TARGET_USER"
    else
      if confirm "User '${TARGET_USER}' not found. Create it?"; then
        adduser --gecos "" "$TARGET_USER"
        usermod -aG sudo "$TARGET_USER"
        success "User '${TARGET_USER}' created."
      else
        die "Deployment requires a non-root user. Aborting."
      fi
    fi

    local target_script="/home/${TARGET_USER}/manager.sh"
    cp "$0" "$target_script"
    chown "${TARGET_USER}:${TARGET_USER}" "$target_script"
    chmod +x "$target_script"

    info "Transitioning session to '${TARGET_USER}'..."
    exec sudo -u "$TARGET_USER" -H bash "$target_script" "${@:1}"
  fi
}

# ── Phase 2: Core Infrastructure ─────────────────────────────────────────────

install_docker() {
  if command -v docker &>/dev/null; then
    success "Docker already installed: $(docker --version | awk '{print $3}' | tr -d ',')"
    return
  fi

  info "Setting up Docker official repositories..."
  # shellcheck source=/dev/null
  source /etc/os-release
  sudo apt-get update -qq &>> "$LOG_FILE"
  sudo apt-get install -y ca-certificates curl gnupg &>> "$LOG_FILE"

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update -qq &>> "$LOG_FILE"
  sudo apt-get install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin &>> "$LOG_FILE"

  sudo systemctl enable --now docker &>> "$LOG_FILE"
  sudo usermod -aG docker "$USER"
  success "Docker Engine V2 installed."
  state_set ".docker_installed" "true"
}

setup_network() {
  if docker network inspect "$PROXY_NETWORK" &>/dev/null; then
    success "Docker network '${PROXY_NETWORK}' already exists."
  else
    info "Creating isolated Docker network '${PROXY_NETWORK}'..."
    docker network create "$PROXY_NETWORK" &>> "$LOG_FILE"
    success "Network '${PROXY_NETWORK}' created."
  fi
}

setup_firewall() {
  local ssh_port
  ssh_port=$(ss -tlnp | awk '/sshd/{print $4}' | grep -oP ':\K[0-9]+' | head -1)
  ssh_port=${ssh_port:-22}

  info "Configuring UFW firewall (SSH: ${ssh_port}, HTTP: 80, HTTPS: 443)..."
  sudo ufw allow "$ssh_port"/tcp &>> "$LOG_FILE"
  sudo ufw allow 80/tcp  &>> "$LOG_FILE"
  sudo ufw allow 443/tcp &>> "$LOG_FILE"
  sudo ufw --force enable &>> "$LOG_FILE"
  success "Firewall configured."
}

deploy_reverse_proxy() {
  if [[ "$(state_get '.proxy_deployed')" == "true" ]]; then
    success "Nginx Proxy Manager already deployed."
    return
  fi

  local custom_df="${DOCKER_FILES_DIR}/nginx-proxy-manager-dockerfile"
  local cfg_dir="${CONFIG_BASE}/nginx-proxy-manager"
  mkdir -p "${cfg_dir}/data" "${cfg_dir}/letsencrypt"

  local active_image="jc21/nginx-proxy-manager:latest"
  if [[ -f "$custom_df" ]]; then
    info "Prioritizing custom Dockerfile for Nginx Proxy Manager..."
    docker build -t "local-nginx-proxy-manager:latest" -f "$custom_df" "$DOCKER_FILES_DIR" &>> "$LOG_FILE"
    active_image="local-nginx-proxy-manager:latest"
  else
    info "Pulling generic image for Nginx Proxy Manager..."
    docker pull "$active_image" &>> "$LOG_FILE" || true
  fi

  info "Deploying Nginx Proxy Manager (Entry Gate)..."
  docker run -d \
    --name nginx-proxy-manager \
    --restart unless-stopped \
    --network "$PROXY_NETWORK" \
    -p 80:80 \
    -p 81:81 \
    -p 443:443 \
    -v "${cfg_dir}/data:/data" \
    -v "${cfg_dir}/letsencrypt:/etc/letsencrypt" \
    -v "${MEDIA_DIR}:${MEDIA_DIR}" \
    "$active_image" &>> "$LOG_FILE"

  state_set ".proxy_deployed" "true"
  success "Nginx Proxy Manager running on port 81 (admin UI)."
  warn "Default login: admin@example.com / changeme  — change it immediately!"
}

setup_media_dir() {
  if [[ -d "$MEDIA_DIR" ]]; then
    success "Media directory '${MEDIA_DIR}' already exists."
  else
    info "Creating shared media directory at ${MEDIA_DIR}..."
    sudo mkdir -p "$MEDIA_DIR"
    sudo chown "${USER}:${USER}" "$MEDIA_DIR"
    sudo chmod 775 "$MEDIA_DIR"
    success "Media directory created: ${MEDIA_DIR}"
  fi
  # Sub-directories used by media services
  mkdir -p "${MEDIA_DIR}/movies" "${MEDIA_DIR}/tv" "${MEDIA_DIR}/music" \
           "${MEDIA_DIR}/books" "${MEDIA_DIR}/downloads"
  success "Media sub-dirs ready: movies/ tv/ music/ books/ downloads/"
}

cmd_initialize() {
  show_header
  label "Phase 1: Environment Validation"
  validate_os
  install_deps
  separator

  label "Phase 2: Core Infrastructure"
  install_docker
  setup_network
  setup_firewall
  setup_media_dir
  deploy_reverse_proxy
  separator

  success "VPS is fully initialized and ready!"
  state_set ".initialized" "true"
  pause
}

# ── Phase 3 & 4: Service Catalog ──────────────────────────────────────────────

# Service definitions: name|image|port|data_dir|extra_env|extra_ports|extra_volumes|extra_args
declare -A SERVICES
SERVICES=(
  # Tier 1: Management
  [homarr]="ghcr.io/homarr-labs/homarr:latest|7575|homarr|SECRET_ENCRYPTION_KEY=1097939ab64487e6072404d50abf337500adc4bf838c628dc0f60612daef3006||/var/run/docker.sock:/var/run/docker.sock|"
  [portainer]="portainer/portainer-ce:latest|9000|portainer||8000:8000|/var/run/docker.sock:/var/run/docker.sock|"

  # Tier 2: Personal Cloud
  [filebrowser]="filebrowser/filebrowser:s6|8080|filebrowser|PUID=1000,PGID=1000,TZ=Africa/Tunis|8080:80||"
  [nextcloud]="lscr.io/linuxserver/nextcloud:latest|8090|nextcloud|PUID=1000,PGID=1000,TZ=Africa/Tunis|8090:443||"

  # Tier 3: Media
  [jellyfin]="lscr.io/linuxserver/jellyfin:latest|8096|jellyfin|PUID=1000,PGID=1000,TZ=Africa/Tunis|8920:8920,7359:7359/udp,1900:1900/udp||"
  [prowlarr]="lscr.io/linuxserver/prowlarr:latest|9696|prowlarr|PUID=1000,PGID=1000,TZ=Africa/Tunis|||"

  # Tier 4: Security Lab
  [kali-lab]="lscr.io/linuxserver/kali-linux:latest|3000|kali-lab|PIXELFLUX_WAYLAND=true,DRINODE=/dev/dri/renderD128,DRI_NODE=/dev/dri/renderD128,PUID=1000,PGID=1000,TZ=Africa/Tunis|||--gpus all --device /dev/dri/renderD128:/dev/dri/renderD128 --shm-size 2gb"

  # Tier 5: GPU Accelerated Cloud
  [brave]="lscr.io/linuxserver/brave:latest|3000|brave|PIXELFLUX_WAYLAND=true,DRINODE=/dev/dri/renderD128,DRI_NODE=/dev/dri/renderD128,PUID=1000,PGID=1000,TZ=Africa/Tunis|||--gpus all --device /dev/dri/renderD128:/dev/dri/renderD128 --shm-size 2gb"
)

SERVICE_DESCRIPTIONS=(
  [homarr]="Tier 1 · Lightweight home dashboard"
  [portainer]="Tier 1 · Docker container visualizer"
  [filebrowser]="Tier 2 · Personal cloud file manager"
  [nextcloud]="Tier 2 · Full personal cloud suite"
  [jellyfin]="Tier 3 · Media streaming server (Alpine)"
  [prowlarr]="Tier 3 · Indexer manager for media"
  [kali-lab]="Tier 4 · Security lab with browser VNC"
  [brave]="Tier 5 · GPU-accelerated Brave Browser"
)

# Service requirements: RAM (MB) | Disk (MB)
SERVICE_REQUIREMENTS=(
  [homarr]="150|500"
  [portainer]="100|500"
  [filebrowser]="50|200"
  [nextcloud]="512|2000"
  [jellyfin]="768|2000"
  [prowlarr]="256|500"
  [kali-lab]="2048|5000"
  [brave]="1024|2000"
)

check_resources() {
  local required_ram=$1
  local required_disk=$2
  
  local free_ram; free_ram=$(free -m | awk '/^Mem:/{print $7}')
  local free_disk; free_disk=$(df -m / | awk 'NR==2{print $4}')

  local ok=true
  if (( free_ram < required_ram )); then
    error "Insufficient RAM! Required: ${required_ram}MB, Available: ${free_ram}MB"
    ok=false
  fi
  if (( free_disk < required_disk )); then
    error "Insufficient Disk Space! Required: ${required_disk}MB, Available: ${free_disk}MB"
    ok=false
  fi
  
  [[ "$ok" == true ]] || return 1
}

is_port_free() {
  ! ss -tlnp | grep -q ":${1} "
}

deploy_service() {
  local name=$1
  local def="${SERVICES[$name]}"
  IFS='|' read -r image default_port _unused extra_env extra_ports extra_volumes extra_args <<< "$def"

  local cfg_dir="${CONFIG_BASE}/${name}"
  local custom_df="${DOCKER_FILES_DIR}/${name}-dockerfile"
  local reqs="${SERVICE_REQUIREMENTS[$name]:-256|1000}"

  # Pre-Flight Resource Check
  if ! check_resources "${reqs%%|*}" "${reqs##*|}"; then
    warn "Deployment aborted due to lack of VPS resources."
    return 1
  fi

  # Check if already deployed
  if [[ "$(state_get ".services.${name}.status")" == "running" ]]; then
    if confirm "'${name}' is already deployed. Redeploy?"; then
      docker rm -f "$name" &>> "$LOG_FILE" || true
    else
      return
    fi
  fi

  # Port selection
  local port=$default_port
  if ! is_port_free "$port"; then
    warn "Port ${port} is in use."
    prompt "Enter an alternative port for ${name}" port
  fi

  # Create service config dir
  mkdir -p "$cfg_dir"

  local active_image="$image"
  if [[ -f "$custom_df" ]]; then
    info "Prioritizing custom Dockerfile for ${name}..."
    docker build -t "local-${name}:latest" -f "$custom_df" "$DOCKER_FILES_DIR" &>> "$LOG_FILE"
    active_image="local-${name}:latest"
  else
    info "Pulling generic image for ${name}..."
    docker pull "$active_image" &>> "$LOG_FILE" || true
  fi

  info "Starting ${name} container..."
  
  local run_cmd=(docker run -d --name "$name" --restart unless-stopped)
  run_cmd+=(--network "$PROXY_NETWORK")
  run_cmd+=(-p "${port}:${default_port}")
  
  if [[ -n "$extra_args" ]]; then
    read -ra args_arr <<< "$extra_args"
    run_cmd+=("${args_arr[@]}")
  fi
  
  if [[ -n "$extra_ports" ]]; then
    IFS=',' read -ra port_arr <<< "$extra_ports"
    for ep in "${port_arr[@]}"; do
      run_cmd+=(-p "$ep")
    done
  fi

  # Map standard config directory securely
  run_cmd+=(-v "${cfg_dir}:/config")
  
  # Mount the central media directory universally at its absolute path
  run_cmd+=(-v "${MEDIA_DIR}:${MEDIA_DIR}")

  # Parse and mount any application-specific requested volumes safely
  if [[ -n "$extra_volumes" ]]; then
    IFS=',' read -ra vol_arr <<< "$extra_volumes"
    for ev in "${vol_arr[@]}"; do
      local parsed_vol="${ev//CFG_DIR/$cfg_dir}"
      run_cmd+=(-v "$parsed_vol")
    done
  fi

  if [[ -n "$extra_env" ]]; then
    IFS=',' read -ra env_arr <<< "$extra_env"
    for e in "${env_arr[@]}"; do
      run_cmd+=(-e "$e")
    done
  fi

  run_cmd+=("$active_image")

  "${run_cmd[@]}" &>> "$LOG_FILE"

  state_set_service "$name" "$port" "running"
  success "${name} deployed on port ${port}.  Config: ${cfg_dir}"

  if [[ "$name" == "kali-lab" ]]; then
    warn "Kali Lab is RAM-intensive. Run './manager.sh down kali-lab' to free resources."
  fi
}

cmd_up() {
  show_header
  label "Service Catalog & Smart Deployment"
  echo

  local free_ram; free_ram=$(free -m | awk '/^Mem:/{print $7}')
  local i=1
  declare -a menu_keys
  
  for key in "${!SERVICES[@]}"; do
    menu_keys+=("$key")
    local desc="${SERVICE_DESCRIPTIONS[$key]:-}"
    local reqs="${SERVICE_REQUIREMENTS[$key]:-256|1000}"
    local req_ram="${reqs%%|*}"
    
    local tag=""
    local tag_color=$NC
    
    if [[ "$(state_get ".services.${key}.status")" == "running" ]]; then
      tag="[RUNNING]"
      tag_color=$GREEN
    elif (( free_ram < req_ram )); then
      tag="[OUT OF RAM]"
      tag_color=$RED
    fi
    
    printf "  ${MAUVE}%2d)${NC} ${BOLD}%-15s${NC} ${DIM}${SUBTEXT}%-40s${NC} ${tag_color}%s${NC}\n" "$i" "$key" "$desc" "$tag"
    (( i++ ))
  done

  echo
  separator
  prompt "Select service number (or 0 to cancel)" choice

  if [[ "$choice" == "0" || -z "$choice" ]]; then return; fi

  local idx=$(( choice - 1 ))
  local selected="${menu_keys[$idx]:-}"
  [[ -n "$selected" ]] || { error "Invalid selection."; pause; return; }

  separator
  info "Deploying: ${selected}"
  deploy_service "$selected"
  pause
}

cmd_down() {
  local target=${1:-}
  if [[ -z "$target" ]]; then
    show_header
    label "Remove a Service"
    echo
    docker ps --format "  ${MAROON}›${NC} {{.Names}}  ${DIM}({{.Image}})${NC}" 2>/dev/null || true
    echo
    prompt "Container name to stop & remove" target
  fi

  [[ -z "$target" ]] && return

  if confirm "Stop and remove '${target}'?"; then
    docker rm -f "$target" &>> "$LOG_FILE" || true
    state_remove_service "$target"
    success "'${target}' removed."
  fi
  pause
}

# ── Phase 5: Maintenance & Monitoring ─────────────────────────────────────────

cmd_status() {
  show_header
  label "Health Dashboard"
  echo

  # Container table
  printf "  ${BOLD}${SUBTEXT}%-20s %-12s %-8s %s${NC}\n" "CONTAINER" "STATUS" "PORT" "IMAGE"
  separator
  docker ps --format '{{.Names}}|{{.Status}}|{{.Ports}}|{{.Image}}' 2>/dev/null \
  | while IFS='|' read -r name status ports image; do
      local col=$GREEN
      [[ "$status" != Up* ]] && col=$RED
      image_short="${image##*/}"
      port_short=$(echo "$ports" | grep -oP ':\K[0-9]+(?=->)' | head -1)
      printf "  ${col}%-20s${NC} %-12s ${TEAL}%-8s${NC} ${DIM}%s${NC}\n" \
        "$name" "$(echo "$status" | cut -c1-12)" ":${port_short}" "$image_short"
    done

  separator
  # System resource summary
  local total used free
  total=$(free -m | awk '/^Mem:/{print $2}')
  used=$(free -m  | awk '/^Mem:/{print $3}')
  free=$(free -m  | awk '/^Mem:/{print $7}')
  echo
  printf "  ${SAPPHIRE}RAM${NC}  total: ${BOLD}%sMB${NC}  used: ${YELLOW}%sMB${NC}  free: ${GREEN}%sMB${NC}\n" \
    "$total" "$used" "$free"

  local disk_used disk_free
  disk_used=$(df -h / | awk 'NR==2{print $3}')
  disk_free=$(df -h / | awk 'NR==2{print $4}')
  printf "  ${SAPPHIRE}DISK${NC} used: ${YELLOW}%s${NC}  free: ${GREEN}%s${NC}\n" "$disk_used" "$disk_free"

  show_footer
  pause
}

cmd_doctor() {
  show_header
  label "System Doctor  —  Security & Health Audit"
  echo

  # 1. Docker daemon
  if systemctl is-active --quiet docker; then
    success "Docker daemon is running."
  else
    error "Docker daemon is NOT running."
  fi

  # 2. Restarting containers
  local restarts
  restarts=$(docker ps --filter "status=restarting" --format "{{.Names}}" 2>/dev/null)
  if [[ -n "$restarts" ]]; then
    warn "Containers in restart loop: ${restarts}"
  else
    success "No containers are in a restart loop."
  fi

  # 3. High memory containers (>80% of system RAM)
  local threshold=$(( $(free -m | awk '/^Mem:/{print $2}') * 80 / 100 ))
  docker stats --no-stream --format "{{.Name}} {{.MemUsage}}" 2>/dev/null \
  | while read -r cname mem_info; do
      local mem_mb; mem_mb=$(echo "$mem_info" | grep -oP '^[\d.]+' | awk '{printf "%d", $1}')
      (( mem_mb > threshold )) && warn "${cname} is using high memory: ${mem_info}"
    done

  # 4. UFW status
  if sudo ufw status | grep -q "Status: active"; then
    success "UFW firewall is active."
  else
    warn "UFW firewall is NOT active."
  fi

  # 5. Fail2Ban
  if command -v fail2ban-client &>/dev/null && systemctl is-active --quiet fail2ban; then
    success "Fail2Ban is active."
  else
    warn "Fail2Ban not detected. Consider installing it for brute-force protection."
    if confirm "Install Fail2Ban now?"; then
      sudo apt-get install -y fail2ban &>> "$LOG_FILE"
      sudo systemctl enable --now fail2ban &>> "$LOG_FILE"
      success "Fail2Ban installed and enabled."
    fi
  fi

  # 6. SSL cert expiry (Nginx PM Let's Encrypt)
  local cert_dir="/etc/letsencrypt/live"
  if [[ -d "$cert_dir" ]]; then
    for cert in "${cert_dir}"/*/fullchain.pem; do
      local expiry days
      expiry=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
      days=$(( ( $(date -d "$expiry" +%s) - $(date +%s) ) / 86400 ))
      if (( days < 14 )); then
        warn "SSL cert expires in ${days} days: ${cert}"
      else
        success "SSL cert OK (${days} days left): $(basename "$(dirname "$cert")")"
      fi
    done
  fi

  # 7. Optional: strip sudo from deploy user
  separator
  if confirm "Lock down this account (remove sudo privileges)?"; then
    warn "Removing ${USER} from sudo group..."
    sudo deluser "$USER" sudo &>> "$LOG_FILE"
    warn "Sudo removed. Re-login required to take effect. Save root access elsewhere!"
  fi

  show_footer
  pause
}

cmd_purge() {
  show_header
  label "NUCLEAR PURGE  —  Destroy Setup"
  echo

  warn "WARNING: This will DESTROY all deployed containers, delete all configurations"
  warn "in ${CONFIG_BASE}, remove the docker network, and erase the script state!"
  echo

  if confirm "Are you ABSOLUTELY sure you want to PURGE EVERYTHING?"; then
    info "Stopping and removing managed containers..."
    docker rm -f nginx-proxy-manager &>> "$LOG_FILE" || true
    for srv in "${!SERVICES[@]}"; do
      docker rm -f "$srv" &>> "$LOG_FILE" || true
    done

    info "Removing Docker network (${PROXY_NETWORK})..."
    docker network rm "$PROXY_NETWORK" &>> "$LOG_FILE" || true

    if confirm "Delete ALL configurations? (Removes ${CONFIG_BASE})"; then
      rm -rf "$CONFIG_BASE"
      success "Configuration directory removed."
    fi

    if confirm "Delete ALL media? (Removes ${MEDIA_DIR})"; then
      sudo rm -rf "$MEDIA_DIR"
      success "Media directory destroyed."
    fi

    info "Resetting script state..."
    rm -f "$STATE_FILE"
    
    success "System successfully purged. You can now start fresh."
  else
    warn "Purge aborted."
  fi
  pause
}

cmd_clean() {
  show_header
  label "Prune Unused Docker Assets"
  echo

  # Show what will be removed
  docker system df 2>/dev/null || true
  separator

  if confirm "Remove unused images and stopped containers? (volumes are PRESERVED unless confirmed)"; then
    docker image prune -af &>> "$LOG_FILE"
    docker container prune -f &>> "$LOG_FILE"
    success "Images and stopped containers pruned."

    if confirm "Also remove orphaned volumes? (WARNING: potential data loss)"; then
      docker volume prune -f &>> "$LOG_FILE"
      success "Orphaned volumes removed."
    else
      warn "Volumes skipped — data is safe."
    fi
  fi

  show_footer
  pause
}

# ── Interactive Main Menu ──────────────────────────────────────────────────────

main_menu() {
  while true; do
    show_header
    label "Main Menu"
    echo
    printf "  ${MAUVE}1)${NC} ${BOLD}Initialize VPS${NC}          ${DIM}${SUBTEXT}Docker + Network + Proxy + Firewall${NC}\n"
    printf "  ${BLUE}2)${NC} ${BOLD}Deploy a Service${NC}         ${DIM}${SUBTEXT}App store (up)${NC}\n"
    printf "  ${TEAL}3)${NC} ${BOLD}Remove a Service${NC}         ${DIM}${SUBTEXT}Stop & clean (down)${NC}\n"
    printf "  ${GREEN}4)${NC} ${BOLD}Health Dashboard${NC}         ${DIM}${SUBTEXT}Status + resources${NC}\n"
    printf "  ${SAPPHIRE}5)${NC} ${BOLD}System Doctor${NC}            ${DIM}${SUBTEXT}Audit + security${NC}\n"
    printf "  ${YELLOW}6)${NC} ${BOLD}Prune & Clean${NC}            ${DIM}${SUBTEXT}Free up disk${NC}\n"
    printf "  ${MAROON}7)${NC} ${BOLD}Nuclear Purge${NC}            ${DIM}${SUBTEXT}Destroy & reset setup${NC}\n"
    printf "  ${RED}0)${NC} Exit\n"
    echo
    prompt "Select" CHOICE

    case "${CHOICE:-}" in
      1) cmd_initialize ;;
      2) cmd_up        ;;
      3) cmd_down      ;;
      4) cmd_status    ;;
      5) cmd_doctor    ;;
      6) cmd_clean     ;;
      7) cmd_purge     ;;
      0) echo -e "\n  ${SUBTEXT}Goodbye.${NC}\n"; exit 0 ;;
      *) error "Invalid option."; sleep 1 ;;
    esac
  done
}

# ── CLI Entrypoint ─────────────────────────────────────────────────────────────

# Init log & state
touch "$LOG_FILE"
state_init

# Phase 1: User & OS pre-flight (skip if already child process)
if [[ "${1:-}" != "--child" ]]; then
  handle_user "$@"
fi

# CLI mode or interactive menu
case "${1:-}" in
  up)     cmd_up      ;;
  down)   cmd_down "${2:-}" ;;
  status) cmd_status  ;;
  doctor) cmd_doctor  ;;
  clean)  cmd_clean   ;;
  purge)  cmd_purge   ;;
  init)   cmd_initialize ;;
  --child|"") main_menu ;;
  *)
    echo -e "\n  ${BOLD}Usage:${NC} ./manager.sh [command]\n"
    echo -e "  Commands: up | down <name> | status | doctor | clean | purge | init"
    echo
    exit 1
    ;;
esac
