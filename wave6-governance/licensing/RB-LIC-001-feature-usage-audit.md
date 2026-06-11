# RB-LIC-001 — Oracle Feature Usage Audit

**Category:** LIC  
**Owner:** Marco Castillo  
**Last Tested:** 2026-06-11  
**Related Scripts:** `wave6-governance/licensing/feature-usage-audit.sh`  
**Estimated Duration:** 5 minutes

---

## Purpose

Compares active Oracle feature usage against your declared licenses in `config/licenses.conf` and automatically flags any feature in use that is not covered. Run quarterly, before Oracle license audits, or after any new feature is enabled.

---

## Prerequisites

- [ ] ORACLE_HOME and ORACLE_SID are set (or `config/db_config.env` is populated)
- [ ] `config/licenses.conf` is configured with your licensed options (see below)
- [ ] SSH access to RHEL host as oracle OS user (bash shell)
- [ ] DBA privilege — SELECT on `DBA_FEATURE_USAGE_STATISTICS`, `V$PDBS`

---

## Configuration

Edit `config/licenses.conf` once to reflect your Oracle licenses. The script reads this file on every run:

```bash
LICENSE_EE=YES
LICENSE_DIAGNOSTICS_PACK=YES    # Diagnostics Pack: AWR, ADDM, Real-Time SQL Monitoring
LICENSE_TUNING_PACK=YES         # Tuning Pack: SQL Tuning Advisor, SQL Access Advisor
LICENSE_PARTITIONING=NO         # set YES if Partitioning option is licensed
LICENSE_MULTITENANT=NO          # set YES if Multitenant option is licensed (>1 PDB)
LICENSE_RAC=NO
LICENSE_ACTIVE_DATA_GUARD=NO
# ... all other options default to NO
LICENSE_METRIC=NAMED_USER_PLUS
LICENSE_USER_COUNT=6000
```

---

## Procedure

### Step 1: Navigate to toolkit root

```bash
cd /u01/app/oracle/scripts/oracle-dba-toolkit
bash   # ensure bash shell, not ksh
```

### Step 2: Run the audit

```bash
./wave6-governance/licensing/feature-usage-audit.sh
```

### Step 3: Review the output sections

| Section | Meaning |
|---------|---------|
| `[OK]` | Feature in use and licensed — no action needed |
| `[INFO]` | Licensed but not currently active — informational |
| `[CHECK]` | Prior usage detected, not currently active — verify manually |
| `[!!!]` | **Feature ACTIVELY IN USE, NOT LICENSED — immediate action required** |

### Step 4: Act on any `[!!!]` exposures

For each exposure:
1. Verify it is genuinely in use (not a false positive from a prior installation)
2. Either: purchase the required option, or disable the feature
3. If it is a known false positive, update `config/licenses.conf` and document the reason in `docs/architecture/`

---

## Verification

Report saved to:
```
reports/licensing/YYYY-MM-DD-feature-usage.txt
```

Exit code 0 = compliant. Exit code 1 = exposures found (also triggers a critical notification via `lib/notify.sh`).

---

## Rollback

Read-only script — no rollback needed.

---

## Notes

- **Oracle Multitenant:** Single PDB per CDB is free in Oracle 19c EE. The script automatically checks PDB count when `IS_CDB=YES` — no manual check needed.
- **TDE / Encrypted Tablespaces:** Licensing is contract-dependent — always appears as `[CHECK]`. Oracle 12.2+ documentation suggests TDE tablespace encryption is included in EE base, but some Oracle support notes indicate Advanced Security may be required depending on your contract vintage. **Confirm with your Oracle account manager or Oracle License Management Services (LMS) before assuming it is free.** Once confirmed, document the outcome in `docs/architecture/` for your audit records.
- **Partitioning (system):** Oracle uses partitioning internally for AWR tables. This does NOT require the Partitioning option. Only user-created partitioned tables trigger a license requirement.
- **`CURRENTLY_USED = FALSE`:** Features with prior usage but not currently active appear in `[CHECK]` — lower urgency but worth reviewing.
- Oracle tracks usage cumulatively since install. `CURRENTLY_USED = TRUE` is the most important indicator.

---

## Change Log

| Date | Author | Change |
|------|--------|--------|
| 2026-06-11 | Marco Castillo | TDE changed to [CHECK] — licensing is contract-dependent, confirmed with Oracle required |
| 2026-06-11 | Marco Castillo | Rewrite: automatic license compliance check using config/licenses.conf |
| 2026-06-10 | Marco Castillo | Initial version |
