#!/usr/bin/env bash
# gsettings_helpers.sh — GSettings / dconf helper functions
#
# Components:
#   - user_gsettings(args...): Run gsettings as the target user.
#   - gsettings_key_exists(schema, key): Check if a key exists in a schema.
#   - user_gsettings_set_if_key_exists(schema, key, value): Set only if key exists.
#   - set_gsettings_strv(schema, key, values...): Set a string-array (strv) key.
#   - set_gsettings_strv_if_key_exists(schema, key, values...): Set strv only if key exists.
#   - join_as_gsettings_array(values...): Format values as a GSettings array string.
#   - append_gsettings_list(schema, key, value): Append a value to a list (idempotent).
#   - remove_gsettings_list(schema, key, value): Remove a value from a list.
#   - set_indexed_keybinding_map(schema, key_prefix, entries...): Set indexed keybindings.

user_gsettings() { run_as_target gsettings "$@"; }

gsettings_key_exists() {
  local schema="$1" key="$2"
  run_as_target gsettings list-keys "$schema" 2>/dev/null | grep -qx "$key"
}

user_gsettings_set_if_key_exists() {
  local schema="$1" key="$2" value="$3"
  if gsettings_key_exists "$schema" "$key"; then
    user_gsettings set "$schema" "$key" "$value" || true
  fi
}

set_gsettings_strv() {
  local schema="$1" key="$2"; shift 2
  user_gsettings set "$schema" "$key" "$(join_as_gsettings_array "$@")"
}

set_gsettings_strv_if_key_exists() {
  local schema="$1" key="$2"; shift 2
  if gsettings_key_exists "$schema" "$key"; then
    set_gsettings_strv "$schema" "$key" "$@" || true
  fi
}

join_as_gsettings_array() {
  local out="[" first=1 val
  for val in "$@"; do
    [ -n "$val" ] || continue
    [ "$first" -eq 0 ] && out+=", "
    out+="'$val'"
    first=0
  done
  out+="]"
  printf "%s" "$out"
}

append_gsettings_list() {
  local schema="$1" key="$2" value="$3"
  local current newlist
  current="$(user_gsettings get "$schema" "$key" 2>/dev/null || echo "[]")"
  newlist="$(VAL="$value" CURRENT="$current" python3 - <<'PY'
import ast, os
cur_raw = os.environ.get("CURRENT", "").strip()
if cur_raw.startswith("@as "): cur_raw = cur_raw[4:].strip()
try: cur = ast.literal_eval(cur_raw) if cur_raw else []
except Exception: cur = []
if not isinstance(cur, list): cur = []
cur = list(dict.fromkeys(str(item) for item in cur))
val = os.environ.get("VAL", "")
if val and val not in cur: cur.append(val)
print("[" + ", ".join(repr(str(item)) for item in cur) + "]")
PY
)"
  user_gsettings set "$schema" "$key" "$newlist"
}

remove_gsettings_list() {
  local schema="$1" key="$2" value="$3"
  local current newlist
  current="$(user_gsettings get "$schema" "$key" 2>/dev/null || echo "[]")"
  newlist="$(VAL="$value" CURRENT="$current" python3 - <<'PY'
import ast, os
cur_raw = os.environ.get("CURRENT", "").strip()
if cur_raw.startswith("@as "): cur_raw = cur_raw[4:].strip()
try: cur = ast.literal_eval(cur_raw) if cur_raw else []
except Exception: cur = []
if not isinstance(cur, list): cur = []
val = os.environ.get("VAL", "")
cur = [str(item) for item in cur if str(item) != val]
cur = list(dict.fromkeys(cur))
print("[" + ", ".join(repr(str(item)) for item in cur) + "]")
PY
)"
  user_gsettings set "$schema" "$key" "$newlist"
}

set_indexed_keybinding_map() {
  local schema="$1" key_prefix="$2"; shift 2
  local entry index keys key_array=()
  for entry in "$@"; do
    index="${entry%%:*}"
    keys="${entry#*:}"
    IFS=',' read -r -a key_array <<<"$keys"
    set_gsettings_strv "$schema" "${key_prefix}${index}" "${key_array[@]}"
  done
}
