#!/usr/bin/env bash
#
# oracle_monitor.sh — Oracle DB comprehensive monitoring script
#
# Ported from oracle_monitor.ksh into the Oracle DBA toolkit framework.
# Preserves all check functions and logic; only plumbing changed:
#   - Toolkit libs sourced (logger.sh, oracle_connect.sh, notify.sh)
#   - NOTIFY_EMAIL replaces hardcoded RECIP
#   - LOG_DIR replaces hardcoded LOGDIR
#   - mailx calls replaced with notify_warn / notify_crit
#   - check_filesystem_usage subshell bug fixed
#   - check_resource_limits awk parsing fixed (grep-based)
#   - egrep replaced with grep -E
#   - Per-function oraenv calls removed (ORACLE_HOME set by oracle_connect.sh)
#   - AUTO_RECOMPILE config flag added to check_invalid_objects
#   - BBOARD/SCONNOR institution-specific check removed
#
# Usage: oracle_monitor.sh <DB_NAME>
# Example: oracle_monitor.sh PROD
#
# originated by SCT rdba N.Saini, finetuned by H.Sallans April 2004
# linux'ified by H.Sallans Jan 2012
# 20160620:hs removed references to monitor OEM dbconsole (12c uses DBexpress)
# 2026: ported into Oracle DBA toolkit framework

PATH=/usr/local/bin:$PATH; export PATH

# === Toolkit bootstrap ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# === Parameters and defaults ===
export DATE=$(date +%F_%H%M)
export HOSTNAME=$(hostname)
export ORATAB="/etc/oratab"
export ORACLE_BASE="${ORACLE_BASE:-/u01/app/oracle}"
export SUBJECT="[ALERT] Oracle DB Monitor Issues on $HOSTNAME at $DATE"
export PING_HOST="localhost"

# === Thresholds ===
# THRESHOLD_TABLESPACE_WARN/CRIT, THRESHOLD_ARCHLOG_WARN/CRIT are loaded from
# config/thresholds.conf via oracle_connect.sh.  Local-only thresholds:
export THRESHOLD_FS=80              # % local filesystem
export THRESHOLD_NETFS=95           # % network filesystem
export PING_THRESHOLD_MS=100        # ms
export TNSPING_THRESHOLD_MS=200     # ms

# Use toolkit threshold vars where they match, fall back to local defaults
THRESHOLD_TBS="${THRESHOLD_TABLESPACE_WARN:-80}"
ARCHIVE_THRESHOLD="${THRESHOLD_ARCHLOG_WARN:-80}"

# === Auto-recompile flag ===
# Set AUTO_RECOMPILE=YES in db_config.env to allow utlrp.sql to run automatically.
AUTO_RECOMPILE="${AUTO_RECOMPILE:-NO}"

# ===== Require a DB name parameter =====
if [ -z "$1" ]; then
  echo "Usage: $0 <DB_NAME>"
  echo "Example: $0 TRNG"
  exit 1
fi

export ORACLE_SID="$1"

if ! grep -q "^${ORACLE_SID}:" "$ORATAB"; then
  echo "[ERROR] Database $ORACLE_SID not found in $ORATAB"
  exit 2
fi

export ORACLE_HOME=$(grep "^${ORACLE_SID}:" "$ORATAB" | cut -d':' -f2)
export PATH=$ORACLE_HOME/bin:$PATH

source "${TOOLKIT_ROOT}/lib/logger.sh"
source "${TOOLKIT_ROOT}/lib/oracle_connect.sh"
source "${TOOLKIT_ROOT}/lib/notify.sh"

# LOG_DIR is set by logger.sh; ISSUE_LOG and LOGFILE are local to this script
export ISSUE_LOG="${LOG_DIR}/oracle_monitor_issues_$DATE.tmp"

# Make log file include the DB name
export LOGFILE="${LOG_DIR}/monitor_${ORACLE_SID}_$DATE.log"

# ============================================================
# Check functions
# ============================================================

# Function to check if file systems are writable
check_server_fs_rw_access() {
  echo -e "\n[15] Server Filesystem Read/Write Access Check" | tee -a "$LOGFILE"

  # Skip these pseudo and system filesystems
  EXCLUDE_TYPES="(tmpfs|devtmpfs|proc|sysfs|cgroup|squashfs|overlay|securityfs|debugfs|devpts|mqueue|hugetlbfs|configfs|fuse|boot|sys|var|home)"

  # Get real mount points only
  SERVER_FS=$(mount | grep -vE "$EXCLUDE_TYPES" | awk '{print $3}' | grep -vE '^/$' | sort -u)

  for fs in $SERVER_FS; do
    TEST_FILE="$fs/.rw_test_$$"
    if [ ! -d "$fs" ]; then
      echo "[WARN] Skipping non-existent: $fs" | tee -a "$LOGFILE"
      echo "[FS] Filesystem $fs does not exist." >> "$ISSUE_LOG"
      continue
    fi

    # Check read access
    if [ ! -r "$fs" ]; then
      echo "[ALERT] $fs is NOT readable!" | tee -a "$LOGFILE"
      echo -e "\n[FS] Filesystem $fs is NOT readable." >> "$ISSUE_LOG"
      continue
    fi

    # Check write access
    touch "$TEST_FILE" 2>/dev/null
    if [ $? -eq 0 ]; then
      echo "[OK] $fs is readable and writable." | tee -a "$LOGFILE"
      rm -f "$TEST_FILE"
    else
      echo "[ALERT] $fs is readable but NOT writable (may be read-only)." | tee -a "$LOGFILE"
      echo -e "\n[FS] Filesystem $fs is NOT writable (read-only?)." >> "$ISSUE_LOG"
    fi
  done
}

