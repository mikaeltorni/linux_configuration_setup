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
 *   shouldMove is true only when the window is a normal candidate and is not
 *   already on a valid active monitor; targetMonitor is then a clamped index.
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

  if (windowOnValidMonitor && windowMonitor === activeMonitor) {
    return { shouldMove: false, targetMonitor: null, reason: 'already-on-active' };
  }

  return {
    shouldMove: true,
    targetMonitor: activeMonitor,
    reason: windowOnValidMonitor ? 'wrong-monitor' : 'unassigned-monitor',
  };
}
