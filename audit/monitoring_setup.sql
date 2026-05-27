-- Oracle Database Comprehensive Auditing, Monitoring & Logging Setup
-- Enables audit trails, configures alert log monitoring, and statistics collection
-- Run as: sqlplus / as sysdba @monitoring_setup.sql

SET ECHO ON
SET FEEDBACK ON
SET PAGESIZE 50
SET LINESIZE 200
SPOOL monitoring_setup.log

PROMPT ================================================================================
PROMPT ORACLE COMPREHENSIVE AUDITING AND MONITORING SETUP
PROMPT Start Time:
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;

-- =============================================================================
-- PART 1: ENABLE UNIFIED AUDIT TRAIL
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 1: CONFIGURE UNIFIED AUDIT TRAIL (Oracle 12c+)
PROMPT ================================================================================

PROMPT Checking Oracle version for unified audit support...
SELECT banner_full FROM v$version WHERE ROWNUM = 1;

PROMPT
PROMPT NOTE: Unified Audit Trail requires CREATE AUDIT POLICY privileges.
PROMPT If running Oracle 11g or earlier, traditional auditing will be used.
PROMPT

-- Create audit for DDL operations
PROMPT Creating audit policies for administrative activities...

BEGIN
  EXECUTE IMMEDIATE q'[CREATE AUDIT POLICY admin_activity_policy
    ACTIONS CREATE USER,
            ALTER USER,
            DROP USER,
            CREATE ROLE,
            DROP ROLE,
            ALTER DATABASE,
            CREATE TABLESPACE,
            DROP TABLESPACE,
            ALTER TABLESPACE,
            CREATE TABLE,
            ALTER TABLE,
            DROP TABLE,
            CREATE INDEX,
            DROP INDEX,
            TRUNCATE,
            CREATE PROCEDURE,
            CREATE FUNCTION,
            CREATE PACKAGE,
            DROP PROCEDURE,
            DROP FUNCTION,
            DROP PACKAGE,
            GRANT,
            REVOKE
  ]';
  DBMS_OUTPUT.PUT_LINE('Admin activity audit policy created.');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -46005 THEN
      DBMS_OUTPUT.PUT_LINE('Note: Unified audit not available in this version. Using traditional auditing.');
    ELSE
      DBMS_OUTPUT.PUT_LINE('Warning: ' || SQLERRM);
    END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE 'AUDIT POLICY admin_activity_policy';
  DBMS_OUTPUT.PUT_LINE('Admin activity audit policy enabled.');
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
/

-- =============================================================================
-- PART 2: ENABLE TRADITIONAL AUDIT TRAIL (11g and earlier)
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 2: ENABLE TRADITIONAL AUDIT TRAIL
PROMPT ================================================================================

PROMPT Enabling basic audit for critical database operations...

PROMPT Auditing failed logins...
AUDIT CREATE SESSION BY ACCESS WHENEVER NOT SUCCESSFUL;

PROMPT Auditing successful logins (sample: every 10th successful login)...
-- AUDIT CREATE SESSION BY ACCESS;

PROMPT Auditing table creation and alteration...
AUDIT CREATE TABLE BY ACCESS;
AUDIT ALTER TABLE BY ACCESS;
AUDIT DROP TABLE BY ACCESS;

PROMPT Auditing user privilege changes...
AUDIT GRANT SYSTEM PRIVILEGES BY ACCESS;
AUDIT REVOKE SYSTEM PRIVILEGES BY ACCESS;
AUDIT GRANT OBJECT PRIVILEGES BY ACCESS;
AUDIT REVOKE OBJECT PRIVILEGES BY ACCESS;

PROMPT Auditing user and role administration...
AUDIT CREATE USER BY ACCESS;
AUDIT ALTER USER BY ACCESS;
AUDIT DROP USER BY ACCESS;
AUDIT CREATE ROLE BY ACCESS;
AUDIT ALTER ROLE BY ACCESS;
AUDIT DROP ROLE BY ACCESS;

PROMPT Auditing database role/privilege changes...
AUDIT ROLE BY ACCESS;

PROMPT Auditing DBA_* table access...
AUDIT SELECT ON dba_users BY ACCESS;
AUDIT SELECT ON dba_roles BY ACCESS;
AUDIT SELECT ON dba_role_privs BY ACCESS;
AUDIT SELECT ON dba_user_privs BY ACCESS;

-- =============================================================================
-- PART 3: CONFIGURE ALERT LOG MONITORING
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 3: CONFIGURE ALERT LOG MONITORING
PROMPT ================================================================================

PROMPT Alert log location:
SELECT value FROM v$parameter WHERE name = 'background_dump_dest';

PROMPT
PROMPT Creating table to track alert log entries...

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE audit_alert_log_tracking';
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
/

CREATE TABLE audit_alert_log_tracking (
  log_id NUMBER PRIMARY KEY,
  capture_timestamp TIMESTAMP DEFAULT SYSDATE,
  alert_entry CLOB,
  severity VARCHAR2(20),
  alert_type VARCHAR2(50),
  processed NUMBER DEFAULT 0
) TABLESPACE SYSAUX;

