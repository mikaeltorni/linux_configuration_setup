#!/usr/bin/env bash
# Probe GDM through the public native resolver without a runtime compiler.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
TARGET_HOME="$fixture/home"
mkdir -p "$TARGET_HOME"
# An installed native GDM query must work even without a runtime compiler.
# Parameters: command tokens. Returns: one for Cargo discovery, builtin status otherwise.
command() {
  [[ "$*" != '-v cargo' ]] || return 1
  builtin command "$@"
}
source "$SCRIPT_DIR/lib/x11_session.sh"
program="$(gdm_x11_program)"
[[ -x "$program" ]]
printf '[daemon]\nWaylandEnable=false\nXorgEnable=true\nPreferredDisplayServer=xorg\n' > "$fixture/custom.conf"
GDM_CUSTOM_CONF="$fixture/custom.conf" detect_x11_session
printf 'Compiler-free native GDM resolution passed\n'
