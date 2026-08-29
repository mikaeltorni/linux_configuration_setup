#!/usr/bin/env bash
# test_active_monitor_placement.sh — verify active-monitor placement (policy + install).
#
# Drives the shipped placementPolicy.js decision function (no re-implementation
# oracle) and the component's configure/detect/uninstall contract against a
# temporary TARGET_HOME.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT_DIR="$SCRIPT_DIR/configs/gnome-extensions/active-monitor-placement@local"
POLICY_JS="$EXT_DIR/placementPolicy.js"

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
echo "--- extension source artifacts ---"
[ -d "$EXT_DIR" ] && pass "extension directory exists" || fail "extension directory exists"
[ -f "$EXT_DIR/extension.js" ] && pass "extension.js exists" || fail "extension.js exists"
[ -f "$EXT_DIR/metadata.json" ] && pass "metadata.json exists" || fail "metadata.json exists"
[ -f "$POLICY_JS" ] && pass "placementPolicy.js exists" || fail "placementPolicy.js exists"
if [ -f "$EXT_DIR/metadata.json" ]; then
  grep -qF 'active-monitor-placement@local' "$EXT_DIR/metadata.json" \
    && pass "metadata uuid is active-monitor-placement@local" \
    || fail "metadata uuid is active-monitor-placement@local"
fi
if [ -f "$EXT_DIR/extension.js" ]; then
  grep -qF 'placementPolicy.js' "$EXT_DIR/extension.js" \
    && pass "extension imports placementPolicy.js" \
    || fail "extension imports placementPolicy.js"
  grep -qF 'window-created' "$EXT_DIR/extension.js" \
    && pass "extension listens for window-created" \
    || fail "extension listens for window-created"
  grep -qF 'move_to_monitor' "$EXT_DIR/extension.js" \
    && pass "extension calls move_to_monitor" \
    || fail "extension calls move_to_monitor"
  grep -qF 'decideActiveMonitorPlacement' "$EXT_DIR/extension.js" \
    && pass "extension uses shipped decideActiveMonitorPlacement" \
    || fail "extension uses shipped decideActiveMonitorPlacement"
  grep -qF 'freezeTargetMonitor' "$EXT_DIR/extension.js" \
    && pass "extension uses freezeTargetMonitor for stable target" \
    || fail "extension uses freezeTargetMonitor for stable target"
  grep -qF 'shouldStopPlacementRechecks' "$EXT_DIR/extension.js" \
    && pass "extension uses shouldStopPlacementRechecks" \
    || fail "extension uses shouldStopPlacementRechecks"
  grep -qF "outcome === 'moved' || outcome === 'settled'" "$EXT_DIR/extension.js" \
    && pass "extension marks corrected on moved or settled" \
    || fail "extension marks corrected on moved or settled"
  grep -qF 'isWindowMoveSafe' "$EXT_DIR/extension.js" \
    && pass "extension gates moves with isWindowMoveSafe" \
    || fail "extension gates moves with isWindowMoveSafe"
  grep -qF 'get_compositor_private' "$EXT_DIR/extension.js" \
    && pass "extension requires mapped compositor actor" \
    || fail "extension requires mapped compositor actor"
  grep -qF 'snapshot target monitor' "$EXT_DIR/extension.js" \
    && pass "extension snapshots target at schedule" \
    || fail "extension snapshots target at schedule"
  # Rechecks must apply the frozen target, not re-resolve live pointer each phase.
  if grep -qF 'applyPlacement(win, `delay-${delayMs}`, frozenTarget)' "$EXT_DIR/extension.js"; then
    pass "rechecks pass frozenTarget into applyPlacement"
  else
    fail "rechecks pass frozenTarget into applyPlacement"
  fi
  # applyPlacement must not call resolveActiveMonitor (would re-chase pointer).
  if awk '/^function applyPlacement/,/^function |^export /' "$EXT_DIR/extension.js" \
      | grep -q 'resolveActiveMonitor'; then
    fail "applyPlacement must not re-resolve active monitor live"
  else
    pass "applyPlacement does not re-resolve active monitor live"
  fi
  if grep -qF 'const BUILTIN_FIXED_MONITOR_APP_IDS' "$EXT_DIR/extension.js" && \
     grep -qF "'smartgit.desktop'" "$EXT_DIR/extension.js"; then
    pass "active-monitor-placement leaves SmartGit's fixed monitor alone"
  else
    fail "active-monitor-placement leaves SmartGit's fixed monitor alone"
  fi
