#!/usr/bin/env bash
# Integration test for prompt-free GNOME Keyring snapshot migration.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/scripts/keyring_snapshot.py"
ACTIVATOR="$ROOT_DIR/scripts/activate_passwordless_keyring.sh"
UNIT="$ROOT_DIR/configs/systemd/passwordless-keyring-activation.service"
UNLOCK_DROPIN="$ROOT_DIR/configs/systemd/gnome-keyring-daemon.service.d/passwordless-login-unlock.conf"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
PYTHON_BIN="${PYTHON_BIN:-/usr/bin/python3}"

test -x "$HELPER"
test -x "$ACTIVATOR"
test -f "$UNIT"
test -f "$UNLOCK_DROPIN"
rg -q 'passwordless_keyring\|Prompt-free login keyring\|on\|configure_passwordless_keyring' \
  "$ROOT_DIR/installer/components.sh"
rg -q 'source "\$SCRIPT_DIR/lib/keyring.sh"' "$ROOT_DIR/install.sh"
rg -q 'gnome-keyring-daemon --login' "$ROOT_DIR/lib/keyring.sh"
rg -q 'install -m 0644 "\$logging_lib"' "$ROOT_DIR/lib/keyring.sh"
rg -q 'source "\$script_dir/logging.sh"' "$ACTIVATOR"
rg -q 'dbus-run-session' "$ROOT_DIR/lib/keyring.sh"
rg -q 'find_python_with_module gi' "$ROOT_DIR/lib/keyring.sh"
rg -q '"\$python_bin" "\$helper" export' "$ROOT_DIR/lib/keyring.sh"
rg -q 'passwordless-keyring-pending' "$ROOT_DIR/lib/keyring.sh"
rg -q 'gnome-keyring-daemon.service.d/passwordless-login-unlock.conf' "$ROOT_DIR/lib/keyring.sh"
rg -q 'Before=gnome-keyring-daemon.socket gnome-keyring-daemon.service' "$UNIT"
rg -q 'WantedBy=sockets.target' "$UNIT"
rg -q '^ExecStart=$' "$UNLOCK_DROPIN"
rg -q 'gnome-keyring-daemon --foreground --unlock --components=pkcs11,secrets --control-directory=%t/keyring' "$UNLOCK_DROPIN"
rg -q '^StandardInput=data$' "$UNLOCK_DROPIN"
rg -q '^StandardInputData=Cg==$' "$UNLOCK_DROPIN"
if rg -q 'systemctl --user stop|kill|pkill|killall' "$ROOT_DIR/lib/keyring.sh"; then
  echo "keyring migration must not terminate the live desktop daemon" >&2
  exit 1
fi
if rg -q 'systemctl|kill|pkill|killall' "$ACTIVATOR"; then
  echo "keyring activation must not manage the live daemon" >&2
  exit 1
fi

run_keyring_session() {
  local home="$1" password="$2" command="$3"
  mkdir -p "$home"
  chmod 700 "$home"
  HOME="$home" XDG_CONFIG_HOME="$home/.config" \
    dbus-run-session -- bash -euo pipefail -c '
      export XDG_RUNTIME_DIR="$HOME/runtime"
      mkdir -p "$XDG_RUNTIME_DIR"
      chmod 700 "$XDG_RUNTIME_DIR"
      printf "%s\n" "$1" | gnome-keyring-daemon --login >/dev/null
      eval "$(gnome-keyring-daemon --start --components=secrets)"
      bash -euo pipefail -c "$2"
    ' bash "$password" "$command"
}

SOURCE_HOME="$SANDBOX/source"
DEST_HOME="$SANDBOX/destination"
ACTIVE_HOME="$SANDBOX/active"
SNAPSHOT="$SANDBOX/items.json"

run_keyring_session "$SOURCE_HOME" "test-password" \
  "'$PYTHON_BIN' '$HELPER' store-test-item account demo 'test-secret'; '$PYTHON_BIN' '$HELPER' export '$SNAPSHOT'"

test "$(stat -c %a "$SNAPSHOT")" = 600
"$PYTHON_BIN" - "$SNAPSHOT" <<'PY'
import json
import sys

items = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(items) == 2
text_item = next(item for item in items if item["label"] == "Migration test")
assert text_item["attributes"] == {"account": "demo", "xdg:schema": "keyring.migration.test"}
assert text_item["secret"] != "test-secret"
PY

run_keyring_session "$DEST_HOME" "" \
  "'$PYTHON_BIN' '$HELPER' import '$SNAPSHOT'; '$PYTHON_BIN' '$HELPER' verify-test-item account demo 'test-secret'"

test "$(cat "$DEST_HOME/.local/share/keyrings/default")" = login

# Reopen the generated files in a fresh daemon to prove that an empty PAM login
# password unlocks the on-disk keyring, not merely the process that created it.
run_keyring_session "$DEST_HOME" "" \
  "'$PYTHON_BIN' '$HELPER' check; '$PYTHON_BIN' '$HELPER' verify-test-item account demo 'test-secret'"

# Reproduce the systemd foreground daemon path. Without --unlock this path
# leaves Login locked; the installed drop-in starts the daemon with one empty
# password line on stdin.
HOME="$DEST_HOME" XDG_CONFIG_HOME="$DEST_HOME/.config" \
  dbus-run-session -- bash -euo pipefail -c '
    export XDG_RUNTIME_DIR="$HOME/runtime-systemd"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    printf "\n" | gnome-keyring-daemon --foreground --unlock \
      --components=secrets --control-directory="$XDG_RUNTIME_DIR/keyring" \
      >/dev/null 2>&1 &
    daemon_pid=$!
    trap "kill $daemon_pid 2>/dev/null || true" EXIT
    for _ in 1 2 3 4 5; do
      "$2" "$1" check >/dev/null 2>&1 && exit 0
      sleep 0.2
    done
    "$2" "$1" check
  ' bash "$HELPER" "$PYTHON_BIN"

# Activation happens while no daemon is touching the files. Verify that it
# preserves the encrypted originals, installs the staged keyring, and is safe
# to invoke again after completion.
mkdir -p "$ACTIVE_HOME/.local/share" \
  "$ACTIVE_HOME/.local/state/linux-configuration-setup/passwordless-keyring-pending"
cp -a "$SOURCE_HOME/.local/share/keyrings" "$ACTIVE_HOME/.local/share/"
cp -a "$DEST_HOME/.local/share/keyrings/." \
  "$ACTIVE_HOME/.local/state/linux-configuration-setup/passwordless-keyring-pending/"
touch "$ACTIVE_HOME/.local/state/linux-configuration-setup/passwordless-keyring-pending/ready"

original_hashes="$(find "$ACTIVE_HOME/.local/share/keyrings" -maxdepth 1 -type f \
  \( -name '*.keyring' -o -name default \) -print0 |
  sort -z | xargs -0 sha256sum | sed "s|$ACTIVE_HOME/.local/share/keyrings/||")"
HOME="$ACTIVE_HOME" XDG_STATE_HOME="$ACTIVE_HOME/.local/state" "$ACTIVATOR"
HOME="$ACTIVE_HOME" XDG_STATE_HOME="$ACTIVE_HOME/.local/state" "$ACTIVATOR"

test -f "$ACTIVE_HOME/.local/state/linux-configuration-setup/passwordless-keyring-v1"
test ! -e "$ACTIVE_HOME/.local/state/linux-configuration-setup/passwordless-keyring-pending"
backup_dir="$(find "$ACTIVE_HOME/.local/state/linux-configuration-setup/keyring-backups" \
  -mindepth 1 -maxdepth 1 -type d -name 'pre-passwordless-*' -print -quit)"
test -n "$backup_dir"
backup_hashes="$(find "$backup_dir" -maxdepth 1 -type f -print0 |
  sort -z | xargs -0 sha256sum | sed "s|$backup_dir/||")"
test "$backup_hashes" = "$original_hashes"
run_keyring_session "$ACTIVE_HOME" "" \
  "'$PYTHON_BIN' '$HELPER' check; '$PYTHON_BIN' '$HELPER' verify-test-item account demo 'test-secret'"

echo "passwordless keyring tests passed"
