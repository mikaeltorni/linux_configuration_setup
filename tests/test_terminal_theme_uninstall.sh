#!/usr/bin/env bash
# The terminal_theme uninstall must reset exactly the keys configure sets.
#
# gsettings is stubbed with a recorder so the test never touches the real
# desktop session: it asserts on the recorded command stream instead.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
TARGET_HOME="$WORK_DIR/home"
TARGET_USER="$(id -un)"
SCRIPT_DIR="$ROOT_DIR"
mkdir -p "$TARGET_HOME"

CALLS="$WORK_DIR/gsettings.log"
: >"$CALLS"

msg() { :; }
log() { :; }
# Stubbed gsettings: every key exists, the default profiles are fixed uuids,
# and every invocation is recorded for the assertions below.
run_as_target() {
  if [ "${1:-}" = "gsettings" ]; then
    shift
    printf '%s\n' "$*" >>"$CALLS"
    case "${1:-}" in
      get)
        case "$*" in
          *default-profile-uuid*) printf "'ptyxis-uuid'\n" ;;
          *ProfilesList*) printf "'legacy-uuid'\n" ;;
          *) printf "''\n" ;;
        esac
        ;;
      list-keys)
        printf 'theme\ninterface-style\nbold-is-bright\npalette\ndefault-profile-uuid\ndefault\nuse-theme-colors\nbackground-color\nforeground-color\nbold-color-same-as-fg\n'
        ;;
    esac
    return 0
  fi
  "$@"
}

source "$ROOT_DIR/lib/gsettings_helpers.sh"
source "$ROOT_DIR/lib/lifecycle.sh"

uninstall_terminal_theme

assert_reset() {
  if ! grep -qx "reset $1" "$CALLS"; then
    printf 'missing reset for: %s\n' "$1" >&2
    exit 1
  fi
}

assert_reset "org.gnome.Console theme"
assert_reset "org.gnome.Ptyxis interface-style"
assert_reset "org.gnome.Ptyxis.Profile:/org/gnome/ptyxis/profiles/ptyxis-uuid/ bold-is-bright"
assert_reset "org.gnome.Ptyxis.Profile:/org/gnome/ptyxis/profiles/ptyxis-uuid/ palette"
assert_reset "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:legacy-uuid/ use-theme-colors"
assert_reset "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:legacy-uuid/ background-color"
assert_reset "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:legacy-uuid/ foreground-color"
assert_reset "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:legacy-uuid/ bold-color-same-as-fg"

# Reset only: the uninstall must never write a second hardcoded theme.
if grep -q '^set ' "$CALLS"; then
  printf 'uninstall must not set any gsettings key:\n' >&2
  grep '^set ' "$CALLS" >&2
  exit 1
fi

printf 'test_terminal_theme_uninstall.sh: all assertions passed\n'
