#!/usr/bin/env bash
# Public installer operations use a temporary root and mocked system services.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$SCRIPT_DIR/configs"
REAL_LOGROTATE="$(command -v logrotate)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
export LOG_RETENTION_ROOT="$TEST_DIR/root"
export RETENTION_CALLS="$TEST_DIR/calls"
mkdir -p "$TEST_DIR/bin" "$LOG_RETENTION_ROOT/etc/logrotate.d"
cat > "$TEST_DIR/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$RETENTION_CALLS"
MOCK
cat > "$TEST_DIR/bin/logrotate" <<'MOCK'
#!/usr/bin/env bash
printf 'logrotate %s\n' "$*" >> "$RETENTION_CALLS"
exit "${RETENTION_BAD_POLICY:-0}"
MOCK
chmod +x "$TEST_DIR/bin/"*
export PATH="$TEST_DIR/bin:$PATH"
# Report a simulated privilege level. Parameters: none. Returns: success for mock root.
is_root() {
  printf 'parameters=none\n' >&2
  local status=1
  [[ "${TEST_ROOT:-0}" == 1 ]] && status=0
  printf '%s\n' "$status" >&2
  return "$status"
}
# Record deferred installation. Parameters: $* - privileged command. Returns: 0.
note_sudo_required() {
  printf 'command=%s\n' "$*" >&2
  printf '%s\n' "$*" >> "$TEST_DIR/deferred"
  printf '0\n' >&2
}
source "$SCRIPT_DIR/lib/log_retention.sh"
cat > "$LOG_RETENTION_ROOT/etc/logrotate.d/rsyslog" <<'POLICY'
/var/log/syslog
/var/log/auth.log
{
    weekly
    rotate 4
    delaycompress
    missingok
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
POLICY
cp "$LOG_RETENTION_ROOT/etc/logrotate.d/rsyslog" "$TEST_DIR/original"
TEST_ROOT=0
configure_log_retention
[[ -s "$TEST_DIR/deferred" && ! -e "$RETENTION_CALLS" ]]
[[ ! -e "$LOG_RETENTION_ROOT/etc/systemd/journald.conf.d/60-bounded-logs.conf" ]]
! detect_log_retention
TEST_ROOT=1
configure_log_retention
detect_log_retention
cmp "$TEST_DIR/original" "$LOG_RETENTION_ROOT/var/backups/log-retention/rsyslog.logrotate.original"
policy="$LOG_RETENTION_ROOT/etc/logrotate.d/rsyslog"
rg -q '^    daily$' "$policy"
rg -q '^    maxsize 100M$' "$policy"
rg -q '^    rotate 7$' "$policy"
! rg -q 'weekly|delaycompress' "$policy"
rg -q '/var/log/auth.log' "$policy"
rg -q '/usr/lib/rsyslog/rsyslog-rotate' "$policy"
rg -q '^SystemMaxUse=512M$' "$LOG_RETENTION_ROOT/etc/systemd/journald.conf.d/60-bounded-logs.conf"
rg -q '^OnCalendar=\*:0/15$' "$LOG_RETENTION_ROOT/etc/systemd/system/logrotate.timer.d/60-bounded-logs.conf"
cp "$RETENTION_CALLS" "$TEST_DIR/first-calls"
configure_log_retention
cmp "$RETENTION_CALLS" "$TEST_DIR/first-calls"
# An invalid transformed policy must preserve files and avoid service changes.
cp "$TEST_DIR/original" "$policy"
export RETENTION_BAD_POLICY=1
if configure_log_retention; then
  printf 'FAIL: invalid policy accepted\n' >&2
  exit 1
fi
cmp "$TEST_DIR/original" "$policy"
[[ "$(rg -c '^systemctl ' "$RETENTION_CALLS")" == 3 ]]
! detect_log_retention
# Validate the actual transformed grammar using logrotate's side-effect-free debug mode.
mkdir -p "$TEST_DIR/log"
awk -f "$CONFIG_DIR/logging/bound-rsyslog.awk" "$TEST_DIR/original" | sed "s@/var/log/@$TEST_DIR/log/@g" > "$TEST_DIR/bounded-policy"
printf 'su %s %s\ninclude %s\n' "$(id -un)" "$(id -gn)" "$TEST_DIR/bounded-policy" > "$TEST_DIR/validation"
"$REAL_LOGROTATE" --debug -s "$TEST_DIR/debug-state" "$TEST_DIR/validation" > "$TEST_DIR/debug-output" 2>&1
cat "$TEST_DIR/debug-output"
rg -q 'Handling 1 logs' "$TEST_DIR/debug-output"
[[ ! -e "$TEST_DIR/debug-state" ]]
source "$SCRIPT_DIR/installer/components.sh"
[[ "${ISC_COMPONENTS[*]}" == *'log_retention|Bound system journal and syslog growth|on|configure_log_retention|detect_log_retention'* ]]
listing="$(bash "$SCRIPT_DIR/install.sh" --list-components)"
[[ "$listing" == *$'log_retention\t'* ]]
[[ ! -e "$LOG_RETENTION_ROOT/etc/systemd/journald.conf.d/changed-by-listing" ]]
printf 'PASS: non-root deferral, clean-root install, limits, hooks, backup, idempotence and invalid-policy preservation.\n'
