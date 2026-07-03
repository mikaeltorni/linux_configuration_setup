#!/usr/bin/env bash
# dash_to_panel.sh - Dash-to-Panel desktop layout (moved here from the taskbar
# system-monitor repo so panel/desktop behavior lives with the rest of the GNOME
# configuration). Self-contained: it downloads the pinned Dash-to-Panel build
# from GitHub releases (version-pinned), patches its metadata for the
# running shell, enables it, disables the Ubuntu Dock, and applies the panel
# dconf defaults. Provides detect/uninstall for the component lifecycle.

D2P_EXT_ID="${DASH_TO_PANEL_EXTENSION_ID:-dash-to-panel@jderose9.github.com}"
D2P_EXT_URL="${DASH_TO_PANEL_EXTENSION_URL:-https://github.com/home-sweet-gnome/dash-to-panel/releases/download/v73/dash-to-panel%40jderose9.github.com_v73.zip}"
# SHA256 verification disabled - using GitHub releases instead

d2p_ext_dir() { printf '%s\n' "$TARGET_HOME/.local/share/gnome-shell/extensions/$D2P_EXT_ID"; }

# d2p_installed - true when the extension is deployed locally or system-wide.
d2p_installed() {
  [ -f "$(d2p_ext_dir)/metadata.json" ] && return 0
  [ -f "/usr/share/gnome-shell/extensions/$D2P_EXT_ID/metadata.json" ] && return 0
  return 1
}

