#!/usr/bin/env bash
# gnome_desktop.sh — GNOME desktop configuration helpers
#
# Components:
#   - detect_terminal_desktop(): Detect the first available terminal emulator.
#   - first_existing_desktop(): Return the first existing .desktop from candidates.
#   - configure_favorites(): Configure GNOME dock favorites.
#   - configure_terminal_dark_theme(): Set terminal to dark background with light text.
#   - configure_display_refresh(): Configure display refresh rate settings.
#   - configure_uv_autostart(): Install the UV package manager (no GUI autostart).
#   - configure_app_rules_extension(): Deploy the app-rules@local GNOME extension.

# detect_terminal_desktop — Detect the preferred installed terminal emulator.
#   Args: none.
#   Returns: 0 and prints the matching .desktop id, or "kitty.desktop" as a
#     fallback when none are installed.
detect_terminal_desktop() {
  log "debug" "detect_terminal_desktop: probing installed terminal emulators"
  local candidate
  for candidate in kitty.desktop org.gnome.Terminal.desktop org.gnome.Console.desktop org.gnome.Ptyxis.desktop; do
    if find_desktop_file_path "$candidate" >/dev/null 2>&1; then echo "$candidate"; return 0; fi
  done
  echo "kitty.desktop"
}

# first_existing_desktop — Print the first existing .desktop entry from the given
#   candidates, or nothing if none exist (never fails the caller).
#   Args: $@ — candidate desktop ids. Returns: 0.
first_existing_desktop() { log "debug" "first_existing_desktop: $*"; find_desktop_entry "$@" || true; }

# configure_favorites — Build the GNOME dash favorite-apps list from the apps
#   that are actually installed and apply it.
#   Args: none. Returns: 0.
configure_favorites() {
  local terminal_desktop
  terminal_desktop="$(detect_terminal_desktop)"
  
  # add_favorite — Append the first installed candidate to the FAVORITES list.
  #   Args: $@ — candidate desktop ids. Returns: 0.
  add_favorite() {
    local entry
    entry="$(first_existing_desktop "$@")"
    [ -n "${entry:-}" ] && FAVORITES+=("$entry")
  }
  
  msg "Setting favorites on the taskbar"
  local FAVORITES=()
  add_favorite cursor.desktop
  add_favorite com.obsproject.Studio.desktop
  add_favorite discord.desktop discord_discord.desktop
  add_favorite google-chrome.desktop com.google.Chrome.desktop
  add_favorite org.gnome.Nautilus.desktop
  add_favorite org.gnome.Settings.desktop gnome-control-center.desktop
  add_favorite "$terminal_desktop" org.gnome.Console.desktop org.gnome.Terminal.desktop org.gnome.Ptyxis.desktop kitty.desktop
  add_favorite org.gnome.SystemMonitor.desktop
  add_favorite com.github.wwmm.easyeffects.desktop
  add_favorite albert.desktop
  add_favorite org.gnome.Notes.desktop org.gnome.TextEditor.desktop
  add_favorite spotify.desktop spotify_spotify.desktop
  add_favorite update-manager.desktop
  add_favorite gitkraken.desktop gitkraken_gitkraken.desktop
  add_favorite lm-studio.desktop
  add_favorite nvidia-settings.desktop
  add_favorite virt-manager.desktop
  
  if [ "${#FAVORITES[@]}" -gt 0 ]; then
    user_gsettings set org.gnome.shell favorite-apps "$(join_as_gsettings_array "${FAVORITES[@]}")"
  else
    msg "No favorites were found to set (no matching desktop files)"
  fi
}

# configure_terminal_dark_theme — Force a dark background with light text across
#   the installed terminals (GNOME Console, Ptyxis, and legacy GNOME Terminal),
#   touching only the keys/profiles that exist on this machine.
#   Args: none. Returns: 0.
configure_terminal_dark_theme() {
  msg "Setting terminal to dark background with light text"
  
  user_gsettings_set_if_key_exists org.gnome.Console theme "'dark'"
  user_gsettings_set_if_key_exists org.gnome.Ptyxis interface-style "'dark'"
  
  local ptyxis_profile=""
  if gsettings_key_exists org.gnome.Ptyxis default-profile-uuid; then
    ptyxis_profile="$(user_gsettings get org.gnome.Ptyxis default-profile-uuid 2>/dev/null || true)"
  fi
  ptyxis_profile="${ptyxis_profile//\'/}"
  if [ -n "$ptyxis_profile" ]; then
    for schema in "org.gnome.Ptyxis.Profile:/org/gnome/ptyxis/profiles/${ptyxis_profile}/" \
                  "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/${ptyxis_profile}/"; do
      if gsettings_key_exists "$schema" bold-is-bright; then
        user_gsettings set "$schema" bold-is-bright true || true
      fi
      if gsettings_key_exists "$schema" palette; then
        user_gsettings set "$schema" palette "'One Half Black'" || \
          user_gsettings set "$schema" palette "'linux'" || \
          user_gsettings set "$schema" palette "'gnome-high-contrast'" || true
      fi
    done
  fi
  
  local profile_id="" schema=""
  if gsettings_key_exists org.gnome.Terminal.ProfilesList default; then
    profile_id="$(user_gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null || true)"
  fi
  profile_id="${profile_id//\'/}"
  if [ -n "$profile_id" ]; then
    schema="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${profile_id}/"
    user_gsettings_set_if_key_exists "$schema" use-theme-colors false
    user_gsettings_set_if_key_exists "$schema" background-color "'rgb(0,0,0)'"
    user_gsettings_set_if_key_exists "$schema" foreground-color "'rgb(255,255,255)'"
    user_gsettings_set_if_key_exists "$schema" bold-color-same-as-fg true
  fi
}

