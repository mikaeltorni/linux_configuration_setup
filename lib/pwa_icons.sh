#!/usr/bin/env bash
# pwa_icons.sh - Chrome PWA desktop-entry and icon configuration.
#
# Public functions:
#   - configure_pwa_icons(): Refresh installed Chrome PWA icons and launchers.

# configure_pwa_icons — Discover installed Chrome PWAs by scanning their manifest
#   resources, then (re)create a .desktop entry and themed icon symlinks for each
#   so they show correct names/icons. Also ensures a monkeytype.desktop alias for
#   the app-rules@local workspace mapping.
#   Args: none.
#   Returns: 0. Returns early when Chrome's Web Applications directory is absent.
configure_pwa_icons() {
  msg "Setting up Chrome PWA icons and desktop entries"
  local pwa_dir="$TARGET_HOME/.config/google-chrome/Default/Web Applications/Manifest Resources"
  local icon_base="$TARGET_HOME/.local/share/icons"
  local icon_theme="${icon_base}/hicolor"

  if [ ! -d "$pwa_dir" ]; then msg "Chrome Web Applications directory not found; skipping PWA icon setup."; return 0; fi

  if find "$icon_base" -user root -print -quit 2>/dev/null | grep -q .; then
    if [ "$(id -u)" -eq 0 ]; then
      msg "Fixing ownership of $icon_base to $TARGET_USER"
      chown -R "$TARGET_USER:$TARGET_USER" "$icon_base"
    else
      msg "Icon theme contains root-owned files; direct PWA icon paths will be used"
    fi
  fi

  # Discover installed Chrome PWAs by scanning manifest files.
  # Each PWA directory contains a Manifest file with the app name and metadata.
  local -A pwa_names=()       # app_id -> display name
  local -A pwa_icons_found=() # track icon sizes found

  for manifest_dir in "$pwa_dir"/*/; do
    local app_id
    app_id="$(basename "$manifest_dir")"
    local name=""

    if [ -f "${manifest_dir}Manifest" ]; then
      # Extract the "name" field from the JSON manifest.
      name="$(grep -oP '"name"\s*:\s*"[^"]+"' "${manifest_dir}Manifest" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)".*/\1/' || true)"
    fi

    # Chrome may retain icon resources after removing the cached manifest.
    if [ -z "$name" ]; then
      local existing_desktop="$TARGET_HOME/.local/share/applications/chrome-${app_id}-Default.desktop"
      if [ -f "$existing_desktop" ]; then
        name="$(sed -n 's/^Name=//p' "$existing_desktop" | head -1)"
      fi
    fi
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
  local sz
  for sz in "${!pwa_icons_found[@]}"; do
    run_as_target mkdir -p "${icon_theme}/${sz}x${sz}/apps" 2>/dev/null || true
  done

  # Create desktop entries and icon symlinks for each discovered PWA.
  for app_id in "${!pwa_names[@]}"; do
    local name="${pwa_names[$app_id]}"
    local icons_dir="$pwa_dir/$app_id/Icons"
    local desktop_icon="chrome-${app_id}-Default"

    # Icon symlinks.
    if [ -d "$icons_dir" ]; then
      for icon_file in "$icons_dir"/*.png; do
        [ -f "$icon_file" ] || continue
        local size
        size="$(basename "$icon_file" .png)"
        run_as_target ln -sf "$icon_file" "${icon_theme}/${size}x${size}/apps/chrome-${app_id}-Default.png" 2>/dev/null || true
      done

      # An absolute path avoids stale or unwritable icon-theme caches.
      for size in 512 256 192 128 96 64 48 32 16; do
        if [ -f "$icons_dir/$size.png" ]; then
          desktop_icon="$icons_dir/$size.png"
          break
        fi
      done
    fi

    # Always refresh the desktop entry so existing PWAs receive icon fixes.
    local desktop_path="$TARGET_HOME/.local/share/applications/chrome-${app_id}-Default.desktop"
    run_as_target tee "$desktop_path" >/dev/null <<DESKTOP
[Desktop Entry]
Version=1.0
Terminal=false
Type=Application
Name=$name
Exec=/opt/google/chrome/google-chrome --profile-directory=Default --app-id=$app_id
Icon=$desktop_icon
StartupWMClass=crx_${app_id}
DESKTOP
    msg "  $name: refreshed desktop entry"
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
