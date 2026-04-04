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

# ── Ordered Service List (for menu) ───────────────────────────────────────────
ORDERED_SERVICES=(
  "homarr" "portainer"
  "filebrowser" "nextcloud"
  "jellyfin" "navidrome" "kavita" "qbittorrent" "prowlarr"
)

declare -A SERVICE_DESCRIPTIONS
SERVICE_DESCRIPTIONS=(
  [homarr]="Tier 1 · Lightweight home dashboard"
  [portainer]="Tier 1 · Docker container visualizer"
  [filebrowser]="Tier 2 · Personal cloud file manager"
  [nextcloud]="Tier 2 · Full personal cloud suite"
  [jellyfin]="Tier 3 · Media streaming server"
  [navidrome]="Tier 3 · Modern music server"
  [qbittorrent]="Tier 3 · Lightweight BitTorrent client"
  [prowlarr]="Tier 3 · Indexer manager for media"
  [kavita]="Tier 3 · Ultimate Ebook & Manga reader"
)

declare -A SERVICE_REQUIREMENTS
SERVICE_REQUIREMENTS=(
  [homarr]="128|500"
  [portainer]="128|500"
  [filebrowser]="128|1000"
  [nextcloud]="512|2000"
  [jellyfin]="1024|4000"
  [navidrome]="256|1000"
  [qbittorrent]="256|2000"
  [prowlarr]="256|1000"
  [kavita]="512|2000"
)

# ── Deployment Logic ──────────────────────────────────────────────────────────

deploy_service() {
  local name=$1 port=$2
  local def="${SERVICES[$name]}"
  [[ -z "$def" ]] && die "Service ${name} not defined in catalog."

  IFS='|' read -r image default_port _dir extra_env extra_ports extra_volumes extra_args <<< "$def"

  local cfg_dir="${CONFIG_BASE}/${name}"
  mkdir -p "$cfg_dir"

  # Pre-flight: Pull image
  run_task "Verifying ${name} image" "docker pull ${image}"
  local active_image="$image"

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
