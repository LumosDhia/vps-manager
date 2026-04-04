#!/usr/bin/env bash
# ==============================================================================
#  lib/services.sh  —  Service Catalog & Deployment Engine
#  Add new services here. Format: image|port|dir|env|extra_ports|extra_volumes|extra_args
# ==============================================================================

# ── Service Catalog ───────────────────────────────────────────────────────────
# Fields: image | default_port | config_dir | extra_env | extra_ports | extra_volumes | extra_args
# extra_env:     comma-separated KEY=VALUE pairs
# extra_ports:   comma-separated HOST:CONTAINER pairs
# extra_volumes: comma-separated HOST:CONTAINER pairs (use CFG_DIR as placeholder)
# extra_args:    raw docker run flags (e.g. --gpus all)

declare -A SERVICES
SERVICES=(
  # ── Tier 1: Management ────────────────────────────────────────────────────
  [homarr]="ghcr.io/homarr-labs/homarr:latest|7575|homarr|SECRET_ENCRYPTION_KEY=1097939ab64487e6072404d50abf337500adc4bf838c628dc0f60612daef3006||/var/run/docker.sock:/var/run/docker.sock|"
  [portainer]="portainer/portainer-ce:latest|9000|portainer|||/var/run/docker.sock:/var/run/docker.sock|"

  # ── Tier 2: Personal Cloud ────────────────────────────────────────────────
  [filebrowser]="filebrowser/filebrowser:s6|8080|filebrowser|PUID=1000,PGID=1000,TZ=Africa/Tunis|:80|${MEDIA_DIR}:/srv|"
  [nextcloud]="lscr.io/linuxserver/nextcloud:latest|8090|nextcloud|PUID=1000,PGID=1000,TZ=Africa/Tunis|:443||"

  # ── Tier 3: Media ─────────────────────────────────────────────────────────
  [jellyfin]="lscr.io/linuxserver/jellyfin:latest|8096|jellyfin|PUID=1000,PGID=1000,TZ=Africa/Tunis|||"
  [prowlarr]="lscr.io/linuxserver/prowlarr:latest|9696|prowlarr|PUID=1000,PGID=1000,TZ=Africa/Tunis|||"
  [qbittorrent]="lscr.io/linuxserver/qbittorrent:latest|8080|qbittorrent|PUID=1000,PGID=1000,TZ=Africa/Tunis,WEBUI_PORT=8080||${MEDIA_DIR}/downloads:/downloads|"
  [navidrome]="deluan/navidrome:latest|4533|navidrome|PUID=1000,PGID=1000,TZ=Africa/Tunis||${MEDIA_DIR}/music:/music|"
  [kavita]="kavitareader/kavita:latest|5000|kavita|PUID=1000,PGID=1000,TZ=Africa/Tunis||${MEDIA_DIR}:/media|"
)

declare -A SERVICE_DESCRIPTIONS
SERVICE_DESCRIPTIONS=(
  [homarr]="Tier 1 · Lightweight home dashboard"
  [portainer]="Tier 1 · Docker container visualizer"
  [filebrowser]="Tier 2 · Personal cloud file manager"
  [nextcloud]="Tier 2 · Full personal cloud suite"
  [jellyfin]="Tier 3 · Media streaming server"
  [prowlarr]="Tier 3 · Indexer manager for media"
  [qbittorrent]="Tier 3 · Lightweight BitTorrent client"
  [navidrome]="Tier 3 · Modern music server"
)

# RAM (MB) | Disk (MB)
declare -A SERVICE_REQUIREMENTS
SERVICE_REQUIREMENTS=(
  [homarr]="150|500"
  [portainer]="100|500"
  [filebrowser]="50|200"
  [nextcloud]="512|2000"
  [jellyfin]="768|2000"
  [prowlarr]="256|500"
  [qbittorrent]="512|1000"
  [navidrome]="256|500"
)

# ── Helpers ───────────────────────────────────────────────────────────────────

check_resources() {
  local required_ram=$1 required_disk=$2
  local free_ram; free_ram=$(free -m | awk '/^Mem:/{print $7}')
  local free_disk; free_disk=$(df -m / | awk 'NR==2{print $4}')
  local ok=true

  (( free_ram < required_ram ))  && { error "Insufficient RAM! Required: ${required_ram}MB, Available: ${free_ram}MB";   ok=false; }
  (( free_disk < required_disk )) && { error "Insufficient Disk! Required: ${required_disk}MB, Available: ${free_disk}MB"; ok=false; }

  [[ "$ok" == true ]] || return 1
}

is_port_free() {
  ! ss -tlnp | grep -q ":${1} "
}

