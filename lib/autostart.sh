#!/usr/bin/env bash
# autostart.sh — Autostart application configuration helpers
#
# Components:
#   - configure_autostart_entry(dest_basename, entry_name, exec_cmd, candidates...):
#     Create or copy a .desktop file into ~/.config/autostart/.
#   - configure_autostart_apps(): Create the general autostart launcher + entry.
#   - configure_selected_app_autostart(): Reconcile master-menu [s] selections.
#   - configure_kitty_defaults(): Apply shared Kitty window and editing defaults.
#
# Sourced after lib/helpers.sh, lib/gsettings_helpers.sh, lib/gnome_desktop.sh.
# Depends on: msg, run_as_target, find_desktop_file_path

# ── Autostart entry creation ─────────────────────────────────────────────────

# configure_autostart_entry — Create or copy an autostart .desktop file.
#   Copies the first matching candidate desktop file into ~/.config/autostart/,
#   or creates a minimal one from parameters if none found.
#   Ensures X-GNOME-Autostart-enabled=true is set in the resulting file.
#   Args:
#     $1: Destination basename (e.g., "spotify")
#     $2: Display name for the entry
#     $3: Exec command string
#     $@: Candidate desktop filenames to search for
#   Returns: 0 (file copy/creation is best-effort and never aborts the caller).
configure_autostart_entry() {
  local dest_basename="$1"
  local entry_name="$2"
  local exec_cmd="$3"
  shift 3
  local candidates=("$@")
  local desktop_src=""

  log "debug" "configure_autostart_entry: dest=$dest_basename name='$entry_name' candidates='${candidates[*]}'"
  run_as_target mkdir -p "$TARGET_HOME/.config/autostart"

  for candidate in "${candidates[@]}"; do
    if desktop_src="$(find_desktop_file_path "$candidate")"; then
      break
    fi
  done

  if [ -n "$desktop_src" ]; then
    run_as_target cp "$desktop_src" "$TARGET_HOME/.config/autostart/${dest_basename}.desktop" || true
  else
    run_as_target tee "$TARGET_HOME/.config/autostart/${dest_basename}.desktop" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=${entry_name}
Exec=${exec_cmd}
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
  fi

  run_as_target bash -lc 'file="$HOME/.config/autostart/'"${dest_basename}"'.desktop"
if [ -f "$file" ]; then
  if grep -q "^X-GNOME-Autostart-enabled=" "$file"; then
    sed -i "s/^X-GNOME-Autostart-enabled=.*/X-GNOME-Autostart-enabled=true/" "$file"
  else
    echo "X-GNOME-Autostart-enabled=true" >> "$file"
  fi
fi' || true
}

# ── Application-specific autostart ───────────────────────────────────────────