fi

echo ""
echo "--- shipped placementPolicy decision logic (real unit under test) ---"
# Drive the real exported function; assert move only when monitors differ and
# the window is a normal candidate. No hardcoded always-pass.
if [ ! -f "$POLICY_JS" ]; then
  fail "cannot run policy tests without placementPolicy.js"
else
  policy_out="$(
    ACTIVE_MONITOR_POLICY_JS="$POLICY_JS" node --input-type=module <<'NODE'
import { pathToFileURL } from 'node:url';
import process from 'node:process';

const policyPath = process.env.ACTIVE_MONITOR_POLICY_JS;
if (!policyPath) {
  console.error('MISSING_POLICY_PATH');
  process.exit(2);
}
const mod = await import(pathToFileURL(policyPath).href);
const decide = mod.decideActiveMonitorPlacement;
const freeze = mod.freezeTargetMonitor;
const shouldStop = mod.shouldStopPlacementRechecks;
if (typeof decide !== 'function') {
  console.error('MISSING_EXPORT');
  process.exit(2);
}
if (typeof freeze !== 'function') {
  console.error('MISSING_FREEZE_EXPORT');
  process.exit(2);
}
if (typeof shouldStop !== 'function') {
  console.error('MISSING_STOP_EXPORT');
  process.exit(2);
}

const cases = [
  {
    name: 'move-when-wrong-monitor',
    input: { skipTaskbar: false, windowMonitor: 1, activeMonitor: 0, monitorCount: 2 },
    expectMove: true, expectTarget: 0, expectReason: 'wrong-monitor',
  },
  {
    name: 'no-move-when-already-on-active',
    input: { skipTaskbar: false, windowMonitor: 0, activeMonitor: 0, monitorCount: 2 },
    expectMove: false, expectTarget: null, expectReason: 'already-on-active',
  },
  {
    name: 'no-move-skip-taskbar',
    input: { skipTaskbar: true, windowMonitor: 1, activeMonitor: 0, monitorCount: 2 },
    expectMove: false, expectTarget: null, expectReason: 'skip-taskbar',
  },
  {
    // Must NOT move while unassigned: Mutter move_to_monitor can SIGSEGV the Shell.
    name: 'no-move-unassigned-window',
    input: { skipTaskbar: false, windowMonitor: -1, activeMonitor: 1, monitorCount: 2 },
    expectMove: false, expectTarget: null, expectReason: 'unassigned-monitor',
  },
  {
    name: 'no-move-invalid-active',
    input: { skipTaskbar: false, windowMonitor: 0, activeMonitor: -1, monitorCount: 2 },
    expectMove: false, expectTarget: null, expectReason: 'invalid-active-monitor',
  },
  {
    name: 'no-move-active-out-of-range',
    input: { skipTaskbar: false, windowMonitor: 0, activeMonitor: 5, monitorCount: 2 },
    expectMove: false, expectTarget: null, expectReason: 'invalid-active-monitor',
  },
  {
    name: 'no-move-zero-monitors',
    input: { skipTaskbar: false, windowMonitor: 0, activeMonitor: 0, monitorCount: 0 },
    expectMove: false, expectTarget: null, expectReason: 'no-monitors',
  },
  {
    name: 'move-to-second-when-active-is-second',
    input: { skipTaskbar: false, windowMonitor: 0, activeMonitor: 1, monitorCount: 2 },
    expectMove: true, expectTarget: 1, expectReason: 'wrong-monitor',
  },
];

