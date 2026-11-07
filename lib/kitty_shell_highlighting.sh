#!/usr/bin/env bash
# Install or remove the Kitty-specific Bash line editor.

# Configure the selectable shell-highlighting component.
# Parameters: none. Returns: installer status.
configure_kitty_shell_highlighting() {
  printf 'parameters=none\n' >&2
  local status=0
  run_as_target env KITTY_BLE_ARCHIVE="${KITTY_BLE_ARCHIVE:-}" bash "$SCRIPT_DIR/scripts/kitty_shell_highlighting.sh" install || status=$?
  printf '%s\n' "$status" >&2
  return "$status"
}

# Detect the installed Kitty shell-highlighting component.
# Parameters: none. Returns: zero when installed, otherwise nonzero.
detect_kitty_shell_highlighting() {
  printf 'parameters=none\n' >&2
  if [[ -f "$TARGET_HOME/.local/share/kitty-blesh/ble.sh" ]] && grep -Fq '# kitty-shell-highlighting begin' "$TARGET_HOME/.bashrc"; then
    printf '0\n' >&2
    return 0
  fi
  printf '1\n' >&2
  return 1
}

# Remove only the managed shell-highlighting configuration and editor.
# Parameters: none. Returns: uninstaller status.
uninstall_kitty_shell_highlighting() {
  printf 'parameters=none\n' >&2
  local status=0
  run_as_target bash "$SCRIPT_DIR/scripts/kitty_shell_highlighting.sh" uninstall || status=$?
  printf '%s\n' "$status" >&2
  return "$status"
}
