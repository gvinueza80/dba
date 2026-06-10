# Wave 1: Automation Platform & Documentation Framework — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a clean GitHub repository with a shared scripting library, documentation framework, and a standalone Oracle licensing audit script that all future waves will build on.

**Architecture:** Clean-slate repo with a `lib/` shared library (connect, logger, notify), `config/` for thresholds and connection templates, wave directories as placeholders, and `docs/` templates for runbooks and ADRs. A bonus licensing audit script is included as a Wave 6 early win. All scripts are idempotent, support `--dry-run`, and exit non-zero on failure.

**Tech Stack:** Bash, Oracle sqlplus (Oracle 19c), RHEL 8, GitHub private repo, GitHub Actions

---

## File Map

| File | Purpose |
|------|---------|
| `README.md` | Program overview, wave map, quick-start guide |
| `config/db_config.env.example` | Connection parameter template (no secrets) |
| `config/thresholds.conf` | All numeric thresholds used by monitoring scripts |
| `lib/oracle_connect.sh` | Shared Oracle connection helper, sourced by all scripts |
| `lib/logger.sh` | Standardized log levels, timestamps, rotating file output |
| `lib/notify.sh` | Pluggable notifier — email initially, Slack/OEM extensible |
| `wave1-automation/README.md` | Wave 1 script inventory, usage, schedule |
| `wave2-health-monitoring/README.md` | Wave 2 placeholder README |
| `wave3-ha-dr/README.md` | Wave 3 placeholder README |
| `wave4-performance/README.md` | Wave 4 placeholder README |
| `wave5-security/README.md` | Wave 5 placeholder README |
| `wave6-governance/README.md` | Wave 6 placeholder README |
| `wave7-strategic/README.md` | Wave 7 placeholder README |
| `docs/runbooks/RB-TEMPLATE-000-runbook-template.md` | Master runbook template |
| `docs/architecture/ADR-TEMPLATE-000-adr-template.md` | ADR template |
| `docs/architecture/ADR-001-shared-library-design.md` | First real ADR: why lib/ exists |
| `docs/growth/README.md` | Growth tracker structure |
| `docs/growth/certifications-roadmap.md` | OCP 19c + OCI cert roadmap |
| `wave6-governance/licensing/feature-usage-audit.sh` | Early-win licensing audit script |
| `wave6-governance/licensing/RB-LIC-001-feature-usage-audit.md` | Runbook for licensing audit |
| `.github/workflows/README.md` | GitHub Actions usage guide |
| `.gitignore` | Ignore reports/, logs/, secrets |

---

## Task 1: Clean the Repository

**Files:**
- Delete: all existing content except `.git/` and `docs/superpowers/`

- [ ] **Step 1: List everything currently in the repo**

```bash
ls -la
```

Expected: existing files from prior Claude session (audit/, monitoring/, ORACLE_AUDIT_REPORT.md, etc.)

- [ ] **Step 2: Remove all existing content except .git and docs/superpowers**

```bash
# On the RHEL server or local clone
find . -mindepth 1 -maxdepth 1 \
  ! -name '.git' \
  ! -name 'docs' \
  -exec rm -rf {} +

# Preserve only docs/superpowers inside docs/
find docs -mindepth 1 -maxdepth 1 \
  ! -name 'superpowers' \
  -exec rm -rf {} +
```

- [ ] **Step 3: Verify only .git and docs/superpowers remain**

```bash
find . -not -path './.git/*' -not -path './.git' | sort
```

Expected output:
```
.
./docs
./docs/superpowers
./docs/superpowers/plans
./docs/superpowers/plans/2026-05-26-oracle-database-verification.md
./docs/superpowers/plans/2026-06-10-wave1-automation-platform.md
./docs/superpowers/specs
./docs/superpowers/specs/2026-06-10-oracle-dba-initiatives-design.md
```

- [ ] **Step 4: Commit the clean state**

```bash
git add -A
git commit -m "chore: clean repo — remove prior session content, preserve specs and plans"
```

---

## Task 2: Create .gitignore

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Create .gitignore**

```bash
cat > .gitignore << 'EOF'
# Generated reports — never commit output files
reports/

# Local logs
logs/
*.log

# Secrets and environment files — never commit real credentials
config/db_config.env
*.env
*.wallet
*.p12
*.jks
cwallet.sso
ewallet.p12

# Oracle temp files
/tmp/*.sql

# OS artifacts
.DS_Store
Thumbs.db
EOF
```

- [ ] **Step 2: Verify .gitignore content**

```bash
cat .gitignore
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: add .gitignore for reports, logs, secrets, Oracle temp files"
```

---

## Task 3: Create Repository Skeleton

