#!/usr/bin/env bash
# test_components_manifest.sh — Guards the selectable-component manifest.
#
# Every user-visible feature in this repository must remain an independently
# selectable installer component. This test verifies that installer/components.sh
# is well-formed, that each component maps to a step function defined under lib/,
# that the README documents exactly the manifest's components, and that
# `--list-components` is side-effect free and matches the manifest.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

echo "=========================================="
echo "  Component Manifest Tests"
echo "=========================================="

# Source the manifest in isolation: it must only declare arrays/variables and
# must not execute any installation step (side-effect free to source).
echo ""
echo "--- manifest is sourceable without side effects ---"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/installer/components.sh"
assert_eq "linux_configuration_setup" "${ISC_REPO_NAME:-}" "ISC_REPO_NAME is set"

uv_row="$(printf '%s\n' "${ISC_COMPONENTS[@]}" | grep '^uv_setup|')"
[[ "$uv_row" == *"UV package manager and supply-chain protection"* ]] || {
  printf 'FAIL: uv_setup should own supply-chain protection\n' >&2
  exit 1
}
[ -f "$SCRIPT_DIR/configs/uv/uv.toml" ] || {
  printf 'FAIL: UV global config is missing from configuration assets\n' >&2
  exit 1
}
[ -f "$SCRIPT_DIR/configs/tmux/.tmux.conf" ] || {
  printf 'FAIL: tmux config is missing from configurations folder\n' >&2
  exit 1
}
[ -f "$SCRIPT_DIR/configs/udev/61-hide-crosswind-xorg.rules" ] || {
  printf 'FAIL: Crosswind udev hide rule is missing from configuration assets\n' >&2
  exit 1
}
grep -Fq 'ENV{ID_INPUT}=""' "$SCRIPT_DIR/configs/udev/61-hide-crosswind-xorg.rules" || {
  printf 'FAIL: Crosswind udev rule must unset ID_INPUT (Xorg checks presence)\n' >&2
  exit 1
}
grep -Fq 'MFG MFG Crosswind V2' "$SCRIPT_DIR/configs/udev/61-hide-crosswind-xorg.rules" || {
  printf 'FAIL: Crosswind udev rule must match the stick name\n' >&2
  exit 1
}
[ -f "$SCRIPT_DIR/configs/xorg/91-ignore-hotplug-joysticks.conf" ] || {
  printf 'FAIL: Xorg ignore-hotplug config is missing\n' >&2
  exit 1
}
hide_row="$(printf '%s\n' "${ISC_COMPONENTS[@]}" | grep '^hide_hotplug_joysticks|')"
[[ "$hide_row" == *'|on|configure_hide_hotplug_joysticks|detect_hide_hotplug_joysticks|uninstall_hide_hotplug_joysticks' ]] || {
  printf 'FAIL: hide_hotplug_joysticks should be independently selectable and default on\n' >&2
  exit 1
}
tmux_row="$(printf '%s\n' "${ISC_COMPONENTS[@]}" | grep '^tmux_defaults|')"
[[ "$tmux_row" == *"full chat history"* ]] || {
  printf 'FAIL: tmux_defaults should advertise full chat history\n' >&2
  exit 1
}
kitty_apostrophe_row="$(printf '%s\n' "${ISC_COMPONENTS[@]}" | grep '^kitty_ignore_apostrophe|')"
[[ "$kitty_apostrophe_row" == *'|on|configure_kitty_apostrophe_filter|detect_kitty_apostrophe_filter|uninstall_kitty_apostrophe_filter' ]] || {
  printf 'FAIL: kitty_ignore_apostrophe should be independently selectable and default on\n' >&2
  exit 1
}
[[ "$kitty_apostrophe_row" == *'KITTY_IGNORE_APOSTROPHE=on/off'* ]] || {
  printf 'FAIL: kitty_ignore_apostrophe should advertise its environment switch\n' >&2
  exit 1
}
[[ "$kitty_apostrophe_row" == *'outside tmux'* ]] || {
  printf 'FAIL: kitty_ignore_apostrophe should advertise its tmux exemption\n' >&2
  exit 1
}
python3 - "$SCRIPT_DIR/installation_configs/default.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    defaults = json.load(handle)
assert defaults["components"]["kitty_ignore_apostrophe"]["on"] == 1
PY
[ "${#ISC_COMPONENTS[@]}" -gt 0 ] && pass "ISC_COMPONENTS is non-empty" \
  || fail "ISC_COMPONENTS is non-empty"

# Collect every function defined under lib/ so each component can be matched to a
# real step function without needing the full runtime environment.
# Component step functions live under lib/; the preflight hook may also be a
# shared-framework helper (e.g. ensure_session_bus) from the sibling
# linux_installation_scripts_functions checkout, so include those too.
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
shared_helpers="$(isc_helpers_path "$SCRIPT_DIR" || true)"
lib_functions="$(grep -rhoE '^[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)' \
  "$SCRIPT_DIR"/lib/*.sh ${shared_helpers:+"$shared_helpers"} 2>/dev/null \
  | sed -E 's/\s*\(\)//' | sort -u)"

