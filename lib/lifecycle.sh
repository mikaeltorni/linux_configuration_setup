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
detect_app_rules()         { [ -d "$TARGET_HOME/.local/share/gnome-shell/extensions/app-rules@local" ]; }
detect_uv_setup()          { [ -x "$TARGET_HOME/.local/bin/uv" ] && [ ! -e "$TARGET_HOME/.config/autostart/uv-python.desktop" ]; }
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
uninstall_app_rules() {
  msg "Removing app-rules GNOME extension"
  run_as_target gnome-extensions disable app-rules@local 2>/dev/null || true
  run_as_target rm -rf "$TARGET_HOME/.local/share/gnome-shell/extensions/app-rules@local"
}
uninstall_uv_setup()       { msg "Removing UV GUI autostart marker"; run_as_target rm -f "$TARGET_HOME/.config/autostart/uv-python.desktop"; }
uninstall_tmux_defaults()  { msg "Removing tmux defaults"; run_as_target rm -f "$TARGET_HOME/.tmux.conf"; }
