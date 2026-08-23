#!/usr/bin/env bash
# test_autostart.sh - Tests for application autostart configuration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_HOME="/tmp/test-autostart-home-$$"
TARGET_USER="$(id -un)"
RUNTIME_DIR="/tmp/test-autostart-runtime-$$"
DISPLAY_VAL=":0"
USER_BUS="unix:path=$RUNTIME_DIR/bus"

cleanup() {
  rm -rf "$TARGET_HOME" "$RUNTIME_DIR"
}
trap cleanup EXIT

mkdir -p \
  "$TARGET_HOME/.config/autostart" \
  "$TARGET_HOME/.local/share/applications" \
  "$RUNTIME_DIR"

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
source "$SCRIPT_DIR/lib/autostart.sh"
source "$SCRIPT_DIR/lib/lifecycle.sh"

run_as_target() {
  HOME="$TARGET_HOME" "$@"
}

msg() {
  :
}

systemctl() {
  :
}

assert_file_exists() {
  local path="$1"
  local description="$2"

  if [ ! -f "$path" ]; then
    printf 'FAIL: %s (missing %s)\n' "$description" "$path" >&2
    exit 1
  fi
}

assert_file_missing() {
  local path="$1"
  local description="$2"

  if [ -e "$path" ]; then
    printf 'FAIL: %s (unexpected %s)\n' "$description" "$path" >&2
    exit 1
  fi
}

assert_grep() {
  local pattern="$1" file="$2" description="$3"
  if ! grep -q "$pattern" "$file"; then
    printf 'FAIL: %s (no match for %s in %s)\n' "$description" "$pattern" "$file" >&2
    exit 1
  fi
}

printf '[Desktop Entry]\nName=GitKraken legacy\nExec=gitkraken\n' \
  >"$TARGET_HOME/.config/autostart/gitkraken-autostart.desktop"

DESKTOP_DIRS=("$TARGET_HOME/.local/share/applications")

configure_autostart_apps

if grep -q 'launch_if_exists gitkraken' "$TARGET_HOME/.local/bin/autostart_apps.sh"; then
  printf 'FAIL: aggregate launcher should not start GitKraken\n' >&2
  exit 1
fi

# ── configure_selected_app_autostart ─────────────────────────────────────────

# GitKraken's [S] selection must resolve the snap desktop candidate, install one
# canonical entry, persist it for the next menu run, and remove it when [S] is
# cleared.
printf '[Desktop Entry]\nName=GitKraken Snap\nExec=/snap/bin/gitkraken --no-sandbox %%U\n' \
  >"$TARGET_HOME/.local/share/applications/gitkraken_gitkraken.desktop"
MANAGED_STARTUP_APPS='gitkraken.desktop|gitkraken_gitkraken.desktop'
SELECTED_STARTUP_APPS='gitkraken.desktop|gitkraken_gitkraken.desktop'
configure_selected_app_autostart
assert_file_missing \
  "$TARGET_HOME/.config/autostart/gitkraken-autostart.desktop" \
  "GitKraken [S] should remove the obsolete legacy launcher"
assert_file_exists \
  "$TARGET_HOME/.config/autostart/gitkraken_gitkraken.desktop" \
  "GitKraken [S] should install the snap desktop launcher"
assert_grep '^X-GNOME-Autostart-enabled=true$' \
  "$TARGET_HOME/.config/autostart/gitkraken_gitkraken.desktop" \
  "GitKraken [S] should enable GNOME autostart"
selected_list="$(list_selected_app_autostart)"
if ! grep -qx 'gitkraken_gitkraken.desktop' <<<"$selected_list"; then
  printf 'FAIL: GitKraken [S] should persist its resolved desktop basename\n' >&2
  exit 1
fi
SELECTED_STARTUP_APPS=''
configure_selected_app_autostart
assert_file_missing \
  "$TARGET_HOME/.config/autostart/gitkraken_gitkraken.desktop" \
  "clearing GitKraken [S] should remove its managed launcher"

# A launcher created before it became [S]-managed must be detected as enabled
# and removed when the user clears [S].
printf '[Desktop Entry]\nName=Cursor\nExec=cursor\nX-GNOME-Autostart-enabled=true\n' \
  >"$TARGET_HOME/.config/autostart/cursor.desktop"
