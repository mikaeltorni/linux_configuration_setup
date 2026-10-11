#!/usr/bin/env bash
# test_gnome_desktop.sh — Tests for GNOME desktop integration.

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
# Resolve the shared framework checkout the same way install.sh does: an
# explicit override, then the sibling directory, then the projects folder (so
# the suite also runs from a git worktree, where the sibling is one level up).
isc_helpers_path() {
  local root="$1" candidate
  for candidate in "${ISC_FUNCTIONS_DIR:-}" \
                   "$root/../linux_installation_scripts_functions" \
                   "$root/../../linux_installation_scripts_functions" \
                   "$HOME/projects/linux_installation_scripts_functions"; do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate/installer_helpers.sh" ]; then
      printf '%s\n' "$candidate/installer_helpers.sh"
      return 0
    fi
  done
  return 1
}
source "$(isc_helpers_path "$SCRIPT_DIR")"
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

assert_file_missing() {
  local path="$1" msg="$2"
  if [ ! -e "$path" ]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (unexpected '$path')"
    FAIL=$((FAIL + 1))
  fi
}

# d2p_log_run_as_target LOG_FILE args... — stub run_as_target for Dash-to-Panel
# lifecycle tests. Records every argv line, answers gsettings get from the D2P_*
# fixtures, swallows systemctl/gnome-extensions/sleep/sh (no live session), and
# executes the rest (install/rm/chmod) into TARGET_HOME.
d2p_log_run_as_target() {
  local log_file="$1"
  shift
  printf '%s\n' "$*" >>"$log_file"
  case "$1" in
    gsettings)
      if [ "${2:-}" = "get" ]; then
        case "${3:-} ${4:-}" in
          "org.gnome.shell enabled-extensions") printf '%s\n' "${D2P_ENABLED_EXTENSIONS:-[]}" ;;
          "org.gnome.shell disabled-extensions") printf '%s\n' "${D2P_DISABLED_EXTENSIONS:-[]}" ;;
          "org.gnome.shell disable-user-extensions") printf '%s\n' "${D2P_DISABLE_USER_EXTENSIONS:-false}" ;;
          *) printf '[]\n' ;;
        esac
      elif [ "${2:-}" = "set" ]; then
        case "${3:-} ${4:-}" in
          "org.gnome.shell enabled-extensions") D2P_ENABLED_EXTENSIONS="${5:-}" ;;
          "org.gnome.shell disabled-extensions") D2P_DISABLED_EXTENSIONS="${5:-}" ;;
          "org.gnome.shell disable-user-extensions") D2P_DISABLE_USER_EXTENSIONS="${5:-}" ;;
        esac
      fi
      return 0
      ;;
    systemctl|gnome-extensions|sleep|sh|dconf)
      return 0
      ;;
    *)
      "$@"
      ;;
  esac
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

# Retired compatibility entrypoints must preserve the owner's installed files.
echo "--- app-rules ownership ---"
app_rules_dst="$TARGET_HOME/.local/share/gnome-shell/extensions/app-rules@local"
mkdir -p "$app_rules_dst"
printf 'workspace owner source\n' >"$app_rules_dst/extension.js"
configure_app_rules_extension
configure_app_rules_extension
source "$SCRIPT_DIR/lib/lifecycle.sh"
# Keep the regression's desktop boundary stubbed even against pre-fix code.
( gnome-extensions() { return 0; }; uninstall_app_rules )
assert_file_contains "$app_rules_dst/extension.js" "workspace owner source" "Must preserve the workspace owner's extension"
if [ -d "$SCRIPT_DIR/configs/gnome-extensions/app-rules@local" ]; then
  echo "FAIL: configuration must not bundle a competing extension"
  FAIL=$((FAIL + 1))
