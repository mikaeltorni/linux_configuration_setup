#!/usr/bin/env bash
# Exercise the public component installer in an isolated home.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
home="$(mktemp -d)"
trap 'rm -rf "$home"' EXIT
export TARGET_HOME_OVERRIDE="$home" HOME="$home" XDG_STATE_HOME="$home/state" INSTALLER_NO_REBOOT=1
export KITTY_BLE_ARCHIVE="${KITTY_BLE_ARCHIVE:?set KITTY_BLE_ARCHIVE to the pinned ble.sh release archive}"
printf '%s\n' '# personal shell configuration' > "$home/.bashrc"
printf 'invalid archive' > "$home/invalid.tar.xz"
if KITTY_BLE_ARCHIVE="$home/invalid.tar.xz" bash "$root/scripts/kitty_shell_highlighting.sh" install; then
  printf 'invalid archive was accepted\n' >&2
  exit 1
fi
grep -qx '# personal shell configuration' "$home/.bashrc"
listing="$(bash "$root/install.sh" --list-components)"
grep -q '^kitty_shell_highlighting[[:space:]]' <<<"$listing"
bash "$root/install.sh" --select kitty_shell_highlighting
[ -f "$home/.local/share/kitty-blesh/ble.sh" ]
grep -q 'kitty-blesh/ble.sh' "$home/.bashrc"
grep -q '# personal shell configuration' "$home/.bashrc"
python3 "$root/tests/kitty_shell_highlighting_pty.py" "$home"
bash "$root/install.sh" --select kitty_shell_highlighting
[ "$(grep -c '# kitty-shell-highlighting begin' "$home/.bashrc")" -eq 2 ]
listing="$(bash "$root/install.sh" --detect)"
grep -q '^kitty_shell_highlighting[[:space:]]installed' <<<"$listing"
bash "$root/install.sh" --uninstall kitty_shell_highlighting
! grep -q 'kitty-blesh/ble.sh' "$home/.bashrc"
grep -q '# personal shell configuration' "$home/.bashrc"
printf 'Kitty shell highlighting component passed\n'
