#!/usr/bin/env bash
# Exercise the Seagate mount helper and installer with temporary paths only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/labels" "$tmp/helper" "$tmp/home"
cp "$SCRIPT_DIR/scripts/mount_seagate_volumes.sh" "$tmp/helper/mount-seagate-volumes"
cp "$SCRIPT_DIR/lib/logging.sh" "$tmp/helper/logging.sh"

cat >"$tmp/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
grep -Fxq "${@: -1}" "$TEST_MOUNTED_FILE" 2>/dev/null
EOF
cat >"$tmp/bin/udisksctl" <<'EOF'
#!/usr/bin/env bash
[ "$1" = mount ] && [ "$2" = --no-user-interaction ] && [ "$3" = -b ]
printf '%s\n' "$4" >>"$TEST_CALLS_FILE"
[ "${TEST_FAIL_DEVICE:-}" != "$4" ] || exit 1
printf '%s\n' "$4" >>"$TEST_MOUNTED_FILE"
EOF
chmod +x "$tmp/bin/findmnt" "$tmp/bin/udisksctl"
export PATH="$tmp/bin:$PATH" SEAGATE_LABEL_DIR="$tmp/labels"
export TEST_MOUNTED_FILE="$tmp/mounted" TEST_CALLS_FILE="$tmp/calls"

"$tmp/helper/mount-seagate-volumes" >/dev/null 2>"$tmp/log"
grep -q 'No Seagate-labelled volume present' "$tmp/log"
ln -s /dev/null "$tmp/labels/Seagate"
ln -s /dev/zero "$tmp/labels/Seagate\\x20Backup"
ln -s /dev/full "$tmp/labels/Other"
"$tmp/helper/mount-seagate-volumes" >/dev/null 2>"$tmp/log"
[ "$(wc -l <"$tmp/calls")" -eq 2 ]
"$tmp/helper/mount-seagate-volumes" >/dev/null 2>"$tmp/log"
[ "$(wc -l <"$tmp/calls")" -eq 2 ]
rm -f "$tmp/mounted"
export TEST_FAIL_DEVICE=/dev/zero
if "$tmp/helper/mount-seagate-volumes" >/dev/null 2>"$tmp/log"; then
  echo 'Expected mount failure to make the service fail' >&2
  exit 1
fi
grep -q 'Could not mount Seagate volume: /dev/zero' "$tmp/log"

source "$SCRIPT_DIR/lib/seagate_mount.sh"
SCRIPT_DIR="$SCRIPT_DIR"
TARGET_HOME="$tmp/home"
run_as_target() { "$@"; }
msg() { :; }
source "$SCRIPT_DIR/lib/logging.sh"
cat >"$tmp/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_SYSTEMCTL_FILE"
EOF
chmod +x "$tmp/bin/systemctl"
export TEST_SYSTEMCTL_FILE="$tmp/systemctl"
configure_seagate_mount
detect_seagate_mount
grep -q 'enable --now seagate-volumes-mount.service' "$tmp/systemctl"
cmp "$SCRIPT_DIR/configs/systemd/seagate-volumes-mount.service" "$(seagate_mount_unit_path)"
configure_seagate_mount
[ "$(grep -c 'enable --now seagate-volumes-mount.service' "$tmp/systemctl")" -eq 2 ]
uninstall_seagate_mount
! detect_seagate_mount
echo 'Seagate mount tests passed'
