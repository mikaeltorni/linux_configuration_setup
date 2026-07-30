// placementPolicy.js — pure active-monitor placement decision.
//
// Decides whether a newly created window should be moved onto the
// active/pointer monitor. No GNOME Shell APIs: unit tests import this
// module directly, and extension.js applies the same decision at runtime.
//
// Components:
//   - freezeTargetMonitor: stable target for one open across delayed rechecks.
//   - decideActiveMonitorPlacement: pure move / no-move policy for new windows.
//   - shouldStopPlacementRechecks: terminal open when already on frozen target.

/**
 * Freeze the target monitor for one window-open across delayed rechecks.
 *
 * Rechecks must not re-resolve the pointer/focus monitor every time: live
 * pointer chase after focus lands on a newly mapped window is what produces
 * cross-monitor thrash (e.g. 0→1→2→1 in journal for one open). Prefer a valid
 * snapshot from schedule time; only adopt a candidate when the snapshot is
 * still invalid (e.g. pointer geometry unavailable at window-created).
 *
 * @param {number} snapshot - Previously frozen target, or -1 if none yet.
 * @param {number} candidate - Freshly resolved pointer/panel monitor index.
 * @param {number} monitorCount - Number of monitors on the display.
 * @returns {number} Stable zero-based monitor index, or -1 when neither is valid.
 */
export function freezeTargetMonitor(snapshot, candidate, monitorCount) {
  const count = Number(monitorCount);
  if (!Number.isFinite(count) || count <= 0) {
    return -1;
  }

  const snap = Number(snapshot);
  if (Number.isFinite(snap) && Number.isInteger(snap) && snap >= 0 && snap < count) {
    return snap;
  }

  const cand = Number(candidate);
  if (Number.isFinite(cand) && Number.isInteger(cand) && cand >= 0 && cand < count) {
    return cand;
  }

  return -1;
}

/**
 * Decide whether a window should be moved onto the active (pointer) monitor.
 *
 * Callers pass already-resolved monitor indices from GNOME (or test doubles).
 * Invalid indices never produce a move target — callers must not call
 * move_to_monitor with an out-of-range index (Mutter asserts which_monitor >= 0).
 *
 * For one open, pass a *frozen* activeMonitor (from freezeTargetMonitor) on
 * every recheck so pointer/focus noise cannot thrash the window across displays.
 *
 * @param {object} input
 * @param {boolean} input.skipTaskbar - true for utility / skip-taskbar windows
 * @param {number} input.windowMonitor - window's current monitor index (-1 if unassigned)
 * @param {number} input.activeMonitor - frozen pointer / panel / primary target index
 * @param {number} input.monitorCount - number of monitors on the display
 * @returns {{shouldMove: boolean, targetMonitor: number|null, reason: string}}
 *   shouldMove is true only when the window is a normal candidate, already has
 *   a valid monitor index, and that index is not the active monitor.
 *   Unassigned windows (monitor -1) return shouldMove false so callers never
 *   invoke Mutter move APIs until placement is safe; targetMonitor is a
 *   clamped index when shouldMove is true.
 */
export function decideActiveMonitorPlacement(input) {
  const skipTaskbar = Boolean(input?.skipTaskbar);
  const windowMonitor = Number(input?.windowMonitor);
  const activeMonitor = Number(input?.activeMonitor);
  const monitorCount = Number(input?.monitorCount);

  if (skipTaskbar) {
    return { shouldMove: false, targetMonitor: null, reason: 'skip-taskbar' };
  }

  if (!Number.isFinite(monitorCount) || monitorCount <= 0) {
    return { shouldMove: false, targetMonitor: null, reason: 'no-monitors' };
  }

  if (
    !Number.isFinite(activeMonitor) ||
    !Number.isInteger(activeMonitor) ||
    activeMonitor < 0 ||
    activeMonitor >= monitorCount
  ) {
    return { shouldMove: false, targetMonitor: null, reason: 'invalid-active-monitor' };
  }

  const windowOnValidMonitor =
    Number.isFinite(windowMonitor) &&
    Number.isInteger(windowMonitor) &&
    windowMonitor >= 0 &&
    windowMonitor < monitorCount;

  // Unassigned / not-yet-placed windows must not be moved: Mutter can SIGSEGV
  // the Shell if move_to_monitor runs before the window has a real monitor.
  // Later rechecks (after the WM assigns a monitor) still correct a wrong one.
  if (!windowOnValidMonitor) {
    return { shouldMove: false, targetMonitor: null, reason: 'unassigned-monitor' };
  }

  if (windowMonitor === activeMonitor) {
    return { shouldMove: false, targetMonitor: null, reason: 'already-on-active' };
  }

  return {
    shouldMove: true,
    targetMonitor: activeMonitor,
    reason: 'wrong-monitor',
  };
}

/**
 * Whether delayed rechecks for one open should stop after this decision.
 *
 * already-on-active means the window has settled on the frozen pointer/panel
 * target. Further rechecks must not run: external primary placement (e.g.
 * multi/split kitty place_on_primary) can move the window to the primary
 * monitor after that settle; a later recheck would still hold the frozen
 * pointer target and drag it back off primary.
 *
 * Unassigned / invalid / skip-taskbar are not terminal — callers may recheck
 * once the window maps or the target becomes valid. A successful move is
 * terminal at the call site (separate from this helper).
 *
 * @param {{shouldMove?: boolean, reason?: string}|null|undefined} decision
 *   Result of decideActiveMonitorPlacement.
 * @returns {boolean} true when rechecks for this open should stop.
 */
export function shouldStopPlacementRechecks(decision) {
  if (!decision || typeof decision !== 'object') {
    return false;
  }
  return decision.reason === 'already-on-active';
}
