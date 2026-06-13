#!/usr/bin/env bash
# Characterization tests for Chrome PWA icon and desktop-entry configuration.

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

run_as_target() {
  "$@"
}

msg() {
  :
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

source "$SCRIPT_DIR/lib/pwa_icons.sh"

FAKE_BIN="$TARGET_HOME/fake-bin"
mkdir -p "$FAKE_BIN"
GTK_CACHE_LOG="$TARGET_HOME/gtk-update-icon-cache.log"
cat >"$FAKE_BIN/gtk-update-icon-cache" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$GTK_CACHE_LOG"
EOF
chmod +x "$FAKE_BIN/gtk-update-icon-cache"
PATH="$FAKE_BIN:$PATH"

app_id="fmpnliohjhemenmnlpbfagaolkdacoja"
app_manifest_dir="$TARGET_HOME/.config/google-chrome/Default/Web Applications/Manifest Resources/$app_id"
mkdir -p "$app_manifest_dir/Icons" "$TARGET_HOME/.local/share/applications"
printf '{"name":"Claude"}\n' >"$app_manifest_dir/Manifest"
printf 'claude-48\n' >"$app_manifest_dir/Icons/48.png"
printf 'claude-512\n' >"$app_manifest_dir/Icons/512.png"

configure_pwa_icons

icon_name="chrome-$app_id-Default.png"
assert_symlink_target \
  "$TARGET_HOME/.local/share/icons/hicolor/48x48/apps/$icon_name" \
  "$app_manifest_dir/Icons/48.png" \
  "installs each available icon size"

desktop_path="$TARGET_HOME/.local/share/applications/chrome-$app_id-Default.desktop"
assert_file_contains "$desktop_path" "Name=Claude" "creates a named desktop entry"
assert_file_contains \
  "$desktop_path" \
  "Icon=$app_manifest_dir/Icons/512.png" \
  "uses the largest preferred icon in the desktop entry"
assert_file_contains \
  "$GTK_CACHE_LOG" \
  "$TARGET_HOME/.local/share/icons/hicolor" \
  "refreshes the user icon cache"

rm "$app_manifest_dir/Manifest"
printf 'Icon=stale\nName=Claude\n' >"$desktop_path"
configure_pwa_icons
assert_file_contains \
  "$desktop_path" \
  "Icon=$app_manifest_dir/Icons/512.png" \
  "recovers a manifest-less PWA from its existing desktop entry"

empty_home="$(mktemp -d)"
old_target_home="$TARGET_HOME"
TARGET_HOME="$empty_home"
configure_pwa_icons
TARGET_HOME="$old_target_home"
rm -rf "$empty_home"
printf '  PASS: skips cleanly when Chrome has no Web Applications directory\n'
PASS=$((PASS + 1))

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
