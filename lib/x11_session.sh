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

# Build the GDM helper with the shared invoker-toolchain builder.
# Parameters: none; SCRIPT_DIR identifies the source and TARGET_HOME receives the ELF.
# Returns: native build/target installation status.
build_gdm_x11() {
  local program
  program="$(bash "$SCRIPT_DIR/scripts/build_lcs_tools.sh" --bin gdm-x11 --print)" || return 1
  run_as_target install -D -m 0755 "$program" "$TARGET_HOME/.local/bin/gdm-x11"
}

# Resolve a preexisting native helper without a runtime compiler or side effects.
# Parameters: none; source/target paths identify installed binaries.
# Returns: zero and the binary path, or one when no native helper exists.
gdm_x11_program() {
  local candidate
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
  if ! build_gdm_x11; then
    printf '1\n'
    return 1
  fi
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
    result=1
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
    result=1
  fi
  printf '%s\n' "$result"
  return "$result"
}
