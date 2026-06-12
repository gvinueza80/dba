#!/usr/bin/env bash
# Daily Health Check — Morning Digest
# Runs consolidated proactive checks and emails a summary before business hours.
# Safe: read-only, no changes made to the database.
#
# Usage:   ./daily_health_check.sh <ORACLE_SID> [--dry-run]
# Example: ./daily_health_check.sh CONBI8
#          ./daily_health_check.sh CONBI16 --dry-run
#
# Output:  reports/health/YYYY-MM-DD-<SID>-health.txt
#          Email digest via lib/notify.sh
#
# Schedule: Daily at 07:00 (cron entry in config/crontab.example)
#
# Exit codes: 0 = healthy, 1 = warnings/criticals found, 2 = error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ─── Argument parsing ─────────────────────────────────────────────────────────
DRY_RUN=false
for arg in "$@"; do
  if [[ "$arg" == "--dry-run" ]]; then
    DRY_RUN=true
  elif [[ "$arg" != --* ]]; then
    export ORACLE_SID="$arg"
  fi
done

if [[ -z "${ORACLE_SID:-}" ]]; then
  echo "Usage: $0 <ORACLE_SID> [--dry-run]" >&2
  exit 2
fi

source "${TOOLKIT_ROOT}/lib/logger.sh"
source "${TOOLKIT_ROOT}/lib/oracle_connect.sh"
source "${TOOLKIT_ROOT}/lib/notify.sh"

REPORT_DIR="${TOOLKIT_ROOT}/reports/health"
REPORT_FILE="${REPORT_DIR}/$(date +%Y-%m-%d)-${ORACLE_SID}-health.txt"

if $DRY_RUN; then
  log_info "[DRY RUN] Would run health checks for ${ORACLE_SID}"
  log_info "[DRY RUN] Report would be written to: ${REPORT_FILE}"
  exit 0
fi

oracle_connect_test || { log_error "Cannot connect to Oracle — aborting"; exit 2; }
mkdir -p "$REPORT_DIR"
log_info "Starting daily health check for ${ORACLE_SID}"

# ─── Counters ─────────────────────────────────────────────────────────────────
WARN_COUNT=0
CRIT_COUNT=0

# ─── Helper: flag line ────────────────────────────────────────────────────────
_flag() {
  local level="$1" msg="$2"
  case "$level" in
    CRIT) echo "  [!!!] ${msg}"; CRIT_COUNT=$((CRIT_COUNT + 1)) ;;
    WARN) echo "  [!]   ${msg}"; WARN_COUNT=$((WARN_COUNT + 1)) ;;
    OK)   echo "  [OK]  ${msg}" ;;
    INFO) echo "        ${msg}" ;;
  esac
}

# ─── Check functions ──────────────────────────────────────────────────────────

