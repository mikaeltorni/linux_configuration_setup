#!/usr/bin/env bash
# install.sh — Linux Configuration Setup (Phase 2 of 7)
#
# This installer configures:
#   - GNOME desktop settings (dark mode, favorites, cursor theme)
#   - System configuration (RTC, auto-lock, mouse acceleration)
#   - Terminal dark themes
#   - Display refresh rate / VRR
#   - Autostart applications (Spotify, GitKraken, EasyEffects)
#   - EasyEffects EQ presets
#   - Chrome PWA icons and desktop entries
#   - UV package manager setup
#   - Tmux defaults
#
# Usage: bash install.sh        # user-level config; root-only steps are skipped and reported
#        sudo bash install.sh   # full configuration including system-level steps

set -euo pipefail

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/configs"
RUNTIME_DIR="/run/user/${TARGET_UID}"
DISPLAY_VAL="${DISPLAY:-:0}"
USER_BUS="unix:path=${RUNTIME_DIR}/bus"
SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"

source "$SCRIPT_DIR/lib/helpers.sh"
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/gsettings_helpers.sh"
source "$SCRIPT_DIR/lib/system_config.sh"
source "$SCRIPT_DIR/lib/autostart.sh"
source "$SCRIPT_DIR/lib/gnome_desktop.sh"

INSTALLER_NO_REBOOT="${INSTALLER_NO_REBOOT:-0}"

main_inner() {
  ensure_session_bus

  msg "=== Linux Configuration Setup ==="
  
  # System-level configuration
  configure_rtc
  configure_clock_calendar
  configure_disable_auto_lock
  configure_dark_mode
  disable_mouse_acceleration
  
  # GNOME desktop configuration
  configure_favorites
  configure_purple_cross_default_cursor
  configure_terminal_dark_theme
  configure_display_refresh
  
  # Autostart applications
  configure_spotify_autostart
  configure_gitkraken_autostart
  configure_autostart_apps
  configure_easyeffects_autostart
  
  # Chrome PWA icons
  configure_pwa_icons
  configure_monkeytype_autostart
  configure_app_rules_extension

  # UV package manager
  configure_uv_autostart
  
  # Tmux defaults
  configure_tmux_defaults

  report_sudo_required
  msg "=== Linux Configuration Setup Complete ==="
}

run_and_log_with_reboot() {
  local ts log_dir log_file
  ts=$(date +"%Y%m%d-%H%M%S")
  log_dir="$SCRIPT_DIR/.log"
  mkdir -p "$log_dir"
  log_file="$log_dir/linux_configuration_setup-$ts.log"
  
  main_inner "$@" 2>&1 | tee "$log_file"
  msg "All done. Log file written to: $log_file"
  
  if [[ "${INSTALLER_NO_REBOOT:-0}" == "1" ]]; then
    msg "Skipping reboot due to INSTALLER_NO_REBOOT=1"
  else
    msg "Configuration applied. No reboot required."
    msg "Log out and back in for GNOME Shell extension changes to take effect."
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_and_log_with_reboot "$@"
fi