# Function to check for network issues using ping
check_ping() {
    local tmpfile
    tmpfile=$(mktemp)
    local host="$1"
    local threshold="$2"
    local logfile="$3"
    local issue_log="$4"

    local ping_out ping_rtt

    # Run ping quietly for 3 packets
    ping_out=$(ping -c 3 -q "$host" 2>&1)

    # Extract average RTT (integer, no decimals)
    ping_rtt=$(echo "$ping_out" | awk -F'/' '/rtt/ {avg=$5; sub(/\..*/, "", avg); print avg}')

    if [[ -n "$ping_rtt" ]]; then
        echo -e "\n[16] Ping Avg RTT (Round Trip Time) to $host: ${ping_rtt}ms" | tee -a "$logfile"
        if (( ping_rtt > threshold )); then
            local body="[PING] Slow ping response: ${ping_rtt}ms (Threshold: ${threshold}ms)"
            echo "$body" >> "$issue_log"
            notify_warn "$host Ping RTT High" "$body"
        fi
    else
        local body="[PING] Ping to $host failed or no data"
        echo -e "\n[PING] Failed to retrieve ping response" | tee -a "$logfile"
        echo "$body" >> "$issue_log"
        notify_crit "$host Ping Failed" "$body"
    fi
    rm -f "$tmpfile"
}

# Function: Check if database is up (PMON process)
check_database_up() {
    local oracle_sid="$1"
    local logfile="$2"
    local issue_log="$3"

    echo -e "\n[DB CHECK] Checking if database $oracle_sid is up" | tee -a "$logfile"

    if ps -ef | grep "[p]mon_$oracle_sid" > /dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') $oracle_sid: Database PMON process is running." | tee -a "$logfile"
    else
        local msg_date
        msg_date=$(date '+%Y-%m-%d %H:%M:%S')
        local body="$msg_date [ALERT] Database: $oracle_sid - PMON process not running!"
        echo "$msg_date [DB DOWN] Database $oracle_sid PMON process not found!" >> "$issue_log"
        notify_crit "Database $oracle_sid DOWN" "$body"
    fi
}

# Function: Check if listener is up
check_listener_up() {
    local listener_name="$1"
    local logfile="$2"
    local issue_log="$3"

    echo -e "\n[LISTENER CHECK] Checking if listener $listener_name is up" | tee -a "$logfile"

    if ps -ef | grep "[t]nslsnr" | grep -iw "$listener_name" > /dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Listener $listener_name: process is running." | tee -a "$logfile"
    else
        local msg_date
        msg_date=$(date '+%Y-%m-%d %H:%M:%S')
        local body="$msg_date [ALERT] Listener: $listener_name - process not running!"
        echo "$msg_date [LISTENER DOWN] Listener $listener_name not found!" >> "$issue_log"
        notify_crit "Listener $listener_name DOWN" "$body"
    fi
}

# Function: Check the job_queue_process in the database
check_job_queue_processes() {
    local tmpfile
    tmpfile=$(mktemp)

    sqlplus -s / as sysdba <<EOF > "$tmpfile"
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT value FROM v\$parameter
WHERE name = 'job_queue_processes';
EXIT;
EOF

    jq_value=$(tr -d '[:space:]' < "$tmpfile")

    if [ -z "$jq_value" ] || [ "$jq_value" -eq 0 ]; then
        local body="Parameter job_queue_processes is disabled or set to 0 (current: ${jq_value:-NULL})"
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ALERT] $ORACLE_SID: $body" \
            | tee -a "$LOGFILE" >> "$ISSUE_LOG"
        notify_warn "$ORACLE_SID job_queue_processes Disabled" "$body"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') $ORACLE_SID: job_queue_processes is set to $jq_value" >> "$LOGFILE"
    fi

    rm -f "$tmpfile"
}

# Check if the database is encrypted.
check_database_encryption() {
    local logfile="$1"
    local issue_log="$2"

    echo -e "\n[Wallet Status] Checking Oracle Wallet status (CDB/PDB aware)" | tee -a "$logfile"

    local wallet_status
    wallet_status=$(sqlplus -s / as sysdba <<EOF
set pages 0 lines 250 feedback off heading off
col name for a25
SELECT b.name || ': ' || a.status
FROM v\$encryption_wallet a
JOIN v\$containers b ON a.con_id = b.con_id
WHERE b.name NOT IN ('PDB\$SEED');
exit;
EOF
)

    local all_open=1
    local alerts=""

    while IFS= read -r line; do
        local status=$(echo "$line" | awk -F': ' '{print $2}')
        local pdb=$(echo "$line" | awk -F': ' '{print $1}')
        if [[ "$status" != "OPEN" ]]; then
            all_open=0
            alerts+="Wallet NOT OPEN in $pdb: $status\n"
        fi
    done <<< "$wallet_status"

    # Log statuses
    echo "$wallet_status" >> "$logfile"

    if [[ $all_open -eq 0 ]]; then
        local body
        body=$(printf "Some wallets are not open:\n%b" "$alerts")
        echo "$(date '+%Y-%m-%d %H:%M:%S') [WALLET_ALERT] $body" >> "$issue_log"
        notify_crit "Oracle Wallet not open in some CDB/PDB" "$body"
    fi
}

# Check if all tablespaces are encrypted.
check_tablespace_encryption() {
    local tmpfile
    tmpfile=$(mktemp)

    sqlplus -s / as sysdba <<EOF > "$tmpfile"
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT tablespace_name
FROM dba_tablespaces
WHERE encrypted = 'NO';
EXIT;
EOF

    if [ -s "$tmpfile" ]; then
        local body
        body=$(cat "$tmpfile")
        echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') [ALERT] $ORACLE_SID: Unencrypted tablespaces found:" | tee -a "$LOGFILE" >> "$ISSUE_LOG"
        cat "$tmpfile" | tee -a "$LOGFILE" >> "$ISSUE_LOG"
        notify_crit "$ORACLE_SID Unencrypted Tablespaces" "Unencrypted tablespaces found:\n$body"
    else
        echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') $ORACLE_SID: All tablespaces are encrypted." >> "$LOGFILE"
    fi

    rm -f "$tmpfile"
}

