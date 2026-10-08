#!/usr/bin/env bash
# Shared native command delivery for the desktop installer's file-edit callers.
LCS_DESKTOP_TOOLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Build the native command and install it for the target without rewriting Cargo HOME.
# Parameters: none; target runner/home are supplied by the existing installer.
# Returns: source binary path or build/target installation failure.
lcs_desktop_tools_program() {
  local program
  program="$(bash "$LCS_DESKTOP_TOOLS_ROOT/scripts/build_lcs_tools.sh" --bin desktop-config --print)" || return 1
  run_as_target install -D -m 0755 "$program" "$TARGET_HOME/.local/bin/desktop-config" || return $?
  printf '%s\n' "$program"
}