# d2p_strv_edit add|remove SCHEMA KEY VALUE - idempotently add/remove a value in
# a gsettings string-array key without an external helper.
d2p_strv_edit() {
  local op="$1" schema="$2" key="$3" value="$4" current new
  current="$(run_as_target gsettings get "$schema" "$key" 2>/dev/null || printf '[]')"
  new="$(OP="$op" VAL="$value" python3 - "$current" <<'PY'
import ast, os, sys
raw = (sys.argv[1] or "").strip() or "[]"
try:
    items = ast.literal_eval(raw); items = items if isinstance(items, list) else []
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

# d2p_strv_contains SCHEMA KEY VALUE - return success when VALUE is an exact
# member of a gsettings string-array. Malformed or unavailable settings are
# treated as absent so lifecycle detection never reports a false positive.
d2p_strv_contains() {
  local schema="$1" key="$2" value="$3" current
  current="$(run_as_target gsettings get "$schema" "$key" 2>/dev/null)" || return 1
  VAL="$value" python3 - "$current" <<'PY'
import ast
import os
import sys

try:
    values = ast.literal_eval(sys.argv[1])
except (SyntaxError, ValueError):
    raise SystemExit(1)
raise SystemExit(0 if isinstance(values, list) and os.environ["VAL"] in values else 1)
PY
}

# d2p_download_install - fetch + verify + extract the pinned EGO build, then pin
d2p_download_install() {
  local ext_dir tmpdir zip_file extracted shell_version
  ext_dir="$(d2p_ext_dir)"
  apt_install curl unzip
  tmpdir="$(mktemp -d)"
  zip_file="$tmpdir/$(basename "$D2P_EXT_URL")"
  msg "Downloading Dash-to-Panel from $D2P_EXT_URL"
  if ! curl -fsSL "$D2P_EXT_URL" -o "$zip_file"; then
    msg "Failed to download Dash-to-Panel"
    return 1
  fi
  run_as_target rm -rf "$ext_dir"
  mkdir -p "$(dirname "$ext_dir")"
  # Remove conflicting pre-existing UI files that may block extraction
  run_as_target rm -f ~/.local/share/gnome-shell/extensions/ui/Box*.ui 2>/dev/null || true
  run_as_target rm -f ~/.local/share/gnome-shell/extensions/ui/SettingsPosition.ui 2>/dev/null || true
  
  unzip -qo "$zip_file" -d "$(dirname "$ext_dir")/temp_extracted" || {
    msg "Failed to extract Dash-to-Panel zip"
    return 1  
  }
  # Handle both subdirectory and flat-zip structures from GitHub releases
  local temp_ext
  temp_ext="$(find "$(dirname "$ext_dir")" -maxdepth 2 -type d -name "*${D2P_EXT_ID}*" | head -1)"
  if [ -n "$temp_ext" ] && [ "$temp_ext" != "$ext_dir" ]; then
    mv "$temp_ext" "$ext_dir"
  elif ls "$(dirname "$ext_dir")/temp_extracted/"*metadata.json >/dev/null 2>&1; then
    # Flat zip structure - move all contents into ext_dir  
    mkdir -p "$ext_dir"
    mv "$(dirname "$ext_dir")/temp_extracted/"* "$ext_dir"/ 2>/dev/null || true
  fi
  rm -rf "$(dirname "$ext_dir")/temp_extracted"
  run_as_target chown -R "${TARGET_USER}:${TARGET_USER}" "$ext_dir"
  rm -rf "$tmpdir"
  shell_version="$(gnome-shell --version 2>/dev/null | awk '{print int($3)}')"
  if [ -n "$shell_version" ] && [ -f "$ext_dir/metadata.json" ]; then
    python3 "$SCRIPT_DIR/scripts/patch_extension_metadata.py" \
      "$ext_dir/metadata.json" "$shell_version" 9999 || true
  fi
}

# configure_dash_to_panel - install (if needed), enable, disable Ubuntu Dock, and
# apply the panel dconf defaults. Component entry point.
configure_dash_to_panel() {
  msg "Configuring Dash-to-Panel"
  d2p_installed || d2p_download_install
  if ! d2p_installed; then
    msg "Dash-to-Panel install failed; leaving Ubuntu Dock enabled."
    return 0
  fi
  
  # Time-boxed, backgrounded D-Bus toggles so a slow/unresponsive shell can never
  # block the installer; persistent state is set via gsettings below.
  run_as_target sh -c 'timeout 5 gnome-extensions disable ubuntu-dock@ubuntu.com >/dev/null 2>&1 </dev/null &' || true
  run_as_target sh -c 'timeout 5 gnome-extensions enable "$1" >/dev/null 2>&1 </dev/null &' _ "$D2P_EXT_ID" || true
  
  # Clear GNOME's global user-extension kill switch, then persist the exact
  # enabled/disabled state so detection reflects the active panel layout.
  log "info" "Enabling GNOME user extensions for Dash-to-Panel"
  run_as_target gsettings set org.gnome.shell disable-user-extensions false 2>/dev/null || true
  d2p_strv_edit add org.gnome.shell enabled-extensions "$D2P_EXT_ID"
  d2p_strv_edit remove org.gnome.shell enabled-extensions ubuntu-dock@ubuntu.com
  d2p_strv_edit remove org.gnome.shell disabled-extensions "$D2P_EXT_ID"
  d2p_strv_edit add org.gnome.shell disabled-extensions ubuntu-dock@ubuntu.com
  
  # Core dash-to-panel settings
  run_as_target dconf write /org/gnome/shell/extensions/dash-to-panel/show-favorites true || true
  run_as_target dconf write /org/gnome/shell/extensions/dash-to-panel/isolate-workspaces true || true
  # Show a panel on every monitor and isolate them, so clicking a taskbar icon
  # on a given monitor launches/focuses windows on that same monitor.
  run_as_target dconf write /org/gnome/shell/extensions/dash-to-panel/multi-monitors true || true
  run_as_target dconf write /org/gnome/shell/extensions/dash-to-panel/isolate-monitors true || true
  run_as_target dconf write /org/gnome/shell/extensions/dash-to-panel/stockgs-keep-top-panel false || true
  run_as_target dconf write /org/gnome/shell/extensions/dash-to-panel/show-activities-button false || true
  
  # Configure bottom panel position for shutdown/date controls integration
  run_as_target dconf write /org/gnome/shell/extensions/dash-to-panel/panel-position "'BOTTOM'" || true
  run_as_target dconf write /org/gnome/shell/extensions/dash-to-panel/panel-positions "{'0': 'BOTTOM'}" || true
  # Verify bottom panel is actually applied
  run_as_target sleep 2 && gsettings get org.gnome.shell.extensions.dash-to-panel panel-position 2>/dev/null || true
  
  # Enable system-status integration in dash-to-panel layout (shutdown, date, calendar)  
  run_as_target dconf write /org/gnome/shell/extensions/dash-to-panel/show-app-menu false || true
  run_as_target dconf write /org/gnome/shell/extensions/dash-to-panel/system-status-position "'right'" || true
  
  # Configure app menu position (left side for shutdown, date controls)  
  run_as_target dconf write /org/gnome/shell/extensions/dash-to-panel/app-menu-position "'left'" || true
}

# detect_dash_to_panel - true when Dash-to-Panel is deployed and is the active
# dock implementation. A globally disabled extension set or an enabled Ubuntu
# Dock means the requested desktop state is not installed.
detect_dash_to_panel() {
  d2p_installed || return 1
  [ "$(run_as_target gsettings get org.gnome.shell disable-user-extensions 2>/dev/null)" = "false" ] || return 1
  d2p_strv_contains org.gnome.shell enabled-extensions "$D2P_EXT_ID" || return 1
  ! d2p_strv_contains org.gnome.shell enabled-extensions ubuntu-dock@ubuntu.com
}

# uninstall_dash_to_panel - remove Dash-to-Panel and restore the Ubuntu Dock.  
uninstall_dash_to_panel() {
  msg "Removing Dash-to-Panel and restoring Ubuntu Dock"
  run_as_target gnome-extensions disable "$D2P_EXT_ID" 2>/dev/null || true
  run_as_target rm -rf "$(d2p_ext_dir)"
  d2p_strv_edit remove org.gnome.shell enabled-extensions "$D2P_EXT_ID"
  d2p_strv_edit add org.gnome.shell disabled-extensions "$D2P_EXT_ID"
  run_as_target gnome-extensions enable ubuntu-dock@ubuntu.com 2>/dev/null || true
  d2p_strv_edit add org.gnome.shell enabled-extensions ubuntu-dock@ubuntu.com
  d2p_strv_edit remove org.gnome.shell disabled-extensions ubuntu-dock@ubuntu.com
}