# Function to check non autoextensible tablespaces
check_autoextend() {
    local tmpfile
    tmpfile=$(mktemp)

    sqlplus -s / as sysdba <<EOF > "$tmpfile"
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT tablespace_name || ' - ' || file_name
FROM dba_data_files
WHERE autoextensible = 'NO';
EXIT;
EOF

    if [ -s "$tmpfile" ]; then
        local body
        body=$(cat "$tmpfile")
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: Non-autoextensible datafiles detected in $ORACLE_SID:" >> "$LOGFILE"
        cat "$tmpfile" >> "$LOGFILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') $ORACLE_SID: Non-autoextensible datafiles found:" >> "$ISSUE_LOG"
        cat "$tmpfile" >> "$ISSUE_LOG"
        notify_warn "$ORACLE_SID Non-autoextensible datafiles detected" "$body"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') $ORACLE_SID: All datafiles are autoextensible." >> "$LOGFILE"
    fi

    rm -f "$tmpfile"
}

# Function to check file system usage
# Bug fixed: alert_found was set inside a pipe subshell; rewritten with process substitution
check_filesystem_usage() {
    local alert_found=0
    local tmpfile
    tmpfile=$(mktemp)

    echo -e "\n[14] Filesystem Usage (> $THRESHOLD_FS% local, > $THRESHOLD_NETFS% network)" | tee -a "$LOGFILE"

    while IFS= read -r line; do
        local usage mountpoint fstype threshold

        usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
        mountpoint=$(echo "$line" | awk '{print $6}')
        fstype=$(df -T "$mountpoint" 2>/dev/null | awk 'NR==2 {print $2}')

        # Decide which threshold to apply
        if echo "$fstype" | grep -qE "^(nfs|nfs4|cifs|smbfs|fuse\.sshfs|fuse)$"; then
            threshold=$THRESHOLD_NETFS
        else
            threshold=$THRESHOLD_FS
        fi

        if [ "$usage" -gt "$threshold" ]; then
            alert_found=1
            echo "[ALERT] FS usage on $mountpoint ($fstype): $usage% > $threshold%" | tee -a "$LOGFILE" | tee -a "$tmpfile"
            echo "[FILESYSTEM] High usage on $mountpoint ($fstype): $usage%" >> "$ISSUE_LOG"
        fi
    done < <(df -hP | awk 'NR>1')

    # If any alert found, send notification
    if [ "$alert_found" -eq 1 ]; then
        notify_warn "Filesystem usage issue on $HOSTNAME ($ORACLE_SID)" "$(cat "$tmpfile")"
    fi

    rm -f "$tmpfile"
}

# Check if the database is running in archive log mode
check_archivelog_enabled() {
    local tmpfile
    tmpfile=$(mktemp)

    sqlplus -s / as sysdba <<EOF > "$tmpfile"
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
ARCHIVE LOG LIST;
EXIT;
EOF

    if grep -q "Archive Mode" "$tmpfile" && grep -q "Enabled" "$tmpfile"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') $ORACLE_SID: ARCHIVELOG mode is enabled." >> "$LOGFILE"
    else
        local body="ARCHIVELOG mode is NOT enabled"
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ALERT] $ORACLE_SID: $body" \
            | tee -a "$LOGFILE" >> "$ISSUE_LOG"
        notify_warn "$ORACLE_SID ARCHIVELOG Disabled" "$body"
    fi

    rm -f "$tmpfile"
}

# Check if the database has flashback option enabled
# (commented out in main body — function preserved for future use)
check_flashback_enabled() {
    local tmpfile
    tmpfile=$(mktemp)

    sqlplus -s / as sysdba <<EOF > "$tmpfile"
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT flashback_on FROM v\$database;
EXIT;
EOF

    flashback_status=$(tr -d '[:space:]' < "$tmpfile")

    if [ "$flashback_status" = "YES" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') $ORACLE_SID: Flashback Database is enabled." >> "$LOGFILE"
    else
        local body="Flashback Database is NOT enabled (status: $flashback_status)"
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ALERT] $ORACLE_SID: $body" \
            | tee -a "$LOGFILE" >> "$ISSUE_LOG"
        notify_warn "$ORACLE_SID Flashback Disabled" "$body"
    fi

    rm -f "$tmpfile"
}

# (commented out in main body — function preserved for future use)
check_users_in_system_tablespaces() {
    local tmpfile
    tmpfile=$(mktemp)

    sqlplus -s / as sysdba <<EOF > "$tmpfile"
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT DISTINCT owner || ' -> ' || tablespace_name
FROM dba_segments
WHERE tablespace_name IN ('SYSTEM','SYSAUX')
  AND owner NOT IN (
    'SYS','SYSTEM','OUTLN','DBSNMP','SYSMAN','AUDSYS','WMSYS','APPQOSSYS',
    'GSMADMIN_INTERNAL','ORDPLUGINS','ORDDATA','ORDSYS','MDSYS','LBACSYS','OLAPSYS',
    'XDB','SI_INFORMTN_SCHEMA','ANONYMOUS','CTXSYS','EXFSYS','DIP','APEX_040000','APEX_050000',
    'APEX_PUBLIC_USER','FLOWS_FILES','FLOWS_30000','FLOWS_040000','FLOWS_050000',
    'SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','OJVMSYS','REMOTE_SCHEDULER_AGENT',
    'GSMCATUSER','GSMUSER','DVSYS','DVF','PUBLIC','ORACLE_OCM','C##ORACLE_OCM',
    'XS$NULL','LBACSYS','TSMSYS','C##XS$NULL'
  )
ORDER BY 1;
EXIT;
EOF

    if [ -s "$tmpfile" ]; then
        local body
        body=$(cat "$tmpfile")
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ALERT] $ORACLE_SID: Non-system schemas have objects in SYSTEM/SYSAUX tablespaces." \
            | tee -a "$LOGFILE" >> "$ISSUE_LOG"
        cat "$tmpfile" >> "$ISSUE_LOG"
        notify_warn "$ORACLE_SID Schemas in SYSTEM/SYSAUX tablespaces" "$body"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') $ORACLE_SID: No unauthorized objects in SYSTEM/SYSAUX tablespaces." >> "$LOGFILE"
    fi

    rm -f "$tmpfile"
}

