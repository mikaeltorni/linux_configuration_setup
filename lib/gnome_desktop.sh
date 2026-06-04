#!/usr/bin/env bash
# gnome_desktop.sh — GNOME desktop configuration helpers
#
# Components:
#   - detect_terminal_desktop(): Detect the first available terminal emulator.
#   - configure_favorites(): Configure GNOME dock favorites.
#   - purple_cross_cursor_aliases(): Print cursor role names forced to Purple Cross.
#   - link_purple_cross_cursor_aliases(): Link all cursor roles to the Purple Cross cursor.
#   - write_purple_cross_cursor_index(): Write cursor theme inheritance metadata.
#   - configure_purple_cross_default_cursor(): Install Purple Cross cursor theme.
#   - configure_terminal_dark_theme(): Set terminal to dark background with light text.
#   - configure_display_refresh(): Configure display refresh rate settings.

PURPLE_CROSS_CURSOR_THEME_NAME="PurpleCrossDefault"
PURPLE_CROSS_CURSOR_SIZE=32

PURPLE_CROSS_CURSOR_ALIASES=(
  00000000000000020006000e7e9ffc3f
  00008160000006810000408080010102
  028006030e0e7ebffc7f7070c0600140
  03b6e0fcb3499374a867c041f52298f0
  048008013003cff3c00c801001200000
  08e8e1c95fe2fc01f976f1e063a24ccd
  1081e37283d90000800003c07f3ef6bf
  14fef782d02440884392942c11205230
  2870a09082c103050810ffdffffe0204
  3085a0e285430894940527032f8b26df
  3ecb610c1bf2410f44200f48c40d3599
  4498f0e0c1937ffe01fd06f973665830
  5c6cd98b3f3ebcb1f9c7f1c204630408
  6407b0e94181790501fd1e167b474872
  640fb0e74195791501fd1ed57b41487f
  9081237383d90e509aa00f00170e968f
  9d800788f1b08800ae810202380a0822
  X_cursor
  a2a266d0498c3104214a47bd64ab0fc8
  alias
  all-scroll
  arrow
  base_arrow_down
  base_arrow_up
  based_arrow_down
  based_arrow_up
  bd_double_arrow
  boat
  bottom_left_corner
  bottom_right_corner
  bottom_side
  bottom_tee
  c7088f0f3e6c8088236ef8e1e3e70000
  cell
  center_ptr
  circle
  closedhand
  col-resize
  color-picker
  context-menu
  copy
  cross
  cross_reverse
  crossed_circle
  crosshair
  d9ce0ab605698f320427677b458ad60b
  default
  diamond_cross
  dnd-ask
  dnd-copy
  dnd-link
  dnd-move
  dnd-no-drop
  dnd-none
  dot
  dot_box_mask
  dotbox
  double_arrow
  down-arrow
  draft
  draft_large
  draft_small
  draped_box
  e-resize
  e29285e634086352946a0e7090d73106
  ew-resize
  exchange
  fcf1c3c7cd4491d801f1e1c78f100000
  fcf21c00b30f7e3f83fe0dfd12e71cff
  fd_double_arrow
  fleur
  forbidden
  grab
  grabbing
  gumby
  h_double_arrow
  half-busy
  hand
  hand1
  hand2
  help
  ibeam
  icon
  left-arrow
  left_ptr_help
  left_ptr_watch
  left_side
  left_tee
  link
  ll_angle
  lr_angle
  move
  n-resize
  ne-resize
  nesw-resize
  no-drop
  not-allowed
  ns-resize
  nw-resize
  nwse-resize
  openhand
  pencil
  pirate
  plus
  pointer
  pointer-move
  pointing_hand
  progress
  question_arrow
  right-arrow
  right_ptr
  right_side
  right_tee
  row-resize
  s-resize
  sb_down_arrow
  sb_h_double_arrow
  sb_left_arrow
  sb_right_arrow
  sb_up_arrow
  sb_v_double_arrow
  se-resize
  size-bdiag
  size-fdiag
  size-hor
  size-ver
  size_all
  size_bdiag
  size_fdiag
  size_hor
  size_ver
  split_h
  split_v
  sw-resize
  target
  tcross
  text
  top_left_arrow
  top_left_corner
  top_right_corner
  top_side
  top_tee
  ul_angle
  up-arrow
  ur_angle
  v_double_arrow
  vertical-text
  w-resize
  wait
  watch
  wayland-cursor
  wayland_cursor
  whats_this
  x-cursor
  xterm
  zoom-in
  zoom-out
)

