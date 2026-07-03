export const TaskbarAppIcon = GObject.registerClass(
  {},
  class TaskbarAppIcon extends AppDisplay.AppIcon {
    _onDestroy() {
      super._onDestroy()

      if (this._updateIconIdleId) {
        GLib.source_remove(this._updateIconIdleId)
        this._updateIconIdleId = 0
      }

      this._timeoutsHandler.destroy()
      this._signalsHandler.destroy()

      this._previewMenu.close(true)
    }

    activate(button, modifiers, handleAsGrouped) {
      let event = Clutter.get_current_event()

      modifiers = event ? event.get_state() : modifiers || 0

      if (this.window || buttonAction != 'TOGGLE-SHOWPREVIEW') closePreview()

      if (appIsRunning && !this.isLauncher) {
        this._launchNewInstance()
      } else {
        this._launchNewInstance()
      }

      global.display.emit('grab-op-begin', null, null)
      Main.overview.hide()
    }

    _launchNewInstance(ctrlPressed) {
      let maybeAnimate = () =>
        SETTINGS.get_boolean('animate-window-launch') && this.animateLaunch()

      if (
        (ctrlPressed || this.app.state == Shell.AppState.RUNNING) &&
        this.app.can_open_new_window()
      ) {
        maybeAnimate()
        this.app.open_new_window(-1)
      } else {
        let windows = this.window ? [this.window] : this.app.get_windows()

        if (windows.length) {
          Main.activateWindow(windows[0])
        } else {
          maybeAnimate()
          this.app.activate()
        }
      }
    }

    _updateWindows() {
      let windows = [this.window]
    }
  },
)
