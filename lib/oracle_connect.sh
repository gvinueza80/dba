#!/usr/bin/env bash
# Shared Oracle connection helper. Source this file — do not execute directly.
# Usage: source lib/oracle_connect.sh
#        $SQLPLUS -S / as sysdba @script.sql
#        oracle_connect_test  # returns 0 if connection succeeds

# Guard: requires bash (not ksh/sh — 'local' and [[ ]] are bash-specific)
if [ -z "$BASH_VERSION" ]; then
  echo "ERROR: lib/oracle_connect.sh requires bash. Run 'bash' first, then source again." >&2
  return 1 2>/dev/null || exit 1
fi

# Load shared config (NOTIFY_EMAIL, LOG_DIR, ORACLE_BASE, AUTO_RECOMPILE, etc.)
# db_config.env must NOT contain ORACLE_SID or ORACLE_HOME — those are per-database.
_TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${_TOOLKIT_ROOT}/config/db_config.env" ]]; then
  # shellcheck source=/dev/null
  source "${_TOOLKIT_ROOT}/config/db_config.env"
fi

# Load per-database config if ORACLE_SID is already set and a matching file exists.
# Clear database-specific vars first so stale values from a previous run never bleed through.
# Create config/db_<SID>.env for each database (see config/db_EXAMPLE.env.example).
unset IS_CDB ORACLE_PDB ORACLE_HOME DBA_USER DBA_PASS ORACLE_WALLET_LOC
if [[ -n "${ORACLE_SID:-}" && -f "${_TOOLKIT_ROOT}/config/db_${ORACLE_SID}.env" ]]; then
  # shellcheck source=/dev/null
  source "${_TOOLKIT_ROOT}/config/db_${ORACLE_SID}.env"
fi

# Export key variables so child processes (sqlplus, rman, dgmgrl) inherit them.
# Config files may assign without 'export'; without this block sqlplus cannot
# find its message files and fails with SP2-0667.
[[ -n "${ORACLE_SID:-}"  ]] && export ORACLE_SID
[[ -n "${ORACLE_HOME:-}" ]] && export ORACLE_HOME && export PATH="${ORACLE_HOME}/bin:${PATH}"
[[ -n "${ORACLE_BASE:-}" ]] && export ORACLE_BASE
[[ -n "${IS_CDB:-}"      ]] && export IS_CDB

# Load thresholds
if [[ -f "${_TOOLKIT_ROOT}/config/thresholds.conf" ]]; then
  # shellcheck source=/dev/null
  source "${_TOOLKIT_ROOT}/config/thresholds.conf"
fi

# If ORACLE_HOME is still not set, derive it from /etc/oratab using ORACLE_SID.
if [[ -z "${ORACLE_HOME:-}" && -n "${ORACLE_SID:-}" ]]; then
  _ORATAB="${ORATAB:-/etc/oratab}"
  if grep -q "^${ORACLE_SID}:" "$_ORATAB" 2>/dev/null; then
    ORACLE_HOME=$(grep "^${ORACLE_SID}:" "$_ORATAB" | cut -d':' -f2)
    export ORACLE_HOME
    export PATH="$ORACLE_HOME/bin:$PATH"
  fi
fi

# Validate ORACLE_HOME
if [[ -z "${ORACLE_HOME:-}" ]]; then
  echo "ERROR: ORACLE_HOME is not set." >&2
  echo "  Set ORACLE_SID before sourcing this lib, or create config/db_${ORACLE_SID:-YOURSID}.env" >&2
  echo "  See config/db_EXAMPLE.env.example for the template." >&2
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
  if [[ -n "${ORACLE_WALLET_LOC:-}" ]]; then
    echo "/@${ORACLE_SID}"
  elif [[ -n "${DBA_USER:-}" && -n "${DBA_PASS:-}" ]]; then
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
# For CDB with ORACLE_PDB set, automatically switches to that PDB container first.
oracle_run_sql() {
  local sql="$1"
  local container_sql=""
  if [[ "${IS_CDB:-NO}" == "YES" && -n "${ORACLE_PDB:-}" ]]; then
    container_sql="ALTER SESSION SET CONTAINER = ${ORACLE_PDB};"
  fi
  "$SQLPLUS" -S "$ORACLE_CONN_STRING" <<EOF 2>&1
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200 TRIMSPOOL ON
${container_sql}
${sql}
EXIT;
EOF
}

# Run a SQL string always at CDB root level (ignores ORACLE_PDB).
# Use for instance-level queries: licensing, health check, V$ views.
oracle_run_sql_root() {
  local sql="$1"
  "$SQLPLUS" -S "$ORACLE_CONN_STRING" <<EOF 2>&1
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 200 TRIMSPOOL ON
${sql}
EXIT;
EOF
}