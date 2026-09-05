#!/usr/bin/env bash
# dash_to_panel.sh - Dash-to-Panel desktop layout (moved here from the taskbar
# system-monitor repo so panel/desktop behavior lives with the rest of the GNOME
# configuration). Self-contained: it downloads the pinned Dash-to-Panel build
# from GitHub releases (version-pinned), patches its metadata for the
# running shell, enables it, disables the Ubuntu Dock, applies the panel
# dconf defaults, and installs a graphical-login oneshot that re-applies
# enablement so a GNOME crash kill-switch cannot leave the panel off after
# reboot. Provides detect/uninstall for the component lifecycle.

D2P_EXT_ID="${DASH_TO_PANEL_EXTENSION_ID:-dash-to-panel@jderose9.github.com}"
D2P_EXT_URL="${DASH_TO_PANEL_EXTENSION_URL:-https://github.com/home-sweet-gnome/dash-to-panel/releases/download/v73/dash-to-panel%40jderose9.github.com_v73.zip}"
D2P_MONITOR_PATCHER="${DASH_TO_PANEL_MONITOR_PATCHER:-$SCRIPT_DIR/scripts/patch_dash_to_panel_monitor_launch.py}"
# SHA256 verification disabled - using GitHub releases instead

d2p_ext_dir() { printf '%s\n' "$TARGET_HOME/.local/share/gnome-shell/extensions/$D2P_EXT_ID"; }

# d2p_local_source_installed - true when the patchable per-user extension
# source exists. A system-wide copy is not modified by this root-optional repo.
d2p_local_source_installed() {
  [ -f "$(d2p_ext_dir)/metadata.json" ] && \
    [ -f "$(d2p_ext_dir)/appIcons.js" ]
}

# d2p_installed - true when the extension is deployed locally or system-wide.
d2p_installed() {
  [ -f "$(d2p_ext_dir)/metadata.json" ] && return 0
  [ -f "/usr/share/gnome-shell/extensions/$D2P_EXT_ID/metadata.json" ] && return 0
  return 1
}

# d2p_strv_edit add|remove SCHEMA KEY VALUE - idempotently add/remove a value in
# a gsettings string-array key via lcs-tools.
d2p_strv_edit() {
  if ! declare -F strv_edit >/dev/null 2>&1; then
    # shellcheck source=gsettings_helpers.sh
    source "$SCRIPT_DIR/lib/gsettings_helpers.sh"
  fi
  strv_edit "$@"
}

# d2p_strv_contains SCHEMA KEY VALUE - return success when VALUE is an exact
# member of a gsettings string-array. Malformed or unavailable settings are
# treated as absent so lifecycle detection never reports a false positive.
d2p_strv_contains() {
  if ! declare -F strv_contains >/dev/null 2>&1; then
    # shellcheck source=gsettings_helpers.sh
    source "$SCRIPT_DIR/lib/gsettings_helpers.sh"
  fi
  strv_contains "$@"
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
    if ! declare -F lcs_bin >/dev/null 2>&1; then
      # shellcheck source=lcs_bin.sh
      source "$SCRIPT_DIR/lib/lcs_bin.sh"
    fi
    lcs_bin patch-metadata "$ext_dir/metadata.json" "$shell_version" 9999 || true
  fi
}

# d2p_apply_monitor_launch_patch EXTENSION_DIR - idempotently patch the pinned
# Dash-to-Panel v73 launch path so new app windows follow the clicked panel's
# monitor. Returns non-zero when the downloaded source is missing or differs
# from the expected pinned release.
d2p_apply_monitor_launch_patch() {
  local ext_dir="${1:-$(d2p_ext_dir)}"
  log "info" "Applying Dash-to-Panel monitor-local launch patch in $ext_dir"
  if ! run_as_target python3 "$D2P_MONITOR_PATCHER" "$ext_dir/appIcons.js"; then
    log "error" "Dash-to-Panel monitor-local launch patch failed in $ext_dir"
    return 1
  fi
}

# d2p_reapply_enabled_state — Force the three facts that make Dash-to-Panel the
#   active dock: org.gnome.shell disable-user-extensions=false, Dash-to-Panel in
#   enabled-extensions (and out of disabled-extensions), Ubuntu Dock out of
#   enabled-extensions (and in disabled-extensions). Safe to call at install
#   time and at graphical login; does not download, patch, or write layout keys.
#   Args: none. Returns: 0 (gsettings writes are best-effort).
d2p_reapply_enabled_state() {
  log "info" "Re-applying Dash-to-Panel enablement (kill switch off, $D2P_EXT_ID on, ubuntu-dock off)"
  if run_as_target gsettings set org.gnome.shell disable-user-extensions false 2>/dev/null; then
    log "info" "Cleared org.gnome.shell disable-user-extensions"
  else
    log "warn" "Could not clear org.gnome.shell disable-user-extensions"
  fi
  d2p_strv_edit add org.gnome.shell enabled-extensions "$D2P_EXT_ID"
  d2p_strv_edit remove org.gnome.shell enabled-extensions ubuntu-dock@ubuntu.com
  d2p_strv_edit remove org.gnome.shell disabled-extensions "$D2P_EXT_ID"
  d2p_strv_edit add org.gnome.shell disabled-extensions ubuntu-dock@ubuntu.com
}

# d2p_reapply_helper_path — Installed login-time helper path for TARGET_HOME.
d2p_reapply_helper_path() {
  printf '%s\n' "$TARGET_HOME/.local/libexec/linux-configuration-setup/reapply-dash-to-panel"
}

