#!/usr/bin/env bash
# Configure GNOME Keyring for prompt-free automatic-login sessions.

# _build_passwordless_keyring — Restore items into an isolated empty-password keyring.
_build_passwordless_keyring() {
  local snapshot="$1" staging_home="$2" helper="$3" python_bin="$4"

  run_as_target install -d -m 0700 "$staging_home" || return
  run_as_target env HOME="$staging_home" \
    XDG_CONFIG_HOME="$staging_home/.config" \
    XDG_DATA_HOME="$staging_home/.local/share" \
    XDG_RUNTIME_DIR="$staging_home/runtime" \
    dbus-run-session -- bash -euo pipefail -c '
      install -d -m 0700 "$XDG_RUNTIME_DIR"
      printf "\n" | gnome-keyring-daemon --login >/dev/null
      gnome-keyring-daemon --start --components=secrets >/dev/null
      "$3" "$1" import "$2"
      "$3" "$1" check
    ' bash "$helper" "$snapshot" "$python_bin"
}

# _install_keyring_activation — Install and enable the next-boot activation unit.
_install_keyring_activation() {
  local activator="$SCRIPT_DIR/scripts/activate_passwordless_keyring.sh"
  local logging_lib="$SCRIPT_DIR/lib/logging.sh"
  local unit="$SCRIPT_DIR/configs/systemd/passwordless-keyring-activation.service"
  local unlock_dropin="$SCRIPT_DIR/configs/systemd/gnome-keyring-daemon.service.d/passwordless-login-unlock.conf"
  local libexec_dir="$TARGET_HOME/.local/libexec/linux-configuration-setup"
  local unit_dir="$TARGET_HOME/.config/systemd/user"
  local keyring_dropin_dir="$unit_dir/gnome-keyring-daemon.service.d"

  run_as_target install -d -m 0700 "$libexec_dir" || return
  run_as_target install -d -m 0755 "$unit_dir" || return
  run_as_target install -d -m 0755 "$keyring_dropin_dir" || return
  run_as_target install -m 0700 "$activator" \
    "$libexec_dir/activate-passwordless-keyring" || return
  run_as_target install -m 0644 "$logging_lib" \
    "$libexec_dir/logging.sh" || return
  run_as_target install -m 0644 "$unit" \
    "$unit_dir/passwordless-keyring-activation.service" || return
  run_as_target install -m 0644 "$unlock_dropin" \
    "$keyring_dropin_dir/passwordless-login-unlock.conf" || return
  run_as_target systemctl --user daemon-reload || return
  run_as_target systemctl --user enable passwordless-keyring-activation.service \
    >/dev/null || return
}

# _stage_passwordless_keyring — Store verified replacement files without
# touching files currently owned by the live keyring daemon.
_stage_passwordless_keyring() {
  local staging_home="$1" pending_dir="$2"
  local staged_keyrings="$staging_home/.local/share/keyrings"

  run_as_target bash -euo pipefail -c '
    shopt -s nullglob
    staged=("$1"/*.keyring "$1"/default)
    ((${#staged[@]} > 0))
    [[ "$(cat "$1/default")" == login ]]
    rm -rf "$2"
    install -d -m 0700 "$2"
    install -m 0600 "${staged[@]}" "$2"/
    touch "$2/ready"
    chmod 0600 "$2/ready"
  ' bash "$staged_keyrings" "$pending_dir"
}

# configure_passwordless_keyring — Keep Secret Service but remove unlock
# prompts. The replacement is staged while the desktop is running and activated
# before gnome-keyring-daemon starts on the next boot.
configure_passwordless_keyring() {
  local helper="$SCRIPT_DIR/scripts/keyring_snapshot.py"
  local state_dir="$TARGET_HOME/.local/state/linux-configuration-setup"
  local marker="$state_dir/passwordless-keyring-v1"
  local pending_dir="$state_dir/passwordless-keyring-pending"
  local keyring_dir="$TARGET_HOME/.local/share/keyrings"
  local migration_dir snapshot staging_home python_bin

  msg "Configuring prompt-free GNOME login keyring"
  if ! need_cmd systemctl; then
    log "error" "Required command is unavailable: systemctl"
    return 1
  fi
  _install_keyring_activation || return

  if run_as_target test -f "$marker" &&
     run_as_target test -f "$keyring_dir/login.keyring" &&
     [[ "$(run_as_target bash -c 'cat "$1" 2>/dev/null' bash "$keyring_dir/default")" == "login" ]]; then
    if ! python_bin="$(find_python_with_module gi)" ||
       ! run_as_target "$python_bin" -c 'import gi; gi.require_version("Secret", "1")'; then
      log "error" "Python Secret Service bindings are unavailable"
      return 1
    fi
    if run_as_target "$python_bin" "$helper" check >/dev/null 2>&1; then
      msg "Prompt-free login keyring is already configured"
      return 0
    fi
    msg "Restarting GNOME Keyring daemon to apply prompt-free unlock"
    run_as_target systemctl --user restart gnome-keyring-daemon.service || return
    if run_as_target "$python_bin" "$helper" check >/dev/null 2>&1; then
      msg "Prompt-free login keyring is already configured"
      return 0
    fi
    log "error" "Existing Login keyring is still locked after applying the passwordless service override"
    return 1
  fi

  if run_as_target test -f "$pending_dir/ready"; then
    msg "Passwordless Login keyring is already staged for the next boot"
    return 0
  fi

  for command in gnome-keyring-daemon dbus-run-session; do
    if ! need_cmd "$command"; then
      log "error" "Required command is unavailable: $command"
      return 1
    fi
  done
  if [ -z "${python_bin:-}" ] &&
     { ! python_bin="$(find_python_with_module gi)" ||
       ! run_as_target "$python_bin" -c 'import gi; gi.require_version("Secret", "1")'; }; then
    log "error" "Python Secret Service bindings are unavailable"
    return 1
  fi
  log "debug" "configure_passwordless_keyring: using $python_bin for Secret Service migration"

  migration_dir="$(run_as_target mktemp -d "$RUNTIME_DIR/keyring-migration.XXXXXX")" || return
  snapshot="$migration_dir/items.json"
  staging_home="$migration_dir/staging-home"

  if ! run_as_target "$python_bin" "$helper" export "$snapshot"; then
    log "error" "Keyring migration requires all collections to be unlocked once"
    run_as_target rm -rf "$migration_dir"
    return 1
  fi

  if ! _build_passwordless_keyring "$snapshot" "$staging_home" "$helper" "$python_bin" ||
     ! _stage_passwordless_keyring "$staging_home" "$pending_dir" ||
     ! _install_keyring_activation; then
    log "error" "Could not stage the passwordless Login keyring"
    run_as_target rm -rf "$pending_dir" "$migration_dir"
    return 1
  fi

  run_as_target rm -rf "$migration_dir"
  msg "Passwordless Login keyring staged without changing the running keyring"
  msg "It will activate before GNOME Keyring starts on the next reboot"
}