selected_list="$(list_selected_app_autostart)"
grep -qx cursor.desktop <<<"$selected_list" || {
  printf 'FAIL: live legacy Cursor launcher should restore its [S] marker\n' >&2
  exit 1
}
MANAGED_STARTUP_APPS='cursor.desktop'
SELECTED_STARTUP_APPS=''
configure_selected_app_autostart
assert_file_missing \
  "$TARGET_HOME/.config/autostart/cursor.desktop" \
  "clearing Cursor [S] should remove a pre-migration launcher"

printf '[Desktop Entry]\nName=Alpha\nExec=alpha\n[Desktop Action New]\nName=New\n' \
  >"$TARGET_HOME/.local/share/applications/alpha.desktop"
printf '[Desktop Entry]\nName=Beta\nExec=beta\n' \
  >"$TARGET_HOME/.local/share/applications/beta-alt.desktop"
printf '[Desktop Entry]\nName=Gamma\nExec=gamma\n' \
  >"$TARGET_HOME/.local/share/applications/gamma.desktop"
printf '[Desktop Entry]\nName=Manual\nExec=manual\n' \
  >"$TARGET_HOME/.config/autostart/manual.desktop"

MANAGED_STARTUP_APPS='alpha.desktop;beta.desktop|beta-alt.desktop;gamma.desktop'
SELECTED_STARTUP_APPS='alpha.desktop;beta.desktop|beta-alt.desktop'
configure_selected_app_autostart

assert_file_exists \
  "$TARGET_HOME/.config/autostart/alpha.desktop" \
  "selected Alpha launcher should autostart"
enabled_line="$(grep -n '^X-GNOME-Autostart-enabled=true$' \
  "$TARGET_HOME/.config/autostart/alpha.desktop" | cut -d: -f1)"
action_line="$(grep -n '^\[Desktop Action New\]$' \
  "$TARGET_HOME/.config/autostart/alpha.desktop" | cut -d: -f1)"
if [ -z "$enabled_line" ] || [ "$enabled_line" -ge "$action_line" ]; then
  printf 'FAIL: autostart flag should be in the main Desktop Entry section\n' >&2
  exit 1
fi
assert_file_exists \
  "$TARGET_HOME/.config/autostart/beta-alt.desktop" \
  "the first installed Beta launcher candidate should autostart"
assert_file_missing \
  "$TARGET_HOME/.config/autostart/gamma.desktop" \
  "unselected Gamma launcher should not autostart"
detect_selected_app_autostart || {
  printf 'FAIL: selected-app autostart state should be detected\n' >&2
  exit 1
}

selected_list="$(list_selected_app_autostart)"
if ! grep -qx alpha.desktop <<<"$selected_list" || \
   ! grep -qx beta-alt.desktop <<<"$selected_list"; then
  printf 'FAIL: selected startup listing should expose persisted launcher basenames\n' >&2
  exit 1
fi

first_hash="$(sha256sum \
  "$TARGET_HOME/.config/autostart/alpha.desktop" \
  "$TARGET_HOME/.config/autostart/beta-alt.desktop" \
  "$TARGET_HOME/.local/state/linux-configuration-setup/selected-app-autostart.list")"
configure_selected_app_autostart
second_hash="$(sha256sum \
  "$TARGET_HOME/.config/autostart/alpha.desktop" \
  "$TARGET_HOME/.config/autostart/beta-alt.desktop" \
  "$TARGET_HOME/.local/state/linux-configuration-setup/selected-app-autostart.list")"
if [ "$first_hash" != "$second_hash" ]; then
  printf 'FAIL: repeated selected-app startup configuration should be idempotent\n' >&2
  exit 1
fi

# Re-applying a different selection removes only entries previously owned by
# this feature and preserves unrelated user autostart files.
SELECTED_STARTUP_APPS='gamma.desktop'
configure_selected_app_autostart
assert_file_missing \
  "$TARGET_HOME/.config/autostart/alpha.desktop" \
  "deselected Alpha launcher should be removed"
assert_file_missing \
  "$TARGET_HOME/.config/autostart/beta-alt.desktop" \
  "deselected Beta launcher should be removed"
assert_file_exists \
  "$TARGET_HOME/.config/autostart/gamma.desktop" \
  "newly selected Gamma launcher should autostart"
