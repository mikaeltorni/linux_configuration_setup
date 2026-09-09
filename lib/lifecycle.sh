#!/usr/bin/env bash
# lifecycle.sh - Detection and uninstall functions for linux_configuration_setup.
#
# detect_* report live desktop state for --detect; uninstall_* reverse a setting
# to its GNOME default (gsettings reset) or remove the file/extension the
# component installed. Components whose reversal is ambiguous or risky (the
# passwordless keyring re-encryption and the shared kitty.conf) deliberately
# ship no uninstall function here and fall back to the runtime's receipt-clear;
# detection still works via their receipt.
#
# All gsettings reads/writes go through run_as_target so they act on the target
# user's session whether the installer runs as that user or via sudo.

cfg_get() { run_as_target gsettings get "$1" "$2" 2>/dev/null; }
cfg_reset() { run_as_target gsettings reset "$1" "$2" 2>/dev/null || true; }

# --- Detection ---------------------------------------------------------------
detect_rtc() {
  local v; v="$(timedatectl show -p LocalRTC --value 2>/dev/null)"; [ "$v" = "yes" ]
}
detect_clock_calendar()    { [ "$(cfg_get org.gnome.desktop.interface clock-show-weekday)" = "true" ]; }
detect_disable_auto_lock() { [ "$(cfg_get org.gnome.desktop.screensaver lock-enabled)" = "false" ]; }
detect_passwordless_keyring() { [ -d "$TARGET_HOME/.local/state/linux-configuration-setup" ]; }
detect_dark_mode()         { [ "$(cfg_get org.gnome.desktop.interface color-scheme)" = "'prefer-dark'" ]; }
detect_mouse_accel()       { [ "$(cfg_get org.gnome.desktop.peripherals.mouse accel-profile)" = "'flat'" ]; }
detect_favorites()         { local v; v="$(cfg_get org.gnome.shell favorite-apps)"; [ -n "$v" ] && [ "$v" != "@as []" ] && [ "$v" != "[]" ]; }
detect_cursor_theme()      { local v; v="$(cfg_get org.gnome.desktop.interface cursor-theme)"; [ -n "$v" ] && [ "$v" != "'Adwaita'" ] && [ "$v" != "'Yaru'" ]; }
detect_display_refresh()   { local v; v="$(cfg_get org.gnome.mutter experimental-features)"; [ -n "$v" ] && [ "$v" != "@as []" ] && [ "$v" != "[]" ]; }
detect_autostart_apps()    { [ -f "$TARGET_HOME/.local/bin/autostart_apps.sh" ]; }
detect_selected_app_autostart() { [ -f "$TARGET_HOME/.local/state/linux-configuration-setup/selected-app-autostart.list" ]; }
# Helper CLI plus the session-wide extension both constitute the fix.
detect_active_monitor_placement() {
  [ -f "$TARGET_HOME/.local/bin/pin-window-to-active-monitor.sh" ] &&
    [ -d "$TARGET_HOME/.local/share/gnome-shell/extensions/active-monitor-placement@local" ] &&
    [ -f "$TARGET_HOME/.local/share/gnome-shell/extensions/active-monitor-placement@local/placementPolicy.js" ]
}
detect_uv_setup()          { [ -x "$TARGET_HOME/.local/bin/uv" ] && [ -f "$TARGET_HOME/.config/uv/uv.toml" ] && [ ! -e "$TARGET_HOME/.config/autostart/uv-python.desktop" ]; }
detect_tmux_defaults()     { [ -f "$TARGET_HOME/.tmux.conf" ]; }