# d2p_reapply_unit_path — Installed systemd user unit path for TARGET_HOME.
d2p_reapply_unit_path() {
  printf '%s\n' "$TARGET_HOME/.config/systemd/user/dash-to-panel-reapply.service"
}

# d2p_install_login_reapply — Install and enable the graphical-login oneshot that
#   calls d2p_reapply_enabled_state. Substitutes the installing checkout into the
#   unit Environment=LCS_SCRIPT_DIR so the helper can source this library later.
#   Args: none. Returns: 0 on success, 1 when the helper/unit cannot be installed
#   or the user unit cannot be enabled.
d2p_install_login_reapply() {
  local libexec_dir unit_dir helper_src unit_src helper_dest unit_dest tmp_unit
  libexec_dir="$TARGET_HOME/.local/libexec/linux-configuration-setup"
  unit_dir="$TARGET_HOME/.config/systemd/user"
  helper_src="$SCRIPT_DIR/scripts/reapply_dash_to_panel.sh"
  unit_src="$SCRIPT_DIR/configs/systemd/dash-to-panel-reapply.service"
  helper_dest="$(d2p_reapply_helper_path)"
  unit_dest="$(d2p_reapply_unit_path)"

  log "info" "Installing Dash-to-Panel login re-apply ($unit_dest)"
  if [ ! -f "$helper_src" ] || [ ! -f "$unit_src" ]; then
    log "error" "Dash-to-Panel login re-apply sources missing ($helper_src, $unit_src)"
    return 1
  fi
  run_as_target install -d -m 0755 "$libexec_dir" || return 1
  run_as_target install -d -m 0755 "$unit_dir" || return 1
  run_as_target install -m 0755 "$helper_src" "$helper_dest" || return 1
  tmp_unit="$(mktemp)"
  python3 -c 'from pathlib import Path; import sys
src, dest, root = sys.argv[1:4]
Path(dest).write_text(Path(src).read_text().replace("@LCS_SCRIPT_DIR@", root))
' "$unit_src" "$tmp_unit" "$SCRIPT_DIR" || { rm -f "$tmp_unit"; return 1; }
  run_as_target install -m 0644 "$tmp_unit" "$unit_dest" || { rm -f "$tmp_unit"; return 1; }
  rm -f "$tmp_unit"
  if ! run_as_target systemctl --user daemon-reload; then
    log "error" "systemctl daemon-reload failed for dash-to-panel-reapply.service"
    return 1
  fi
  if ! run_as_target systemctl --user enable dash-to-panel-reapply.service; then
    log "error" "Could not enable dash-to-panel-reapply.service"
    return 1
  fi
  log "info" "Enabled dash-to-panel-reapply.service for graphical-session-pre.target"
}

# d2p_uninstall_login_reapply — Disable and remove the graphical-login oneshot.
#   Does not touch other files in ~/.local/libexec/linux-configuration-setup
#   (the passwordless keyring helper also lives there). Args: none. Returns: 0.
d2p_uninstall_login_reapply() {
  local helper_dest unit_dest
  helper_dest="$(d2p_reapply_helper_path)"
  unit_dest="$(d2p_reapply_unit_path)"
  log "info" "Removing Dash-to-Panel login re-apply ($unit_dest)"
  run_as_target systemctl --user disable --now dash-to-panel-reapply.service >/dev/null 2>&1 || true
  run_as_target rm -f "$helper_dest" "$unit_dest"
  run_as_target systemctl --user daemon-reload || true
}

# configure_dash_to_panel - install (if needed), enable, disable Ubuntu Dock, and
# apply the panel dconf defaults. Component entry point.
configure_dash_to_panel() {
  msg "Configuring Dash-to-Panel"
  # Always keep a user-owned source copy: this installer cannot safely patch a
  # root-owned system extension during a normal sudo-free configuration run.
  d2p_local_source_installed || d2p_download_install
  if ! d2p_local_source_installed; then
    msg "Dash-to-Panel install failed; leaving Ubuntu Dock enabled."
    return 0
  fi
  if ! d2p_apply_monitor_launch_patch "$(d2p_ext_dir)"; then
    msg "Dash-to-Panel source did not match the pinned v73 monitor-launch patch."
    return 1
  fi
  
  # Time-boxed, backgrounded D-Bus toggles so a slow/unresponsive shell can never
  # block the installer; persistent state is set via gsettings below.
  run_as_target sh -c 'timeout 5 gnome-extensions disable ubuntu-dock@ubuntu.com >/dev/null 2>&1 </dev/null &' || true
  run_as_target sh -c 'timeout 5 gnome-extensions enable "$1" >/dev/null 2>&1 </dev/null &' _ "$D2P_EXT_ID" || true
  
  d2p_reapply_enabled_state
  if ! d2p_install_login_reapply; then
    msg "Dash-to-Panel login re-apply hook failed to install; panel may not survive reboot."
    return 1
  fi
  
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
  d2p_uninstall_login_reapply
  run_as_target gnome-extensions disable "$D2P_EXT_ID" 2>/dev/null || true
  run_as_target rm -rf "$(d2p_ext_dir)"
  d2p_strv_edit remove org.gnome.shell enabled-extensions "$D2P_EXT_ID"
  d2p_strv_edit add org.gnome.shell disabled-extensions "$D2P_EXT_ID"
  run_as_target gnome-extensions enable ubuntu-dock@ubuntu.com 2>/dev/null || true
  d2p_strv_edit add org.gnome.shell enabled-extensions ubuntu-dock@ubuntu.com
  d2p_strv_edit remove org.gnome.shell disabled-extensions ubuntu-dock@ubuntu.com
}
