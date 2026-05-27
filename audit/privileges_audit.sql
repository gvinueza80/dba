-- =============================================================================
-- Oracle Database Privilege & Access Control Audit Script
-- CIS Oracle Database Benchmarks v1.1.1 - Access Control Assessment
-- =============================================================================

SET ECHO ON
SET HEADING ON
SET PAGESIZE 50
SET LINESIZE 200
SET FEEDBACK ON
SET TRIMSPOOL ON

SPOOL privileges_assessment_output.txt

PROMPT ================================================================================
PROMPT Oracle Database Privilege & Access Control Audit
PROMPT ================================================================================
PROMPT Date:
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') AS assessment_date FROM dual;

PROMPT
PROMPT Database Instance:
SELECT name FROM v$database;

-- =============================================================================
-- SECTION 1: DANGEROUS SYSTEM PRIVILEGES GRANTED TO USERS
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 1: DANGEROUS SYSTEM PRIVILEGES GRANTED TO USERS
PROMPT CIS Benchmark 1.3.3 - System Privilege Auditing
PROMPT ================================================================================
PROMPT

PROMPT Dangerous System Privileges (ALTER SYSTEM, DROP USER, ALTER TABLESPACE, etc.):
SELECT
    grantee,
    COUNT(*) as dangerous_privilege_count,
    LISTAGG(privilege, ', ') WITHIN GROUP (ORDER BY privilege) as dangerous_privileges
FROM dba_sys_privs
WHERE privilege IN (
    'ALTER SYSTEM',           -- Modify critical database parameters
    'DROP USER',              -- Delete any user account
    'ALTER USER',             -- Modify user accounts including passwords
    'CREATE USER',            -- Create new user accounts
    'DROP TABLESPACE',        -- Delete entire tablespaces
    'ALTER TABLESPACE',       -- Modify tablespace properties
    'CREATE TABLESPACE',      -- Create new tablespaces
    'DROP ANY TABLE',         -- Delete any table in database
    'CREATE ANY TABLE',       -- Create tables in any schema
    'BECOME USER',            -- Impersonate any user
    'ALTER DATABASE',         -- Modify database configuration
    'GRANT ANY PRIVILEGE',    -- Grant any privilege to others
    'GRANT ANY ROLE',         -- Grant any role to others
    'ADMIN OPTION FOR',       -- Grant role with admin option
    'RESTRICTED SESSION'      -- Connect during restricted mode
)
AND grantee NOT IN ('SYS', 'SYSTEM', 'DBA', 'SCHEDULER_ADMIN')
GROUP BY grantee
ORDER BY dangerous_privilege_count DESC;

PROMPT
PROMPT
PROMPT Detailed Dangerous Privileges Listing:
SELECT
    grantee,
    privilege,
    admin_option,
    'DANGEROUS' as privilege_classification
FROM dba_sys_privs
WHERE privilege IN (
    'ALTER SYSTEM', 'DROP USER', 'ALTER USER', 'CREATE USER',
    'DROP TABLESPACE', 'ALTER TABLESPACE', 'CREATE TABLESPACE',
    'DROP ANY TABLE', 'CREATE ANY TABLE', 'BECOME USER',
    'ALTER DATABASE', 'GRANT ANY PRIVILEGE', 'GRANT ANY ROLE',
    'ADMIN OPTION FOR', 'RESTRICTED SESSION'
)
AND grantee NOT IN ('SYS', 'SYSTEM', 'DBA', 'SCHEDULER_ADMIN')
ORDER BY grantee, privilege;

-- =============================================================================
-- SECTION 2: SYSTEM PRIVILEGES GRANTED TO USERS (ALL)
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 2: ALL SYSTEM PRIVILEGES GRANTED TO USERS
PROMPT CIS Benchmark 1.3.3, 1.3.4 - Complete Privilege Inventory
PROMPT ================================================================================
PROMPT

PROMPT All System Privileges Granted to Non-Default Users:
SELECT
    grantee,
    COUNT(*) as total_privileges,
    LISTAGG(privilege, ', ') WITHIN GROUP (ORDER BY privilege) as all_privileges