let failed = 0;
for (const c of cases) {
  const got = decide(c.input);
  const ok =
    Boolean(got.shouldMove) === Boolean(c.expectMove) &&
    (got.targetMonitor === c.expectTarget || (got.targetMonitor == null && c.expectTarget == null)) &&
    got.reason === c.expectReason;
  if (ok) {
    console.log(`CASE_PASS ${c.name}`);
  } else {
    failed += 1;
    console.log(
      `CASE_FAIL ${c.name} got=${JSON.stringify(got)} expectMove=${c.expectMove} ` +
      `expectTarget=${c.expectTarget} expectReason=${c.expectReason}`
    );
  }
}

// freezeTargetMonitor: keep valid snapshot; adopt candidate only when empty.
const freezeCases = [
  {
    name: 'freeze-keeps-valid-snapshot',
    args: [1, 2, 3],
    expect: 1,
  },
  {
    name: 'freeze-adopts-candidate-when-snapshot-invalid',
    args: [-1, 2, 3],
    expect: 2,
  },
  {
    name: 'freeze-ignores-out-of-range-candidate',
    args: [-1, 5, 3],
    expect: -1,
  },
  {
    name: 'freeze-ignores-changing-candidate-when-frozen',
    args: [0, 2, 3],
    expect: 0,
  },
  {
    name: 'freeze-no-monitors',
    args: [0, 1, 0],
    expect: -1,
  },
];
for (const c of freezeCases) {
  const got = freeze(...c.args);
  if (got === c.expect) {
    console.log(`CASE_PASS ${c.name}`);
  } else {
    failed += 1;
    console.log(`CASE_FAIL ${c.name} got=${got} expect=${c.expect}`);
  }
}

// Multi-recheck stability with a fixed snapshot (the extension contract).
// Window starts on monitor 0; snapshot target is 1; live pointer "moves" to
// 0, then 2, then 1 across phases — freeze must keep target 1, and decide
// must produce at most one corrective move (to 1), never thrash to 0 or 2.
{
  const monitorCount = 3;
  const livePointerSequence = [1, 0, 2, 1]; // schedule + delay phases
  let frozen = -1;
  let windowMonitor = 0;
  const moves = [];
  for (let i = 0; i < livePointerSequence.length; i++) {
    frozen = freeze(frozen, livePointerSequence[i], monitorCount);
    const d = decide({
      skipTaskbar: false,
      windowMonitor,
      activeMonitor: frozen,
      monitorCount,
    });
    if (d.shouldMove) {
      moves.push({ phase: i, from: windowMonitor, to: d.targetMonitor });
      windowMonitor = d.targetMonitor;
    }
  }
  const onlyToSnapshot =
    moves.length <= 1 &&
    moves.every((m) => m.to === 1) &&
    windowMonitor === 1 &&
    frozen === 1;
  if (onlyToSnapshot) {
    console.log(`CASE_PASS multi-recheck-stable-snapshot moves=${JSON.stringify(moves)}`);
  } else {
    failed += 1;
    console.log(
      `CASE_FAIL multi-recheck-stable-snapshot frozen=${frozen} ` +
      `windowMonitor=${windowMonitor} moves=${JSON.stringify(moves)}`
    );
  }
}

// Contrast: without freeze, re-resolving live pointer each phase thrash-moves.
{
  const monitorCount = 3;
  const livePointerSequence = [1, 0, 2, 1];
  let windowMonitor = 0;
  const thrashMoves = [];
  for (let i = 0; i < livePointerSequence.length; i++) {
    const d = decide({
      skipTaskbar: false,
      windowMonitor,
      activeMonitor: livePointerSequence[i],
      monitorCount,
    });
    if (d.shouldMove) {
      thrashMoves.push({ phase: i, from: windowMonitor, to: d.targetMonitor });
      windowMonitor = d.targetMonitor;
    }
  }
  const thrashed =
    thrashMoves.length >= 2 &&
    new Set(thrashMoves.map((m) => m.to)).size >= 2;
  if (thrashed) {
    console.log(
      `CASE_PASS multi-recheck-without-snapshot-thrashes moves=${JSON.stringify(thrashMoves)}`
    );
  } else {
    failed += 1;
    console.log(
      `CASE_FAIL multi-recheck-without-snapshot-thrashes moves=${JSON.stringify(thrashMoves)}`
    );
  }
}