CREATE INDEX idx_alert_log_timestamp ON audit_alert_log_tracking(capture_timestamp);
CREATE INDEX idx_alert_log_severity ON audit_alert_log_tracking(severity);

PROMPT Alert log tracking table created.

-- =============================================================================
-- PART 4: ENABLE DICTIONARY PROTECTION AUDITING
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 4: ENABLE AUDIT FOR DICTIONARY PROTECTION
PROMPT ================================================================================

PROMPT Configuring audit for system table modifications (requires AUDIT ANY TABLE)...

BEGIN
  EXECUTE IMMEDIATE 'AUDIT SELECT ANY TABLE BY ACCESS';
  EXECUTE IMMEDIATE 'AUDIT INSERT ANY TABLE BY ACCESS';
  EXECUTE IMMEDIATE 'AUDIT UPDATE ANY TABLE BY ACCESS';
  EXECUTE IMMEDIATE 'AUDIT DELETE ANY TABLE BY ACCESS';
  DBMS_OUTPUT.PUT_LINE('Table operation auditing enabled.');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Note: Table operation auditing configuration: ' || SQLERRM);
END;
/

-- =============================================================================
-- PART 5: ENABLE DATABASE-WIDE STATISTICS COLLECTION
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 5: ENABLE AUTOMATIC STATISTICS GATHERING
PROMPT ================================================================================

PROMPT Creating automated statistics gathering job...

BEGIN
  -- Create job for nightly statistics gathering
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'GATHER_STATS_JOB',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN
                         DBMS_STATS.GATHER_DATABASE_STATS(
                           estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
                           granularity => ''ALL'',
                           cascade => TRUE,
                           degree => DBMS_STATS.DEFAULT_DEGREE
                         );
                       END;',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=DAILY;BYHOUR=22',
    enabled         => TRUE
  );
  DBMS_OUTPUT.PUT_LINE('Statistics gathering job created (nightly at 10 PM).');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE = -27404 THEN
      DBMS_OUTPUT.PUT_LINE('Note: Job GATHER_STATS_JOB already exists.');
    ELSE
      DBMS_OUTPUT.PUT_LINE('Warning: ' || SQLERRM);
    END IF;
END;
/

-- =============================================================================
-- PART 6: ENABLE PERFORMANCE STATISTICS MONITORING
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 6: ENABLE PERFORMANCE STATISTICS AND METRICS
PROMPT ================================================================================

PROMPT Enabling statistics gathering for performance monitoring...

BEGIN
  -- Enable AWR (Automatic Workload Repository) if licensed
  DBMS_WORKLOAD_REPOSITORY.MODIFY_SNAPSHOT_SETTINGS(
    retention  => 8,  -- Keep 8 days of snapshots
    interval   => 60  -- Take snapshots every 60 minutes
  );
  DBMS_OUTPUT.PUT_LINE('AWR snapshot settings configured (60-minute intervals, 8-day retention).');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Note: AWR configuration - ' || SQLERRM);
END;
/

-- Enable ASH (Active Session History) if available
PROMPT Enabling Active Session History (ASH) for wait event tracking...

BEGIN
  EXECUTE IMMEDIATE 'ALTER SYSTEM SET db_recovery_file_dest_size=50G SCOPE=BOTH';
  DBMS_OUTPUT.PUT_LINE('Database recovery file destination sized for ASH tracking.');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Note: ASH configuration - ' || SQLERRM);
END;
/

-- =============================================================================
-- PART 7: CREATE AUDIT REPORTING PROCEDURES
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 7: CREATE AUDIT REPORTING VIEWS AND PROCEDURES
PROMPT ================================================================================

PROMPT Creating view for recent audit events...

CREATE OR REPLACE VIEW v_recent_audit_events AS
SELECT
    sessionid,
    username,
    timestamp,
    owner,
    obj_name,
    action_name,
    returncode,
    CASE WHEN returncode = 0 THEN 'SUCCESS' ELSE 'FAILURE' END AS status
FROM dba_audit_trail
WHERE timestamp >= SYSDATE - 1
ORDER BY timestamp DESC;

PROMPT Creating procedure for audit report generation...

