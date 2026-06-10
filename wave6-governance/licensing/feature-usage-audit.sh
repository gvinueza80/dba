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