check_instance_status() {
  echo ""
  echo "━━━ 1. INSTANCE STATUS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local result
  result=$(oracle_run_sql_root "
SELECT
  'STATUS='        || status                                          || '|' ||
  'UPTIME_DAYS='   || TRUNC(SYSDATE - startup_time)                  || '|' ||
  'SGA_GB='        || ROUND(SGA_TARGET/1024/1024/1024,1)             || '|' ||
  'PGA_MB='        || ROUND(pga_aggregate_target/1024/1024)          || '|' ||
  'SESSIONS='      || (SELECT COUNT(*) FROM v\$session WHERE type='USER') || '|' ||
  'MAX_PROCESSES=' || (SELECT value FROM v\$parameter WHERE name='processes')
FROM v\$instance, v\$sga_dynamic_components, v\$parameter p
WHERE component='SGA Target'
  AND p.name='pga_aggregate_target'
  AND rownum=1;" | grep 'STATUS=' | head -1)

  local status uptime sga_gb pga_mb sessions max_proc
  status=$(echo "$result"       | grep -o 'STATUS=[^|]*'        | cut -d= -f2)
  uptime=$(echo "$result"       | grep -o 'UPTIME_DAYS=[^|]*'   | cut -d= -f2)
  sga_gb=$(echo "$result"       | grep -o 'SGA_GB=[^|]*'        | cut -d= -f2)
  pga_mb=$(echo "$result"       | grep -o 'PGA_MB=[^|]*'        | cut -d= -f2)
  sessions=$(echo "$result"     | grep -o 'SESSIONS=[^|]*'      | cut -d= -f2)
  max_proc=$(echo "$result"     | grep -o 'MAX_PROCESSES=[^|]*' | cut -d= -f2)

  local sess_pct=0
  [[ -n "$max_proc" && "$max_proc" -gt 0 ]] && sess_pct=$(( sessions * 100 / max_proc ))

  if [[ "$status" == "OPEN" ]]; then
    _flag OK "Instance is OPEN | Uptime: ${uptime} day(s) | SGA: ${sga_gb}GB | PGA: ${pga_mb}MB"
  else
    _flag CRIT "Instance status: ${status}"
  fi

  if [[ "$sess_pct" -ge "${THRESHOLD_SESSIONS_CRIT:-90}" ]]; then
    _flag CRIT "Sessions: ${sessions} / ${max_proc} (${sess_pct}%) — exceeds critical threshold"
  elif [[ "$sess_pct" -ge "${THRESHOLD_SESSIONS_WARN:-80}" ]]; then
    _flag WARN "Sessions: ${sessions} / ${max_proc} (${sess_pct}%) — exceeds warning threshold"
  else
    _flag OK   "Sessions: ${sessions} / ${max_proc} (${sess_pct}%)"
  fi
}

check_top_wait_events() {
  echo ""
  echo "━━━ 2. TOP 5 WAIT EVENTS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  oracle_run_sql_root "
SELECT RPAD(event,45) || ' | waits: ' || LPAD(total_waits,10) || ' | time(s): ' || LPAD(ROUND(time_waited/100),8)
FROM (
  SELECT event, total_waits, time_waited
  FROM v\$system_event
  WHERE wait_class != 'Idle'
  ORDER BY time_waited DESC
)
WHERE rownum <= 5;" | grep -v '^$' | while IFS= read -r line; do
    _flag INFO "$line"
  done
}

check_tablespace_usage() {
  echo ""
  echo "━━━ 3. TABLESPACE USAGE ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  while IFS='|' read -r ts_name used_pct used_gb total_gb; do
    ts_name=$(echo "$ts_name"   | xargs)
    used_pct=$(echo "$used_pct" | xargs)
    used_gb=$(echo "$used_gb"   | xargs)
    total_gb=$(echo "$total_gb" | xargs)
    [[ -z "$ts_name" ]] && continue

    if [[ "$used_pct" -ge "${THRESHOLD_TABLESPACE_CRIT:-90}" ]]; then
      _flag CRIT "Tablespace ${ts_name}: ${used_pct}% used (${used_gb}GB / ${total_gb}GB)"
    elif [[ "$used_pct" -ge "${THRESHOLD_TABLESPACE_WARN:-80}" ]]; then
      _flag WARN "Tablespace ${ts_name}: ${used_pct}% used (${used_gb}GB / ${total_gb}GB)"
    else
      _flag OK   "Tablespace ${ts_name}: ${used_pct}% used (${used_gb}GB / ${total_gb}GB)"
    fi
  done < <(oracle_run_sql_root "
SELECT
  ts.tablespace_name || '|' ||
  ROUND(used_space * t.block_size / 1024/1024/1024 * 100 /
    NULLIF(tablespace_size * t.block_size / 1024/1024/1024, 0)) || '|' ||
  ROUND(used_space * t.block_size / 1024/1024/1024, 2) || '|' ||
  ROUND(tablespace_size * t.block_size / 1024/1024/1024, 2)
FROM dba_tablespace_usage_metrics ts
JOIN dba_tablespaces t ON ts.tablespace_name = t.tablespace_name
ORDER BY 2 DESC NULLS LAST;" | grep '|')
}

check_failed_scheduler_jobs() {
  echo ""
  echo "━━━ 4. FAILED DBMS_SCHEDULER JOBS (last 24h) ━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local failed
  failed=$(oracle_run_sql_root "
SELECT job_name || ' | status: ' || status || ' | error: ' || error# ||
       ' | started: ' || TO_CHAR(actual_start_date,'YYYY-MM-DD HH24:MI')
FROM dba_scheduler_job_run_details
WHERE status NOT IN ('SUCCEEDED','RUNNING')
  AND actual_start_date > SYSDATE - 1
ORDER BY actual_start_date DESC;" | grep -v '^$' | grep '|')

  if [[ -z "$failed" ]]; then
    _flag OK "No failed scheduler jobs in the last 24 hours"
  else
    while IFS= read -r line; do
      _flag WARN "$line"
    done <<< "$failed"
  fi
}

check_alert_log_errors() {
  echo ""
  echo "━━━ 5. ALERT LOG ORA- ERRORS (last 24h) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local trace_dir alert_log
  trace_dir=$(oracle_run_sql_root "SELECT value FROM v\$diag_info WHERE name='Diag Trace';" | grep -v '^$' | xargs)
  alert_log="${trace_dir}/alert_${ORACLE_SID}.log"

  if [[ ! -f "$alert_log" ]]; then
    _flag WARN "Alert log not found at: ${alert_log}"
    return
  fi

  local cutoff errors
  cutoff=$(date -d '24 hours ago' '+%Y-%m-%d')
  errors=$(awk -v cutoff="$cutoff" '
    /^[0-9]{4}-[0-9]{2}-[0-9]{2}/ { current_date=substr($0,1,10) }
    /ORA-/ && current_date >= cutoff { print }
  ' "$alert_log" 2>/dev/null | grep -v "^$" | sort -u | head -20)

  if [[ -z "$errors" ]]; then
    _flag OK "No ORA- errors in alert log in the last 24 hours"
  else
    local count
    count=$(echo "$errors" | wc -l)
    if echo "$errors" | grep -qE "ORA-00600|ORA-07445|ORA-04031"; then
      _flag CRIT "${count} ORA- error(s) found — including critical internal errors"
    else
      _flag WARN "${count} ORA- error(s) found in alert log"
    fi
    echo "$errors" | while IFS= read -r line; do
      _flag INFO "  $line"
    done
  fi
}

check_rman_backup_age() {
  echo ""
  echo "━━━ 6. RMAN BACKUP STATUS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local age_hours last_backup
  age_hours=$(oracle_run_sql_root "
SELECT TRUNC((SYSDATE - MAX(completion_time)) * 24)
FROM v\$backup_set
WHERE backup_type IN ('D','I')
  AND status = 'AVAILABLE';" | grep -v '^$' | xargs)

  last_backup=$(oracle_run_sql_root "
SELECT TO_CHAR(MAX(completion_time),'YYYY-MM-DD HH24:MI')
FROM v\$backup_set
WHERE backup_type IN ('D','I')
  AND status = 'AVAILABLE';" | grep -v '^$' | xargs)

  if [[ -z "$age_hours" || "$age_hours" == "null" ]]; then
    _flag CRIT "No RMAN backup found"
  elif [[ "$age_hours" -ge "${THRESHOLD_BACKUP_AGE_CRIT:-48}" ]]; then
    _flag CRIT "Last backup: ${last_backup} (${age_hours}h ago) — exceeds critical threshold"
  elif [[ "$age_hours" -ge "${THRESHOLD_BACKUP_AGE_WARN:-24}" ]]; then
    _flag WARN "Last backup: ${last_backup} (${age_hours}h ago) — exceeds warning threshold"
  else
    _flag OK   "Last backup: ${last_backup} (${age_hours}h ago)"
  fi
}

check_invalid_objects() {
  echo ""
  echo "━━━ 7. INVALID OBJECTS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local count
  count=$(oracle_run_sql_root "
SELECT COUNT(*)
FROM dba_objects
WHERE status = 'INVALID'
  AND object_type NOT IN ('SYNONYM','UNDEFINED');" | grep -v '^$' | xargs)

  if [[ -z "$count" || "$count" -eq 0 ]]; then
    _flag OK "No invalid objects"
  elif [[ "$count" -ge "${THRESHOLD_INVALID_OBJECTS_WARN:-1}" ]]; then
    _flag WARN "${count} invalid object(s) found"

    oracle_run_sql_root "
SELECT owner || '.' || object_name || ' (' || object_type || ')'
FROM dba_objects
WHERE status = 'INVALID'
  AND object_type NOT IN ('SYNONYM','UNDEFINED')
ORDER BY owner, object_type, object_name
FETCH FIRST 10 ROWS ONLY;" | grep -v '^$' | while IFS= read -r line; do
      _flag INFO "  $line"
    done
    [[ "$count" -gt 10 ]] && _flag INFO "  ... and $((count - 10)) more"
  fi
}

# ─── Build report ─────────────────────────────────────────────────────────────
{
echo "════════════════════════════════════════════════════════════════════════"
echo " ORACLE DAILY HEALTH CHECK"
echo "════════════════════════════════════════════════════════════════════════"
echo " Database : ${ORACLE_SID}  (IS_CDB=${IS_CDB:-NO})"
echo " Host     : $(hostname)"
echo " Date     : $(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════════════════════════════════"

check_instance_status
check_top_wait_events
check_tablespace_usage
check_failed_scheduler_jobs
check_alert_log_errors
check_rman_backup_age
check_invalid_objects

echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo " SUMMARY"
echo "════════════════════════════════════════════════════════════════════════"
echo "  Critical : ${CRIT_COUNT}"
echo "  Warning  : ${WARN_COUNT}"
echo ""
if [[ "$CRIT_COUNT" -gt 0 ]]; then
  echo "  RESULT: CRITICAL — Immediate attention required."
elif [[ "$WARN_COUNT" -gt 0 ]]; then
  echo "  RESULT: WARNING — Review flagged items."
else
  echo "  RESULT: HEALTHY — All checks passed."
fi
echo "════════════════════════════════════════════════════════════════════════"
} | tee "$REPORT_FILE"

log_info "Report saved to ${REPORT_FILE}"

# ─── Notify ───────────────────────────────────────────────────────────────────
REPORT_BODY="$(cat "$REPORT_FILE")"

if [[ "$CRIT_COUNT" -gt 0 ]]; then
  notify_crit "Daily Health Check — CRITICAL on ${ORACLE_SID}" "$REPORT_BODY"
  exit 1
elif [[ "$WARN_COUNT" -gt 0 ]]; then
  notify_warn "Daily Health Check — WARNING on ${ORACLE_SID}" "$REPORT_BODY"
  exit 1
else
  notify_info "Daily Health Check — HEALTHY on ${ORACLE_SID}" "$REPORT_BODY"
  exit 0
fi