fi

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
# The standalone (no SELECTED_FAVORITE_APPS) default dock is sourced from
# linux_installations_setup's --list-favorite-components contract. Stub that
# listing via LIS_INSTALL_SH so the test is hermetic and asserts the wiring.
LIS_STUB="$TARGET_HOME/lis-install-stub.sh"
cat >"$LIS_STUB" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "--list-favorite-components" ] || exit 0
printf 'obs\tcom.obsproject.Studio.desktop\n'
printf 'remote_desktop\torg.remmina.Remmina.desktop,remmina.desktop\n'
printf 'baobab\torg.gnome.baobab.desktop\ton\n'
STUB
chmod +x "$LIS_STUB"
touch "$TARGET_HOME/.local/share/applications/org.remmina.Remmina.desktop"
touch "$TARGET_HOME/.local/share/applications/com.obsproject.Studio.desktop"
touch "$TARGET_HOME/.local/share/applications/org.gnome.baobab.desktop"
touch "$TARGET_HOME/.local/share/applications/org.gnome.SystemMonitor.desktop"
LIS_INSTALL_SH="$LIS_STUB" configure_favorites </dev/null
if grep -q "org.remmina.Remmina.desktop" "$GSETTINGS_CALL_LOG" && \
   grep -q "com.obsproject.Studio.desktop" "$GSETTINGS_CALL_LOG" && \
   grep -q "org.gnome.baobab.desktop" "$GSETTINGS_CALL_LOG" && \
   ! grep -q "org.gnome.SystemMonitor.desktop" "$GSETTINGS_CALL_LOG"; then
  pass "configure_favorites builds the default dock from installations_setup and omits System Monitor"
else
  fail "configure_favorites builds the default dock from installations_setup and omits System Monitor"
fi

>"$GSETTINGS_CALL_LOG"
touch "$TARGET_HOME/.local/share/applications/org.gnome.Nautilus.desktop"
touch "$TARGET_HOME/.local/share/applications/google-chrome.desktop"
SELECTED_FAVORITE_APPS="google-chrome.desktop" configure_favorites </dev/null
if grep -q "org.gnome.Nautilus.desktop" "$GSETTINGS_CALL_LOG" && \
   grep -q "google-chrome.desktop" "$GSETTINGS_CALL_LOG" && \
   ! grep -q "org.remmina.Remmina.desktop" "$GSETTINGS_CALL_LOG"; then
  pass "configure_favorites merges selected program favourites with baseline entries"
else
  fail "configure_favorites merges selected program favourites with baseline entries"
fi
unset SELECTED_FAVORITE_APPS

# Master handoff with MANAGED_FAVORITE_APPS must reconcile only managed ids and
# preserve unrelated dock favourites such as user-pinned PWAs.
echo ""
echo "--- configure_favorites (managed reconciliation) ---"

CURRENT_FAVORITE_APPS="['chatgpt-pwa.desktop', 'google-chrome.desktop', 'org.remmina.Remmina.desktop', 'org.gnome.SystemMonitor.desktop']"
>"$GSETTINGS_CALL_LOG"
touch "$TARGET_HOME/.local/share/applications/google-chrome.desktop"
touch "$TARGET_HOME/.local/share/applications/org.gnome.baobab.desktop"
touch "$TARGET_HOME/.local/share/applications/org.remmina.Remmina.desktop"
user_gsettings() {
  printf '%s\n' "$*" >>"$GSETTINGS_CALL_LOG"
  if [ "$1" = "get" ] && [ "$2" = "org.gnome.shell" ] && [ "$3" = "favorite-apps" ]; then
    printf '%s\n' "$CURRENT_FAVORITE_APPS"
    return 0
  fi
  [ "$1" = "get" ] && return 1
  return 0
}
MANAGED_FAVORITE_APPS="google-chrome.desktop,org.gnome.baobab.desktop,org.remmina.Remmina.desktop,com.obsproject.Studio.desktop"
SELECTED_FAVORITE_APPS="google-chrome.desktop,org.gnome.baobab.desktop"
configure_favorites </dev/null
if grep -q "chatgpt-pwa.desktop" "$GSETTINGS_CALL_LOG" && \
   grep -q "google-chrome.desktop" "$GSETTINGS_CALL_LOG" && \
   grep -q "org.gnome.baobab.desktop" "$GSETTINGS_CALL_LOG" && \
   ! grep -q "org.remmina.Remmina.desktop" "$GSETTINGS_CALL_LOG" && \
   ! grep -q "com.obsproject.Studio.desktop" "$GSETTINGS_CALL_LOG" && \
   ! grep -q "org.gnome.SystemMonitor.desktop" "$GSETTINGS_CALL_LOG"; then
  pass "configure_favorites preserves unmanaged PWAs and removes the obsolete System Monitor favorite"