# list_selected_app_autostart - Print the persisted basename of each launcher
# selected through the master menu, plus enabled live autostart basenames. The
# live rows let newly migrated application metadata (for example Cursor) adopt
# an existing launcher so the first [S] state is truthful. The master filters
# this output against declared candidates. It returns 1 only when neither
# managed state nor enabled live launchers exist.
# Args: none. Output: unique validated .desktop basenames, one per line.
list_selected_app_autostart() {
  local state_file="$TARGET_HOME/.local/state/linux-configuration-setup/selected-app-autostart.list"
  local autostart_dir="$TARGET_HOME/.config/autostart"
  local basename path managed=0 found=0
  local -A emitted=()
  if [ -f "$state_file" ]; then
    managed=1
    while IFS= read -r basename; do
      [[ "$basename" == *.desktop && "$basename" != */* ]] || continue
      [[ -n "${emitted[$basename]:-}" ]] && continue
      emitted[$basename]=1
      found=1
      printf '%s\n' "$basename"
    done <"$state_file"
  fi
  for path in "$autostart_dir"/*.desktop; do
    [ -f "$path" ] || continue
    grep -qi '^Hidden=true$' "$path" && continue
    grep -qi '^X-GNOME-Autostart-enabled=false$' "$path" && continue
    basename="$(basename "$path")"
    [[ -n "${emitted[$basename]:-}" ]] && continue
    emitted[$basename]=1
    found=1
    printf '%s\n' "$basename"
  done
  [ "$managed" -eq 1 ] || [ "$found" -eq 1 ]
}

# configure_autostart_apps — Create the general autostart launcher script and
#   its autostart entry. The launcher currently starts no applications; add
#   `launch_if_exists <cmd>` lines below to autostart programs on login.
#   Args: none. Returns: 0.
configure_autostart_apps() {
  msg "Configuring general autostart launcher"
  run_as_target install -d -m 0755 "$TARGET_HOME/.local/bin"
  run_as_target tee "$TARGET_HOME/.local/bin/autostart_apps.sh" >/dev/null << 'EOF'
#!/usr/bin/env bash
set -u

launch_if_exists() {
  local cmd="$1"
  shift  # drop the command name; remaining args pass through to the launch
  if command -v "$cmd" >/dev/null 2>&1; then
    "$cmd" "$@" &
  fi
}

exit 0
EOF
  run_as_target chmod +x "$TARGET_HOME/.local/bin/autostart_apps.sh"

  configure_autostart_entry \
    "autostart_apps" \
    "autostart apps" \
    "/bin/bash -lc \"$TARGET_HOME/.local/bin/autostart_apps.sh\""
}

# configure_selected_app_autostart - Reconcile the desktop applications marked
# with [s] in the master installer. SELECTED_STARTUP_APPS and
# MANAGED_STARTUP_APPS contain semicolon-separated launcher groups; within each
# group, pipe-separated desktop filenames are ordered alternatives.
#
# Reconciliation is scoped to MANAGED_STARTUP_APPS: only launchers this run
# actually manages, plus the legacy entries created by this setup chain for
# those same applications, are removed. Persisted entries outside that superset
# are preserved on disk and re-recorded in the state file, so a partial handoff
# (single-component run, repository subset, or a direct child-installer
# invocation) cannot wipe startup apps it was never told about. Unrelated
# user-managed autostart files remain untouched. Missing desktop files are
# logged and skipped rather than replaced with launchers whose Exec command
# cannot be derived safely.
# Args: none. Returns 0 after reconciliation; filesystem errors propagate.
configure_selected_app_autostart() {
  local selected="${SELECTED_STARTUP_APPS:-}"
  local managed="${MANAGED_STARTUP_APPS:-}"
  local state_dir="$TARGET_HOME/.local/state/linux-configuration-setup"
  local state_file="$state_dir/selected-app-autostart.list"
  local pending_file="$state_file.pending"
  local autostart_dir="$TARGET_HOME/.config/autostart"
  local basename group candidate desktop_src known=0 managed_group
  local -a groups=() candidates=() managed_groups=() preserved=()
  local -A managed_basenames=()

  if [ -z "$managed" ]; then
    log "info" "Selected app autostart skipped: no master startup metadata"
    return 0
  fi

  msg "Configuring selected application startup"
  log "info" "Reconciling master-selected application startup entries"
  run_as_target install -d -m 0755 "$autostart_dir" "$state_dir"

  # Index every launcher this run is authorized to touch, and clear each one
  # up front. Removing recognized candidates first adopts launchers written by
  # older per-app installers and guarantees clearing [S] removes the app even
  # when it predates the managed state file.
  IFS=';' read -r -a managed_groups <<<"$managed"
  for managed_group in "${managed_groups[@]}"; do
    IFS='|' read -r -a candidates <<<"$managed_group"
    for candidate in "${candidates[@]}"; do
      [[ "$candidate" == *.desktop && "$candidate" != */* ]] || continue
      managed_basenames["$candidate"]=1
      log "debug" "Removing managed startup candidate before reconciliation: $candidate"
      run_as_target rm -f "$autostart_dir/$candidate"
    done
  done

  # Carry over persisted entries that this run's metadata does not cover. A
  # partial handoff (a single-component run, a repository subset, or a manual
  # child-installer invocation) only describes part of the user's [s] choices,
  # so anything outside MANAGED_STARTUP_APPS keeps both its launcher and its
  # state row. Without this the narrow run would silently delete every startup
  # app it happened not to know about.
  if [ -f "$state_file" ]; then
    while IFS= read -r basename; do
      [[ "$basename" == *.desktop && "$basename" != */* ]] || continue
      if [ -z "${managed_basenames[$basename]:-}" ]; then
        log "info" "Preserving startup entry outside this run's managed metadata: $basename"
        preserved+=("$basename")
      fi
    done <"$state_file"
  fi

  # Filenames written by older setup-chain components before the unified [s]
  # selector existed. They are not metadata candidates, so each is tied to the
  # candidate that superseded it and is only cleared when this run actually
  # manages that application — otherwise a partial run would delete a legacy
  # launcher it has no authority over. Rows are "alias:anchor|anchor…".
  local legacy_row legacy_alias legacy_anchors legacy_anchor
  for legacy_row in \
    "gitkraken-autostart.desktop:gitkraken.desktop|gitkraken_gitkraken.desktop" \
    "easyeffects.desktop:com.github.wwmm.easyeffects.desktop|org.gnome.EasyEffects.desktop"; do
    legacy_alias="${legacy_row%%:*}"
    legacy_anchors="${legacy_row#*:}"
    IFS='|' read -r -a candidates <<<"$legacy_anchors"
    for legacy_anchor in "${candidates[@]}"; do
      [ -n "${managed_basenames[$legacy_anchor]:-}" ] || continue
      log "debug" "Removing legacy startup alias $legacy_alias for $legacy_anchor"
      run_as_target rm -f "$autostart_dir/$legacy_alias"
      break
    done
  done
  # Older EasyEffects setup enabled a user service in addition to its desktop
  # entry. Disable that duplicate login path when this run manages EasyEffects;
  # the selected desktop launcher is now the single source of startup behavior.
  # Do not stop a running instance.
  if [ -n "${managed_basenames[com.github.wwmm.easyeffects.desktop]:-}" ] \
     || [ -n "${managed_basenames[org.gnome.EasyEffects.desktop]:-}" ]; then
    run_as_target systemctl --user disable easyeffects.service >/dev/null 2>&1 || true
  fi
  run_as_target sh -c ': > "$1"' _ "$pending_file"
  if [ "${#preserved[@]}" -gt 0 ]; then
    printf '%s\n' "${preserved[@]}" | run_as_target tee -a "$pending_file" >/dev/null
  fi

  IFS=';' read -r -a groups <<<"$selected"
  for group in "${groups[@]}"; do
    [ -n "$group" ] || continue
    known=0
    for managed_group in "${managed_groups[@]}"; do
      if [ "$group" = "$managed_group" ]; then known=1; break; fi
    done
    if [ "$known" -ne 1 ]; then
      log "warn" "Skipping startup launcher group absent from managed metadata: $group"
      continue
    fi

    desktop_src=""
    IFS='|' read -r -a candidates <<<"$group"
    for candidate in "${candidates[@]}"; do
      [[ "$candidate" == *.desktop && "$candidate" != */* ]] || continue
      if desktop_src="$(find_desktop_file_path "$candidate")"; then
        break
      fi
      desktop_src=""
    done
    if [ -z "$desktop_src" ]; then
      log "warn" "No installed desktop file found for startup launcher group: $group"
      continue
    fi

    basename="$(basename "$desktop_src")"
    log "info" "Installing selected startup entry: $basename"
    run_as_target cp "$desktop_src" "$autostart_dir/$basename"
    run_as_target bash -c '
file="$1"
if grep -q "^X-GNOME-Autostart-enabled=" "$file"; then
  sed -i "s/^X-GNOME-Autostart-enabled=.*/X-GNOME-Autostart-enabled=true/" "$file"
elif grep -q "^\\[Desktop Entry\\]$" "$file"; then
  sed -i "/^\\[Desktop Entry\\]$/a X-GNOME-Autostart-enabled=true" "$file"
else
  printf "X-GNOME-Autostart-enabled=true\\n" >>"$file"
fi
' _ "$autostart_dir/$basename"
    printf '%s\n' "$basename" | run_as_target tee -a "$pending_file" >/dev/null
  done

  run_as_target mv "$pending_file" "$state_file"
  log "info" "Selected application startup reconciliation complete"
}

