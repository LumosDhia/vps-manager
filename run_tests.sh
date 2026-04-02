#!/usr/bin/env bash
# ==============================================================================
#  Install BATS and run all manager.sh unit tests
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install BATS if missing
if ! command -v bats &>/dev/null; then
  echo "► BATS not found. Installing via git..."
  git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats-core
  sudo /tmp/bats-core/install.sh /usr/local
fi

echo
echo "  ── Running VPS Manager Unit Tests ─────────────────────────────────"
echo

bats --tap "${SCRIPT_DIR}/tests/test_manager.bats"