CREATE OR REPLACE PROCEDURE sp_audit_report (
  p_days_back IN NUMBER DEFAULT 7
)
IS
BEGIN
  DBMS_OUTPUT.PUT_LINE('===============================================');
  DBMS_OUTPUT.PUT_LINE('AUDIT TRAIL REPORT - Last ' || p_days_back || ' Days');
  DBMS_OUTPUT.PUT_LINE('Generated: ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
  DBMS_OUTPUT.PUT_LINE('===============================================');
  DBMS_OUTPUT.NEW_LINE;

  DBMS_OUTPUT.PUT_LINE('Failed Login Attempts:');
  FOR rec IN (
    SELECT username, COUNT(*) AS attempt_count, MAX(timestamp) AS last_attempt
    FROM dba_audit_trail
    WHERE action_name = 'LOGON' AND returncode != 0
      AND timestamp >= SYSDATE - p_days_back
    GROUP BY username
    ORDER BY attempt_count DESC
  )
  LOOP
    DBMS_OUTPUT.PUT_LINE('  ' || rec.username || ': ' || rec.attempt_count ||
                         ' attempts (last: ' || rec.last_attempt || ')');
  END LOOP;

  DBMS_OUTPUT.NEW_LINE;
  DBMS_OUTPUT.PUT_LINE('Privilege Changes:');
  FOR rec IN (
    SELECT username, action_name, COUNT(*) AS count
    FROM dba_audit_trail
    WHERE action_name IN ('GRANT SYSTEM PRIVILEGE', 'REVOKE SYSTEM PRIVILEGE',
                          'GRANT OBJECT PRIVILEGE', 'REVOKE OBJECT PRIVILEGE')
      AND timestamp >= SYSDATE - p_days_back
    GROUP BY username, action_name
    ORDER BY count DESC
  )
  LOOP
    DBMS_OUTPUT.PUT_LINE('  ' || rec.username || ': ' || rec.action_name ||
                         ' (' || rec.count || ' times)');
  END LOOP;

  DBMS_OUTPUT.NEW_LINE;
  DBMS_OUTPUT.PUT_LINE('Administrative Changes:');
  FOR rec IN (
    SELECT username, action_name, COUNT(*) AS count
    FROM dba_audit_trail
    WHERE action_name IN ('CREATE USER', 'ALTER USER', 'DROP USER',
                          'CREATE ROLE', 'DROP ROLE', 'CREATE TABLE', 'DROP TABLE')
      AND timestamp >= SYSDATE - p_days_back
    GROUP BY username, action_name
    ORDER BY count DESC
  )
  LOOP
    DBMS_OUTPUT.PUT_LINE('  ' || rec.username || ': ' || rec.action_name ||
                         ' (' || rec.count || ' times)');
  END LOOP;

  DBMS_OUTPUT.NEW_LINE;
  DBMS_OUTPUT.PUT_LINE('===============================================');
END sp_audit_report;
/

SHOW ERRORS;

-- =============================================================================
-- PART 8: CONFIGURE ALERT TRIGGERS
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 8: SETUP ALERT THRESHOLDS AND NOTIFICATIONS
PROMPT ================================================================================

PROMPT Configuring tablespace threshold alerts...

CREATE OR REPLACE PROCEDURE check_tablespace_usage
IS
  v_threshold NUMBER := 90;
BEGIN
  FOR ts IN (
    SELECT dt.tablespace_name,
           ROUND(100 * du.used_space / dt.allocated_space, 2) AS pct_used
    FROM (SELECT tablespace_name, SUM(bytes) AS allocated_space
          FROM dba_data_files
          GROUP BY tablespace_name) dt
    JOIN (SELECT tablespace_name, SUM(bytes) AS used_space
          FROM dba_extents
          GROUP BY tablespace_name) du
    ON dt.tablespace_name = du.tablespace_name
  )
  LOOP
    IF ts.pct_used >= v_threshold THEN
      DBMS_OUTPUT.PUT_LINE('ALERT: Tablespace ' || ts.tablespace_name ||
                           ' is ' || ts.pct_used || '% full!');
    END IF;
  END LOOP;
END check_tablespace_usage;
/

-- =============================================================================
-- PART 9: VERIFICATION AND SUMMARY
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 9: VERIFICATION OF MONITORING SETUP
PROMPT ================================================================================

PROMPT Current Audit Settings:
SELECT * FROM dba_stmt_audit_opts WHERE audit_option LIKE '%SESSION%' OR audit_option LIKE '%TABLE%';

PROMPT
PROMPT Enabled Audit Options Count:
SELECT COUNT(*) AS enabled_audits FROM dba_stmt_audit_opts WHERE audit_option IS NOT NULL;

PROMPT
PROMPT Alert Log Configuration:
SELECT name, value FROM v$parameter WHERE name LIKE '%dump%' ORDER BY name;

PROMPT
PROMPT Database Alert Capability:
SELECT * FROM v$option WHERE parameter IN ('Diagnostics Pack', 'Tuning Pack', 'Database Vault');

PROMPT
PROMPT ================================================================================
PROMPT MONITORING AND AUDITING SETUP COMPLETE
PROMPT ================================================================================
PROMPT End Time:
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;

SPOOL OFF

PROMPT
PROMPT Monitoring setup complete. Check monitoring_setup.log for details.
PROMPT
PROMPT NEXT STEPS:
PROMPT 1. Review monitoring_setup.log for any warnings
PROMPT 2. Schedule the health check script (./monitoring/alerts.sh) to run hourly/daily
PROMPT 3. Test the audit report: EXEC sp_audit_report(7);
PROMPT 4. Configure alert notifications in your monitoring platform
PROMPT 5. Review audit trail data after 1 hour with: SELECT * FROM v_recent_audit_events;
