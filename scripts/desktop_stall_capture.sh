#!/usr/bin/env bash
# desktop_stall_capture.sh — record rare NVIDIA/input desktop stall episodes.
#
# Follows the user journal and writes a snapshot under
# $XDG_STATE_HOME/desktop-stall/episodes/ when mutter's NVIDIA DFP probe loop
# starts, when phrase-automation recreates uinput, or when libinput drops
# events. Episodes are uncommon; the watcher stays quiet until a trigger.
#
# Usage:
#   desktop_stall_capture.sh              # follow journal (systemd service)
#   desktop_stall_capture.sh --dump-now [reason]
set -euo pipefail

STATE_DIR="${STALL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/desktop-stall}"
EPISODE_DIR="$STATE_DIR/episodes"
LOG_FILE="$STATE_DIR/stall.log"
COOLDOWN_SEC="${STALL_COOLDOWN_SEC:-60}"
DFP_THRESHOLD="${STALL_DFP_THRESHOLD:-5}"
LAST_DUMP_EPOCH=0
DFP_SECOND=""
DFP_COUNT=0

if [[ -n "${LCS_SCRIPT_DIR:-}" && -f "${LCS_SCRIPT_DIR}/lib/logging.sh" ]]; then
  # shellcheck source=/dev/null
  source "${LCS_SCRIPT_DIR}/lib/logging.sh"
fi

# _stall_log — append one line to the stall log and the centralized logger.
#   Args: message text. Returns: 0.
_stall_log() {
  local msg="$*"
  local ts
  ts="$(date -Iseconds 2>/dev/null || date)"
  mkdir -p "$STATE_DIR"
  printf '%s %s\n' "$ts" "$msg" >>"$LOG_FILE"
  if declare -F log >/dev/null 2>&1; then
    log info "$msg"
  else
    printf '%s %s\n' "$ts" "$msg" >&2
  fi
}

# dump_episode — write a stall snapshot (processes, udev, DFP, PA uinput).
#   Args: $1 reason string. Returns: 0. Honors STALL_COOLDOWN_SEC.
dump_episode() {
  local reason="${1:-unspecified}"
  local now dest
  now="$(date +%s)"
  if (( now - LAST_DUMP_EPOCH < COOLDOWN_SEC )); then
    return 0
  fi
  LAST_DUMP_EPOCH="$now"
  mkdir -p "$EPISODE_DIR"
  dest="$EPISODE_DIR/$(date +%Y%m%d-%H%M%S).txt"
  {
    echo "=== desktop stall episode ==="
    echo "captured_at: $(date -Iseconds)"
    echo "reason: $reason"
    echo
    echo "=== load ==="
    cat /proc/loadavg 2>/dev/null || true
    echo "=== pressure cpu ==="
    head -n 1 /proc/pressure/cpu 2>/dev/null || true
    echo "=== gpu ==="
    nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,pstate --format=csv 2>/dev/null || true
    echo "=== top cpu ==="
    ps -eo pid,pcpu,rss,stat,comm,args --sort=-pcpu 2>/dev/null | head -20 || true
    echo "=== phrase_automation ==="
    tmux display-message -p -t phrase_automation:app '#{pane_start_command}' 2>/dev/null || true
    tmux show-environment -t phrase_automation 2>/dev/null | grep PHRASE || true
    pgrep -af 'python3 main.py' 2>/dev/null | grep -v grep || true
    echo "=== DFP last 60s ==="
    journalctl --since "60 sec ago" --no-pager 2>/dev/null | grep -c "DFP-0): connected" || true
    echo "=== udev/input last 2 min ==="
    journalctl --since "2 min ago" --no-pager 2>/dev/null \
      | grep -E "config/udev: (Adding|Removing) input|section-interceptor|section-wheel|Adding input device MFG|SYN_DROPPED|lagging behind" \
      | tail -80 || true
    echo "=== recent uinput_created (live + worktrees, 10 min) ==="
    find /home/mk/projects/phrase_automation /home/mk/projects/.worktrees/phrase_automation \
      -name phrase_automation.log -mmin -10 2>/dev/null \
      | while read -r logf; do
          hits="$(grep -E "uinput_created|uinput_closed" "$logf" 2>/dev/null | tail -20 || true)"
          if [ -n "$hits" ]; then
            echo "-- $logf --"
            printf '%s\n' "$hits"
          fi
        done
  } >"$dest" 2>/dev/null || true
  ln -sfn "episodes/$(basename "$dest")" "$STATE_DIR/latest.txt" 2>/dev/null || true
  _stall_log "dumped episode $dest ($reason)"
}

# process_journal_line — classify one journal line and dump on a stall trigger.
#   Args: $1 journal line. Returns: 0.
process_journal_line() {
  local line="$1"
  local second

  if [[ "$line" == *"DFP-0): connected"* ]]; then
    second="${line:0:19}"
    if [[ "$second" != "$DFP_SECOND" ]]; then
      DFP_SECOND="$second"
      DFP_COUNT=1
    else
      DFP_COUNT=$((DFP_COUNT + 1))
    fi
    if (( DFP_COUNT >= DFP_THRESHOLD )); then
      dump_episode "dfp_probe_loop count=${DFP_COUNT} second=${DFP_SECOND}"
      DFP_COUNT=0
    fi
    return 0
  fi
  if [[ "$line" == *"SYN_DROPPED"* || "$line" == *"lagging behind"* ]]; then
    dump_episode "libinput_drop"
    return 0
  fi
  if [[ "$line" == *"Adding input device section-interceptor"* \
     || "$line" == *"Adding input device section-wheel-interceptor"* ]]; then
    dump_episode "pa_uinput_hotplug"
    return 0
  fi
  if [[ "$line" == *"Adding input device MFG"* ]]; then
    dump_episode "crosswind_xorg_add"
    return 0
  fi
}

# follow_journal — stream journal lines into process_journal_line.
follow_journal() {
  ${STALL_JOURNAL_CMD:-journalctl -f -n 0 --no-pager -o short-iso} \
    | while IFS= read -r line; do
        process_journal_line "$line" || true
      done
}

main() {
  mkdir -p "$EPISODE_DIR"
  case "${1:-}" in
    --dump-now)
      COOLDOWN_SEC=0
      dump_episode "${2:-manual}"
      ;;
    *)
      _stall_log "watching journal for NVIDIA/input stall triggers"
      follow_journal
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
