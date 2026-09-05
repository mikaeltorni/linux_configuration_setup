#!/usr/bin/env bash
# reapply_dash_to_panel.sh — Graphical-login Dash-to-Panel enablement.
#
# Installed to ~/.local/libexec/linux-configuration-setup/reapply-dash-to-panel
# and started by dash-to-panel-reapply.service (WantedBy=graphical-session-pre.target).
# Bootstraps a minimal installer environment and calls d2p_reapply_enabled_state
# so a reboot cannot leave org.gnome.shell disable-user-extensions true while
# Dash-to-Panel is already listed in enabled-extensions.
#
# LCS_SCRIPT_DIR is injected by d2p_install_login_reapply (the checkout that
# installed this helper). Fallbacks keep a standard projects clone working if
# the unit environment is missing.
set -u

: "${LCS_SCRIPT_DIR:=}"
_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$LCS_SCRIPT_DIR" ] || [ ! -f "$LCS_SCRIPT_DIR/lib/dash_to_panel.sh" ]; then
  if [ -f "$_HERE/../lib/dash_to_panel.sh" ]; then
    LCS_SCRIPT_DIR="$(cd "$_HERE/.." && pwd)"
  elif [ -f "${HOME}/projects/linux_configuration_setup/lib/dash_to_panel.sh" ]; then
    LCS_SCRIPT_DIR="${HOME}/projects/linux_configuration_setup"
  fi
fi

if [ -z "${LCS_SCRIPT_DIR:-}" ] || [ ! -f "$LCS_SCRIPT_DIR/lib/dash_to_panel.sh" ]; then
  printf 'reapply-dash-to-panel: cannot locate linux_configuration_setup checkout\n' >&2
  exit 1
fi

SCRIPT_DIR="$LCS_SCRIPT_DIR"
TARGET_USER="${TARGET_USER:-$(id -un)}"
TARGET_HOME="${TARGET_HOME:-$(getent passwd "$TARGET_USER" | cut -d: -f6)}"
TARGET_HOME="${TARGET_HOME:-$HOME}"

if ! declare -F run_as_target >/dev/null 2>&1; then
  run_as_target() { "$@"; }
fi
if ! declare -F msg >/dev/null 2>&1; then
  msg() { printf '%s\n' "$*" >&2; }
fi
if ! declare -F log >/dev/null 2>&1; then
  # shellcheck source=../lib/logging.sh
  source "$SCRIPT_DIR/lib/logging.sh"
fi
# shellcheck source=../lib/gsettings_helpers.sh
source "$SCRIPT_DIR/lib/gsettings_helpers.sh"
# shellcheck source=../lib/dash_to_panel.sh
source "$SCRIPT_DIR/lib/dash_to_panel.sh"

log "info" "Login re-apply for Dash-to-Panel from $SCRIPT_DIR"
d2p_reapply_enabled_state
