#!/usr/bin/env bash
# gsettings_helpers.sh — GSettings / dconf helper functions
#
# Components:
#   - user_gsettings(args...): Run gsettings as the target user.
#   - gsettings_key_exists(schema, key): Check if a key exists in a schema.
#   - user_gsettings_set_if_key_exists(schema, key, value): Set only if key exists.
#   - join_as_gsettings_array(values...): Format values as a GSettings array string.
#   - parse_gsettings_string_array(raw): Split a gsettings string-array value into lines.

# user_gsettings — Run gsettings as the target user (thin wrapper).
#   Args: $@ — arguments forwarded to gsettings.
#   Returns: the exit status of gsettings.
user_gsettings() { log "debug" "user_gsettings: $*"; run_as_target gsettings "$@"; }

# gsettings_key_exists — Test whether a schema defines a given key.
#   Args: $1 — schema id; $2 — key name.
#   Returns: 0 if the key exists in the schema, non-zero otherwise.
gsettings_key_exists() {
  local schema="$1" key="$2"
  log "debug" "gsettings_key_exists: $schema $key"
  run_as_target gsettings list-keys "$schema" 2>/dev/null | grep -qx "$key"
}

# user_gsettings_set_if_key_exists — Set a key only when the schema defines it,
#   so optional GNOME components don't cause errors when absent.
#   Args: $1 — schema id; $2 — key name; $3 — value.
#   Returns: 0 (the underlying set is best-effort and never aborts the caller).
user_gsettings_set_if_key_exists() {
  local schema="$1" key="$2" value="$3"
  log "debug" "user_gsettings_set_if_key_exists: $schema $key=$value"
  if gsettings_key_exists "$schema" "$key"; then
    user_gsettings set "$schema" "$key" "$value" || true
  fi
}

# join_as_gsettings_array — Format positional values as a GSettings array
#   literal (e.g. ['a', 'b']), skipping empty elements.
#   Args: $@ — values to include in the array.
#   Returns: 0 and prints the array string.
join_as_gsettings_array() {
  log "debug" "join_as_gsettings_array: $*"
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

# parse_gsettings_string_array — Split a gsettings/dconf string-array value into
#   one element per line. Empty arrays and malformed values print nothing.
#   Args: $1 — raw value such as ['a.desktop', 'b.desktop'].
#   Returns: 0 always.
parse_gsettings_string_array() {
  local raw="${1:-}" entry
  log "debug" "parse_gsettings_string_array: $raw"
  raw="${raw#@as }"
  raw="${raw#[}"
  raw="${raw%]}"
  raw="${raw//\'/}"
  IFS=', ' read -r -a _parsed <<<"$raw"
  for entry in "${_parsed[@]}"; do
    [ -n "$entry" ] && printf '%s\n' "$entry"
  done
  return 0
}
