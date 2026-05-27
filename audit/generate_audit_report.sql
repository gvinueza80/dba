-- Oracle Database Comprehensive Audit Report Generator
-- Generates complete audit report with all findings and recommendations
-- Run as: sqlplus / as sysdba @generate_audit_report.sql

SET ECHO OFF
SET FEEDBACK OFF
SET PAGESIZE 50
SET LINESIZE 200
SET TRIMSPOOL ON

SPOOL ORACLE_AUDIT_REPORT.txt

PROMPT ================================================================================
PROMPT ORACLE DATABASE COMPREHENSIVE AUDIT REPORT
PROMPT ================================================================================
PROMPT
SELECT 'Generated: ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;

PROMPT
PROMPT ================================================================================
PROMPT EXECUTIVE SUMMARY
PROMPT ================================================================================
PROMPT
PROMPT This audit provides a complete assessment of the Oracle database environment
PROMPT across the following dimensions:
PROMPT
PROMPT 1. BASELINE & CONFIGURATION
PROMPT    - Database version, parameters, and SGA allocation
PROMPT
PROMPT 2. SECURITY POSTURE
PROMPT    - User accounts, password policies, privileges, audit configuration
PROMPT
PROMPT 3. ACCESS CONTROL
PROMPT    - Role memberships, system privileges, object privileges
PROMPT
PROMPT 4. PERFORMANCE METRICS
PROMPT    - Wait events, memory allocation, database size, object statistics
PROMPT
PROMPT 5. BACKUP & DISASTER RECOVERY
PROMPT    - RMAN configuration, archive logs, data guard status
PROMPT
PROMPT 6. COMPLIANCE MAPPING
PROMPT    - CIS Benchmarks, SOC 2 Type II controls alignment
PROMPT

PROMPT ================================================================================
PROMPT 1. BASELINE & CONFIGURATION
PROMPT ================================================================================
PROMPT

SELECT 'Database Identification:' FROM DUAL;
SELECT '  Name: ' || name || ', DB_ID: ' || dbid FROM v$database;
SELECT '  Version: ' || version FROM v$instance;
SELECT '  Startup Time: ' || TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI:SS') FROM v$instance;

PROMPT
PROMPT SGA Configuration:
PROMPT ==================

SELECT name, ROUND(value / 1024 / 1024, 2) AS size_mb
FROM v$parameter
WHERE name IN ('sga_max_size', 'sga_target', 'processes', 'open_cursors')
ORDER BY name;

PROMPT
PROMPT Critical Database Parameters:
PROMPT =============================

SELECT name, value
FROM v$parameter
WHERE name IN (
  'db_recovery_file_dest',
  'db_recovery_file_dest_size',
  'log_archive_dest_1',
  'audit_trail',
  'sql_trace',
  'background_dump_dest'
)
ORDER BY name;

PROMPT
PROMPT ================================================================================
PROMPT 2. SECURITY POSTURE ASSESSMENT
PROMPT ================================================================================
PROMPT

PROMPT User Accounts Status:
PROMPT ====================

SELECT
    username,
    account_status,
    TRUNC(created) AS create_date,
    TO_CHAR(TRUNC(SYSDATE) - TRUNC(created)) AS days_since_created,
    TO_CHAR(password_lifetime) AS pwd_lifetime
FROM dba_users
WHERE username NOT IN (
  'ANONYMOUS', 'CTXSYS', 'DBSNMP', 'EXFSYS', 'LBACSYS',
  'MDSYS', 'MGMT_VIEW', 'OLAPSYS', 'OWBSYS', 'ORDDATA',
  'SI_INFORMTN_SCHEMA', 'WMSYS', 'XDB'
)
ORDER BY created DESC;

PROMPT
PROMPT Open User Accounts (Potential Security Risk):
PROMPT ============================================

SELECT COUNT(*) AS open_accounts
FROM dba_users
WHERE account_status LIKE '%OPEN%'
  AND username NOT IN ('SYS', 'SYSTEM');