purple_cross_cursor_aliases() {
  printf '%s\n' "${PURPLE_CROSS_CURSOR_ALIASES[@]}"
}

link_purple_cross_cursor_aliases() {
  local cursors_dir="$1"
  local cursor_name
  for cursor_name in "${PURPLE_CROSS_CURSOR_ALIASES[@]}"; do
    run_as_target ln -sf left_ptr "$cursors_dir/$cursor_name"
  done
}

write_purple_cross_cursor_index() {
  local index_path="$1"
  local name="$2"
  local inherits="$3"

  run_as_target tee "$index_path" >/dev/null <<EOF
[Icon Theme]
Name=$name
Inherits=$inherits
EOF
}

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

  local theme_name="$PURPLE_CROSS_CURSOR_THEME_NAME"
  local theme_dir="$TARGET_HOME/.local/share/icons/$theme_name"
  local cursors_dir="$theme_dir/cursors"
  local default_theme_dir="$TARGET_HOME/.local/share/icons/default"
  local legacy_default_theme_dir="$TARGET_HOME/.icons/default"
  local build_dir="$TARGET_HOME/.cache/isc/purple-cross-cursor-build"

  if ! need_cmd icotool || ! need_cmd xcursorgen; then apt_install x11-apps icoutils; fi

  rm -rf /tmp/purple-cross-cursor 2>/dev/null || true
  run_as_target mkdir -p "$TARGET_HOME/.cache/isc"
  rm -rf "$build_dir" 2>/dev/null || true
  run_as_target mkdir -p "$build_dir" "$cursors_dir" "$default_theme_dir" "$legacy_default_theme_dir"

  if ! run_as_target icotool -x -o "$build_dir" "$asset_path" >/dev/null 2>&1; then
    echo "WARNING: icotool failed to extract $asset_path"; return 0
  fi

  local png_path
  png_path="$(find "$build_dir" -maxdepth 1 -type f -name '*.png' -print -quit 2>/dev/null)" || true
  if [ -z "$png_path" ]; then echo "WARNING: no PNG extracted from cursor asset"; return 0; fi
  run_as_target cp "$png_path" "$build_dir/purple-cross.png"

  run_as_target tee "$build_dir/cursor.conf" >/dev/null <<EOF
