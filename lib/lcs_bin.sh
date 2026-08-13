#!/usr/bin/env bash
# lcs_bin.sh — Resolve and invoke the lcs-tools Rust helper.
#
# Sourced by installer libraries after SCRIPT_DIR is set. Builds the binary on
# demand via scripts/build_lcs_tools.sh.
#
# Public functions:
#   ensure_lcs_bin  — build/locate dist/lcs-tools; sets LCS_BIN
#   lcs_bin         — ensure_lcs_bin then run it with "$@"

# ensure_lcs_bin — Locate or build dist/lcs-tools; export LCS_BIN.
ensure_lcs_bin() {
  local build_script bin root
  root="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  build_script="$root/scripts/build_lcs_tools.sh"
  if [ -n "${LCS_BIN:-}" ] && [ -x "$LCS_BIN" ]; then
    return 0
  fi
  if [ ! -x "$build_script" ]; then
    if declare -F msg >/dev/null 2>&1; then
      msg "Missing build helper: $build_script"
    else
      printf 'Missing build helper: %s\n' "$build_script" >&2
    fi
    return 1
  fi
  bin="$(bash "$build_script" --print)" || return 1
  LCS_BIN="$bin"
  export LCS_BIN
}

# lcs_bin — Run the helper CLI.
lcs_bin() {
  ensure_lcs_bin || return 1
  "$LCS_BIN" "$@"
}
