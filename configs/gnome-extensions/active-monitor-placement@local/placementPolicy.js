// placementPolicy.js — pure active-monitor placement decision.
//
// Decides whether a newly created window should be moved onto the
// active/pointer monitor. No GNOME Shell APIs: unit tests import this
// module directly, and extension.js applies the same decision at runtime.
//
// Components:
//   - decideActiveMonitorPlacement: pure move / no-move policy for new windows.

/**
 * Decide whether a window should be moved onto the active (pointer) monitor.
 *
 * Callers pass already-resolved monitor indices from GNOME (or test doubles).
 * Invalid indices never produce a move target — callers must not call
 * move_to_monitor with an out-of-range index (Mutter asserts which_monitor >= 0).
 *
 * @param {object} input
 * @param {boolean} input.skipTaskbar - true for utility / skip-taskbar windows
 * @param {number} input.windowMonitor - window's current monitor index (-1 if unassigned)
 * @param {number} input.activeMonitor - pointer / current monitor index
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
