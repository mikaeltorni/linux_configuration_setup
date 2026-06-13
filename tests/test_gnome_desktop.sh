#!/usr/bin/env bash
# test_gnome_desktop.sh — Tests for GNOME desktop and legacy PWA integration.

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
source "$SCRIPT_DIR/lib/pwa_icons.sh"
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

assert_file_contains() {
  local path="$1" expected="$2" msg="$3"
  if grep -Fq "$expected" "$path" 2>/dev/null; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (missing '$expected' in '$path')"
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

# Test configure_terminal_dark_theme avoids unavailable schemas
echo ""
echo "--- configure_terminal_dark_theme ---"

run_as_target() { "$@"; }
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

# Test configure_pwa_icons installs every icon size and a matching desktop entry
echo ""
echo "--- configure_pwa_icons ---"

FAKE_BIN="$TARGET_HOME/fake-bin"
mkdir -p "$FAKE_BIN"
PATH="$FAKE_BIN:$PATH"

claude_app_id="fmpnliohjhemenmnlpbfagaolkdacoja"
claude_manifest_dir="$TARGET_HOME/.config/google-chrome/Default/Web Applications/Manifest Resources/$claude_app_id"
mkdir -p "$claude_manifest_dir/Icons"
printf '{"name":"Claude"}\n' >"$claude_manifest_dir/Manifest"
printf 'claude-48\n' >"$claude_manifest_dir/Icons/48.png"
printf 'claude-512\n' >"$claude_manifest_dir/Icons/512.png"

FAKE_GTK_CACHE_LOG="$TARGET_HOME/gtk-update-icon-cache.log"
cat >"$FAKE_BIN/gtk-update-icon-cache" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$FAKE_GTK_CACHE_LOG"
EOF
chmod +x "$FAKE_BIN/gtk-update-icon-cache"

configure_pwa_icons

claude_icon_name="chrome-$claude_app_id-Default.png"
assert_symlink_target \
  "$TARGET_HOME/.local/share/icons/hicolor/48x48/apps/$claude_icon_name" \
  "$claude_manifest_dir/Icons/48.png" \
  "Should install the Claude 48px icon"
assert_symlink_target \
  "$TARGET_HOME/.local/share/icons/hicolor/512x512/apps/$claude_icon_name" \
  "$claude_manifest_dir/Icons/512.png" \
  "Should install the Claude 512px icon"
claude_desktop="$TARGET_HOME/.local/share/applications/chrome-$claude_app_id-Default.desktop"
assert_file_contains "$claude_desktop" "Name=Claude" "Should create the Claude desktop entry"
assert_file_contains \
  "$claude_desktop" \
  "Icon=$claude_manifest_dir/Icons/512.png" \
  "Should point the Claude desktop entry directly at its largest icon"
assert_file_contains "$FAKE_GTK_CACHE_LOG" "$TARGET_HOME/.local/share/icons/hicolor" "Should refresh the icon cache"

# Chrome can remove a cached manifest while retaining PWA icons and its entry.
rm "$claude_manifest_dir/Manifest"
printf 'Icon=stale\nName=Claude\n' >"$claude_desktop"
configure_pwa_icons
assert_file_contains \
  "$claude_desktop" \
  "Icon=$claude_manifest_dir/Icons/512.png" \
  "Should recover a manifest-less Claude PWA from its existing desktop entry"

echo ""
echo "Results: $PASS passed, $FAIL failed"

# Cleanup
rm -rf "$TARGET_HOME"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
