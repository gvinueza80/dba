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