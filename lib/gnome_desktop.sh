#!/usr/bin/env bash
# gnome_desktop.sh — GNOME desktop configuration helpers
#
# Components:
#   - detect_terminal_desktop(): Detect the first available terminal emulator.
#   - configure_favorites(): Configure GNOME dock favorites.
#   - configure_purple_cross_default_cursor(): Install Purple Cross cursor theme.
#   - configure_terminal_dark_theme(): Set terminal to dark background with light text.
#   - configure_display_refresh(): Configure display refresh rate settings.

detect_terminal_desktop() {
  local candidate
  for candidate in kitty.desktop org.gnome.Terminal.desktop org.gnome.Console.desktop org.gnome.Ptyxis.desktop; do
    if find_desktop_file_path "$candidate" >/dev/null 2>&1; then echo "$candidate"; return 0; fi
  done
  echo "kitty.desktop"
}

first_existing_desktop() { find_desktop_entry "$@" || true; }

configure_favorites() {
  local terminal_desktop
  terminal_desktop="$(detect_terminal_desktop)"
  
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
  
  if [ "${#FAVORITES[@]}" -gt 0 ]; then
    user_gsettings set org.gnome.shell favorite-apps "$(join_as_gsettings_array "${FAVORITES[@]}")"
  else
    msg "No favorites were found to set (no matching desktop files)"
  fi
}

configure_purple_cross_default_cursor() {
  msg "Configuring Purple Cross default cursor"

  local asset_path="$CONFIG_DIR/cursors/purple_cross.cur"
  if [ ! -f "$asset_path" ]; then
    echo "WARNING: Purple Cross cursor asset not found at $asset_path — skipping cursor setup"
    return 0
  fi

  local theme_name="PurpleCrossDefault"
  local theme_dir="$TARGET_HOME/.local/share/icons/$theme_name"
  local cursors_dir="$theme_dir/cursors"
  local default_theme_dir="$TARGET_HOME/.local/share/icons/default"
  local build_dir="$TARGET_HOME/.cache/isc/purple-cross-cursor-build"

  if ! need_cmd icotool || ! need_cmd xcursorgen; then apt_install x11-apps icoutils; fi

  rm -rf /tmp/purple-cross-cursor 2>/dev/null || true
  run_as_target mkdir -p "$TARGET_HOME/.cache/isc"
  rm -rf "$build_dir" 2>/dev/null || true
  install -d -m 0755 "$build_dir" "$cursors_dir" "$default_theme_dir"

  if ! icotool -x -o "$build_dir" "$asset_path" >/dev/null 2>&1; then
    echo "WARNING: icotool failed to extract $asset_path"; return 0
  fi

  local png_path
  png_path="$(find "$build_dir" -maxdepth 1 -type f -name '*.png' -print-quit 2>/dev/null)" || true
  if [ -z "$png_path" ]; then echo "WARNING: no PNG extracted from cursor asset"; return 0; fi
  cp "$png_path" "$build_dir/purple-cross.png"

  cat >"$build_dir/cursor.conf" <<EOF
32 9 9 $build_dir/purple-cross.png
EOF

  if ! xcursorgen "$build_dir/cursor.conf" "$cursors_dir/left_ptr"; then
    echo "WARNING: xcursorgen failed to build Purple Cross cursor"; return 0
  fi

  ln -sf left_ptr "$cursors_dir/default"
  ln -sf left_ptr "$cursors_dir/arrow"
  ln -sf left_ptr "$cursors_dir/top_left_arrow"
  for cursor_name in \
    hand1 \
    hand2 \
    hand \
    pointer \
    pointing_hand \
    e29285e634086352946a0e7090d73106 \
    9d800788f1b08800ae810202380a0822; do
    ln -sf left_ptr "$cursors_dir/$cursor_name"
  done
  for cursor_name in \
    xterm \
    text \
    ibeam \
    vertical-text \
    048008013003cff3c00c801001200000; do
    ln -sf left_ptr "$cursors_dir/$cursor_name"
  done

  cat >"$theme_dir/index.theme" <<EOF
[Icon Theme]
Name=$theme_name
Inherits=Yaru
EOF

  cat >"$default_theme_dir/index.theme" <<EOF
[Icon Theme]
Name=Default
Inherits=$theme_name
EOF

  chown -R "$TARGET_USER:$TARGET_USER" "$build_dir" "$theme_dir" "$default_theme_dir" 2>/dev/null || true
  user_gsettings set org.gnome.desktop.interface cursor-theme "'$theme_name'" || true
  user_gsettings set org.gnome.desktop.interface cursor-size 32 || true
  rm -rf "$build_dir" 2>/dev/null || true
  msg "Purple Cross cursor theme configured"
}

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
  
  local profile_id schema=""
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

