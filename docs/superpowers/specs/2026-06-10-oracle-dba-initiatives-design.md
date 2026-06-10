# Oracle DBA Initiative Program — Design Spec

**Date:** 2026-06-10  
**Author:** Marco Castillo  
**Status:** Approved  
**Scope:** Senior Oracle DBA initiative program for Oracle 19c (PRODDB) on RHEL 8

---

## Overview

A structured, automation-first initiative program covering all major senior Oracle DBA responsibilities. Work is organized into 7 waves, sequenced by priority: operational efficiency first (automation + documentation), then stability (monitoring + HA/DR), then optimization, governance, and strategic modernization.

The program lives entirely in a single GitHub private repository. Every initiative is scripted, documented, and versioned. The DBA's own existing scripts are reviewed, improved if needed, and onboarded into the framework during each wave's implementation.

**Starting point:** clean repository — all pre-existing content removed before Wave 1 begins.

---

## Environment

- **Database:** Oracle 19c Enterprise Edition (PRODDB)
- **OS:** Red Hat Enterprise Linux 8 (RHEL 8)
- **Deployment:** On-premise, mixed (standby-capable + containerized instances)
- **Licenses:** Oracle EE + Diagnostics Pack + Tuning Pack (AWR, ADDM, ASH available)
- **Current HA/DR:** RMAN backups only — no standby
- **Current automation:** Scheduled jobs (cron + DBMS_SCHEDULER), undocumented, no central repo
- **Repository:** GitHub private repo

---

## Repository Structure

```
oracle-dba-toolkit/
├── README.md
├── config/
│   ├── db_config.env.example        # Connection params template (no secrets committed)
│   └── thresholds.conf              # All alerting/health check thresholds
├── lib/
│   ├── oracle_connect.sh            # Shared connection helper (sourced by all scripts)
│   ├── logger.sh                    # Standardized logging (stdout + rotating file)
│   └── notify.sh                    # Notification dispatcher (email/Slack/OEM)
├── wave1-automation/                # Automation platform + documentation framework
├── wave2-health-monitoring/         # Health check + alerting + patch management
├── wave3-ha-dr/                     # Data Guard + RMAN hardening
├── wave4-performance/               # AWR/ADDM automation + capacity planning
├── wave5-security/                  # CIS hardening + compliance management
├── wave6-governance/                # Data quality + cost/licensing optimization
├── wave7-strategic/                 # Cloud assessment + AI integration
├── docs/
│   ├── runbooks/                    # Operational runbooks (RB-<CATEGORY>-<NNN>-<title>.md)
│   ├── architecture/                # Architecture Decision Records (ADRs)
│   ├── growth/                      # Personal growth tracker, certifications, study notes
│   └── superpowers/                 # Specs and plans (this workflow)
├── reports/                         # Git-ignored; generated report output
└── .github/
    └── workflows/                   # GitHub Actions for scheduled automation
```

**Architecture principles:**
- Secrets never committed — loaded from environment variables or Oracle Wallet at runtime
- All scripts are idempotent and have a `--dry-run` flag
- All scripts return exit code 0 (success) or non-zero (failure)
- Structured logs written to `/var/log/oracle-dba/` on the DB host
- GitHub Actions drives external scheduling; DBMS_SCHEDULER handles DB-internal jobs
- Runbook naming: `RB-<CATEGORY>-<NNN>-<short-title>.md`

---

## Initiative Inventory (15 initiatives, 7 waves)

| Wave | # | Initiative | Priority Driver |
|------|---|-----------|----------------|
| 1 | 1 | Automation platform | Foundation |
| 1 | 2 | Documentation framework | Foundation |
| 2 | 3 | Daily health check | Stability |
| 2 | 4 | Monitoring & alerting | Stability |
| 2 | 5 | Patch management | Stability |
| 3 | 6 | HA & DR — Data Guard | Resilience |
| 3 | 7 | Backup hardening | Resilience |
| 4 | 8 | Performance tuning | Optimization |
| 4 | 9 | Capacity planning | Optimization |
| 5 | 10 | Security hardening | Governance |
| 5 | 11 | Compliance & audit management | Governance |
| 6 | 12 | Data quality & governance | Advanced |
| 6 | 13 | Cost & licensing optimization | Advanced |
| 7 | 14 | Cloud & modernization | Strategic |
| 7 | 15 | Professional growth & AI integration | Strategic |