check_tnsping() {
    local oracle_sid="$1"
    local logfile="$2"
    local issue_log="$3"
    local threshold="$4"

    # ORACLE_HOME already set by oracle_connect.sh — no per-function oraenv needed

    local tmpfile
    tmpfile=$(mktemp)

    # Run TNSPING
    local tns_out tns_time
    tns_out=$(tnsping "$oracle_sid" 2>&1)
    tns_time=$(echo "$tns_out" | grep 'OK (' | sed -n 's/.*OK (\([0-9]*\) msec).*/\1/p')

    if [[ -n "$tns_time" ]]; then
        echo -e "\n[TNSPING] Response time: ${tns_time}ms" | tee -a "$logfile"
        if (( tns_time > threshold )); then
            local body="[TNSPING] Slow TNS response for $oracle_sid: ${tns_time}ms (Threshold: ${threshold}ms)"
            echo "$body" >> "$issue_log"
            notify_warn "$oracle_sid Slow TNSPING" "$body"
        fi
    else
        local body="[TNSPING] $oracle_sid failed tnsping check"$'\n'"$tns_out"
        echo -e "\n[TNSPING] Failed to connect to $oracle_sid or no timing found" | tee -a "$logfile"
        echo "$body" >> "$issue_log"
        notify_crit "$oracle_sid TNSPING Failure" "$body"
    fi

    rm -f "$tmpfile"
}

check_alert_log() {
    local oracle_sid="$1"
    local logfile="$2"
    local issue_log="$3"
    local alert_log="$4"

    # ORACLE_HOME already set by oracle_connect.sh — no per-function oraenv needed

    local tmpfile
    tmpfile=$(mktemp)

    if [[ -z "$alert_log" ]]; then
        local body="No alert log found for $oracle_sid"
        echo "[ALERT LOG] Could not find alert log for $oracle_sid" | tee -a "$logfile"
        echo "[ALERT LOG] No alert log found for $oracle_sid" >> "$issue_log"
        notify_warn "$oracle_sid Alert Log Missing" "$body"
        rm -f "$tmpfile"
        return
    fi

    # Search last 50 lines for critical Oracle errors
    local errors
    # Temporarily skip ORA-00942 for TRNG until the table issue is resolved
    if [ "$oracle_sid" = "TRNG" ]; then
      errors=$(tail -50 "$alert_log" | grep -E "ORA-|ERROR|FATAL|PANIC" | grep -Ev "ORA-3136|ORA-00060|KUP-04040|TNS-|ORA-00942")
    else
      errors=$(tail -50 "$alert_log" | grep -E "ORA-|ERROR|FATAL|PANIC" | grep -Ev "ORA-3136|ORA-00060|KUP-04040|TNS-")
    fi

    if [[ -n "$errors" ]]; then
        echo "[ALERT LOG] Issues found in alert log for $oracle_sid:" | tee -a "$logfile"
        echo "$errors" | tee -a "$logfile"
        local body="[ALERT LOG] Problems detected in $oracle_sid alert log:"$'\n\n'"$errors"
        echo "$body" >> "$issue_log"
        notify_warn "$oracle_sid Alert Log Errors" "$body"
    else
        echo "[ALERT LOG] No new critical errors in $oracle_sid alert log" | tee -a "$logfile"
    fi

    rm -f "$tmpfile"
}

check_resource_usage() {
    local logfile="$1"
    local issue_log="$2"
    local tmpfile tmpalert
    tmpfile=$(mktemp)
    tmpalert=$(mktemp)
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "\n[4] Process/Session Limits" | tee -a "$logfile"

    sqlplus -s / as sysdba <<EOF > "$tmpfile"
set pages 100
set lines 200
col resource_name for a20
select resource_name, current_utilization, limit_value
from v\$resource_limit
where resource_name in ('processes','sessions');
exit;
EOF

    # Append SQL results to logfile
    cat "$tmpfile" >> "$logfile"

    # Prepare alert lines if usage > 90%
    awk -v now="$now" -v sid="$ORACLE_SID" '
         NR>1 && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ {
             usage = ($2 / $3) * 100
             if (usage > 90) {
                 printf "%s %s: [ALERT] High %s usage: %d/%d (%.0f%%)\n", \
                        now, sid, $1, $2, $3, usage
             }
         }' "$tmpfile" | tee -a "$issue_log" > "$tmpalert"

    if [[ -s "$tmpalert" ]]; then
        notify_warn "Database $ORACLE_SID Resource Usage High" "$(cat "$tmpalert")"
    fi

    rm -f "$tmpfile" "$tmpalert"
}

check_fra_usage() {
    local logfile="$1"
    local issue_log="$2"
    local tmpfile
    tmpfile=$(mktemp)

    echo -e "\n[5] Fast Recovery Area (FRA) / Archive Usage" | tee -a "$logfile"

    # Get FRA details
    sqlplus -s / as sysdba <<EOF >> "$logfile"
    set pages 100 lines 200
    col size_mb for 999,999
    col used_mb for 999,999
    col reclaimable_mb for 999,999
    col pct_used for 999.99
    SELECT
        SPACE_LIMIT / 1024 / 1024 AS size_mb,
        SPACE_USED / 1024 / 1024 AS used_mb,
        SPACE_RECLAIMABLE / 1024 / 1024 AS reclaimable_mb,
        ROUND(SPACE_USED * 100 / SPACE_LIMIT, 2) AS pct_used,
        NUMBER_OF_FILES
    FROM
        V\$RECOVERY_FILE_DEST;
    exit;
EOF

    # Get FRA % usage
    FRA_PCT=$(sqlplus -s / as sysdba <<EOF
    set head off feedback off pages 0
    SELECT ROUND(SPACE_USED * 100 / SPACE_LIMIT, 2)
    FROM V\$RECOVERY_FILE_DEST;
    exit;
EOF
    )

    FRA_PCT=$(echo "$FRA_PCT" | xargs | cut -d"." -f1)

    if [[ "$FRA_PCT" =~ ^[0-9]+$ && "$FRA_PCT" -gt "$ARCHIVE_THRESHOLD" ]]; then
        local body="$(date '+%Y-%m-%d %H:%M:%S') $ORACLE_SID: [FRA] Archive/FRA space usage is high: ${FRA_PCT}% (Threshold: ${ARCHIVE_THRESHOLD}%)"
        echo "$body" | tee -a "$issue_log" > "$tmpfile"
        notify_warn "$ORACLE_SID FRA Usage High" "$body"
    fi

    rm -f "$tmpfile"
}

