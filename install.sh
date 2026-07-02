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
source "$SCRIPT_DIR/lib/dash_to_panel.sh"
source "$SCRIPT_DIR/lib/lifecycle.sh"

isc_activate_components
source "$SCRIPT_DIR/installer/components.sh"

INSTALLER_NO_REBOOT="${INSTALLER_NO_REBOOT:-0}"

main_inner() {
  msg "=== Linux Configuration Setup ==="
  
  # Feature-specific installation support (--features=feature1,feature2,...)
  SELECTED_FEATURES="${FEATURES:-}"
  
  if [ -n "$SELECTED_FEATURES" ]; then
    IFS="," read -ra FEATURE_ARRAY <<< "$SELECTED_FEATURES"
    msg "Feature filter active: ${FEATURE_ARRAY[*]}"
    
    # Build filtered component selection based on FEATURES
    local select_arg=""
    for arg in "$@"; do
      if [[ "${arg}" == --select=* ]]; then
        local selected_components="${arg#--select=}"
        local filtered="" first=true
        
        for comp_id in ${selected_components}; do
          for feature in "${FEATURE_ARRAY[@]}"; do  
            if [ "$comp_id" = "$feature" ]; then
              if $first; then filtered="$comp_id"; first=false; else filtered="$filtered,$comp_id"; fi  
              break
            fi  
          done  
        done
        
        select_arg="--select=$filtered"
        break
      fi
    done
    
    # If no specific --select, use feature list directly as component IDs  
    if [ -z "$select_arg" ]; then
      local features_as_components="" first=true
      for feature in "${FEATURE_ARRAY[@]}"; do
        if $first; then features_as_components="$feature"; first=false; else features_as_components="$features_as_components,$feature"; fi
      done
      select_arg="--select=$features_as_components"
    fi
    
    component_main "$select_arg"  
  else
    msg "Installing all configured components"
    component_main "$@"
  fi
  
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