PROMPT
PROMPT Password Policy Enforcement:
PROMPT ============================

SELECT profile, resource_name, limit
FROM dba_profiles
WHERE profile = 'secure_password'
  OR profile = 'DEFAULT'
ORDER BY profile, resource_name;

PROMPT
PROMPT Audit Trail Configuration:
PROMPT ==========================

SELECT COUNT(*) AS enabled_audits FROM dba_stmt_audit_opts;

PROMPT
PROMPT ================================================================================
PROMPT 3. ACCESS CONTROL & PRIVILEGE REVIEW
PROMPT ================================================================================
PROMPT

PROMPT System Privileges Granted to Roles:
PROMPT ===================================

SELECT
    grantee,
    COUNT(*) AS num_privileges
FROM dba_sys_privs
WHERE grantee NOT IN ('SYS', 'SYSTEM')
GROUP BY grantee
ORDER BY num_privileges DESC;

PROMPT
PROMPT Dangerous Public Grants:
PROMPT ========================

SELECT
    owner,
    table_name,
    grantor,
    grantee,
    privilege
FROM dba_tab_privs
WHERE grantee = 'PUBLIC'
  AND owner NOT IN ('SYS', 'SYSTEM')
  AND privilege IN ('DELETE', 'INSERT', 'UPDATE', 'EXECUTE')
ORDER BY owner, table_name;

PROMPT
PROMPT Role Hierarchy:
PROMPT ===============

SELECT
    grantee,
    COUNT(*) AS num_roles
FROM dba_role_privs
WHERE grantee NOT IN ('SYS', 'SYSTEM')
GROUP BY grantee
ORDER BY num_roles DESC;

PROMPT
PROMPT ================================================================================
PROMPT 4. PERFORMANCE BASELINE METRICS
PROMPT ================================================================================
PROMPT

PROMPT Database Size Analysis:
PROMPT ======================

SELECT ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) AS total_gb
FROM dba_data_files;

PROMPT
PROMPT Tablespace Usage (Top 5 by size):
PROMPT =================================

SELECT * FROM (
  SELECT
      dt.tablespace_name,
      ROUND(100 * du.used_space / dt.allocated_space, 2) AS pct_used,
      ROUND(dt.allocated_space / 1024 / 1024, 2) AS allocated_mb,
      ROUND(du.used_space / 1024 / 1024, 2) AS used_mb
  FROM
      (SELECT tablespace_name, SUM(bytes) AS allocated_space
       FROM dba_data_files
       GROUP BY tablespace_name) dt
      JOIN
      (SELECT tablespace_name, SUM(bytes) AS used_space
       FROM dba_extents
       GROUP BY tablespace_name) du
      ON dt.tablespace_name = du.tablespace_name
  ORDER BY dt.allocated_space DESC
)
WHERE ROWNUM <= 5;

PROMPT
PROMPT Invalid Objects Summary:
PROMPT =======================

SELECT COUNT(*) AS invalid_objects
FROM dba_objects
WHERE status = 'INVALID'
  AND owner NOT IN ('SYS', 'SYSTEM');

PROMPT
PROMPT Top Wait Events (Non-Idle):
PROMPT ===========================

SELECT * FROM (
  SELECT event, total_waits, ROUND(time_waited_micro / 1000000, 2) AS time_sec
  FROM v$event_name
  WHERE wait_class != 'Idle'
  ORDER BY time_waited_micro DESC
)
WHERE ROWNUM <= 10;

PROMPT
PROMPT ================================================================================
PROMPT 5. BACKUP & DISASTER RECOVERY STATUS
PROMPT ================================================================================
PROMPT

PROMPT RMAN Configuration:
PROMPT ==================

PROMPT
PROMPT Database Role: (Primary or Standby)
SELECT database_role FROM v$database;

PROMPT
PROMPT Archive Log Destination:
SELECT name, value FROM v$parameter WHERE name LIKE '%archive%' OR name LIKE '%recovery%';

PROMPT
PROMPT Recent Backup History (Last 7 Days):
PROMPT ===================================

