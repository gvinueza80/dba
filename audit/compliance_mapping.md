# CIS Oracle Database Benchmarks v1.1.1 - Assessment Mapping

This document maps audit tasks to CIS benchmark controls.

**Scope:** Oracle Database 19c (compatible with Oracle 12c+)

## Section 1: Installation, Patching, and Upgrades

- **CIS 1.1: Ensure latest Oracle patch is installed**
  - Status: [TO BE ASSESSED IN TASK 1]
  - Finding: [Will populate after audit]
  - Evidence: From `baseline_report.txt` - Patch Level query result

## Section 2: Database Installation and Configuration

- **CIS 2.1: Ensure 'AUDIT_TRAIL' is set to 'DB' or higher**
  - Status: [TO BE ASSESSED IN TASK 3]
  - Finding: [Will populate after audit]
  - Evidence: v$parameter query for audit_trail setting

- **CIS 2.2: Ensure 'DB_RECOVERY_FILE_DEST' is configured**
  - Status: [TO BE ASSESSED IN TASK 1]
  - Finding: [Will populate after audit]

## Section 3: General Database Security

- **CIS 3.1: Ensure 'FAILED_LOGIN_ATTEMPTS' is set to '5' or less**
  - Status: [TO BE ASSESSED IN TASK 2]
  - Finding: [Will populate after audit]
  - Evidence: dba_profiles query for FAILED_LOGIN_ATTEMPTS

- **CIS 3.2: Ensure 'PASSWORD_LIFE_TIME' is set to '60' or less**
  - Status: [TO BE ASSESSED IN TASK 2]
  - Finding: [Will populate after audit]
  - Evidence: dba_profiles query for PASSWORD_LIFE_TIME

- **CIS 3.3: Ensure 'PASSWORD_GRACE_TIME' is set appropriately**
  - Status: [TO BE ASSESSED IN TASK 2]
  - Finding: [Will populate after audit]

- **CIS 3.4: Ensure 'PASSWORD_REUSE_TIME' is set to '365' or greater**
  - Status: [TO BE ASSESSED IN TASK 2]
  - Finding: [Will populate after audit]

## Section 4: Privilege and Role Management

- **CIS 4.1: Ensure 'DBA' role is not granted to non-DBA users**
  - Status: [TO BE ASSESSED IN TASK 3]
  - Finding: [Will populate after audit]
  - Evidence: dba_role_privs query for DBA role

- **CIS 4.2: Ensure 'SYSDBA' and 'SYSOPER' privileges are granted only to DBAs**
  - Status: [TO BE ASSESSED IN TASK 3]
  - Finding: [Will populate after audit]
  - Evidence: v$pwfile_users query

- **CIS 4.3: Ensure dangerous system privileges are not granted to users**
  - Status: [TO BE ASSESSED IN TASK 3]
  - Finding: [Will populate after audit]
  - Evidence: dba_sys_privs query for ALTER SYSTEM, CREATE USER, etc.

## Section 5: User Account Management

- **CIS 5.1: Remove default accounts or lock and expire them**
  - Status: [TO BE ASSESSED IN TASK 2]
  - Finding: [Will populate after audit]
  - Evidence: dba_users query for default accounts (SYS, SYSTEM, SCOTT, XDB, OUTLN, etc.)

- **CIS 5.2: Ensure users are not granted multiple roles**
  - Status: [TO BE ASSESSED IN TASK 3]
  - Finding: [Will populate after audit]
  - Evidence: dba_role_privs query

## Section 6: Auditing and Logging

- **CIS 6.2: Ensure audit records are protected**
  - Status: [TO BE ASSESSED IN TASK 8]
  - Finding: [Will populate after audit]

- **CIS 6.3: Ensure central audit log retention is enabled**
  - Status: [TO BE ASSESSED IN TASK 8]
  - Finding: [Will populate after audit]

## Section 7: Database Encryption

- **CIS 7.1: Ensure Transparent Data Encryption (TDE) is enabled**
  - Status: [TO BE ASSESSED IN TASK 7]
  - Finding: [Will populate after audit]
  - Evidence: v$parameter query for encryption_wallet_location

- **CIS 7.2: Ensure network encryption is enabled**
  - Status: [TO BE ASSESSED IN TASK 7]
  - Finding: [Will populate after audit]

## Section 8: Backup and Recovery

- **CIS 8.1: Ensure backups are configured and current**
  - Status: [TO BE ASSESSED IN TASK 5]
  - Finding: [Will populate after audit]
  - Evidence: RMAN configuration and backup history

- **CIS 8.2: Ensure archive logs are created and retained**
  - Status: [TO BE ASSESSED IN TASK 5]
  - Finding: [Will populate after audit]
  - Evidence: log_archive_dest and log_archive_format parameters

- **CIS 8.3: Ensure Data Guard or standby database is configured**
  - Status: [TO BE ASSESSED IN TASK 5]
  - Finding: [Will populate after audit]
  - Evidence: v$database protection_mode and Data Guard status

## Assessment Summary

| Section | Total Controls | Status | Notes |
|---------|----------------|--------|-------|
| 1: Installation & Patching | 1 | Pending | Will assess patch level |
| 2: Database Installation | 2 | Pending | Recovery file destination and other configs |
| 3: General Security | 4 | Pending | Password policies and access controls |
| 4: Privilege Management | 3 | Pending | Role and privilege grants |
| 5: User Account Management | 2 | Pending | Default accounts and role assignment |
| 6: Auditing & Logging | 2 | Pending | Audit records protection and retention |
| 7: Database Encryption | 2 | Pending | TDE and network encryption |
| 8: Backup & Recovery | 3 | Pending | Backup configuration and Data Guard |
| **TOTAL** | **19** | **Pending** | Phase 1 assessment in progress |

---

## Assessment Methodology

1. **Task 1 (Current):** Baseline inventory - Oracle version, patches, database configuration
2. **Task 2:** Security posture - default accounts, password policies, authentication
3. **Task 3:** Access control - privilege and role audit
4. **Task 4:** Performance baseline - system metrics and health
5. **Task 5:** Backup & disaster recovery - RMAN and Data Guard assessment
6. **Task 6-7:** Apply fixes for critical issues identified in phases 1-2
7. **Task 8:** Enable monitoring and auditing
8. **Task 9:** Generate comprehensive audit report with findings and recommendations

## CIS Benchmarks Reference

- **CIS Oracle Database Benchmarks v1.1.1** - https://www.cisecurity.org/
- Framework provides prescriptive guidance for configuring Oracle Database to support information security
- Each control includes level assignment (Level 1: Basic, Level 2: Advanced)
- This assessment focuses on Level 1 and Level 2 controls applicable to on-prem Oracle instances

