#!/usr/bin/env bash
# install.sh — Linux Configuration Setup (Phase 2 of 7)
#
# This installer configures:
#   - GNOME desktop settings (dark mode, favorites, cursor theme)
#   - System configuration (RTC, auto-lock, mouse acceleration)
#   - Terminal dark themes
#   - Display refresh rate / VRR
#   - Autostart applications (Spotify, GitKraken, EasyEffects)
#   - EasyEffects EQ preset (bundled or user-supplied via EASYEFFECTS_EQ_FILE)
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

source "$SCRIPT_DIR/lib/logging.sh"

# Load the shared installer framework + shared install-time helpers (single
# source of truth in linux_installation_scripts_functions) before any library or
# step uses run_as_target/msg/apt_install. No vendored copy: resolve a sibling
# checkout or download on demand.
for __isc_d in "${ISC_FUNCTIONS_DIR:-}" \
               "$SCRIPT_DIR/../linux_installation_scripts_functions" \
               "$HOME/projects/linux_installation_scripts_functions"; do
  [ -n "$__isc_d" ] && [ -f "$__isc_d/component_loader.sh" ] && { source "$__isc_d/component_loader.sh"; break; }
done
declare -F isc_load_helpers >/dev/null 2>&1 || \
  source <(curl -fsSL "https://raw.githubusercontent.com/mikaeltorni/linux_installation_scripts_functions/${ISC_FUNCTIONS_REF:-master}/component_loader.sh")
isc_load_helpers

source "$SCRIPT_DIR/lib/helpers.sh"
source "$SCRIPT_DIR/lib/gsettings_helpers.sh"
source "$SCRIPT_DIR/lib/system_config.sh"
source "$SCRIPT_DIR/lib/keyring.sh"
source "$SCRIPT_DIR/lib/autostart.sh"
source "$SCRIPT_DIR/lib/gnome_desktop.sh"
source "$SCRIPT_DIR/lib/cursor_theme.sh"
source "$SCRIPT_DIR/lib/pwa_icons.sh"
source "$SCRIPT_DIR/lib/dash_to_panel.sh"
source "$SCRIPT_DIR/lib/lifecycle.sh"

# Component selection runtime and this repository's component manifest. The
# runtime provides --list-components / --select / --default / interactive
# selection; the manifest maps each component id to a configure_* step above. The
# framework was already resolved above (for isc_load_helpers); activate the
# component runtime from the same checkout.
isc_activate_components
source "$SCRIPT_DIR/installer/components.sh"

INSTALLER_NO_REBOOT="${INSTALLER_NO_REBOOT:-0}"

# main_inner — Run the selected configuration components. Selection is resolved
# by component_main (interactive menu, --select, --default, or defaults when not
# on a TTY). report_sudo_required summarizes any skipped root-only steps.
main_inner() {
  msg "=== Linux Configuration Setup ==="
  component_main "$@"
  local rc=$?
  report_sudo_required
  msg "=== Linux Configuration Setup Complete ==="
  return $rc
}

# run_and_log_with_reboot — Run main_inner, tee all output to a timestamped log
#   under SCRIPT_DIR/.log, and print the final reboot/log-out guidance.
#   Args: $@ — arguments forwarded to main_inner (component selection flags).
#   Returns: 0 (the log file is always written; reboot is never performed).
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
  # Listing/help must print only their output (the master installer parses
  # --list-components), so bypass the logging/reboot wrapper for those.
  case "${1:-}" in
    --list-components|--detect|--help|-h|--uninstall|--uninstall=*) component_main "$@"; exit $? ;;
  esac
  run_and_log_with_reboot "$@"
fi