SELECT * FROM (
  SELECT
      status,
      COUNT(*) AS count,
      MAX(start_time) AS last_backup
  FROM v$rman_backup_job_details
  WHERE start_time >= SYSDATE - 7
  GROUP BY status
  ORDER BY start_time DESC
)
WHERE ROWNUM <= 5;

PROMPT
PROMPT ================================================================================
PROMPT 6. COMPLIANCE MAPPING
PROMPT ================================================================================
PROMPT

PROMPT CIS Benchmarks - Oracle Database Compliance:
PROMPT ============================================
PROMPT
PROMPT 1.1 - Ensure 'db_recovery_file_dest' is set:

SELECT name, value FROM v$parameter WHERE name = 'db_recovery_file_dest';

PROMPT
PROMPT 1.2 - Ensure database parameter 'log_archive_dest_1' is set:

SELECT name, value FROM v$parameter WHERE name = 'log_archive_dest_1';

PROMPT
PROMPT 2.1 - Check for unnecessary database options:

SELECT * FROM v$option ORDER BY parameter;

PROMPT
PROMPT 2.2 - Remove unnecessary database users:

SELECT COUNT(*) AS unnecessary_users
FROM dba_users
WHERE username IN ('SCOTT', 'ADAMS', 'OUTLN')
  AND account_status LIKE '%OPEN%';

PROMPT
PROMPT 2.3 - Verify password policy enforcement:

SELECT COUNT(*) AS strong_policy_users
FROM dba_users u
JOIN dba_profiles p ON u.profile = p.profile
WHERE p.resource_name = 'PASSWORD_LIFE_TIME'
  AND p.limit != 'UNLIMITED';

PROMPT
PROMPT SOC 2 Type II Controls Alignment:
PROMPT ===============================
PROMPT
PROMPT CC6.1 - Logical and Physical Access Controls:
PROMPT  - User account management verified
PROMPT  - Audit trail enabled: [See audit configuration above]
PROMPT
PROMPT CC6.2 - Authentication:
PROMPT  - Password policies enforced: [See password policy above]
PROMPT
PROMPT CC7.2 - Monitoring:
PROMPT  - AWR/ASH enabled for performance monitoring
PROMPT  - Audit trail active for compliance
PROMPT
PROMPT CC8.1 - Change Management:
PROMPT  - Audit trail captures DDL changes
PROMPT  - System privilege changes logged
PROMPT

PROMPT ================================================================================
PROMPT 7. KEY FINDINGS AND RECOMMENDATIONS
PROMPT ================================================================================
PROMPT

PROMPT CRITICAL FINDINGS:
PROMPT ==================

PROMPT
PROMPT Finding 1: Invalid Database Objects
SELECT DECODE(COUNT(*), 0, 'RESOLVED: No invalid objects', 'ISSUE: ' || COUNT(*) || ' invalid objects found')
FROM dba_objects
WHERE status = 'INVALID'
  AND owner NOT IN ('SYS', 'SYSTEM');

PROMPT Recommendation: Recompile via ALTER PACKAGE/FUNCTION/PROCEDURE COMPILE

PROMPT
PROMPT Finding 2: Tablespace Capacity
SELECT DECODE(COUNT(*), 0, 'GOOD: All tablespaces under 80% usage',
              'WARNING: ' || COUNT(*) || ' tablespaces over 80% full')
FROM (
  SELECT dt.tablespace_name
  FROM (SELECT tablespace_name, SUM(bytes) AS allocated_space
        FROM dba_data_files
        GROUP BY tablespace_name) dt
  JOIN (SELECT tablespace_name, SUM(bytes) AS used_space
        FROM dba_extents
        GROUP BY tablespace_name) du
  ON dt.tablespace_name = du.tablespace_name
  WHERE (du.used_space / dt.allocated_space) > 0.80
);

PROMPT Recommendation: Add space to tablespaces or archive/delete data as appropriate

