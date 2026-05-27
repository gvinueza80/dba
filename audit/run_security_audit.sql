SET ECHO OFF
SET HEADING ON
SET PAGESIZE 50
SET LINESIZE 180
SET FEEDBACK ON
SET TRIMSPOOL ON
SET SQLPROMPT ""

WHENEVER SQLERROR CONTINUE
WHENEVER OSERROR CONTINUE

SPOOL security_assessment_output.txt APPEND

PROMPT ================================================================================
PROMPT Oracle Database Security Posture Assessment
PROMPT ================================================================================
PROMPT Date:
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') AS assessment_date FROM dual;

PROMPT
PROMPT Database Instance:
SELECT name FROM v$database;

-- =============================================================================
-- SECTION 1: DEFAULT ACCOUNTS STATUS
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 1: DEFAULT ACCOUNTS STATUS
PROMPT CIS Benchmark 1.1, 1.2, 1.3 - Default Accounts Management
PROMPT ================================================================================
PROMPT

PROMPT Default Accounts (SYS, SYSTEM, DBSNMP, APPQOSSYS, DGPROPUSER, GSMADMIN_INTERNAL, LBACSYS, MDSYS, OJVMSYS, OLAPSYS, ORDDATA, ORDSYS, OUTLN, WMSYS, XDB):
SELECT
    username,
    account_status,
    lock_date,
    expiry_date,
    created
FROM dba_users
WHERE username IN ('SYS', 'SYSTEM', 'DBSNMP', 'APPQOSSYS', 'DGPROPUSER', 'GSMADMIN_INTERNAL',
                   'LBACSYS', 'MDSYS', 'OJVMSYS', 'OLAPSYS', 'ORDDATA', 'ORDSYS', 'OUTLN', 'WMSYS', 'XDB')
ORDER BY username;

PROMPT
PROMPT
PROMPT All Default Accounts Detail (including tablespaces):
SELECT
    username,
    account_status,
    created,
    lock_date,
    expiry_date,
    default_tablespace,
    temporary_tablespace
FROM dba_users
WHERE username IN ('SYS', 'SYSTEM', 'DBSNMP', 'APPQOSSYS', 'DGPROPUSER', 'GSMADMIN_INTERNAL',
                   'LBACSYS', 'MDSYS', 'OJVMSYS', 'OLAPSYS', 'ORDDATA', 'ORDSYS', 'OUTLN', 'WMSYS', 'XDB')
ORDER BY created;

-- =============================================================================
-- SECTION 2: PASSWORD POLICY SETTINGS
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 2: PASSWORD POLICY SETTINGS
PROMPT CIS Benchmark 1.5.1 - Password Parameters
PROMPT ================================================================================
PROMPT

PROMPT Default Profile Password Settings:
SELECT
    profile,
    resource_name,
    resource_type,
    limit
FROM dba_profiles
WHERE profile = 'DEFAULT'
AND resource_name IN ('FAILED_LOGIN_ATTEMPTS', 'PASSWORD_LIFE_TIME', 'PASSWORD_GRACE_TIME',
                      'PASSWORD_REUSE_TIME', 'PASSWORD_VERIFY_FUNCTION')
ORDER BY resource_name;

PROMPT
PROMPT
PROMPT All Profiles with Password Policies:
SELECT
    profile,
    resource_name,
    limit
FROM dba_profiles
WHERE resource_type = 'PASSWORD'
ORDER BY profile, resource_name;

-- =============================================================================
-- SECTION 3: USERS WITH DBA ROLE
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 3: USERS WITH DBA ROLE ASSIGNMENT
PROMPT CIS Benchmark 1.3.4 - Limited DBA Privilege Grants
PROMPT ================================================================================
PROMPT

PROMPT Users with DBA Role:
SELECT
    u.username,
    u.account_status,
    u.created,
    'DBA' as role_granted
FROM dba_users u
INNER JOIN dba_role_privs drp ON u.username = drp.grantee
WHERE drp.granted_role = 'DBA'
ORDER BY u.username;

PROMPT
PROMPT
PROMPT DBA Role Privilege Details:
SELECT
    grantee,
    granted_role,
    admin_option,
    delegate_option
FROM dba_role_privs
WHERE granted_role = 'DBA'
ORDER BY grantee;

-- =============================================================================
-- SECTION 4: USERS WITH SYSDBA/SYSOPER PRIVILEGE
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 4: USERS WITH SYSDBA/SYSOPER PRIVILEGE
PROMPT CIS Benchmark 1.3.1, 1.3.2 - SYSDBA/SYSOPER Privilege Management
PROMPT ================================================================================
PROMPT

PROMPT Users with SYSDBA/SYSOPER Privileges (from password file):
SELECT
    SYSDBA,
    SYSOPER,
    SYSASM,
    SYSDG,
    SYSKM,
    SYSRAC,
    USERNAME
FROM v$pwfile_users
ORDER BY USERNAME;

-- =============================================================================
-- SECTION 5: AUDIT TRAIL CONFIGURATION
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 5: AUDIT TRAIL CONFIGURATION
PROMPT CIS Benchmark 1.6.1, 1.6.3 - Audit Trail Settings
PROMPT ================================================================================
PROMPT

