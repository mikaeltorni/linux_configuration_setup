#!/usr/bin/env bash
# test_desktop_stall_capture.sh — classify/dump logic for stall episode capture.
# Run with: bash tests/test_desktop_stall_capture.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/desktop_stall_capture.sh"

passed=0
failed=0

check() {
  local description="$1"
  shift
  echo -n "  $description... "
  if "$@"; then
    echo PASS
    passed=$((passed + 1))
  else
    echo FAIL
    failed=$((failed + 1))
  fi
}

dfp_loop_dumps_once_over_threshold() {
  local tmp
  tmp="$(mktemp -d)"
  (
    STALL_STATE_DIR="$tmp"
    STATE_DIR="$tmp"
    EPISODE_DIR="$tmp/episodes"
    LOG_FILE="$tmp/stall.log"
    COOLDOWN_SEC=0
    DFP_THRESHOLD=5
    DFP_SECOND=""
    DFP_COUNT=0
    LAST_DUMP_EPOCH=0
    mkdir -p "$EPISODE_DIR"
    dump_episode() { printf '%s\n' "$1" >>"$tmp/reasons"; }
    local i
    for i in 1 2 3 4 5 6; do
      process_journal_line "2026-09-15T11:44:28+03:00 host NVIDIA(GPU-0): Samsung (DFP-0): connected"
    done
    grep -q "dfp_probe_loop" "$tmp/reasons"
  )
  local status=$?
  rm -rf "$tmp"
  return "$status"
}

interceptor_hotplug_dumps() {
  local tmp
  tmp="$(mktemp -d)"
  (
    STALL_STATE_DIR="$tmp"
    STATE_DIR="$tmp"
    EPISODE_DIR="$tmp/episodes"
    LOG_FILE="$tmp/stall.log"
    COOLDOWN_SEC=0
    LAST_DUMP_EPOCH=0
    dump_episode() { printf '%s\n' "$1" >>"$tmp/reasons"; }
    process_journal_line "2026-09-15T11:44:07+03:00 host (II) config/udev: Adding input device section-interceptor (/dev/input/event256)"
    grep -qx "pa_uinput_hotplug" "$tmp/reasons"
  )
  local status=$?
  rm -rf "$tmp"
  return "$status"
}

dump_now_writes_episode_file() {
  local tmp
  tmp="$(mktemp -d)"
  STALL_STATE_DIR="$tmp" STATE_DIR="$tmp" EPISODE_DIR="$tmp/episodes" \
    LOG_FILE="$tmp/stall.log" COOLDOWN_SEC=0 LAST_DUMP_EPOCH=0 \
    "$ROOT_DIR/scripts/desktop_stall_capture.sh" --dump-now "unit-test"
  local count
  count="$(find "$tmp/episodes" -type f | wc -l)"
  latest="$(readlink "$tmp/latest.txt" 2>/dev/null || true)"
  rm -rf "$tmp"
  [ "$count" -ge 1 ] && [[ "$latest" == episodes/* ]]
}

check "DFP loop at threshold dumps an episode" dfp_loop_dumps_once_over_threshold
check "interceptor udev add dumps an episode" interceptor_hotplug_dumps
check "--dump-now writes an episode file" dump_now_writes_episode_file

echo
echo "Results: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
