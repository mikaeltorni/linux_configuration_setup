#!/usr/bin/env bash
# helpers.sh — Core utility functions sourced by install scripts
#
# Components:
#   - msg(msg): User-facing message with arrow prefix.
#   - need_cmd(cmd): Check if a command exists in PATH.
#   - apt_install(pkgs...): Idempotently install missing apt packages.
#   - toml_string_array(name): Format a bash array as a TOML string array.
#   - run_as_target(cmd...): Execute a command as the target user.
#   - ensure_root(): Exit with error if not running as root.
#   - ensure_session_bus(): Exit with error if session bus is missing.
#   - find_desktop_file_path(name): Find full path to a .desktop file.
#   - find_desktop_entry(candidates...): Find basename of first existing .desktop.
#
# Must be sourced after SCRIPT_DIR, CONFIG_DIR, TARGET_USER, TARGET_HOME,
# RUNTIME_DIR, DISPLAY_VAL, USER_BUS are set.

msg() { printf "\n==> %s\n" "$*"; }
need_cmd() { command -v "$1" >/dev/null 2>&1; }

# apt_install — Ensure one or more apt packages are installed (idempotent).
#   Skips packages that are already present and only refreshes the apt cache
#   when at least one package is missing, so it is safe to call repeatedly on a
#   clean install. Runs as root (the installer is invoked with sudo).
#   Args: $@ — apt package names to ensure are installed.
#   Returns: 0 when all requested packages are present (or were installed
#     successfully); non-zero if apt-get is unavailable or the install fails.
apt_install() {
  local pkg missing=()
  for pkg in "$@"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    log "debug" "apt_install: all packages already installed: $*"
    return 0
  fi

  if ! need_cmd apt-get; then
    log "error" "apt_install: apt-get not available; cannot install ${missing[*]}"
    return 1
  fi

  log "info" "Installing apt packages: ${missing[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1 || \
    log "warn" "apt_install: 'apt-get update' failed; attempting install anyway"
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

toml_string_array() {
  local ref="$1" item result="[" sep="" arr=()
  eval "arr=(\"\${$ref[@]}\")" || return 1
  for item in "${arr[@]}"; do
    item="${item//\\/\\\\}"
    item="${item//\"/\\\"}"
    result+="${sep}\"${item}\""
    sep=", "
  done
  result+="]"
  printf '%s\n' "$result"
}

run_as_target() {
  sudo -H -u "$TARGET_USER" env \
    HOME="$TARGET_HOME" \
    USER="$TARGET_USER" \
    LOGNAME="$TARGET_USER" \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    DBUS_SESSION_BUS_ADDRESS="$USER_BUS" \
    DISPLAY="$DISPLAY_VAL" \
    "$@"
}

ensure_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log "error" "Please run with sudo: sudo bash $0"
    echo "Please run with sudo: sudo bash $0"
    exit 1
  fi
}

ensure_session_bus() {
  if [ ! -S "${RUNTIME_DIR}/bus" ]; then
    log "error" "No user session bus at ${RUNTIME_DIR}/bus"
    cat <<EOF
No user session bus at ${RUNTIME_DIR}/bus.
Open a terminal in ${TARGET_USER}'s *logged-in desktop* session and run:
  sudo bash $0
EOF
    exit 1
  fi
}

DESKTOP_DIRS=(
  /usr/share/applications
  /var/lib/snapd/desktop/applications
  "$TARGET_HOME/.local/share/applications"
)

find_desktop_file_path() {
  local name="$1"
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

find_desktop_entry() {
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