else
  fail "configure_favorites preserves unmanaged PWAs and removes the obsolete System Monitor favorite"
fi
unset MANAGED_FAVORITE_APPS SELECTED_FAVORITE_APPS CURRENT_FAVORITE_APPS

# Standalone/config_active runs derive managed metadata from installations_setup
# and must still preserve unrelated dock favourites when env handoff is absent.
echo ""
echo "--- configure_favorites (standalone reconciliation) ---"

CURRENT_FAVORITE_APPS="['chatgpt-pwa.desktop', 'org.remmina.Remmina.desktop']"
>"$GSETTINGS_CALL_LOG"
rm -f "$TARGET_HOME/.local/share/applications/org.remmina.Remmina.desktop"
LIS_STUB="$TARGET_HOME/lis-standalone-stub.sh"
cat >"$LIS_STUB" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "--list-favorite-components" ] || exit 0
printf 'obs\tcom.obsproject.Studio.desktop\n'
printf 'remote_desktop\torg.remmina.Remmina.desktop,remmina.desktop\n'
STUB
chmod +x "$LIS_STUB"
touch "$TARGET_HOME/.local/share/applications/com.obsproject.Studio.desktop"
LIS_INSTALL_SH="$LIS_STUB"
user_gsettings() {
  printf '%s\n' "$*" >>"$GSETTINGS_CALL_LOG"
  if [ "$1" = "get" ] && [ "$2" = "org.gnome.shell" ] && [ "$3" = "favorite-apps" ]; then
    printf '%s\n' "$CURRENT_FAVORITE_APPS"
    return 0
  fi
  [ "$1" = "get" ] && return 1
  return 0
}
configure_favorites </dev/null
if grep -q "chatgpt-pwa.desktop" "$GSETTINGS_CALL_LOG" && \
   grep -q "com.obsproject.Studio.desktop" "$GSETTINGS_CALL_LOG" && \
   ! grep -q "org.remmina.Remmina.desktop" "$GSETTINGS_CALL_LOG"; then
  pass "configure_favorites preserves PWAs on standalone config reload without master handoff"
else
  fail "configure_favorites preserves PWAs on standalone config reload without master handoff"
fi
unset LIS_INSTALL_SH CURRENT_FAVORITE_APPS

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

# Test Dash-to-Panel lifecycle detection requires the active bottom-panel setup
echo ""
echo "--- dash_to_panel lifecycle ---"

source "$SCRIPT_DIR/lib/dash_to_panel.sh"
mkdir -p "$TARGET_HOME/.local/share/gnome-shell/extensions/$D2P_EXT_ID"
printf '{"uuid":"%s"}\n' "$D2P_EXT_ID" >"$TARGET_HOME/.local/share/gnome-shell/extensions/$D2P_EXT_ID/metadata.json"
touch "$TARGET_HOME/.local/share/gnome-shell/extensions/$D2P_EXT_ID/appIcons.js"

D2P_ENABLED_EXTENSIONS="['$D2P_EXT_ID']"
D2P_DISABLED_EXTENSIONS="['ubuntu-dock@ubuntu.com']"
D2P_DISABLE_USER_EXTENSIONS="false"
run_as_target() {
  if [ "$1" = "gsettings" ] && [ "$2" = "get" ]; then
    case "$3 $4" in
      "org.gnome.shell enabled-extensions") printf '%s\n' "$D2P_ENABLED_EXTENSIONS" ;;
      "org.gnome.shell disabled-extensions") printf '%s\n' "$D2P_DISABLED_EXTENSIONS" ;;
      "org.gnome.shell disable-user-extensions") printf '%s\n' "$D2P_DISABLE_USER_EXTENSIONS" ;;
      *) return 1 ;;
    esac
    return 0
  fi
  "$@"
}

detect_dash_to_panel && pass "detect_dash_to_panel sees deployed and enabled Dash-to-Panel" \
  || fail "detect_dash_to_panel sees deployed and enabled Dash-to-Panel"