// shouldStopPlacementRechecks: only already-on-active is terminal via policy.
{
  const stopCases = [
    {
      name: 'stop-on-already-on-active',
      decision: { shouldMove: false, targetMonitor: null, reason: 'already-on-active' },
      expect: true,
    },
    {
      name: 'no-stop-on-unassigned',
      decision: { shouldMove: false, targetMonitor: null, reason: 'unassigned-monitor' },
      expect: false,
    },
    {
      name: 'no-stop-on-wrong-monitor-decision',
      decision: { shouldMove: true, targetMonitor: 1, reason: 'wrong-monitor' },
      expect: false,
    },
    {
      name: 'no-stop-on-null',
      decision: null,
      expect: false,
    },
  ];
  for (const c of stopCases) {
    const got = shouldStop(c.decision);
    if (got === c.expect) {
      console.log(`CASE_PASS ${c.name}`);
    } else {
      failed += 1;
      console.log(`CASE_FAIL ${c.name} got=${got} expect=${c.expect}`);
    }
  }
}

// Programmatic primary survival: freeze pointer≠primary, settle already-on-active,
// external place_on_primary moves to primary, later rechecks must NOT move back.
// Mirrors multi/split kitty: pointer mon 1, primary mon 0.
{
  const monitorCount = 3;
  const pointerMonitor = 1;
  const primaryMonitor = 0;
  let frozen = freeze(-1, pointerMonitor, monitorCount);
  let windowMonitor = pointerMonitor; // lands with pointer first
  let stopped = false;
  const extensionMoves = [];

  // Phase 0 (delay-150): already-on-active → must stop rechecks (settled).
  {
    const d = decide({
      skipTaskbar: false,
      windowMonitor,
      activeMonitor: frozen,
      monitorCount,
    });
    if (d.shouldMove) {
      extensionMoves.push({ phase: 0, from: windowMonitor, to: d.targetMonitor });
      windowMonitor = d.targetMonitor;
      stopped = true;
    } else if (shouldStop(d)) {
      stopped = true;
    }
  }

  // External multi/split place_on_primary (not the extension).
  windowMonitor = primaryMonitor;

  // Phases 1–3 (delay-400/900/1600): if we wrongly continued, frozen pointer
  // would pull the window off primary. With stop, no further moves.
  for (let phase = 1; phase <= 3; phase++) {
    if (stopped) {
      continue;
    }
    frozen = freeze(frozen, pointerMonitor, monitorCount);
    const d = decide({
      skipTaskbar: false,
      windowMonitor,
      activeMonitor: frozen,
      monitorCount,
    });
    if (d.shouldMove) {
      extensionMoves.push({ phase, from: windowMonitor, to: d.targetMonitor });
      windowMonitor = d.targetMonitor;
    }
    if (shouldStop(d)) {
      stopped = true;
    }
  }

  // Contrast: without stop, continuing rechecks after primary would undo it.
  let undoMonitor = primaryMonitor;
  const undoMoves = [];
  for (let phase = 1; phase <= 3; phase++) {
    const d = decide({
      skipTaskbar: false,
      windowMonitor: undoMonitor,
      activeMonitor: pointerMonitor,
      monitorCount,
    });
    if (d.shouldMove) {
      undoMoves.push({ phase, from: undoMonitor, to: d.targetMonitor });
      undoMonitor = d.targetMonitor;
    }
  }

  const primarySurvived =
    stopped === true &&
    extensionMoves.length === 0 &&
    windowMonitor === primaryMonitor &&
    undoMoves.length >= 1 &&
    undoMoves.every((m) => m.to === pointerMonitor);

  if (primarySurvived) {
    console.log(
      `CASE_PASS primary-survives-after-settle-and-stop ` +
      `windowMonitor=${windowMonitor} undoWould=${JSON.stringify(undoMoves)}`
    );
  } else {
    failed += 1;
    console.log(
      `CASE_FAIL primary-survives-after-settle-and-stop stopped=${stopped} ` +
      `windowMonitor=${windowMonitor} extensionMoves=${JSON.stringify(extensionMoves)} ` +
      `undoMoves=${JSON.stringify(undoMoves)}`
    );
  }
}