# --- Uninstall ---------------------------------------------------------------
uninstall_rtc() {
  if [ "$(id -u)" -ne 0 ]; then msg "SKIP (requires sudo): timedatectl set-local-rtc 0"; return 0; fi
  msg "Restoring UTC hardware clock"; timedatectl set-local-rtc 0 2>/dev/null || true
}
uninstall_clock_calendar() {
  msg "Resetting clock/calendar display"
  cfg_reset org.gnome.desktop.interface clock-show-weekday
  cfg_reset org.gnome.desktop.interface clock-show-date
}
uninstall_disable_auto_lock() {
  msg "Re-enabling screen auto-lock defaults"
  cfg_reset org.gnome.desktop.session idle-delay
  cfg_reset org.gnome.desktop.screensaver lock-enabled
  cfg_reset org.gnome.desktop.screensaver idle-activation-enabled
}
uninstall_dark_mode() {
  msg "Resetting color scheme and themes to default"
  cfg_reset org.gnome.desktop.interface color-scheme
  cfg_reset org.gnome.desktop.interface gtk-theme
  cfg_reset org.gnome.desktop.interface icon-theme
}
uninstall_mouse_accel() {
  msg "Restoring default mouse acceleration"
  cfg_reset org.gnome.desktop.peripherals.mouse accel-profile
  cfg_reset org.gnome.desktop.peripherals.mouse speed
  cfg_reset org.gnome.desktop.peripherals.touchpad accel-profile
  cfg_reset org.gnome.desktop.peripherals.touchpad speed
}
uninstall_favorites()      { msg "Resetting dock favorites"; cfg_reset org.gnome.shell favorite-apps; }
uninstall_cursor_theme()   { msg "Resetting cursor theme"; cfg_reset org.gnome.desktop.interface cursor-theme; }
uninstall_display_refresh(){ msg "Resetting display experimental features"; cfg_reset org.gnome.mutter experimental-features; }
uninstall_autostart_apps() { msg "Removing autostart apps helper"; run_as_target rm -f "$TARGET_HOME/.local/bin/autostart_apps.sh"; }
uninstall_selected_app_autostart() {
  local state_file="$TARGET_HOME/.local/state/linux-configuration-setup/selected-app-autostart.list"
  local basename
  msg "Removing selected application startup entries"
  if [ -f "$state_file" ]; then
    while IFS= read -r basename; do
      [[ "$basename" == *.desktop && "$basename" != */* ]] || continue
      run_as_target rm -f "$TARGET_HOME/.config/autostart/$basename"
    done <"$state_file"
  fi
  run_as_target rm -f "$state_file" "$state_file.pending"
  log "info" "Removed tracked selected application startup entries"
}
# Compatibility no-op: old receipts must never remove another owner's files.
uninstall_app_rules() {
  msg "App rules are owned by linux_workspaces_setup; keeping installed files unchanged."
}
uninstall_active_monitor_placement() {
  msg "Removing active-monitor placement helper and extension"
  run_as_target rm -f "$TARGET_HOME/.local/bin/pin-window-to-active-monitor.sh"
  run_as_target gnome-extensions disable active-monitor-placement@local 2>/dev/null || true
  run_as_target rm -rf "$TARGET_HOME/.local/share/gnome-shell/extensions/active-monitor-placement@local"
  # Drop from enabled-extensions when gsettings is available (best-effort).
  if ! declare -F strv_edit >/dev/null 2>&1; then
    # shellcheck source=gsettings_helpers.sh
    source "$SCRIPT_DIR/lib/gsettings_helpers.sh"
  fi
  strv_edit remove org.gnome.shell enabled-extensions active-monitor-placement@local
}
uninstall_uv_setup()       { msg "Removing UV configuration"; run_as_target rm -f "$TARGET_HOME/.config/autostart/uv-python.desktop" "$TARGET_HOME/.config/uv/uv.toml"; }
uninstall_tmux_defaults()  { msg "Removing tmux defaults"; run_as_target rm -f "$TARGET_HOME/.tmux.conf"; }

# uninstall_terminal_theme — Reset every key configure_terminal_dark_theme set.
#   Each terminal is reset back to its own schema default (never to a second
#   hardcoded theme), so the desktop decides the colors again. Keys and
#   profiles that do not exist on this machine are skipped, exactly as the
#   configure step skips them.
#   Args: none. Returns: 0.
uninstall_terminal_theme() {
  msg "Resetting terminal theme to the desktop defaults"
  cfg_reset org.gnome.Console theme
  cfg_reset org.gnome.Ptyxis interface-style

  local ptyxis_profile="" profile_id="" schema=""
  if gsettings_key_exists org.gnome.Ptyxis default-profile-uuid; then
    ptyxis_profile="$(user_gsettings get org.gnome.Ptyxis default-profile-uuid 2>/dev/null || true)"
  fi
  ptyxis_profile="${ptyxis_profile//\'/}"
  if [ -n "$ptyxis_profile" ]; then
    for schema in "org.gnome.Ptyxis.Profile:/org/gnome/ptyxis/profiles/${ptyxis_profile}/" \
                  "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/${ptyxis_profile}/"; do
      cfg_reset "$schema" bold-is-bright
      cfg_reset "$schema" palette
    done
  fi

  if gsettings_key_exists org.gnome.Terminal.ProfilesList default; then
    profile_id="$(user_gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null || true)"
  fi
  profile_id="${profile_id//\'/}"
  if [ -n "$profile_id" ]; then
    schema="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${profile_id}/"
    cfg_reset "$schema" use-theme-colors
    cfg_reset "$schema" background-color
    cfg_reset "$schema" foreground-color
    cfg_reset "$schema" bold-color-same-as-fg
  fi
}

# kitty_managed_keys — Print the kitty.conf settings this repo manages.
#   One key per line; used by both the detector and the uninstall step so the
#   two can never drift from configure_kitty_defaults.
#   Args: none. Returns: 0.
kitty_managed_keys() {
  printf '%s\n' confirm_os_window_close "map ctrl+backspace" wayland_titlebar_color
}

# detect_kitty_defaults — True when every managed kitty.conf setting is present.
#   Args: none. Returns: 0 when all managed keys are set, 1 otherwise.
detect_kitty_defaults() {
  local conf="$TARGET_HOME/.config/kitty/kitty.conf" key
  [ -f "$conf" ] || return 1
  while read -r key; do
    grep -q "^${key}" "$conf" || return 1
  done < <(kitty_managed_keys)
  return 0
}

# uninstall_kitty_defaults — Drop the managed settings from kitty.conf.
#   Only the lines this repo writes (and the comment line each one is preceded
#   by) are removed; every other customization in the user's kitty.conf is kept,
#   and the file itself is never deleted.
#   Args: none. Returns: 0.
uninstall_kitty_defaults() {
  local conf="$TARGET_HOME/.config/kitty/kitty.conf"
  msg "Removing managed Kitty defaults from kitty.conf"
  run_as_target test -f "$conf" || return 0
  run_as_target python3 - "$conf" <<'PY'
"""Strip the installer-managed kitty settings, keeping user content intact."""
import sys

MANAGED = (
    "confirm_os_window_close",
    "map ctrl+backspace",
    "wayland_titlebar_color",
)
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    lines = handle.read().splitlines()

kept: list[str] = []
for line in lines:
    if line.startswith(MANAGED):
        # Drop the comment block written directly above the managed setting.
        while kept and kept[-1].startswith("#"):
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
