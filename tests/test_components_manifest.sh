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
[ "${#ISC_COMPONENTS[@]}" -gt 0 ] && pass "ISC_COMPONENTS is non-empty" \
  || fail "ISC_COMPONENTS is non-empty"

# Collect every function defined under lib/ so each component can be matched to a
# real step function without needing the full runtime environment.
# Component step functions live under lib/; the preflight hook may also be a
# shared-framework helper (e.g. ensure_session_bus) from the sibling
# linux_installation_scripts_functions checkout, so include those too.
shared_helpers="$SCRIPT_DIR/../linux_installation_scripts_functions/installer_helpers.sh"
lib_functions="$(grep -rhoE '^[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)' \
  "$SCRIPT_DIR"/lib/*.sh ${shared_helpers:+"$shared_helpers"} 2>/dev/null \
  | sed -E 's/\s*\(\)//' | sort -u)"

echo ""
echo "--- every component is well-formed and maps to a defined function ---"
declare -A seen_ids=()
manifest_ids=()
for entry in "${ISC_COMPONENTS[@]}"; do
  IFS='|' read -r id label default func <<<"$entry"
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

echo ""
echo "--- --list-components is side-effect free and matches the manifest ---"
tmp_home="$(mktemp -d)"
list_out="$(HOME="$tmp_home" bash "$SCRIPT_DIR/install.sh" --list-components 2>/dev/null)"
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
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
