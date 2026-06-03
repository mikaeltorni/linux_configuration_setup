# Linux Configuration Setup

**Phase 2 of 7** — GNOME desktop configuration, autostart applications, and system settings.

## Overview

This repository configures the GNOME desktop environment after base packages are installed. It handles:

- **System configuration**: RTC to local time, clock/calendar display, screen auto-lock
- **Dark mode**: GTK theme, icon theme, cursor theme (Purple Cross)
- **GNOME favorites**: Taskbar/dock favorite apps with terminal detection
- **Terminal themes**: Dark background/light text for Console, Ptyxis, GNOME Terminal
- **Display refresh**: Xorg xrandr max refresh rate or Wayland VRR
- **Autostart applications**: Spotify, GitKraken, EasyEffects, custom launcher script
- **EasyEffects presets**: Output EQ preset (scout-eq.json)
- **Chrome PWA icons**: Symlinks and desktop entries for Chrome progressive web apps
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
│   ├── autostart.sh          # Autostart entries for apps
│   └── gnome_desktop.sh      # GNOME desktop config (favorites, cursor, themes)
├── configs/
│   ├── easyeffects/
│   │   └── output/
│   │       └── scout-eq.json    # EasyEffects output EQ preset
│   └── equalizer.apo            # APO equalizer config (reference)
└── .gitignore
```

## Dependencies

This repo is run **after** `linux_installations_setup` has cloned it. It requires:
- GNOME Shell running with GSettings available
- Target user's session bus at `$XDG_RUNTIME_DIR/bus`
- `python3` for safe GSettings list parsing

## License

MIT

## Disclaimer

This software is provided under the MIT License on an **“as is”** basis, without warranties of any kind. To the maximum extent permitted by applicable law, the authors and copyright holders shall not be liable for any claims, damages, losses, or other liability arising from the use of this software.

You are solely responsible for determining whether this software is suitable, safe, lawful, and appropriate for your intended use. Unless explicitly stated otherwise, this project is general-purpose software and is not designed, tested, certified, or approved for safety-critical, medical, automotive, aviation, industrial-control, life-support, cybersecurity-critical, financial-critical, or other high-risk use cases.

The authors and copyright holders make no guarantees regarding security, reliability, availability, correctness, compliance, non-infringement, or fitness for any particular purpose.

This notice is intended to clarify the nature of the project and does not impose additional restrictions beyond the MIT License.