FROM dba_sys_privs
WHERE grantee NOT IN ('SYS', 'SYSTEM', 'DBA', 'SCHEDULER_ADMIN')
AND grantee NOT LIKE 'ORACLE%'
GROUP BY grantee
ORDER BY grantee;

PROMPT
PROMPT
PROMPT System Privileges Detail (with ADMIN OPTION):
SELECT
    grantee,
    privilege,
    admin_option,
    CASE
        WHEN privilege IN ('ALTER SYSTEM', 'DROP USER', 'ALTER USER', 'CREATE USER',
                          'DROP TABLESPACE', 'ALTER TABLESPACE', 'CREATE TABLESPACE',
                          'DROP ANY TABLE', 'CREATE ANY TABLE', 'BECOME USER',
                          'ALTER DATABASE', 'GRANT ANY PRIVILEGE', 'GRANT ANY ROLE')
        THEN 'CRITICAL'
        WHEN privilege LIKE '%ANY%' OR privilege LIKE '%ADMIN%'
        THEN 'HIGH'
        ELSE 'MEDIUM'
    END as risk_level
FROM dba_sys_privs
WHERE grantee NOT IN ('SYS', 'SYSTEM', 'DBA', 'SCHEDULER_ADMIN')
AND grantee NOT LIKE 'ORACLE%'
ORDER BY grantee, risk_level DESC, privilege;

-- =============================================================================
-- SECTION 3: SYSTEM PRIVILEGES WITH ADMIN OPTION
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 3: SYSTEM PRIVILEGES GRANTED WITH ADMIN OPTION
PROMPT CIS Benchmark 1.3.3 - ADMIN OPTION Auditing
PROMPT ================================================================================
PROMPT

PROMPT Users with ADMIN OPTION on System Privileges:
SELECT
    grantee,
    COUNT(*) as admin_option_count,
    LISTAGG(privilege, ', ') WITHIN GROUP (ORDER BY privilege) as privileges_with_admin_option
FROM dba_sys_privs
WHERE admin_option = 'YES'
AND grantee NOT IN ('SYS', 'SYSTEM')
GROUP BY grantee
ORDER BY admin_option_count DESC;

PROMPT
PROMPT
PROMPT Detailed Admin Option Grants:
SELECT
    grantee,
    privilege,
    admin_option
FROM dba_sys_privs
WHERE admin_option = 'YES'
AND grantee NOT IN ('SYS', 'SYSTEM')
ORDER BY grantee, privilege;

-- =============================================================================
-- SECTION 4: ROLE ASSIGNMENTS AND INHERITANCE
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 4: ROLE ASSIGNMENTS TO USERS
PROMPT CIS Benchmark 1.3.4 - Role-Based Access Control
PROMPT ================================================================================
PROMPT

PROMPT All Role Assignments to Users:
SELECT
    grantee,
    granted_role,
    admin_option,
    delegate_option
FROM dba_role_privs
WHERE grantee NOT IN ('SYS', 'SYSTEM')
AND grantee NOT LIKE 'ORACLE%'
ORDER BY grantee, granted_role;

PROMPT
PROMPT
PROMPT Role Grants Summary (Count by User):
SELECT
    grantee,
    COUNT(*) as role_count,
    LISTAGG(granted_role, ', ') WITHIN GROUP (ORDER BY granted_role) as roles_assigned
FROM dba_role_privs
WHERE grantee NOT IN ('SYS', 'SYSTEM')
AND grantee NOT LIKE 'ORACLE%'
GROUP BY grantee
ORDER BY role_count DESC, grantee;

PROMPT
PROMPT
PROMPT Roles with Admin/Delegate Option (Privilege Escalation Risk):
SELECT
    grantee,
    granted_role,
    admin_option,
    delegate_option
FROM dba_role_privs
WHERE (admin_option = 'YES' OR delegate_option = 'YES')
AND grantee NOT IN ('SYS', 'SYSTEM')
ORDER BY grantee, granted_role;

