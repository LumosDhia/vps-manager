#!/usr/bin/env bats
# ==============================================================================
#  manager.sh Unit Tests  |  tests/test_manager.bats
#  Framework: BATS (Bash Automated Testing System)
#  Run: bats tests/test_manager.bats
# ==============================================================================

# Load helper: this sources manager.sh functions without executing the script
MANAGER="${BATS_TEST_DIRNAME}/../manager.sh"

# ── Stubs/Mocks ────────────────────────────────────────────────────────────────
# Override system-level calls so tests are safe and idempotent.
docker()   { echo "docker $*"; }
sudo()     { shift; "$@"; }
jq()       { command jq "$@"; }
systemctl(){ echo "systemctl $@"; }
ss()       { echo "LISTEN 127.0.0.1:22 users"; }
free()     { printf "Mem: 8192 2048 0 0 0 6144\n"; }
df()       { printf "Filesystem Size Used Avail\n/dev/sda1 50G 10G 40G\n"; }
ufw()      { echo "Status: active"; }
fail2ban-client() { return 0; }
export -f docker sudo jq systemctl ss free df ufw fail2ban-client

# Source the script in "test mode" - skips the interactive entrypoint
_source_manager() {
  set +euo pipefail
  source <(
    # Strip main entrypoint so sourcing just loads the functions
    grep -v 'handle_user\|main_menu\|cmd_initialize\|^touch\|^state_init\|^case\|^  up)\|^  down)\|^  status)\|^  doctor)\|^  clean)\|^  purge)\|^  init)\|^  --child\|^  \*)\|^esac' "$MANAGER" | \
    sed '/^if \[\[ "\${1:-}" != "--child" \]\]/,/^fi/d'
  )
  set -euo pipefail
  STATE_FILE="$(mktemp)"
  LOG_FILE="$(mktemp)"
  echo '{"services":{}}' > "$STATE_FILE"
}

setup() {
  _source_manager
}

teardown() {
  rm -f "$STATE_FILE" "$LOG_FILE"
}

# ── Test Suite 1: Service Catalog Definitions ──────────────────────────────────

@test "SERVICES array is populated" {
  [ "${#SERVICES[@]}" -gt 0 ]
}

@test "SERVICE_DESCRIPTIONS matches every SERVICES key" {
  for key in "${!SERVICES[@]}"; do
    [ -n "${SERVICE_DESCRIPTIONS[$key]:-}" ] || {
      echo "Missing description for: $key"
      return 1
    }
  done
}

@test "SERVICE_REQUIREMENTS matches every SERVICES key" {
  for key in "${!SERVICES[@]}"; do
    [ -n "${SERVICE_REQUIREMENTS[$key]:-}" ] || {
      echo "Missing requirement for: $key"
      return 1
    }
  done
}

@test "All service definitions have 8 pipe-delimited fields" {
  for key in "${!SERVICES[@]}"; do
    local def="${SERVICES[$key]}"
    local field_count; field_count=$(echo "$def" | awk -F'|' '{print NF}')
    [ "$field_count" -eq 8 ] || {
      echo "Service '$key' has $field_count fields (expected 8)"
      return 1
    }
  done
}

@test "SERVICE_REQUIREMENTS values follow RAM|DISK format" {
  for key in "${!SERVICE_REQUIREMENTS[@]}"; do
    local reqs="${SERVICE_REQUIREMENTS[$key]}"
    echo "$reqs" | grep -qE '^[0-9]+\|[0-9]+$' || {
      echo "Bad format for '$key': $reqs"
      return 1
    }
  done
}

@test "jellyfin is defined in SERVICES" {
  [ -n "${SERVICES[jellyfin]:-}" ]
}

@test "brave service requires GPU args" {
  echo "${SERVICES[brave]}" | grep -q "gpus all"
}

@test "kali-lab service requires GPU args" {
  echo "${SERVICES[kali-lab]}" | grep -q "gpus all"
}

@test "homarr mounts docker.sock" {
  echo "${SERVICES[homarr]}" | grep -q "docker.sock"
}

@test "portainer mounts docker.sock" {
  echo "${SERVICES[portainer]}" | grep -q "docker.sock"
}

@test "jellyfin uses Africa/Tunis timezone" {
  echo "${SERVICES[jellyfin]}" | grep -q "Africa/Tunis"
}

@test "jellyfin uses correct linuxserver image registry" {
  echo "${SERVICES[jellyfin]}" | grep -q "lscr.io/linuxserver"
}

# ── Test Suite 2: State Management ────────────────────────────────────────────

@test "state_init creates state file with default JSON" {
  rm -f "$STATE_FILE"
  state_init
  [ -f "$STATE_FILE" ]
  run jq -r '.services' "$STATE_FILE"
  [ "$output" = "{}" ]
}

@test "state_set persists a key-value pair" {
  state_set ".docker_installed" "true"
  run jq -r '.docker_installed' "$STATE_FILE"
  [ "$output" = "true" ]
}

@test "state_get retrieves a stored value" {
  state_set ".proxy_deployed" "true"
  run state_get ".proxy_deployed"
  [ "$output" = "true" ]
}

@test "state_get returns empty for missing key" {
  run state_get ".nonexistent_key"
  [ -z "$output" ]
}

@test "state_set_service stores service metadata" {
  state_set_service "jellyfin" "8096" "running"
  run jq -r '.services.jellyfin.port' "$STATE_FILE"
  [ "$output" = "8096" ]
  run jq -r '.services.jellyfin.status' "$STATE_FILE"
  [ "$output" = "running" ]
}

@test "state_remove_service deletes a service entry" {
  state_set_service "homarr" "7575" "running"
  state_remove_service "homarr"
  run jq -r '.services.homarr' "$STATE_FILE"
  [ "$output" = "null" ]
}

# ── Test Suite 3: Resource Checking ──────────────────────────────────────────

@test "check_resources passes when enough RAM and Disk" {
  # Mocked free() returns 6144MB available, df returns 40960MB available
  run check_resources 512 1000
  [ "$status" -eq 0 ]
}

@test "check_resources fails when RAM required exceeds available" {
  run check_resources 99999 100
  [ "$status" -ne 0 ]
}

@test "check_resources fails when disk required exceeds available" {
  # 40960MB available, ask for more
  run check_resources 100 999999
  [ "$status" -ne 0 ]
}

# ── Test Suite 4: Port Utilities ──────────────────────────────────────────────

@test "is_port_free returns true for unused port" {
  # Mocked ss() only echoes port 22
  run bash -c 'source '"$MANAGER"' 2>/dev/null || true; ss(){ echo "LISTEN 127.0.0.1:22"; }; export -f ss; is_port_free 7575 && echo ok'
  [ "$output" = "ok" ]
}

# ── Test Suite 5: Globals & Paths ─────────────────────────────────────────────

@test "MEDIA_DIR is set to /mnt/media" {
  [ "$MEDIA_DIR" = "/mnt/media" ]
}

@test "CONFIG_BASE contains personal-server" {
  echo "$CONFIG_BASE" | grep -q "personal-server"
}

@test "PROXY_NETWORK is set" {
  [ -n "$PROXY_NETWORK" ]
}

@test "DOCKER_FILES_DIR points to docker-files" {
  echo "$DOCKER_FILES_DIR" | grep -q "docker-files"
}
