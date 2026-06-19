# Linux Configuration Setup

> Part of [installation_scripts](https://github.com/mikaeltorni/installation_scripts) — the master installer that orchestrates a productivity-focused Ubuntu 24.04 desktop setup (workspaces, hotkeys, window tiling, programming tools, and more). Tested on Ubuntu 24.04.4 LTS.

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
- **Chrome PWA icons**: Symlinks and desktop entries for installed Chrome progressive web apps, including Claude
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
- PWA icons: repairs icon links for every available size and refreshes desktop entries with direct icon paths
- Cursor theme: rebuilds the Purple Cross cursor, maps common pointer/hover/drag/resize roles back to it, and updates both modern and legacy Xcursor default inheritance paths

## Development

Run the shell and Python tests before changing installer behavior:

```bash
bash tests/test_cursor_theme.sh
bash tests/test_gnome_desktop.sh
bash tests/test_pwa_icons.sh
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
│   ├── system_config.sh      # RTC, clock, lock, dark mode, mouse accel
│   ├── autostart.sh          # Autostart entries for apps (Spotify, GitKraken, EasyEffects, Monkeytype)
│   ├── cursor_theme.sh       # Purple Cross cursor build, aliases, and defaults
│   ├── gnome_desktop.sh      # GNOME desktop config (favorites, terminal themes, display, extensions)
│   └── pwa_icons.sh          # Chrome PWA desktop entries and icon links
├── configs/
│   ├── cursors/
│   │   └── purple_cross.cur    # Purple Cross cursor theme asset
│   ├── equalizer.apo           # APO equalizer config (reference)
│   ├── easyeffects/
│   │   └── output/
│   │       └── scout-eq.json   # EasyEffects output EQ preset
│   └── gnome-extensions/
│       ├── app-rules@local/    # GNOME Shell extension: per-app workspace/sticky rules
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

Window-count badges are owned by `linux_taskbar_window_count` and installed separately from that repository.

## Dependencies

This repo is run **after** `linux_installations_setup` has cloned it. It requires:
- GNOME Shell running with GSettings available
- Target user's session bus at `$XDG_RUNTIME_DIR/bus`
- `python3` for safe GSettings list parsing
- Pillow (`python3-pil`) and `xcursorgen` for rebuilding the Purple Cross cursor theme

## Troubleshooting

- If the Purple Cross cursor does not appear immediately everywhere, restart affected applications. Some Wayland and XWayland clients cache cursor themes after startup.
- The installer writes `~/.local/share/icons/default/index.theme` and `~/.icons/default/index.theme` so applications that read Xcursor defaults outside GNOME GSettings still inherit `PurpleCrossDefault`.
- GitKraken uses only `~/.config/autostart/gitkraken.desktop`; the installer removes the obsolete `gitkraken-autostart.desktop` alias to prevent duplicate launches.
- Log out and back in before testing GNOME Shell extension code changes.
- Monkeytype PWA autostarts on login and opens on workspace 7 via the `app-rules@local` extension. If it doesn't appear on workspace 7, verify the extension is enabled and check that `monkeytype.desktop` exists in `~/.local/share/applications/`.

## License

MIT

## Component selection

This repository's `install.sh` participates in the shared installer
component menu (see the [`installation_scripts`](https://github.com/mikaeltorni/installation_scripts)
master installer). Run standalone, it offers an interactive submenu on a
terminal; the master installer drives it non-interactively.

```bash
bash install.sh                 # interactive component selection (TTY), else defaults
bash install.sh --default       # install all default-on components, no prompts
bash install.sh --all           # install every component, no prompts
bash install.sh --select a,b    # install exactly these component ids
bash install.sh --list-components  # print: id<TAB>label<TAB>default
```

In the interactive menu, **space** toggles a component, `a`/`n` select all
or none, and **Enter** installs the selection. Components:

| Component id | Description | Default |
|---|---|---|
| `rtc` | Local-time RTC (dual-boot clock fix) | on |
| `clock_calendar` | Clock and calendar display | on |
| `disable_auto_lock` | Disable screen auto-lock | on |
| `dark_mode` | Dark mode and themes | on |
| `mouse_accel` | Disable mouse acceleration | on |
| `favorites` | Dock favorite apps | on |
| `cursor_theme` | Purple cross cursor theme | on |
| `terminal_theme` | Terminal dark theme | on |
| `display_refresh` | Display refresh rate / VRR | on |
| `spotify_autostart` | Spotify autostart | on |
| `gitkraken_autostart` | GitKraken autostart | on |
| `autostart_apps` | General autostart applications | on |
| `kitty_defaults` | Kitty terminal defaults | on |
| `easyeffects` | EasyEffects autostart and EQ presets | on |
| `pwa_icons` | Chrome PWA icons and desktop entries | on |
| `monkeytype_autostart` | Monkeytype autostart | on |
| `app_rules` | App window rules extension | on |
| `uv_setup` | UV package manager setup | on |
| `tmux_defaults` | Tmux defaults | on |


## Disclaimer

This software is provided under the MIT License on an **“as is”** basis, without warranties of any kind. To the maximum extent permitted by applicable law, the authors and copyright holders shall not be liable for any claims, damages, losses, or other liability arising from the use of this software.

You are solely responsible for determining whether this software is suitable, safe, lawful, and appropriate for your intended use. Unless explicitly stated otherwise, this project is general-purpose software and is not designed, tested, certified, or approved for safety-critical, medical, automotive, aviation, industrial-control, life-support, cybersecurity-critical, financial-critical, or other high-risk use cases.

The authors and copyright holders make no guarantees regarding security, reliability, availability, correctness, compliance, non-infringement, or fitness for any particular purpose.

This notice is intended to clarify the nature of the project and does not impose additional restrictions beyond the MIT License.