**Files:**
- Create: all wave directories + placeholder READMEs + `reports/` + `.github/workflows/`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p \
  config \
  lib \
  wave1-automation \
  wave2-health-monitoring \
  wave3-ha-dr \
  wave4-performance \
  wave5-security \
  wave6-governance/licensing \
  wave7-strategic \
  docs/runbooks \
  docs/architecture \
  docs/growth \
  reports \
  .github/workflows
```

- [ ] **Step 2: Create placeholder READMEs for wave directories**

```bash
for wave in \
  "wave2-health-monitoring:Wave 2 — Health Check, Monitoring & Patch Management" \
  "wave3-ha-dr:Wave 3 — HA & DR (Data Guard + Backup Hardening)" \
  "wave4-performance:Wave 4 — Performance Tuning & Capacity Planning" \
  "wave5-security:Wave 5 — Security Hardening & Compliance" \
  "wave6-governance:Wave 6 — Data Quality & Cost/Licensing Optimization" \
  "wave7-strategic:Wave 7 — Cloud & Modernization + AI Integration"
do
  dir="${wave%%:*}"
  title="${wave##*:}"
  cat > "${dir}/README.md" << EOF
# ${title}

> Status: Planned — implementation not yet started.

Scripts and documentation for this wave will be added during its implementation phase.

Refer to the program spec: \`docs/superpowers/specs/2026-06-10-oracle-dba-initiatives-design.md\`
EOF
done
```

- [ ] **Step 3: Create reports/.gitkeep so directory is tracked**

```bash
touch reports/.gitkeep
echo "reports/" >> .gitignore
# reports/ content ignored but directory tracked via .gitkeep
```

- [ ] **Step 4: Create .github/workflows/README.md**

```bash
cat > .github/workflows/README.md << 'EOF'
# GitHub Actions Workflows

Workflows in this directory drive scheduled automation for the oracle-dba-toolkit.

## Naming Convention

`<wave>-<initiative>-<frequency>.yml`

Examples:
- `wave2-health-check-daily.yml`
- `wave2-patch-report-quarterly.yml`

## Requirements

All workflows that SSH to the DB host require these GitHub repository secrets:

| Secret | Description |
|--------|-------------|
| `DB_HOST` | Hostname or IP of the Oracle DB server |
| `DB_SSH_KEY` | Private SSH key for the oracle OS user |
| `NOTIFY_EMAIL` | Email address for alert notifications |

## Adding a New Workflow

1. Copy an existing workflow as a template
2. Set the `cron` schedule
3. Update the SSH command to call the correct script
4. Add the workflow to the wave README script inventory
EOF
```

- [ ] **Step 5: Commit skeleton**

```bash
git add -A
git commit -m "chore: initialize repository skeleton — wave directories, .gitignore, workflows guide"
```

---

## Task 4: Create lib/logger.sh

**Files:**
- Create: `lib/logger.sh`

- [ ] **Step 1: Create logger.sh**

```bash
cat > lib/logger.sh << 'SCRIPT'
#!/usr/bin/env bash
# Shared logging library. Source this file — do not execute directly.
# Usage: source lib/logger.sh
#        log_info "message"
#        log_warn "message"
#        log_error "message"

LOG_DIR="${LOG_DIR:-/var/log/oracle-dba}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/oracle-dba.log}"
LOG_MAX_BYTES="${LOG_MAX_BYTES:-10485760}"  # 10 MB default rotation size

_log_init() {
  mkdir -p "$LOG_DIR" 2>/dev/null || {
    echo "WARN: cannot create $LOG_DIR — logging to stdout only" >&2
    LOG_FILE="/dev/null"
  }
  touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/dev/null"
}

_log_rotate() {
  [[ "$LOG_FILE" == "/dev/null" ]] && return
  local size
  size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
  if (( size > LOG_MAX_BYTES )); then
    mv "$LOG_FILE" "${LOG_FILE}.$(date +%Y%m%d%H%M%S).bak"
    touch "$LOG_FILE"
  fi
}

_log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  local line="[${ts}] [${level}] ${msg}"
  echo "$line"
  _log_rotate
  echo "$line" >> "$LOG_FILE" 2>/dev/null
}

log_info()  { _log "INFO " "$@"; }
log_warn()  { _log "WARN " "$@"; }
log_error() { _log "ERROR" "$@"; }

_log_init
SCRIPT
chmod +x lib/logger.sh
```

- [ ] **Step 2: Smoke-test logger.sh in a subshell**

