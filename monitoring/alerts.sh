#!/bin/bash
# Oracle Database Health Check and Alerting Script
# Monitors critical database metrics and generates alerts
# Run via cron: 0 * * * * /path/to/monitoring/alerts.sh (hourly)

set -e

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="${PROJECT_DIR}/audit"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
ALERT_FILE="${LOG_DIR}/alerts.log"
HEALTH_REPORT="${LOG_DIR}/health_report_$(date '+%Y%m%d_%H%M%S').txt"

# Thresholds
TABLESPACE_THRESHOLD=90
ARCHIVE_LOG_THRESHOLD=80
UNDO_USAGE_THRESHOLD=85
INVALID_OBJECTS_THRESHOLD=0

# Initialize
mkdir -p "$LOG_DIR"
touch "$ALERT_FILE"

echo "================================================================================" | tee -a "$ALERT_FILE"
echo "ORACLE DATABASE HEALTH CHECK" | tee -a "$ALERT_FILE"
echo "Timestamp: $TIMESTAMP" | tee -a "$ALERT_FILE"
echo "================================================================================" | tee -a "$ALERT_FILE"

# Check if ORACLE_HOME is set
if [ -z "$ORACLE_HOME" ]; then
    echo "ERROR: ORACLE_HOME not set. Cannot proceed." | tee -a "$ALERT_FILE"
    exit 1
fi

SQLPLUS="${ORACLE_HOME}/bin/sqlplus"

# =============================================================================
# HEALTH CHECK 1: TABLESPACE USAGE
# =============================================================================

echo "" | tee -a "$ALERT_FILE"
echo "1. TABLESPACE USAGE ANALYSIS" | tee -a "$ALERT_FILE"
echo "-----------------------------------" | tee -a "$ALERT_FILE"

cat > /tmp/check_tablespace.sql << 'EOSQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200
SELECT
    ts.tablespace_name || '|' ||
    ROUND(100 * du.used_space / dt.allocated_space, 2) || '|' ||
    ROUND(dt.allocated_space / 1024 / 1024, 2) || '|' ||
    ROUND(du.used_space / 1024 / 1024, 2)
FROM
    (SELECT tablespace_name, SUM(bytes) AS allocated_space
     FROM dba_data_files
     GROUP BY tablespace_name) dt
JOIN
    (SELECT tablespace_name, SUM(bytes) AS used_space
     FROM dba_extents
     GROUP BY tablespace_name) du
ON dt.tablespace_name = du.tablespace_name
ORDER BY du.used_space DESC;
EOSQL

ALERT_COUNT=0
while IFS='|' read -r ts_name pct_used allocated used; do
    if [ -z "$ts_name" ]; then
        continue
    fi

    echo "  $ts_name: ${pct_used}% used (${used}MB / ${allocated}MB)" | tee -a "$ALERT_FILE"

    if (( $(echo "$pct_used > $TABLESPACE_THRESHOLD" | bc -l) )); then
        echo "    [ALERT] CRITICAL: Tablespace above ${TABLESPACE_THRESHOLD}% threshold!" | tee -a "$ALERT_FILE"
        ALERT_COUNT=$((ALERT_COUNT + 1))
    fi
done < <($SQLPLUS -S / as sysdba @/tmp/check_tablespace.sql 2>/dev/null)

rm -f /tmp/check_tablespace.sql

# =============================================================================
# HEALTH CHECK 2: INVALID OBJECTS
# =============================================================================

echo "" | tee -a "$ALERT_FILE"
echo "2. INVALID OBJECTS CHECK" | tee -a "$ALERT_FILE"
echo "-----------------------------------" | tee -a "$ALERT_FILE"

cat > /tmp/check_invalid.sql << 'EOSQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200
SELECT COUNT(*) FROM dba_objects WHERE status = 'INVALID';
EOSQL

INVALID_COUNT=$($SQLPLUS -S / as sysdba @/tmp/check_invalid.sql 2>/dev/null | grep -v '^$' | head -1)
echo "  Invalid objects: $INVALID_COUNT" | tee -a "$ALERT_FILE"

if [ "$INVALID_COUNT" -gt "$INVALID_OBJECTS_THRESHOLD" ]; then
    echo "    [ALERT] WARNING: Found $INVALID_COUNT invalid objects!" | tee -a "$ALERT_FILE"
    ALERT_COUNT=$((ALERT_COUNT + 1))
fi

rm -f /tmp/check_invalid.sql

# =============================================================================
# HEALTH CHECK 3: DATABASE SIZE GROWTH
# =============================================================================

echo "" | tee -a "$ALERT_FILE"
echo "3. DATABASE SIZE ANALYSIS" | tee -a "$ALERT_FILE"
echo "-----------------------------------" | tee -a "$ALERT_FILE"

cat > /tmp/check_size.sql << 'EOSQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200
SELECT ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) FROM dba_data_files;
EOSQL

DB_SIZE=$($SQLPLUS -S / as sysdba @/tmp/check_size.sql 2>/dev/null | grep -v '^$' | head -1)
echo "  Total database size: ${DB_SIZE}GB" | tee -a "$ALERT_FILE"

rm -f /tmp/check_size.sql

# =============================================================================
# HEALTH CHECK 4: UNDO TABLESPACE
# =============================================================================

