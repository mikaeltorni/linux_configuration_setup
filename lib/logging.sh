#!/usr/bin/env bash
# logging.sh — Centralized logging utility for all project scripts.
#
# Components:
#   - log(level, msg): Timestamped logging with levels (verbose/debug/info/warn/error)
#   - _log_level_value(level): Internal level parser honoring LOG_LEVEL.
#   - _log_json_escape(text): Internal JSON string escaper for production logs.

_LOG_LEVEL_VERBOSE=0
_LOG_LEVEL_DEBUG=10
_LOG_LEVEL_INFO=20
_LOG_LEVEL_WARN=30
_LOG_LEVEL_ERROR=40

INSTALLER_PRODUCTION="${INSTALLER_PRODUCTION:-0}"

# _log_level_value — Convert a level name to its numeric threshold.
#   Args: $1 — level name. Returns: 0 and prints the numeric threshold.
_log_level_value() {
  case "${1,,}" in
    verbose) printf '%s\n' "$_LOG_LEVEL_VERBOSE" ;;
    debug) printf '%s\n' "$_LOG_LEVEL_DEBUG" ;;
    info) printf '%s\n' "$_LOG_LEVEL_INFO" ;;
    warn|warning) printf '%s\n' "$_LOG_LEVEL_WARN" ;;
    error) printf '%s\n' "$_LOG_LEVEL_ERROR" ;;
    *) printf '%s\n' "$_LOG_LEVEL_INFO" ;;
  esac
}

# _log_json_escape — Escape text for the simple JSON line logger.
#   Args: $1 — raw message text. Returns: 0 and prints escaped text.
_log_json_escape() {
  local text="${1:-}"
  text="${text//\\/\\\\}"
  text="${text//\"/\\\"}"
  text="${text//$'\n'/\\n}"
  text="${text//$'\r'/\\r}"
  text="${text//$'\t'/\\t}"
  printf '%s' "$text"
}

# log — Emit a timestamped log line to stderr if the message level meets the
#   active threshold. Uses JSON output when INSTALLER_PRODUCTION=1, otherwise a
#   human-readable format.
#   Args: $1 — level name; $2.. — message text.
#   Returns: 0 (messages below the threshold are silently dropped).
log() {
  local level="${1:-info}" msg="${*:2}"
  local threshold current_threshold timestamp level_upper
  threshold="$(_log_level_value "$level")"
  current_threshold="$(_log_level_value "${LOG_LEVEL:-info}")"
  if (( threshold < current_threshold )); then return 0; fi
  level_upper="${level^^}"
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  if [[ "${INSTALLER_PRODUCTION}" == "1" ]]; then
    printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' \
      "$timestamp" "$level_upper" "$(_log_json_escape "$msg")" >&2
  else
    printf "[%s] [%s] %s\n" "$timestamp" "$level_upper" "$msg" >&2
  fi
}
