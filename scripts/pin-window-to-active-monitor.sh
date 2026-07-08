#!/usr/bin/env bash
# pin-window-to-active-monitor.sh — move a window to the monitor containing the
# mouse pointer, so newly-launched windows don't land on a different monitor
# when the active workspace is crowded.
#
# Installed by linux_configuration_setup (component: active_monitor_placement)
# to ~/.local/bin/. Called by the open-kitty-and-sort hotkey after a new kitty
# window is detected, but general-purpose: any script can call it with a window
# ID to move that window to the pointer's monitor.
#
# On X11, keyboard shortcuts do not move the pointer, so the pointer stays on
# the monitor the user was working on when the hotkey fired. By moving the new
# window to that monitor, the window never lands on a wrong display — even when
# GNOME's window placement redirected it elsewhere because the active workspace
# was crowded.
#
# Usage: pin-window-to-active-monitor.sh [WINDOW_ID]
#   WINDOW_ID - the window to move (default: the currently focused window)
#
# Requires xdotool (X11) and xrandr for monitor detection. Degrades gracefully:
# if either is missing, or the session is not X11, the script exits 0 without
# moving anything.

set -u

# xdotool is needed for window geometry, pointer location, and window movement.
if ! command -v xdotool >/dev/null 2>&1; then
  printf 'pin-window-to-active-monitor: xdotool not found; nothing to do.\n' >&2
  exit 0
fi

# xrandr provides per-monitor geometry and offsets. It is part of the standard
# Ubuntu desktop install (x11-xserver-utils); skip silently when absent.
if ! command -v xrandr >/dev/null 2>&1; then
  printf 'pin-window-to-active-monitor: xrandr not found; nothing to do.\n' >&2
  exit 0
fi

# Resolve the window to move: explicit argument, else the focused window.
wid="${1:-}"
if [ -z "$wid" ]; then
  wid="$(xdotool getactivewindow 2>/dev/null || true)"
fi
if [ -z "$wid" ]; then
  printf 'pin-window-to-active-monitor: no window to move.\n' >&2
  exit 0
fi

# Get the pointer location — the target monitor is the one the pointer is on.
# (Keyboard shortcuts don't move the pointer, so it stays on the active monitor
# when a hotkey fires.)
eval "$(xdotool getmouselocation --shell 2>/dev/null)"
if [ -z "${X:-}" ] || [ -z "${Y:-}" ]; then
  printf 'pin-window-to-active-monitor: could not get pointer location.\n' >&2
  exit 0
fi
pointer_x="$X"
pointer_y="$Y"

# Get the window's current geometry.
eval "$(xdotool getwindowgeometry --shell "$wid" 2>/dev/null)"
if [ -z "${X:-}" ] || [ -z "${Y:-}" ]; then
  printf 'pin-window-to-active-monitor: could not get window geometry for %s.\n' "$wid" >&2
  exit 0
fi
win_x="$X"
win_y="$Y"
win_w="${WIDTH:-0}"
win_h="${HEIGHT:-0}"

# point_on_monitor PX PY MX MY MW MH — true when point (PX,PY) is inside the
# monitor rectangle with origin (MX,MY) and size (MW,MH).
point_on_monitor() {
  local px="$1" py="$2" mx="$3" my="$4" mw="$5" mh="$6"
  [ "$px" -ge "$mx" ] && [ "$px" -lt $((mx + mw)) ] && \
    [ "$py" -ge "$my" ] && [ "$py" -lt $((my + mh)) ]
}

# Parse xrandr --listmonitors into "mx my mw mh" lines (one per monitor).
# Example input line:
#   0: +*DP-4 3840/700x2160/390+0+2160  DP-4
# grep extracts the geometry token "W/mmWxH/mmH+XOFF+YOFF" from each line;
# the while loop splits it into monitor origin and size.
monitor_lines="$(xrandr --listmonitors 2>/dev/null \
  | grep -oE '[0-9]+/[0-9]+x[0-9]+/[0-9]+\+[0-9]+\+[0-9]+' \
  | while IFS= read -r geom; do
      mw="${geom%%/*}"
      rest="${geom#*/}"
      rest="${rest#*x}"
      mh="${rest%%/*}"
      rest="${rest#*/}"
      rest="${rest#*+}"
      mx="${rest%%+*}"
      my="${rest#*+}"
      printf '%s %s %s %s\n' "$mx" "$my" "$mw" "$mh"
    done)"

if [ -z "$monitor_lines" ]; then
  printf 'pin-window-to-active-monitor: could not parse monitor layout.\n' >&2
  exit 0
fi

# Find which monitor the pointer is on (target) and which the window center is
# on (current). If they differ, move the window to preserve its relative
# position within the target monitor.
target_mx="" target_my="" target_mw="" target_mh=""
current_mx="" current_my="" current_mw="" current_mh=""
center_x=$((win_x + win_w / 2))
center_y=$((win_y + win_h / 2))

while IFS=' ' read -r mx my mw mh; do
  [ -z "$mx" ] && continue
  if point_on_monitor "$pointer_x" "$pointer_y" "$mx" "$my" "$mw" "$mh"; then
    target_mx="$mx" target_my="$my" target_mw="$mw" target_mh="$mh"
  fi
  if point_on_monitor "$center_x" "$center_y" "$mx" "$my" "$mw" "$mh"; then
    current_mx="$mx" current_my="$my" current_mw="$mw" current_mh="$mh"
  fi
done <<< "$monitor_lines"

# Bail if we couldn't locate the pointer or window on any monitor.
if [ -z "$target_mx" ] || [ -z "$current_mx" ]; then
  printf 'pin-window-to-active-monitor: could not determine monitor for pointer or window.\n' >&2
  exit 0
fi

# Already on the target monitor — nothing to do.
if [ "$target_mx" = "$current_mx" ] && [ "$target_my" = "$current_my" ]; then
  exit 0
fi

# Move the window to the target monitor, preserving its relative position
# within the monitor, then clamp so it doesn't overflow the target's edges.
new_x=$((target_mx + (win_x - current_mx)))
new_y=$((target_my + (win_y - current_my)))

if [ "$win_w" -gt 0 ]; then
  [ "$new_x" -lt "$target_mx" ] && new_x="$target_mx"
  [ $((new_x + win_w)) -gt $((target_mx + target_mw)) ] && new_x=$((target_mx + target_mw - win_w))
fi
if [ "$win_h" -gt 0 ]; then
  [ "$new_y" -lt "$target_my" ] && new_y="$target_my"
  [ $((new_y + win_h)) -gt $((target_my + target_mh)) ] && new_y=$((target_my + target_mh - win_h))
fi

xdotool windowmove "$wid" "$new_x" "$new_y" 2>/dev/null || true
printf 'pin-window-to-active-monitor: moved window %s to monitor at %s,%s (pos %s,%s)\n' \
  "$wid" "$target_mx" "$target_my" "$new_x" "$new_y" >&2