process.exit(failed === 0 ? 0 : 1);
NODE
  )" || true
  echo "$policy_out"
  while IFS= read -r line; do
    case "$line" in
      CASE_PASS\ *) pass "policy: ${line#CASE_PASS }" ;;
      CASE_FAIL\ *) fail "policy: ${line#CASE_FAIL }" ;;
      MISSING_EXPORT) fail "decideActiveMonitorPlacement exported" ;;
      MISSING_FREEZE_EXPORT) fail "freezeTargetMonitor exported" ;;
      MISSING_STOP_EXPORT) fail "shouldStopPlacementRechecks exported" ;;
    esac
  done <<< "$policy_out"
  if ! echo "$policy_out" | grep -q 'CASE_PASS'; then
    fail "policy runner produced at least one CASE_PASS"
  fi
fi


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
[[ "$lib_text" == *"active-monitor-placement@local"* ]] && pass "configure deploys extension uuid" || fail "configure deploys extension uuid"
[[ "$lib_text" == *"placementPolicy.js"* ]] || [[ "$lib_text" == *'ACTIVE_MONITOR_EXT'* ]] \
  && pass "configure references extension source" || fail "configure references extension source"
# Reconfigure must force-reactivate (remove+add enabled-extensions), not only add.
[[ "$lib_text" == *"_active_monitor_strv_edit remove"* ]] && [[ "$lib_text" == *"_active_monitor_strv_edit add"* ]] \
  && pass "configure force-reactivates via remove+add enabled-extensions" \
  || fail "configure force-reactivates via remove+add enabled-extensions"
[[ "$lib_text" == *"EnableExtension"* ]] \
  && pass "configure uses D-Bus EnableExtension path" \
  || fail "configure uses D-Bus EnableExtension path"

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
[[ "$lifecycle_text" == *"active-monitor-placement@local"* ]] && pass "lifecycle knows extension uuid" || fail "lifecycle knows extension uuid"

echo ""
echo "--- configure / detect / uninstall contract (temp home) ---"
# Isolated install: real configure_active_monitor_placement against TARGET_HOME,
# with gsettings/gnome-extensions stubbed so enable paths do not touch the live session.
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/active-monitor-test-home.XXXXXX")"
GS_STATE="$TEST_HOME/gsettings-enabled.txt"
printf "[]\n" >"$GS_STATE"
export PATH="$TEST_HOME/bin:$PATH"
mkdir -p "$TEST_HOME/bin"

cat >"$TEST_HOME/bin/gsettings" <<'GS'
#!/usr/bin/env bash
set -euo pipefail
state="${ACTIVE_MONITOR_TEST_GS_STATE:?}"
op="${1:-}"
schema="${2:-}"
key="${3:-}"
if [ "$op" = "get" ] && [ "$schema" = "org.gnome.shell" ] && [ "$key" = "enabled-extensions" ]; then
  cat "$state"
  exit 0
fi
if [ "$op" = "get" ] && [ "$schema" = "org.gnome.shell" ] && [ "$key" = "disabled-extensions" ]; then
  printf '[]\n'
  exit 0
fi
if [ "$op" = "set" ] && [ "$schema" = "org.gnome.shell" ] && [ "$key" = "enabled-extensions" ]; then
  printf '%s\n' "${4:-[]}" >"$state"
  exit 0
fi
if [ "$op" = "set" ] && [ "$schema" = "org.gnome.shell" ] && [ "$key" = "disabled-extensions" ]; then
  exit 0
fi
if [ "$op" = "set" ] && [ "$schema" = "org.gnome.shell" ] && [ "$key" = "disable-user-extensions" ]; then
  exit 0
fi
exit 0
GS
chmod +x "$TEST_HOME/bin/gsettings"