```bash
bash -c '
  export LOG_DIR=/tmp/test-oracle-dba-logs
  source lib/logger.sh
  log_info  "test info message"
  log_warn  "test warn message"
  log_error "test error message"
  echo "--- log file contents ---"
  cat /tmp/test-oracle-dba-logs/oracle-dba.log
  rm -rf /tmp/test-oracle-dba-logs
'
```

Expected output:
```
[YYYY-MM-DD HH:MM:SS] [INFO ] test info message
[YYYY-MM-DD HH:MM:SS] [WARN ] test warn message
[YYYY-MM-DD HH:MM:SS] [ERROR] test error message
--- log file contents ---
[YYYY-MM-DD HH:MM:SS] [INFO ] test info message
[YYYY-MM-DD HH:MM:SS] [WARN ] test warn message
[YYYY-MM-DD HH:MM:SS] [ERROR] test error message
```

- [ ] **Step 3: Commit**

```bash
git add lib/logger.sh
git commit -m "feat: add lib/logger.sh — shared logging with rotation"
```

---

## Task 5: Create config/thresholds.conf and config/db_config.env.example

**Files:**
- Create: `config/thresholds.conf`
- Create: `config/db_config.env.example`

- [ ] **Step 1: Create thresholds.conf**

```bash
cat > config/thresholds.conf << 'EOF'
# Oracle DBA Toolkit — Alert Thresholds
# All scripts source this file via: source config/thresholds.conf
# Edit values here to tune alerting without touching scripts.

# Tablespace usage (percent)
THRESHOLD_TABLESPACE_WARN=80
THRESHOLD_TABLESPACE_CRIT=90

# Archive log destination usage (percent)
THRESHOLD_ARCHLOG_WARN=75
THRESHOLD_ARCHLOG_CRIT=85

# Session usage — percent of max PROCESSES parameter
THRESHOLD_SESSIONS_WARN=80
THRESHOLD_SESSIONS_CRIT=90

# RMAN backup age before alerting (hours)
THRESHOLD_BACKUP_AGE_WARN=24
THRESHOLD_BACKUP_AGE_CRIT=48

# Invalid objects count before alerting
THRESHOLD_INVALID_OBJECTS_WARN=1

# Data Guard lag before alerting (minutes)
THRESHOLD_DG_LAG_WARN=5
THRESHOLD_DG_LAG_CRIT=15

# Undo segment size before informational notice (MB)
THRESHOLD_UNDO_NOTICE_MB=5000

# SQL regression — elapsed time increase (percent) before flagging
THRESHOLD_SQL_REGRESSION_PCT=20

# Tablespace growth forecast — days before full to trigger warning
THRESHOLD_CAPACITY_DAYS_WARN=90
THRESHOLD_CAPACITY_DAYS_CRIT=30
EOF
```

- [ ] **Step 2: Create db_config.env.example**

```bash
cat > config/db_config.env.example << 'EOF'
# Oracle DBA Toolkit — Connection Configuration Template
# Copy this file to config/db_config.env and fill in values.
# NEVER commit config/db_config.env — it is in .gitignore.
#
# Alternative: use Oracle Wallet. If ORACLE_WALLET_LOC is set,
# lib/oracle_connect.sh will use wallet authentication instead.

# Oracle environment
ORACLE_HOME=/u01/app/oracle/product/19c
ORACLE_SID=PRODDB
ORACLE_BASE=/u01/app/oracle

# Connection credentials (only needed if not using Oracle Wallet)
# DBA_USER=system
# DBA_PASS=changeme

# Oracle Wallet location (preferred over plaintext credentials)
# ORACLE_WALLET_LOC=/etc/oracle/wallet

# Notification settings
NOTIFY_EMAIL=dba@example.com
NOTIFY_SLACK_WEBHOOK=
# Leave NOTIFY_SLACK_WEBHOOK blank to disable Slack notifications

# Log directory override (default: /var/log/oracle-dba)
# LOG_DIR=/var/log/oracle-dba
EOF
```

- [ ] **Step 3: Verify db_config.env is gitignored**

```bash
echo "testvalue" > config/db_config.env
git status config/db_config.env
rm config/db_config.env
```

Expected: `config/db_config.env` does NOT appear in git status output (it is ignored).

- [ ] **Step 4: Commit**

```bash
git add config/thresholds.conf config/db_config.env.example
git commit -m "feat: add config/thresholds.conf and db_config.env.example"
```

---

## Task 6: Create lib/oracle_connect.sh

**Files:**
- Create: `lib/oracle_connect.sh`

This is the most critical shared library file. Every script sources it to get a working `$SQLPLUS` variable and validated Oracle environment. It supports both Oracle Wallet and env-file authentication.

- [ ] **Step 1: Create oracle_connect.sh**