check_blocking_sessions() {
    local logfile="$1"
    local issue_log="$2"
    local tmpfile
    tmpfile=$(mktemp)

    echo -e "\n[6] Blocking Sessions (ROOT)" | tee -a "$logfile"

    sqlplus -s / as sysdba <<EOF > "$tmpfile"
SET HEAD OFF FEEDBACK OFF
SELECT s1.username || ' blocks ' || s2.username
FROM   v\$lock l1, v\$session s1, v\$lock l2, v\$session s2
WHERE  s1.sid = l1.sid
  AND  s2.sid = l2.sid
  AND  l1.block = 1
  AND  l2.request > 0
  AND  l1.id1 = l2.id1
  AND  l1.id2 = l2.id2;
EOF

    if [ -s "$tmpfile" ]; then
        {
            echo "$(date '+%Y-%m-%d %H:%M:%S') [ALERT] Database: $ORACLE_SID Blocking sessions detected"
            cat "$tmpfile"
        } | tee -a "$logfile" >> "$issue_log"
        notify_warn "$ORACLE_SID Blocking Sessions Detected" "$(cat "$tmpfile")"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') $ORACLE_SID: No blocking sessions." | tee -a "$logfile"
    fi

    rm -f "$tmpfile"
}

check_tablespace_usage() {
    local logfile="$1"
    local issue_log="$2"
    local threshold="$3"

    echo -e "\n[10] Checking for Tablespace Usage" | tee -a "$logfile"

    local ts

    ts=$(sqlplus -s / as sysdba <<EOF
set pages 0 lines 200 feedback off verify off heading off echo off
-- Regular tablespaces (exclude UNDO)
SELECT tablespace_name || ' - Used: ' ||
       ROUND(used_percent,2) || '%'
FROM dba_tablespace_usage_metrics
WHERE used_percent > $threshold;
EXIT;
EOF
)

    ts=$(echo "$ts" | sed '/^ *$/d')

    if [[ -n "$ts" ]]; then
        local msg_date
        msg_date=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$msg_date [TABLESPACE] $ORACLE_SID high usage:" >> "$issue_log"
        echo "$ts" >> "$issue_log"
        notify_warn "$ORACLE_SID Tablespace Usage" "$msg_date [ALERT] Database: $ORACLE_SID - High Tablespace Usage"$'\n\n'"$ts"
    fi

    echo "$ts" >> "$logfile"
}

check_invalid_objects() {
    local logfile="$1"
    local issue_log="$2"

    echo -e "\n[11] Checking for Invalid Objects" | tee -a "$logfile"

    # Skip validation if ORACLE_SID=DEVL
    if [[ "$ORACLE_SID" == "DEVL" ]]; then
        echo "Skipping invalid objects check for $ORACLE_SID" | tee -a "$logfile"
        return 0
    fi

    # Schema CCC omitted temporarily
    local invalid
    invalid=$(sqlplus -s / as sysdba <<EOF
    set pages 0 lines 200 feedback off verify off heading off echo off
    col owner for a20
    col object_type for a30
    whenever sqlerror continue
    select owner, object_type, count(*) from dba_objects
    where status='INVALID' and owner<>'CCC'
    group by owner, object_type;
    exit;
EOF
    )

    # Remove empty lines
    invalid=$(echo "$invalid" | sed '/^ *$/d')

    if [[ -n "$invalid" ]]; then
        local msg_date
        msg_date=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$msg_date [INVALID_OBJECTS] Found in $ORACLE_SID:" >> "$issue_log"
        echo "$invalid" >> "$issue_log"

        # Auto-recompile only if explicitly enabled via config
        if [[ "${AUTO_RECOMPILE}" == "YES" ]]; then
            sqlplus -s / as sysdba <<EOF
    @?/rdbms/admin/utlrp.sql
EOF
        fi

        # Send alert
        notify_warn "$ORACLE_SID Invalid Objects" "$msg_date [ALERT] Database: $ORACLE_SID - Invalid objects found"$'\n\n'"$invalid"
    fi

    echo "$invalid" >> "$logfile"
}

check_long_running_queries() {
    local logfile="$1"
    local issue_log="$2"
    local threshold_min=30

    echo -e "\n[14] Checking for Long-Running Queries" | tee -a "$logfile"

    local queries
    queries=$(sqlplus -s / as sysdba <<EOF
    set pages 0 lines 200 feedback off heading off echo off
    col username for a20
    col sql_id for a15
    col opname for a30
    select sid, serial#, username, sql_id, opname,
           round(elapsed_seconds/60) as elapsed_min
    from v\$session_longops
    where sofar <> totalwork
      and elapsed_seconds/60 > $threshold_min;
    exit;
EOF
    )

    queries=$(echo "$queries" | sed '/^ *$/d')

    if [[ -n "$queries" ]]; then
        local msg_date=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$msg_date [LONG_RUNNING_QUERIES] Found in $ORACLE_SID:" >> "$issue_log"
        echo "$queries" >> "$issue_log"
        notify_warn "$ORACLE_SID Long Running Queries" "$msg_date [ALERT] Long-running queries detected in $ORACLE_SID"$'\n\n'"$queries"
    fi

    echo "$queries" >> "$logfile"
}

check_listener_log_errors() {
    local logfile="$1"
    local issue_log="$2"
    local sid="${3,,}"
    local listener_log="$ORACLE_BASE/diag/tnslsnr/$(hostname)/lsnr_$sid/alert/log.xml"

    echo -e "\n[15] Checking Listener Log for Errors" | tee -a "$logfile"

    if [[ -f "$listener_log" ]]; then
        local errors
        errors=$(tail -100 "$listener_log" | grep -E "ORA-|TNS-" | tail -20)

        if [[ -n "$errors" ]]; then
            local msg_date=$(date '+%Y-%m-%d %H:%M:%S')
            echo "$msg_date [LISTENER_LOG_ERRORS] Found in $ORACLE_SID:" >> "$issue_log"
            echo "$errors" >> "$issue_log"
            notify_warn "$ORACLE_SID Listener Errors" "$msg_date [ALERT] Listener errors detected for $ORACLE_SID"$'\n\n'"$errors"
        fi

        echo "$errors" >> "$logfile"
    else
        echo "Listener log not found: $listener_log" | tee -a "$logfile"
    fi
}

