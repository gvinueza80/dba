#!/bin/bash
# audit/oracle_baseline.sh
# Captures Oracle version, configuration, patches, installed features

echo "=== ORACLE INVENTORY BASELINE ===" > baseline_report.txt
echo "Date: $(date)" >> baseline_report.txt
echo "" >> baseline_report.txt

# Oracle version and patch level
sqlplus -v >> baseline_report.txt 2>&1
sqlplus -s / as sysdba <<EOF >> baseline_report.txt 2>&1
SET HEADING OFF FEEDBACK OFF
SELECT 'Oracle Version: ' || BANNER FROM v\$version WHERE BANNER LIKE 'Oracle%';
SELECT 'Patch Level: ' || patch_level FROM registry\$history WHERE action = 'APPLY' ORDER BY action_time DESC FETCH FIRST 1 ROW ONLY;
EXIT;
EOF

# Database name, location, initialization parameters
sqlplus -s / as sysdba <<EOF >> baseline_report.txt 2>&1
SET HEADING ON
SELECT name FROM v\$database;
SELECT value FROM v\$parameter WHERE name IN ('db_name','memory_target','processes','open_cursors');
EXIT;
EOF

# Tablespaces
sqlplus -s / as sysdba <<EOF >> baseline_report.txt 2>&1
COLUMN tablespace_name FORMAT A20
COLUMN status FORMAT A10
SELECT tablespace_name, status, extent_management, segment_space_management FROM dba_tablespaces;
EXIT;
EOF

# Data files and log files
sqlplus -s / as sysdba <<EOF >> baseline_report.txt 2>&1
SELECT 'Datafiles:' FROM dual;
SELECT name FROM v\$datafile;
SELECT 'Redo Logs:' FROM dual;
SELECT member FROM v\$logfile;
EXIT;
EOF

echo "Baseline captured: audit/baseline_report.txt"
