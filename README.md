# Linux Configuration Setup

**Phase 2 of 7** — GNOME desktop configuration, autostart applications, and system settings.

Installer run logs are written to the repository-local `.log/` directory.

## Overview

This repository configures the GNOME desktop environment after base packages are installed. It handles:

- **System configuration**: RTC to local time, clock/calendar display, screen auto-lock
- **Dark mode**: GTK theme, icon theme, cursor theme (Purple Cross)
- **GNOME favorites**: Taskbar/dock favorite apps with terminal detection
- **Terminal themes**: Dark background/light text for Console, Ptyxis, GNOME Terminal
- **Display refresh**: Xorg xrandr max refresh rate or Wayland VRR
- **Autostart applications**: Spotify, GitKraken, EasyEffects, Monkeytype PWA, and Kitty
- **EasyEffects presets**: Output EQ preset (scout-eq.json)
- **Chrome PWA icons**: Symlinks and desktop entries for Chrome progressive web apps
- **PWA workspace rules**: `app-rules@local` GNOME extension assigns windows to specific workspaces (e.g., Monkeytype → workspace 7, ChatGPT → workspace 0)
- **UV package manager**: Install astral.sh/uv and disable GUI autostart

## Installation

```bash
# Run as root — it will configure everything for the target user
sudo bash install.sh
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `INSTALLER_NO_REBOOT` | `0` | Set to `1` to skip reboot message |

## Idempotency

All configuration steps are idempotent:
- GSettings: uses `set_if_key_exists` pattern — no duplicate values
- Autostart entries: checks for existing `.desktop` files before creating
- EasyEffects preset: only copies if source exists, overwrites in place
- PWA icons: creates symlinks and desktop entries only if missing
- Cursor theme: rebuilds the Purple Cross cursor, maps common pointer/hover/drag/resize roles back to it, and updates both modern and legacy Xcursor default inheritance paths

## Development

Run the shell and Python tests before changing installer behavior:

```bash
bash tests/test_gnome_desktop.sh
bash tests/test_shell_helpers.sh
python3 -m unittest discover -s tests -p 'test_*.py'
```

## Structure

```
linux_configuration_setup/
├── install.sh              # Configuration entry point
├── lib/
│   ├── helpers.sh          # Core utilities (msg, run_as_target, etc.)
│   ├── logging.sh          # Centralized logging with levels
│   ├── gsettings_helpers.sh  # GSettings/dconf helper functions
│   ├── systemd_helpers.sh    # Systemd user service management
│   ├── system_config.sh      # RTC, clock, lock, dark mode, mouse accel
│   ├── autostart.sh          # Autostart entries for apps (Spotify, GitKraken, EasyEffects, Monkeytype)
│   └── gnome_desktop.sh      # GNOME desktop config (favorites, cursor, themes, PWA icons, extensions)
├── configs/
│   ├── cursors/
│   │   └── purple_cross.cur    # Purple Cross cursor theme asset
│   ├── equalizer.apo           # APO equalizer config (reference)
│   ├── easyeffects/
│   │   └── output/
│   │       └── scout-eq.json   # EasyEffects output EQ preset
│   └── gnome-extensions/
│       └── app-rules@local/    # GNOME Shell extension: per-app workspace/sticky rules
└── .gitignore
```

## PWA Workspace Rules (app-rules@local)

The `app-rules@local` GNOME Shell extension assigns windows to specific workspaces or makes them sticky. It is deployed from `configs/gnome-extensions/app-rules@local/`.

Current rules:

| App | Workspace / Behavior |
|-----|----------------------|
| Cursor (cursor.desktop) | Workspace 0 |
| GitKraken | Workspace 2 |
| Monkeytype PWA | Workspace 7 |
| ChatGPT PWA | Workspace 0 |
| OBS Studio | Workspace 7 |
| Discord | Sticky (all workspaces) |
| Spotify | Sticky (all workspaces) |

**Note:** After modifying the extension, log out and back in for changes to take effect. GNOME Shell does not hot-reload extensions on Wayland.

## Dependencies

This repo is run **after** `linux_installations_setup` has cloned it. It requires:
- GNOME Shell running with GSettings available
- Target user's session bus at `$XDG_RUNTIME_DIR/bus`
- `python3` for safe GSettings list parsing
- `icotool` and `xcursorgen` for rebuilding the Purple Cross cursor theme (the installer installs `icoutils` and `x11-apps` when needed)

## Troubleshooting

- If the Purple Cross cursor does not appear immediately everywhere, restart affected applications. Some Wayland and XWayland clients cache cursor themes after startup.
- The installer writes `~/.local/share/icons/default/index.theme` and `~/.icons/default/index.theme` so applications that read Xcursor defaults outside GNOME GSettings still inherit `PurpleCrossDefault`.
- GitKraken uses only `~/.config/autostart/gitkraken.desktop`; the installer removes the obsolete `gitkraken-autostart.desktop` alias to prevent duplicate launches.
- Log out and back in before testing GNOME Shell extension code changes.
- Monkeytype PWA autostarts on login and opens on workspace 7 via the `app-rules@local` extension. If it doesn't appear on workspace 7, verify the extension is enabled and check that `monkeytype.desktop` exists in `~/.local/share/applications/`.

## License

MIT

## Disclaimer

This software is provided under the MIT License on an **“as is”** basis, without warranties of any kind. To the maximum extent permitted by applicable law, the authors and copyright holders shall not be liable for any claims, damages, losses, or other liability arising from the use of this software.

You are solely responsible for determining whether this software is suitable, safe, lawful, and appropriate for your intended use. Unless explicitly stated otherwise, this project is general-purpose software and is not designed, tested, certified, or approved for safety-critical, medical, automotive, aviation, industrial-control, life-support, cybersecurity-critical, financial-critical, or other high-risk use cases.

The authors and copyright holders make no guarantees regarding security, reliability, availability, correctness, compliance, non-infringement, or fitness for any particular purpose.

This notice is intended to clarify the nature of the project and does not impose additional restrictions beyond the MIT License.