---

## Wave 1: Foundation

### Initiative 1: Automation Platform

**Purpose:** Shared scripting framework used by all subsequent waves.

**Deliverables:**
- `lib/oracle_connect.sh` — single connection helper; reads from Oracle Wallet or env file; never hardcodes credentials
- `lib/logger.sh` — log levels (INFO/WARN/ERROR), timestamps, stdout + rotating log file output
- `lib/notify.sh` — pluggable notifier; starts with email (sendmail/mailx), extensible to Slack/OEM
- `config/thresholds.conf` — all numeric thresholds in one file (tablespace %, session count, backup age, etc.)
- `config/db_config.env.example` — connection parameter template

**Standards:**
- Every script sources `lib/oracle_connect.sh` and `lib/logger.sh`
- Every script accepts `--dry-run` flag
- Every script exits non-zero on failure
- DBMS_SCHEDULER job naming convention: `DBA_<WAVE>_<NAME>_<FREQ>` (e.g., `DBA_W2_HEALTH_DAILY`)

### Initiative 2: Documentation Framework

**Purpose:** Consistent structure so all documentation is findable, maintainable, and audit-ready.

**Deliverables:**
- Runbook template covering: purpose, prerequisites, step-by-step procedure, rollback steps, related scripts, last-tested date, owner
- ADR (Architecture Decision Record) template for capturing why decisions were made
- Wave README template: lists all scripts, inputs/outputs, schedule, dependencies
- `docs/growth/` structure: certifications roadmap (OCP 19c, OCI), study log, completed initiatives tracker

**Script onboarding process (used in every wave):**
1. DBA provides existing scripts
2. Review: understand purpose, identify gaps vs. component requirements
3. Improve: fix bugs, add missing checks, add dry-run, standardize error handling
4. Refactor: wire to `lib/oracle_connect.sh`, `lib/logger.sh`, `lib/notify.sh`
5. Document: write runbook + update wave README
6. Commit and schedule

---

## Wave 2: Stability

### Initiative 3: Daily Health Check

**Purpose:** Automated proactive morning digest replacing manual DBA checks.

**Schedule:** Daily, before business hours (DBMS_SCHEDULER + GitHub Actions)

**Checks:**
- Instance status: uptime, SGA/PGA usage, active sessions vs. `processes` parameter
- Top 5 wait events from `V$SYSTEM_EVENT`
- Tablespace usage: all tablespaces, flag >80% (warning) and >90% (critical)
- Failed DBMS_SCHEDULER jobs since last run
- Alert log ORA- errors since last run
- RMAN backup age: flag if last successful backup >24 hours
- Invalid object count

**Output:** HTML/text email digest + `reports/health/YYYY-MM-DD-health.txt` (saved daily, committed weekly for trending)

**Script onboarding:** DBA's existing health check scripts reviewed, improved, refactored to shared library, gaps filled.

### Initiative 4: Monitoring & Alerting

**Purpose:** Reactive threshold-based alerts that fire immediately on breach — separate from daily digest.

**Alerts:**
- Tablespace >85% → WARNING; >95% → CRITICAL
- Sessions >90% of `processes` parameter → CRITICAL
- ORA-00600 or ORA-07445 in alert log → CRITICAL (immediate page)
- RMAN backup older than 24h → WARNING
- Archive log dest >80% full → CRITICAL

**All thresholds:** defined in `config/thresholds.conf`  
**Notification:** `lib/notify.sh` (email initially, Slack/OEM extensible)

### Initiative 5: Patch Management

**Purpose:** Track Oracle quarterly CPU and OS patch lifecycle.

**Deliverables:**
- `wave2-health-monitoring/patch-tracker/patch-register.md` — applied/pending patch register
- Script: queries `dba_registry_history` and `v$patches`, compares against current Oracle CPU quarter
- Patch gap report: applied vs. missing, CVE severity where known
- GitHub issue auto-created each quarter via Actions + gh CLI when new CPU is due
- Runbook: `RB-PATCH-001-quarterly-cpu-procedure.md`

