#!/bin/bash
# Oracle Database Backup & Disaster Recovery Audit
# Checks RMAN configuration, archive logs, standby status, and backup history
# Run as: ./backup_audit.sh

echo "================================================================================"
echo "ORACLE DATABASE BACKUP & DISASTER RECOVERY AUDIT"
echo "================================================================================"
echo "Report Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Check if ORACLE_HOME is set
if [ -z "$ORACLE_HOME" ]; then
    echo "ERROR: ORACLE_HOME is not set. Please source oraenv or set ORACLE_HOME."
    exit 1
fi

SQLPLUS=$ORACLE_HOME/bin/sqlplus
RMAN=$ORACLE_HOME/bin/rman

echo "================================================================================"
echo "1. RMAN CONFIGURATION AND BACKUP STATUS"
echo "================================================================================"

# Create temporary SQL script for RMAN status
cat > /tmp/rman_audit.sql << 'EOF'
SET PAGESIZE 50
SET LINESIZE 200
SET FEEDBACK ON

PROMPT
PROMPT ================================================================================
PROMPT RMAN CONFIGURATION
PROMPT ================================================================================

SHOW ALL;

PROMPT
PROMPT ================================================================================
PROMPT RMAN BACKUP HISTORY (LAST 30 DAYS)
PROMPT ================================================================================

SELECT
    session_key,
    command_id,
    operation,
    status,
    start_time,
    end_time,
    ROUND((end_time - start_time) * 24 * 60, 2) AS duration_minutes,
    output_size_gb
FROM (
    SELECT
        session_key,
        command_id,
        operation,
        status,
        start_time,
        end_time,
        ROUND(output_bytes / 1024 / 1024 / 1024, 2) AS output_size_gb,
        ROW_NUMBER() OVER (ORDER BY start_time DESC) AS rn
    FROM v$rman_backup_job_details
    WHERE start_time >= SYSDATE - 30
    ORDER BY start_time DESC
)
WHERE rn <= 20;

PROMPT
PROMPT ================================================================================
PROMPT BACKUP SETS AND PIECES (LAST 10)
PROMPT ================================================================================

SELECT
    bs.backup_set_key,
    bs.backup_type,
    bs.status,
    bs.start_time,
    bs.completion_time,
    COUNT(bp.backup_piece_key) AS num_pieces,
    ROUND(SUM(bp.bytes) / 1024 / 1024, 2) AS total_size_mb
FROM rc_backup_set bs
LEFT JOIN rc_backup_piece bp ON bs.backup_set_key = bp.backup_set_key
WHERE bs.start_time >= SYSDATE - 30
GROUP BY
    bs.backup_set_key,
    bs.backup_type,
    bs.status,
    bs.start_time,
    bs.completion_time
ORDER BY bs.start_time DESC
FETCH FIRST 10 ROWS ONLY;

EOF

echo "Executing RMAN configuration query..."
$SQLPLUS -S / as sysdba @/tmp/rman_audit.sql 2>&1 | head -100

rm -f /tmp/rman_audit.sql

echo ""
echo "================================================================================"
echo "2. ARCHIVE LOG STATUS"
echo "================================================================================"

cat > /tmp/archive_audit.sql << 'EOF'
SET PAGESIZE 50
SET LINESIZE 200

PROMPT Archive Log Destination:
SELECT name, value FROM v$parameter WHERE name = 'db_recovery_file_dest';
SELECT name, value FROM v$parameter WHERE name = 'db_recovery_file_dest_size';
SELECT name, value FROM v$parameter WHERE name = 'log_archive_dest_1';

PROMPT
PROMPT Archive Log Usage:
SELECT
    trunc(completion_time) AS day,
    COUNT(*) AS num_logs,
    ROUND(SUM(blocks * block_size) / 1024 / 1024 / 1024, 2) AS total_size_gb
FROM v$archived_log
WHERE completion_time >= TRUNC(SYSDATE) - 7
GROUP BY trunc(completion_time)
ORDER BY day DESC;

PROMPT
PROMPT Recent Archive Logs (Last 20):
SELECT
    recid,
    stamp,
    name,
    completion_time,
    ROUND(blocks * block_size / 1024 / 1024, 2) AS size_mb,
    archived,
    deleted,
    status
FROM v$archived_log
WHERE completion_time >= TRUNC(SYSDATE) - 1
ORDER BY completion_time DESC
FETCH FIRST 20 ROWS ONLY;

EOF

echo "Executing archive log query..."
$SQLPLUS -S / as sysdba @/tmp/archive_audit.sql 2>&1 | head -100

rm -f /tmp/archive_audit.sql

echo ""
echo "================================================================================"
echo "3. DATA GUARD / STANDBY STATUS"
echo "================================================================================"

cat > /tmp/standby_audit.sql << 'EOF'
SET PAGESIZE 50
SET LINESIZE 200

PROMPT Database Role and Open Status:
SELECT
    database_role,
    open_cursors,
    restricted
FROM v$database;

PROMPT
PROMPT Data Guard Protection Mode:
SELECT protection_mode, protection_level FROM v$database;

PROMPT
PROMPT Standby Log Files (if this is primary):
SELECT group#, type, member
FROM v$logfile
WHERE type = 'STANDBY'
ORDER BY group#;

PROMPT
PROMPT Log Apply Services (if this is standby):
SELECT * FROM v$managed_standby WHERE process IN ('MRP0', 'MRP', 'RFS');

EOF

echo "Executing standby/Data Guard query..."
$SQLPLUS -S / as sysdba @/tmp/standby_audit.sql 2>&1

rm -f /tmp/standby_audit.sql

echo ""
echo "================================================================================"
echo "4. BACKUP SPACE ANALYSIS"
echo "================================================================================"

cat > /tmp/backup_space.sql << 'EOF'
SET PAGESIZE 50
SET LINESIZE 200

PROMPT Disk Quota Usage for DB_RECOVERY_FILE_DEST:
SELECT
    name,
    ROUND(space_limit / 1024 / 1024 / 1024, 2) AS limit_gb,
    ROUND(space_used / 1024 / 1024 / 1024, 2) AS used_gb,
    ROUND((space_limit - space_used) / 1024 / 1024 / 1024, 2) AS free_gb,
    ROUND(100 * space_used / space_limit, 2) AS pct_used
FROM v$recovery_file_dest;

PROMPT
PROMPT Recent Backup Files (Last 15 Days):
SELECT
    recid,
    backup_type,
    status,
    bytes_in_backup,
    ROUND(bytes_in_backup / 1024 / 1024 / 1024, 2) AS size_gb,
    incremental_level,
    creation_time,
    completion_time
FROM v$backup_files
WHERE creation_time >= TRUNC(SYSDATE) - 15
ORDER BY creation_time DESC
FETCH FIRST 30 ROWS ONLY;

EOF

echo "Executing backup space query..."
$SQLPLUS -S / as sysdba @/tmp/backup_space.sql 2>&1

rm -f /tmp/backup_space.sql

echo ""
echo "================================================================================"
echo "5. RECOVERY TEST VALIDATION"
echo "================================================================================"

echo "NOTE: Recovery tests should be performed manually or via automated procedures."
echo "Recommended: Run RESTORE ... VALIDATE on backups to verify integrity."
echo ""
echo "Example:"
echo "  RMAN> RESTORE DATABASE VALIDATE;"
echo "  RMAN> RESTORE ARCHIVELOG FROM TIME 'sysdate-7' VALIDATE;"
echo ""

echo "================================================================================"
echo "BACKUP AUDIT COMPLETE"
echo "================================================================================"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