```bash
cat > lib/oracle_connect.sh << 'SCRIPT'
#!/usr/bin/env bash
# Shared Oracle connection helper. Source this file — do not execute directly.
# Usage: source lib/oracle_connect.sh
#        $SQLPLUS -S / as sysdba @script.sql
#        oracle_connect_test  # returns 0 if connection succeeds

# Load config if db_config.env exists alongside this toolkit
_TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${_TOOLKIT_ROOT}/config/db_config.env" ]]; then
  # shellcheck source=/dev/null
  source "${_TOOLKIT_ROOT}/config/db_config.env"
fi

# Load thresholds
if [[ -f "${_TOOLKIT_ROOT}/config/thresholds.conf" ]]; then
  # shellcheck source=/dev/null
  source "${_TOOLKIT_ROOT}/config/thresholds.conf"
fi

# Validate ORACLE_HOME
if [[ -z "$ORACLE_HOME" ]]; then
  echo "ERROR: ORACLE_HOME is not set. Source oraenv or set it in config/db_config.env." >&2
  exit 1
fi

SQLPLUS="${ORACLE_HOME}/bin/sqlplus"
RMAN="${ORACLE_HOME}/bin/rman"
DGMGRL="${ORACLE_HOME}/bin/dgmgrl"

if [[ ! -x "$SQLPLUS" ]]; then
  echo "ERROR: sqlplus not found at ${SQLPLUS}" >&2
  exit 1
fi

# Build connection string
# Prefer Oracle Wallet; fall back to DBA_USER/DBA_PASS; fall back to OS auth
_oracle_conn_string() {
  if [[ -n "$ORACLE_WALLET_LOC" ]]; then
    echo "/@${ORACLE_SID}"
  elif [[ -n "$DBA_USER" && -n "$DBA_PASS" ]]; then
    echo "${DBA_USER}/${DBA_PASS}@${ORACLE_SID}"
  else
    echo "/ as sysdba"
  fi
}

ORACLE_CONN_STRING="$(_oracle_conn_string)"

# Test connectivity — returns 0 on success, 1 on failure
oracle_connect_test() {
  local result
  result=$("$SQLPLUS" -S "$ORACLE_CONN_STRING" <<'EOF' 2>&1
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT 'CONNECTED' FROM dual;
EXIT;
EOF
)
  if echo "$result" | grep -q "CONNECTED"; then
    return 0
  else
    echo "ERROR: Oracle connection failed. Output: ${result}" >&2
    return 1
  fi
}

# Run a SQL string and return output. Usage: oracle_run_sql "SELECT 1 FROM dual;"
oracle_run_sql() {
  local sql="$1"
  "$SQLPLUS" -S "$ORACLE_CONN_STRING" <<EOF 2>&1
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200 TRIMSPOOL ON
${sql}
EXIT;
EOF
}
SCRIPT
chmod +x lib/oracle_connect.sh
```

- [ ] **Step 2: Smoke-test oracle_connect.sh (dry validation — checks sourcing and variable export)**

```bash
bash -c '
  export ORACLE_HOME=/u01/app/oracle/product/19c
  export ORACLE_SID=PRODDB
  # Fake sqlplus so the file-existence check passes in CI
  mkdir -p /tmp/fake-oracle/bin
  echo "#!/bin/bash" > /tmp/fake-oracle/bin/sqlplus
  echo "echo CONNECTED" >> /tmp/fake-oracle/bin/sqlplus
  chmod +x /tmp/fake-oracle/bin/sqlplus
  export ORACLE_HOME=/tmp/fake-oracle
  source lib/oracle_connect.sh
  echo "SQLPLUS=$SQLPLUS"
  echo "RMAN=$RMAN"
  echo "ORACLE_CONN_STRING=$ORACLE_CONN_STRING"
  rm -rf /tmp/fake-oracle
'
```

Expected output:
```
SQLPLUS=/tmp/fake-oracle/bin/sqlplus
RMAN=/tmp/fake-oracle/bin/rman
ORACLE_CONN_STRING=/ as sysdba
```

- [ ] **Step 3: Test against real Oracle (run on the RHEL DB host)**

```bash
source lib/oracle_connect.sh
oracle_connect_test && echo "Connection OK" || echo "Connection FAILED"
```

Expected: `Connection OK`

- [ ] **Step 4: Commit**

```bash
git add lib/oracle_connect.sh
git commit -m "feat: add lib/oracle_connect.sh — shared Oracle connection helper with wallet support"
```

---

## Task 7: Create lib/notify.sh

**Files:**
- Create: `lib/notify.sh`

- [ ] **Step 1: Create notify.sh**

