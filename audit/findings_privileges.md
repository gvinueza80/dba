# Oracle Database Privilege & Access Control Audit - Findings

**Database:** PRODDB (Oracle 19c Enterprise Edition)
**Assessment Date:** 2026-05-27
**Compliance Framework:** CIS Oracle Database Benchmarks v1.1.1
**Status:** REVIEW REQUIRED - Critical findings present

---

## Executive Summary

The privilege audit identified **4 critical issues**, **3 high-priority issues**, and **2 medium-priority improvements**. APP_ADMIN holds DBA role plus 25 system privileges, creating SYSDBA equivalence. Three users have privilege escalation potential. PUBLIC privileges include dangerous system packages (DBMS_SQL, UTL_FILE, UTL_HTTP).

**Risk Assessment:** HIGH RISK - Immediate action required

---

## Critical Issues

### 1. APP_ADMIN with DBA Role + Dangerous System Privileges
**Risk:** CRITICAL | **CIS:** 1.3.3, 1.3.4

Current: APP_ADMIN has 41 total privileges (DBA role + 25 system + 15 object)
- ALTER SYSTEM (with ADMIN OPTION)
- CREATE/DROP USER (with ADMIN OPTION)  
- ALTER TABLESPACE (with ADMIN OPTION)
- GRANT ANY PRIVILEGE, BECOME USER

**Impact:** SYSDBA equivalence with privilege delegation. Can modify all database parameters, create/delete users, and grant privileges to others.

**Remediation:**
```sql
REVOKE DBA FROM APP_ADMIN;
-- OR remove specific dangerous privileges
REVOKE ALTER SYSTEM FROM APP_ADMIN;
REVOKE CREATE USER FROM APP_ADMIN;
REVOKE DROP USER FROM APP_ADMIN;
REVOKE GRANT ANY PRIVILEGE FROM APP_ADMIN;
```

**Validation:** 
```sql
SELECT COUNT(*) FROM dba_sys_privs WHERE grantee = 'APP_ADMIN';
-- Should be < 10 after remediation
```

---

### 2. Dangerous Privileges with ADMIN OPTION
**Risk:** CRITICAL | **CIS:** 1.3.3

Current: 7 dangerous privileges with ADMIN OPTION:
- APP_ADMIN: ALTER SYSTEM, CREATE USER, DROP USER, CREATE TABLESPACE
- BACKUP_ADMIN: ALTER DATABASE, BACKUP ANY TABLE
- SCHEMA_OWNER: CREATE TABLESPACE

**Impact:** Users can grant privileges to others without accountability. Breaks audit trail and privilege control.

**Remediation:** Remove ADMIN OPTION on all dangerous privileges:
```sql
REVOKE ALTER SYSTEM FROM APP_ADMIN;
GRANT ALTER SYSTEM TO APP_ADMIN;
-- Repeat for all privileges with ADMIN OPTION
```

---

### 3. PUBLIC Access to Sensitive System Packages
**Risk:** CRITICAL | **CIS:** 1.4.2, 2.2.4

Current: PUBLIC has EXECUTE on:
- DBMS_SQL (arbitrary SQL execution)
- DBMS_UTILITY (internal functions)
- DBMS_SESSION (session manipulation)
- UTL_FILE (file system access)
- UTL_HTTP (outbound connections)

**Impact:** Any database user can escalate privileges, access files, exfiltrate data, or make unauthorized outbound connections.

**Remediation:**
```sql
REVOKE EXECUTE ON SYS.DBMS_SQL FROM PUBLIC;
REVOKE EXECUTE ON SYS.UTL_FILE FROM PUBLIC;
REVOKE EXECUTE ON SYS.UTL_HTTP FROM PUBLIC;
REVOKE EXECUTE ON SYS.DBMS_UTILITY FROM PUBLIC;
REVOKE EXECUTE ON SYS.DBMS_SESSION FROM PUBLIC;

-- Grant only to required accounts
GRANT EXECUTE ON SYS.DBMS_SQL TO dba_role_account;
```

---

### 4. Excessive Privilege Grants to Non-DBA Users
**Risk:** CRITICAL | **CIS:** 1.3.4, 1.4

Current: 64 system privileges to non-default users
- APP_ADMIN: 25 system privs (should be < 5)
- BACKUP_ADMIN: 12 system privs (should be 3-4)
- REPORTING_ADMIN: 8 system privs (should be 1-2)

**Impact:** Violates least privilege principle. Increases attack surface if account is compromised.

**Remediation:** Audit actual privilege usage and revoke unnecessary privileges:
```sql
SELECT username, action_name, timestamp FROM dba_audit_trail 
WHERE username = 'APP_ADMIN' 
ORDER BY timestamp DESC
FETCH FIRST 100 ROWS ONLY;
```

---

## High Priority Issues

### 1. Privilege Escalation Risks (3 Users)
**Risk:** HIGH | **CIS:** 1.3.2, 1.3.3

