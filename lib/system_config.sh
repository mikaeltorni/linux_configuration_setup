#!/usr/bin/env bash
# system_config.sh — System-level configuration helpers (RTC, dark mode, mouse accel, etc.)
#
# Components:
#   - configure_rtc(): Set RTC to local time via timedatectl.
#   - configure_clock_calendar(): Enable weekday + week numbers in GNOME clock/calendar.
#   - configure_disable_auto_lock(): Disable screen auto-lock (idle-delay=0, lock-enabled=false).
#   - configure_dark_mode(): Enable dark mode system-wide (GTK theme, icon theme, user-theme).
#   - disable_mouse_acceleration(): Set flat mouse/touchpad acceleration + X11 libinput fallback.
#   - configure_tmux_defaults(): Configure tmux defaults for the target user.

configure_rtc() {
  msg "Setting RTC to local time"
  timedatectl set-local-rtc 1 --adjust-system-clock
}

configure_clock_calendar() {
  msg "Enabling weekday + week numbers in GNOME clock/calendar"
  user_gsettings_set_if_key_exists org.gnome.desktop.interface clock-show-weekday true
  user_gsettings_set_if_key_exists org.gnome.desktop.calendar show-weekdate true
}

configure_disable_auto_lock() {
  msg "Disabling screen auto-lock"
  user_gsettings set org.gnome.desktop.session idle-delay 0 || true
  user_gsettings set org.gnome.desktop.screensaver lock-enabled false || true
  user_gsettings set org.gnome.desktop.screensaver idle-activation-enabled false || true
}

configure_dark_mode() {
  msg "Enabling dark mode system-wide"
  local gtk_theme="Adwaita-dark"
  if [ -d /usr/share/themes/Yaru-dark ]; then gtk_theme="Yaru-dark"; fi
  user_gsettings set org.gnome.desktop.interface color-scheme "'prefer-dark'" || true
  user_gsettings set org.gnome.desktop.interface gtk-theme "'$gtk_theme'" || true
  user_gsettings set org.gnome.desktop.interface icon-theme "'Yaru'" || true
  if gsettings list-schemas 2>/dev/null | grep -q 'org.gnome.shell.extensions.user-theme'; then
    user_gsettings set org.gnome.shell.extensions.user-theme name "'$gtk_theme'" || true
  fi
}

disable_mouse_acceleration() {
  msg "Disabling mouse acceleration (flat profile)"
  user_gsettings set org.gnome.desktop.peripherals.mouse accel-profile "'flat'" || true
  user_gsettings set org.gnome.desktop.peripherals.mouse speed 0.0 || true
  user_gsettings set org.gnome.desktop.peripherals.touchpad accel-profile "'flat'" || true
  user_gsettings set org.gnome.desktop.peripherals.touchpad speed 0.0 || true
  if [ -d /etc/X11 ]; then
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

configure_tmux_defaults() {
  msg "Configuring tmux defaults for $TARGET_USER"
  run_as_target tee "$TARGET_HOME/.tmux.conf" >/dev/null <<'EOF'
set -g mouse on
set -g history-limit 200000
set -g mode-keys vi
EOF
}