-- =============================================================================
-- SECTION 5: PUBLIC PRIVILEGES (EXCESSIVE ACCESS)
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 5: PRIVILEGES GRANTED TO PUBLIC
PROMPT CIS Benchmark 1.4.2, 2.2.4 - PUBLIC Access Control
PROMPT ================================================================================
PROMPT

PROMPT System Privileges Granted to PUBLIC:
SELECT
    grantee,
    privilege,
    admin_option
FROM dba_sys_privs
WHERE grantee = 'PUBLIC'
ORDER BY privilege;

PROMPT
PROMPT
PROMPT Roles Granted to PUBLIC:
SELECT
    grantee,
    granted_role,
    admin_option,
    delegate_option
FROM dba_role_privs
WHERE grantee = 'PUBLIC'
ORDER BY granted_role;

-- =============================================================================
-- SECTION 6: OBJECT PRIVILEGES GRANTED TO PUBLIC
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 6: OBJECT PRIVILEGES GRANTED TO PUBLIC
PROMPT CIS Benchmark 1.4.2 - PUBLIC Access to Database Objects
PROMPT ================================================================================
PROMPT

PROMPT Object Privileges Granted to PUBLIC (Dangerous Objects):
SELECT
    owner,
    table_name,
    grantee,
    privilege,
    grantable
FROM dba_tab_privs
WHERE grantee = 'PUBLIC'
AND privilege IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'ALTER', 'DEBUG', 'EXECUTE')
ORDER BY owner, table_name, privilege;

PROMPT
PROMPT
PROMPT Count of PUBLIC Privileges by Object Type:
SELECT
    owner,
    COUNT(*) as public_privilege_count,
    LISTAGG(DISTINCT privilege, ', ') WITHIN GROUP (ORDER BY privilege) as privileges
FROM dba_tab_privs
WHERE grantee = 'PUBLIC'
ORDER BY owner, public_privilege_count DESC;

PROMPT
PROMPT
PROMPT Sensitive Objects with PUBLIC Access (EXECUTE):
SELECT
    owner,
    table_name,
    grantee,
    privilege
FROM dba_tab_privs
WHERE grantee = 'PUBLIC'
AND privilege = 'EXECUTE'
AND owner NOT IN ('SYS', 'SYSTEM', 'APEX_040200', 'APEX_ADMIN_UTIL')
ORDER BY owner, table_name;

-- =============================================================================
-- SECTION 7: DBA ROLE MEMBERS
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 7: DBA ROLE MEMBERS AND PRIVILEGES
PROMPT CIS Benchmark 1.3.4 - Limited DBA Privilege Grants
PROMPT ================================================================================
PROMPT

PROMPT Users/Roles with DBA Role:
SELECT
    grantee,
    granted_role,
    admin_option,
    delegate_option
FROM dba_role_privs
WHERE granted_role = 'DBA'
ORDER BY grantee;

PROMPT
PROMPT
PROMPT DBA Role Privileges Summary:
SELECT
    COUNT(*) as total_dba_privileges,
    LISTAGG(privilege, ', ') WITHIN GROUP (ORDER BY privilege) as dba_privileges
FROM dba_role_privs drp
INNER JOIN dba_sys_privs dsp ON drp.granted_role = dsp.grantee
WHERE drp.granted_role = 'DBA';

-- =============================================================================
-- SECTION 8: PRIVILEGE ESCALATION RISKS
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 8: PRIVILEGE ESCALATION RISKS
PROMPT CIS Benchmark 1.3.2, 1.3.3 - Privilege Escalation Analysis
PROMPT ================================================================================
PROMPT

PROMPT Users with Privilege Escalation Potential (CREATE/DROP USER):
SELECT
    grantee,
    COUNT(*) as escalation_privilege_count
FROM dba_sys_privs
WHERE privilege IN ('CREATE USER', 'DROP USER', 'ALTER USER', 'BECOME USER',
                   'GRANT ANY PRIVILEGE', 'GRANT ANY ROLE')
AND grantee NOT IN ('SYS', 'SYSTEM', 'DBA')
GROUP BY grantee
HAVING COUNT(*) > 0
ORDER BY escalation_privilege_count DESC;

