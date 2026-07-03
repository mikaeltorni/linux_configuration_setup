#!/usr/bin/env python3
"""Idempotently patch Dash-to-Panel v73 for monitor-local app launches.

Usage: patch_dash_to_panel_monitor_launch.py PATH/TO/appIcons.js
"""

from __future__ import annotations

import os
from pathlib import Path
import stat
import sys
import tempfile

from logging_utils import get_logger, log_call


MARKER = "_armLaunchMonitorPlacement()"
LOGGER = get_logger("dash-to-panel-monitor-launch", "dash_to_panel_monitor_launch.log")


def replace_once(source: str, old: str, new: str, description: str) -> str:
    """Replace one pinned source fragment or raise a descriptive error."""
    count = source.count(old)
    if count != 1:
        raise ValueError(
            f"expected one {description} fragment in Dash-to-Panel v73, found {count}"
        )
    return source.replace(old, new, 1)


def patched_source(source: str) -> str:
    """Return Dash-to-Panel source with deterministic launch placement added."""
    if MARKER in source:
        return source

    source = replace_once(
        source,
        """      this._timeoutsHandler.destroy()
      this._signalsHandler.destroy()

      this._previewMenu.close(true)
""",
        """      this._timeoutsHandler.destroy()
      this._signalsHandler.destroy()
      this._clearLaunchMonitorPlacement()

      this._previewMenu.close(true)
""",
        "destroy cleanup",
    )
    source = replace_once(
        source,
        """    activate(button, modifiers, handleAsGrouped) {
""",
        """    _clearLaunchMonitorPlacement() {
      if (this._launchMonitorSignalId) {
        this.app.disconnect(this._launchMonitorSignalId)
        this._launchMonitorSignalId = 0
      }

      if (this._launchMonitorTimeoutId) {
        GLib.source_remove(this._launchMonitorTimeoutId)
        this._launchMonitorTimeoutId = 0
      }
    }

    _armLaunchMonitorPlacement() {
      if (
        !SETTINGS.get_boolean('multi-monitors') ||
        !SETTINGS.get_boolean('isolate-monitors')
      ) {
        return
      }

      this._clearLaunchMonitorPlacement()
      const targetMonitor = this.dtpPanel.monitor.index
      const existingWindows = new Set(this.app.get_windows())

      this._launchMonitorSignalId = this.app.connect('windows-changed', () => {
        const newWindow = this.app
          .get_windows()
          .find((window) => !existingWindows.has(window) && !window.skip_taskbar)
        if (!newWindow) return

        try {
          if (newWindow.get_monitor() !== targetMonitor)
            newWindow.move_to_monitor(targetMonitor)
          console.log(
            `[dash-to-panel] placed new ${this.app.id} window on clicked panel monitor ${targetMonitor}`,
          )
        } catch (error) {
          console.error(
            `[dash-to-panel] failed to place new ${this.app.id} window on monitor ${targetMonitor}: ${error}`,
          )
        }
        this._clearLaunchMonitorPlacement()
      })

      this._launchMonitorTimeoutId = GLib.timeout_add_seconds(
        GLib.PRIORITY_DEFAULT,
        10,
        () => {
          this._launchMonitorTimeoutId = 0
          console.warn(
            `[dash-to-panel] timed out waiting for new ${this.app.id} window for monitor ${targetMonitor}`,
          )
          this._clearLaunchMonitorPlacement()
          return GLib.SOURCE_REMOVE
        },
      )
    }

    activate(button, modifiers, handleAsGrouped) {
""",
        "activate method",
    )
    source = replace_once(
        source,
        """        maybeAnimate()
        this.app.open_new_window(-1)
""",
        """        this._armLaunchMonitorPlacement()
        maybeAnimate()
        this.app.open_new_window(-1)
""",
        "open-new-window launch",
    )
    source = replace_once(
        source,
        """        } else {
          maybeAnimate()
          this.app.activate()
        }
""",
        """        } else {
          this._armLaunchMonitorPlacement()
          maybeAnimate()
          this.app.activate()
        }
""",
        "inactive app launch",
    )
    return source


@log_call(LOGGER)
def patch_file(path: Path) -> None:
    """Patch *path* atomically while preserving its existing permission bits."""
    source = path.read_text(encoding="utf-8")
    patched = patched_source(source)
    if patched == source:
        LOGGER.info("Monitor-local launch patch already present in %s", path)
        return

    mode = stat.S_IMODE(path.stat().st_mode)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, delete=False
    ) as temporary:
        temporary.write(patched)
        temporary_path = Path(temporary.name)
    os.chmod(temporary_path, mode)
    os.replace(temporary_path, path)
    LOGGER.info("Applied monitor-local launch patch to %s", path)


@log_call(LOGGER)
def main(argv: list[str]) -> int:
    """Validate CLI arguments and patch the requested appIcons.js file."""
    if len(argv) != 2:
        print(f"usage: {Path(argv[0]).name} PATH/TO/appIcons.js", file=sys.stderr)
        return 2
    try:
        patch_file(Path(argv[1]))
    except (OSError, ValueError) as error:
        LOGGER.error("Monitor-local launch patch failed for %s: %s", argv[1], error)
        print(f"Dash-to-Panel monitor-launch patch failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
