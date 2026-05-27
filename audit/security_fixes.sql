-- Oracle Database Critical Security Hardening Fixes
-- Run as: sqlplus / as sysdba @security_fixes.sql
-- WARNING: This script makes permanent changes. Review before running.

SET ECHO ON
SET FEEDBACK ON
SET PAGESIZE 50
SET LINESIZE 200
SPOOL security_fixes.log

PROMPT ================================================================================
PROMPT ORACLE CRITICAL SECURITY HARDENING FIXES
PROMPT Start Time:
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;

-- =============================================================================
-- PART 1: LOCK DEFAULT/UNNECESSARY ACCOUNTS
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 1: LOCK UNUSED DEFAULT ACCOUNTS
PROMPT ================================================================================

PROMPT Locking OUTLN account (used only for explain plan storage)...
ALTER USER outln ACCOUNT LOCK;
PROMPT OUTLN account locked.

PROMPT Locking SCOTT account (demo user - should not exist in production)...
BEGIN
  FOR u IN (SELECT username FROM dba_users WHERE username = 'SCOTT' AND account_status LIKE '%OPEN%')
  LOOP
    EXECUTE IMMEDIATE 'ALTER USER ' || u.username || ' ACCOUNT LOCK PASSWORD EXPIRE';
  END LOOP;
  IF SQL%ROWCOUNT = 0 THEN
    DBMS_OUTPUT.PUT_LINE('SCOTT account not found or already locked.');
  END IF;
END;
/

PROMPT Locking ADAMS account (demo user)...
BEGIN
  FOR u IN (SELECT username FROM dba_users WHERE username = 'ADAMS' AND account_status LIKE '%OPEN%')
  LOOP
    EXECUTE IMMEDIATE 'ALTER USER ' || u.username || ' ACCOUNT LOCK PASSWORD EXPIRE';
  END LOOP;
END;
/

PROMPT Locking TRACESVR account (trace server - not used in modern versions)...
BEGIN
  FOR u IN (SELECT username FROM dba_users WHERE username = 'TRACESVR' AND account_status LIKE '%OPEN%')
  LOOP
    EXECUTE IMMEDIATE 'ALTER USER ' || u.username || ' ACCOUNT LOCK PASSWORD EXPIRE';
  END LOOP;
END;
/

PROMPT Locking CTXSYS account if not needed...
BEGIN
  FOR u IN (SELECT username FROM dba_users WHERE username = 'CTXSYS' AND account_status LIKE '%OPEN%')
  LOOP
    DBMS_OUTPUT.PUT_LINE('CTXSYS is text search module - only lock if not in use.');
    -- EXECUTE IMMEDIATE 'ALTER USER ' || u.username || ' ACCOUNT LOCK';
  END LOOP;
END;
/

PROMPT Locking WMSYS account if not needed...
BEGIN
  FOR u IN (SELECT username FROM dba_users WHERE username = 'WMSYS' AND account_status LIKE '%OPEN%')
  LOOP
    DBMS_OUTPUT.PUT_LINE('WMSYS is workspace manager - only lock if not in use.');
    -- EXECUTE IMMEDIATE 'ALTER USER ' || u.username || ' ACCOUNT LOCK';
  END LOOP;
END;
/

-- =============================================================================
-- PART 2: ENFORCE STRONG PASSWORD POLICIES
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 2: ENABLE AND ENFORCE PASSWORD COMPLEXITY POLICY
PROMPT ================================================================================

PROMPT Creating verify_function_11g for password complexity...
CREATE OR REPLACE FUNCTION verify_function_11g(
    username varchar2,
    password varchar2,
    old_password varchar2
)
RETURN boolean IS
    n boolean;
    m integer;
    differ integer;
