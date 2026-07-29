#!/usr/bin/env bash
# active_monitor.sh - install system-wide active-monitor placement + CLI helper.
#
# Sourced by install.sh after the shared component framework + install helpers
# are loaded (it relies on msg, run_as_target, is_root from
# installer_helpers.sh and log from logging.sh). Defines the configure function
# for the active_monitor_placement component.
#
# Two artifacts are deployed:
#   1. scripts/pin-window-to-active-monitor.sh → ~/.local/bin/ (CLI pin for
#      open-kitty-and-sort and other callers).
#   2. active-monitor-placement@local GNOME Shell extension →
#      ~/.local/share/gnome-shell/extensions/ (session-wide window-created
#      correction onto the pointer/active monitor when Mutter places a new
#      window on a crowded or other display).
#
# The extension is the system-wide fix; the helper remains for script callers.

ACTIVE_MONITOR_HELPER_NAME="pin-window-to-active-monitor.sh"
ACTIVE_MONITOR_HELPER_SRC="$SCRIPT_DIR/scripts/$ACTIVE_MONITOR_HELPER_NAME"
ACTIVE_MONITOR_EXT_UUID="active-monitor-placement@local"
ACTIVE_MONITOR_EXT_SRC="${CONFIG_DIR:-$SCRIPT_DIR/configs}/gnome-extensions/$ACTIVE_MONITOR_EXT_UUID"
ACTIVE_MONITOR_EXT_DST_REL=".local/share/gnome-shell/extensions/$ACTIVE_MONITOR_EXT_UUID"

# _active_monitor_strv_edit add|remove SCHEMA KEY VALUE — idempotently edit a
# gsettings string-array key (enabled-extensions). Isolated helper so this
# component does not depend on dash_to_panel's private d2p_strv_edit.
# Args: $1 op, $2 schema, $3 key, $4 value. Returns: 0 (set is best-effort).
_active_monitor_strv_edit() {
  local op="$1" schema="$2" key="$3" value="$4" current new
  current="$(run_as_target gsettings get "$schema" "$key" 2>/dev/null || printf '[]')"
  new="$(OP="$op" VAL="$value" python3 - "$current" <<'PY'
import ast, os, sys
raw = (sys.argv[1] or "").strip() or "[]"
try:
    items = ast.literal_eval(raw)
    items = items if isinstance(items, list) else []
except Exception:
    items = []
val, op = os.environ["VAL"], os.environ["OP"]
if op == "add" and val not in items:
    items.append(val)
elif op == "remove":
    items = [x for x in items if x != val]
print("[" + ", ".join("'" + x + "'" for x in items) + "]")
PY
)"
  run_as_target gsettings set "$schema" "$key" "$new" 2>/dev/null || true
}

# _active_monitor_deploy_helper — copy the pin-window CLI helper to ~/.local/bin.
# Returns: 0 on success; 1 when the source script is missing.
_active_monitor_deploy_helper() {
  local target="$TARGET_HOME/.local/bin/$ACTIVE_MONITOR_HELPER_NAME"
  if [ ! -f "$ACTIVE_MONITOR_HELPER_SRC" ]; then
    log "error" "pin-window-to-active-monitor source missing at $ACTIVE_MONITOR_HELPER_SRC"
    msg "pin-window-to-active-monitor helper source missing; skipping helper."
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
  return 0
}

# _active_monitor_deploy_extension — copy and enable active-monitor-placement@local.
# Returns: 0 on success or clean skip when source is missing; non-zero on hard fail.
_active_monitor_deploy_extension() {
  local ext_src="$ACTIVE_MONITOR_EXT_SRC"
  local ext_dst="$TARGET_HOME/$ACTIVE_MONITOR_EXT_DST_REL"

  if [ ! -d "$ext_src" ]; then
    log "error" "active-monitor-placement extension source missing at $ext_src"
    msg "  active-monitor-placement source not found at $ext_src; skipping extension."
    return 1
  fi
  if [ ! -f "$ext_src/extension.js" ] || [ ! -f "$ext_src/placementPolicy.js" ] || [ ! -f "$ext_src/metadata.json" ]; then
    log "error" "active-monitor-placement extension incomplete under $ext_src"
    msg "  active-monitor-placement extension files incomplete; skipping."
    return 1
  fi

  msg "Deploying $ACTIVE_MONITOR_EXT_UUID GNOME Shell extension"
  run_as_target install -d -m 0755 "$(dirname "$ext_dst")" "$ext_dst"

  local f
  for f in "$ext_src"/*; do
    [ -f "$f" ] || continue
    log "debug" "active_monitor: deploying extension file $(basename "$f")"
    if is_root; then
      install -m 0644 -o "$TARGET_USER" -g "$TARGET_USER" "$f" "$ext_dst/$(basename "$f")"
    else
      install -m 0644 "$f" "$ext_dst/$(basename "$f")"
    fi
  done

  # Persist enable without blocking the installer on a slow Shell D-Bus call.
  log "info" "enabling user extensions and $ACTIVE_MONITOR_EXT_UUID"
  run_as_target gsettings set org.gnome.shell disable-user-extensions false 2>/dev/null || true
  _active_monitor_strv_edit add org.gnome.shell enabled-extensions "$ACTIVE_MONITOR_EXT_UUID"
  _active_monitor_strv_edit remove org.gnome.shell disabled-extensions "$ACTIVE_MONITOR_EXT_UUID"
  run_as_target sh -c 'timeout 5 gnome-extensions enable "$1" >/dev/null 2>&1 </dev/null &' _ "$ACTIVE_MONITOR_EXT_UUID" || true

  log "info" "deployed $ACTIVE_MONITOR_EXT_UUID to $ext_dst"
  msg "  Extension deployed to $ext_dst"
  msg "  NOTE: If the Shell does not load the new code in-session, log out and back in (installers never kill GNOME Shell)."
  return 0
}

# configure_active_monitor_placement - deploy the pin helper and the session-wide
# active-monitor-placement extension so ordinary launches land on the
# pointer/active monitor when the WM would otherwise pick a crowded other display.
# Returns: 0 when at least the helper is installed; 1 only when both artifacts fail.
configure_active_monitor_placement() {
  msg "Installing active-monitor placement (helper + session extension)"
  local helper_rc=0 ext_rc=0
  _active_monitor_deploy_helper || helper_rc=$?
  _active_monitor_deploy_extension || ext_rc=$?
  if [ "$helper_rc" -ne 0 ] && [ "$ext_rc" -ne 0 ]; then
    log "error" "active_monitor_placement: both helper and extension deploy failed"
    return 1
  fi
  if [ "$helper_rc" -ne 0 ]; then
    log "warn" "active_monitor_placement: helper deploy failed; extension path may still work"
  fi
  if [ "$ext_rc" -ne 0 ]; then
    log "warn" "active_monitor_placement: extension deploy failed; CLI pin helper still available"
  fi
  return 0
}
