#!/usr/bin/env bash
# Activate a staged passwordless keyring before gnome-keyring-daemon starts.

set -euo pipefail

state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
state_dir="$state_home/linux-configuration-setup"
pending_dir="$state_dir/passwordless-keyring-pending"
keyring_dir="$HOME/.local/share/keyrings"
marker="$state_dir/passwordless-keyring-v1"

[[ -f "$pending_dir/ready" ]] || exit 0
[[ -f "$pending_dir/login.keyring" ]]
[[ -f "$pending_dir/default" ]]
[[ "$(cat "$pending_dir/default")" == login ]]

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="$state_dir/keyring-backups/pre-passwordless-$timestamp"
while [[ -e "$backup_dir" ]]; do
  sleep 1
  timestamp="$(date +%Y%m%d-%H%M%S)"
  backup_dir="$state_dir/keyring-backups/pre-passwordless-$timestamp"
done

install -d -m 0700 "$keyring_dir" "$backup_dir"
shopt -s nullglob
current=("$keyring_dir"/*.keyring "$keyring_dir"/default)
staged=("$pending_dir"/*.keyring "$pending_dir"/default)
((${#staged[@]} > 0))

((${#current[@]} == 0)) || mv -- "${current[@]}" "$backup_dir"/
if ! install -m 0600 "${staged[@]}" "$keyring_dir"/; then
  rm -f "$keyring_dir"/*.keyring "$keyring_dir"/default
  originals=("$backup_dir"/*)
  ((${#originals[@]} == 0)) || mv -- "${originals[@]}" "$keyring_dir"/
  exit 1
fi

install -m 0600 /dev/null "$marker"
rm -rf "$pending_dir"
