#!/usr/bin/env bash
# helpers.sh — Configuration-setup-specific helpers.
#
# The shared install-time helpers (msg, need_cmd, is_root, run_as_target,
# apt_install, ensure_session_bus, and the sudo-skip reporting) now live in the
# framework's installer_helpers.sh and are loaded by install.sh via
# isc_load_helpers (single source of truth: linux_installation_scripts_functions).
# This file holds only what is specific to this repository: desktop-file lookup.
#
# Must be sourced after the shared helpers are loaded (so log() is available).

DESKTOP_DIRS=(
  /usr/share/applications
  /var/lib/snapd/desktop/applications
  "$TARGET_HOME/.local/share/applications"
)

# find_python_with_module — Print a Python executable that can import a module.
#   Checks PATH first, then /usr/bin/python3 so user-managed Python shims do not
#   hide APT-provided desktop bindings during clean installs.
#   PYTHON_CANDIDATES may override the candidate list for tests.
#   Args: $1 — module import name. Returns: 0 and prints the executable path.
find_python_with_module() {
  local module="$1"
  local candidate
  for candidate in ${PYTHON_CANDIDATES:-python3 /usr/bin/python3}; do
    if command -v "$candidate" >/dev/null 2>&1 &&
       "$candidate" -c "import ${module}" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

# find_desktop_file_path — Locate the full path of a .desktop file by name.
#   Searches the standard system, snap, and per-user application directories.
#   Args: $1 — desktop entry name, with or without the ".desktop" suffix.
#   Returns: 0 and prints the absolute path of the first match; non-zero if no
#   matching file is found.
find_desktop_file_path() {
  local name="$1"
  log "debug" "find_desktop_file_path: looking up '$name'"
  local dir path="$name"
  if [[ "$name" != *.desktop ]]; then
    path="${name}.desktop"
  fi
  for dir in "${DESKTOP_DIRS[@]}"; do
    if [ -f "${dir}/${path}" ]; then
      printf '%s\n' "${dir}/${path}"
      return 0
    fi
  done
  return 1
}

# find_desktop_entry — Return the basename of the first existing .desktop entry
#   from a list of candidates (useful when an app ships under several ids).
#   Args: $@ — candidate desktop entry names, in priority order.
#   Returns: 0 and prints the matching "<name>.desktop" basename; non-zero if
#   none of the candidates exist.
find_desktop_entry() {
  log "debug" "find_desktop_entry: candidates: $*"
  local candidate
  for candidate in "$@"; do
    if find_desktop_file_path "$candidate" >/dev/null; then
      if [[ "$candidate" == *.desktop ]]; then
        printf '%s\n' "$candidate"
      else
        printf '%s\n' "${candidate}.desktop"
      fi
      return 0
    fi
  done
  return 1
}
