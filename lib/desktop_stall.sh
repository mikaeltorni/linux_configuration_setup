#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/desktop_tools.sh"
# desktop_stall.sh — install the user service that snapshots rare input lag.
#
# NVIDIA X11 + a new uinput/hotplug device can start mutter's DFP probe loop.
# Episodes are uncommon after the interceptor/Crosswind fixes, so this watcher
# stays quiet until a trigger and then writes
# ~/.local/state/desktop-stall/episodes/.

# dsc_helper_path — Installed capture helper path for TARGET_HOME.
dsc_helper_path() {
  printf '%s\n' "$TARGET_HOME/.local/libexec/linux-configuration-setup/desktop-stall-capture"
}

# dsc_unit_path — Installed systemd user unit path for TARGET_HOME.
dsc_unit_path() {
  printf '%s\n' "$TARGET_HOME/.config/systemd/user/desktop-stall-capture.service"
}

# configure_desktop_stall_capture — install, enable, and start the watcher.
#   Args: none. Returns: 0 on success, 1 when the helper/unit cannot be installed.
# Parameters: none; installer globals identify source and target.
# Returns: existing file/service installation status.
configure_desktop_stall_capture() {
  local libexec_dir unit_dir helper_src unit_src helper_dest unit_dest tmp_unit
  libexec_dir="$TARGET_HOME/.local/libexec/linux-configuration-setup"
  unit_dir="$TARGET_HOME/.config/systemd/user"
  helper_src="$SCRIPT_DIR/scripts/desktop_stall_capture.sh"
  unit_src="$SCRIPT_DIR/configs/systemd/desktop-stall-capture.service"
  helper_dest="$(dsc_helper_path)"
  unit_dest="$(dsc_unit_path)"

  msg "Installing desktop stall capture ($unit_dest)"
  log info "configure_desktop_stall_capture: helper=$helper_dest unit=$unit_dest"
  if [ ! -f "$helper_src" ] || [ ! -f "$unit_src" ]; then
    log error "configure_desktop_stall_capture: missing $helper_src or $unit_src"
    return 1
  fi
  run_as_target install -d -m 0755 "$libexec_dir" || return 1
  run_as_target install -d -m 0755 "$unit_dir" || return 1
  run_as_target install -m 0755 "$helper_src" "$helper_dest" || return 1
  tmp_unit="$(mktemp)"
  "$(lcs_desktop_tools_program)" render-unit "$unit_src" "$tmp_unit" "$SCRIPT_DIR" || { rm -f "$tmp_unit"; return 1; }
  run_as_target install -m 0644 "$tmp_unit" "$unit_dest" || { rm -f "$tmp_unit"; return 1; }
  rm -f "$tmp_unit"
  if ! run_as_target systemctl --user daemon-reload; then
    log error "configure_desktop_stall_capture: daemon-reload failed"
    return 1
  fi
  if ! run_as_target systemctl --user enable --now desktop-stall-capture.service; then
    log error "configure_desktop_stall_capture: enable --now failed"
    return 1
  fi
  log info "configure_desktop_stall_capture: enabled desktop-stall-capture.service"
}

# detect_desktop_stall_capture — true when the helper and user unit are present.
detect_desktop_stall_capture() {
  [ -x "$(dsc_helper_path)" ] && [ -f "$(dsc_unit_path)" ]
}

# uninstall_desktop_stall_capture — disable and remove the watcher.
#   Args: none. Returns: 0.
uninstall_desktop_stall_capture() {
  local helper_dest unit_dest
  helper_dest="$(dsc_helper_path)"
  unit_dest="$(dsc_unit_path)"
  msg "Removing desktop stall capture ($unit_dest)"
  log info "uninstall_desktop_stall_capture: disabling $unit_dest"
  run_as_target systemctl --user disable --now desktop-stall-capture.service >/dev/null 2>&1 || true
  run_as_target rm -f "$helper_dest" "$unit_dest"
  run_as_target systemctl --user daemon-reload || true
}
