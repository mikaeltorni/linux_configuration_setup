#!/usr/bin/env bash
# cursor_theme.sh - Purple Cross cursor theme configuration.
#
# Public functions:
#   - link_purple_cross_cursor_aliases(): Link all cursor roles to Purple Cross.
#   - write_purple_cross_cursor_index(): Write cursor theme inheritance metadata.
#   - configure_purple_cross_default_cursor(): Install the Purple Cross theme.

PURPLE_CROSS_CURSOR_THEME_NAME="PurpleCrossDefault"
PURPLE_CROSS_CURSOR_SIZE=48

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

# link_purple_cross_cursor_aliases - Symlink every cursor role name to the built
#   left_ptr cursor so all roles render as the Purple Cross.
#   Args: $1 - cursors directory to populate. Returns: 0.
link_purple_cross_cursor_aliases() {
  local cursors_dir="$1"
  log "debug" "link_purple_cross_cursor_aliases: linking ${#PURPLE_CROSS_CURSOR_ALIASES[@]} roles in $cursors_dir"
  local cursor_name
  for cursor_name in "${PURPLE_CROSS_CURSOR_ALIASES[@]}"; do
    run_as_target ln -sf left_ptr "$cursors_dir/$cursor_name"
  done
}

# write_purple_cross_cursor_index - Write an index.theme file describing a
#   cursor theme's display name and the theme it inherits from.
#   Args: $1 - index.theme path; $2 - theme name; $3 - inherited theme name.
#   Returns: the exit status of the underlying write.
write_purple_cross_cursor_index() {
  local index_path="$1"
  local name="$2"
  local inherits="$3"

  log "debug" "write_purple_cross_cursor_index: $index_path (Name=$name, Inherits=$inherits)"
  run_as_target tee "$index_path" >/dev/null <<EOF
[Icon Theme]
Name=$name
Inherits=$inherits
EOF
}

# configure_purple_cross_default_cursor - Build and install the Purple Cross
#   cursor theme from the bundled .cur asset, alias every cursor role to it, and
#   set it as the user's cursor theme. Installs xcursorgen (x11-apps) on demand.
#   Args: none.
#   Returns: 0. Logs a warning and returns early if the asset or required tools
#     (python3-pil) are missing, so a clean install never aborts here.
configure_purple_cross_default_cursor() {
  msg "Configuring Purple Cross default cursor"

  local asset_path="$CONFIG_DIR/cursors/purple_cross.cur"
  if [ ! -f "$asset_path" ]; then
    log "warn" "Purple Cross cursor asset not found at $asset_path — skipping cursor setup"
    return 0
  fi

  local theme_name="$PURPLE_CROSS_CURSOR_THEME_NAME"
  local theme_dir="$TARGET_HOME/.local/share/icons/$theme_name"
  local cursors_dir="$theme_dir/cursors"
  local default_theme_dir="$TARGET_HOME/.local/share/icons/default"
  local legacy_default_theme_dir="$TARGET_HOME/.icons/default"
  local legacy_theme_dir="$TARGET_HOME/.icons/$theme_name"
  local legacy_theme_target="../.local/share/icons/$theme_name"
  local build_dir="$TARGET_HOME/.cache/isc/purple-cross-cursor-build"
  local python_bin

  if ! need_cmd xcursorgen; then apt_install x11-apps; fi
  if ! python_bin="$(find_python_with_module PIL)"; then
    log "warn" "python3-pil is required to build the Purple Cross cursor — skipping cursor setup"
    return 0
  fi

  run_as_target mkdir -p "$TARGET_HOME/.cache/isc"
  rm -rf "$build_dir" 2>/dev/null || true
  run_as_target mkdir -p "$build_dir" "$cursors_dir" "$default_theme_dir" "$legacy_default_theme_dir"

  local png_path="$build_dir/purple-cross.png"
  local hotspot
  log "debug" "configure_purple_cross_default_cursor: using $python_bin for cursor extraction"
  if ! hotspot="$(run_as_target "$python_bin" "$SCRIPT_DIR/scripts/extract_cursor.py" \
    "$asset_path" "$png_path" "$PURPLE_CROSS_CURSOR_SIZE")"; then
    log "warn" "failed to extract Purple Cross cursor asset — skipping cursor setup"
    return 0
  fi

  local hotspot_x hotspot_y
  read -r hotspot_x hotspot_y <<<"$hotspot"
  run_as_target tee "$build_dir/cursor.conf" >/dev/null <<EOF
$PURPLE_CROSS_CURSOR_SIZE $hotspot_x $hotspot_y $png_path
EOF

  if ! run_as_target xcursorgen "$build_dir/cursor.conf" "$cursors_dir/left_ptr"; then
    log "warn" "xcursorgen failed to build Purple Cross cursor — skipping cursor setup"; return 0
  fi

  link_purple_cross_cursor_aliases "$cursors_dir"
  write_purple_cross_cursor_index "$theme_dir/index.theme" "$theme_name" "Yaru"
  write_purple_cross_cursor_index "$default_theme_dir/index.theme" "Default" "$theme_name"
  write_purple_cross_cursor_index "$legacy_default_theme_dir/index.theme" "Default" "$theme_name"

  log "debug" "configure_purple_cross_default_cursor: linking $legacy_theme_dir to $legacy_theme_target for Xcursor clients"
  rm -rf "$legacy_theme_dir" 2>/dev/null || true
  if ! run_as_target ln -s "$legacy_theme_target" "$legacy_theme_dir"; then
    log "warn" "failed to expose Purple Cross cursor theme at $legacy_theme_dir"
  fi

  chown -R "$TARGET_USER:$TARGET_USER" "$build_dir" "$theme_dir" "$default_theme_dir" 2>/dev/null || true
  chown -R "$TARGET_USER:$TARGET_USER" "$legacy_default_theme_dir" 2>/dev/null || true
  chown -h "$TARGET_USER:$TARGET_USER" "$legacy_theme_dir" 2>/dev/null || true
  user_gsettings set org.gnome.desktop.interface cursor-theme "'$theme_name'" || true
  user_gsettings set org.gnome.desktop.interface cursor-size "$PURPLE_CROSS_CURSOR_SIZE" || true
  run_as_target rm -rf "$build_dir" 2>/dev/null || true
  msg "Purple Cross cursor theme configured"
}
