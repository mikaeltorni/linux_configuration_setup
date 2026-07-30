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
// Stability: the target monitor is snapshotted once per open (at schedule, or
// on the first recheck that can resolve it). Rechecks reuse that frozen target
// so later focus/pointer noise cannot thrash the window across monitors
// (journal pattern: delay-150 → mon1, delay-400 → mon2, delay-900 → mon1).
//
// Safety: never call move_to_monitor until the window is mapped and already
// has a valid monitor index. Calling Mutter with an unassigned window can
// SIGSEGV the entire GNOME Shell (signal 11) — that is not catchable in JS.
//
// Components:
//   - isSkipTaskbar: detect utility / skip-taskbar windows.
//   - isWindowMoveSafe: mapped + valid-monitor gate before Mutter move APIs.
//   - resolveActiveMonitor: clamp pointer/current monitor index.
//   - resolveWindowMonitor: read window monitor without treating -1 as usable.
//   - applyPlacement: run policy and move when needed (uses frozen target).
//   - ActiveMonitorPlacementExtension: window-created + delayed recheck wiring.

import GLib from 'gi://GLib';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import {
  decideActiveMonitorPlacement,
  freezeTargetMonitor,
} from './placementPolicy.js';

// Delays (ms) for placement rechecks after window-created. Early passes often
// see unassigned monitors (policy: no move); later passes correct once Mutter
// has finished its own (possibly wrong) placement. Include a late pass for
// slow-to-map clients (kitty/gtk sometimes assign geometry after 1s).
const RECHECK_DELAYS_MS = [150, 400, 900, 1600];

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
 * Whether it is safe to call move_to_monitor on this window.
 *
 * Requires a compositor actor (mapped) and a non-negative get_monitor() index.
 * Both gates prevent the known Mutter SIGSEGV on premature move_to_monitor.
 *
 * @param {Meta.Window|null} win - Window under consideration.
 * @returns {boolean} true only when Mutter move APIs may be called.
 */
function isWindowMoveSafe(win) {
  if (!win || typeof win.move_to_monitor !== 'function') {
    return false;
  }
  try {
    if (typeof win.get_compositor_private === 'function') {
      const actor = win.get_compositor_private();
      if (!actor) {
        return false;
      }
    }
    if (typeof win.get_monitor !== 'function') {
      return false;
    }
    const index = win.get_monitor();
    // Coerce GJS number; reject -1 and NaN. Do not require Number.isInteger
    // alone in case GJS surfaces integers as floating values.
    const n = Number(index);
    if (!Number.isFinite(n) || n < 0) {
      return false;
    }
    return true;
  } catch (_e) {
    return false;
  }
}

/**
 * Resolve the active (pointer) monitor index, clamped to a valid range.
 *
 * Uses global pointer coordinates first so a newly focused window that landed
 * on the wrong display cannot redefine "active" via focus-based APIs. Falls
 * back to display.get_current_monitor() when pointer geometry is unavailable.
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

  // Pointer hit-test (authoritative for "monitor the user is working on").
  try {
    if (typeof global.get_pointer === 'function' &&
        typeof display.get_monitor_geometry === 'function') {
      const pointer = global.get_pointer();
      const px = Number(pointer?.[0]);
      const py = Number(pointer?.[1]);
      if (Number.isFinite(px) && Number.isFinite(py)) {
        for (let i = 0; i < monitorCount; i++) {
          const geo = display.get_monitor_geometry(i);
          if (!geo) {
            continue;
          }
          const gx = Number(geo.x);
          const gy = Number(geo.y);
          const gw = Number(geo.width);
          const gh = Number(geo.height);
          if (
            Number.isFinite(gx) && Number.isFinite(gy) &&
            Number.isFinite(gw) && Number.isFinite(gh) &&
            px >= gx && px < gx + gw &&
            py >= gy && py < gy + gh
          ) {
            return i;
          }
        }
      }
    }
  } catch (_e) {
    // fall through to get_current_monitor
  }

  let index = typeof display.get_current_monitor === 'function'
    ? display.get_current_monitor()
    : -1;
  const n = Number(index);
  if (!Number.isFinite(n) || n < 0 || n >= monitorCount) {
    return -1;
  }
  return Math.trunc(n);
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
    const n = Number(win.get_monitor());
    if (!Number.isFinite(n) || n < 0) {
      return -1;
    }
    return Math.trunc(n);
  } catch (_e) {
    return -1;
  }
}

/**
 * Apply pure placement policy and move the window when it landed elsewhere.
 *
 * @param {Meta.Window} win - Candidate window.
 * @param {string} phase - Log label for which recheck fired (e.g. "delay-350").
 * @param {number} frozenActiveMonitor - Target monitor snapshotted for this open.
 * @returns {boolean} true when a move was performed.
 */