# ── Deployment Engine ─────────────────────────────────────────────────────────

deploy_service() {
  local name=$1
  local provided_port=${2:-}
  local def="${SERVICES[$name]}"
  IFS='|' read -r image default_port _unused extra_env extra_ports extra_volumes extra_args <<< "$def"

  local cfg_dir="${CONFIG_BASE}/${name}"
  local custom_df="${DOCKER_FILES_DIR}/${name}-dockerfile"
  local port

  if [[ -n "$provided_port" ]]; then
    port="$provided_port"
  else
    # Fallback to interactive logic for manual single calls
    local reqs="${SERVICE_REQUIREMENTS[$name]:-256|1000}"
    if ! check_resources "${reqs%%|*}" "${reqs##*|}"; then
      warn "Deployment aborted due to lack of VPS resources."
      return 1
    fi

    if docker container inspect "$name" &>/dev/null; then
      if confirm "'${name}' container already exists. Rebuild it?"; then
        docker rm -f "$name" &>> "$LOG_FILE" || true
      else
        return
      fi
    fi

    if ! is_port_free "$default_port"; then
      error "Default port ${default_port} is already in use."
      prompt "Enter a custom port for ${name}" port
      [[ -z "$port" ]] && { warn "No port provided. Aborting."; return 1; }
    else
      printf "  ${MAUVE}?${NC} ${BOLD}Port for ${name}${NC} [${DIM}default: ${default_port}${NC}]: "
      read -r port
      [[ -z "$port" ]] && port="$default_port"
    fi
  fi

  mkdir -p "$cfg_dir"

  local active_image="$image"
  if [[ -f "$custom_df" ]]; then
    run_task "Building custom ${name} image" "docker build -t local-${name}:latest -f $custom_df $DOCKER_FILES_DIR"
    active_image="local-${name}:latest"
  else
    # If pulled in parallel, this completes instantly
    run_task "Verifying ${name} image" "docker pull $active_image"
  fi

  info "Starting ${name} container..."
  local run_cmd=(docker run -d --name "$name" --restart unless-stopped)
  run_cmd+=(--network "$PROXY_NETWORK")
  
  # Smart port mapping for containers with mismatched internal ports
  local internal_port="$default_port"
  if [[ "$extra_ports" == :* ]]; then
    internal_port="${extra_ports#:}"
    extra_ports="" # Clear it so it's not mapped twice
  fi
  run_cmd+=(-p "${port}:${internal_port}")

  [[ -n "$extra_args" ]] && { read -ra args_arr <<< "$extra_args"; run_cmd+=("${args_arr[@]}"); }

  if [[ -n "$extra_ports" ]]; then
    IFS=',' read -ra port_arr <<< "$extra_ports"
    for ep in "${port_arr[@]}"; do run_cmd+=(-p "$ep"); done
  fi

  # Firewall safety: Ensure the host port is open to the internet
  if command -v ufw &>/dev/null; then
    sudo ufw allow "$port"/tcp &>> "$LOG_FILE" || true
  fi

  run_cmd+=(-v "${cfg_dir}:/config")
  run_cmd+=(-v "${MEDIA_DIR}:${MEDIA_DIR}")

  if [[ -n "$extra_volumes" ]]; then
    IFS=',' read -ra vol_arr <<< "$extra_volumes"
    for ev in "${vol_arr[@]}"; do
      run_cmd+=(-v "${ev//CFG_DIR/$cfg_dir}")
    done
  fi

  if [[ -n "$extra_env" ]]; then
    IFS=',' read -ra env_arr <<< "$extra_env"
    for e in "${env_arr[@]}"; do run_cmd+=(-e "$e"); done
  fi

  # ── Smart overrides for specific services ──────────────────────────────────────
  if [[ "$name" == "qbittorrent" ]]; then
    run_cmd+=(-e "WEBUI_PORT=${port}")
  fi

  run_cmd+=("$active_image")
  run_task "Launching container" "${run_cmd[*]}"

  state_set_service "$name" "$port" "running"
  success "${name} deployed on port ${port}.  Config: ${cfg_dir}"
  
  if [[ -v MULTI_DEPLOY_SUMMARY ]]; then
    MULTI_DEPLOY_SUMMARY+=("  ${GREEN}${OK}${NC} ${BOLD}${name}${NC} deployed on port ${TEAL}:${port}${NC}")
  fi

  # ── Post-deploy hooks ──────────────────────────────────────────────────────
  if [[ "$name" == "qbittorrent" ]]; then
    # We delay password fetching to give container time to start while other things deploy
    export QBITTORRENT_CHECK_PASSWORD=true
  fi
}
