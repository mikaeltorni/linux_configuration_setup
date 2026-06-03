#!/usr/bin/env bash
# test_gnome_desktop.sh — Tests for lib/gnome_desktop.sh functions
# Tests: detect_terminal_desktop, first_existing_desktop

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Mock variables needed by helpers before sourcing
TARGET_HOME="/tmp/test-target-home-$$"
RUNTIME_DIR="/tmp/test-runtime-$$"
DISPLAY_VAL=":0"
USER_BUS="unix:path=$RUNTIME_DIR/bus"
CONFIG_DIR="$TARGET_HOME/configs"
TARGET_USER="$(id -un)"
DESKTOP_DIRS=(
  /usr/share/applications
  /var/lib/snapd/desktop/applications
  "$TARGET_HOME/.local/share/applications"
)

mkdir -p "$TARGET_HOME/.local/share/applications"

source "$SCRIPT_DIR/lib/helpers.sh"
source "$SCRIPT_DIR/lib/gsettings_helpers.sh"
source "$SCRIPT_DIR/lib/gnome_desktop.sh"
DESKTOP_DIRS=("$TARGET_HOME/.local/share/applications")

PASS=0
FAIL=0

assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local path="$1" msg="$2"
  if [ -e "$path" ]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (missing '$path')"
    FAIL=$((FAIL + 1))
  fi
}

assert_symlink_target() {
  local path="$1" expected="$2" msg="$3"
  local actual=""
  actual="$(readlink "$path" 2>/dev/null || true)"
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (expected symlink '$expected', got '${actual:-<none>}')"
    FAIL=$((FAIL + 1))
  fi
}

echo "=========================================="
echo "  GNOME Desktop Module Tests"
echo "=========================================="

# Test detect_terminal_desktop
echo ""
echo "--- detect_terminal_desktop ---"

# Create mock desktop files
touch "$TARGET_HOME/.local/share/applications/kitty.desktop"
touch "$TARGET_HOME/.local/share/applications/org.gnome.Terminal.desktop"

result="$(detect_terminal_desktop)"
assert_eq "kitty.desktop" "$result" "Should find kitty.desktop first"

rm -f "$TARGET_HOME/.local/share/applications/kitty.desktop"
result="$(detect_terminal_desktop)"
assert_eq "org.gnome.Terminal.desktop" "$result" "Should fall back to org.gnome.Terminal.desktop"

# Test first_existing_desktop
echo ""
echo "--- first_existing_desktop ---"

touch "$TARGET_HOME/.local/share/applications/spotify.desktop"
touch "$TARGET_HOME/.local/share/applications/spotify_spotify.desktop"

result="$(first_existing_desktop spotify.desktop spotify_spotify.desktop)"
assert_eq "spotify.desktop" "$result" "Should return first existing desktop file"

result="$(first_existing_desktop nonexistent.desktop also-nonexistent.desktop)"
assert_eq "" "$result" "Should return empty for non-existent files"

# Test with .desktop extension auto-addition
touch "$TARGET_HOME/.local/share/applications/obs.desktop"
result="$(first_existing_desktop obs)"
assert_eq "obs.desktop" "$result" "Should add .desktop extension automatically"

# Test configure_purple_cross_default_cursor creates a complete sticky theme
echo ""
echo "--- configure_purple_cross_default_cursor ---"

FAKE_BIN="$TARGET_HOME/fake-bin"
mkdir -p "$CONFIG_DIR/cursors" "$FAKE_BIN"
touch "$CONFIG_DIR/cursors/purple_cross.cur"
cat >"$FAKE_BIN/icotool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
outdir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) outdir="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$outdir"
printf 'fake-png\n' >"$outdir/extracted.png"
EOF
cat >"$FAKE_BIN/xcursorgen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output="${@: -1}"
printf 'fake-xcursor\n' >"$output"
EOF
chmod +x "$FAKE_BIN/icotool" "$FAKE_BIN/xcursorgen"
PATH="$FAKE_BIN:$PATH"

run_as_target() { "$@"; }
apt_install() { echo "apt_install $*" >>"$TARGET_HOME/apt-install.log"; }
GSETTINGS_CALL_LOG="$TARGET_HOME/cursor-gsettings-calls.log"
user_gsettings() { printf '%s\n' "$*" >>"$GSETTINGS_CALL_LOG"; }

configure_purple_cross_default_cursor

cursor_theme_dir="$TARGET_HOME/.local/share/icons/PurpleCrossDefault"
cursor_dir="$cursor_theme_dir/cursors"
assert_file_exists "$cursor_dir/left_ptr" "Should build the Purple Cross left_ptr cursor"
for cursor_name in default arrow text xterm wait progress left_ptr_watch move grab grabbing all-scroll \
  e-resize w-resize n-resize s-resize ne-resize nw-resize se-resize sw-resize \
  ew-resize ns-resize nesw-resize nwse-resize no-drop not-allowed forbidden \
  crosshair copy alias dnd-copy dnd-link dnd-move dnd-no-drop zoom-in zoom-out; do
  assert_symlink_target "$cursor_dir/$cursor_name" "left_ptr" "Should force $cursor_name to Purple Cross"
done
assert_file_exists "$TARGET_HOME/.local/share/icons/default/index.theme" "Should configure Xcursor default inheritance under .local"
assert_file_exists "$TARGET_HOME/.icons/default/index.theme" "Should configure legacy Xcursor default inheritance"
if grep -q "cursor-theme 'PurpleCrossDefault'" "$GSETTINGS_CALL_LOG" && \
   grep -q "cursor-size 32" "$GSETTINGS_CALL_LOG"; then
  echo "  PASS: Should set GNOME cursor theme and size"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Should set GNOME cursor theme and size"
  FAIL=$((FAIL + 1))
fi

# Test configure_terminal_dark_theme avoids unavailable schemas
echo ""
echo "--- configure_terminal_dark_theme ---"

GSETTINGS_CALL_LOG="$TARGET_HOME/gsettings-calls.log"
>"$GSETTINGS_CALL_LOG"
user_gsettings() {
  printf '%s\n' "$*" >>"$GSETTINGS_CALL_LOG"
  if [ "$1" = "get" ]; then
    return 1
  fi
}
gsettings_key_exists() {
  return 1
}

configure_terminal_dark_theme
if grep -q "org.gnome.Console" "$GSETTINGS_CALL_LOG" 2>/dev/null || \
   grep -q "org.gnome.Ptyxis" "$GSETTINGS_CALL_LOG" 2>/dev/null; then
  echo "  FAIL: Should not set unavailable Console/Ptyxis schemas"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: Should skip unavailable Console/Ptyxis schemas"
  PASS=$((PASS + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"

# Cleanup
rm -rf "$TARGET_HOME"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
