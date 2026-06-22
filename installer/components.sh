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

ISC_COMPONENTS=(
  "rtc|Local-time RTC (dual-boot clock fix)|on|configure_rtc"
  "clock_calendar|Clock and calendar display|on|configure_clock_calendar"
  "disable_auto_lock|Disable screen auto-lock|on|configure_disable_auto_lock"
  "passwordless_keyring|Prompt-free login keyring|on|configure_passwordless_keyring"
  "dark_mode|Dark mode and themes|on|configure_dark_mode"
  "mouse_accel|Disable mouse acceleration|on|disable_mouse_acceleration"
  "favorites|Dock favorite apps|on|configure_favorites"
  "cursor_theme|Purple cross cursor theme|on|configure_purple_cross_default_cursor"
  "terminal_theme|Terminal dark theme|on|configure_terminal_dark_theme"
  "display_refresh|Display refresh rate / VRR|on|configure_display_refresh"
  "spotify_autostart|Spotify autostart|on|configure_spotify_autostart"
  "gitkraken_autostart|GitKraken autostart|on|configure_gitkraken_autostart"
  "autostart_apps|General autostart applications|on|configure_autostart_apps"
  "kitty_defaults|Kitty terminal defaults|on|configure_kitty_defaults"
  "easyeffects|EasyEffects autostart and EQ presets|on|configure_easyeffects_autostart"
  "pwa_icons|Chrome PWA icons and desktop entries|on|configure_pwa_icons"
  "monkeytype_autostart|Monkeytype autostart|on|configure_monkeytype_autostart"
  "app_rules|App window rules extension|on|configure_app_rules_extension"
  "uv_setup|UV package manager setup|on|configure_uv_autostart"
  "tmux_defaults|Tmux defaults|on|configure_tmux_defaults"
)