---

## Wave 3: Resilience

### Initiative 6: HA & DR — Data Guard

**Purpose:** Reduce RTO from hours (RMAN-only) to <15 minutes with a physical standby.

**Phase A — Formal RTO/RPO targets (pre-standby):**
- RTO target: <15 minutes
- RPO target: <5 minutes (ASYNC transport) or zero (SYNC transport)
- Targets documented and signed off before standby provisioning

**Phase B — Data Guard implementation:**
- Provision physical standby server (same Oracle version as primary)
- Configure Data Guard broker (`dgmgrl`)
- Redo transport: ASYNC default; SYNC optional for zero data loss
- Automated lag monitoring integrated into Wave 2 daily health check
- Annual failover drill: documented procedure + scheduled on calendar

**Runbooks:** `RB-DR-001-data-guard-setup.md`, `RB-DR-002-failover-procedure.md`, `RB-DR-003-failover-drill.md`

### Initiative 7: Backup Hardening

**Purpose:** Formalize RMAN policy, validate backup integrity, add off-site copy.

**Policy:**
- Full backup: weekly
- Incremental backup: daily (level 1)
- Archive log backup: every 4 hours
- Retention: 30 days online + off-site copy

**Automated validation:**
- Weekly `RESTORE ... VALIDATE` job — verifies backup integrity without restoring
- Monthly restore drill to non-production environment

**Off-site copy:** RMAN `BACKUP ... TO DESTINATION` to OCI Object Storage or NFS secondary  
**Script onboarding:** DBA's existing RMAN scripts reviewed, improved, promoted into formal policy  
**Runbooks:** `RB-BACKUP-001-rman-full-backup.md`, `RB-BACKUP-002-restore-procedure.md`, `RB-BACKUP-003-validate-backup.md`

---

## Wave 4: Optimization

### Initiative 8: Performance Tuning

**Purpose:** AWR/ADDM/ASH-driven automation for proactive performance management.

**Deliverables:**
- Automated weekly AWR report generation (HTML + text) → `reports/performance/`
- ADDM findings parser: extracts top recommendations from `DBA_ADVISOR_FINDINGS`, emails weekly digest
- Top SQL report: weekly snapshot of top 10 SQL by elapsed time, CPU, buffer gets from `DBA_HIST_SQLSTAT`
- SQL regression detector: compares current week vs. prior week, flags SQL that degraded >20%

**Runbooks:** `RB-PERF-001-awr-analysis.md`, `RB-PERF-002-top-sql-tuning.md`  
**Script onboarding:** DBA's existing performance scripts reviewed, improved, integrated.

### Initiative 9: Capacity Planning

**Purpose:** Automated growth trending and forecasting to prevent capacity surprises.

**Deliverables:**
- Tablespace growth trending: weekly snapshot to tracking table, 90-day forecast via linear regression
- Datafile autoextend inventory: identifies datafiles approaching max size and projected date
- CPU/memory trending from `DBA_HIST_SYSSTAT` and `DBA_HIST_OSSTAT`
- Monthly capacity report: growth rates, projected full dates, recommended actions → `reports/capacity/YYYY-MM/`

**Health check integration:** tablespace trending feeds back into Wave 2 daily digest over time.

---

## Wave 5: Governance

### Initiative 10: Security Hardening

**Purpose:** Reach and maintain 95%+ CIS Oracle Database Benchmark v1.1.1 compliance.

**Deliverables:**
- CIS benchmark checker script: runs all 12 benchmark areas, scores each, outputs compliance percentage
- Weekly scheduled run with delta report (what changed since last run)
- Idempotent remediation: auto-fixes driftable items, flags manual-intervention items
- Privilege review script: flags users with DBA role, ANY privileges, default passwords, inactive accounts >90 days
- Quarterly privilege review report → `reports/security/` with sign-off record

**Runbooks:** `RB-SEC-001-cis-hardening.md`, `RB-SEC-002-user-privilege-review.md`  
**Script onboarding:** DBA's existing security scripts reviewed, improved, integrated.

### Initiative 11: Compliance & Audit Management

**Purpose:** Automated SOC2 evidence collection and standing audit practice.

