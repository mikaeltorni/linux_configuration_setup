#!/usr/bin/env bash
# Persistent GDM policy for the next login; never reloads or stops the session.

# Save the target user's Ubuntu Xorg choice through AccountsService.
# Parameters: none. TARGET_UID identifies the account; GDM_XSESSIONS_DIR supplies installed sessions.
# Returns: 0 when all saved preferences are verified; 1 when unavailable or unsuccessful.
save_x11_account_session() {
  printf 'parameters=none\n'
  local xsessions="${GDM_XSESSIONS_DIR:-/usr/share/xsessions}"
  local account="/org/freedesktop/Accounts/User${TARGET_UID}"
  local method property value actual
  if [[ ! -f "$xsessions/ubuntu-xorg.desktop" ]] || ! command -v busctl >/dev/null 2>&1; then
    printf '1\n'
    return 1
  fi
  for method in SetXSession SetSession SetSessionType; do
    value=ubuntu-xorg
    [[ "$method" != SetSessionType ]] || value=x11
    if ! run_as_target busctl --timeout=5 --allow-interactive-authorization=no call \
      org.freedesktop.Accounts "$account" org.freedesktop.Accounts.User "$method" s "$value"; then
      printf '1\n'
      return 1
    fi
  done
  for property in XSession Session SessionType; do
    value=ubuntu-xorg
    [[ "$property" != SessionType ]] || value=x11
    if ! actual="$(run_as_target busctl --timeout=5 get-property \
      org.freedesktop.Accounts "$account" org.freedesktop.Accounts.User "$property")" ||
       [[ "$actual" != "s \"$value\"" ]]; then
      printf '1\n'
      return 1
    fi
  done
  msg "Saved X11 for your next login. Log out and back in when ready; the running session is unchanged."
  printf '0\n'
  return 0
}

# Build gdm-x11 with the invoker's Cargo. Tests set TEST_EUID and keep Python.
# Parameters: none. SCRIPT_DIR is the repository and TARGET_HOME receives the ELF.
# Returns: 0 when Cargo is absent, this is a fixture run, or the binary is installed.
build_gdm_x11() {
  [[ -z "${TEST_EUID:-}" ]] || return 0
  command -v cargo >/dev/null 2>&1 || return 0
  local cargo_bin cargo_home rustup_home
  cargo_bin="$(command -v cargo)"
  cargo_home="$(cd "$(dirname "$cargo_bin")/.." && pwd)"
  rustup_home="$(cd "$(dirname "$cargo_home")" && pwd)/.rustup"
  env CARGO_HOME="$cargo_home" RUSTUP_HOME="$rustup_home" \
    cargo build --locked --release --manifest-path "$SCRIPT_DIR/Cargo.toml" --bin gdm-x11
  install -D -m 0755 "$SCRIPT_DIR/target/release/gdm-x11" "$SCRIPT_DIR/dist/gdm-x11"
  if [[ -n "${TARGET_HOME:-}" ]]; then
    install -D -m 0755 "$SCRIPT_DIR/target/release/gdm-x11" "$TARGET_HOME/.local/bin/gdm-x11"
  fi
}

# Print the gdm-x11 ELF when Cargo is available and a build exists.
# Parameters: none. Returns: 0 and the path, or 1 so the caller uses Python.
gdm_x11_program() {
  local candidate
  command -v cargo >/dev/null 2>&1 || return 1
  for candidate in \
    "$SCRIPT_DIR/target/release/gdm-x11" \
    "$SCRIPT_DIR/dist/gdm-x11" \
    "${TARGET_HOME:-}/.local/bin/gdm-x11"
  do
    [[ -n "$candidate" && -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

# Configure GDM to use X11, preserving unrelated settings.
# Parameters: none. GDM_CUSTOM_CONF and GDM_XSESSIONS_DIR override system paths for tests.
# Returns: 0 on success/root deferral; nonzero when prerequisites or the write fail.
configure_x11_session() {
  printf 'parameters=none\n'
  local configuration="${GDM_CUSTOM_CONF:-/etc/gdm3/custom.conf}"
  local xsessions="${GDM_XSESSIONS_DIR:-/usr/share/xsessions}"
  local result=0 program
  build_gdm_x11
  if ! is_root; then
    if ! save_x11_account_session; then
      msg "Could not save the account's X11 preference; the system policy still requires the sudo command below."
    fi
    note_sudo_required "sudo bash $SCRIPT_DIR/install.sh --select x11_session"
    printf '0\n'
    return 0
  fi
  if program="$(gdm_x11_program)"; then
    "$program" apply "$configuration" "$xsessions" || result=$?
  else
    python3 "$SCRIPT_DIR/scripts/gdm_x11.py" apply "$configuration" "$xsessions" || result=$?
  fi
  # GDM 46's HUP handler only rereads settings. It does not stop GDM or Shell.
  if [[ "$result" -eq 0 ]] && command -v systemctl >/dev/null 2>&1 &&
     systemctl is-active --quiet gdm.service; then
    systemctl kill --kill-who=main --signal=HUP gdm.service || result=$?
  fi
  printf '%s\n' "$result"
  return "$result"
}

# Inspect the effective system policy rather than an installer receipt.
# Parameters: none. GDM_CUSTOM_CONF overrides the system path for tests.
# Returns: 0 when GDM is configured for X11; nonzero otherwise.
detect_x11_session() {
  printf 'parameters=none\n'
  local result=0 program
  if program="$(gdm_x11_program)"; then
    "$program" check "${GDM_CUSTOM_CONF:-/etc/gdm3/custom.conf}" >/dev/null 2>&1 || result=$?
  else
    python3 "$SCRIPT_DIR/scripts/gdm_x11.py" check "${GDM_CUSTOM_CONF:-/etc/gdm3/custom.conf}" >/dev/null 2>&1 || result=$?
  fi
  printf '%s\n' "$result"
  return "$result"
}