# configure_display_refresh — Maximise the display refresh rate. On Xorg it sets
#   each connected monitor to its highest mode via xrandr; on Wayland it enables
#   mutter's variable-refresh-rate experimental feature.
#   Args: none. Returns: 0.
configure_display_refresh() {
  if [[ "$SESSION_TYPE" =~ ^(x11|xorg)$ ]]; then
    msg "Xorg: setting MAX refresh per monitor via xrandr (best effort)"
    apt_install x11-xserver-utils
    run_as_target bash -lc '
      if command -v xrandr >/dev/null; then
        while read -r out _ status _; do
          [ "$status" = "connected" ] || continue
          best_line=$(xrandr --query | awk -v o="$out" "/^\"?\"?\"?\"?$/ {next} \$0 ~ (\"^\" o \" \") {inblk=1; next} inblk && /^[A-Za-z0-9-]+ connected/ {inblk=0} inblk && /^[[:space:]]*[0-9]+x[0-9]+/ {mode=\$1; for(i=2;i<=NF;i++){if(index(\$i,\"+\")||index(\$i,\"*\")||\$i ~ /^[0-9.]+$/){gsub(/[*+]/, \"\", \$i); rate=\$i; printf(\"%s %s\\n\", mode, rate)}}}" | sort -k2,2nr -k1,1 | head -n1)
          mode=${best_line% *}; rate=${best_line##* }
          [ -n "$mode" ] && [ -n "$rate" ] && xrandr --output "$out" --mode "$mode" --rate "$rate" || true
        done < <(xrandr --query | awk "/ connected/{print \$1, \$2}")
      fi'
  else
    msg "Wayland: enabling VRR experimental feature (if supported)"
    user_gsettings set org.gnome.mutter experimental-features "['variable-refresh-rate']"
  fi
}

# configure_uv_autostart — Install the UV Python package manager for the target
#   user and remove any stale autostart entry so UV never launches as a GUI app.
#   Args: none. Returns: 0 (installation is best-effort).
configure_uv_autostart() {
  msg "Ensuring UV is installed and not autostarting as a GUI app"
  run_as_target bash -lc 'curl -LsSf https://astral.sh/uv/install.sh | sh' || true
  run_as_target rm -f "$TARGET_HOME/.config/autostart/uv-python.desktop" || true
}

# ── GNOME Shell extensions ───────────────────────────────────────────────────

# configure_app_rules_extension — Deploy/update the app-rules@local extension.
#   Copies the extension from CONFIG_DIR to ~/.local/share/gnome-shell/extensions/
#   and ensures proper ownership. The user must log out/in for changes to take effect.
#   Args: none. Returns: 0 (skips cleanly if the extension source is missing).
configure_app_rules_extension() {
  msg "Deploying app-rules@local GNOME Shell extension"

  local ext_src="$CONFIG_DIR/gnome-extensions/app-rules@local"
  local ext_dst="$TARGET_HOME/.local/share/gnome-shell/extensions/app-rules@local"

  if [ ! -d "$ext_src" ]; then
    msg "  app-rules source not found at $ext_src; skipping."
    return 0
  fi

  run_as_target install -d -m 0755 "$(dirname "$ext_dst")" "$ext_dst"
  
  # Copy extension files (preserve the directory structure)
  for f in "$ext_src"/*; do
    [ -f "$f" ] || continue
    log "debug" "configure_app_rules_extension: deploying $(basename "$f")"
    run_as_target install -m 0644 "$f" "$ext_dst/$(basename "$f")"
  done
  
  msg "  Extension deployed to $ext_dst"
  msg "  NOTE: Log out and back in for GNOME Shell extension changes to take effect."
}
