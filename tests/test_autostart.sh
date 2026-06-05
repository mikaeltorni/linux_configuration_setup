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

source "$SCRIPT_DIR/lib/helpers.sh"
source "$SCRIPT_DIR/lib/autostart.sh"

run_as_target() {
  HOME="$TARGET_HOME" "$@"
}

msg() {
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

printf '[Desktop Entry]\nName=GitKraken\nExec=gitkraken\n' \
  >"$TARGET_HOME/.local/share/applications/gitkraken.desktop"
printf '[Desktop Entry]\nName=GitKraken legacy\nExec=gitkraken\n' \
  >"$TARGET_HOME/.config/autostart/gitkraken-autostart.desktop"

DESKTOP_DIRS=("$TARGET_HOME/.local/share/applications")
configure_gitkraken_autostart

assert_file_exists \
  "$TARGET_HOME/.config/autostart/gitkraken.desktop" \
  "GitKraken canonical autostart entry should exist"
assert_file_missing \
  "$TARGET_HOME/.config/autostart/gitkraken-autostart.desktop" \
  "GitKraken legacy autostart entry should be removed"

configure_autostart_apps

if grep -q 'launch_if_exists gitkraken' "$TARGET_HOME/.local/bin/autostart_apps.sh"; then
  printf 'FAIL: aggregate launcher should not start GitKraken\n' >&2
  exit 1
fi

printf 'PASS: GitKraken uses one canonical autostart entry\n'