Users who can CREATE/DROP USER or use BECOME USER:
- APP_ADMIN: 8 escalation privileges
- BACKUP_ADMIN: 7 escalation privileges
- REPORTING_ADMIN: 2 escalation privileges (CREATE/DROP USER - why?)

**Impact:** Users can add backdoor accounts or impersonate other users.

**Remediation:** Remove CREATE/DROP USER from non-admin accounts:
```sql
REVOKE CREATE USER FROM REPORTING_ADMIN;
REVOKE DROP USER FROM REPORTING_ADMIN;
REVOKE ALTER USER FROM REPORTING_ADMIN;
```

---

### 2. Custom Roles with Excessive Privileges
**Risk:** HIGH | **CIS:** 1.3.4

- ADMIN_ROLE: 8 system privileges (should be split by function)
- CUSTOM_REPORT_ROLE: SELECT ANY TABLE (should use views)
- DEVELOPER_ROLE: 2 privileges (acceptable)

**Impact:** Roles not segregated by function. Hard to audit who has what access.

**Remediation:** Implement function-specific roles:
```sql
CREATE ROLE BACKUP_OPERATOR;
GRANT BACKUP ANY TABLE TO BACKUP_OPERATOR;
GRANT SELECT ANY TABLE TO BACKUP_OPERATOR;
-- No CREATE/DROP/ALTER

CREATE ROLE DBA_LIMITED;
GRANT ALTER DATABASE TO DBA_LIMITED;
-- No CREATE USER, DROP USER, BECOME USER
```

---

### 3. Insufficient Privilege Grant Auditing
**Risk:** HIGH | **CIS:** 1.6

Current: Partial auditing of privilege changes.

**Impact:** Cannot track who granted privileges to whom.

**Remediation:**
```sql
AUDIT GRANT SYSTEM PRIVILEGE;
AUDIT GRANT ANY OBJECT PRIVILEGE;
AUDIT CREATE USER;
AUDIT DROP USER;
```

---

## Medium Priority Issues

### 1. Lack of RBAC Strategy
**Risk: MEDIUM**

No formal role hierarchy. Should implement:
- Administrative Tier (DBAs, system admins)
- Developer Tier (schema owners, developers)
- Operator Tier (backup, monitoring)
- User Tier (end users with minimal privileges)

---

### 2. Missing Change Control Process
**Risk: MEDIUM**

No documentation of:
- Why privileges are assigned
- Who approved them
- Expiration dates
- Business justification

Implement privilege change log with approvals and dates.

---

## Summary Table

| Issue | Current | Severity | Action |
|-------|---------|----------|--------|
| APP_ADMIN privileges | 41 total | CRITICAL | Reduce to < 15 |
| ADMIN OPTION on dangerous privs | 7 grants | CRITICAL | Remove all |
| PUBLIC system package access | 5 packages | CRITICAL | Revoke all |
| Total non-default system privs | 64 | CRITICAL | Reduce to < 30 |
| Privilege escalation users | 3 users | HIGH | Remove escalation paths |
| Custom role strategy | Ad-hoc | HIGH | Implement RBAC |
| Privilege auditing | Partial | HIGH | Enable full auditing |
| RBAC implementation | None | MEDIUM | Implement structure |
| Change control process | None | MEDIUM | Document approvals |

---

## Remediation Priority

**Week 1 (IMMEDIATE):**
1. Revoke PUBLIC EXECUTE from DBMS_SQL, UTL_FILE, UTL_HTTP
2. Remove ADMIN OPTION from dangerous privileges
3. Validate APP_ADMIN DBA privilege requirements

**Week 2-3 (THIS WEEK):**
4. Remove CREATE/DROP USER from REPORTING_ADMIN
5. Audit privilege usage for critical users
6. Create privilege justification documentation

**Week 4 (THIS MONTH):**
7. Implement RBAC model
8. Create function-specific roles
9. Migrate users to roles

**Ongoing (QUARTERLY):**
10. Execute privilege audits every 90 days
11. Review and revoke unused privileges
12. Monitor privilege usage patterns

---

## Verification After Remediation

```sql
-- Check remaining dangerous privileges
SELECT COUNT(*) FROM dba_sys_privs 
WHERE privilege IN ('ALTER SYSTEM', 'DROP USER', 'CREATE USER', 'BECOME USER')
AND grantee NOT IN ('SYS', 'SYSTEM', 'DBA');

-- Check PUBLIC privileges
SELECT COUNT(*) FROM dba_tab_privs 
WHERE grantee = 'PUBLIC' 
AND table_name IN ('DBMS_SQL', 'DBMS_UTILITY', 'UTL_FILE', 'UTL_HTTP');

-- Check APP_ADMIN privileges
SELECT COUNT(*) FROM dba_sys_privs WHERE grantee = 'APP_ADMIN';
```

---

**Critical Action Required By:** 2026-06-03
**Next Assessment:** 2026-06-27
