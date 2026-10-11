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
#   - configure_app_rules_extension(): Retired compatibility entrypoint; owner is linux_workspaces_setup.

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

# favorite_app_candidate_groups — Emit the default dock favourite candidate
#   groups owned by linux_installations_setup. Each printed line is one app's
#   comma-separated .desktop id alternatives, in installations_setup's declared
#   order. linux_installations_setup is the single source of truth for which
#   installed apps become dock favourites; this reuses its
#   `--list-favorite-components` contract so a standalone configuration run
#   reproduces the exact list the master installer forwards as
#   SELECTED_FAVORITE_APPS — no duplicated app list is maintained here.
#   Args: none. Output: newline-separated candidate groups (empty when the
#   installations_setup checkout cannot be located).
favorite_app_candidate_groups() {
  local lib_dir install_sh
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for install_sh in "${LIS_INSTALL_SH:-}" \
                    "$lib_dir/../../linux_installations_setup/install.sh" \
                    "$HOME/projects/linux_installations_setup/install.sh"; do
    [ -n "$install_sh" ] && [ -f "$install_sh" ] || continue
    log "debug" "favorite_app_candidate_groups: sourcing $install_sh --list-favorite-components"
    bash "$install_sh" --list-favorite-components 2>/dev/null \
      | awk -F'\t' 'NF>=2 && $2!=""{print $2}'
    return 0
  done
  log "debug" "favorite_app_candidate_groups: no linux_installations_setup checkout found"
  return 0
}

# favorite_app_managed_desktop_ids — Emit every installer-managed favourite
#   .desktop id published by linux_installations_setup, including alternative
#   filenames within each candidate group. Used to reconcile dock entries on
#   standalone and config_active runs when the master installer did not export
#   MANAGED_FAVORITE_APPS.
#   Args: none. Output: comma-separated .desktop ids (empty when unavailable).
favorite_app_managed_desktop_ids() {
  local group entry out=""
  local -a candidates=()
  while IFS= read -r group; do
    [ -n "$group" ] || continue
    candidates=()
    IFS=', ' read -r -a candidates <<<"$group"
    for entry in "${candidates[@]}"; do
      [[ -n "$entry" ]] || continue
      out="${out:+$out,}$entry"
    done
  done < <(favorite_app_candidate_groups)
  printf '%s' "$out"
}

