#!/usr/bin/env bash
# Exercise real desktop installer helpers with isolated files and Python trapped.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
TARGET_HOME="$fixture/home"
TARGET_USER="$(id -un)"
mkdir -p "$TARGET_HOME" "$fixture/bin"
printf '#!/bin/bash\nexit 95\n' > "$fixture/bin/python3"
printf '#!/bin/bash\nexit 0\n' > "$fixture/bin/systemctl"
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH"
# Ignore installer-only diagnostic output.
# Parameters: diagnostic tokens. Returns: zero.
msg() { :; }
# Ignore existing installer-only diagnostics.
# Parameters: diagnostic tokens. Returns: zero.
log() { :; }
# Invoke file operations directly in the isolated target paths.
# Parameters: command tokens. Returns: command status/output.
run_as_target() { "$@"; }
source "$SCRIPT_DIR/lib/kitty_input.sh"
source "$SCRIPT_DIR/lib/lifecycle.sh"
source "$SCRIPT_DIR/lib/desktop_stall.sh"
source "$SCRIPT_DIR/lib/dash_to_panel.sh"
for round in 1 2; do
  configure_kitty_apostrophe_filter
  detect_kitty_apostrophe_filter
  uninstall_kitty_apostrophe_filter
  if detect_kitty_apostrophe_filter; then exit 1; fi
  configure_desktop_stall_capture
  d2p_install_login_reapply
done
grep -Fq "$SCRIPT_DIR" "$(dsc_unit_path)"
grep -Fq "$SCRIPT_DIR" "$(d2p_reapply_unit_path)"
if rg -q '@LCS_SCRIPT_DIR@' "$(dsc_unit_path)" "$(d2p_reapply_unit_path)"; then exit 1; fi
printf '# personal\nfont_size 13\n# managed\nconfirm_os_window_close 0\n' > "$TARGET_HOME/.config/kitty/kitty.conf"
uninstall_kitty_defaults
[[ "$(cat "$TARGET_HOME/.config/kitty/kitty.conf")" == $'# personal\nfont_size 13' ]]
printf 'Native desktop file operations passed\n'
