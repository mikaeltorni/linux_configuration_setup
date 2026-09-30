#!/usr/bin/env bash
# components.sh - Component manifest for linux_configuration_setup.
#
# Declares the selectable installer components for this repository and maps each
# to the step function (defined in lib/) that installs it. install.sh sources
# the lib files first, then this manifest, then drives everything through
# component_main from installer/component_runtime.sh.
#
# Entry format: "id|label|default(on/off)|function".
#
# Usage:
#   source "$SCRIPT_DIR/installer/components.sh"

ISC_REPO_NAME="linux_configuration_setup"
ISC_REPO_LABEL="GNOME desktop configuration"

# Run once before any selected component (ensures the user session bus).
ISC_PREFLIGHT="ensure_session_bus"

# Entry format: "id|label|default|function[|detect_fn[|uninstall_fn]]". Where a
# component omits the trailing fields, detection falls back to an install
# receipt and its [u] action clears that receipt (no live reversal): this is
# intentional for the keyring re-encryption and the shared/generated assets
# whose reversal would be ambiguous or risky.
ISC_COMPONENTS=(
  "rtc|Local-time RTC (dual-boot clock fix)|on|configure_rtc|detect_rtc|uninstall_rtc"
  "clock_calendar|Clock and calendar display|on|configure_clock_calendar|detect_clock_calendar|uninstall_clock_calendar"
  "disable_auto_lock|Disable screen auto-lock|on|configure_disable_auto_lock|detect_disable_auto_lock|uninstall_disable_auto_lock"
  "session_restart|Restart and power off without returning to the login screen|on|configure_session_restart|detect_session_restart|uninstall_session_restart"
  "passwordless_keyring|Prompt-free login keyring|on|configure_passwordless_keyring|detect_passwordless_keyring"
  "dark_mode|Color scheme and themes (dark default; DESKTOP_COLOR_SCHEME=light)|on|configure_dark_mode|detect_dark_mode|uninstall_dark_mode"
  "mouse_accel|Disable mouse acceleration|on|disable_mouse_acceleration|detect_mouse_accel|uninstall_mouse_accel"
  "hide_hotplug_joysticks|Hide Crosswind/test uinput from Xorg (NVIDIA lag)|on|configure_hide_hotplug_joysticks|detect_hide_hotplug_joysticks|uninstall_hide_hotplug_joysticks"
  "desktop_stall_capture|Log rare NVIDIA/input desktop stall episodes|on|configure_desktop_stall_capture|detect_desktop_stall_capture|uninstall_desktop_stall_capture"
  "seagate_mount|Mount Seagate-labelled disks at desktop login|on|configure_seagate_mount|detect_seagate_mount|uninstall_seagate_mount"
  "favorites|Dock favorite apps (override with FAVORITES_APPS)|on|configure_favorites|detect_favorites|uninstall_favorites"
  "cursor_theme|Purple cross cursor theme (override with CURSOR_SOURCE_FILE)|on|configure_purple_cross_default_cursor|detect_cursor_theme|uninstall_cursor_theme"
  "terminal_theme|Terminal dark theme|on|configure_terminal_dark_theme||uninstall_terminal_theme"
  "display_refresh|Display refresh rate / VRR|on|configure_display_refresh|detect_display_refresh|uninstall_display_refresh"
  "autostart_apps|General autostart applications|on|configure_autostart_apps|detect_autostart_apps|uninstall_autostart_apps"
  "selected_app_autostart|Master-selected app startup ([s] in app menu)|on|configure_selected_app_autostart|detect_selected_app_autostart|uninstall_selected_app_autostart"
  "kitty_defaults|Kitty terminal defaults|on|configure_kitty_defaults|detect_kitty_defaults|uninstall_kitty_defaults"
  "kitty_ignore_apostrophe|Ignore apostrophe input outside tmux (KITTY_IGNORE_APOSTROPHE=on/off)|on|configure_kitty_apostrophe_filter|detect_kitty_apostrophe_filter|uninstall_kitty_apostrophe_filter"
  "active_monitor_placement|Pin new windows to the active/pointer monitor (system-wide)|on|configure_active_monitor_placement|detect_active_monitor_placement|uninstall_active_monitor_placement"
  "uv_setup|UV package manager and supply-chain protection|on|configure_uv_autostart|detect_uv_setup|uninstall_uv_setup"
  "tmux_defaults|Tmux defaults with full chat history|on|configure_tmux_defaults|detect_tmux_defaults|uninstall_tmux_defaults"
  "dash_to_panel|Dash-to-Panel layout (replaces Ubuntu Dock)|on|configure_dash_to_panel|detect_dash_to_panel|uninstall_dash_to_panel"
)
