#!/usr/bin/env bash
set -euo pipefail

source_text="$(cat "$(dirname "$0")/../install.sh")"
grep -q 'log_dir="$SCRIPT_DIR/.log"' <<<"$source_text"
grep -q 'mkdir -p "$log_dir"' <<<"$source_text"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
stderr_file="$(mktemp)"
trap 'rm -f "$stderr_file"' EXIT

(
  source "$ROOT_DIR/lib/logging.sh"
  LOG_LEVEL=debug
  log "debug" 'debug "message"'
  INSTALLER_PRODUCTION=1 log "info" 'json "message"'
) 2>"$stderr_file"

grep -q '\[DEBUG\] debug "message"' "$stderr_file"
grep -q '"level":"INFO"' "$stderr_file"
grep -q '"message":"json \\"message\\""' "$stderr_file"
