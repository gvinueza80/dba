-- Oracle Database Performance Baseline Audit
-- Captures memory, wait events, database size, invalid objects, and tablespace usage
-- Run as: sqlplus / as sysdba @performance_audit.sql

SET ECHO ON
SET FEEDBACK ON
SET PAGESIZE 50
SET LINESIZE 200
SPOOL performance_audit.log

PROMPT ================================================================================
PROMPT ORACLE DATABASE PERFORMANCE BASELINE ANALYSIS
PROMPT ================================================================================
PROMPT Report Date:
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;

PROMPT
PROMPT ================================================================================
PROMPT 1. SGA (System Global Area) CONFIGURATION
PROMPT ================================================================================

SELECT name, value
FROM v$parameter
WHERE name IN ('sga_max_size', 'sga_target', 'processes', 'open_cursors')
ORDER BY name;

PROMPT
PROMPT ================================================================================
PROMPT 2. MEMORY ALLOCATION DETAILS
PROMPT ================================================================================

SELECT component, current_size_mb
FROM v$sga_dynamic_components
WHERE current_size_mb > 0
ORDER BY current_size_mb DESC;

PROMPT
PROMPT ================================================================================
PROMPT 3. TOP 20 WAIT EVENTS
PROMPT ================================================================================

SELECT * FROM (
  SELECT event, total_waits, time_waited_micro/1000000 AS time_waited_sec,
         ROUND(100 * time_waited_micro / SUM(time_waited_micro) OVER (), 2) AS pct_total
  FROM v$event_name e
  WHERE wait_class != 'Idle'
  ORDER BY time_waited_micro DESC
)
WHERE ROWNUM <= 20;

PROMPT
PROMPT ================================================================================
PROMPT 4. DATABASE SIZE ANALYSIS
PROMPT ================================================================================

PROMPT Total Database Size (GB):
SELECT ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) AS total_size_gb
FROM dba_data_files;

PROMPT Data Files Size:
SELECT tablespace_name, ROUND(SUM(bytes) / 1024 / 1024, 2) AS size_mb
FROM dba_data_files
GROUP BY tablespace_name
ORDER BY bytes DESC;

PROMPT
PROMPT ================================================================================
PROMPT 5. TABLESPACE USAGE AND ALLOCATION
PROMPT ================================================================================

SELECT
    dt.tablespace_name,
    ROUND(dt.allocated_space / 1024 / 1024, 2) AS allocated_mb,
    ROUND(du.used_space / 1024 / 1024, 2) AS used_mb,
    ROUND((dt.allocated_space - du.used_space) / 1024 / 1024, 2) AS free_mb,
    ROUND(100 * du.used_space / dt.allocated_space, 2) AS pct_used
FROM
    (SELECT tablespace_name, SUM(bytes) AS allocated_space
     FROM dba_data_files
     GROUP BY tablespace_name) dt
    JOIN
    (SELECT tablespace_name, SUM(bytes) AS used_space
     FROM dba_extents
     GROUP BY tablespace_name) du
    ON dt.tablespace_name = du.tablespace_name
ORDER BY pct_used DESC;

PROMPT
PROMPT ================================================================================
PROMPT 6. INVALID AND UNRECOMPILABLE OBJECTS
PROMPT ================================================================================

PROMPT Count of Invalid Objects by Type:
SELECT object_type, COUNT(*) AS count
FROM dba_objects
WHERE status = 'INVALID'
GROUP BY object_type
ORDER BY count DESC;

PROMPT Detailed Invalid Objects:
SELECT owner, object_type, object_name, status, created, last_ddl_time
FROM dba_objects
WHERE status = 'INVALID'
ORDER BY owner, object_type;

PROMPT
PROMPT ================================================================================
PROMPT 7. OBJECT STATISTICS (LAST ANALYZED)
PROMPT ================================================================================

SELECT
    object_type,
    COUNT(*) AS total_objects,
    SUM(CASE WHEN last_analyzed IS NULL THEN 1 ELSE 0 END) AS never_analyzed,
    ROUND(100 * SUM(CASE WHEN last_analyzed IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_never_analyzed
FROM dba_objects
WHERE owner NOT IN ('SYS', 'SYSTEM')
GROUP BY object_type
ORDER BY pct_never_analyzed DESC;

PROMPT
PROMPT ================================================================================
PROMPT 8. UNDO TABLESPACE USAGE
PROMPT ================================================================================

SELECT
    tablespace_name,
    ROUND(SUM(bytes) / 1024 / 1024, 2) AS size_mb,
    status,
    retention
FROM dba_undo_extents
GROUP BY tablespace_name, status, retention;

PROMPT
PROMPT ================================================================================
PROMPT 9. ARCHIVE LOG DESTINATION AND STATUS
PROMPT ================================================================================

SELECT name, value
FROM v$parameter
WHERE name IN ('db_recovery_file_dest', 'db_recovery_file_dest_size', 'log_archive_dest_1')
ORDER BY name;

PROMPT
PROMPT ================================================================================
PROMPT 10. INSTANCE UPTIME AND RESTART INFO
PROMPT ================================================================================

SELECT startup_time FROM v$instance;

PROMPT
PROMPT ================================================================================
PROMPT 11. CPU AND SYSTEM LOAD
PROMPT ================================================================================

SELECT stat_name, value
FROM v$osstat
WHERE stat_name IN ('NUM_CPUS', 'LOAD')
ORDER BY stat_name;

PROMPT
PROMPT ================================================================================
PROMPT 12. BACKGROUND PROCESS STATUS
PROMPT ================================================================================

SELECT pname, status, pid
FROM v$process
WHERE pname IS NOT NULL
ORDER BY pname;

SPOOL OFF

PROMPT
PROMPT Performance audit complete. Check performance_audit.log for results.