PROMPT
PROMPT
PROMPT Users with SYSDBA/SYSOPER Equivalence Risk:
SELECT
    grantee,
    COUNT(*) as admin_privilege_count,
    LISTAGG(privilege, ', ') WITHIN GROUP (ORDER BY privilege) as critical_privileges
FROM dba_sys_privs
WHERE privilege IN (
    'ALTER SYSTEM', 'CREATE USER', 'DROP USER', 'ALTER USER',
    'CREATE TABLESPACE', 'ALTER TABLESPACE', 'DROP TABLESPACE',
    'ALTER DATABASE', 'GRANT ANY PRIVILEGE', 'GRANT ANY ROLE',
    'BACKUP ANY TABLE', 'SELECT ANY TABLE', 'BECOME USER'
)
AND grantee NOT IN ('SYS', 'SYSTEM', 'DBA')
GROUP BY grantee
HAVING COUNT(*) >= 3
ORDER BY admin_privilege_count DESC;

-- =============================================================================
-- SECTION 9: OBJECT PRIVILEGE SUMMARY
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 9: EXCESSIVE OBJECT PRIVILEGES GRANTED
PROMPT CIS Benchmark 1.4.1 - Object Privilege Auditing
PROMPT ================================================================================
PROMPT

PROMPT Users with Excessive Object Privileges (SELECT ANY/ALL):
SELECT
    grantee,
    COUNT(*) as object_privilege_count,
    LISTAGG(DISTINCT privilege, ', ') WITHIN GROUP (ORDER BY privilege) as privileges
FROM dba_tab_privs
WHERE grantee NOT IN ('SYS', 'SYSTEM', 'PUBLIC')
AND grantee NOT LIKE 'ORACLE%'
AND privilege IN ('SELECT ANY', 'INSERT ANY', 'UPDATE ANY', 'DELETE ANY', 'EXECUTE ANY')
GROUP BY grantee
ORDER BY grantee;

PROMPT
PROMPT
PROMPT Users with EXECUTE Privilege on Sensitive Packages:
SELECT
    grantee,
    table_name,
    privilege,
    CASE
        WHEN table_name IN ('DBMS_SQL', 'DBMS_JOB', 'DBMS_SCHEDULER',
                           'SYS.DBMS_UTILITY', 'SYS.DBMS_DDL_INTERNAL')
        THEN 'CRITICAL'
        ELSE 'HIGH'
    END as risk_level
FROM dba_tab_privs
WHERE privilege = 'EXECUTE'
AND table_name IN ('DBMS_SQL', 'DBMS_JOB', 'DBMS_SCHEDULER',
                  'SYS.DBMS_UTILITY', 'SYS.DBMS_DDL_INTERNAL')
AND grantee NOT IN ('SYS', 'SYSTEM')
ORDER BY risk_level DESC, grantee, table_name;

-- =============================================================================
-- SECTION 10: PRIVILEGE SUMMARY STATISTICS
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 10: PRIVILEGE SUMMARY STATISTICS
PROMPT ================================================================================
PROMPT

PROMPT Total System Privileges Granted (Non-Default Users):
SELECT COUNT(*) as total_system_privileges FROM dba_sys_privs
WHERE grantee NOT IN ('SYS', 'SYSTEM', 'DBA');

PROMPT
PROMPT
PROMPT Total Role Assignments (Non-Default Users):
SELECT COUNT(*) as total_role_assignments FROM dba_role_privs
WHERE grantee NOT IN ('SYS', 'SYSTEM');

PROMPT
PROMPT
PROMPT Total Object Privileges (Non-Default Users):
SELECT COUNT(*) as total_object_privileges FROM dba_tab_privs
WHERE grantee NOT IN ('SYS', 'SYSTEM', 'PUBLIC')
AND grantee NOT LIKE 'ORACLE%';

PROMPT
PROMPT
PROMPT Total PUBLIC Privileges (System + Object):
SELECT
    (SELECT COUNT(*) FROM dba_sys_privs WHERE grantee = 'PUBLIC') +
    (SELECT COUNT(*) FROM dba_tab_privs WHERE grantee = 'PUBLIC') as total_public_privileges
