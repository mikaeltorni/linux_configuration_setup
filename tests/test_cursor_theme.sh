#!/usr/bin/env bash
# Characterization tests for the Purple Cross cursor theme configuration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_HOME="$(mktemp -d)"
TARGET_USER="$(id -un)"
CONFIG_DIR="$TARGET_HOME/configs"
PASS=0
FAIL=0

cleanup() {
  rm -rf "$TARGET_HOME"
}
trap cleanup EXIT

msg() {
  :
}

run_as_target() {
  "$@"
}

apt_install() {
  printf '%s\n' "$*" >>"$TARGET_HOME/apt-install.log"
}

user_gsettings() {
  printf '%s\n' "$*" >>"$TARGET_HOME/gsettings.log"
}

log() {
  printf '%s: %s\n' "$1" "$2" >>"$TARGET_HOME/messages.log"
}

XCURSORGEN_AVAILABLE=1
need_cmd() {
  [ "$1" != "xcursorgen" ] || [ "$XCURSORGEN_AVAILABLE" -eq 1 ]
}

assert_file_exists() {
  local path="$1" description="$2"
  if [ -e "$path" ]; then
    printf '  PASS: %s\n' "$description"
    PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (missing '%s')\n" "$description" "$path"
    FAIL=$((FAIL + 1))
  fi
}

assert_path_absent() {
  local path="$1" description="$2"
  if [ ! -e "$path" ]; then
    printf '  PASS: %s\n' "$description"
    PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (unexpected '%s')\n" "$description" "$path"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_contains() {
  local path="$1" expected="$2" description="$3"
  if grep -Fq "$expected" "$path" 2>/dev/null; then
    printf '  PASS: %s\n' "$description"
    PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (missing '%s' in '%s')\n" \
      "$description" "$expected" "$path"
    FAIL=$((FAIL + 1))
  fi
}

assert_symlink_target() {
  local path="$1" expected="$2" description="$3"
  local actual
  actual="$(readlink "$path" 2>/dev/null || true)"
  if [ "$actual" = "$expected" ]; then
    printf '  PASS: %s\n' "$description"
    PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (expected '%s', got '%s')\n" \
      "$description" "$expected" "${actual:-<none>}"
    FAIL=$((FAIL + 1))
  fi
}

assert_eq() {
  local expected="$1" actual="$2" description="$3"
  if [ "$actual" = "$expected" ]; then
    printf '  PASS: %s\n' "$description"
    PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (expected '%s', got '%s')\n" \
      "$description" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

source "$SCRIPT_DIR/lib/helpers.sh"
source "$SCRIPT_DIR/lib/cursor_theme.sh"

theme_dir="$TARGET_HOME/.local/share/icons/$PURPLE_CROSS_CURSOR_THEME_NAME"

configure_purple_cross_default_cursor
assert_path_absent "$theme_dir" "skips cleanly when the bundled asset is missing"
assert_file_contains \
  "$TARGET_HOME/messages.log" \
  "cursor asset not found" \
  "logs the missing-asset reason"

mkdir -p "$CONFIG_DIR/cursors"
cp "$SCRIPT_DIR/configs/cursors/purple_cross.cur" "$CONFIG_DIR/cursors/purple_cross.cur"

FAKE_BIN="$TARGET_HOME/fake-bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/python3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "-c" ]; then
  [ "${FAKE_PIL_AVAILABLE:-1}" -eq 1 ]
  exit
fi
printf 'fake-png\n' >"$3"
printf '4 5\n'
EOF
cat >"$FAKE_BIN/xcursorgen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'fake-xcursor\n' >"${@: -1}"
EOF
chmod +x "$FAKE_BIN/python3" "$FAKE_BIN/xcursorgen"
PATH="$FAKE_BIN:$PATH"
export PATH
PYTHON_CANDIDATES=python3
export PYTHON_CANDIDATES

FAKE_PIL_AVAILABLE=0
export FAKE_PIL_AVAILABLE
>"$TARGET_HOME/messages.log"
configure_purple_cross_default_cursor
assert_path_absent "$theme_dir" "skips cleanly when Pillow is unavailable"
assert_file_contains \
  "$TARGET_HOME/messages.log" \
  "python3-pil is required" \
  "logs the missing Pillow dependency"

FAKE_PIL_AVAILABLE=1
export FAKE_PIL_AVAILABLE
XCURSORGEN_AVAILABLE=0
configure_purple_cross_default_cursor

cursor_dir="$theme_dir/cursors"
assert_file_exists "$cursor_dir/left_ptr" "builds the primary cursor"
assert_symlink_target "$cursor_dir/default" "left_ptr" "links the default cursor role"
assert_symlink_target "$cursor_dir/text" "left_ptr" "links the text cursor role"
assert_symlink_target "$cursor_dir/grabbing" "left_ptr" "links the grabbing cursor role"
assert_symlink_target "$cursor_dir/nwse-resize" "left_ptr" "links a resize cursor role"
assert_file_contains \
  "$theme_dir/index.theme" \
  "Inherits=Yaru" \
  "writes the cursor theme inheritance"
assert_file_contains \
  "$TARGET_HOME/.local/share/icons/default/index.theme" \
  "Inherits=$PURPLE_CROSS_CURSOR_THEME_NAME" \
  "writes the modern default cursor inheritance"
assert_file_contains \
  "$TARGET_HOME/.icons/default/index.theme" \
  "Inherits=$PURPLE_CROSS_CURSOR_THEME_NAME" \
  "writes the legacy default cursor inheritance"
assert_file_contains \
  "$TARGET_HOME/gsettings.log" \
  "cursor-theme '$PURPLE_CROSS_CURSOR_THEME_NAME'" \
  "sets the GNOME cursor theme"
assert_file_contains \
  "$TARGET_HOME/gsettings.log" \
  "cursor-size $PURPLE_CROSS_CURSOR_SIZE" \
  "sets the GNOME cursor size"
assert_file_contains \
  "$TARGET_HOME/apt-install.log" \
  "x11-apps" \
  "requests xcursorgen through the root-optional package helper"
assert_path_absent \
  "$TARGET_HOME/.cache/isc/purple-cross-cursor-build" \
  "removes temporary build files"

expected_alias_count="${#PURPLE_CROSS_CURSOR_ALIASES[@]}"
actual_alias_count="$(find "$cursor_dir" -maxdepth 1 -type l | wc -l)"
assert_eq "$expected_alias_count" "$actual_alias_count" "links every declared cursor alias"

XCURSORGEN_AVAILABLE=1
configure_purple_cross_default_cursor
assert_file_exists "$cursor_dir/left_ptr" "supports a repeated installation run"
actual_alias_count="$(find "$cursor_dir" -maxdepth 1 -type l | wc -l)"
assert_eq "$expected_alias_count" "$actual_alias_count" "keeps alias links idempotent"

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
