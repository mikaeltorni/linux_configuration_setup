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

log() { :; }  # silence shared-helper debug logging in this harness
source "$SCRIPT_DIR/../linux_installation_scripts_functions/installer_helpers.sh"
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

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

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

assert_file_mode() {
  local path="$1" expected="$2" msg="$3"
  local actual=""
  actual="$(stat -c '%a' "$path" 2>/dev/null || true)"
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (expected mode '$expected', got '${actual:-<missing>}')"
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

# Test configure_app_rules_extension creates a clean-home destination directory
# before copying the bundled extension files.
echo ""
echo "--- configure_app_rules_extension ---"

CONFIG_DIR="$TARGET_HOME/configs"
mkdir -p "$CONFIG_DIR/gnome-extensions/app-rules@local"
printf '{"uuid":"app-rules@local"}\n' >"$CONFIG_DIR/gnome-extensions/app-rules@local/metadata.json"
printf 'extension source\n' >"$CONFIG_DIR/gnome-extensions/app-rules@local/extension.js"

configure_app_rules_extension

app_rules_dst="$TARGET_HOME/.local/share/gnome-shell/extensions/app-rules@local"
assert_file_exists "$app_rules_dst" "Should create the app-rules extension directory"
assert_file_mode "$app_rules_dst/metadata.json" "644" "Should install metadata.json with a stable file mode"
assert_file_contains "$app_rules_dst/extension.js" "extension source" "Should copy extension.js into the destination"

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

# Test configure_favorites honors a user-supplied app list
echo ""
echo "--- configure_favorites (customizable) ---"

source "$SCRIPT_DIR/lib/gsettings_helpers.sh"
source "$SCRIPT_DIR/lib/system_config.sh"

run_as_target() { "$@"; }
GSETTINGS_CALL_LOG="$TARGET_HOME/gsettings-favorites.log"
>"$GSETTINGS_CALL_LOG"
user_gsettings() {
  printf '%s\n' "$*" >>"$GSETTINGS_CALL_LOG"
  [ "$1" = "get" ] && return 1
  return 0
}
gsettings_key_exists() { return 1; }
gsettings() { return 1; }  # used by configure_dark_mode's user-theme probe

FAVORITES_APPS="alpha.desktop, beta.desktop gamma.desktop" configure_favorites
if grep -q "favorite-apps \['alpha.desktop', 'beta.desktop', 'gamma.desktop'\]" "$GSETTINGS_CALL_LOG"; then
  pass "configure_favorites applies the user-supplied FAVORITES_APPS list"
else
  fail "configure_favorites applies the user-supplied FAVORITES_APPS list"
fi

>"$GSETTINGS_CALL_LOG"
unset FAVORITES_APPS
touch "$TARGET_HOME/.local/share/applications/org.remmina.Remmina.desktop"
configure_favorites </dev/null
if grep -q "org.remmina.Remmina.desktop" "$GSETTINGS_CALL_LOG"; then
  pass "configure_favorites includes Remmina when installed"
else
  fail "configure_favorites includes Remmina when installed"
fi

# Test configure_dark_mode respects the color-scheme override
echo ""
echo "--- configure_dark_mode (dark/light) ---"

>"$GSETTINGS_CALL_LOG"
configure_dark_mode </dev/null
assert_file_contains "$GSETTINGS_CALL_LOG" "color-scheme 'prefer-dark'" "defaults to the dark color scheme"

>"$GSETTINGS_CALL_LOG"
DESKTOP_COLOR_SCHEME=light configure_dark_mode </dev/null
assert_file_contains "$GSETTINGS_CALL_LOG" "color-scheme 'prefer-light'" "DESKTOP_COLOR_SCHEME=light selects the light scheme"

>"$GSETTINGS_CALL_LOG"
DESKTOP_GTK_THEME="My-Theme" configure_dark_mode </dev/null
assert_file_contains "$GSETTINGS_CALL_LOG" "gtk-theme 'My-Theme'" "DESKTOP_GTK_THEME overrides the GTK theme name"

echo ""
echo "Results: $PASS passed, $FAIL failed"

# Cleanup
rm -rf "$TARGET_HOME"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
