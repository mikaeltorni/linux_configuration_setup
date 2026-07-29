// extension.js - active-monitor-placement@local GNOME Shell extension.
//
// When a normal (non-skip-taskbar) window is created, GNOME/Mutter may place it
// on a different monitor because the active one is crowded. This extension
// rechecks shortly after create/map and moves the window onto the pointer's
// current monitor when the pure placement policy says so.
//
// The decision logic lives in placementPolicy.js so unit tests can drive the
// shipped policy without a live Shell. A delayed recheck mirrors the known
// open-kitty-and-sort race: the WM may finish placement after the first map.
//
// Components:
//   - isSkipTaskbar: detect utility / skip-taskbar windows.
//   - resolveActiveMonitor: clamp pointer/current monitor index.
//   - resolveWindowMonitor: read window monitor without calling APIs with -1.
//   - applyPlacement: run policy and move when needed.
//   - ActiveMonitorPlacementExtension: window-created + delayed recheck wiring.

import GLib from 'gi://GLib';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import { decideActiveMonitorPlacement } from './placementPolicy.js';

// Delays (ms) for placement rechecks after window-created. The first pass
// catches early wrong placement; later passes cover Mutter's async placement.
const RECHECK_DELAYS_MS = [50, 300, 700];

/**
 * Whether a window is a utility / skip-taskbar candidate that must not be moved.
 *
 * @param {Meta.Window|null} win - Window under consideration.
 * @returns {boolean} true when the window should be ignored.
 */
function isSkipTaskbar(win) {
  if (!win) {
    return true;
  }
  try {
    if (typeof win.is_skip_taskbar === 'function') {
      return Boolean(win.is_skip_taskbar());
    }
    return Boolean(win.skip_taskbar);
  } catch (_e) {
    return true;
  }
}

/**
 * Resolve the active (pointer / current) monitor index, clamped to a valid range.
 *
 * @param {Meta.Display} display - global.display
 * @returns {number} Zero-based monitor index, or -1 when none are available.
 */
function resolveActiveMonitor(display) {
  const monitorCount = typeof display.get_n_monitors === 'function'
    ? display.get_n_monitors()
    : 0;
  if (monitorCount <= 0) {
    return -1;
  }
  let index = typeof display.get_current_monitor === 'function'
    ? display.get_current_monitor()
    : -1;
  if (!Number.isInteger(index) || index < 0 || index >= monitorCount) {
    return -1;
  }
  return index;
}

/**
 * Read the window's monitor index without treating -1 as a usable target.
 *
 * @param {Meta.Window} win - Window whose monitor is requested.
 * @returns {number} Zero-based index, or -1 when unassigned / invalid.
 */
function resolveWindowMonitor(win) {
  try {
    if (typeof win.get_monitor !== 'function') {
      return -1;
    }
    const index = win.get_monitor();
    if (!Number.isInteger(index) || index < 0) {
      return -1;
    }
    return index;
  } catch (_e) {
    return -1;
  }
}

/**
 * Apply pure placement policy and move the window when it landed elsewhere.
 *
 * @param {Meta.Window} win - Candidate window.
 * @param {string} phase - Log label for which recheck fired (e.g. "delay-300").
 * @returns {boolean} true when a move was performed.
 */
function applyPlacement(win, phase) {
  if (!win || typeof win.move_to_monitor !== 'function') {
    return false;
  }

  // Window may have been destroyed between schedule and fire.
  try {
    if (typeof win.get_compositor_private === 'function' && !win.get_compositor_private()) {
      // Still allow windows that are mapping; only bail if clearly gone.
    }
  } catch (_e) {
    return false;
  }

  const display = global.display;
  const monitorCount = typeof display.get_n_monitors === 'function'
    ? display.get_n_monitors()
    : 0;
  const activeMonitor = resolveActiveMonitor(display);
  const windowMonitor = resolveWindowMonitor(win);
  const skipTaskbar = isSkipTaskbar(win);

  const decision = decideActiveMonitorPlacement({
    skipTaskbar,
    windowMonitor,
    activeMonitor,
    monitorCount,
  });

  if (!decision.shouldMove) {
    // already-on-active and skip-taskbar are the common quiet paths; log only
    // unusual bailouts (invalid monitors, empty display) for diagnostics.
    if (decision.reason !== 'already-on-active' && decision.reason !== 'skip-taskbar') {
      console.log(`[active-monitor-placement] skip (${phase}): ${decision.reason}`);
    }
    return false;
  }

  const target = decision.targetMonitor;
  if (!Number.isInteger(target) || target < 0 || target >= monitorCount) {
    console.log(`[active-monitor-placement] refuse move with invalid target ${target}`);
    return false;
  }

  try {
    win.move_to_monitor(target);
    console.log(
      `[active-monitor-placement] moved window to monitor ${target} ` +
      `(from ${windowMonitor}, reason=${decision.reason}, phase=${phase})`
    );
    return true;
  } catch (e) {
    console.log(`[active-monitor-placement] move_to_monitor failed: ${e}`);
    return false;
  }
}

export default class ActiveMonitorPlacementExtension extends Extension {
  enable() {
    this._timeouts = [];
    this._sig = global.display.connect('window-created', (_disp, win) => {
      this._schedulePlacement(win);
    });
    console.log('[active-monitor-placement] enabled (window-created correction active)');
  }

  /**
   * Schedule immediate + delayed placement corrections for a new window.
   *
   * @param {Meta.Window} win - Newly created window.
   * @returns {void}
   */
  _schedulePlacement(win) {
    if (!win || isSkipTaskbar(win)) {
      return;
    }

    for (const delayMs of RECHECK_DELAYS_MS) {
      const sourceId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, delayMs, () => {
        this._timeouts = this._timeouts.filter((id) => id !== sourceId);
        try {
          applyPlacement(win, `delay-${delayMs}`);
        } catch (e) {
          console.log(`[active-monitor-placement] recheck error: ${e}`);
        }
        return GLib.SOURCE_REMOVE;
      });
      this._timeouts.push(sourceId);
    }
  }

  disable() {
    if (this._sig) {
      global.display.disconnect(this._sig);
      this._sig = null;
    }
    if (this._timeouts) {
      for (const id of this._timeouts) {
        try {
          GLib.source_remove(id);
        } catch (_e) {
          // already fired
        }
      }
      this._timeouts = [];
    }
    console.log('[active-monitor-placement] disabled');
  }
}
