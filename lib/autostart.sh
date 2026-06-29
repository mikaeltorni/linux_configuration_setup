#!/usr/bin/env bash
# autostart.sh — Autostart application configuration helpers
#
# Components:
#   - configure_autostart_entry(dest_basename, entry_name, exec_cmd, candidates...):
#     Create or copy a .desktop file into ~/.config/autostart/.
#   - configure_spotify_autostart(): Enable Spotify autostart.
#   - configure_gitkraken_autostart(): Enable GitKraken autostart.
#   - configure_autostart_apps(): Create the Kitty launcher + autostart entry.
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

# configure_autostart_apps — Create the Kitty launcher script and its autostart
#   entry so Kitty opens on login.
#   Args: none. Returns: 0.
configure_autostart_apps() {
  msg "Autostarting Kitty"
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

launch_if_exists kitty

exit 0
EOF
  run_as_target chmod +x "$TARGET_HOME/.local/bin/autostart_apps.sh"

  configure_autostart_entry \
    "autostart_apps" \
    "autostart apps" \
    "/bin/bash -lc \"$TARGET_HOME/.local/bin/autostart_apps.sh\""
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
#   The resolved file is copied into ~/.config/easyeffects/output/ preserving its
#   basename. JSON presets are picked up directly by EasyEffects; APO files (the
#   bundled default) can be imported from there via the equalizer's APO import.
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
  local dest="$dest_dir/$(basename "$eq_src")"
  run_as_target cp -f "$eq_src" "$dest"
  run_as_target chmod 0644 "$dest"
  msg "  Installed EQ preset: $dest"
}
