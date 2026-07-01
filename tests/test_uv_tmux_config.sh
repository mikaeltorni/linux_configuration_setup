#!/usr/bin/env bash
# Regression tests for UV and tmux configuration assets owned by this repo.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_HOME="$(mktemp -d)"
trap 'rm -rf "$TARGET_HOME"' EXIT
TARGET_USER="$(id -un)"
CONFIG_DIR="$ROOT_DIR/configs"

msg() { :; }
log() { :; }
run_as_target() {
  # Skip the networked UV bootstrap; execute deterministic file operations.
  [[ "${1:-}" == bash ]] && return 0
  "$@"
}

source "$ROOT_DIR/lib/gnome_desktop.sh"
source "$ROOT_DIR/lib/system_config.sh"

configure_uv_autostart
configure_tmux_defaults

diff -q "$CONFIG_DIR/uv/uv.toml" "$TARGET_HOME/.config/uv/uv.toml" >/dev/null
diff -q "$CONFIG_DIR/tmux/.tmux.conf" "$TARGET_HOME/.tmux.conf" >/dev/null

# Repeated deployment must reproduce the same files without failure.
configure_uv_autostart
configure_tmux_defaults
diff -q "$CONFIG_DIR/uv/uv.toml" "$TARGET_HOME/.config/uv/uv.toml" >/dev/null
diff -q "$CONFIG_DIR/tmux/.tmux.conf" "$TARGET_HOME/.tmux.conf" >/dev/null

printf 'test_uv_tmux_config.sh: all assertions passed\n'