echo "" | tee -a "$ALERT_FILE"
echo "4. UNDO TABLESPACE USAGE" | tee -a "$ALERT_FILE"
echo "-----------------------------------" | tee -a "$ALERT_FILE"

cat > /tmp/check_undo.sql << 'EOSQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200
SELECT
    status || '|' ||
    ROUND(SUM(bytes) / 1024 / 1024, 2)
FROM dba_undo_extents
GROUP BY status
ORDER BY status;
EOSQL

UNDO_ISSUES=0
while IFS='|' read -r status size_mb; do
    if [ -z "$status" ]; then
        continue
    fi
    echo "  Undo status '$status': ${size_mb}MB" | tee -a "$ALERT_FILE"

    if [ "$status" = "UNEXPIRED" ] || [ "$status" = "ACTIVE" ]; then
        if (( $(echo "$size_mb > 5000" | bc -l) )); then
            echo "    [INFO] Large undo segment - verify long-running queries" | tee -a "$ALERT_FILE"
            UNDO_ISSUES=$((UNDO_ISSUES + 1))
        fi
    fi
done < <($SQLPLUS -S / as sysdba @/tmp/check_undo.sql 2>/dev/null)

rm -f /tmp/check_undo.sql

# =============================================================================
# HEALTH CHECK 5: ARCHIVE LOG STATUS
# =============================================================================

echo "" | tee -a "$ALERT_FILE"
echo "5. ARCHIVE LOG DESTINATION" | tee -a "$ALERT_FILE"
echo "-----------------------------------" | tee -a "$ALERT_FILE"

cat > /tmp/check_archive.sql << 'EOSQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200
SELECT
    name || '|' ||
    ROUND(space_used / 1024 / 1024 / 1024, 2) || '|' ||
    ROUND(space_limit / 1024 / 1024 / 1024, 2) || '|' ||
    ROUND(100 * space_used / space_limit, 2)
FROM v$recovery_file_dest;
EOSQL

while IFS='|' read -r dest used limit pct; do
    if [ -z "$dest" ]; then
        continue
    fi
    echo "  Destination: $dest" | tee -a "$ALERT_FILE"
    echo "    Used: ${used}GB / ${limit}GB (${pct}%)" | tee -a "$ALERT_FILE"

    if (( $(echo "$pct > $ARCHIVE_LOG_THRESHOLD" | bc -l) )); then
        echo "    [ALERT] WARNING: Archive log destination above ${ARCHIVE_LOG_THRESHOLD}% threshold!" | tee -a "$ALERT_FILE"
        ALERT_COUNT=$((ALERT_COUNT + 1))
    fi
done < <($SQLPLUS -S / as sysdba @/tmp/check_archive.sql 2>/dev/null)

rm -f /tmp/check_archive.sql

# =============================================================================
# HEALTH CHECK 6: LISTENER AND CONNECTION STATUS
# =============================================================================

echo "" | tee -a "$ALERT_FILE"
echo "6. DATABASE CONNECTIVITY" | tee -a "$ALERT_FILE"
echo "-----------------------------------" | tee -a "$ALERT_FILE"

cat > /tmp/check_connect.sql << 'EOSQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200
SELECT 'Connection Test: SUCCESS';
EOSQL

if $SQLPLUS -S / as sysdba @/tmp/check_connect.sql >/dev/null 2>&1; then
    echo "  [OK] Database connection successful" | tee -a "$ALERT_FILE"
else
    echo "  [ALERT] CRITICAL: Unable to connect to database!" | tee -a "$ALERT_FILE"
    ALERT_COUNT=$((ALERT_COUNT + 1))
fi

rm -f /tmp/check_connect.sql

# =============================================================================
# HEALTH CHECK 7: INSTANCE UPTIME
# =============================================================================

echo "" | tee -a "$ALERT_FILE"
echo "7. INSTANCE STATUS" | tee -a "$ALERT_FILE"
echo "-----------------------------------" | tee -a "$ALERT_FILE"

cat > /tmp/check_uptime.sql << 'EOSQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200
SELECT TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI:SS') FROM v$instance;
EOSQL

STARTUP_TIME=$($SQLPLUS -S / as sysdba @/tmp/check_uptime.sql 2>/dev/null | grep -v '^$' | head -1)
echo "  Instance startup: $STARTUP_TIME" | tee -a "$ALERT_FILE"

rm -f /tmp/check_uptime.sql

# =============================================================================
# SUMMARY
# =============================================================================

echo "" | tee -a "$ALERT_FILE"
echo "================================================================================" | tee -a "$ALERT_FILE"
echo "HEALTH CHECK SUMMARY" | tee -a "$ALERT_FILE"
echo "-----------------------------------" | tee -a "$ALERT_FILE"
echo "Total alerts: $ALERT_COUNT" | tee -a "$ALERT_FILE"

if [ $ALERT_COUNT -eq 0 ]; then
    echo "[OK] All checks passed - Database health is good" | tee -a "$ALERT_FILE"
    EXIT_CODE=0
else
    echo "[WARNING] Found $ALERT_COUNT alerts - Review above for details" | tee -a "$ALERT_FILE"
    EXIT_CODE=1
fi

echo "================================================================================" | tee -a "$ALERT_FILE"
echo "" | tee -a "$ALERT_FILE"

# Copy to health report
cp "$ALERT_FILE" "$HEALTH_REPORT"

exit $EXIT_CODE
