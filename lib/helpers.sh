#!/usr/bin/env bash
# helpers.sh — Core utility functions sourced by install scripts
#
# Components:
#   - msg(msg): User-facing message with arrow prefix.
#   - need_cmd(cmd): Check if a command exists in PATH.
#   - apt_install(pkgs...): Idempotently install missing apt packages.
#   - toml_string_array(name): Format a bash array as a TOML string array.
#   - run_as_target(cmd...): Execute a command as the target user.
#   - ensure_session_bus(): Exit with error if session bus is missing.
#   - find_desktop_file_path(name): Find full path to a .desktop file.
#   - find_desktop_entry(candidates...): Find basename of first existing .desktop.
#
# Must be sourced after SCRIPT_DIR, CONFIG_DIR, TARGET_USER, TARGET_HOME,
# RUNTIME_DIR, DISPLAY_VAL, USER_BUS are set.

# msg — Print a user-facing message to stdout with an "==> " arrow prefix.
#   Args: $* — message text to display.
#   Returns: always 0.
msg() { printf "\n==> %s\n" "$*"; }

# need_cmd — Test whether a command is available on PATH.
#   Args: $1 — command name to look up.
#   Returns: 0 if the command exists, non-zero otherwise.
need_cmd() { command -v "$1" >/dev/null 2>&1; }

# is_root — Test whether the script runs with root privileges.
#   Args: none. Returns: 0 when root, non-zero otherwise.
is_root() { [ "$(id -u)" -eq 0 ]; }

# Root-only steps skipped during a non-root run; reported at the end.
SUDO_REQUIRED_STEPS=()

# note_sudo_required — Record a skipped root-only step for the final report.
#   Args: $1 — human-readable description of the skipped step. Returns: 0.
note_sudo_required() {
  SUDO_REQUIRED_STEPS+=("$1")
  msg "SKIP (requires sudo): $1"
}

# report_sudo_required — Print all root-only steps skipped this run, if any.
#   Args: none. Returns: 0.
report_sudo_required() {
  [ "${#SUDO_REQUIRED_STEPS[@]}" -eq 0 ] && return 0
  msg "The following steps still require root and were skipped:"
  printf '    - %s\n' "${SUDO_REQUIRED_STEPS[@]}"
  msg "Apply them with: sudo bash install.sh"
}

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

  if ! is_root; then
    note_sudo_required "apt install ${missing[*]}"
    return 0
  fi

  log "info" "Installing apt packages: ${missing[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1 || \
    log "warn" "apt_install: 'apt-get update' failed; attempting install anyway"
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

# toml_string_array — Format a named bash array as a TOML string array literal.
#   Escapes backslashes and double quotes in each element.
#   Args: $1 — name of the array variable to format (passed by name).
#   Returns: 0 and prints e.g. ["a", "b"]; non-zero if the array is unreadable.
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

# run_as_target — Run a command as the target (non-root) user with the desktop
#   session environment (HOME, XDG_RUNTIME_DIR, DBUS, DISPLAY) populated so that
#   gsettings/systemctl --user calls reach the live session.
#   Args: $@ — command and arguments to execute.
#   Returns: the exit status of the executed command.
run_as_target() {
  if [ "$(id -un)" = "$TARGET_USER" ]; then
    env \
      HOME="$TARGET_HOME" \
      USER="$TARGET_USER" \
      LOGNAME="$TARGET_USER" \
      XDG_RUNTIME_DIR="$RUNTIME_DIR" \
      DBUS_SESSION_BUS_ADDRESS="$USER_BUS" \
      DISPLAY="$DISPLAY_VAL" \
      "$@"
  else
    sudo -H -u "$TARGET_USER" env \
      HOME="$TARGET_HOME" \
      USER="$TARGET_USER" \
      LOGNAME="$TARGET_USER" \
      XDG_RUNTIME_DIR="$RUNTIME_DIR" \
      DBUS_SESSION_BUS_ADDRESS="$USER_BUS" \
      DISPLAY="$DISPLAY_VAL" \
      "$@"
  fi
}

# ensure_session_bus — Abort if the target user has no live D-Bus session bus
#   (required for gsettings/systemctl --user to affect the running desktop).
#   Args: none.
#   Returns: 0 if the session bus socket exists; otherwise logs an error,
#     prints guidance, and exits the process with 1.
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

# find_desktop_file_path — Locate the full path of a .desktop file by name.
#   Searches the standard system, snap, and per-user application directories.
#   Args: $1 — desktop entry name, with or without the ".desktop" suffix.
#   Returns: 0 and prints the absolute path of the first match; non-zero if no
#     matching file is found.
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

# find_desktop_entry — Return the basename of the first existing .desktop entry
#   from a list of candidates (useful when an app ships under several ids).
#   Args: $@ — candidate desktop entry names, in priority order.
#   Returns: 0 and prints the matching "<name>.desktop" basename; non-zero if
#     none of the candidates exist.
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