$PURPLE_CROSS_CURSOR_SIZE 9 9 $build_dir/purple-cross.png
EOF

  if ! run_as_target xcursorgen "$build_dir/cursor.conf" "$cursors_dir/left_ptr"; then
    echo "WARNING: xcursorgen failed to build Purple Cross cursor"; return 0
  fi

  link_purple_cross_cursor_aliases "$cursors_dir"
  write_purple_cross_cursor_index "$theme_dir/index.theme" "$theme_name" "Yaru"
  write_purple_cross_cursor_index "$default_theme_dir/index.theme" "Default" "$theme_name"
  write_purple_cross_cursor_index "$legacy_default_theme_dir/index.theme" "Default" "$theme_name"

  chown -R "$TARGET_USER:$TARGET_USER" "$build_dir" "$theme_dir" "$default_theme_dir" 2>/dev/null || true
  chown -R "$TARGET_USER:$TARGET_USER" "$legacy_default_theme_dir" 2>/dev/null || true
  user_gsettings set org.gnome.desktop.interface cursor-theme "'$theme_name'" || true
  user_gsettings set org.gnome.desktop.interface cursor-size "$PURPLE_CROSS_CURSOR_SIZE" || true
  run_as_target rm -rf "$build_dir" 2>/dev/null || true
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
  
  # Discover installed Chrome PWAs by scanning manifest files.
  # Each PWA directory contains a Manifest file with the app name and metadata.
  local -A pwa_names=()       # app_id -> display name
  local -A pwa_icons_found=() # track icon sizes found
  
  for manifest_dir in "$pwa_dir"/*/; do
    [ -f "${manifest_dir}Manifest" ] || continue
    local app_id="$(basename "$manifest_dir")"
    local name=""
    # Extract the "name" field from the JSON manifest.
    name="$(grep -oP '"name"\s*:\s*"[^"]+"' "${manifest_dir}Manifest" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)".*/\1/' || true)"
    [ -z "$name" ] && continue
    
    pwa_names["$app_id"]="$name"
    
    # Collect icon sizes.
    local icons_dir="${manifest_dir}Icons"
    if [ -d "$icons_dir" ]; then
      for icon_file in "$icons_dir"/*.png; do
        [ -f "$icon_file" ] || continue
        pwa_icons_found["$(basename "$icon_file" .png)"]=1
      done
    fi
  done
  
  # Create icon directories for all found sizes.
  local dir_list=()
  for sz in "${!pwa_icons_found[@]}"; do dir_list+=("${sz}x${sz}"); done
  [ ${#dir_list[@]} -gt 0 ] && run_as_target mkdir -p "${icon_theme}/${dir_list[*]}/apps"
  
  # Create desktop entries and icon symlinks for each discovered PWA.
  local CHROME_PWAS=(chatgpt monkeytype)  # logical names for workspace rules
  
  for app_id in "${!pwa_names[@]}"; do
    local name="${pwa_names[$app_id]}"
    
    # Icon symlinks.
    local icons_dir="$pwa_dir/$app_id/Icons"
    if [ -d "$icons_dir" ]; then
      for icon_file in "$icons_dir"/*.png; do
        [ -f "$icon_file" ] || continue
        local size="$(basename "$icon_file" .png)"
        run_as_target ln -sf "$icon_file" "${icon_theme}/${size}x${size}/apps/chrome-${app_id}-Default.png"
      done
    fi
    
    # Desktop entry.
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
  
  # Create a "monkeytype.desktop" symlink so the app-rules@local extension
  # can match windows to workspace 7 by that name.
  local mt_desktop="$TARGET_HOME/.local/share/applications/monkeytype.desktop"
  if [ -f "$mt_desktop" ]; then
    : # already exists (created by configure_monkeytype_autostart or manually)
  else
    # Try to find the actual Chrome PWA desktop file for monkeytype.
    local mt_real=""
    for f in "$TARGET_HOME/.local/share/applications"/chrome-*-Default.desktop; do
      [ -f "$f" ] || continue
      if grep -qi "monkeytype" "$f" 2>/dev/null; then
        mt_real="$f"
        break
      fi
    done
    if [ -n "$mt_real" ]; then
      run_as_target ln -sf "$(basename "$mt_real")" "$mt_desktop"
      msg "  Created symlink: monkeytype.desktop → $(basename "$mt_real")"
    fi
  fi

  run_as_target gtk-update-icon-cache --force "${icon_theme}" 2>/dev/null || true
}

configure_uv_autostart() {
  msg "Ensuring UV is installed and not autostarting as a GUI app"
  run_as_target bash -lc 'curl -LsSf https://astral.sh/uv/install.sh | sh' || true
  run_as_target rm -f "$TARGET_HOME/.config/autostart/uv-python.desktop" || true
}

# ── GNOME Shell extensions ───────────────────────────────────────────────────

# configure_app_rules_extension — Deploy/update the app-rules@local extension.
#   Copies the extension from CONFIG_DIR to ~/.local/share/gnome-shell/extensions/
#   and ensures proper ownership. The user must log out/in for changes to take effect.
configure_app_rules_extension() {
  msg "Deploying app-rules@local GNOME Shell extension"

  local ext_src="$CONFIG_DIR/gnome-extensions/app-rules@local"
  local ext_dst="$TARGET_HOME/.local/share/gnome-shell/extensions/app-rules@local"

  if [ ! -d "$ext_src" ]; then
    msg "  app-rules source not found at $ext_src; skipping."
    return 0
  fi

  run_as_target mkdir -p "$(dirname "$ext_dst")"
  
  # Copy extension files (preserve the directory structure)
  for f in "$ext_src"/*; do
    [ -f "$f" ] || continue
    run_as_target cp "$f" "$ext_dst/$(basename "$f")"
  done
  
  msg "  Extension deployed to $ext_dst"
  msg "  NOTE: Log out and back in for GNOME Shell extension changes to take effect."
}
