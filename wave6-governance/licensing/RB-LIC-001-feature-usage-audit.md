# RB-LIC-001 — Oracle Feature Usage Audit

**Category:** LIC  
**Owner:** Marco Castillo  
**Last Tested:** 2026-06-10  
**Related Scripts:** `wave6-governance/licensing/feature-usage-audit.sh`  
**Estimated Duration:** 5 minutes

---

## Purpose

Queries `DBA_FEATURE_USAGE_STATISTICS` to identify which Oracle licensed options are actively in use. Run this before any Oracle license audit, before dropping options, or quarterly as a standing practice.

---

## Prerequisites

- [ ] ORACLE_HOME and ORACLE_SID are set (or `config/db_config.env` is populated)
- [ ] SSH access to RHEL host as oracle OS user
- [ ] DBA privilege (SELECT on DBA_FEATURE_USAGE_STATISTICS)

---

## Procedure

### Step 1: Navigate to toolkit root

```bash
cd /path/to/oracle-dba-toolkit
```

### Step 2: Run the audit

```bash
./wave6-governance/licensing/feature-usage-audit.sh
```

### Step 3: Review the "EXTRA-COST OPTIONS" section

Compare every row with `DETECTED_USAGES > 0` against your Oracle license agreement. Features listed there carry additional license costs.

---

## Verification

Report saved to:
```
reports/licensing/YYYY-MM-DD-feature-usage.txt
```

---

## Rollback

Read-only script — no rollback needed.

---

## Notes

- Oracle tracks feature usage internally via background processes. A feature may show `DETECTED_USAGES > 0` even if you stopped using it — the count is cumulative since install.
- `CURRENTLY_USED = YES` is the most important column — it means the feature is active right now.
- If an unlicensed extra-cost option shows usage, investigate immediately and open a case with Oracle licensing or your Oracle account manager.

---

## Change Log

| Date | Author | Change |
|------|--------|--------|
| 2026-06-10 | Marco Castillo | Initial version |
