#!/usr/bin/env bash
# gsettings_helpers.sh — GSettings / dconf helper functions
#
# Components:
#   - user_gsettings(args...): Run gsettings as the target user.
#   - gsettings_key_exists(schema, key): Check if a key exists in a schema.
#   - user_gsettings_set_if_key_exists(schema, key, value): Set only if key exists.
#   - set_gsettings_strv(schema, key, values...): Set a string-array (strv) key.
#   - join_as_gsettings_array(values...): Format values as a GSettings array string.
#   - append_gsettings_list(schema, key, value): Append a value to a list (idempotent).
#   - remove_gsettings_list(schema, key, value): Remove a value from a list.
#   - set_indexed_keybinding_map(schema, key_prefix, entries...): Set indexed keybindings.

# user_gsettings — Run gsettings as the target user (thin wrapper).
#   Args: $@ — arguments forwarded to gsettings.
#   Returns: the exit status of gsettings.
user_gsettings() { run_as_target gsettings "$@"; }

# gsettings_key_exists — Test whether a schema defines a given key.
#   Args: $1 — schema id; $2 — key name.
#   Returns: 0 if the key exists in the schema, non-zero otherwise.
gsettings_key_exists() {
  local schema="$1" key="$2"
  run_as_target gsettings list-keys "$schema" 2>/dev/null | grep -qx "$key"
}

# user_gsettings_set_if_key_exists — Set a key only when the schema defines it,
#   so optional GNOME components don't cause errors when absent.
#   Args: $1 — schema id; $2 — key name; $3 — value.
#   Returns: 0 (the underlying set is best-effort and never aborts the caller).
user_gsettings_set_if_key_exists() {
  local schema="$1" key="$2" value="$3"
  if gsettings_key_exists "$schema" "$key"; then
    user_gsettings set "$schema" "$key" "$value" || true
  fi
}

# set_gsettings_strv — Set a string-array (strv) key from positional values.
#   Args: $1 — schema id; $2 — key name; $@ (after shift) — array elements.
#   Returns: the exit status of the underlying gsettings set.
set_gsettings_strv() {
  local schema="$1" key="$2"; shift 2
  user_gsettings set "$schema" "$key" "$(join_as_gsettings_array "$@")"
}

# join_as_gsettings_array — Format positional values as a GSettings array
#   literal (e.g. ['a', 'b']), skipping empty elements.
#   Args: $@ — values to include in the array.
#   Returns: 0 and prints the array string.
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

# append_gsettings_list — Append a value to a GSettings list key, de-duplicating
#   existing entries so repeated installer runs stay idempotent.
#   Args: $1 — schema id; $2 — key name; $3 — value to append.
#   Returns: the exit status of the final gsettings set.
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

# remove_gsettings_list — Remove every occurrence of a value from a GSettings
#   list key, de-duplicating the remaining entries.
#   Args: $1 — schema id; $2 — key name; $3 — value to remove.
#   Returns: the exit status of the final gsettings set.
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

# set_indexed_keybinding_map — Set a series of indexed keybinding keys (e.g.
#   switch-to-application-1..N) from "index:key1,key2" entries.
#   Args: $1 — schema id; $2 — key prefix; $@ — "<index>:<comma-separated-keys>"
#     entries.
#   Returns: 0 after all entries are applied.
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