```bash
cat > lib/notify.sh << 'SCRIPT'
#!/usr/bin/env bash
# Shared notification dispatcher. Source this file — do not execute directly.
# Usage: source lib/notify.sh
#        notify_warn  "subject" "body"
#        notify_crit  "subject" "body"
#        notify_info  "subject" "body"
#
# Configure via environment or config/db_config.env:
#   NOTIFY_EMAIL          — recipient email address
#   NOTIFY_SLACK_WEBHOOK  — Slack incoming webhook URL (leave blank to disable)

_notify_email() {
  local subject="$1"
  local body="$2"
  [[ -z "$NOTIFY_EMAIL" ]] && return 0
  if command -v mailx &>/dev/null; then
    echo "$body" | mailx -s "$subject" "$NOTIFY_EMAIL"
  elif command -v sendmail &>/dev/null; then
    printf "Subject: %s\n\n%s" "$subject" "$body" | sendmail "$NOTIFY_EMAIL"
  else
    echo "WARN: no mail client found (mailx/sendmail). Cannot send email." >&2
  fi
}

_notify_slack() {
  local subject="$1"
  local body="$2"
  [[ -z "$NOTIFY_SLACK_WEBHOOK" ]] && return 0
  local payload
  payload=$(printf '{"text":"*%s*\n%s"}' "$subject" "$body")
  if command -v curl &>/dev/null; then
    curl -s -X POST -H 'Content-type: application/json' \
      --data "$payload" "$NOTIFY_SLACK_WEBHOOK" >/dev/null
  else
    echo "WARN: curl not found. Cannot send Slack notification." >&2
  fi
}

# notify_info — informational, email only
notify_info() {
  local subject="[Oracle DBA] INFO: $1"
  local body="$2"
  _notify_email "$subject" "$body"
}

# notify_warn — warning, email + Slack
notify_warn() {
  local subject="[Oracle DBA] WARNING: $1"
  local body="$2"
  _notify_email "$subject" "$body"
  _notify_slack "$subject" "$body"
}

# notify_crit — critical, email + Slack
notify_crit() {
  local subject="[Oracle DBA] CRITICAL: $1"
  local body="$2"
  _notify_email "$subject" "$body"
  _notify_slack "$subject" "$body"
}
SCRIPT
chmod +x lib/notify.sh
```

- [ ] **Step 2: Smoke-test notify.sh (dry run — no real email/Slack)**

```bash
bash -c '
  export NOTIFY_EMAIL=""
  export NOTIFY_SLACK_WEBHOOK=""
  source lib/notify.sh
  notify_info "Test subject" "Test info body"
  notify_warn "Test subject" "Test warn body"
  notify_crit "Test subject" "Test crit body"
  echo "notify.sh sourced and functions callable — OK"
'
```

Expected: `notify.sh sourced and functions callable — OK` (no errors)

- [ ] **Step 3: Commit**

```bash
git add lib/notify.sh
git commit -m "feat: add lib/notify.sh — email + Slack notification dispatcher"
```

---

## Task 8: Create Documentation Templates

**Files:**
- Create: `docs/runbooks/RB-TEMPLATE-000-runbook-template.md`
- Create: `docs/architecture/ADR-TEMPLATE-000-adr-template.md`
- Create: `docs/architecture/ADR-001-shared-library-design.md`
- Create: `docs/growth/README.md`
- Create: `docs/growth/certifications-roadmap.md`

- [ ] **Step 1: Create runbook template**

```bash
cat > docs/runbooks/RB-TEMPLATE-000-runbook-template.md << 'EOF'
# RB-<CATEGORY>-<NNN> — <Short Title>

**Category:** <!-- BACKUP | PERF | SEC | DR | PATCH | COMP | DQ | LIC | CLOUD -->  
**Owner:** Marco Castillo  
**Last Tested:** YYYY-MM-DD  
**Related Scripts:** `wave<N>-<name>/path/to/script.sh`  
**Estimated Duration:** X minutes

---

## Purpose

One or two sentences describing what this runbook accomplishes and when to use it.

---

## Prerequisites

- [ ] ORACLE_HOME and ORACLE_SID are set
- [ ] Oracle Wallet or DBA credentials available
- [ ] SSH access to RHEL host as oracle OS user
- [ ] `lib/oracle_connect.sh` sourced
- [ ] Add any additional prerequisites specific to this runbook

---

## Procedure

### Step 1: <First Step Title>

```bash
# Command(s) to execute
```

Expected output:
```
<what success looks like>
```

### Step 2: <Next Step Title>

```bash
# Command(s) to execute
```

Expected output:
```
<what success looks like>
```

<!-- Add more steps as needed -->

---

## Verification

How to confirm the procedure completed successfully:

```bash
# Verification command
```

Expected:
```
<what verified success looks like>
```

---

## Rollback

Steps to undo if something goes wrong:

```bash
# Rollback commands
```

---

## Notes

Any caveats, known issues, or context that would surprise a reader.

---

## Change Log

| Date | Author | Change |
|------|--------|--------|
| YYYY-MM-DD | Marco Castillo | Initial version |
EOF
```

