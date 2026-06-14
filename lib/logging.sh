#!/usr/bin/env bash
# logging.sh — Centralized logging utility for all project scripts.
#
# Components:
#   - log(level, msg): Timestamped logging with levels (verbose/debug/info/warn/error)

_LOG_LEVEL_VERBOSE=0
_LOG_LEVEL_DEBUG=10
_LOG_LEVEL_INFO=20
_LOG_LEVEL_WARN=30
_LOG_LEVEL_ERROR=40

_LOG_CURRENT_THRESHOLD=$_LOG_LEVEL_INFO
INSTALLER_PRODUCTION="${INSTALLER_PRODUCTION:-0}"

# log — Emit a timestamped log line to stderr if the message level meets the
#   active threshold. Uses JSON output when INSTALLER_PRODUCTION=1, otherwise a
#   human-readable format.
#   Args: $1 — level name; $2.. — message text.
#   Returns: 0 (messages below the threshold are silently dropped).
log() {
  local level="${1:-info}" msg="${*:2}"
  local threshold=0
  case "${level,,}" in
    verbose) threshold=$_LOG_LEVEL_VERBOSE ;;
    debug)   threshold=$_LOG_LEVEL_DEBUG   ;;
    info)    threshold=$_LOG_LEVEL_INFO     ;;
    warn|warning) threshold=$_LOG_LEVEL_WARN ;;
    error)   threshold=$_LOG_LEVEL_ERROR    ;;
    *)       threshold=$_LOG_LEVEL_INFO     ;;
  esac
  if (( threshold < _LOG_CURRENT_THRESHOLD )); then return 0; fi
  local timestamp level_upper="${level^^}"
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  if [[ "${INSTALLER_PRODUCTION}" == "1" ]]; then
    printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' \
      "$timestamp" "$level_upper" "$(echo "$msg" | sed 's/"/\\"/g')" >&2
  else
    printf "[%s] [%s] %s\n" "$timestamp" "$level_upper" "$msg" >&2
  fi
}
