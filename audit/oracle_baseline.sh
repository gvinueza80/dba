#!/bin/bash
# audit/oracle_baseline.sh
# Captures Oracle version, configuration, patches, installed features

# Configuration
REPORT_FILE="baseline_report.txt"
TEMP_REPORT="${REPORT_FILE}.tmp"
ORACLE_USER="oracle"

# Cleanup on exit (remove temp file)
trap 'rm -f "$TEMP_REPORT"' EXIT

# Validate prerequisites
validate_prerequisites() {
    # Check if running as oracle user
    if [ "$(id -un)" != "$ORACLE_USER" ]; then
        echo "ERROR: This script must be run as the '$ORACLE_USER' user (current user: $(id -un))" >&2
        exit 1
    fi

    # Check ORACLE_HOME is set
    if [ -z "$ORACLE_HOME" ]; then
        echo "ERROR: ORACLE_HOME environment variable is not set" >&2
        exit 1
    fi

    # Check ORACLE_HOME directory exists
    if [ ! -d "$ORACLE_HOME" ]; then
        echo "ERROR: ORACLE_HOME directory does not exist: $ORACLE_HOME" >&2
        exit 1
    fi

    # Check sqlplus is available
    if ! command -v sqlplus &> /dev/null; then
        echo "ERROR: sqlplus not found in PATH. Ensure ORACLE_HOME/bin is in PATH" >&2
        exit 1
    fi
}

# Execute sqlplus command and capture output
execute_sqlplus() {
    local sql_query="$1"
    sqlplus -s / as sysdba <<EOF
$sql_query
EXIT;
EOF

    # Check for sqlplus command execution status
    if [ $? -ne 0 ]; then
        echo "ERROR: sqlplus command failed" >&2
        return 1
    fi
}

# Validate prerequisites before proceeding
validate_prerequisites

# Initialize report with timestamp
{
    echo "=== ORACLE INVENTORY BASELINE ==="
    echo "Date: $(date)"
    echo ""
} > "$TEMP_REPORT"

# Oracle version and patch level
{
    echo "--- Oracle Version Info ---"
    sqlplus -v 2>&1 || { echo "WARNING: sqlplus -v failed"; true; }
    echo ""
    execute_sqlplus "SET HEADING OFF FEEDBACK OFF
SELECT 'Oracle Version: ' || BANNER FROM v\$version WHERE BANNER LIKE 'Oracle%';
SELECT 'Patch Level: ' || patch_level FROM registry\$history WHERE action = 'APPLY' AND ROWNUM <= 1 ORDER BY action_time DESC;" 2>&1 || { echo "WARNING: Patch level query failed"; true; }
    echo ""
} >> "$TEMP_REPORT"

# Database name, location, initialization parameters
{
    echo "--- Database Configuration ---"
    execute_sqlplus "SET HEADING ON
SELECT name FROM v\$database;
SELECT value FROM v\$parameter WHERE name IN ('db_name','memory_target','processes','open_cursors');" 2>&1 || { echo "WARNING: Database config query failed"; true; }
    echo ""
} >> "$TEMP_REPORT"

# Tablespaces
{
    echo "--- Tablespaces ---"
    execute_sqlplus "COLUMN tablespace_name FORMAT A20
COLUMN status FORMAT A10
SELECT tablespace_name, status, extent_management, segment_space_management FROM dba_tablespaces;" 2>&1 || { echo "WARNING: Tablespace query failed"; true; }
    echo ""
} >> "$TEMP_REPORT"

# Data files and log files
{
    echo "--- Data Files and Redo Logs ---"
    execute_sqlplus "SELECT 'Datafiles:' FROM dual;
SELECT name FROM v\$datafile;
SELECT 'Redo Logs:' FROM dual;
SELECT member FROM v\$logfile;" 2>&1 || { echo "WARNING: Data files and logs query failed"; true; }
    echo ""
} >> "$TEMP_REPORT"

# Validate that the report contains meaningful content and finalize
if [ -f "$TEMP_REPORT" ]; then
    REPORT_SIZE=$(stat -f%z "$TEMP_REPORT" 2>/dev/null || stat -c%s "$TEMP_REPORT" 2>/dev/null || echo 0)
    if [ "$REPORT_SIZE" -ge 500 ]; then
        mv "$TEMP_REPORT" "$REPORT_FILE"
        echo "SUCCESS: Baseline captured to $REPORT_FILE ($(wc -l < "$REPORT_FILE") lines)"
    else
        echo "ERROR: Report file is too small ($REPORT_SIZE bytes). Queries may have failed." >&2
        rm -f "$TEMP_REPORT"
        exit 1
    fi
else
    echo "ERROR: Temporary report file was not created" >&2
    exit 1
fi
