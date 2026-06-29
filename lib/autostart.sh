#!/usr/bin/env bash
# autostart.sh — Autostart application configuration helpers
#
# Components:
#   - configure_autostart_entry(dest_basename, entry_name, exec_cmd, candidates...):
#     Create or copy a .desktop file into ~/.config/autostart/.
#   - configure_spotify_autostart(): Enable Spotify autostart.
#   - configure_gitkraken_autostart(): Enable GitKraken autostart.
#   - configure_autostart_apps(): Create the general autostart launcher + entry.
#   - configure_selected_app_autostart(): Reconcile master-menu [s] selections.
#   - configure_kitty_defaults(): Ensure Kitty config disables the close prompt.
#   - configure_easyeffects_autostart(): Enable EasyEffects autostart + systemd service.
#   - configure_easyeffects_eq(): Install an EasyEffects output EQ preset (user-supplied or bundled).
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

# configure_spotify_autostart — Enable Spotify to start on login.
#   Args: none. Returns: 0.
configure_spotify_autostart() {
  if [ -n "${MANAGED_STARTUP_APPS:-}" ]; then
    log "info" "Spotify autostart delegated to selected_app_autostart"
    return 0
  fi
  msg "Enabling Spotify autostart"

  configure_autostart_entry \
    "spotify" \
    "Spotify" \
    "spotify" \
    spotify.desktop spotify_spotify.desktop
}