echo ""
echo "--- every component is well-formed and maps to a defined function ---"
declare -A seen_ids=()
manifest_ids=()
for entry in "${ISC_COMPONENTS[@]}"; do
  IFS='|' read -r id label default func _detect _uninstall _section <<<"$entry"
  manifest_ids+=("$id")

  [ -n "$id" ] && pass "id present in '$entry'" || fail "id present in '$entry'"
  [ -n "$label" ] && pass "label present for '$id'" || fail "label present for '$id'"

  if [ "$default" = "on" ] || [ "$default" = "off" ]; then
    pass "default valid for '$id' ($default)"
  else
    fail "default valid for '$id' (got '$default')"
  fi

  if [ -n "${seen_ids[$id]:-}" ]; then
    fail "id '$id' is unique"
  else
    pass "id '$id' is unique"
    seen_ids[$id]=1
  fi

  if printf '%s\n' "$lib_functions" | grep -qx "$func"; then
    pass "component '$id' maps to defined function '$func'"
  else
    fail "component '$id' maps to defined function '$func'"
  fi
done

echo ""
echo "--- master-selected startup is the only app-startup component ---"
for legacy_id in spotify_autostart gitkraken_autostart easyeffects_autostart; do
  if [[ -n "${seen_ids[$legacy_id]:-}" ]]; then
    fail "legacy component '$legacy_id' is absent"
  else
    pass "legacy component '$legacy_id' is absent"
  fi
done
if [[ -n "${seen_ids[selected_app_autostart]:-}" ]]; then
  pass "selected_app_autostart is the startup authority"
else
  fail "selected_app_autostart is the startup authority"
fi

echo ""
echo "--- app rules have one owner ---"
if [ ! -d "$SCRIPT_DIR/configs/gnome-extensions/app-rules@local" ] &&
   ! printf '%s\n' "${ISC_COMPONENTS[@]}" | grep -q '^app_rules|'; then
  pass "App rules are exclusively installed by linux_workspaces_setup"
else
  fail "Configuration must not bundle or select competing app rules"
fi

echo "--- LM Studio and Monkeytype are not dock favorites ---"
if grep -Fq 'add_favorite lm-studio.desktop' "$SCRIPT_DIR/lib/gnome_desktop.sh"; then
  fail "LM Studio is absent from the baseline dock favorites"
else
  pass "LM Studio is absent from the baseline dock favorites"
fi

if grep -Fq "monkeytype.desktop" "$SCRIPT_DIR/lib/gnome_desktop.sh"; then
  fail "Monkeytype is absent from the baseline dock favorites"
else
  pass "Monkeytype is absent from the baseline dock favorites"
fi

echo ""
echo "--- the preflight hook maps to a defined function ---"
if [ -n "${ISC_PREFLIGHT:-}" ]; then
  if printf '%s\n' "$lib_functions" | grep -qx "$ISC_PREFLIGHT"; then
    pass "preflight '$ISC_PREFLIGHT' is defined"
  else
    fail "preflight '$ISC_PREFLIGHT' is defined"
  fi
fi

echo ""
echo "--- README documents exactly the manifest's components ---"
readme="$SCRIPT_DIR/README.md"
for id in "${manifest_ids[@]}"; do
  if grep -qF "\`$id\`" "$readme"; then
    pass "README documents component '$id'"
  else
    fail "README documents component '$id'"
  fi
done

if grep -Eq 'Phase [0-9] of [0-9]|[0-9]-Repo Desktop Setup Chain' "$readme"; then
  fail "README does not claim an obsolete numbered setup chain"
else
  pass "README does not claim an obsolete numbered setup chain"
fi

if grep -q 'detect_app_rules()' "$SCRIPT_DIR/lib/lifecycle.sh"; then
  fail "app-rules detect helper stays in workspaces_setup"
else
  pass "app-rules detect helper stays in workspaces_setup"
fi

if grep -q 'SELECTED_FEATURES="${FEATURES:-}"' "$SCRIPT_DIR/install.sh"; then
  fail "FEATURES filter is gone; use --select"
else
  pass "FEATURES filter is gone; use --select"
fi

echo ""
echo "--- --list-components is side-effect free and matches the manifest ---"
tmp_home="$(mktemp -d)"
# The isolated HOME hides the usual ~/projects fallback, so hand the installer
# the framework checkout explicitly instead of letting it reach the network.
isc_functions_dir="$(dirname "$(isc_helpers_path "$SCRIPT_DIR")")"
list_out="$(HOME="$tmp_home" ISC_FUNCTIONS_DIR="$isc_functions_dir" \
  bash "$SCRIPT_DIR/install.sh" --list-components 2>/dev/null)"
listed_ids="$(printf '%s\n' "$list_out" | awk -F'\t' 'NF{print $1}')"
expected_ids="$(printf '%s\n' "${manifest_ids[@]}")"
assert_eq "$expected_ids" "$listed_ids" "--list-components prints the manifest ids in order"

# Listing must not write logs or other artifacts into the project or HOME.
if [ -z "$(ls -A "$tmp_home" 2>/dev/null)" ]; then
  pass "--list-components leaves HOME untouched"
else
  fail "--list-components leaves HOME untouched (created: $(ls -A "$tmp_home"))"
fi
rm -rf "$tmp_home"

echo ""
echo "--- selected startup listing is a side-effect-free CLI query ---"
tmp_home="$(mktemp -d)"
mkdir -p "$tmp_home/.local/state/linux-configuration-setup"
printf 'kitty.desktop\n' >"$tmp_home/.local/state/linux-configuration-setup/selected-app-autostart.list"
selected_out="$(TARGET_HOME_OVERRIDE="$tmp_home" bash "$SCRIPT_DIR/install.sh" --list-selected-startup-apps 2>/dev/null)"
assert_eq "kitty.desktop" "$selected_out" "--list-selected-startup-apps reports persisted selection"
rm -rf "$tmp_home"

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