D2P_DISABLE_USER_EXTENSIONS="true"
if detect_dash_to_panel; then
  fail "detect_dash_to_panel rejects globally disabled user extensions"
else
  pass "detect_dash_to_panel rejects globally disabled user extensions"
fi
D2P_DISABLE_USER_EXTENSIONS="false"
D2P_ENABLED_EXTENSIONS="['$D2P_EXT_ID', 'ubuntu-dock@ubuntu.com']"
if detect_dash_to_panel; then
  fail "detect_dash_to_panel rejects Ubuntu Dock still being enabled"
else
  pass "detect_dash_to_panel rejects Ubuntu Dock still being enabled"
fi
D2P_ENABLED_EXTENSIONS="[]"
if detect_dash_to_panel; then
  fail "detect_dash_to_panel requires Dash-to-Panel to be enabled"
else
  pass "detect_dash_to_panel requires Dash-to-Panel to be enabled"
fi
D2P_ENABLED_EXTENSIONS="['$D2P_EXT_ID']"

# configure_dash_to_panel must clear the global user-extension kill switch so the
# bottom panel (and every other user extension) can load on the next login, and
# must install a graphical-login re-apply so a later crash cannot leave the
# kill switch true across reboot.
D2P_CONFIGURE_LOG="$TARGET_HOME/d2p-configure.log"
D2P_HELPER="$TARGET_HOME/.local/libexec/linux-configuration-setup/reapply-dash-to-panel"
D2P_UNIT="$TARGET_HOME/.config/systemd/user/dash-to-panel-reapply.service"
>"$D2P_CONFIGURE_LOG"
run_as_target() { d2p_log_run_as_target "$D2P_CONFIGURE_LOG" "$@"; }
configure_dash_to_panel </dev/null
assert_file_contains "$D2P_CONFIGURE_LOG" \
  "gsettings set org.gnome.shell disable-user-extensions false" \
  "configure_dash_to_panel enables user extensions globally"
assert_file_contains "$D2P_CONFIGURE_LOG" \
  "gsettings set org.gnome.shell enabled-extensions ['$D2P_EXT_ID']" \
  "configure_dash_to_panel keeps Dash-to-Panel in enabled-extensions"
assert_file_contains "$D2P_CONFIGURE_LOG" \
  "gsettings set org.gnome.shell disabled-extensions ['ubuntu-dock@ubuntu.com']" \
  "configure_dash_to_panel persists the disabled-extension list"
assert_file_contains "$D2P_CONFIGURE_LOG" \
  "systemctl --user enable dash-to-panel-reapply.service" \
  "configure_dash_to_panel enables the login re-apply unit"
assert_file_exists "$D2P_HELPER" \
  "configure_dash_to_panel installs the login re-apply helper"
assert_file_exists "$D2P_UNIT" \
  "configure_dash_to_panel installs the login re-apply systemd user unit"
assert_file_contains "$D2P_HELPER" \
  "d2p_reapply_enabled_state" \
  "login re-apply helper calls the shipped re-apply function"
assert_file_contains "$D2P_UNIT" \
  "WantedBy=graphical-session-pre.target" \
  "login re-apply unit is pulled in before the graphical session"
assert_file_contains "$D2P_UNIT" \
  "ExecStart=%h/.local/libexec/linux-configuration-setup/reapply-dash-to-panel" \
  "login re-apply unit runs the installed helper"
assert_file_contains "$D2P_UNIT" \
  "Environment=LCS_SCRIPT_DIR=$SCRIPT_DIR" \
  "login re-apply unit records the checkout that installed it"

# d2p_reapply_enabled_state must restore the three facts from the live failure
# (kill switch true, Dash-to-Panel already listed, Ubuntu Dock still enabled).
echo ""
echo "--- d2p_reapply_enabled_state from kill switch ---"
D2P_REAPPLY_LOG="$TARGET_HOME/d2p-reapply.log"
>"$D2P_REAPPLY_LOG"
D2P_DISABLE_USER_EXTENSIONS="true"
D2P_ENABLED_EXTENSIONS="['ubuntu-dock@ubuntu.com']"
D2P_DISABLED_EXTENSIONS="['$D2P_EXT_ID']"
run_as_target() { d2p_log_run_as_target "$D2P_REAPPLY_LOG" "$@"; }
d2p_reapply_enabled_state
assert_file_contains "$D2P_REAPPLY_LOG" \
  "gsettings set org.gnome.shell disable-user-extensions false" \
  "re-apply clears the user-extension kill switch"
