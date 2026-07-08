#!/usr/bin/env bash
# test_active_monitor_placement.sh — verify the active-monitor-placement component.
#
# Checks that the helper script exists, is valid bash, declares the expected
# functions, and that the component is declared in the manifest.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=========================================="
echo "  Active Monitor Placement Tests"
echo "=========================================="

echo ""
echo "--- helper script exists and is valid bash ---"
helper="$SCRIPT_DIR/scripts/pin-window-to-active-monitor.sh"
if [ -f "$helper" ]; then
  pass "helper script exists"
else
  fail "helper script exists"
  exit 1
fi
if bash -n "$helper" 2>/dev/null; then
  pass "helper script is valid bash"
else
  fail "helper script is valid bash"
fi
if [ -x "$helper" ] || [ "$(stat -c %a "$helper" 2>/dev/null || stat -f %Lp "$helper" 2>/dev/null)" = "755" ]; then
  pass "helper script is executable"
else
  fail "helper script is executable"
fi

echo ""
echo "--- helper script uses xdotool and xrandr ---"
source_text="$(cat "$helper")"
[[ "$source_text" == *"xdotool"* ]] && pass "references xdotool" || fail "references xdotool"
[[ "$source_text" == *"xrandr"* ]] && pass "references xrandr" || fail "references xrandr"
[[ "$source_text" == *"windowmove"* ]] && pass "uses xdotool windowmove" || fail "uses xdotool windowmove"
[[ "$source_text" == *"getmouselocation"* ]] && pass "uses pointer location" || fail "uses pointer location"

echo ""
echo "--- install library defines configure function ---"
lib_file="$SCRIPT_DIR/lib/active_monitor.sh"
if [ -f "$lib_file" ]; then
  pass "lib/active_monitor.sh exists"
else
  fail "lib/active_monitor.sh exists"
  exit 1
fi
lib_text="$(cat "$lib_file")"
[[ "$lib_text" == *"configure_active_monitor_placement()"* ]] && pass "configure function defined" || fail "configure function defined"

echo ""
echo "--- component is declared in manifest ---"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/installer/components.sh"
found=false
for entry in "${ISC_COMPONENTS[@]}"; do
  IFS='|' read -r id label default func detect uninstall _section <<<"$entry"
  if [ "$id" = "active_monitor_placement" ]; then
    found=true
    [ "$default" = "on" ] && pass "default is on" || fail "default is on (got '$default')"
    [ "$func" = "configure_active_monitor_placement" ] && pass "maps to configure function" || fail "maps to configure function"
    [ "$detect" = "detect_active_monitor_placement" ] && pass "maps to detect function" || fail "maps to detect function"
    [ "$uninstall" = "uninstall_active_monitor_placement" ] && pass "maps to uninstall function" || fail "maps to uninstall function"
    break
  fi
done
$found && pass "component found in manifest" || fail "component found in manifest"

echo ""
echo "--- lifecycle defines detect and uninstall ---"
lifecycle_text="$(cat "$SCRIPT_DIR/lib/lifecycle.sh")"
[[ "$lifecycle_text" == *"detect_active_monitor_placement()"* ]] && pass "detect function in lifecycle" || fail "detect function in lifecycle"
[[ "$lifecycle_text" == *"uninstall_active_monitor_placement()"* ]] && pass "uninstall function in lifecycle" || fail "uninstall function in lifecycle"

echo ""
echo "--- README documents the component ---"
readme="$SCRIPT_DIR/README.md"
grep -qF '`active_monitor_placement`' "$readme" && pass "README documents component" || fail "README documents component"
grep -qF 'pin-window-to-active-monitor' "$readme" && pass "README documents helper script" || fail "README documents helper script"

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