# configure_favorites — Build the GNOME dash favorite-apps list from the apps
#   that are actually installed and apply it. When MANAGED_FAVORITE_APPS is set
#   (master handoff), only installer-managed .desktop ids are reconciled; other
#   dock favourites such as user-pinned PWAs are preserved. The removed default
#   System Monitor pin is also reconciled during upgrades.
# Parameters: none.
# Returns: the status of applying the favorites list.
configure_favorites() {
  printf 'parameters=none\n'
  local selected_program_favorites="${SELECTED_FAVORITE_APPS:-}"
  local managed_program_favorites="${MANAGED_FAVORITE_APPS:-}"
  local managed_reconcile_ids="$managed_program_favorites"
  local favorites_manual_override=0
  [[ -n "${FAVORITES_APPS:-}" ]] && favorites_manual_override=1
  if [ -z "$managed_reconcile_ids" ]; then
    managed_reconcile_ids="$(favorite_app_managed_desktop_ids)"
    [ -n "$managed_reconcile_ids" ] && \
      log "info" "Derived managed dock favourites from installations_setup metadata"
  fi
  # Treat the removed baseline favorite as managed so upgrades unpin its stale
  # entry while preserving unrelated user favorites.
  managed_reconcile_ids="${managed_reconcile_ids:+$managed_reconcile_ids,}org.gnome.SystemMonitor.desktop"

  # add_favorite — Append the first installed candidate to the FAVORITES list.
  #   Args: $@ — candidate desktop ids. Returns: 0.
  add_favorite() {
    local entry
    entry="$(first_existing_desktop "$@")"
    [ -n "${entry:-}" ] && FAVORITES+=("$entry")
    return 0  # never fail the caller under set -e when an app is absent
  }

  msg "Setting favorites on the taskbar"
  local FAVORITES=()
  add_favorite cursor.desktop
  add_favorite org.gnome.Nautilus.desktop
  add_favorite org.gnome.Settings.desktop gnome-control-center.desktop
  add_favorite org.gnome.Notes.desktop org.gnome.TextEditor.desktop
  add_favorite update-manager.desktop
  if [ -n "$managed_program_favorites" ]; then
    # Master handoff owns program favourites. Baseline utilities stay above;
    # selected rows may be empty when every [f] marker is cleared.
    local selected_entry
    local -a _selected_program_favorites=()
    if [ -n "$selected_program_favorites" ]; then
      IFS=', ' read -r -a _selected_program_favorites <<<"$selected_program_favorites"
      for selected_entry in "${_selected_program_favorites[@]}"; do
        [ -n "$selected_entry" ] && add_favorite "$selected_entry"
      done
    fi
  elif [ -n "$selected_program_favorites" ]; then
    # Legacy master handoff without managed metadata: keep baseline utilities and
    # add only the selected program .desktop ids.
    local selected_entry
    local -a _selected_program_favorites=()
    IFS=', ' read -r -a _selected_program_favorites <<<"$selected_program_favorites"
    for selected_entry in "${_selected_program_favorites[@]}"; do
      [ -n "$selected_entry" ] && add_favorite "$selected_entry"
    done
  else
    # No master handoff (standalone run): rebuild the same default app dock the
    # master installer would forward by consuming linux_installations_setup's
    # favourite-component contract, keeping that repo the single source of truth.
    # Each candidate group lists .desktop alternatives; add_favorite pins the
    # first installed one.
    local candidate_group
    local -a _candidates
    while IFS= read -r candidate_group; do
      [ -n "$candidate_group" ] || continue
      _candidates=()
      IFS=', ' read -r -a _candidates <<<"$candidate_group"
      [ "${#_candidates[@]}" -gt 0 ] && add_favorite "${_candidates[@]}"
    done < <(favorite_app_candidate_groups)
  fi

  # Allow the user to fully customize the dock favorites. The default offered is
  # the installed-app list computed above (comma-joined); FAVORITES_APPS or an
  # interactive entry overrides it with a verbatim, comma/space-separated list of
  # .desktop ids.
  local default_csv="" entry
  for entry in "${FAVORITES[@]}"; do
    [ -n "$entry" ] || continue
    default_csv="${default_csv:+$default_csv,}$entry"
  done

  local resolved
  resolved="$(resolve_user_value FAVORITES_APPS \
    "  Dock favorite apps (comma-separated .desktop ids): " "$default_csv")"

  # Split on commas and whitespace, scoping IFS to just this read.
  FAVORITES=()
  IFS=', ' read -r -a FAVORITES <<<"$resolved"

  if [ "$favorites_manual_override" = "0" ] && [ -n "$managed_reconcile_ids" ]; then
    local current_raw managed_entry preserved_entry merged_entry
    local -a current_favorites=() managed_ids=() preserved=() merged=()
    local -A managed_set=() merged_set=()

    current_raw="$(user_gsettings get org.gnome.shell favorite-apps 2>/dev/null || true)"
    if [[ "$current_raw" == \[* ]]; then
      mapfile -t current_favorites < <(parse_gsettings_string_array "$current_raw")
    fi
    IFS=', ' read -r -a managed_ids <<<"$managed_reconcile_ids"
    for managed_entry in "${managed_ids[@]}"; do
      [ -n "$managed_entry" ] && managed_set[$managed_entry]=1
    done
    for preserved_entry in "${current_favorites[@]}"; do
      [ -n "$preserved_entry" ] || continue
      [[ -n "${managed_set[$preserved_entry]:-}" ]] && continue
      preserved+=("$preserved_entry")
    done
    for merged_entry in "${FAVORITES[@]}" "${preserved[@]}"; do
      [ -n "$merged_entry" ] || continue
      [[ -n "${merged_set[$merged_entry]:-}" ]] && continue
      merged_set[$merged_entry]=1
      merged+=("$merged_entry")
    done
    FAVORITES=("${merged[@]}")
    log "info" "Reconciled dock favorites: preserved ${#preserved[@]} unmanaged entries"
  fi

  if [ "${#FAVORITES[@]}" -gt 0 ]; then
    user_gsettings set org.gnome.shell favorite-apps "$(join_as_gsettings_array "${FAVORITES[@]}")"
  else
    msg "No favorites were found to set (no matching desktop files)"
  fi
  local result=$?
  printf '%s\n' "$result"
  return "$result"
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
#   each connected monitor to its highest mode via xrandr and clears mutter VRR
#   leftovers (Wayland may have left experimental-features on; on NVIDIA X11
#   that walks every DFP ~16 Hz and drops pointer/keyboard events). On Wayland
#   it enables mutter's variable-refresh-rate experimental feature.
#   Args: none. Returns: 0.
configure_display_refresh() {
  if [[ "$SESSION_TYPE" =~ ^(x11|xorg)$ ]]; then
    msg "Xorg: clearing leftover mutter VRR and setting MAX refresh per monitor"
    log "info" "configure_display_refresh: X11 clearing org.gnome.mutter experimental-features (VRR leftover causes NVIDIA output-detect lag)"
    user_gsettings set org.gnome.mutter experimental-features "[]"
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
  log "info" "Deploying UV supply-chain config from $CONFIG_DIR/uv/uv.toml"
  run_as_target install -D -m 0644 \
    "$CONFIG_DIR/uv/uv.toml" \
    "$TARGET_HOME/.config/uv/uv.toml"
}

# ── GNOME Shell extensions ───────────────────────────────────────────────────

# Compatibility entrypoint for old callers. linux_workspaces_setup exclusively
# deploys app-rules; never overwrite its numbering and lifecycle implementation.
configure_app_rules_extension() {
  msg "App rules are owned by linux_workspaces_setup; keeping installed files unchanged."
}
