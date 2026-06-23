#!/usr/bin/env bash
# Activate a staged passwordless keyring before gnome-keyring-daemon starts.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$script_dir/logging.sh" ]]; then
  # The installed systemd helper receives the centralized shell logger beside
  # this script. Source-tree test runs use the no-op fallback below.
  source "$script_dir/logging.sh"
else
  log() { :; }
fi

state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
state_dir="$state_home/linux-configuration-setup"
pending_dir="$state_dir/passwordless-keyring-pending"
keyring_dir="$HOME/.local/share/keyrings"
marker="$state_dir/passwordless-keyring-v1"

[[ -f "$pending_dir/ready" ]] || { log "debug" "No staged passwordless keyring found"; exit 0; }
[[ -f "$pending_dir/login.keyring" ]]
[[ -f "$pending_dir/default" ]]
[[ "$(cat "$pending_dir/default")" == login ]]
log "info" "Activating staged passwordless Login keyring"

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="$state_dir/keyring-backups/pre-passwordless-$timestamp"
while [[ -e "$backup_dir" ]]; do
  sleep 1
  timestamp="$(date +%Y%m%d-%H%M%S)"
  backup_dir="$state_dir/keyring-backups/pre-passwordless-$timestamp"
done

install -d -m 0700 "$keyring_dir" "$backup_dir"
log "debug" "Backing up existing keyrings to $backup_dir"
shopt -s nullglob
current=("$keyring_dir"/*.keyring "$keyring_dir"/default)
staged=("$pending_dir"/*.keyring "$pending_dir"/default)
((${#staged[@]} > 0))

((${#current[@]} == 0)) || mv -- "${current[@]}" "$backup_dir"/
if ! install -m 0600 "${staged[@]}" "$keyring_dir"/; then
  log "error" "Failed to install staged passwordless keyring; restoring backup"
  rm -f "$keyring_dir"/*.keyring "$keyring_dir"/default
  originals=("$backup_dir"/*)
  ((${#originals[@]} == 0)) || mv -- "${originals[@]}" "$keyring_dir"/
  exit 1
fi

install -m 0600 /dev/null "$marker"
rm -rf "$pending_dir"
log "info" "Passwordless Login keyring activated"