assert_file_exists \
  "$TARGET_HOME/.config/autostart/manual.desktop" \
  "unmanaged user autostart files should be preserved"

uninstall_selected_app_autostart
assert_file_missing \
  "$TARGET_HOME/.config/autostart/gamma.desktop" \
  "uninstall should remove the tracked selected launcher"
assert_file_exists \
  "$TARGET_HOME/.config/autostart/manual.desktop" \
  "uninstall should preserve unmanaged user autostart files"

selected_list="$(list_selected_app_autostart || true)"
if grep -qx gamma.desktop <<<"$selected_list"; then
  printf 'FAIL: selected startup listing should omit an uninstalled managed launcher\n' >&2
  exit 1
fi

printf 'PASS: selected app autostart reconciles tracked desktop entries\n'

# ── configure_kitty_defaults ─────────────────────────────────────────────────

KITTY_CONF="$TARGET_HOME/.config/kitty/kitty.conf"

# Case 1: file absent → created with the setting.
rm -f "$KITTY_CONF"
configure_kitty_defaults
assert_file_exists "$KITTY_CONF" "kitty.conf should be created when absent"
assert_grep '^confirm_os_window_close 0$' "$KITTY_CONF" "created conf disables close prompt"
assert_grep '^map ctrl+backspace send_key ctrl+w$' "$KITTY_CONF" "created conf maps Ctrl+Backspace to word deletion"
assert_grep '^wayland_titlebar_color background$' "$KITTY_CONF" "created conf keeps Wayland controls readable"

# Case 2: existing unrelated line preserved, setting appended.
printf 'allow_remote_control yes\n' >"$KITTY_CONF"
configure_kitty_defaults
assert_grep '^allow_remote_control yes$' "$KITTY_CONF" "existing lines are preserved"
assert_grep '^confirm_os_window_close 0$' "$KITTY_CONF" "setting appended to existing conf"
assert_grep '^map ctrl+backspace send_key ctrl+w$' "$KITTY_CONF" "word deletion mapping appended to existing conf"
assert_grep '^wayland_titlebar_color background$' "$KITTY_CONF" "Wayland titlebar setting appended to existing conf"

# Case 3: stale value replaced in place (not duplicated).
printf 'confirm_os_window_close yes\n' >"$KITTY_CONF"
configure_kitty_defaults
assert_grep '^confirm_os_window_close 0$' "$KITTY_CONF" "stale value replaced with 0"
count="$(grep -c '^confirm_os_window_close' "$KITTY_CONF")"
if [ "$count" -ne 1 ]; then
  printf 'FAIL: confirm_os_window_close should appear once (found %s)\n' "$count" >&2
  exit 1
fi

# Case 4: stale mapping replaced in place (not duplicated).
printf 'map ctrl+backspace send_text all stale\n' >"$KITTY_CONF"
configure_kitty_defaults
assert_grep '^map ctrl+backspace send_key ctrl+w$' "$KITTY_CONF" "stale Ctrl+Backspace mapping replaced"
count="$(grep -c '^map ctrl+backspace' "$KITTY_CONF")"
if [ "$count" -ne 1 ]; then
  printf 'FAIL: Ctrl+Backspace mapping should appear once (found %s)\n' "$count" >&2
  exit 1
fi

configure_kitty_defaults
count="$(grep -c '^map ctrl+backspace' "$KITTY_CONF")"
if [ "$count" -ne 1 ]; then
  printf 'FAIL: Ctrl+Backspace mapping should remain idempotent (found %s)\n' "$count" >&2
  exit 1
fi

# Case 5: stale system-colored Wayland titlebar is replaced once. Kitty's
# libdecor/Yaru system path can render a white bar without visible controls.
printf 'wayland_titlebar_color system\n' >"$KITTY_CONF"
configure_kitty_defaults
assert_grep '^wayland_titlebar_color background$' "$KITTY_CONF" "stale Wayland titlebar color replaced"
count="$(grep -c '^wayland_titlebar_color' "$KITTY_CONF")"
if [ "$count" -ne 1 ]; then
  printf 'FAIL: wayland_titlebar_color should appear once (found %s)\n' "$count" >&2
  exit 1
fi

printf 'PASS: configure_kitty_defaults applies Kitty defaults idempotently\n'