- [ ] **Step 2: Create ADR template**

```bash
cat > docs/architecture/ADR-TEMPLATE-000-adr-template.md << 'EOF'
# ADR-<NNN> — <Decision Title>

**Date:** YYYY-MM-DD  
**Author:** Marco Castillo  
**Status:** Proposed | Accepted | Superseded by ADR-NNN

---

## Context

What situation or problem forced this decision? What constraints existed?

---

## Decision

What was decided? State it clearly and directly.

---

## Alternatives Considered

| Option | Reason Rejected |
|--------|----------------|
| Option A | Reason |
| Option B | Reason |

---

## Consequences

What becomes easier or harder as a result of this decision? What are the trade-offs?

---

## References

- Link to relevant docs, scripts, or external resources
EOF
```

- [ ] **Step 3: Create first real ADR — shared library design**

```bash
cat > docs/architecture/ADR-001-shared-library-design.md << 'EOF'
# ADR-001 — Shared Library in lib/ Used by All Scripts

**Date:** 2026-06-10  
**Author:** Marco Castillo  
**Status:** Accepted

---

## Context

The initiative program will produce dozens of shell scripts across 7 waves. Without a shared foundation, each script would re-implement Oracle connection logic, logging, and notifications differently — making the toolkit hard to maintain and inconsistent to operate.

---

## Decision

All shell scripts source three shared libraries from `lib/`:

- `lib/oracle_connect.sh` — Oracle connection, sqlplus variable, connect test
- `lib/logger.sh` — standardized log levels, timestamps, rotating log file
- `lib/notify.sh` — email + Slack notification dispatcher

All numeric thresholds are defined in `config/thresholds.conf` and sourced via `lib/oracle_connect.sh`.

No credentials are ever hardcoded. Scripts use Oracle Wallet or environment variables loaded from `config/db_config.env` (git-ignored).

---

## Alternatives Considered

| Option | Reason Rejected |
|--------|----------------|
| Each script self-contained | No shared code means inconsistent logging, duplicate connection logic, hard to change notification channels |
| Python framework (e.g., cx_Oracle) | Adds Python dependency; Bash is universal on RHEL Oracle hosts; DBA's existing scripts are Bash |
| Oracle EM / OEM only | Not available in this environment; this toolkit must work without OEM |

---

## Consequences

- Every new script must source `lib/oracle_connect.sh` and `lib/logger.sh` — small overhead, large consistency gain
- Changing the notification channel (e.g., adding PagerDuty) requires editing only `lib/notify.sh`
- Scripts are testable in isolation by mocking the lib files
- Log rotation is centralized — all scripts write to `/var/log/oracle-dba/oracle-dba.log`
EOF
```

- [ ] **Step 4: Create docs/growth/README.md**

```bash
cat > docs/growth/README.md << 'EOF'
# Professional Growth Tracker

**Owner:** Marco Castillo  
**Updated:** 2026-06-10

This directory tracks professional development activities alongside the Oracle DBA Initiative Program.

## Contents

| File | Purpose |
|------|---------|
| `certifications-roadmap.md` | Active certification goals and study plan |
| `study-log.md` | Weekly study notes and resources (create as needed) |
| `completed-initiatives.md` | Log of completed initiative waves and outcomes (create as needed) |

## Philosophy

Every initiative wave produces skills. Document them here so they're visible during performance reviews, job searches, or mentoring conversations.
EOF
```

- [ ] **Step 5: Create docs/growth/certifications-roadmap.md**

```bash
cat > docs/growth/certifications-roadmap.md << 'EOF'
# Certifications Roadmap

**Owner:** Marco Castillo  
**Updated:** 2026-06-10

---

## Active Goals

### Oracle Database 19c Certified Professional (OCP)

**Target date:** TBD  
**Status:** Planning

| Exam | Code | Status | Notes |
|------|------|--------|-------|
| Oracle Database Administration I | 1Z0-082 | Not started | |
| Oracle Database Administration II | 1Z0-083 | Not started | |

**Study resources:**
- Oracle University: Database Administration Workshop (recommended)
- Oracle Database 19c documentation: [docs.oracle.com](https://docs.oracle.com/en/database/oracle/oracle-database/19/)
- Practice exams: ExamTopics, Whizlabs

---

### Oracle Cloud Infrastructure (OCI) Foundations Associate

**Target date:** TBD  
**Status:** Planning

| Exam | Code | Status | Notes |
|------|------|--------|-------|
| OCI Foundations Associate | 1Z0-1085 | Not started | Good entry point before architect-level |

**Study resources:**
- Oracle MyLearn: OCI Foundations free learning path
- OCI Free Tier: hands-on practice environment

---

## Completed Certifications

| Certification | Date | Notes |
|---------------|------|-------|
| (none recorded yet) | | |

---

## Notes

Update target dates once wave implementation begins — real hands-on work with AWR, Data Guard, OCI, and security hardening directly supports exam topics.
EOF
```