PROMPT AUDIT_TRAIL Parameter Setting:
SELECT
    name,
    value,
    type,
    display_value
FROM v$parameter
WHERE name = 'audit_trail'
ORDER BY name;

PROMPT
PROMPT
PROMPT All Audit Related Parameters:
SELECT
    name,
    value,
    type,
    display_value
FROM v$parameter
WHERE name LIKE '%audit%'
ORDER BY name;

-- =============================================================================
-- SECTION 6: AUTHENTICATION METHOD PARAMETERS
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 6: AUTHENTICATION METHOD PARAMETERS
PROMPT CIS Benchmark 2.2.1, 2.2.2 - External Authentication
PROMPT ================================================================================
PROMPT

PROMPT Authentication Related Parameters:
SELECT
    name,
    value,
    type,
    display_value
FROM v$parameter
WHERE name IN ('os_authent_prefix', 'remote_os_authent', 'remote_login_passwordfile', 'ldap_directory_access')
ORDER BY name;

-- =============================================================================
-- SECTION 7: ENCRYPTION SETTINGS
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 7: ENCRYPTION SETTINGS
PROMPT CIS Benchmark 2.3.1, 2.3.2 - Encryption Parameters
PROMPT ================================================================================
PROMPT

PROMPT Encryption Related Parameters:
SELECT
    name,
    value,
    type,
    display_value
FROM v$parameter
WHERE name LIKE '%encrypt%'
OR name LIKE '%crypto%'
OR name LIKE '%tde%'
ORDER BY name;

-- =============================================================================
-- SECTION 8: USERS WITH NO PASSWORD EXPIRY
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 8: USERS WITH NO PASSWORD EXPIRY
PROMPT CIS Benchmark 1.5.1 - Password Expiration
PROMPT ================================================================================
PROMPT

PROMPT Users with PASSWORD_LIFE_TIME = UNLIMITED (No Expiry):
SELECT
    du.username,
    du.account_status,
    du.created,
    dp.limit as password_life_time
FROM dba_users du
LEFT JOIN dba_profiles dp ON du.profile = dp.profile
    AND dp.resource_name = 'PASSWORD_LIFE_TIME'
WHERE du.profile = 'DEFAULT'
AND (dp.limit = 'UNLIMITED' OR dp.limit IS NULL)
AND du.username NOT IN ('SYS', 'SYSTEM')
ORDER BY du.username;

-- =============================================================================
-- SECTION 9: SYSTEM PRIVILEGES AUDIT
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 9: SYSTEM PRIVILEGES AUDIT
PROMPT CIS Benchmark 1.3.3, 1.3.4 - System Privilege Auditing
PROMPT ================================================================================
PROMPT

PROMPT Users with CREATE USER, DROP USER, ALTER USER Privileges:
SELECT
    grantee,
    privilege,
    admin_option
FROM dba_sys_privs
WHERE privilege IN ('CREATE USER', 'DROP USER', 'ALTER USER', 'SYSDBA', 'SYSOPER')
AND grantee NOT IN ('SYS', 'SYSTEM', 'DBA')
ORDER BY grantee, privilege;

-- =============================================================================
-- SECTION 10: ROLE PRIVILEGE SUMMARY
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 10: ROLE PRIVILEGE SUMMARY
PROMPT CIS Benchmark 1.3.4 - Role-Based Access Control
PROMPT ================================================================================
PROMPT

PROMPT Roles Granted to Non-Default Users:
SELECT
    grantee,
    granted_role,
    admin_option,
    delegate_option
FROM dba_role_privs
WHERE grantee NOT IN ('SYS', 'SYSTEM', 'DBA', 'CONNECT', 'RESOURCE')
AND grantee NOT LIKE 'ORACLE%'
AND granted_role NOT IN ('CONNECT', 'RESOURCE')
ORDER BY grantee, granted_role;

-- =============================================================================
-- SECTION 11: GRANT OPTIONS ANALYSIS
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 11: USERS WITH ADMIN OPTION ON SYSTEM PRIVILEGES
PROMPT CIS Benchmark 1.3.3 - ADMIN OPTION Auditing
PROMPT ================================================================================
PROMPT

PROMPT System Privileges Granted WITH ADMIN OPTION:
SELECT
    grantee,
    privilege,
    admin_option
FROM dba_sys_privs
WHERE admin_option = 'YES'
AND grantee NOT IN ('SYS', 'SYSTEM')
ORDER BY grantee, privilege;

-- =============================================================================
-- SECTION 12: USER COUNT SUMMARY
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT SECTION 12: USER SUMMARY STATISTICS
PROMPT ================================================================================
PROMPT

PROMPT Total User Count:
SELECT COUNT(*) as total_users FROM dba_users;

PROMPT
PROMPT Active vs Locked Accounts:
SELECT
    account_status,
    COUNT(*) as user_count
FROM dba_users
GROUP BY account_status
ORDER BY account_status;

PROMPT
PROMPT
PROMPT Database Roles Count:
SELECT COUNT(*) as total_roles FROM dba_roles;

-- =============================================================================
-- COMPLETION
-- =============================================================================
PROMPT
PROMPT ================================================================================
PROMPT Security Assessment Completed
PROMPT ================================================================================
PROMPT Timestamp:
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') AS completion_time FROM dual;

SPOOL OFF
EXIT;
