#!/usr/bin/env bash
# install.sh — Linux Configuration Setup (Phase 2 of 7)
set -euo pipefail

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_HOME="${TARGET_HOME_OVERRIDE:-$(getent passwd "$TARGET_USER" | cut -d: -f6)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/configs"
RUNTIME_DIR="/run/user/${TARGET_UID}"
DISPLAY_VAL="${DISPLAY:-:0}"
USER_BUS="unix:path=${RUNTIME_DIR}/bus"
SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"

source "$SCRIPT_DIR/lib/logging.sh"

for __isc_d in "${ISC_FUNCTIONS_DIR:-}" \
               "$SCRIPT_DIR/../linux_installation_scripts_functions" \
               "$HOME/projects/linux_installation_scripts_functions"; do
  [ -n "$__isc_d" ] && [ -f "$__isc_d/component_loader.sh" ] && { source "$__isc_d/component_loader.sh"; break; }
done
if ! declare -F isc_load_helpers >/dev/null 2>&1; then
  __isc_framework_ref="${ISC_FUNCTIONS_REF:-master}"
  __isc_framework_key="${__isc_framework_ref//\//_}"
  __isc_framework_cache="${XDG_CACHE_HOME:-$HOME/.cache}/installation_scripts/framework-${__isc_framework_key}"
  __isc_framework_loader="$__isc_framework_cache/component_loader.sh"
  if [[ ! -f "$__isc_framework_loader" ]]; then
    command -v git >/dev/null 2>&1 || { log error 'git is required to download the shared installer framework'; exit 1; }
    __isc_framework_parent="${__isc_framework_cache%/*}"
    mkdir -p "$__isc_framework_parent"
    __isc_framework_tmp="$(mktemp -d "$__isc_framework_parent/.framework-${__isc_framework_key}.XXXXXX")"
    log info "cloning shared installer framework ref $__isc_framework_ref for standalone installation"
    if ! GIT_TERMINAL_PROMPT=0 git clone --quiet --depth 1 --single-branch \
      --branch "$__isc_framework_ref" \
      https://github.com/mikaeltorni/linux_installation_scripts_functions.git \
      "$__isc_framework_tmp/repository"; then
      log error 'could not clone the shared installer framework; check GitHub access'
      exit 1
    fi
    if [[ ! -e "$__isc_framework_cache" ]] && mv "$__isc_framework_tmp/repository" "$__isc_framework_cache"; then
      rmdir "$__isc_framework_tmp" 2>/dev/null || true
    else
      __isc_framework_loader="$__isc_framework_tmp/repository/component_loader.sh"
    fi
  fi
  ISC_FUNCTIONS_DIR="${__isc_framework_loader%/*}"
  export ISC_FUNCTIONS_DIR
  source "$__isc_framework_loader"
fi
isc_load_helpers

source "$SCRIPT_DIR/lib/helpers.sh"
source "$SCRIPT_DIR/lib/gsettings_helpers.sh"  
source "$SCRIPT_DIR/lib/system_config.sh"
source "$SCRIPT_DIR/lib/log_retention.sh"
source "$SCRIPT_DIR/lib/x11_session.sh"
source "$SCRIPT_DIR/lib/keyring.sh"
source "$SCRIPT_DIR/lib/autostart.sh"
source "$SCRIPT_DIR/lib/kitty_input.sh"
source "$SCRIPT_DIR/lib/gnome_desktop.sh"
source "$SCRIPT_DIR/lib/active_monitor.sh"
source "$SCRIPT_DIR/lib/cursor_theme.sh"
source "$SCRIPT_DIR/lib/dash_to_panel.sh"
source "$SCRIPT_DIR/lib/desktop_stall.sh"
source "$SCRIPT_DIR/lib/seagate_mount.sh"
source "$SCRIPT_DIR/lib/lifecycle.sh"

isc_activate_components
source "$SCRIPT_DIR/installer/components.sh"

INSTALLER_NO_REBOOT="${INSTALLER_NO_REBOOT:-0}"

main_inner() {
  msg "=== Linux Configuration Setup ==="
  msg "Installing all configured components"
  component_main "$@"
  local rc=$?
  report_sudo_required
  msg "=== Linux Configuration Setup Complete ==="
  return $rc
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
  case "${1:-}" in
    --list-selected-startup-apps) list_selected_app_autostart; exit $? ;;
  esac
  if isc_route_readonly_args "$@"; then exit $?; fi
  run_and_log_with_reboot "$@"
fi
