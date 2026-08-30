#!/usr/bin/env bash
# Lifecycle tests for the independently selectable Kitty apostrophe filter.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_HOME="$(mktemp -d)"
trap 'rm -rf "$TARGET_HOME"' EXIT
TARGET_USER="$(id -un)"
LOG_FILE="$TARGET_HOME/actions.log"
export HOME="$TARGET_HOME"

msg() { :; }
log() { printf '%s\n' "$*" >>"$LOG_FILE"; }
run_as_target() { "$@"; }

source "$ROOT_DIR/lib/kitty_input.sh"

CONF="$TARGET_HOME/.config/kitty/kitty.conf"
mkdir -p "$(dirname "$CONF")"
cat >"$CONF" <<'EOF'
# Personal mappings that this component must preserve.
map a send_text all a
map shift+apostrophe send_text all "
map apostrophe no_op
EOF

configure_kitty_apostrophe_filter
grep -qx 'map apostrophe discard_event' "$CONF"
grep -qx 'map a send_text all a' "$CONF"
grep -qx 'map shift+apostrophe send_text all "' "$CONF"
[ "$(grep -c '^map apostrophe ' "$CONF")" -eq 1 ]
detect_kitty_apostrophe_filter
grep -q 'Applying Kitty apostrophe input filter' "$LOG_FILE"

# A second configure run is idempotent.
configure_kitty_apostrophe_filter
[ "$(grep -c '^map apostrophe ' "$CONF")" -eq 1 ]

# Detection checks the effective action, not merely the key's presence.
sed -i 's/^map apostrophe.*/map apostrophe no_op/' "$CONF"
if detect_kitty_apostrophe_filter; then
  printf 'stale apostrophe action was detected as enabled\n' >&2
  exit 1
fi
configure_kitty_apostrophe_filter

uninstall_kitty_apostrophe_filter
! grep -q '^map apostrophe ' "$CONF"
grep -qx 'map a send_text all a' "$CONF"
grep -qx 'map shift+apostrophe send_text all "' "$CONF"
grep -q 'Removing Kitty apostrophe input filter' "$LOG_FILE"

# Repeated uninstall and an absent config are harmless.
uninstall_kitty_apostrophe_filter
rm -f "$CONF"
uninstall_kitty_apostrophe_filter
! detect_kitty_apostrophe_filter

printf 'test_kitty_apostrophe_filter.sh: all assertions passed\n'
