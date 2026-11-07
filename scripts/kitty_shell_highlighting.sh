#!/usr/bin/env bash
# Install a verified ble.sh release and maintain only our Bash startup blocks.
set -euo pipefail
operation="${1:-}"
case "$operation" in install|uninstall) ;; *) exit 2 ;; esac
rc="$HOME/.bashrc"
editor="$HOME/.local/share/kitty-blesh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if [[ "$operation" == install ]]; then
  archive="$tmp/ble.tar.xz"
  if [[ -n "${KITTY_BLE_ARCHIVE:-}" ]]; then
    cp "$KITTY_BLE_ARCHIVE" "$archive"
  else
    curl --fail --location --silent --show-error --max-time 60 \
      'https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly-20261031+1529427.tar.xz' -o "$archive"
  fi
  printf '%s  %s\n' 'd80197ac0733872d1795134df8cd252d07f49813996312da0e40827e9abc451c' "$archive" | sha256sum -c --status
  mkdir -p "$tmp/editor" "$(dirname "$editor")"
  tar -xJf "$archive" --strip-components=1 -C "$tmp/editor"
  test -f "$tmp/editor/ble.sh"
  rm -rf "$editor"
  mv "$tmp/editor" "$editor"
fi
mkdir -p "$(dirname "$rc")"
touch "$rc"
awk '
  $0 == "# kitty-shell-highlighting begin" { skip=1; next }
  $0 == "# kitty-shell-highlighting end" { skip=0; next }
  !skip { print }
' "$rc" > "$tmp/rc"
if [[ "$operation" == install ]]; then
  {
    cat <<'BLOCK'
# kitty-shell-highlighting begin
if [[ $- == *i* && -n ${KITTY_WINDOW_ID:-} && -r $HOME/.local/share/kitty-blesh/ble.sh ]]; then
  source "$HOME/.local/share/kitty-blesh/ble.sh" --attach=none
  bleopt complete_auto_complete=
  ble-face command_builtin='fg=81,bold'
  ble-face command_file='fg=81,bold'
  ble-face syntax_delimiter='fg=214,bold'
fi
# kitty-shell-highlighting end
BLOCK
    cat "$tmp/rc"
    cat <<'BLOCK'
# kitty-shell-highlighting begin
if [[ $- == *i* && -n ${KITTY_WINDOW_ID:-} && -n ${BLE_VERSION:-} ]]; then
  ble-attach
fi
# kitty-shell-highlighting end
BLOCK
  } > "$tmp/newrc"
  cat "$tmp/newrc" > "$rc"
else
  cat "$tmp/rc" > "$rc"
  rm -rf "$editor"
fi