check_redo_log_switches() {
    local logfile="$1"
    local issue_log="$2"
    local threshold=20

    echo -e "\n[16] Checking Redo Log Switch Frequency" | tee -a "$logfile"

    local switches
    switches=$(sqlplus -s / as sysdba <<EOF
    set pages 0 lines 200 feedback off verify off heading off echo off
    select to_char(first_time,'YYYY-MM-DD') as day,
           to_char(first_time,'HH24') as hour,
           count(*) as switches
    from v\$log_history
    where first_time > sysdate - 1
    group by to_char(first_time,'YYYY-MM-DD'), to_char(first_time,'HH24')
    order by day, hour;
    exit;
EOF
    )

    switches=$(echo "$switches" | sed '/^ *$/d')

    local alerts=""
    while read -r day hour count; do
        hour=$((10#$hour))
        # Skip 17h00-19h00 (hours 17 and 18)
        if [[ "$hour" -ge 17 && "$hour" -lt 19 ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') [REDO_LOG_SWITCHES] Skipped hour $day $hour" >> "$logfile"
            continue
        fi

        if [[ -n "$count" && "$count" =~ ^[0-9]+$ ]]; then
            avg=$(( 60 / count ))
            if (( avg < threshold )); then
                alerts+="- $day $hour:00-$hour:59 → $count switches (~$avg min apart)\n"
            fi
        fi
    done <<< "$switches"

    if [[ -n "$alerts" ]]; then
        local msg_date
        msg_date=$(date '+%Y-%m-%d %H:%M:%S')
        echo -e "$msg_date [REDO_LOG_SWITCH_ALERT] $ORACLE_SID: Frequent switches (< $threshold min avg):" >> "$issue_log"
        echo -e "$alerts" >> "$issue_log"
        local body
        body=$(printf "%s [ALERT] Database: %s - Frequent redo log switches detected\n\nThe following hours had more switches than recommended:\n\n%b" \
               "$msg_date" "$ORACLE_SID" "$alerts")
        notify_warn "$ORACLE_SID Frequent Redo Log Switches" "$body"
    fi
}

# (commented out in main body — function preserved for future use)
check_db_growth() {
    local logfile="$1"
    local issue_log="$2"

    echo -e "\n[--] Checking Database Growth Trends" | tee -a "$logfile"

    local growth
    growth=$(sqlplus -s / as sysdba <<EOF
    set pages 0 lines 200 feedback off heading off echo off
    col owner for a20
    select owner, round(sum(bytes)/1024/1024) as size_mb
    from dba_segments
    group by owner
    order by size_mb desc fetch first 10 rows only;
    exit;
EOF
    )

    growth=$(echo "$growth" | sed '/^ *$/d')

    if [[ -n "$growth" ]]; then
        local msg_date=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$msg_date [DB_GROWTH] Top 10 schemas in $ORACLE_SID:" >> "$issue_log"
        echo "$growth" >> "$issue_log"
    fi

    echo "$growth" >> "$logfile"
}

# (commented out in main body — function preserved for future use)
check_security_users() {
    local logfile="$1"
    local issue_log="$2"

    echo -e "\n[--] Checking User Security" | tee -a "$logfile"

    local sec_checks
    sec_checks=$(sqlplus -s / as sysdba <<EOF
    set pages 0 lines 200 feedback off heading off echo off
    col username for a20
    -- Default passwords
    select 'DefaultPwd' check_type, username
    from dba_users_with_defpwd
    union all
    -- Locked/expired users
    select 'LockedOrExpired', username
    from dba_users
    where account_status like 'LOCKED%' or account_status like 'EXPIRED%'
    union all
    -- DBA/system-level users
    select 'DBA_Priv', grantee
    from dba_role_privs
    where granted_role='DBA';
    exit;
EOF
    )

    sec_checks=$(echo "$sec_checks" | sed '/^ *$/d')

    if [[ -n "$sec_checks" ]]; then
        local msg_date=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$msg_date [SECURITY_CHECKS] Issues in $ORACLE_SID:" >> "$issue_log"
        echo "$sec_checks" >> "$issue_log"
    fi

    echo "$sec_checks" >> "$logfile"
}

# Bug fixed: awk -F',' replaced with grep-based parsing (SQL output is space-delimited)
check_resource_limits() {
    local logfile="$1"
    local issue_log="$2"

    echo -e "\n[17] Checking Memory Resource Usage (SGA/PGA)" | tee -a "${logfile}"

    local mem
    mem=$(sqlplus -s / as sysdba <<EOF
    set pages 0 lines 200 feedback off heading off echo off
    SELECT 'PGA Total Allocated', ROUND(value/1024/1024) FROM v\$pgastat WHERE name='total PGA allocated'
    UNION ALL
    SELECT 'PGA Used for Workareas', ROUND(value/1024/1024) FROM v\$pgastat WHERE name='total PGA used for auto workareas'
    UNION ALL
    SELECT 'PGA Cache Hit %', ROUND(value) FROM v\$pgastat WHERE name='cache hit percentage'
    UNION ALL
    SELECT 'PGA Over Limit Count', value FROM v\$pgastat WHERE name='over allocation count'
    UNION ALL
    SELECT 'Shared Pool Free', ROUND(bytes/1024/1024) FROM v\$sgastat WHERE pool='shared pool' AND name='free memory'
    UNION ALL
    SELECT 'Large Pool Free', ROUND(bytes/1024/1024) FROM v\$sgastat WHERE pool='large pool' AND name='free memory'
    UNION ALL
    SELECT 'Buffer Cache Hit Ratio',
        ROUND(
            (
                (
                    (SELECT VALUE FROM v\$sysstat WHERE name='db block gets from cache') +
                    (SELECT VALUE FROM v\$sysstat WHERE name='consistent gets from cache') -
                    (SELECT VALUE FROM v\$sysstat WHERE name='physical reads')
                ) /
                (
                    (SELECT VALUE FROM v\$sysstat WHERE name='db block gets from cache') +
                    (SELECT VALUE FROM v\$sysstat WHERE name='consistent gets from cache')
                )
            ) * 100
        )
    FROM dual;
    exit;
EOF
    )

    mem=$(echo "${mem}" | sed '/^ *$/d')

    # Parse by label using grep — output is space-delimited with multi-word labels
    local pga_total pga_used pga_hit pga_over shared_free large_free cache_hit

    pga_total=$(echo "${mem}" | grep 'PGA Total Allocated' | awk '{print $NF}')
    pga_used=$(echo "${mem}" | grep 'PGA Used for Workareas' | awk '{print $NF}')
    pga_hit=$(echo "${mem}" | grep 'PGA Cache Hit %' | awk '{print $NF}')
    pga_over=$(echo "${mem}" | grep 'PGA Over Limit Count' | awk '{print $NF}')
    shared_free=$(echo "${mem}" | grep 'Shared Pool Free' | awk '{print $NF}')
    large_free=$(echo "${mem}" | grep 'Large Pool Free' | awk '{print $NF}')
    cache_hit=$(echo "${mem}" | grep 'Buffer Cache Hit Ratio' | awk '{print $NF}')

    local alerts=""
    if [[ -n "${pga_total}" && -n "${pga_used}" && "${pga_total}" -gt 0 ]]; then
        local percent_used
        percent_used=$(echo "${pga_used} * 100 / ${pga_total}" | bc)
        if [[ "${percent_used}" -ge 90 ]]; then
            alerts+="High PGA usage: ${pga_used} MB / ${pga_total} MB (>90%)\n"
        fi
    fi

    if [[ -n "${pga_hit}" && "${pga_hit}" -lt 95 ]]; then
        alerts+="Low PGA cache hit ratio: ${pga_hit}% (<95%)\n"
    fi

    if [[ -n "${pga_over}" && "${pga_over}" -gt 0 ]]; then
        alerts+="PGA over-allocation events: ${pga_over} (work spilled to disk)\n"
    fi

    if [[ -n "${shared_free}" && "${shared_free}" -lt 50 ]]; then
        alerts+="Low Shared Pool free memory: ${shared_free}MB (<50MB)\n"
    fi

    if [[ -n "${large_free}" && "${large_free}" -lt 20 ]]; then
        alerts+="Low Large Pool free memory: ${large_free}MB (<20MB)\n"
    fi

    if [[ -n "${cache_hit}" && "${cache_hit}" -lt 90 ]]; then
        alerts+="Low Buffer Cache Hit Ratio: ${cache_hit}% (<90%)\n"
    fi

    local msg_date
    msg_date=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${msg_date} [RESOURCE_LIMITS] ${ORACLE_SID}:" >> "${logfile}"
    echo "${mem}" >> "${logfile}"

    if [[ -n "${alerts}" ]]; then
        echo "${msg_date} [RESOURCE_ALERT] ${ORACLE_SID}:" >> "${issue_log}"
        echo -e "${alerts}" >> "${issue_log}"
        notify_warn "${ORACLE_SID} Memory Usage (SGA/PGA)" \
            "${msg_date} [ALERT] Database: ${ORACLE_SID} - Memory pressure detected"$'\n'"$(printf '%b' "${alerts}")"
    fi
}

check_invalid_indexes() {
    local logfile="$1"
    local issue_log="$2"

    echo -e "\n[18] Checking for Invalid/Unusable Indexes" | tee -a "$logfile"

    local idx
    idx=$(sqlplus -s / as sysdba <<EOF
    set pages 0 lines 200 feedback off heading off echo off
    col owner for a20
    col index_name for a30
    select owner, index_name, status
    from dba_indexes
    where status='UNUSABLE';
    exit;
EOF
    )

    idx=$(echo "$idx" | sed '/^ *$/d')

    if [[ -n "$idx" ]]; then
        local msg_date=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$msg_date [INVALID_INDEXES] Found in $ORACLE_SID:" >> "$issue_log"
        echo "$idx" >> "$issue_log"
        notify_warn "$ORACLE_SID Unusable Indexes" "$msg_date [ALERT] Unusable indexes detected in $ORACLE_SID"$'\n\n'"$idx"
    fi

    echo "$idx" >> "$logfile"
}

check_user_accounts() {
    local logfile="$1"
    local issue_log="$2"
    local oracle_sid="$3"

    echo -e "\n[USER CHECK] Checking user accounts in $oracle_sid" | tee -a "$logfile"

    # ORACLE_HOME already set by oracle_connect.sh — no per-function oraenv needed

    local tmpfile
    tmpfile=$(mktemp)

    sqlplus -s / as sysdba <<EOF > "$tmpfile"
SET PAGESIZE 100
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON

COL username FORMAT A25
COL account_status FORMAT A30
COL expiry_date FORMAT A20

SELECT u.username,
       u.account_status,
       u.expiry_date
FROM   dba_users u
WHERE  u.username IN (
          SELECT owner
          FROM   dba_objects
          GROUP  BY owner
       )
AND    u.username NOT IN (
        'SYS','SYSTEM','OUTLN','DBSNMP','SYSMAN','AUDSYS','WMSYS','APPQOSSYS','SCOTT','OWBSYS_AUDIT','OWBSYS',
        'GSMADMIN_INTERNAL','ORDPLUGINS','ORDDATA','ORDSYS','MDSYS','LBACSYS','OLAPSYS','CONVERTRE','CONVERT2',
        'XDB','SI_INFORMTN_SCHEMA','ANONYMOUS','CTXSYS','EXFSYS','DIP','APEX_040000','APEX_050000','DBSFWUSER',
        'APEX_PUBLIC_USER','FLOWS_FILES','FLOWS_30000','FLOWS_040000','FLOWS_050000',
        'SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','OJVMSYS','REMOTE_SCHEDULER_AGENT',
        'GSMCATUSER','GSMUSER','DVSYS','DVF','PUBLIC','ORACLE_OCM','C##ORACLE_OCM',
        'XS$NULL','LBACSYS','TSMSYS','C##XS$NULL'
       )
AND   (u.account_status LIKE 'EXPIRED%'
        OR u.account_status LIKE 'LOCKED%'
        OR u.expiry_date <= SYSDATE + 7)
ORDER BY u.expiry_date NULLS LAST;
EXIT;
EOF

    if [[ -s "$tmpfile" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ALERT] Issues found with application users in $oracle_sid:" | tee -a "$logfile"
        cat "$tmpfile" | tee -a "$logfile" >> "$issue_log"
        notify_warn "$oracle_sid User Accounts Expiring/Locked" "$(cat "$tmpfile")"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [USER CHECK] All monitored application users in $oracle_sid are fine." | tee -a "$logfile"
    fi

    rm -f "$tmpfile"
}

# ============================================================
# Main
# ============================================================

# Create log directory if it does not exist (logger.sh does this, but ensure ISSUE_LOG dir is also ready)
mkdir -p "$LOG_DIR"
> "$ISSUE_LOG"

echo "==== Oracle Single-DB Monitoring on $HOSTNAME - $DATE ===="

ALERT_LOG=$(find "$ORACLE_BASE/diag/rdbms" -name "alert_${ORACLE_SID}.log" 2>/dev/null | head -1)

echo -e "\n======== Monitoring ORACLE_SID=$ORACLE_SID ========" | tee -a "$LOGFILE"

# [1] Connectivity
echo -e "\n[1] Connectivity Checks with Timing" | tee -a "$LOGFILE"
check_tnsping "$ORACLE_SID" "$LOGFILE" "$ISSUE_LOG" "$TNSPING_THRESHOLD_MS"
check_database_up "$ORACLE_SID" "$LOGFILE" "$ISSUE_LOG"
check_listener_up "LSNR_$ORACLE_SID" "$LOGFILE" "$ISSUE_LOG"

# [2] Alert Log ORA- Errors
echo -e "\n[2] Alert Log ORA- Errors" | tee -a "$LOGFILE"
check_alert_log "$ORACLE_SID" "$LOGFILE" "$ISSUE_LOG" "$ALERT_LOG"

# === CDB or Non-CDB Detection ===
IS_CDB=$(sqlplus -s / as sysdba <<EOF
  set heading off feedback off
  select cdb from v\$database;
  exit;
EOF
)
IS_CDB=$(echo "$IS_CDB" | xargs)

_run_db_checks() {
  check_job_queue_processes
  echo -e "\n[3] Check if database jobs are enabled" | tee -a "$LOGFILE"
  check_resource_usage "$LOGFILE" "$ISSUE_LOG"
  check_fra_usage "$LOGFILE" "$ISSUE_LOG"
  check_blocking_sessions "$LOGFILE" "$ISSUE_LOG"
  echo -e "\n[7] Checking for non autoextend Tablespaces" | tee -a "$LOGFILE"
  check_autoextend
  echo -e "\n[8] Checking for Database and Tablespace Encryption" | tee -a "$LOGFILE"
  check_database_encryption "$LOGFILE" "$ISSUE_LOG"
  check_tablespace_encryption
  echo -e "\n[9] Checking for users on system or sysaux tablespaces" | tee -a "$LOGFILE"
  #check_users_in_system_tablespaces
  check_tablespace_usage "$LOGFILE" "$ISSUE_LOG" "$THRESHOLD_TBS"
  check_invalid_objects "$LOGFILE" "$ISSUE_LOG"
  echo -e "\n[12] Checking for Database in Archive Log Mode" | tee -a "$LOGFILE"
  check_archivelog_enabled
  echo -e "\n[13] Checking if database has flashback option enabled" | tee -a "$LOGFILE"
  #check_flashback_enabled
  check_long_running_queries "$LOGFILE" "$ISSUE_LOG"
  check_listener_log_errors "$LOGFILE" "$ISSUE_LOG" "$ORACLE_SID"
  FLAGFILE="/tmp/redo_switch_check_$(date +%Y%m%d)"
  if [[ ! -f "$FLAGFILE" ]]; then
     check_redo_log_switches "$LOGFILE" "$ISSUE_LOG"
     touch "$FLAGFILE"
     find /tmp -name 'redo_switch_check_*' -mtime +0 -delete
  fi
  #check_db_growth "$LOGFILE" "$ISSUE_LOG"
  #check_security_users "$LOGFILE" "$ISSUE_LOG"
  check_resource_limits "$LOGFILE" "$ISSUE_LOG"
  check_invalid_indexes "$LOGFILE" "$ISSUE_LOG"
}

if [[ "$IS_CDB" == "NO" ]]; then
  echo -e "\n[INFO] Non-CDB instance. Running checks directly..." | tee -a "$LOGFILE"
  _run_db_checks
else
    echo -e "\n[INFO] CDB detected. Scanning PDBs..." | tee -a "$LOGFILE"
    PDBS=$(sqlplus -s / as sysdba <<EOF
    set pages 0 feedback off heading off
    select name from v\$pdbs where open_mode='READ WRITE';
    exit;
EOF
)

  if [[ -z "$PDBS" ]]; then
    echo "[INFO] No open PDBs found." | tee -a "$LOGFILE"
  else
    for pdb in $PDBS; do
      echo -e "\n------ PDB: $pdb ------" | tee -a "$LOGFILE"
      # Set ORACLE_PDB so oracle_run_sql() from lib/oracle_connect.sh switches container.
      # Note: _run_db_checks uses inline sqlplus / as sysdba heredocs which connect to
      # CDB$ROOT regardless — instance-level V$ checks (FRA, resource usage, blocking)
      # run at root intentionally. PDB-specific DBA_ views return CDB-wide data from root.
      export ORACLE_PDB="$pdb"
      _run_db_checks
      unset ORACLE_PDB
    done
  fi
fi

echo -e "\n======== END of $ORACLE_SID ==========" | tee -a "$LOGFILE"

check_filesystem_usage
check_server_fs_rw_access
check_ping "$PING_HOST" "$PING_THRESHOLD_MS" "$LOGFILE" "$ISSUE_LOG"

# === Send consolidated alert email if issues were found ===
if [[ -s "$ISSUE_LOG" ]]; then
  notify_crit "Oracle DB Monitor Issues on $HOSTNAME at $DATE" "$(cat "$ISSUE_LOG")"
fi

rm -f "$ISSUE_LOG"

exit
