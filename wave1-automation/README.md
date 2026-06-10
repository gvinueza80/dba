# Wave 1 — Automation Platform & Documentation Framework

**Status:** Complete  
**Owner:** Marco Castillo  
**Completed:** 2026-06-10

---

## Purpose

Foundational shared library and documentation framework used by all subsequent waves. No production automation runs from this wave — it provides the building blocks everything else depends on.

---

## Shared Library (lib/)

| File | Purpose | Used By |
|------|---------|---------|
| `lib/oracle_connect.sh` | Oracle connection helper, sqlplus variable, connect test | All scripts |
| `lib/logger.sh` | Log levels, timestamps, rotating log file output | All scripts |
| `lib/notify.sh` | Email + Slack notification dispatcher | All alert scripts |

### How to use in a new script

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"  # adjust depth as needed

source "${TOOLKIT_ROOT}/lib/logger.sh"
source "${TOOLKIT_ROOT}/lib/oracle_connect.sh"
source "${TOOLKIT_ROOT}/lib/notify.sh"

# Parse --dry-run flag
DRY_RUN=false
for arg in "$@"; do [[ "$arg" == "--dry-run" ]] && DRY_RUN=true; done

# Test connection first
oracle_connect_test || { log_error "Cannot connect to Oracle"; exit 1; }

log_info "Script starting"
# ... your logic here ...
log_info "Script complete"
```

---

## Configuration

| File | Purpose |
|------|---------|
| `config/thresholds.conf` | All numeric alert thresholds — edit here, not in scripts |
| `config/db_config.env.example` | Connection parameter template — copy to `db_config.env`, never commit |

---

## Documentation Templates

| File | Purpose |
|------|---------|
| `docs/runbooks/RB-TEMPLATE-000-runbook-template.md` | Copy this to create any new runbook |
| `docs/architecture/ADR-TEMPLATE-000-adr-template.md` | Copy this to create any new ADR |

---

## Script Onboarding Process

When onboarding an existing DBA script into a wave:

1. **Review** — read the script, understand its purpose, identify gaps vs. wave requirements
2. **Improve** — fix bugs, add missing checks, add `--dry-run`, standardize error handling
3. **Refactor** — add `source` calls for `lib/oracle_connect.sh`, `lib/logger.sh`, `lib/notify.sh`; remove inline duplicates
4. **Document** — write a runbook using `RB-TEMPLATE-000` and update the wave README script inventory
5. **Commit** — `git add` + `git commit` with descriptive message
6. **Schedule** — add DBMS_SCHEDULER job or GitHub Actions workflow

---

## Schedule

No scheduled jobs in Wave 1 — this wave is a foundation only.
