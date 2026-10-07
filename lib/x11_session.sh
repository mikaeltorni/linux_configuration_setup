#!/usr/bin/env bash
# Persistent GDM policy for the next login; never reloads or stops the session.

# Configure GDM to use X11, preserving unrelated settings.
# Parameters: none. GDM_CUSTOM_CONF and GDM_XSESSIONS_DIR override system paths for tests.
# Returns: 0 on success/root deferral; nonzero when prerequisites or the write fail.
configure_x11_session() {
  printf 'parameters=none\n'
  local configuration="${GDM_CUSTOM_CONF:-/etc/gdm3/custom.conf}"
  local xsessions="${GDM_XSESSIONS_DIR:-/usr/share/xsessions}"
  local result=0
  if ! is_root; then
    note_sudo_required "sudo bash $SCRIPT_DIR/install.sh --select x11_session"
    printf '0\n'
    return 0
  fi
  python3 "$SCRIPT_DIR/scripts/gdm_x11.py" apply "$configuration" "$xsessions" || result=$?
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
  local result=0
  python3 "$SCRIPT_DIR/scripts/gdm_x11.py" check "${GDM_CUSTOM_CONF:-/etc/gdm3/custom.conf}" >/dev/null 2>&1 || result=$?
  printf '%s\n' "$result"
  return "$result"
}
