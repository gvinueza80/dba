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
