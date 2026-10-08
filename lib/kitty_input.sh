#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/desktop_tools.sh"
# kitty_input.sh — Reversible Kitty input-filter configuration.
#
# Public functions:
#   - configure_kitty_apostrophe_filter(): Filter bare Kitty input, not tmux.
#   - detect_kitty_apostrophe_filter(): Check for the exact discard mapping.
#   - uninstall_kitty_apostrophe_filter(): Remove only the managed mapping.
#
# Depends on the installer-provided msg, log, and run_as_target helpers.

KITTY_APOSTROPHE_COMMENT="# Ignore accidental apostrophe input outside tmux; pass it through inside tmux."
KITTY_APOSTROPHE_LEGACY_COMMENT="# Ignore accidental apostrophe input while leaving every other key unchanged."
KITTY_APOSTROPHE_LEGACY_PREFIX="map apostrophe "
KITTY_APOSTROPHE_MATCH='not cmdline:"(?:^|/)tmux$"'
KITTY_APOSTROPHE_MAPPING="map --when-focus-on='$KITTY_APOSTROPHE_MATCH' apostrophe discard_event"
KITTY_APOSTROPHE_MAPPING_PREFIX="${KITTY_APOSTROPHE_MAPPING%discard_event}"

# _write_kitty_apostrophe_filter — Reconcile the managed mapping in kitty.conf.
#   Removes the earlier unconditional mapping during upgrades and owns only the
#   exact conditional mapping used by this component. Other shortcuts,
#   including shifted apostrophe and user-defined conditional mappings, remain.
# Parameters: state - on or off. Returns: native filesystem operation status.
_write_kitty_apostrophe_filter() {
  local state="$1"
  local conf="$TARGET_HOME/.config/kitty/kitty.conf"
  run_as_target "$(lcs_desktop_tools_program)" kitty-filter \
    "$conf" "$state" "$KITTY_APOSTROPHE_COMMENT" \
    "$KITTY_APOSTROPHE_LEGACY_COMMENT" "$KITTY_APOSTROPHE_MAPPING" \
    "$KITTY_APOSTROPHE_LEGACY_PREFIX" "$KITTY_APOSTROPHE_MAPPING_PREFIX"
}

# configure_kitty_apostrophe_filter — Install a conditional Kitty mapping that
#   consumes an unmodified apostrophe only when the Kitty child is not tmux.
#   Inside tmux, modifier combinations, apostrophe, and every other key pass to
#   the terminal application normally. Existing unconditional apostrophe
#   actions are migrated so the effective behavior is deterministic. The
#   KITTY_IGNORE_APOSTROPHE environment variable accepts on (default) or off;
#   off delegates to the same reversible uninstall path used by the component.
#   Args: none. Returns: 0 after applying the requested state, 2 for an invalid
#   environment value without changing the config.
configure_kitty_apostrophe_filter() {
  local requested_state="${KITTY_IGNORE_APOSTROPHE:-on}"
  case "$requested_state" in
    on)
      ;;
    off)
      log "info" "KITTY_IGNORE_APOSTROPHE requested state: off"
      uninstall_kitty_apostrophe_filter
      return
      ;;
    *)
      msg "Invalid KITTY_IGNORE_APOSTROPHE value '$requested_state' (expected on or off)"
      log "error" "Invalid KITTY_IGNORE_APOSTROPHE value: $requested_state"
      return 2
      ;;
  esac

  msg "Enabling Kitty apostrophe input filter"
  log "info" "KITTY_IGNORE_APOSTROPHE requested state: on"
  log "info" "Applying Kitty apostrophe filter outside tmux for $TARGET_USER"
  _write_kitty_apostrophe_filter on
}

# detect_kitty_apostrophe_filter — Check for the exact managed conditional
#   discard action rather than treating any apostrophe mapping as enabled.
#   Args: none. Returns: 0 when enabled, 1 otherwise.
detect_kitty_apostrophe_filter() {
  local conf="$TARGET_HOME/.config/kitty/kitty.conf"
  [ -f "$conf" ] && grep -Fxq "$KITTY_APOSTROPHE_MAPPING" "$conf"
}

# uninstall_kitty_apostrophe_filter — Remove current and legacy managed
#   mappings while preserving every unrelated Kitty setting and shortcut.
#   Args: none. Returns: 0, including when the config is already absent.
uninstall_kitty_apostrophe_filter() {
  local conf="$TARGET_HOME/.config/kitty/kitty.conf"
  msg "Disabling Kitty apostrophe input filter"
  log "info" "Removing Kitty apostrophe input filter for $TARGET_USER"
  run_as_target test -f "$conf" || return 0
  _write_kitty_apostrophe_filter off
}
