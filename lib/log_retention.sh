#!/usr/bin/env bash
# Bounded system logging; normal installs never discard existing log contents.

# Require the current logging policy assets before installation.
# Parameters: none. Returns: 0 for readable assets, 1 when an asset is missing.
require_log_retention_assets() {
  printf 'parameters=none\n' >&2
  local name
  for name in journald.conf logrotate-timer.conf bound-rsyslog.awk; do
    if [[ ! -r "$CONFIG_DIR/logging/$name" ]]; then
      printf 'Missing logging asset: %s\n' "$CONFIG_DIR/logging/$name" >&2
      printf '1\n' >&2
      return 1
    fi
  done
  printf '0\n' >&2
}

# Inspect installed bounds, including the existing rsyslog policy when present.
# Parameters: none. Returns: 0 when all applicable policies match, 1 otherwise.
detect_log_retention() {
  printf 'parameters=none\n' >&2
  local root="${LOG_RETENTION_ROOT:-}" rsyslog
  rsyslog="$root/etc/logrotate.d/rsyslog"
  if ! cmp -s "$CONFIG_DIR/logging/journald.conf" "$root/etc/systemd/journald.conf.d/60-bounded-logs.conf"; then
    printf '1\n' >&2
    return 1
  fi
  if command -v logrotate >/dev/null; then
    if ! cmp -s "$CONFIG_DIR/logging/logrotate-timer.conf" "$root/etc/systemd/system/logrotate.timer.d/60-bounded-logs.conf"; then
      printf '1\n' >&2
      return 1
    fi
    if [[ -f "$rsyslog" ]] && ! cmp -s "$rsyslog" <(awk -f "$CONFIG_DIR/logging/bound-rsyslog.awk" "$rsyslog"); then
      printf '1\n' >&2
      return 1
    fi
  fi
  printf '0\n' >&2
}

# Install journal limits and available text-log rotation without deleting logs.
# Parameters: none. Returns: 0 for installation, idempotence or sudo deferral; nonzero for failure.
configure_log_retention() {
  printf 'parameters=none\n' >&2
  if ! require_log_retention_assets; then
    printf '1\n' >&2
    return 1
  fi
  local root="${LOG_RETENTION_ROOT:-}" rsyslog candidate validation
  if ! is_root; then
    note_sudo_required "bash '$SCRIPT_DIR/install.sh' --select log_retention"
    printf '0\n' >&2
    return 0
  fi
  if detect_log_retention; then
    printf '0\n' >&2
    return 0
  fi
  rsyslog="$root/etc/logrotate.d/rsyslog"
  if command -v logrotate >/dev/null && [[ -f "$rsyslog" ]]; then
    candidate="$(mktemp)"
    if ! awk -f "$CONFIG_DIR/logging/bound-rsyslog.awk" "$rsyslog" > "$candidate"; then
      rm -f "$candidate"
      printf '1\n' >&2
      return 1
    fi
    # logrotate only reads regular configuration files; process substitutions are ignored.
    validation="$(mktemp)"
    printf 'su root adm\ninclude %s\n' "$candidate" > "$validation"
    if ! logrotate --debug "$validation"; then
      rm -f "$candidate" "$validation"
      printf 'Refusing to install an invalid logrotate policy\n' >&2
      printf '1\n' >&2
      return 1
    fi
    rm -f "$validation"
    if [[ ! -e "$root/var/backups/log-retention/rsyslog.logrotate.original" ]]; then
      install -D -m 0600 "$rsyslog" "$root/var/backups/log-retention/rsyslog.logrotate.original" || { printf '1\n' >&2; return 1; }
    fi
    install -m 0644 "$candidate" "$rsyslog" || { printf '1\n' >&2; return 1; }
    rm -f "$candidate"
  fi
  install -D -m 0644 "$CONFIG_DIR/logging/journald.conf" "$root/etc/systemd/journald.conf.d/60-bounded-logs.conf" || { printf '1\n' >&2; return 1; }
  if command -v logrotate >/dev/null; then
    install -D -m 0644 "$CONFIG_DIR/logging/logrotate-timer.conf" "$root/etc/systemd/system/logrotate.timer.d/60-bounded-logs.conf" || { printf '1\n' >&2; return 1; }
    systemctl daemon-reload || { printf '1\n' >&2; return 1; }
    systemctl restart logrotate.timer || { printf '1\n' >&2; return 1; }
  fi
  systemctl restart systemd-journald.service || { printf '1\n' >&2; return 1; }
  printf '0\n' >&2
}
