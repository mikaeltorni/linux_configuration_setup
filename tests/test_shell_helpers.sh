#!/usr/bin/env bash
# test_shell_helpers.sh — Shell helper simulation tests.
# Runs without modifying the system (no GSettings changes, no package installs).

set -uo pipefail  # Note: -e removed so a failed assertion doesn't abort the run

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PASS=0
FAIL=0

pass_test() { printf "  PASS: %s\n" "$1"; PASS=$((PASS + 1)); }
fail_test() { printf "  FAIL: %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

cd "$ROOT_DIR"

# ── Set up required environment BEFORE sourcing helpers.sh ───────────────────
TARGET_HOME="/tmp/test_target_home_$$"
RUNTIME_DIR="/run/user/1000"
DISPLAY_VAL=":0"
USER_BUS="unix:path=$RUNTIME_DIR/bus"
mkdir -p "$TARGET_HOME/.local/share/applications"
touch "$TARGET_HOME/.local/share/applications/custom.desktop"

# ── helpers.sh tests ────────────────────────────────────────────────────────
# Shared helpers (need_cmd, apt_install, run_as_target, …) live in the framework;
# repo-specific helpers (find_desktop_*) live in lib/helpers.sh.
log() { :; }  # silence the framework helpers' debug logging in this harness
source "$ROOT_DIR/../linux_installation_scripts_functions/installer_helpers.sh"
source lib/helpers.sh

# Test need_cmd returns correct exit codes for existing command
if need_cmd bash; then
    pass_test "need_cmd returns true for existing command (bash)"
else
    fail_test "need_cmd" "should return true for bash"
fi

# Test need_cmd returns false for non-existent command
if ! need_cmd nonexistent_command_xyz123; then
    pass_test "need_cmd returns false for non-existent command"
else
    fail_test "need_cmd" "should return false for nonexistent_command_xyz123"
fi

# Test find_desktop_file_path searches correct directories
test_find_desktop() {
    local name="$1" expected_path="$2"
    if [ -n "${expected_path:-}" ]; then
        result="$(find_desktop_file_path "$name")" || true
        if [ "$result" = "$expected_path" ]; then
            pass_test "find_desktop_file_path finds $name at correct path"
        else
            fail_test "find_desktop_file_path" "expected $expected_path, got ${result:-<none>}"
        fi
    else
        if find_desktop_file_path "$name" >/dev/null 2>&1; then
            fail_test "find_desktop_file_path" "should not find $name"
        else
            pass_test "find_desktop_file_path correctly rejects missing file"
        fi
    fi
}

test_find_desktop "custom.desktop" "$TARGET_HOME/.local/share/applications/custom.desktop"
test_find_desktop "nonexistent.desktop" ""

# Test find_desktop_entry returns basename of first match
result="$(find_desktop_entry custom.desktop nonexistent.desktop)" || true
if [ "$result" = "custom.desktop" ]; then
    pass_test "find_desktop_entry returns basename of first match"
else
    fail_test "find_desktop_entry" "expected 'custom.desktop', got '${result:-<none>}'"
fi

# Test apt_install skips already-installed packages (no apt-get invocation)
# dpkg reports success (installed); apt-get is mocked to record any calls.
test_apt_install_skip() {
    local marker="$TARGET_HOME/apt-get-called"
    rm -f "$marker"
    (
        dpkg() { return 0; }                       # pretend every package is installed
        apt-get() { echo called >>"$marker"; }     # should never run
        log() { :; }                               # silence logging
        apt_install already-here >/dev/null 2>&1
    )
    if [ ! -f "$marker" ]; then
        pass_test "apt_install skips packages that are already installed"
    else
        fail_test "apt_install" "should not call apt-get when package is present"
    fi
}
test_apt_install_skip

# Test apt_install installs missing packages (apt-get install is invoked)
test_apt_install_missing() {
    local marker="$TARGET_HOME/apt-get-install"
    rm -f "$marker"
    (
        dpkg() { return 1; }                       # pretend nothing is installed
        apt-get() { [ "$1" = "install" ] && echo "$*" >>"$marker"; return 0; }
        is_root() { return 0; }
        log() { :; }
        apt_install needs-install >/dev/null 2>&1
    )
    if grep -q "needs-install" "$marker" 2>/dev/null; then
        pass_test "apt_install installs missing packages via apt-get"
    else
        fail_test "apt_install" "should call apt-get install for missing package"
    fi
}
test_apt_install_missing

# ── gsettings_helpers.sh tests ──────────────────────────────────────────────
source lib/gsettings_helpers.sh

# Test join_as_gsettings_array formats array correctly
result="$(join_as_gsettings_array 'item1' 'item2' 'item3')"
expected="['item1', 'item2', 'item3']"
if [ "$result" = "$expected" ]; then
    pass_test "join_as_gsettings_array formats array correctly"
else
    fail_test "join_as_gsettings_array" "expected $expected, got $result"
fi

# Test join_as_gsettings_array skips empty values
result="$(join_as_gsettings_array 'item1' '' 'item3')"
expected="['item1', 'item3']"
if [ "$result" = "$expected" ]; then
    pass_test "join_as_gsettings_array skips empty values"
else
    fail_test "join_as_gsettings_array" "expected $expected, got $result"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