BEGIN
    -- Check minimum length (at least 8 characters)
    IF length(password) < 8 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Password must be at least 8 characters long');
    END IF;

    -- Check for uppercase letter
    n := regexp_like(password, '[A-Z]');
    IF NOT n THEN
        RAISE_APPLICATION_ERROR(-20002, 'Password must contain at least one uppercase letter');
    END IF;

    -- Check for lowercase letter
    n := regexp_like(password, '[a-z]');
    IF NOT n THEN
        RAISE_APPLICATION_ERROR(-20003, 'Password must contain at least one lowercase letter');
    END IF;

    -- Check for digit
    n := regexp_like(password, '[0-9]');
    IF NOT n THEN
        RAISE_APPLICATION_ERROR(-20004, 'Password must contain at least one digit');
    END IF;

    -- Check for special character
    n := regexp_like(password, '[!@#$%^&*()_+\-=\[\]{};:''"<>?,./]');
    IF NOT n THEN
        RAISE_APPLICATION_ERROR(-20005, 'Password must contain at least one special character');
    END IF;

    -- Check if password contains username
    IF instr(upper(password), upper(username)) > 0 THEN
        RAISE_APPLICATION_ERROR(-20006, 'Password cannot contain username');
    END IF;

    -- Check differences from old password (if not first password)
    IF old_password IS NOT NULL THEN
        differ := 0;
        m := length(old_password);
        FOR i IN 1 .. greatest(length(password), m) LOOP
            IF substr(password, i, 1) != substr(old_password, i, 1) THEN
                differ := differ + 1;
            END IF;
        END LOOP;
        IF differ < 4 THEN
            RAISE_APPLICATION_ERROR(-20007, 'New password must differ by at least 4 characters');
        END IF;
    END IF;

    RETURN true;
END verify_function_11g;
/

SHOW ERRORS;

PROMPT Password verification function created successfully.

PROMPT Creating PASSWORD profile with strong requirements...
BEGIN
  EXECUTE IMMEDIATE 'DROP PROFILE secure_password LIMIT PASSWORD_LIFE_TIME UNLIMITED PASSWORD_GRACE_TIME UNLIMITED';
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
/

CREATE PROFILE secure_password LIMIT
    FAILED_LOGIN_ATTEMPTS 5
    PASSWORD_LOCK_TIME 1/24  -- Lock for 1 hour
    PASSWORD_LIFE_TIME 90    -- Expire password every 90 days
    PASSWORD_GRACE_TIME 7    -- 7-day grace period before expiration
    PASSWORD_REUSE_TIME 365
    PASSWORD_REUSE_MAX 5
    PASSWORD_VERIFY_FUNCTION verify_function_11g;

PROMPT Secure password profile created.

PROMPT Applying secure password profile to all non-SYS users...
DECLARE
  v_count INTEGER := 0;
BEGIN
  FOR user_rec IN (
    SELECT username
    FROM dba_users
    WHERE username NOT IN ('SYS', 'SYSTEM')
      AND account_status = 'OPEN'
  )
  LOOP
    BEGIN
      EXECUTE IMMEDIATE 'ALTER USER ' || user_rec.username || ' PROFILE secure_password';
      v_count := v_count + 1;
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Warning: Could not apply profile to ' || user_rec.username);
    END;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE('Applied secure_password profile to ' || v_count || ' users.');
END;
/

-- =============================================================================
-- PART 3: REVOKE DANGEROUS PRIVILEGES FROM PUBLIC
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 3: REVOKE DANGEROUS PRIVILEGES FROM PUBLIC
PROMPT ================================================================================

PROMPT Revoking EXECUTE on DBMS_SQL from PUBLIC...
BEGIN
  EXECUTE IMMEDIATE 'REVOKE EXECUTE ON sys.dbms_sql FROM PUBLIC';
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Note: DBMS_SQL privilege may already be revoked');
END;
/

PROMPT Revoking EXECUTE on DBMS_JAVA from PUBLIC...
BEGIN
  EXECUTE IMMEDIATE 'REVOKE EXECUTE ON sys.dbms_java FROM PUBLIC';
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Note: DBMS_JAVA privilege may already be revoked');
END;
/

PROMPT Revoking EXECUTE on DBMS_EXPORT_EXTENSION from PUBLIC...
BEGIN
  EXECUTE IMMEDIATE 'REVOKE EXECUTE ON sys.dbms_export_extension FROM PUBLIC';
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
/