configure_pwa_icons() {
  msg "Setting up Chrome PWA icons and desktop entries"
  local pwa_dir="$TARGET_HOME/.config/google-chrome/Default/Web Applications/Manifest Resources"
  local icon_base="$TARGET_HOME/.local/share/icons"
  local icon_theme="${icon_base}/hicolor"
  
  if [ ! -d "$pwa_dir" ]; then msg "Chrome Web Applications directory not found; skipping PWA icon setup."; return 0; fi
  
  local icons_owner
  icons_owner="$(stat -c '%U' "$icon_base" 2>/dev/null || echo unknown)"
  if [ "$icons_owner" = "root" ]; then
    msg "Fixing ownership of $icon_base to $TARGET_USER"
    chown "$TARGET_USER:$TARGET_USER" "$icon_base"
  fi
  
  # PWA definitions — app-id|name|desktop_file|workspace
  local CHROME_PWAS=(
    "chatgpt|ChatGPT|chatgpt.desktop|0"
    "monkeytype|Monkeytype|monkeytype.desktop|7"
  )
  
  local -A needed_sizes=()
  for entry in "${CHROME_PWAS[@]}"; do
    IFS='|' read -r app_id name desktop_file workspace <<< "$entry"
    local icons_dir="$pwa_dir/$app_id/Icons"
    [ -d "$icons_dir" ] || continue
    for icon_file in "$icons_dir"/*.png; do
      [ -f "$icon_file" ] || continue
      needed_sizes["$(basename "$icon_file" .png)"]=1
    done
  done
  
  local dir_list=()
  for sz in "${!needed_sizes[@]}"; do dir_list+=("${sz}x${sz}"); done
  [ ${#dir_list[@]} -gt 0 ] && run_as_target mkdir -p "${icon_theme}/${dir_list[*]}/apps"
  
  for entry in "${CHROME_PWAS[@]}"; do
    IFS='|' read -r app_id name desktop_file workspace <<< "$entry"
    local icons_dir="$pwa_dir/$app_id/Icons"
    [ -d "$icons_dir" ] || { msg "  $name: icon directory not found"; continue; }
    
    for icon_file in "$icons_dir"/*.png; do
      [ -f "$icon_file" ] || continue
      local size="$(basename "$icon_file" .png)"
      run_as_target ln -sf "$icon_file" "${icon_theme}/${size}x${size}/apps/chrome-${app_id}-Default.png"
    done
    
    local desktop_path="$TARGET_HOME/.local/share/applications/chrome-${app_id}-Default.desktop"
    if [ ! -f "$desktop_path" ]; then
      run_as_target tee "$desktop_path" >/dev/null <<DESKTOP
[Desktop Entry]
Version=1.0
Terminal=false
Type=Application
Name=$name
Exec=/opt/google/chrome/google-chrome --profile-directory=Default --app-id=$app_id
Icon=chrome-${app_id}-Default
StartupWMClass=crx_${app_id}
DESKTOP
      msg "  $name: created desktop entry"
    fi
  done
  
  run_as_target gtk-update-icon-cache --force "${icon_theme}" 2>/dev/null || true
}

configure_uv_autostart() {
  msg "Ensuring UV is installed and not autostarting as a GUI app"
  run_as_target bash -lc 'curl -LsSf https://astral.sh/uv/install.sh | sh' || true
  run_as_target rm -f "$TARGET_HOME/.config/autostart/uv-python.desktop" || true
}