**Deliverables:**
- Unified audit policy review: ensures coverage of login failures, privilege use, DDL, sensitive table access
- Monthly SOC2 evidence package: audit logs + compliance scores + privilege review sign-offs
- Evidence saved to `reports/compliance/YYYY-MM/` — ready for auditor hand-off

**Runbook:** `RB-COMP-001-soc2-evidence-collection.md`

---

## Wave 6: Advanced Governance

### Initiative 12: Data Quality & Governance

**Purpose:** Proactive data integrity monitoring across key schemas.

**Deliverables:**
- Data profiling scripts: null rates, duplicate detection, referential integrity violations
- Constraint audit: tables missing PKs, FKs, or check constraints
- Stale statistics detector: tables/indexes with missing or outdated optimizer statistics (`DBA_TAB_STATISTICS`)
- Weekly data quality HTML report per schema → `reports/data-quality/`

**Runbooks:** `RB-DQ-001-data-profiling.md`, `RB-DQ-002-statistics-management.md`

### Initiative 13: Cost & Licensing Optimization

**Purpose:** Ensure Oracle license compliance and identify savings opportunities.

**Deliverables:**
- Feature usage audit: queries `DBA_FEATURE_USAGE_STATISTICS` — maps actual usage to license entitlements
- Extra-cost options checker: flags usage of unlicensed options (critical for Oracle audit defense)
- License rightsizing report: usage vs. entitlements, savings opportunities

**Note:** The feature usage audit script is high-value and low-effort — consider running it as a standalone quick win during Wave 1 or 2 to get an early read on licensing exposure.

**Runbook:** `RB-LIC-001-feature-usage-audit.md`

---

## Wave 7: Strategic

### Initiative 14: Cloud & Modernization

**Purpose:** Assess readiness for OCI migration and document modernization path.

**Deliverables:**
- OCI readiness checklist: networking, licensing, sizing, application dependencies
- Migration options matrix: OCI DBCS vs. Exadata Cloud Service vs. Autonomous Database
- Non-production POC plan: clone to OCI to validate performance and compatibility
- Modernization tracker: deprecated features in use, upgrade path to Oracle 21c/23ai
- Runbook: `RB-CLOUD-001-oci-migration-assessment.md`

**Note:** Cloud migration requires organizational decisions beyond the DBA role. This wave produces assessment artifacts and recommendations, not a migration execution plan.

### Initiative 15: Professional Growth & AI Integration

**Purpose:** Continuous learning and AI tooling to amplify DBA effectiveness.

**Deliverables:**
- AI-assisted SQL tuning: integrate Oracle 23ai SQL Firewall and AI tuning advisor where applicable
- LLM-assisted runbook drafting: use Claude API to generate first-draft runbooks from script comments and AWR findings; DBA reviews and approves
- Searchable knowledge base: all runbooks, ADRs, and reports in GitHub form the knowledge base
- `docs/growth/`: certifications roadmap (OCP 19c, OCI), study log, completed initiatives tracker

**Early start:** LLM-assisted runbook drafting can begin in Wave 1 — no dependency on later waves.

---

## Error Handling Standards (all waves)

- Scripts exit non-zero on any unhandled error
- All errors logged via `lib/logger.sh` with ERROR level
- Critical alerts dispatched via `lib/notify.sh` immediately
- `--dry-run` flag available on all scripts that make changes
- No script modifies production data without an explicit `--execute` flag

---

## Testing Strategy

- Each script tested in non-production Oracle environment before production deployment
- `--dry-run` output reviewed before first production run
- Restore/failover drills executed in non-production before production procedures are finalized
- CIS benchmark checker validated against known-compliant and known-non-compliant configurations

---

## Sequencing Notes

- **Wave 1 first** — the shared library (`lib/`) must exist before any other wave script is written
- **Licensing audit** (Wave 6) is worth pulling forward as a quick standalone check in Wave 1 or 2
- **LLM runbook drafting** (Wave 7) can start in Wave 1 with no prerequisites
- **Data Guard** (Wave 3) requires standby server provisioning — coordinate with infrastructure team
- Each wave is independent once Wave 1 is complete — waves can overlap where capacity allows