- [ ] **Step 6: Commit all documentation templates**

```bash
git add docs/
git commit -m "feat: add runbook template, ADR template, ADR-001, and growth tracker"
```

---

## Task 9: Create wave1-automation/README.md

**Files:**
- Create: `wave1-automation/README.md`

- [ ] **Step 1: Create Wave 1 README**

```bash
cat > wave1-automation/README.md << 'EOF'
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
EOF
```

- [ ] **Step 2: Commit**

```bash
git add wave1-automation/README.md
git commit -m "feat: add wave1-automation README with shared library usage guide and onboarding process"
```

---

## Task 10: Create Licensing Audit Script (Wave 6 Early Win)

**Files:**
- Create: `wave6-governance/licensing/feature-usage-audit.sh`
- Create: `wave6-governance/licensing/RB-LIC-001-feature-usage-audit.md`

This is a standalone, read-only script. It queries `DBA_FEATURE_USAGE_STATISTICS` to show which Oracle options are in use — critical for avoiding unexpected Oracle license audit findings.

- [ ] **Step 1: Create feature-usage-audit.sh**

```bash
cat > wave6-governance/licensing/feature-usage-audit.sh << 'SCRIPT'
#!/usr/bin/env bash
# Oracle Feature Usage Audit — Wave 6 Early Win
# Queries DBA_FEATURE_USAGE_STATISTICS to identify licensed and unlicensed features in use.
# Safe: read-only, no changes made to the database.
# Usage: ./feature-usage-audit.sh [--dry-run]
#
# Output: Console report + saved to reports/licensing/YYYY-MM-DD-feature-usage.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${TOOLKIT_ROOT}/lib/logger.sh"
source "${TOOLKIT_ROOT}/lib/oracle_connect.sh"
source "${TOOLKIT_ROOT}/lib/notify.sh"

DRY_RUN=false
for arg in "$@"; do [[ "$arg" == "--dry-run" ]] && DRY_RUN=true; done

REPORT_DIR="${TOOLKIT_ROOT}/reports/licensing"
REPORT_FILE="${REPORT_DIR}/$(date +%Y-%m-%d)-feature-usage.txt"

if $DRY_RUN; then
  log_info "[DRY RUN] Would query DBA_FEATURE_USAGE_STATISTICS and write to ${REPORT_FILE}"
  exit 0
fi

oracle_connect_test || { log_error "Cannot connect to Oracle — aborting"; exit 1; }

mkdir -p "$REPORT_DIR"

log_info "Starting Oracle feature usage audit"

{
echo "========================================================================"
echo "ORACLE FEATURE USAGE AUDIT"
echo "Database: ${ORACLE_SID}"
echo "Date:     $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================================"
echo ""

echo "--- FEATURES CURRENTLY IN USE (DETECTED_USAGES > 0) ---"
oracle_run_sql "
SELECT
    name                                          AS feature_name,
    version,
    detected_usages,
    TO_CHAR(last_usage_date, 'YYYY-MM-DD')        AS last_used,
    currently_used
FROM dba_feature_usage_statistics
WHERE detected_usages > 0
ORDER BY name;"

echo ""
echo "--- EXTRA-COST OPTIONS — CHECK THESE AGAINST YOUR LICENSE ---"
echo "The following features carry additional Oracle license costs."
echo "Any row with DETECTED_USAGES > 0 that is NOT in your license is an exposure."
echo ""
oracle_run_sql "
SELECT
    name                                          AS feature_name,
    detected_usages,
    TO_CHAR(last_usage_date, 'YYYY-MM-DD')        AS last_used,
    currently_used
FROM dba_feature_usage_statistics
WHERE detected_usages > 0
  AND name IN (
    'Active Data Guard',
    'Advanced Compression',
    'Advanced Security',
    'Database Vault',
    'Label Security',
    'Multitenant',
    'OLAP',
    'Partitioning',
    'RAC',
    'Real Application Clusters',
    'Spatial and Graph',
    'Advanced Analytics',
    'GoldenGate'
  )
ORDER BY name;"

echo ""
echo "========================================================================"
echo "AUDIT COMPLETE"
echo "========================================================================"
} | tee "$REPORT_FILE"

log_info "Report saved to ${REPORT_FILE}"
SCRIPT
chmod +x wave6-governance/licensing/feature-usage-audit.sh
```