function applyPlacement(win, phase, frozenActiveMonitor) {
  if (!isWindowMoveSafe(win)) {
    // Last recheck: surface that we never got a move-safe window (mapping race).
    if (phase === `delay-${RECHECK_DELAYS_MS[RECHECK_DELAYS_MS.length - 1]}`) {
      console.log(`[active-monitor-placement] skip (${phase}): not-move-safe`);
    }
    return false;
  }

  const display = global.display;
  const monitorCount = typeof display.get_n_monitors === 'function'
    ? display.get_n_monitors()
    : 0;
  // Never re-resolve the live pointer here: use the per-open frozen target so
  // delayed rechecks cannot thrash across monitors when focus/pointer moves.
  const activeMonitor = Number(frozenActiveMonitor);
  const windowMonitor = resolveWindowMonitor(win);
  const skipTaskbar = isSkipTaskbar(win);

  // Second hard gate: never pass an unassigned window into move_to_monitor.
  if (windowMonitor < 0 || windowMonitor >= monitorCount) {
    if (phase === `delay-${RECHECK_DELAYS_MS[RECHECK_DELAYS_MS.length - 1]}`) {
      console.log(`[active-monitor-placement] skip (${phase}): unassigned-monitor`);
    }
    return false;
  }
  if (
    !Number.isFinite(activeMonitor) ||
    activeMonitor < 0 ||
    activeMonitor >= monitorCount
  ) {
    console.log(`[active-monitor-placement] skip (${phase}): invalid-active-monitor`);
    return false;
  }

  const decision = decideActiveMonitorPlacement({
    skipTaskbar,
    windowMonitor,
    activeMonitor: Math.trunc(activeMonitor),
    monitorCount,
  });

  if (!decision.shouldMove) {
    // Quiet for already-on-active / skip-taskbar / still-unassigned.
    if (
      decision.reason !== 'already-on-active' &&
      decision.reason !== 'skip-taskbar' &&
      decision.reason !== 'unassigned-monitor'
    ) {
      console.log(`[active-monitor-placement] skip (${phase}): ${decision.reason}`);
    }
    return false;
  }

  const target = Number(decision.targetMonitor);
  if (!Number.isFinite(target) || target < 0 || target >= monitorCount) {
    console.log(`[active-monitor-placement] refuse move with invalid target ${target}`);
    return false;
  }
  const targetIndex = Math.trunc(target);

  // Idempotent: if a race placed us correctly since the decision, do nothing.
  if (resolveWindowMonitor(win) === targetIndex) {
    return false;
  }

  // Re-check mapped state immediately before the Mutter call.
  if (!isWindowMoveSafe(win)) {
    return false;
  }

  try {
    win.move_to_monitor(targetIndex);
    console.log(
      `[active-monitor-placement] moved window to monitor ${targetIndex} ` +
      `(from ${windowMonitor}, reason=${decision.reason}, phase=${phase})`
    );
    return true;
  } catch (e) {
    // JS exceptions only; C-level SIGSEGV cannot be caught — prevented by gates.
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
   * Schedule delayed placement corrections for a new window.
   *
   * Snapshots the active (pointer) monitor once so all rechecks share one
   * stable target. If the snapshot is invalid at schedule time, the first
   * recheck that can resolve a candidate freezes it for the remaining phases.
   *
   * @param {Meta.Window} win - Newly created window.
   * @returns {void}
   */
  _schedulePlacement(win) {
    if (!win || isSkipTaskbar(win)) {
      return;
    }

    // Per-open frozen target (shared across timeouts for this schedule only).
    // Prefer schedule-time pointer/panel monitor; fill once if still invalid.
    let frozenTarget = resolveActiveMonitor(global.display);
    if (frozenTarget >= 0) {
      console.log(
        `[active-monitor-placement] snapshot target monitor ${frozenTarget} at schedule`
      );
    }

    for (const delayMs of RECHECK_DELAYS_MS) {
      const sourceId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, delayMs, () => {
        this._timeouts = this._timeouts.filter((id) => id !== sourceId);
        try {
          // Window may have been destroyed between schedule and fire.
          if (!win || (typeof win.get_compositor_private === 'function' &&
              !win.get_compositor_private() && resolveWindowMonitor(win) < 0)) {
            return GLib.SOURCE_REMOVE;
          }
          const display = global.display;
          const monitorCount = typeof display.get_n_monitors === 'function'
            ? display.get_n_monitors()
            : 0;
          // Fill frozen target only while still invalid; never re-chase pointer.
          const previousFrozen = frozenTarget;
          frozenTarget = freezeTargetMonitor(
            frozenTarget,
            resolveActiveMonitor(display),
            monitorCount
          );
          if (previousFrozen < 0 && frozenTarget >= 0) {
            console.log(
              `[active-monitor-placement] freeze target monitor ${frozenTarget} ` +
              `(phase=delay-${delayMs})`
            );
          }
          applyPlacement(win, `delay-${delayMs}`, frozenTarget);
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