assert_file_contains "$D2P_REAPPLY_LOG" \
  "gsettings set org.gnome.shell enabled-extensions ['$D2P_EXT_ID']" \
  "re-apply leaves Dash-to-Panel enabled and Ubuntu Dock out of enabled-extensions"
assert_file_contains "$D2P_REAPPLY_LOG" \
  "gsettings set org.gnome.shell disabled-extensions ['ubuntu-dock@ubuntu.com']" \
  "re-apply puts Ubuntu Dock on the disabled-extension list"

# uninstall must drop the login hook and restore Ubuntu Dock membership.
echo ""
echo "--- uninstall_dash_to_panel removes login re-apply ---"
D2P_UNINSTALL_LOG="$TARGET_HOME/d2p-uninstall.log"
>"$D2P_UNINSTALL_LOG"
run_as_target() { d2p_log_run_as_target "$D2P_UNINSTALL_LOG" "$@"; }
uninstall_dash_to_panel
unset -f run_as_target
assert_file_missing "$D2P_HELPER" \
  "uninstall_dash_to_panel removes the login re-apply helper"
assert_file_missing "$D2P_UNIT" \
  "uninstall_dash_to_panel removes the login re-apply systemd user unit"
assert_file_contains "$D2P_UNINSTALL_LOG" \
  "systemctl --user disable --now dash-to-panel-reapply.service" \
  "uninstall_dash_to_panel disables the login re-apply unit"
assert_file_contains "$D2P_UNINSTALL_LOG" \
  "gsettings set org.gnome.shell enabled-extensions ['ubuntu-dock@ubuntu.com']" \
  "uninstall_dash_to_panel restores Ubuntu Dock"

# configure_display_refresh: leftover Wayland VRR on X11 makes the NVIDIA X
# driver walk every DFP ~16 times per second and drop mouse/keyboard events.
echo ""
echo "--- configure_display_refresh X11 clears leftover VRR ---"
REFRESH_LOG="$TARGET_HOME/display-refresh.log"
>"$REFRESH_LOG"
SESSION_TYPE="x11"
apt_install() { printf 'apt_install %s\n' "$*" >>"$REFRESH_LOG"; }
msg() { :; }
user_gsettings() { printf 'gsettings %s\n' "$*" >>"$REFRESH_LOG"; }
run_as_target() { printf '%s\n' "$*" >>"$REFRESH_LOG"; }
configure_display_refresh
unset -f apt_install user_gsettings run_as_target
assert_file_contains "$REFRESH_LOG" \
  'gsettings set org.gnome.mutter experimental-features []' \
  "X11 display_refresh clears mutter variable-refresh-rate leftovers"
if grep -Fq "variable-refresh-rate" "$REFRESH_LOG"; then
  fail "X11 display_refresh must not enable variable-refresh-rate"
else
  pass "X11 display_refresh does not enable variable-refresh-rate"
fi

echo ""
echo "--- configure_display_refresh Wayland still enables VRR ---"
>"$REFRESH_LOG"
SESSION_TYPE="wayland"
apt_install() { printf 'apt_install %s\n' "$*" >>"$REFRESH_LOG"; }
msg() { :; }
user_gsettings() { printf 'gsettings %s\n' "$*" >>"$REFRESH_LOG"; }
run_as_target() { printf '%s\n' "$*" >>"$REFRESH_LOG"; }
configure_display_refresh
unset -f apt_install user_gsettings run_as_target
assert_file_contains "$REFRESH_LOG" \
  "gsettings set org.gnome.mutter experimental-features ['variable-refresh-rate']" \
  "Wayland display_refresh still enables mutter VRR"

echo ""
echo "Results: $PASS passed, $FAIL failed"

# Cleanup
rm -rf "$TARGET_HOME"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
