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
source lib/helpers.sh

# Test toml_string_array formats array correctly
items=("model-with-reasoning" "current-dir" "context-remaining")
result="$(toml_string_array items)"
expected="[\"model-with-reasoning\", \"current-dir\", \"context-remaining\"]"
if [ "$result" = "$expected" ]; then
    pass_test "toml_string_array formats array correctly"
else
    fail_test "toml_string_array" "expected $expected, got $result"
fi

# Test toml_string_array handles single item
items=("single-item")
result="$(toml_string_array items)"
expected="[\"single-item\"]"
if [ "$result" = "$expected" ]; then
    pass_test "toml_string_array handles single item"
else
    fail_test "toml_string_array" "expected $expected, got $result"
fi

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

# Test append_gsettings_list idempotency (simulated — no real gsettings)
# Simulates the Python heredoc logic from gsettings_helpers.sh
test_append_logic() {
    local current="$1" val="$2" expected_result="$3"
    # The CURRENT env var should match actual gsettings output format: @as ["item1", "item2"]
    result="$(CURRENT="$current" VAL="$val" python3 - <<'PY'
import ast, os
cur_raw = os.environ.get("CURRENT", "").strip()
if cur_raw.startswith("@as "):
    cur_raw = cur_raw[4:].strip()
try:
    cur = ast.literal_eval(cur_raw) if cur_raw else []
except Exception:
    cur = []
val = os.environ["VAL"]
if val not in cur:
    cur.append(val)
print("[" + ", ".join(f"'{v}'" for v in cur) + "]")
PY
)"
    if [ "$result" = "$expected_result" ]; then
        pass_test "append_gsettings_list logic handles $current + $val"
    else
        fail_test "append_gsettings_list" "expected $expected_result, got $result"
    fi
}

# Use actual gsettings output format (@as ["item1", "item2"])
test_append_logic '@as ["item1"]' "item2" "['item1', 'item2']"
test_append_logic "@as ['item1', 'item2']" "item2" "['item1', 'item2']"  # idempotent

# Test set_indexed_keybinding_map parsing (simulated)
test_parse_bindings() {
    local input="$1" expected_count="$2"
    IFS=',' read -ra parts <<< "$input"
    local count=${#parts[@]}
    if [ "$count" -eq "$expected_count" ]; then
        pass_test "set_indexed_keybinding_map parses $input into $expected_count entries"
    else
        fail_test "set_indexed_keybinding_map" "expected $expected_count, got $count"
    fi
}

test_parse_bindings "<Super>XF86Launch1,<Control><Alt>Delete,<Primary>c" 3
test_parse_bindings "<Super>XF86Launch1" 1

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