- [ ] **Step 2: Test with --dry-run**

```bash
source lib/oracle_connect.sh 2>/dev/null || export ORACLE_HOME=/u01/app/oracle/product/19c ORACLE_SID=PRODDB
./wave6-governance/licensing/feature-usage-audit.sh --dry-run
```

Expected:
```
[YYYY-MM-DD HH:MM:SS] [INFO ] [DRY RUN] Would query DBA_FEATURE_USAGE_STATISTICS and write to .../reports/licensing/YYYY-MM-DD-feature-usage.txt
```

- [ ] **Step 3: Run against real Oracle (run on RHEL DB host)**

```bash
./wave6-governance/licensing/feature-usage-audit.sh
```

Expected: feature usage report printed to console and saved to `reports/licensing/`.

Review the "EXTRA-COST OPTIONS" section carefully against your Oracle license entitlements.

- [ ] **Step 4: Create the runbook**

```bash
cat > wave6-governance/licensing/RB-LIC-001-feature-usage-audit.md << 'EOF'
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
EOF
```

- [ ] **Step 5: Update wave6-governance/README.md to reference the new script**

```bash
cat >> wave6-governance/README.md << 'EOF'

---

## Early Win: Licensing Audit (Available Now)

The licensing audit script is ready to use immediately — it does not depend on any other Wave 6 work.

| Script | Runbook | Schedule |
|--------|---------|---------|
| `licensing/feature-usage-audit.sh` | `licensing/RB-LIC-001-feature-usage-audit.md` | Quarterly (run manually until Wave 6 scheduled) |
EOF
```

- [ ] **Step 6: Commit**

```bash
git add wave6-governance/
git commit -m "feat: add Wave 6 early win — Oracle feature/licensing usage audit script and runbook"
```

---

## Task 11: Create Root README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create README.md**

```bash
cat > README.md << 'EOF'
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
EOF
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "feat: add root README with quick-start, repo structure, and wave map"
```

---

## Task 12: Final Verification

- [ ] **Step 1: Verify complete repo structure**

```bash
find . -not -path './.git/*' -not -path './.git' -not -path './reports/*' | sort
```

Expected output includes all files created across Tasks 1–11.

- [ ] **Step 2: Verify .gitignore is working (no secrets, no reports)**

```bash
echo "test" > config/db_config.env
echo "test" > reports/test.txt
git status
rm config/db_config.env reports/test.txt
```

Expected: neither file appears in `git status` output.

- [ ] **Step 3: Verify shared library sources cleanly**

```bash
bash -c '
  export ORACLE_HOME=/u01/app/oracle/product/19c
  export ORACLE_SID=PRODDB
  export NOTIFY_EMAIL=""
  export LOG_DIR=/tmp/test-dba-verify
  source lib/logger.sh
  source lib/notify.sh
  log_info "logger OK"
  notify_info "test" "notify OK"
  echo "All libraries sourced successfully"
  rm -rf /tmp/test-dba-verify
'
```

Expected: `All libraries sourced successfully`

- [ ] **Step 4: Verify licensing audit script runs with --dry-run**

```bash
./wave6-governance/licensing/feature-usage-audit.sh --dry-run
```

Expected: DRY RUN log line, exit 0.

- [ ] **Step 5: Verify git log shows clean commit history**

```bash
git log --oneline
```

Expected: clean sequence of commits from Tasks 1–11.

- [ ] **Step 6: Push to GitHub**

```bash
git push origin HEAD
```

Expected: branch pushed to GitHub private repo successfully.

---

## Self-Review Notes

**Spec coverage check:**
- Clean repo start → Task 1 ✓
- lib/oracle_connect.sh → Task 6 ✓
- lib/logger.sh → Task 4 ✓
- lib/notify.sh → Task 7 ✓
- config/thresholds.conf → Task 5 ✓
- config/db_config.env.example → Task 5 ✓
- Runbook template → Task 8 ✓
- ADR template → Task 8 ✓
- docs/growth/ structure → Task 8 ✓
- Wave directory skeleton → Task 3 ✓
- Licensing audit early win → Task 10 ✓
- Root README → Task 11 ✓
- GitHub Actions structure → Task 3 ✓
- Script onboarding process documented → Task 9 (wave1 README) ✓

**No placeholders found.** All steps contain complete, executable commands.
