#!/usr/bin/env bash
# active_monitor.sh - install the pin-window-to-active-monitor runtime helper.
#
# Sourced by install.sh after the shared component framework + install helpers
# are loaded (it relies on msg, run_as_target, is_root from
# installer_helpers.sh and log from logging.sh). Defines the configure function
# for the active_monitor_placement component.
#
# The helper script (scripts/pin-window-to-active-monitor.sh) is deployed to
# ~/.local/bin/ so it can be called by any runtime script or hotkey — notably
# the open-kitty-and-sort hotkey from linux_hotkey_window_tools, which calls it
# to keep newly-launched kitty windows on the active monitor even when the
# workspace is crowded.

ACTIVE_MONITOR_HELPER_NAME="pin-window-to-active-monitor.sh"
ACTIVE_MONITOR_HELPER_SRC="$SCRIPT_DIR/scripts/$ACTIVE_MONITOR_HELPER_NAME"

# configure_active_monitor_placement - deploy the pin-window-to-active-monitor
# helper to the target user's ~/.local/bin so runtime scripts and hotkeys can
# call it. Returns: 0 on success; 1 when the source script is missing.
configure_active_monitor_placement() {
  msg "Installing pin-window-to-active-monitor helper"
  local target="$TARGET_HOME/.local/bin/$ACTIVE_MONITOR_HELPER_NAME"
  if [ ! -f "$ACTIVE_MONITOR_HELPER_SRC" ]; then
    log "error" "pin-window-to-active-monitor source missing at $ACTIVE_MONITOR_HELPER_SRC"
    msg "pin-window-to-active-monitor helper source missing; skipping component."
    return 1
  fi
  run_as_target install -d -m 0755 "$TARGET_HOME/.local/bin"
  if is_root; then
    install -D -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "$ACTIVE_MONITOR_HELPER_SRC" "$target"
  else
    install -D -m 0755 "$ACTIVE_MONITOR_HELPER_SRC" "$target"
  fi
  log "info" "installed pin-window-to-active-monitor helper to $target"
  msg "Installed pin-window-to-active-monitor helper to ~/.local/bin/"
}
