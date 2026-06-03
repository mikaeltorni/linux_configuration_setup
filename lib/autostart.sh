#!/usr/bin/env bash
# autostart.sh — Autostart application configuration helpers
#
# Components:
#   - configure_autostart_entry(dest_basename, entry_name, exec_cmd, candidates...):
#     Create or copy a .desktop file into ~/.config/autostart/.
#   - configure_spotify_autostart(): Enable Spotify autostart.
#   - configure_gitkraken_autostart(): Enable GitKraken autostart.
#   - configure_autostart_apps(): Create autostart_apps.sh launcher + autostart entry.
#   - configure_easyeffects_autostart(): Enable EasyEffects autostart + systemd service.
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
configure_autostart_entry() {
  local dest_basename="$1"
  local entry_name="$2"
  local exec_cmd="$3"
  shift 3
  local candidates=("$@")
  local desktop_src=""

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
configure_spotify_autostart() {
  msg "Enabling Spotify autostart"

  configure_autostart_entry \
    "spotify" \
    "Spotify" \
    "spotify" \
    spotify.desktop spotify_spotify.desktop
}

# configure_gitkraken_autostart — Enable GitKraken to start on login.
configure_gitkraken_autostart() {
  msg "Enabling GitKraken autostart"

  configure_autostart_entry \
    "gitkraken" \
    "GitKraken" \
    "gitkraken --no-sandbox" \
    gitkraken.desktop gitkraken_gitkraken.desktop
}

# configure_autostart_apps — Create a launcher script for GitKraken and Kitty.
configure_autostart_apps() {
   msg "Autostarting GitKraken and Kitty"
  run_as_target install -d -m 0755 "$TARGET_HOME/.local/bin"
  run_as_target tee "$TARGET_HOME/.local/bin/autostart_apps.sh" >/dev/null << 'EOF'
#!/usr/bin/env bash
set -u

launch_if_exists() {
  local cmd="$1"
  # Shift first argument; safe even if empty
    shift
  if command -v "$cmd" >/dev/null 2>&1; then
    "$cmd" "$@" &
  fi
}

launch_if_exists gitkraken
launch_if_exists kitty

exit 0
EOF
  run_as_target chmod +x "$TARGET_HOME/.local/bin/autostart_apps.sh"

  configure_autostart_entry \
    "autostart_apps" \
    "autostart apps" \
    "/bin/bash -lc \"$HOME/.local/bin/autostart_apps.sh\""
}

# ── EasyEffects autostart ────────────────────────────────────────────────────

# configure_easyeffects_autostart — Enable EasyEffects autostart + systemd service.
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