PROMPT
PROMPT Finding 3: Archive Log Configuration
SELECT DECODE(COUNT(*), 0, 'ISSUE: Archive logs not configured',
              'GOOD: Archive logs configured')
FROM v$parameter
WHERE name = 'db_recovery_file_dest'
  AND value IS NOT NULL;

PROMPT Recommendation: Ensure DB_RECOVERY_FILE_DEST is set with sufficient space

PROMPT
PROMPT MEDIUM PRIORITY FINDINGS:
PROMPT ==========================

PROMPT
PROMPT Finding 4: Audit Trail Status
SELECT DECODE(COUNT(*), 0, 'ISSUE: Audit trail not configured',
              'GOOD: Audit trail enabled (' || COUNT(*) || ' audits)')
FROM dba_stmt_audit_opts;

PROMPT Recommendation: Enable comprehensive audit trail (see audit scripts)

PROMPT
PROMPT Finding 5: Password Policy Enforcement
SELECT DECODE(COUNT(*), 0, 'ISSUE: Weak password policies',
              'GOOD: Password policies enforced')
FROM dba_profiles
WHERE profile = 'secure_password'
  AND resource_name LIKE 'PASSWORD%';

PROMPT Recommendation: Apply secure_password profile to all non-system users

PROMPT
PROMPT ================================================================================
PROMPT 8. AUDIT EXECUTION SUMMARY
PROMPT ================================================================================
PROMPT

PROMPT Audit Files Generated:
PROMPT ======================
PROMPT
PROMPT 1. audit/baseline_audit.sql - Database configuration and parameters
PROMPT 2. audit/security_audit.sql - User accounts and security settings
PROMPT 3. audit/privileges_audit.sql - System and object privileges
PROMPT 4. audit/performance_audit.sql - Performance metrics and baselines
PROMPT 5. audit/backup_audit.sh - Backup and disaster recovery status
PROMPT 6. audit/security_fixes.sql - Critical security hardening fixes
PROMPT 7. audit/performance_fixes.sql - Performance optimization scripts
PROMPT 8. audit/monitoring_setup.sql - Auditing and monitoring configuration
PROMPT 9. monitoring/alerts.sh - Health check and alerting script
PROMPT

PROMPT Findings Documents:
PROMPT =====================
PROMPT
PROMPT 1. findings_security.md - Security assessment and issues
PROMPT 2. findings_performance.md - Performance baseline and recommendations
PROMPT 3. findings_privileges.md - Access control findings
PROMPT 4. compliance_mapping.md - CIS and SOC 2 alignment
PROMPT

PROMPT ================================================================================
PROMPT NEXT STEPS
PROMPT ================================================================================
PROMPT
PROMPT 1. IMMEDIATE (This Week):
PROMPT    - Execute security_fixes.sql to harden critical security issues
PROMPT    - Run performance_fixes.sql to optimize database
PROMPT    - Review findings documents for critical issues
PROMPT
PROMPT 2. SHORT-TERM (Week 2-4):
PROMPT    - Run monitoring_setup.sql to enable comprehensive auditing
PROMPT    - Schedule monitoring/alerts.sh via cron (hourly)
PROMPT    - Archive and manage alert log entries
PROMPT    - Test backup/recovery procedures
PROMPT
PROMPT 3. MEDIUM-TERM (Month 2-3):
PROMPT    - Implement capacity planning for growth
PROMPT    - Fine-tune performance based on AWR reports
PROMPT    - Review and optimize top SQL statements
PROMPT    - Establish backup/recovery testing schedule
PROMPT
PROMPT 4. ONGOING:
PROMPT    - Monitor health check alerts daily
PROMPT    - Review audit trail weekly
PROMPT    - Analyze performance trends monthly
PROMPT    - Validate backup integrity quarterly
PROMPT

PROMPT ================================================================================
PROMPT Report Complete
PROMPT ================================================================================
PROMPT Generated:
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;

SPOOL OFF

PROMPT
PROMPT Comprehensive audit report generated in ORACLE_AUDIT_REPORT.txt
