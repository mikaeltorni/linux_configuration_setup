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
//   - applyPlacement: run policy and move when needed (uses frozen target);
//     returns moved|settled|pending so already-on-active stops rechecks.
//   - hasExplicitMonitorRule: honor app-rules' per-application monitor pins.
//   - ActiveMonitorPlacementExtension: window-created + delayed recheck wiring.
//
// Coexistence with app-rules@local: the installer's [m] menu action pins chosen
// applications (e.g. Spotify, Discord) to a fixed monitor in
// ~/.config/app-rules/user-rules.json. Those windows are explicitly excluded
// here, because a pointer-following correction would immediately undo the
// user's fixed choice. Every other window keeps the active-monitor behavior.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import {
  decideActiveMonitorPlacement,
  freezeTargetMonitor,
  shouldStopPlacementRechecks,
} from './placementPolicy.js';

// Delays (ms) for placement rechecks after window-created. Early passes often
// see unassigned monitors (policy: no move); later passes correct once Mutter
// has finished its own (possibly wrong) placement. Include a late pass for
// slow-to-map clients (kitty/gtk sometimes assign geometry after 1s).
const RECHECK_DELAYS_MS = [150, 400, 900, 1600];

// Built-in app-rules monitor pins must be excluded from pointer-following
// placement even when the dynamic user-rules file has no monitor entry.
const BUILTIN_FIXED_MONITOR_APP_IDS = new Set([
  'smartgit.desktop',
  'gitkraken.desktop',
  'gitkraken_gitkraken.desktop',
  'monkeytype.desktop',
  'chrome-picebhhlijnlefeleilfbanaghjlkkna-Default.desktop',
]);

/**
 * Read the app ids that app-rules@local pins to a fixed monitor.
 *
 * The file is installer-owned and rewritten by the master menu, so it is
 * re-read when its modification time changes rather than cached for the whole
 * session. Any read or parse failure yields an empty set, which simply keeps
 * the previous (pointer-following) behavior for every window.
 *
 * @param {{mtime: number, ids: Set<string>}} cache - Mutable cache record.
 * @returns {Set<string>} Lower-cased app ids with an explicit monitor rule.
 */
function explicitMonitorAppIds(cache) {
  const path = GLib.build_filenamev([
    GLib.get_user_config_dir(), 'app-rules', 'user-rules.json',
  ]);
  let mtime = 0;
  try {
    const info = Gio.File.new_for_path(path).query_info(
      'time::modified', Gio.FileQueryInfoFlags.NONE, null);
    mtime = info.get_attribute_uint64('time::modified');
  } catch (_e) {
    cache.mtime = 0;
    cache.ids = new Set(BUILTIN_FIXED_MONITOR_APP_IDS);
    return cache.ids;
  }
  if (mtime === cache.mtime) {
    return cache.ids;
  }

  const ids = new Set(BUILTIN_FIXED_MONITOR_APP_IDS);
  try {
    const [ok, bytes] = GLib.file_get_contents(path);
    if (ok) {
      const parsed = JSON.parse(new TextDecoder().decode(bytes));
      for (const rule of parsed.rules || []) {
        if (!rule || !rule.monitor || !Array.isArray(rule.appIds)) {
          continue;
        }
        for (const appId of rule.appIds) {
          ids.add(String(appId).toLowerCase());
        }
      }
    }
  } catch (e) {
    console.log(`[active-monitor-placement] failed to read ${path}: ${e}`);
  }
  cache.mtime = mtime;
  cache.ids = ids;
  if (ids.size > 0) {
    console.log(`[active-monitor-placement] ${ids.size} app id(s) pinned by app-rules; leaving them alone`);
  }
  return ids;
}

/**
 * Whether a window belongs to an application with an explicit monitor pin.
 *
 * @param {Meta.Window|null} win - Window under consideration.
 * @param {{mtime: number, ids: Set<string>}} cache - Rule cache record.
 * @returns {boolean} true when app-rules owns this window's placement.
 */