cat >"$TEST_HOME/bin/gnome-extensions" <<'GE'
#!/usr/bin/env bash
# no-op stub
exit 0
GE
chmod +x "$TEST_HOME/bin/gnome-extensions"

# Minimal installer environment
TARGET_HOME="$TEST_HOME/user"
TARGET_USER="$(id -un)"
SCRIPT_DIR_SAVE="$SCRIPT_DIR"
CONFIG_DIR="$SCRIPT_DIR/configs"
export ACTIVE_MONITOR_TEST_GS_STATE="$GS_STATE"

mkdir -p "$TARGET_HOME"

run_as_target() { "$@"; }
is_root() { return 1; }
msg() { printf '%s\n' "$*" >&2; }
log() { :; }

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/active_monitor.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/lifecycle.sh"

# Before configure: detect must be false
if detect_active_monitor_placement; then
  fail "detect false before configure"
else
  pass "detect false before configure"
fi

configure_active_monitor_placement
cfg_rc=$?

if [ "$cfg_rc" -eq 0 ]; then
  pass "configure_active_monitor_placement returns 0"
else
  fail "configure_active_monitor_placement returns 0 (got $cfg_rc)"
fi

helper_dst="$TARGET_HOME/.local/bin/pin-window-to-active-monitor.sh"
ext_dst="$TARGET_HOME/.local/share/gnome-shell/extensions/active-monitor-placement@local"
[ -f "$helper_dst" ] && pass "configure installs pin helper" || fail "configure installs pin helper"
[ -x "$helper_dst" ] && pass "installed helper is executable" || fail "installed helper is executable"
[ -d "$ext_dst" ] && pass "configure installs extension dir" || fail "configure installs extension dir"
[ -f "$ext_dst/extension.js" ] && pass "configure installs extension.js" || fail "configure installs extension.js"
[ -f "$ext_dst/placementPolicy.js" ] && pass "configure installs placementPolicy.js" || fail "configure installs placementPolicy.js"
[ -f "$ext_dst/metadata.json" ] && pass "configure installs metadata.json" || fail "configure installs metadata.json"

# Shipped policy content must match source (not a stub)
if [ -f "$ext_dst/placementPolicy.js" ] && cmp -s "$POLICY_JS" "$ext_dst/placementPolicy.js"; then
  pass "deployed placementPolicy.js matches source"
else
  fail "deployed placementPolicy.js matches source"
fi

if detect_active_monitor_placement; then
  pass "detect true after configure"
else
  fail "detect true after configure"
fi

# enabled-extensions should mention our uuid after configure
if grep -qF 'active-monitor-placement@local' "$GS_STATE"; then
  pass "configure adds extension to enabled-extensions"
else
  fail "configure adds extension to enabled-extensions (state=$(cat "$GS_STATE"))"
fi

uninstall_active_monitor_placement

if [ ! -f "$helper_dst" ]; then
  pass "uninstall removes pin helper"
else
  fail "uninstall removes pin helper"
fi
if [ ! -d "$ext_dst" ]; then
  pass "uninstall removes extension dir"
else
  fail "uninstall removes extension dir"
fi
if detect_active_monitor_placement; then
  fail "detect false after uninstall"
else
  pass "detect false after uninstall"
fi

# Reinstall restores
configure_active_monitor_placement >/dev/null 2>&1 || true
if detect_active_monitor_placement && [ -f "$helper_dst" ] && [ -f "$ext_dst/placementPolicy.js" ]; then
  pass "reinstall restores helper and extension"
else
  fail "reinstall restores helper and extension"
fi

# Cleanup
rm -rf "$TEST_HOME"
SCRIPT_DIR="$SCRIPT_DIR_SAVE"

echo ""
echo "--- README documents the component ---"
readme="$SCRIPT_DIR/README.md"
grep -qF '`active_monitor_placement`' "$readme" && pass "README documents component" || fail "README documents component"
grep -qF 'pin-window-to-active-monitor' "$readme" && pass "README documents helper script" || fail "README documents helper script"
grep -qF 'active-monitor-placement@local' "$readme" && pass "README documents extension" || fail "README documents extension"

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
