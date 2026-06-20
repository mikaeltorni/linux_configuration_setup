#!/usr/bin/env bash
# system_config.sh — System-level configuration helpers (RTC, dark mode, mouse accel, etc.)
#
# Components:
#   - configure_rtc(): Set RTC to local time via timedatectl.
#   - configure_clock_calendar(): Enable weekday + week numbers in GNOME clock/calendar.
#   - configure_disable_auto_lock(): Disable screen auto-lock (idle-delay=0, lock-enabled=false).
#   - configure_dark_mode(): Enable dark mode system-wide (GTK theme, icon theme, user-theme).
#   - disable_mouse_acceleration(): Set flat mouse/touchpad acceleration + X11 libinput fallback.
#
# Sourced after lib/helpers.sh and lib/gsettings_helpers.sh.
# Depends on: msg, run_as_target, user_gsettings

# ── RTC configuration ────────────────────────────────────────────────────────

# configure_rtc — Set the hardware clock to local time (dual-boot clock fix).
#   Args: none.
#   Returns: 0 when RTC is already local, the step is skipped (non-root), or
#     timedatectl succeeds; non-zero if timedatectl fails while running as root.
configure_rtc() {
  msg "Setting RTC to local time"
  if [ "$(timedatectl show --property=LocalRTC --value 2>/dev/null)" = "yes" ]; then
    msg "RTC already set to local time"
    return 0
  fi
  if ! is_root; then
    note_sudo_required "timedatectl set-local-rtc 1 --adjust-system-clock"
    return 0
  fi
  timedatectl set-local-rtc 1 --adjust-system-clock
}

# ── Clock & calendar configuration ───────────────────────────────────────────

# configure_clock_calendar — Enable weekday + week numbers in GNOME clock/calendar.
#   Args: none. Returns: 0 (best-effort; only sets keys the schema defines).
configure_clock_calendar() {
  msg "Enabling weekday + week numbers in GNOME clock/calendar"
  user_gsettings_set_if_key_exists org.gnome.desktop.interface clock-show-weekday true
  user_gsettings_set_if_key_exists org.gnome.desktop.calendar show-weekdate true
}

# ── Screen lock configuration ────────────────────────────────────────────────

# configure_disable_auto_lock — Disable screen auto-lock and idle activation.
#   Args: none. Returns: 0 (each gsettings write is best-effort).
configure_disable_auto_lock() {
  msg "Disabling screen auto-lock"
  user_gsettings set org.gnome.desktop.session idle-delay 0 || true
  user_gsettings set org.gnome.desktop.screensaver lock-enabled false || true
  user_gsettings set org.gnome.desktop.screensaver idle-activation-enabled false || true
}

# ── Dark mode configuration ──────────────────────────────────────────────────

# configure_dark_mode — Enable dark mode system-wide.
#   Sets GTK theme (Adwaita-dark or Yaru-dark), icon theme, and user-theme extension.
#   Args: none. Returns: 0 (each gsettings write is best-effort).
configure_dark_mode() {
  msg "Enabling dark mode system-wide"

  local gtk_theme="Adwaita-dark"
  if [ -d /usr/share/themes/Yaru-dark ]; then
    gtk_theme="Yaru-dark"
  fi

  user_gsettings set org.gnome.desktop.interface color-scheme "'prefer-dark'" || true
  user_gsettings set org.gnome.desktop.interface gtk-theme "'$gtk_theme'" || true
  user_gsettings set org.gnome.desktop.interface icon-theme "'Yaru'" || true

  if gsettings list-schemas 2>/dev/null | grep -q 'org.gnome.shell.extensions.user-theme'; then
    user_gsettings set org.gnome.shell.extensions.user-theme name "'$gtk_theme'" || true
  fi
}

# ── Mouse acceleration configuration ─────────────────────────────────────────

# disable_mouse_acceleration — Set flat mouse/touchpad acceleration profile.
#   Configures GNOME settings for both Wayland and Xorg, plus an X11 libinput fallback.
#   Args: none.
#   Returns: 0 when settings are applied, the X11 config already exists, or the
#     root-only file write is deferred (non-root); non-zero if writing the
#     /etc/X11 config fails while running as root.
disable_mouse_acceleration() {
  msg "Disabling mouse acceleration (flat profile)"

  # GNOME settings (Wayland + Xorg)
  user_gsettings set org.gnome.desktop.peripherals.mouse accel-profile "'flat'" || true
  user_gsettings set org.gnome.desktop.peripherals.mouse speed 0.0 || true
  user_gsettings set org.gnome.desktop.peripherals.touchpad accel-profile "'flat'" || true
  user_gsettings set org.gnome.desktop.peripherals.touchpad speed 0.0 || true

  # X11 fallback to enforce libinput flat profile
  if [ -d /etc/X11 ]; then
    if [ -f /etc/X11/xorg.conf.d/90-libinput-no-accel.conf ]; then
      return 0
    fi
    if ! is_root; then
      note_sudo_required "write /etc/X11/xorg.conf.d/90-libinput-no-accel.conf (libinput flat profile)"
      return 0
    fi
    install -d -m 0755 /etc/X11/xorg.conf.d
    cat >/etc/X11/xorg.conf.d/90-libinput-no-accel.conf <<'EOF'
Section "InputClass"
  Identifier "Disable libinput mouse acceleration"
  MatchIsPointer "yes"
  MatchDriver "libinput"
  Option "AccelProfile" "flat"
  Option "AccelSpeed" "0"
EndSection
EOF
  fi
}

# ── Tmux configuration ───────────────────────────────────────────────────────

# configure_tmux_defaults — Install .tmux.conf from CONFIG_DIR for the target user.
#   Args: none. Returns: 0 (logs a warning and skips if the source is missing).
configure_tmux_defaults() {
  msg "Configuring tmux defaults for $TARGET_USER"

  local tmux_conf_src="$CONFIG_DIR/.tmux.conf"
  if [ -f "$tmux_conf_src" ]; then
    run_as_target cp -f "$tmux_conf_src" "$TARGET_HOME/.tmux.conf"
    msg "Tmux config installed from $tmux_conf_src"
  else
    log "warn" ".tmux.conf not found at $tmux_conf_src — skipping tmux configuration"
  fi
}