function hasExplicitMonitorRule(win, cache) {
  const ids = explicitMonitorAppIds(cache);
  if (ids.size === 0 || !win) {
    return false;
  }
  try {
    const app = Shell.WindowTracker.get_default().get_window_app(win);
    const appId = app ? app.get_id() : null;
    return Boolean(appId) && ids.has(appId.toLowerCase());
  } catch (_e) {
    return false;
  }
}

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
 * @returns {'moved'|'settled'|'pending'}
 *   moved: Mutter move performed; settled: already on frozen target (or race
 *   placed there) — stop rechecks so external primary placement can stick;
 *   pending: try again on a later delay.
 */
function applyPlacement(win, phase, frozenActiveMonitor) {
  if (!isWindowMoveSafe(win)) {
    // Last recheck: surface that we never got a move-safe window (mapping race).
    if (phase === `delay-${RECHECK_DELAYS_MS[RECHECK_DELAYS_MS.length - 1]}`) {
      console.log(`[active-monitor-placement] skip (${phase}): not-move-safe`);
    }
    return 'pending';
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
    return 'pending';
  }
  if (
    !Number.isFinite(activeMonitor) ||
    activeMonitor < 0 ||
    activeMonitor >= monitorCount
  ) {
    console.log(`[active-monitor-placement] skip (${phase}): invalid-active-monitor`);
    return 'pending';
  }

  const decision = decideActiveMonitorPlacement({
    skipTaskbar,
    windowMonitor,
    activeMonitor: Math.trunc(activeMonitor),
    monitorCount,
  });

  if (!decision.shouldMove) {
    // Terminal when already on the frozen target: stop rechecks so multi/split
    // place_on_primary can move to primary without a later recheck undoing it.
    if (shouldStopPlacementRechecks(decision)) {
      return 'settled';
    }
    // Quiet for skip-taskbar / still-unassigned.
    if (
      decision.reason !== 'skip-taskbar' &&
      decision.reason !== 'unassigned-monitor'
    ) {
      console.log(`[active-monitor-placement] skip (${phase}): ${decision.reason}`);
    }
    return 'pending';
  }

  const target = Number(decision.targetMonitor);
  if (!Number.isFinite(target) || target < 0 || target >= monitorCount) {
    console.log(`[active-monitor-placement] refuse move with invalid target ${target}`);
    return 'pending';
  }
  const targetIndex = Math.trunc(target);

  // Idempotent: race already placed us on the frozen target — treat as settled.
  if (resolveWindowMonitor(win) === targetIndex) {
    return 'settled';
  }

  // Re-check mapped state immediately before the Mutter call.
  if (!isWindowMoveSafe(win)) {
    return 'pending';
  }

  try {
    win.move_to_monitor(targetIndex);
    console.log(
      `[active-monitor-placement] moved window to monitor ${targetIndex} ` +
      `(from ${windowMonitor}, reason=${decision.reason}, phase=${phase})`
    );
    return 'moved';
  } catch (e) {
    // JS exceptions only; C-level SIGSEGV cannot be caught — prevented by gates.
    console.log(`[active-monitor-placement] move_to_monitor failed: ${e}`);
    return 'pending';
  }
}

export default class ActiveMonitorPlacementExtension extends Extension {
  enable() {
    this._timeouts = [];
    // app-rules' explicit monitor pins, refreshed when the rules file changes.
    this._monitorRuleCache = { mtime: 0, ids: new Set() };
    // Windows settled this session (moved or already-on-active on frozen target):
    // skip later rechecks so external primary placement can stick and we avoid
    // recheck spam / tiler fights.
    this._corrected = new Set();
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
   * After a successful move or already-on-active settle, later rechecks for
   * the same window are skipped (so place_on_primary is not undone).
   *
   * @param {Meta.Window} win - Newly created window.
   * @returns {void}
   */
  _schedulePlacement(win) {
    if (!win || isSkipTaskbar(win)) {
      return;
    }

    // app-rules owns this application's monitor: never fight its fixed choice.
    if (hasExplicitMonitorRule(win, this._monitorRuleCache)) {
      console.log('[active-monitor-placement] skip: app has an explicit app-rules monitor');
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
          if (this._corrected?.has(win)) {
            return GLib.SOURCE_REMOVE;
          }
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
          const outcome = applyPlacement(win, `delay-${delayMs}`, frozenTarget);
          // Terminal on move OR already-on-active settle — not only on move.
          if (outcome === 'moved' || outcome === 'settled') {
            this._corrected?.add(win);
          }
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
    this._corrected = null;
    console.log('[active-monitor-placement] disabled');
  }
}