FROM dual;

PROMPT
PROMPT
PROMPT Users/Roles with Dangerous Privileges Count:
SELECT
    COUNT(DISTINCT grantee) as user_count_with_dangerous_privs
FROM dba_sys_privs
WHERE privilege IN (
    'ALTER SYSTEM', 'DROP USER', 'ALTER USER', 'CREATE USER',
    'DROP TABLESPACE', 'ALTER TABLESPACE', 'CREATE TABLESPACE',
    'DROP ANY TABLE', 'CREATE ANY TABLE', 'BECOME USER',
    'ALTER DATABASE', 'GRANT ANY PRIVILEGE', 'GRANT ANY ROLE'
)
AND grantee NOT IN ('SYS', 'SYSTEM', 'DBA');

-- =============================================================================
-- SECTION 11: NON-DEFAULT ROLES WITH ADMIN PRIVILEGES
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 11: CUSTOM ROLES WITH ADMIN PRIVILEGES
PROMPT CIS Benchmark 1.3.4 - Role-Based Access Control
PROMPT ================================================================================
PROMPT

PROMPT Custom Roles with System Privileges:
SELECT DISTINCT
    dsp.grantee as role_name,
    COUNT(*) as privilege_count,
    LISTAGG(privilege, ', ') WITHIN GROUP (ORDER BY privilege) as privileges
FROM dba_sys_privs dsp
WHERE dsp.grantee NOT IN ('SYS', 'SYSTEM', 'DBA', 'CONNECT', 'RESOURCE', 'SELECT_CATALOG_ROLE',
                         'EXECUTE_CATALOG_ROLE', 'DELETE_CATALOG_ROLE', 'CAPTURE_ADMIN')
AND dsp.grantee IN (SELECT role FROM dba_roles)
GROUP BY dsp.grantee
ORDER BY privilege_count DESC, dsp.grantee;

-- =============================================================================
-- SECTION 12: LEAST PRIVILEGE VIOLATIONS
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 12: LEAST PRIVILEGE VIOLATION ANALYSIS
PROMPT CIS Benchmark 1.4 - Least Privilege Principle
PROMPT ================================================================================
PROMPT

PROMPT Users with Multiple Privilege Types (Potential Over-Privilege):
SELECT
    u.username,
    (SELECT COUNT(*) FROM dba_sys_privs WHERE grantee = u.username) as sys_priv_count,
    (SELECT COUNT(*) FROM dba_role_privs WHERE grantee = u.username) as role_count,
    (SELECT COUNT(*) FROM dba_tab_privs WHERE grantee = u.username) as obj_priv_count,
    ((SELECT COUNT(*) FROM dba_sys_privs WHERE grantee = u.username) +
     (SELECT COUNT(*) FROM dba_role_privs WHERE grantee = u.username) +
     (SELECT COUNT(*) FROM dba_tab_privs WHERE grantee = u.username)) as total_privilege_count
FROM dba_users u
WHERE u.username NOT IN ('SYS', 'SYSTEM', 'DBSNMP', 'AUDSYS', 'GSMADMIN_INTERNAL',
                         'LBACSYS', 'MDSYS', 'OJVMSYS', 'OLAPSYS', 'ORDDATA',
                         'ORDSYS', 'OUTLN', 'WMSYS', 'XDB', 'APEX_040200', 'APEX_ADMIN_UTIL')
AND u.account_status != 'LOCKED'
HAVING ((SELECT COUNT(*) FROM dba_sys_privs WHERE grantee = u.username) +
        (SELECT COUNT(*) FROM dba_role_privs WHERE grantee = u.username) +
        (SELECT COUNT(*) FROM dba_tab_privs WHERE grantee = u.username)) > 0
ORDER BY total_privilege_count DESC;

-- =============================================================================
-- COMPLETION
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT Privilege Audit Completed
PROMPT ================================================================================
PROMPT Timestamp:
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') AS completion_time FROM dual;

SPOOL OFF
SET ECHO OFF
EXIT;