# configure_gitkraken_autostart — Enable GitKraken to start on login.
#   Args: none. Returns: 0.
configure_gitkraken_autostart() {
  if [ -n "${MANAGED_STARTUP_APPS:-}" ]; then
    log "info" "GitKraken autostart delegated to selected_app_autostart"
    return 0
  fi
  msg "Enabling GitKraken autostart"

  # Older setup revisions used this alternate basename, causing GNOME to
  # launch GitKraken twice when the canonical entry was later added.
  run_as_target rm -f "$TARGET_HOME/.config/autostart/gitkraken-autostart.desktop"

  configure_autostart_entry \
    "gitkraken" \
    "GitKraken" \
    "gitkraken --no-sandbox" \
    gitkraken.desktop gitkraken_gitkraken.desktop
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
# Only entries recorded in this feature's state file and legacy entries created
# by this setup chain are removed. Unrelated user-managed autostart files remain
# untouched. Missing desktop files are logged and skipped rather than replaced
# with launchers whose Exec command cannot be derived safely.
# Args: none. Returns 0 after reconciliation; filesystem errors propagate.
configure_selected_app_autostart() {
  local selected="${SELECTED_STARTUP_APPS:-}"
  local managed="${MANAGED_STARTUP_APPS:-}"
  local state_dir="$TARGET_HOME/.local/state/linux-configuration-setup"
  local state_file="$state_dir/selected-app-autostart.list"
  local pending_file="$state_file.pending"
  local autostart_dir="$TARGET_HOME/.config/autostart"
  local basename group candidate desktop_src known=0 managed_group
  local -a groups=() candidates=() managed_groups=()

  if [ -z "$managed" ]; then
    log "info" "Selected app autostart skipped: no master startup metadata"
    return 0
  fi

  msg "Configuring selected application startup"
  log "info" "Reconciling master-selected application startup entries"
  run_as_target install -d -m 0755 "$autostart_dir" "$state_dir"

  if [ -f "$state_file" ]; then
    while IFS= read -r basename; do
      [[ "$basename" == *.desktop && "$basename" != */* ]] || continue
      log "debug" "Removing previously managed startup entry: $basename"
      run_as_target rm -f "$autostart_dir/$basename"
    done <"$state_file"
  fi

  # These filenames were created by older setup-chain components before the
  # unified [s] selector existed. Reconcile them once under the new authority.
  run_as_target rm -f \
    "$autostart_dir/spotify.desktop" \
    "$autostart_dir/gitkraken.desktop" \
    "$autostart_dir/gitkraken-autostart.desktop" \
    "$autostart_dir/easyeffects.desktop" \
    "$autostart_dir/albert.desktop"
  # Older EasyEffects setup enabled a user service in addition to its desktop
  # entry. Disable that duplicate login path; the selected desktop launcher is
  # now the single source of startup behavior. Do not stop a running instance.
  run_as_target systemctl --user disable easyeffects.service >/dev/null 2>&1 || true
  run_as_target sh -c ': > "$1"' _ "$pending_file"

  IFS=';' read -r -a groups <<<"$selected"
  IFS=';' read -r -a managed_groups <<<"$managed"
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

# configure_kitty_defaults — Ensure ~/.config/kitty/kitty.conf disables the
#   "Are you sure you want to close this OS window" confirmation prompt by
#   setting `confirm_os_window_close 0`.
#   Idempotent: creates the file if absent, replaces an existing
#   confirm_os_window_close line, or appends the setting — without disturbing
#   any other lines (e.g. allow_remote_control added by other tooling).
configure_kitty_defaults() {
  msg "Configuring Kitty defaults (disable close-window confirmation)"

  run_as_target bash -lc '
set -eu
conf="$HOME/.config/kitty/kitty.conf"
mkdir -p "$(dirname "$conf")"
if [ ! -f "$conf" ]; then
  printf "# Managed by linux_configuration_setup.\nconfirm_os_window_close 0\n" > "$conf"
elif grep -q "^confirm_os_window_close" "$conf"; then
  sed -i "s/^confirm_os_window_close.*/confirm_os_window_close 0/" "$conf"
else
  printf "\n# Do not prompt when closing an OS window that has running programs.\nconfirm_os_window_close 0\n" >> "$conf"
fi'
}

# ── EasyEffects autostart ────────────────────────────────────────────────────

# configure_easyeffects_autostart — Enable EasyEffects autostart + systemd service.
#   Args: none. Returns: 0 (the systemd enable step is best-effort).
configure_easyeffects_autostart() {
  if [ -n "${MANAGED_STARTUP_APPS:-}" ]; then
    log "info" "EasyEffects autostart delegated to selected_app_autostart"
    return 0
  fi
  msg "Ensuring EasyEffects autostarts"

  configure_autostart_entry \
    "easyeffects" \
    "EasyEffects" \
    "easyeffects --gapplication-service" \
    com.github.wwmm.easyeffects.desktop org.gnome.EasyEffects.desktop

  # Best-effort systemd user service if present
  run_as_target systemctl --user enable --now easyeffects.service >/dev/null 2>&1 || true
}

# easyeffects_apo_to_json — Convert an Equalizer APO config into an EasyEffects
#   output preset (JSON) on stdout. EasyEffects 7.x only loads JSON presets from
#   its output/ directory; a raw .apo file dropped there is ignored, so the APO
#   bands must be translated into the native preset structure
#   (verified against EasyEffects 7.1.6: the resulting preset is listed by
#   `easyeffects -p`, loads via `easyeffects -l`, and populates all bands).
#   Each "Filter N: ON PK Fc <f> Hz Gain <g> dB Q <q>" line becomes a Bell band;
#   "Preamp: <x> dB" becomes the equalizer input-gain. The same bands are written
#   to both channels (split-channels=false). Args: $1 = path to the .apo file.
easyeffects_apo_to_json() {
  awk '
    BEGIN { preamp = 0; n = 0 }
    /^[[:space:]]*Preamp:/ {
      for (i = 1; i <= NF; i++) if ($i ~ /^-?[0-9.]+$/) { preamp = $i; break }
      next
    }
    /Filter[[:space:]]+[0-9]+:[[:space:]]+ON[[:space:]]+PK/ {
      freq = q = ""; gain = 0
      for (i = 1; i <= NF; i++) {
        if ($i == "Fc")   freq = $(i+1)
        if ($i == "Gain") gain = $(i+1)
        if ($i == "Q")    q    = $(i+1)
      }
      bandfreq[n] = freq; bandgain[n] = gain; bandq[n] = q; n++
      next
    }
    function emit_channel(    j) {
      for (j = 0; j < n; j++) {
        printf "        \"band%d\": {\n", j
        printf "          \"frequency\": %s,\n", bandfreq[j]+0
        printf "          \"gain\": %s,\n", bandgain[j]+0
        printf "          \"mode\": \"RLC (BT)\",\n"
        printf "          \"mute\": false,\n"
        printf "          \"q\": %s,\n", bandq[j]+0
        printf "          \"slope\": \"x1\",\n"
        printf "          \"solo\": false,\n"
        printf "          \"type\": \"Bell\",\n"
        printf "          \"width\": 4.0\n"
        printf "        }%s\n", (j < n-1 ? "," : "")
      }
    }
    END {
      print  "{"
      print  "  \"output\": {"
      print  "    \"blocklist\": [],"
      print  "    \"plugins_order\": [\"equalizer#0\"],"
      print  "    \"equalizer#0\": {"
      print  "      \"balance\": 0.0,"
      print  "      \"bypass\": false,"
      printf "      \"input-gain\": %s,\n", preamp+0
      print  "      \"mode\": \"IIR\","
      printf "      \"num-bands\": %d,\n", n
      print  "      \"output-gain\": 0.0,"
      print  "      \"pitch-left\": 0.0,"
      print  "      \"pitch-right\": 0.0,"
      print  "      \"split-channels\": false,"
      print  "      \"left\": {"
      emit_channel()
      print  "      },"
      print  "      \"right\": {"
      emit_channel()
      print  "      }"
      print  "    }"
      print  "  }"
      print  "}"
    }
  ' "$1"
}

# configure_easyeffects_eq — Install an EasyEffects output EQ preset.
#   The preset source is resolved with full user customization in mind:
#     1. EASYEFFECTS_EQ_FILE env var (used by non-interactive/master-installer runs).
#     2. An interactive prompt (only when stdin is a TTY) whose default — shown as
#        the pre-typed value — is the bundled preset; the user may type the path
#        to their own EQ file instead.
#     3. The bundled preset at CONFIG_DIR/equalizer.apo.
#   A native EasyEffects JSON preset (.json) is installed verbatim; any other file
#   is treated as Equalizer APO text and converted to JSON, because EasyEffects
#   only loads JSON presets from output/ (a raw .apo there is silently ignored).
#   The preset is named after the source basename and selected as the last-used
#   output preset so EasyEffects applies it automatically on the next launch.
#   Args: none. Returns: 0 (skips cleanly when no EQ file is available).
configure_easyeffects_eq() {
  msg "Installing EasyEffects output EQ preset"

  local default_eq="$CONFIG_DIR/equalizer.apo"
  local eq_src
  eq_src="$(resolve_user_value EASYEFFECTS_EQ_FILE \
    "  EasyEffects EQ file to install: " "$default_eq")"
  [ -z "$eq_src" ] && eq_src="$default_eq"

  # Expand a leading ~ for user-typed paths.
  case "$eq_src" in
    "~/"*) eq_src="$TARGET_HOME/${eq_src#~/}" ;;
    "~")   eq_src="$TARGET_HOME" ;;
  esac

  if [ ! -f "$eq_src" ]; then
    log "warn" "configure_easyeffects_eq: EQ file '$eq_src' not found; falling back to bundled preset"
    eq_src="$default_eq"
  fi
  if [ ! -f "$eq_src" ]; then
    log "warn" "configure_easyeffects_eq: no EQ file available ('$eq_src' missing); skipping"
    return 0
  fi

  local dest_dir="$TARGET_HOME/.config/easyeffects/output"
  run_as_target install -d -m 0755 "$dest_dir"

  # Drop stale .apo files from earlier installs that copied APO directly (ignored
  # by EasyEffects) so the output directory holds only loadable JSON presets.
  run_as_target sh -c 'rm -f "$1"/*.apo 2>/dev/null || true' _ "$dest_dir"

  local preset_name dest
  preset_name="$(basename "$eq_src")"; preset_name="${preset_name%.*}"
  dest="$dest_dir/${preset_name}.json"

  case "$eq_src" in
    *.json)
      run_as_target cp -f "$eq_src" "$dest"
      ;;
    *)
      easyeffects_apo_to_json "$eq_src" | run_as_target tee "$dest" >/dev/null
      ;;
  esac
  run_as_target chmod 0644 "$dest"
  msg "  Installed EQ preset: $dest"

  # Select the preset so EasyEffects applies it automatically when it starts.
  user_gsettings_set_if_key_exists com.github.wwmm.easyeffects \
    last-used-output-preset "'${preset_name}'"
}
