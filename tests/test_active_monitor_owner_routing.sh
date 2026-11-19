#!/usr/bin/env bash
# Exercise legacy component routing with an isolated target and sibling owner.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/home" "$scratch/bin" "$scratch/linux_active_monitor_placement"
git -C "$root" archive HEAD | tar -x -C "$scratch" --transform='s,^,config-owner/,'
for command in gsettings gnome-extensions gdbus dconf sudo; do
    printf '#!/bin/sh\nexit 98\n' > "$scratch/bin/$command"
    chmod +x "$scratch/bin/$command"
done
cat > "$scratch/linux_active_monitor_placement/install.sh" <<'SH'
#!/usr/bin/env bash
set -eu
[[ "$TARGET_HOME_OVERRIDE" == "$HOME" ]]
case "$*" in
    '--select active_monitor_placement') touch "$HOME/installed" ;;
    '--detect') if [[ -f "$HOME/installed" ]]; then state=installed; else state=absent; fi
        printf 'active_monitor_placement\t%s\n' "$state"; exit ;;
    '--uninstall active_monitor_placement') rm "$HOME/installed" ;;
    *) exit 99 ;;
esac
printf '%s\n' "$*" >> "$HOME/owner-actions"
SH
export HOME="$scratch/home" TARGET_HOME_OVERRIDE="$scratch/home" PATH="$scratch/bin:/usr/bin:/bin"
export ISC_LOG_DIR="$scratch/log" INSTALLER_NO_REBOOT=1
unset ACTIVE_MONITOR_PLACEMENT_DIR ISC_COMPONENT_LIB_DIR ISC_FUNCTIONS_DIR
install="$scratch/config-owner/install.sh"
# Copy the code under test to keep the fixture identical before and after edits.
cp "$root"/lib/{active_monitor,lifecycle}.sh "$scratch/config-owner/lib/"
bash "$install" --select active_monitor_placement > "$scratch/selection" 2>&1
test -f "$HOME/installed" || { printf 'Standalone owner was not called\n' >&2; exit 1; }
[[ "$(bash "$install" --detect 2>/dev/null)" == *$'active_monitor_placement\tinstalled'* ]]
bash "$install" --reconfigure active_monitor_placement >/dev/null 2>&1
bash "$install" --uninstall active_monitor_placement >/dev/null 2>&1
[[ "$(bash "$install" --detect 2>/dev/null)" == *$'active_monitor_placement\tabsent'* ]]
[[ "$(cat "$HOME/owner-actions")" == $'--select active_monitor_placement\n--select active_monitor_placement\n--uninstall active_monitor_placement' ]]
[[ ! -e "$HOME/.local/bin/pin-window-to-active-monitor.sh" ]]
printf 'PASS: legacy active-monitor selection, detection, reconfigure and removal delegate to the sibling owner\n'
