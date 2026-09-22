#!/usr/bin/env bash
# Install the graphical-session user service for Seagate-labelled volumes.

# seagate_mount_unit_path — Path of the installed systemd user unit.
seagate_mount_unit_path() {
  printf '%s\n' "$TARGET_HOME/.config/systemd/user/seagate-volumes-mount.service"
}

# configure_seagate_mount — Install and start the volume mount user service.
#   Args: none. Returns: nonzero if installation or service activation fails.
configure_seagate_mount() {
  local helper_dir unit_dir unit_path
  helper_dir="$TARGET_HOME/.local/libexec/linux-configuration-setup"
  unit_dir="$TARGET_HOME/.config/systemd/user"
  unit_path="$(seagate_mount_unit_path)"
  log info "configure_seagate_mount: installing $unit_path"
  run_as_target install -d -m 0755 "$helper_dir" "$unit_dir" || return 1
  run_as_target install -m 0755 "$SCRIPT_DIR/scripts/mount_seagate_volumes.sh" "$helper_dir/mount-seagate-volumes" || return 1
  run_as_target install -m 0644 "$SCRIPT_DIR/lib/logging.sh" "$helper_dir/logging.sh" || return 1
  run_as_target install -m 0644 "$SCRIPT_DIR/configs/systemd/seagate-volumes-mount.service" "$unit_path" || return 1
  run_as_target systemctl --user daemon-reload || return 1
  run_as_target systemctl --user enable --now seagate-volumes-mount.service || return 1
  log info "configure_seagate_mount: enabled seagate-volumes-mount.service"
}

# detect_seagate_mount — True when the helper and service are installed.
detect_seagate_mount() {
  [ -x "$TARGET_HOME/.local/libexec/linux-configuration-setup/mount-seagate-volumes" ] &&
    [ -f "$(seagate_mount_unit_path)" ]
}

# uninstall_seagate_mount — Remove only this component's user service files.
#   Args: none. Returns: 0 after best-effort unit deactivation.
uninstall_seagate_mount() {
  local helper_dir
  helper_dir="$TARGET_HOME/.local/libexec/linux-configuration-setup"
  log info "uninstall_seagate_mount: disabling Seagate mount service"
  run_as_target systemctl --user disable --now seagate-volumes-mount.service >/dev/null 2>&1 || true
  run_as_target rm -f "$helper_dir/mount-seagate-volumes" "$helper_dir/logging.sh" "$(seagate_mount_unit_path)"
  run_as_target systemctl --user daemon-reload || true
}
