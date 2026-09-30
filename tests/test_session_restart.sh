#!/usr/bin/env bash
# test_session_restart.sh — Restart must not stop at the login screen.
#
# logind's delay window lets GNOME end the session before reboot.target starts.
# The session_restart component installs a logind drop-in that removes that wait.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=========================================="
echo "  Session restart tests"
echo "=========================================="

DROPIN_NAME="50-immediate-session-restart.conf"
ASSET="$ROOT_DIR/configs/logind/$DROPIN_NAME"

echo ""
echo "--- shipped logind drop-in ---"
if [[ -f "$ASSET" ]] && grep -qx 'InhibitDelayMaxSec=0' "$ASSET"; then
  pass "drop-in sets InhibitDelayMaxSec=0"
else
  fail "drop-in sets InhibitDelayMaxSec=0"
fi
if [[ -f "$ASSET" ]] && grep -qx '\[Login\]' "$ASSET"; then
  pass "drop-in is a logind Login section"
else
  fail "drop-in is a logind Login section"
fi

# shellcheck source=../lib/logging.sh
source "$ROOT_DIR/lib/logging.sh"

msg() { printf '%s\n' "$*"; }
SUDO_REQUIRED_STEPS=()
note_sudo_required() { SUDO_REQUIRED_STEPS+=("$1"); }
IS_ROOT=0
is_root() { [[ "$IS_ROOT" == "1" ]]; }

# shellcheck source=../lib/system_config.sh
source "$ROOT_DIR/lib/system_config.sh"
# shellcheck source=../lib/lifecycle.sh
source "$ROOT_DIR/lib/lifecycle.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export SESSION_RESTART_DROPIN_DEST="$TMP_DIR/logind.conf.d/$DROPIN_NAME"
export SESSION_RESTART_SYSTEMCTL_LOG="$TMP_DIR/systemctl.log"
mkdir -p "$TMP_DIR/bin"
cat >"$TMP_DIR/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${SESSION_RESTART_SYSTEMCTL_LOG:?}"
EOF
chmod +x "$TMP_DIR/bin/systemctl"
export PATH="$TMP_DIR/bin:$PATH"

echo ""
echo "--- non-root defers the root-only install ---"
: >"$SESSION_RESTART_SYSTEMCTL_LOG"
IS_ROOT=0
configure_session_restart
if [[ "${#SUDO_REQUIRED_STEPS[@]}" -eq 1 ]] &&
   [[ "${SUDO_REQUIRED_STEPS[0]}" == *"install -D -m 0644"* ]] &&
   [[ "${SUDO_REQUIRED_STEPS[0]}" == *"$ASSET"* ]] &&
   [[ "${SUDO_REQUIRED_STEPS[0]}" == *"systemctl reload systemd-logind"* ]]; then
  pass "non-root records the install and logind reload"
else
  fail "non-root records the install and logind reload (got: ${SUDO_REQUIRED_STEPS[*]:-none})"
fi
if [[ ! -s "$SESSION_RESTART_SYSTEMCTL_LOG" ]]; then
  pass "non-root does not reload logind"
else
  fail "non-root does not reload logind"
fi
if ! detect_session_restart; then
  pass "missing drop-in is not detected as installed"
else
  fail "missing drop-in is not detected as installed"
fi

echo ""
echo "--- root installs the drop-in and reloads logind ---"
IS_ROOT=1
configure_session_restart
if cmp -s "$ASSET" "$SESSION_RESTART_DROPIN_DEST"; then
  pass "root installs the shipped drop-in"
else
  fail "root installs the shipped drop-in"
fi
if [[ "$(cat "$SESSION_RESTART_SYSTEMCTL_LOG")" == "reload systemd-logind" ]]; then
  pass "root reloads systemd-logind"
else
  fail "root reloads systemd-logind (got: $(cat "$SESSION_RESTART_SYSTEMCTL_LOG"))"
fi
if detect_session_restart; then
  pass "installed drop-in is detected"
else
  fail "installed drop-in is detected"
fi

echo ""
echo "--- a matching drop-in is left in place ---"
: >"$SESSION_RESTART_SYSTEMCTL_LOG"
configure_session_restart
if [[ ! -s "$SESSION_RESTART_SYSTEMCTL_LOG" ]]; then
  pass "second install does not reload logind again"
else
  fail "second install does not reload logind again"
fi

echo ""
echo "--- uninstall removes the drop-in and reloads logind ---"
uninstall_session_restart
if [[ ! -e "$SESSION_RESTART_DROPIN_DEST" ]]; then
  pass "uninstall removes the drop-in"
else
  fail "uninstall removes the drop-in"
fi
if [[ "$(cat "$SESSION_RESTART_SYSTEMCTL_LOG")" == "reload systemd-logind" ]]; then
  pass "uninstall reloads systemd-logind"
else
  fail "uninstall reloads systemd-logind (got: $(cat "$SESSION_RESTART_SYSTEMCTL_LOG"))"
fi
if ! detect_session_restart; then
  pass "removed drop-in is not detected"
else
  fail "removed drop-in is not detected"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