# ── Kitty terminal defaults ──────────────────────────────────────────────────

# configure_kitty_defaults — Ensure ~/.config/kitty/kitty.conf uses a readable
#   Wayland titlebar with visible controls, disables the close-window
#   confirmation, and translates Ctrl+Backspace to Ctrl+W, the conventional
#   terminal word-rubout key. Idempotently creates, replaces, or appends all
#   managed settings without disturbing unrelated configuration. The separate
#   kitty_ignore_apostrophe component owns apostrophe suppression.
configure_kitty_defaults() {
  msg "Configuring Kitty defaults (window behavior and input mappings)"
  log "info" "Applying managed Kitty defaults for $TARGET_USER"

  run_as_target bash -lc '
set -eu
conf="$HOME/.config/kitty/kitty.conf"
mkdir -p "$(dirname "$conf")"
if [ ! -f "$conf" ]; then
  printf "# Managed by linux_configuration_setup.\n" > "$conf"
fi
if grep -q "^confirm_os_window_close" "$conf"; then
  sed -i "s/^confirm_os_window_close.*/confirm_os_window_close 0/" "$conf"
else
  printf "\n# Do not prompt when closing an OS window that has running programs.\nconfirm_os_window_close 0\n" >> "$conf"
fi
if grep -q "^map ctrl+backspace" "$conf"; then
  sed -i "s/^map ctrl+backspace.*/map ctrl+backspace send_key ctrl+w/" "$conf"
else
  printf "\n# Make Ctrl+Backspace use the standard terminal word-rubout key.\nmap ctrl+backspace send_key ctrl+w\n" >> "$conf"
fi
if grep -q "^wayland_titlebar_color" "$conf"; then
  sed -i "s/^wayland_titlebar_color.*/wayland_titlebar_color background/" "$conf"
else
  printf "\n# Match Kitty Wayland decorations to the terminal and keep window controls visible.\nwayland_titlebar_color background\n" >> "$conf"
fi'
}