PROMPT Revoking UTL_FILE privileges from PUBLIC...
BEGIN
  EXECUTE IMMEDIATE 'REVOKE EXECUTE ON sys.utl_file FROM PUBLIC';
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Note: UTL_FILE privilege may already be revoked');
END;
/

-- =============================================================================
-- PART 4: ENABLE AUDIT TRAIL
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 4: ENABLE COMPREHENSIVE AUDIT TRAIL
PROMPT ================================================================================

PROMPT Enabling basic auditing...
AUDIT ALL BY SYS BY ACCESS;

PROMPT Auditing database administration activities...
AUDIT CREATE ANY TABLE BY ACCESS;
AUDIT DROP ANY TABLE BY ACCESS;
AUDIT ALTER ANY TABLE BY ACCESS;
AUDIT EXECUTE ANY PROCEDURE BY ACCESS;
AUDIT GRANT ANY PRIVILEGE BY ACCESS;

PROMPT Auditing privilege grants and revokes...
AUDIT GRANT BY ACCESS;
AUDIT REVOKE BY ACCESS;

PROMPT Auditing user/role management...
AUDIT CREATE USER BY ACCESS;
AUDIT ALTER USER BY ACCESS;
AUDIT DROP USER BY ACCESS;
AUDIT CREATE ROLE BY ACCESS;
AUDIT DROP ROLE BY ACCESS;

PROMPT Auditing failed login attempts...
AUDIT CREATE SESSION BY ACCESS WHENEVER NOT SUCCESSFUL;

PROMPT Auditing data access (selective)...
AUDIT SELECT ON dba_tables BY ACCESS;
AUDIT INSERT ON dba_tables BY ACCESS;
AUDIT UPDATE ON dba_tables BY ACCESS;
AUDIT DELETE ON dba_tables BY ACCESS;

-- =============================================================================
-- PART 5: SET PARAMETER SECURITY OPTIONS
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 5: CONFIGURE SECURITY-RELATED DATABASE PARAMETERS
PROMPT ================================================================================

PROMPT Setting SQL92_SECURITY to prevent select from non-existent tables...
BEGIN
  EXECUTE IMMEDIATE 'ALTER SYSTEM SET sql92_security=TRUE SCOPE=BOTH';
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Warning: sql92_security may not be settable on this version');
END;
/

PROMPT Setting O7_DICTIONARY_ACCESSIBILITY to prevent dictionary access...
BEGIN
  EXECUTE IMMEDIATE 'ALTER SYSTEM SET O7_DICTIONARY_ACCESSIBILITY=FALSE SCOPE=BOTH';
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Note: O7_DICTIONARY_ACCESSIBILITY configuration attempted');
END;
/

-- =============================================================================
-- PART 6: VERIFICATION AND SUMMARY
-- =============================================================================

PROMPT
PROMPT ================================================================================
PROMPT PART 6: VERIFICATION OF SECURITY FIXES
PROMPT ================================================================================

PROMPT Locked Accounts Status:
SELECT username, account_status
FROM dba_users
WHERE username IN ('OUTLN', 'SCOTT', 'ADAMS', 'TRACESVR')
ORDER BY username;

PROMPT
PROMPT Current Profiles:
SELECT profile FROM dba_profiles GROUP BY profile ORDER BY profile;

PROMPT
PROMPT Password Policy Settings:
SELECT profile, resource_name, resource_type, limit
FROM dba_profiles
WHERE profile = 'secure_password'
AND resource_name LIKE 'PASSWORD%'
ORDER BY resource_name;

PROMPT
PROMPT Audit Trail Status:
SELECT * FROM v$option WHERE parameter = 'Auditing';

PROMPT
PROMPT ================================================================================
PROMPT SECURITY HARDENING COMPLETE
PROMPT ================================================================================
PROMPT End Time:
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;

SPOOL OFF

PROMPT
PROMPT Security hardening complete. Check security_fixes.log for details.
PROMPT
PROMPT IMPORTANT POST-EXECUTION STEPS:
PROMPT 1. Review the security_fixes.log file
PROMPT 2. Verify all changes with SELECT queries
PROMPT 3. Test password policy with a new user creation
PROMPT 4. Run audit trail queries to verify collection
PROMPT 5. Document all changes in the audit trail
