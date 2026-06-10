# Oracle DBA Toolkit

**Owner:** Marco Castillo  
**Database:** PRODDB (Oracle 19c Enterprise Edition)  
**OS:** Red Hat Enterprise Linux 8  
**Updated:** 2026-06-10

A structured, automation-first initiative program covering all senior Oracle DBA responsibilities. Every initiative is scripted, documented, and versioned here.

---

## Quick Start

1. Clone this repo to your Oracle RHEL host
2. Copy `config/db_config.env.example` to `config/db_config.env` and fill in your connection details
3. Source the Oracle environment: `source oraenv` or set `ORACLE_HOME` and `ORACLE_SID`
4. Test connectivity: `source lib/oracle_connect.sh && oracle_connect_test`
5. Run the licensing audit: `./wave6-governance/licensing/feature-usage-audit.sh`

---

## Repository Structure

```
oracle-dba-toolkit/
├── config/          # Thresholds and connection template (no secrets committed)
├── lib/             # Shared library: connect, logger, notify
├── wave1-automation/        # Foundation: automation platform + docs framework
├── wave2-health-monitoring/ # Health check, alerting, patch management
├── wave3-ha-dr/             # Data Guard, RMAN hardening
├── wave4-performance/       # AWR/ADDM automation, capacity planning
├── wave5-security/          # CIS hardening, SOC2 compliance
├── wave6-governance/        # Data quality, licensing optimization
├── wave7-strategic/         # Cloud assessment, AI integration
├── docs/
│   ├── runbooks/            # Operational runbooks (RB-CATEGORY-NNN-title.md)
│   ├── architecture/        # Architecture Decision Records
│   ├── growth/              # Certifications roadmap, study log
│   └── superpowers/         # Specs and implementation plans
└── .github/workflows/       # GitHub Actions scheduled automation
```

---

## Initiative Program — Wave Map

| Wave | Status | Initiatives |
|------|--------|------------|
| 1 | Complete | Automation platform, Documentation framework |
| 2 | Planned | Daily health check, Monitoring & alerting, Patch management |
| 3 | Planned | HA & DR (Data Guard), Backup hardening |
| 4 | Planned | Performance tuning, Capacity planning |
| 5 | Planned | Security hardening, Compliance & audit management |
| 6 | Planned | Data quality, Cost & licensing optimization |
| 7 | Planned | Cloud & modernization, AI integration |

Full spec: [`docs/superpowers/specs/2026-06-10-oracle-dba-initiatives-design.md`](docs/superpowers/specs/2026-06-10-oracle-dba-initiatives-design.md)

---

## Adding a New Script

1. Source the shared library at the top of your script (see `wave1-automation/README.md` for the template)
2. Place the script in the correct wave directory
3. Add `--dry-run` support
4. Write a runbook using `docs/runbooks/RB-TEMPLATE-000-runbook-template.md`
5. Update the wave README script inventory
6. Commit

---

## Security

- **Never commit credentials.** Use `config/db_config.env` (git-ignored) or Oracle Wallet.
- All scripts are read-only by default. Scripts that make changes require `--execute` flag.
- See `wave5-security/` for CIS benchmark compliance automation.
