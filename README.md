# Linux Configuration Setup

> Part of [installation_scripts](https://github.com/mikaeltorni/installation_scripts) — the master installer that orchestrates a productivity-focused Ubuntu 24.04 desktop setup (workspaces, hotkeys, window tiling, programming tools, and more). Tested on Ubuntu 24.04.4 LTS.

GNOME desktop configuration, autostart applications, and system settings.

Installer run logs and Python helper diagnostics are written to the
repository-local `.log/` directory.

## Repository dependencies

This repository installs and runs **standalone** — it has no hard dependency on
any sibling setup repository.

- **Build-time (soft):** the shared installer component framework
  [`linux_installation_scripts_functions`](https://github.com/mikaeltorni/linux_installation_scripts_functions) —
  loaded from a sibling checkout when present, otherwise downloaded on demand,
  so a missing checkout never blocks installation.

See the full cross-repository map in
[installation_scripts/DEPENDENCIES.md](https://github.com/mikaeltorni/installation_scripts/blob/master/DEPENDENCIES.md).

## Overview

This repository configures the GNOME desktop environment after base packages are installed. It handles:

- **System configuration**: RTC to local time, clock/calendar display, screen auto-lock, and Restart/Power Off that reboots instead of returning to the login screen
- **Prompt-free credentials**: passwordless GNOME Login keyring for automatic-login sessions
- **Color scheme**: Dark by default; set `DESKTOP_COLOR_SCHEME=light` (or type `light` at the prompt) for light mode. `DESKTOP_GTK_THEME` / `DESKTOP_ICON_THEME` override the GTK/icon theme names
- **Cursor theme**: Bundled Purple Cross by default; set `CURSOR_SOURCE_FILE=/path/to/your.cur` (or type a path) to build the theme from your own cursor image
- **GNOME favorites**: Baseline desktop utilities plus favorite metadata
  published by application-owning repositories, including Baobab by default;
  the master installer forwards selected rows as `SELECTED_FAVORITE_APPS` and
  the complete managed set as `MANAGED_FAVORITE_APPS` so user-pinned PWAs and
  other unrelated dock favourites survive config reloads
- **Terminal themes**: Dark background/light text for Console, Ptyxis, GNOME Terminal
- **Kitty defaults**: Window behavior and Ctrl+Backspace word deletion
- **Optional Kitty input filter**: A default-on apostrophe-only `discard_event`
  mapping for bare Kitty consoles; tmux sessions receive apostrophes normally,
  and all other terminal input remains unchanged
- **Display refresh**: Xorg xrandr max refresh rate and mutter VRR cleared (NVIDIA X11 leftover VRR causes a ~16 Hz output-detect loop that lags mouse and typing); Wayland keeps mutter VRR
- **Autostart applications**: Spotify, GitKraken, SmartGit, EasyEffects, and Kitty
- **Seagate disks**: Mount present volumes whose labels start with `Seagate` at graphical login through UDisks, using the same `/media/$USER/<label>` path as Files. Missing disks are skipped.
- **App workspace rules** are installed by `linux_workspaces_setup`, the sole owner of `app-rules@local`.
- **Active-monitor placement**: Installs `~/.local/bin/pin-window-to-active-monitor.sh`, a runtime helper that moves a window to the monitor containing the mouse pointer. The open-kitty-and-sort hotkey (`linux_hotkey_window_tools`) calls it so newly-launched kitty windows stay on the active monitor even when the workspace is crowded and GNOME would have placed them on a different display.
- **UV package manager**: Install astral.sh/uv, deploy the global rolling 24-hour supply-chain cutoff, and disable GUI autostart
- **tmux defaults with full chat history**: Deploy `configs/tmux/.tmux.conf` to
  the target user's home with tmux's maximum accepted history limit
  (`2147483647` lines), which is effectively uncapped for complete agent chats

## Installation

```bash
# Run as root — it will configure everything for the target user
sudo bash install.sh
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `INSTALLER_NO_REBOOT` | `0` | Set to `1` to skip reboot message |
| `DESKTOP_COLOR_SCHEME` | `dark` | `dark` or `light` color scheme (`dark_mode` component) |
| `DESKTOP_GTK_THEME` | _(auto)_ | Override the GTK theme name (`dark_mode` component) |
| `DESKTOP_ICON_THEME` | `Yaru` | Override the icon theme name (`dark_mode` component) |
| `FAVORITES_APPS` | _(installed apps)_ | Comma/space-separated `.desktop` ids for the dock (`favorites` component); full manual override |
| `SELECTED_FAVORITE_APPS` | _(unset)_ | Internal master-installer handoff: comma/space-separated program-menu favourites merged with baseline dock entries |
| `MANAGED_FAVORITE_APPS` | _(unset)_ | Internal master handoff: complete favourite-capable `.desktop` id set used to reconcile installer-owned dock entries while preserving unrelated favourites |
| `SELECTED_STARTUP_APPS` | _(unset)_ | Internal master handoff: semicolon-separated selected launcher groups; pipe separates filename alternatives |
| `MANAGED_STARTUP_APPS` | _(unset)_ | Internal master handoff: complete startup-capable launcher set. It is the reconciler's authority boundary — persisted entries outside it are preserved, so a partial handoff never deletes startup apps it was not told about |
| `KITTY_IGNORE_APOSTROPHE` | `on` | `on` consumes unmodified apostrophes outside tmux; `off` removes the filter (`kitty_ignore_apostrophe` component) |
| `TARGET_HOME_OVERRIDE` | Target user's passwd home | Override the target home for isolated installer tests/automation |
| `CURSOR_SOURCE_FILE` | bundled `purple_cross.cur` | Path to your own cursor image (`cursor_theme` component) |

These overrides are read from the environment on non-interactive runs (including
the master installer); on an interactive terminal each prompts with its default
pre-filled so you can edit or accept it.

The Kitty filter can be switched in place without running unrelated components:

```bash
KITTY_IGNORE_APOSTROPHE=off bash install.sh --select kitty_ignore_apostrophe
KITTY_IGNORE_APOSTROPHE=on bash install.sh --select kitty_ignore_apostrophe
```

## Idempotency

All configuration steps are idempotent:

- GSettings: uses `set_if_key_exists` pattern — no duplicate values
- Autostart entries: checks for existing `.desktop` files before creating
- Cursor theme: rebuilds the Purple Cross cursor at 48px for visibility, maps every discovered pointer/text/hover/drag/resize role back to it, updates both modern and legacy Xcursor default inheritance paths, and exposes the generated theme through `~/.icons/PurpleCrossDefault`

The `passwordless_keyring` component keeps Secret Service enabled but removes
its at-rest password. This prevents unlock dialogs during automatic login and
when applications access stored credentials. Existing items are migrated into
a verified replacement. Fresh automatic-login keyrings are first unlocked
silently through the empty-password service override; the migration helper
never opens a graphical authentication dialog. A genuinely password-protected
keyring must be unlocked once before rerunning the component so its credentials
can be preserved. A one-shot user service activates a migrated replacement
before GNOME Keyring starts on the next reboot, and the GNOME Keyring user
service keeps using the empty-password unlock path across later daemon starts.
The migration retains the prior encrypted files under
`~/.local/state/linux-configuration-setup/keyring-backups/` for rollback. The
passwordless keyring is not protected by an at-rest password.

## Development

Run the shell and Python tests before changing installer behavior:

```bash
bash tests/test_cursor_theme.sh
bash tests/test_gnome_desktop.sh
bash tests/test_shell_helpers.sh
bash tests/test_active_monitor_placement.sh
cargo test
python3 -m unittest discover -s tests -p 'test_*.py'
```

## Structure

```
linux_configuration_setup/
├── install.sh              # Configuration entry point
├── lib/
│   ├── helpers.sh          # Repository-specific helpers and Python selection
│   ├── logging.sh          # Centralized logging with levels
│   ├── gsettings_helpers.sh  # GSettings/dconf helper functions
│   ├── lcs_bin.sh            # Resolves/builds the lcs-tools Rust helper
│   ├── system_config.sh      # RTC, clock, lock, immediate restart, dark mode, mouse accel
│   ├── autostart.sh          # Unified master-selected application startup
│   ├── active_monitor.sh     # Active-monitor placement (CLI helper + Shell extension)
│   ├── cursor_theme.sh       # Purple Cross cursor build, aliases, and defaults
│   ├── dash_to_panel.sh      # Dash-to-Panel layout and login re-apply
│   ├── desktop_stall.sh      # Rare NVIDIA/input stall episode capture
│   └── gnome_desktop.sh      # GNOME desktop config (favorites, terminal themes, display, extensions)
├── scripts/
│   ├── logging_utils.py      # Centralized Python logging and call tracing
│   ├── keyring_snapshot.py   # Secret Service export/import helper
│   ├── pin-window-to-active-monitor.sh  # Move a window to the pointer's monitor
│   ├── activate_passwordless_keyring.sh  # Next-boot keyring activator
│   ├── reapply_dash_to_panel.sh  # Graphical-login Dash-to-Panel enablement
│   └── desktop_stall_capture.sh  # Journal watcher for DFP/uinput stall dumps
├── src/                    # lcs-tools (GSettings arrays + metadata pin)
├── configs/
│   ├── tmux/.tmux.conf            # tmux user defaults
│   ├── uv/uv.toml                 # global rolling publication cutoff
│   ├── cursors/
│   │   └── purple_cross.cur    # Purple Cross cursor theme asset
│   ├── systemd/
│   │   ├── dash-to-panel-reapply.service  # Graphical-login Dash-to-Panel enablement
│   │   └── desktop-stall-capture.service  # User service watching DFP/uinput stalls
│   └── gnome-extensions/
│       └── active-monitor-placement@local/  # New windows → pointer/active monitor
└── .gitignore
```

## Active monitor placement (`active_monitor_placement`)

When a monitor is crowded, GNOME/Mutter often places a newly opened window on
another display (commonly the second monitor). The `active_monitor_placement`
component fixes that system-wide:

1. **`active-monitor-placement@local`** — GNOME Shell extension that listens for
   `window-created`, rechecks after short delays (WM placement is async), and
   moves normal (non–skip-taskbar) windows onto the pointer/current monitor when
   they landed elsewhere. Pure decision logic lives in `placementPolicy.js` so
   it is unit-tested without a live Shell. Applications that carry an explicit
   monitor rule in `~/.config/app-rules/user-rules.json` (written by the master
   installer's `[m]` menu action) are skipped, so a pinned display always wins
   over the pointer heuristic.
2. **`pin-window-to-active-monitor.sh`** — CLI helper in `~/.local/bin/` for
   scripts (notably `open-kitty-and-sort`) that already pin a specific window ID.

Both artifacts are installed by default (`on` in the component menu). After
deploy, enable is persisted in `enabled-extensions`; if the Shell does not load
new extension code mid-session, log out and back in (installers never kill
GNOME Shell).

## App Workspace Rules (app-rules@local)

Install and configure app rules through `linux_workspaces_setup` and its
`app_rules` component. It owns the extension and saved 1-based monitor rules,
including screen-position matching and deferred moves for mapped windows.
This repository no longer bundles, installs, detects, or removes that extension.
Legacy shell helper calls are harmless no-ops, preserving the installed owner.
This also prevents a configuration-only reinstall from reverting monitor pins.

Window-count badges are owned by `linux_taskbar_window_count` and installed separately from that repository.

## Dependencies

This repo is run **after** `linux_installations_setup` has cloned it. It requires:
- GNOME Shell running with GSettings available
- Target user's session bus at `$XDG_RUNTIME_DIR/bus`
- `lcs-tools` (Rust, `src/`) for GSettings string-array edits, extension metadata pinning, and CUR-to-PNG cursor extraction
- `xcursorgen` for rebuilding the Purple Cross cursor theme

## Troubleshooting

- If the Purple Cross cursor does not appear immediately everywhere, restart affected applications. Some Wayland and XWayland clients cache cursor themes after startup.
- The installer writes `~/.local/share/icons/default/index.theme` and `~/.icons/default/index.theme`, then links `~/.icons/PurpleCrossDefault` to the generated theme so applications that read Xcursor defaults outside GNOME GSettings can load it.
- GitKraken, SmartGit, Spotify, EasyEffects, Albert, Cursor, and the other application
  launchers use the master menu's `[S]` selection as their single startup
  authority. The reconciler removes obsolete legacy aliases to prevent duplicate
  launches, but only for applications the current run manages.
- `[S]` reconciliation is scoped to `MANAGED_STARTUP_APPS`. A run that only
  describes part of the selection — a single-component run
  (`--select selected_app_autostart`), a repository subset, or a direct child
  installer invocation — leaves every persisted entry outside that set on disk
  and re-records it in
  `~/.local/state/linux-configuration-setup/selected-app-autostart.list`. Pass
  the complete managed superset whenever you want cleared `[S]` markers to
  actually remove launchers.
- Log out and back in before testing GNOME Shell extension code changes.
- PWAs (Monkeytype, ChatGPT, Claude, etc.) are installed manually from Chrome — this repo no longer creates their desktop entries, icons, or autostart files. Once you have installed a PWA, the `app-rules@local` extension assigns its window to the mapped workspace. Monkeytype is excluded from pointer-monitor placement so that pin can keep it on monitor 2. If a PWA does not land on its workspace, verify the extension is enabled and that the PWA's window class matches a rule.
- Dash-to-Panel is configured with one isolated panel per monitor. Its pinned
  v73 source is patched during installation so a new window launched from a
  panel icon is explicitly moved to that panel's monitor. A user systemd
  oneshot (`dash-to-panel-reapply.service`, pulled in by
  `graphical-session-pre.target`) re-applies enablement at every graphical
  login: it clears `org.gnome.shell disable-user-extensions`, keeps
  Dash-to-Panel in `enabled-extensions`, and keeps Ubuntu Dock out. That
  survives the GNOME crash kill-switch that otherwise leaves the extension
  installed but `Enabled: No` after reboot. Uninstalling `dash_to_panel`
  removes the oneshot and restores Ubuntu Dock.

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
bash install.sh --list-selected-startup-apps
                                # read persisted master-managed startup choices
```

`--list-selected-startup-apps` is a read-only internal contract used by the
master installer to restore `[S]` menu markers. It emits persisted selections
and enabled live autostart basenames; the master matches those against declared
application metadata. This adopts launchers from older installers without
claiming unrelated user entries.

In the interactive menu, **space** toggles a component, `a`/`n` select all
or none, and **Enter** installs the selection. Components:

| Component id | Description | Default |
|---|---|---|
| `rtc` | Local-time RTC (dual-boot clock fix) | on |
| `clock_calendar` | Clock and calendar display | on |
| `disable_auto_lock` | Disable screen auto-lock | on |
| `session_restart` | Restart and power off without returning to the login screen | on |
| `passwordless_keyring` | Prompt-free login keyring | on |
| `dark_mode` | Color scheme and themes (override with `DESKTOP_COLOR_SCHEME`) | on |
| `mouse_accel` | Disable mouse acceleration | on |
| `hide_hotplug_joysticks` | Hide Crosswind/test uinput from Xorg (NVIDIA lag) | on |
| `desktop_stall_capture` | Log rare NVIDIA/input desktop stall episodes | on |
| `seagate_mount` | Mount Seagate-labelled disks at desktop login | on |
| `favorites` | Dock favorite apps (override with `FAVORITES_APPS`) | on |
| `cursor_theme` | Purple cross cursor theme (override with `CURSOR_SOURCE_FILE`) | on |
| `terminal_theme` | Terminal dark theme | on |
| `display_refresh` | Display refresh rate / VRR | on |
| `autostart_apps` | General autostart applications | on |
| `selected_app_autostart` | Master-selected app startup (`s` in app menu) | on |
| `kitty_defaults` | Kitty terminal defaults (window behavior and word deletion) | on |
| `kitty_ignore_apostrophe` | Ignore apostrophe input in bare Kitty consoles, but not inside tmux | on |
| `active_monitor_placement` | Pin new windows to the active/pointer monitor (session extension + CLI helper) | on |
| `uv_setup` | UV package manager and supply-chain protection | on |
| `tmux_defaults` | Tmux defaults with full chat history | on |
| `dash_to_panel` | Dash-to-Panel layout (replaces Ubuntu Dock) | on |

## Detect, reconfigure, and uninstall

This installer tracks what it has installed and can re-apply or remove it, so you
can refresh configuration after a repo update or cleanly back a feature out.

```bash
bash install.sh --detect            # show each component as installed|absent
bash install.sh --reconfigure a,b   # re-apply (idempotent) these component ids
bash install.sh --uninstall a,b     # uninstall these component ids
```

In the interactive menu (run `bash install.sh` on a terminal, or via the master
installer), already-installed components show a green `✓`. Select one with
**space** to **reconfigure** it (`~`), press **`u`** to mark it for **uninstall**
(`✗`), or press **`r`** to reconfigure every installed component at once. Detection
uses a live check where deterministic and otherwise an install receipt under
`${XDG_STATE_HOME:-~/.local/state}/isc/receipts/`; a component without a reversal
step simply clears that receipt on uninstall.

Three reversals are worth spelling out. Uninstalling `terminal_theme` resets every
terminal key it set back to that terminal's own schema default (it never writes a
second theme), and uninstalling `kitty_defaults` removes only the settings this
repo appended to `~/.config/kitty/kitty.conf` — the rest of your kitty config,
and the file itself, are left alone. Uninstalling `kitty_ignore_apostrophe`
removes only its bare-console apostrophe mapping and preserves tmux input,
modifier combinations, and every other shortcut. `passwordless_keyring` deliberately has no
reversal: re-locking the login keyring would need a password the installer does
not have, and guessing wrong would cut you off from your stored secrets.

## Disclaimer

This software is provided under the MIT License on an **“as is”** basis, without warranties of any kind. To the maximum extent permitted by applicable law, the authors and copyright holders shall not be liable for any claims, damages, losses, or other liability arising from the use of this software.

You are solely responsible for determining whether this software is suitable, safe, lawful, and appropriate for your intended use. Unless explicitly stated otherwise, this project is general-purpose software and is not designed, tested, certified, or approved for safety-critical, medical, automotive, aviation, industrial-control, life-support, cybersecurity-critical, financial-critical, or other high-risk use cases.

The authors and copyright holders make no guarantees regarding security, reliability, availability, correctness, compliance, non-infringement, or fitness for any particular purpose.

This notice is intended to clarify the nature of the project and does not impose additional restrictions beyond the MIT License.
