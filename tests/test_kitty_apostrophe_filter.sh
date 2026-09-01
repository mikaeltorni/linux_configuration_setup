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
EXPECTED_MAPPING="map --when-focus-on='not cmdline:\"(?:^|/)tmux$\"' apostrophe discard_event"
mkdir -p "$(dirname "$CONF")"
cat >"$CONF" <<'EOF'
# Personal mappings that this component must preserve.
map a send_text all a
map shift+apostrophe send_text all "
# User-owned conditional mapping.
map --when-focus-on='title:^special$' apostrophe send_text all x
# Ignore accidental apostrophe input while leaving every other key unchanged.
map apostrophe no_op
EOF

configure_kitty_apostrophe_filter
grep -Fqx "$EXPECTED_MAPPING" "$CONF"
if grep -q '^map apostrophe ' "$CONF"; then
  printf 'legacy unconditional apostrophe mapping was not migrated\n' >&2
  exit 1
fi
if grep -Fq '# Ignore accidental apostrophe input while leaving every other key unchanged.' "$CONF"; then
  printf 'legacy managed comment was not migrated\n' >&2
  exit 1
fi
grep -qx 'map a send_text all a' "$CONF"
grep -qx 'map shift+apostrophe send_text all "' "$CONF"
grep -Fqx "map --when-focus-on='title:^special$' apostrophe send_text all x" "$CONF"
[ "$(grep -Fc "$EXPECTED_MAPPING" "$CONF")" -eq 1 ]
detect_kitty_apostrophe_filter
grep -q 'Applying Kitty apostrophe filter outside tmux' "$LOG_FILE"

# A second configure run is idempotent.
configure_kitty_apostrophe_filter
[ "$(grep -Fc "$EXPECTED_MAPPING" "$CONF")" -eq 1 ]

# The environment switch supports explicit on/off without affecting other keys.
KITTY_IGNORE_APOSTROPHE=off configure_kitty_apostrophe_filter
if detect_kitty_apostrophe_filter; then
  printf 'KITTY_IGNORE_APOSTROPHE=off left the filter enabled\n' >&2
  exit 1
fi
grep -qx 'map a send_text all a' "$CONF"
grep -qx 'map shift+apostrophe send_text all "' "$CONF"
grep -Fqx "map --when-focus-on='title:^special$' apostrophe send_text all x" "$CONF"
KITTY_IGNORE_APOSTROPHE=on configure_kitty_apostrophe_filter
detect_kitty_apostrophe_filter

# Invalid values fail closed before changing the existing config.
before_invalid="$(cat "$CONF")"
if KITTY_IGNORE_APOSTROPHE=maybe configure_kitty_apostrophe_filter; then
  printf 'invalid KITTY_IGNORE_APOSTROPHE value was accepted\n' >&2
  exit 1
fi
[ "$(cat "$CONF")" = "$before_invalid" ]
grep -q 'Invalid KITTY_IGNORE_APOSTROPHE value: maybe' "$LOG_FILE"

# Detection checks the effective action, not merely the key's presence.
sed -i 's/ apostrophe discard_event$/ apostrophe no_op/' "$CONF"
if detect_kitty_apostrophe_filter; then
  printf 'stale apostrophe action was detected as enabled\n' >&2
  exit 1
fi
configure_kitty_apostrophe_filter

uninstall_kitty_apostrophe_filter
if grep -Fq "$EXPECTED_MAPPING" "$CONF" || grep -q '^map apostrophe ' "$CONF"; then
  printf 'uninstall left an apostrophe mapping behind\n' >&2
  exit 1
fi
grep -qx 'map a send_text all a' "$CONF"
grep -qx 'map shift+apostrophe send_text all "' "$CONF"
grep -Fqx "map --when-focus-on='title:^special$' apostrophe send_text all x" "$CONF"
grep -q 'Removing Kitty apostrophe input filter' "$LOG_FILE"

# Repeated uninstall and an absent config are harmless.
uninstall_kitty_apostrophe_filter
rm -f "$CONF"
uninstall_kitty_apostrophe_filter
if detect_kitty_apostrophe_filter; then
  printf 'absent config was detected as enabled\n' >&2
  exit 1
fi

printf 'test_kitty_apostrophe_filter.sh: all assertions passed\n'
