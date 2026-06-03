#!/usr/bin/env bash
# systemd_helpers.sh — Common systemd user service management helpers
#
# Components:
#   - enable_systemd_service(service_name): Enable and start a systemd user service.
#   - restart_systemd_service(service_name): Restart a systemd user service.
#   - reload_systemd_daemon(): Reload the systemd daemon (runs as target user).

enable_systemd_service() {
  local service_name="$1"
  run_as_target systemctl --user daemon-reload || true
  run_as_target systemctl --user enable "$service_name" || true
  run_as_target systemctl --user start "$service_name" || true
}

restart_systemd_service() {
  local service_name="$1"
  run_as_target systemctl --user restart "$service_name" || true
}

reload_systemd_daemon() {
  run_as_target systemctl --user daemon-reload || true
}
