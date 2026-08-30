#!/usr/bin/env bash
# Lifecycle tests for the kitty_defaults component: configure, detect, uninstall.
#
# The component appends managed settings to the user's own kitty.conf, so the
# uninstall step has to take exactly those lines back out and leave everything
# else the user wrote untouched.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_HOME="$(mktemp -d)"
trap 'rm -rf "$TARGET_HOME"' EXIT
TARGET_USER="$(id -un)"
SCRIPT_DIR="$ROOT_DIR"
export HOME="$TARGET_HOME"

msg() { :; }
log() { :; }
run_as_target() { "$@"; }

source "$ROOT_DIR/lib/gsettings_helpers.sh"
source "$ROOT_DIR/lib/autostart.sh"
source "$ROOT_DIR/lib/lifecycle.sh"

CONF="$TARGET_HOME/.config/kitty/kitty.conf"

# A user config that already carries personal settings the installer must keep.
mkdir -p "$(dirname "$CONF")"
cat >"$CONF" <<'EOF'
# My own kitty configuration.
font_size 13.0
background_opacity 0.9
EOF

configure_kitty_defaults
grep -qx 'confirm_os_window_close 0' "$CONF"
grep -qx 'map ctrl+backspace send_key ctrl+w' "$CONF"
grep -qx 'map apostrophe discard_event' "$CONF"
grep -qx 'wayland_titlebar_color background' "$CONF"
detect_kitty_defaults

# Re-running must not duplicate the managed lines.
configure_kitty_defaults
[ "$(grep -c '^confirm_os_window_close' "$CONF")" -eq 1 ]

uninstall_kitty_defaults
if detect_kitty_defaults; then
  printf 'kitty defaults still detected after uninstall\n' >&2
  exit 1
fi
! grep -q '^confirm_os_window_close' "$CONF"
! grep -q '^map ctrl+backspace' "$CONF"
! grep -q '^map apostrophe' "$CONF"
! grep -q '^wayland_titlebar_color' "$CONF"

# The user's own settings survive, and the file is never deleted.
[ -f "$CONF" ]
grep -qx 'font_size 13.0' "$CONF"
grep -qx 'background_opacity 0.9' "$CONF"
grep -qx '# My own kitty configuration.' "$CONF"

# Uninstalling twice, or with no config at all, is a no-op rather than an error.
uninstall_kitty_defaults
rm -f "$CONF"
uninstall_kitty_defaults
! detect_kitty_defaults

printf 'test_kitty_defaults_lifecycle.sh: all assertions passed\n'
