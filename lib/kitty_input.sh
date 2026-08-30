#!/usr/bin/env bash
# kitty_input.sh — Reversible Kitty input-filter configuration.
#
# Public functions:
#   - configure_kitty_apostrophe_filter(): Consume only unmodified apostrophes.
#   - detect_kitty_apostrophe_filter(): Check for the exact discard mapping.
#   - uninstall_kitty_apostrophe_filter(): Remove only the managed mapping.
#
# Depends on the installer-provided msg, log, and run_as_target helpers.

KITTY_APOSTROPHE_COMMENT="# Ignore accidental apostrophe input while leaving every other key unchanged."
KITTY_APOSTROPHE_MAPPING="map apostrophe discard_event"

# configure_kitty_apostrophe_filter — Install the exact Kitty mapping that
#   consumes an unmodified apostrophe. Modifier combinations and all other keys
#   remain available to the terminal application. Existing apostrophe actions
#   are replaced so the effective behavior is deterministic.
#   Args: none. Returns: 0 when the config is updated.
configure_kitty_apostrophe_filter() {
  msg "Enabling Kitty apostrophe input filter"
  log "info" "Applying Kitty apostrophe input filter for $TARGET_USER"

  run_as_target env \
    KITTY_APOSTROPHE_COMMENT="$KITTY_APOSTROPHE_COMMENT" \
    KITTY_APOSTROPHE_MAPPING="$KITTY_APOSTROPHE_MAPPING" \
    bash -lc '
set -eu
conf="$HOME/.config/kitty/kitty.conf"
mkdir -p "$(dirname "$conf")"
if [ ! -f "$conf" ]; then
  printf "# Managed by linux_configuration_setup.\n" >"$conf"
fi
if grep -q "^map apostrophe[[:space:]]" "$conf"; then
  sed -i "s/^map apostrophe[[:space:]].*/$KITTY_APOSTROPHE_MAPPING/" "$conf"
else
  printf "\n%s\n%s\n" "$KITTY_APOSTROPHE_COMMENT" "$KITTY_APOSTROPHE_MAPPING" >>"$conf"
fi'
}

# detect_kitty_apostrophe_filter — Check the live config for the exact managed
#   discard action rather than treating any apostrophe mapping as enabled.
#   Args: none. Returns: 0 when enabled, 1 otherwise.
detect_kitty_apostrophe_filter() {
  local conf="$TARGET_HOME/.config/kitty/kitty.conf"
  [ -f "$conf" ] && grep -Fxq "$KITTY_APOSTROPHE_MAPPING" "$conf"
}

# uninstall_kitty_apostrophe_filter — Remove the managed mapping and its exact
#   comment while preserving every unrelated Kitty setting and shortcut.
#   Args: none. Returns: 0, including when the config is already absent.
uninstall_kitty_apostrophe_filter() {
  local conf="$TARGET_HOME/.config/kitty/kitty.conf"
  msg "Disabling Kitty apostrophe input filter"
  log "info" "Removing Kitty apostrophe input filter for $TARGET_USER"
  run_as_target test -f "$conf" || return 0
  run_as_target python3 - \
    "$conf" "$KITTY_APOSTROPHE_COMMENT" "${KITTY_APOSTROPHE_MAPPING%discard_event}" <<'PY'
"""Remove the installer-owned apostrophe mapping without touching other keys."""
import sys

path, comment, mapping_prefix = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    lines = handle.read().splitlines()

kept: list[str] = []
for line in lines:
    if line.startswith(mapping_prefix):
        if kept and kept[-1] == comment:
            kept.pop()
        while kept and not kept[-1].strip():
            kept.pop()
        continue
    kept.append(line)

text = "\n".join(kept).rstrip("\n")
with open(path, "w", encoding="utf-8") as handle:
    handle.write(text + "\n" if text else "")
PY
}
