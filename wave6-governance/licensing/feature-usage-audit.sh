#!/usr/bin/env bash
# Oracle Feature Usage — License Compliance Audit
# Compares active Oracle feature usage against config/licenses.conf and flags exposures.
# Safe: read-only, no changes made to the database.
# Usage: ./feature-usage-audit.sh [--dry-run]
#
# Exit codes: 0 = compliant, 1 = license exposures found, 2 = error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

source "${TOOLKIT_ROOT}/lib/logger.sh"
source "${TOOLKIT_ROOT}/lib/oracle_connect.sh"
source "${TOOLKIT_ROOT}/lib/notify.sh"

# Load license configuration
LICENSES_CONF="${TOOLKIT_ROOT}/config/licenses.conf"
if [[ ! -f "$LICENSES_CONF" ]]; then
  log_error "config/licenses.conf not found."
  log_error "Create it from the template: cp config/licenses.conf.example config/licenses.conf"
  exit 2
fi
# shellcheck source=/dev/null
source "$LICENSES_CONF"

DRY_RUN=false
for arg in "$@"; do [[ "$arg" == "--dry-run" ]] && DRY_RUN=true; done

REPORT_DIR="${TOOLKIT_ROOT}/reports/licensing"
REPORT_FILE="${REPORT_DIR}/$(date +%Y-%m-%d)-feature-usage.txt"

if $DRY_RUN; then
  log_info "[DRY RUN] Would query DBA_FEATURE_USAGE_STATISTICS and write to ${REPORT_FILE}"
  log_info "[DRY RUN] Licenses configured: EE=${LICENSE_EE:-NO} | DIAG=${LICENSE_DIAGNOSTICS_PACK:-NO} | TUNING=${LICENSE_TUNING_PACK:-NO}"
  exit 0
fi

oracle_connect_test || { log_error "Cannot connect to Oracle — aborting"; exit 2; }
mkdir -p "$REPORT_DIR"
log_info "Starting license compliance audit"

# ─── License mapping ──────────────────────────────────────────────────────────

# Returns the license key required for a given Oracle feature name
_required_license() {
  local f="$1"
  case "$f" in
    # Diagnostics Pack
    "Active Session History"|"Automatic Workload Repository"|"ADDM"|\
    "Real-Time SQL Monitoring"|"Statistics Advisor"|\
    "Baseline Static Computation"|"Baseline Adaptive Thresholds"|\
    "SQL Tuning Set (system)")
      echo "DIAGNOSTICS_PACK" ;;
    # Tuning Pack
    "Automatic SQL Tuning Advisor"|"SQL Access Advisor"|\
    "SQL Tuning Advisor"|"SQL Tuning Set (user)")
      echo "TUNING_PACK" ;;
    # Partitioning — system variant is EE base
    "Partitioning (system)")
      echo "EE_BASE" ;;
    "Partitioning"|"Partitioning (user)")
      echo "PARTITIONING" ;;
    # Multitenant — single PDB is free in 19c (special check)
    "Oracle Multitenant"|"Multitenant")
      echo "MULTITENANT_SPECIAL" ;;
    # RAC
    "Real Application Clusters"|Oracle\ RAC*)
      echo "RAC" ;;
    # Active Data Guard
    "Active Data Guard"|"Active Data Guard - Real-Time Query")
      echo "ACTIVE_DATA_GUARD" ;;
    # Advanced Compression
    "Advanced Compression"|"Backup High Compression"|\
    "Backup Low Compression"|"Backup Medium Compression")
      echo "ADVANCED_COMPRESSION" ;;
    # Database Vault
    "Database Vault")
      echo "DATABASE_VAULT" ;;
    # Label Security
    "Label Security")
      echo "LABEL_SECURITY" ;;
    # Spatial and Graph
    "Spatial"|"Spatial and Graph"|Graph*)
      echo "SPATIAL_GRAPH" ;;
    # OLAP
    OLAP*)
      echo "OLAP" ;;
    # Advanced Analytics / Machine Learning
    "Data Mining"|"Advanced Analytics"|Oracle\ Machine\ Learning*)
      echo "ADVANCED_ANALYTICS" ;;
    # Advanced Security option — covers TDE, network encryption, ACFS, SecureFiles
    "Encrypted Tablespaces"|"Transparent Data Encryption"|\
    "Backup Encryption"|\
    "Advanced Security"|"Network Encryption"|"Native Network Encryption"|\
    "ASO native encryption and checksumming"|\
    "ACFS Encryption"|\
    "SecureFile Encryption (user)")
      echo "ADVANCED_SECURITY" ;;
    # System-internal SecureFile encryption — EE base, no user license needed
    "SecureFile Encryption (system)")
      echo "EE_BASE" ;;
    # GoldenGate
    GoldenGate*)
      echo "GOLDENGATE" ;;
    # Everything else is EE base
    *)
      echo "EE_BASE" ;;
  esac
}

# Returns YES/NO/SPECIAL for a license key
_is_licensed() {
  case "$1" in
    "EE_BASE")              echo "${LICENSE_EE:-NO}" ;;
    "DIAGNOSTICS_PACK")     echo "${LICENSE_DIAGNOSTICS_PACK:-NO}" ;;
    "TUNING_PACK")          echo "${LICENSE_TUNING_PACK:-NO}" ;;
    "PARTITIONING")         echo "${LICENSE_PARTITIONING:-NO}" ;;
    "MULTITENANT_SPECIAL")  echo "SPECIAL" ;;
    "RAC")                  echo "${LICENSE_RAC:-NO}" ;;
    "ACTIVE_DATA_GUARD")    echo "${LICENSE_ACTIVE_DATA_GUARD:-NO}" ;;
    "ADVANCED_COMPRESSION") echo "${LICENSE_ADVANCED_COMPRESSION:-NO}" ;;
    "DATABASE_VAULT")       echo "${LICENSE_DATABASE_VAULT:-NO}" ;;
    "LABEL_SECURITY")       echo "${LICENSE_LABEL_SECURITY:-NO}" ;;
    "SPATIAL_GRAPH")        echo "${LICENSE_SPATIAL_GRAPH:-NO}" ;;
    "OLAP")                 echo "${LICENSE_OLAP:-NO}" ;;
    "ADVANCED_ANALYTICS")   echo "${LICENSE_ADVANCED_ANALYTICS:-NO}" ;;
    "ADVANCED_SECURITY")    echo "${LICENSE_ADVANCED_SECURITY:-NO}" ;;
    "GOLDENGATE")           echo "${LICENSE_GOLDENGATE:-NO}" ;;
    *)                      echo "UNKNOWN" ;;
  esac
}

# Human-readable license name
_license_label() {
  case "$1" in
    "EE_BASE")              echo "Oracle EE (base)" ;;
    "DIAGNOSTICS_PACK")     echo "Diagnostics Pack" ;;
    "TUNING_PACK")          echo "Tuning Pack" ;;
    "PARTITIONING")         echo "Partitioning option" ;;
    "MULTITENANT_SPECIAL")  echo "Oracle Multitenant option" ;;
    "RAC")                  echo "Real Application Clusters" ;;
    "ACTIVE_DATA_GUARD")    echo "Active Data Guard" ;;
    "ADVANCED_COMPRESSION") echo "Advanced Compression" ;;
    "DATABASE_VAULT")       echo "Database Vault" ;;
    "LABEL_SECURITY")       echo "Label Security" ;;
    "SPATIAL_GRAPH")        echo "Spatial and Graph" ;;
    "OLAP")                 echo "OLAP" ;;
    "ADVANCED_ANALYTICS")   echo "Advanced Analytics" ;;
    "ADVANCED_SECURITY")    echo "Advanced Security (covers TDE)" ;;
    "GOLDENGATE")           echo "GoldenGate" ;;
    *)                      echo "Unknown" ;;
  esac
}

# ─── Query Oracle and categorize features ─────────────────────────────────────

declare -a COVERED=()
declare -a EXPOSURES=()
declare -a MANUAL_CHECK=()
declare -a INACTIVE=()
EXPOSURE_COUNT=0

while IFS='|' read -r raw_name raw_usages raw_date raw_current; do
  fname="$(echo "$raw_name"   | xargs)"
  fused="$(echo "$raw_current" | xargs)"
  fdate="$(echo "$raw_date"   | xargs)"
  [[ -z "$fname" ]] && continue

  req_lic="$(_required_license "$fname")"
  lic_status="$(_is_licensed "$req_lic")"
  lic_label="$(_license_label "$req_lic")"

  if [[ "$req_lic" == "MULTITENANT_SPECIAL" ]]; then
    pdb_count=0
    if [[ "${IS_CDB:-NO}" == "YES" ]]; then
      pdb_count="$(oracle_run_sql_root \
        "SELECT COUNT(*) FROM v\$pdbs WHERE con_id > 2;" | tr -d ' \n')"
    fi
    if [[ "$pdb_count" -gt 1 && "${LICENSE_MULTITENANT:-NO}" != "YES" ]]; then
      EXPOSURES+=("[!!!] ${fname} | ${pdb_count} PDBs — >1 PDB requires Multitenant option | last_used=${fdate}")
      EXPOSURE_COUNT=$((EXPOSURE_COUNT + 1))
    else
      COVERED+=("[OK]  ${fname} | Oracle EE (base) — ${pdb_count} PDB(s), single PDB is free in 19c")
    fi
    continue
  fi

  if [[ "$lic_status" == "YES" ]]; then
    if [[ "$fused" == "TRUE" ]]; then
      COVERED+=("[OK]  ${fname} | ${lic_label}")
    else
      INACTIVE+=("[INFO] ${fname} | ${lic_label} — licensed but not currently active | last_used=${fdate}")
    fi
  elif [[ "$lic_status" == "NO" && "$fused" == "TRUE" ]]; then
    EXPOSURES+=("[!!!] ${fname} | Requires: ${lic_label} — NOT IN config/licenses.conf | last_used=${fdate}")
    EXPOSURE_COUNT=$((EXPOSURE_COUNT + 1))
  elif [[ "$lic_status" == "NO" && "$fused" == "FALSE" ]]; then
    MANUAL_CHECK+=("[CHECK] ${fname} | Requires: ${lic_label} — prior usage, not currently active | last_used=${fdate}")
  else
    MANUAL_CHECK+=("[CHECK] ${fname} | License requirement unknown — verify manually | last_used=${fdate}")
  fi

done < <(oracle_run_sql_root "
SELECT
    name || '|' ||
    detected_usages || '|' ||
    NVL(TO_CHAR(last_usage_date,'YYYY-MM-DD'),'never') || '|' ||
    currently_used
FROM dba_feature_usage_statistics
WHERE detected_usages > 0
ORDER BY name;")

# ─── Print report ─────────────────────────────────────────────────────────────

{
echo "========================================================================"
echo " ORACLE FEATURE USAGE — LICENSE COMPLIANCE AUDIT"
echo "========================================================================"
echo " Database : ${ORACLE_SID}  (IS_CDB=${IS_CDB:-NO})"
echo " Date     : $(date '+%Y-%m-%d %H:%M:%S')"
echo " Licenses : EE=${LICENSE_EE:-NO} | Diagnostics=${LICENSE_DIAGNOSTICS_PACK:-NO} | Tuning=${LICENSE_TUNING_PACK:-NO}"
echo "            Partitioning=${LICENSE_PARTITIONING:-NO} | Multitenant=${LICENSE_MULTITENANT:-NO} | RAC=${LICENSE_RAC:-NO}"
echo "            ADG=${LICENSE_ACTIVE_DATA_GUARD:-NO} | AdvComp=${LICENSE_ADVANCED_COMPRESSION:-NO} | Vault=${LICENSE_DATABASE_VAULT:-NO}"
echo " Metric   : ${LICENSE_METRIC:-UNKNOWN} | Users: ${LICENSE_USER_COUNT:-0}"
echo "========================================================================"

echo ""
echo "────────────────────────────────────────────────────────────────────────"
echo " [OK] LICENSED AND IN USE (${#COVERED[@]})"
echo "────────────────────────────────────────────────────────────────────────"
if [[ "${#COVERED[@]}" -gt 0 ]]; then
  for f in "${COVERED[@]}"; do echo "  $f"; done
else
  echo "  (none)"
fi

if [[ "${#INACTIVE[@]}" -gt 0 ]]; then
  echo ""
  echo "────────────────────────────────────────────────────────────────────────"
  echo " [INFO] LICENSED BUT NOT CURRENTLY ACTIVE (${#INACTIVE[@]})"
  echo "────────────────────────────────────────────────────────────────────────"
  for f in "${INACTIVE[@]}"; do echo "  $f"; done
fi

if [[ "${#MANUAL_CHECK[@]}" -gt 0 ]]; then
  echo ""
  echo "────────────────────────────────────────────────────────────────────────"
  echo " [CHECK] MANUAL VERIFICATION NEEDED (${#MANUAL_CHECK[@]})"
  echo "────────────────────────────────────────────────────────────────────────"
  for f in "${MANUAL_CHECK[@]}"; do echo "  $f"; done
fi

if [[ "${#EXPOSURES[@]}" -gt 0 ]]; then
  echo ""
  echo "════════════════════════════════════════════════════════════════════════"
  echo " [!!!] LICENSE EXPOSURES — IMMEDIATE ACTION REQUIRED (${EXPOSURE_COUNT})"
  echo "════════════════════════════════════════════════════════════════════════"
  for f in "${EXPOSURES[@]}"; do echo "  $f"; done
  echo ""
  echo "  These features are ACTIVELY IN USE but NOT listed as licensed in"
  echo "  config/licenses.conf. Options:"
  echo "    1. Purchase the required option/pack from Oracle"
  echo "    2. Disable the feature if it is not intentionally used"
  echo "    3. If you believe this is a false positive, update config/licenses.conf"
  echo "       and document the reason in docs/architecture/"
fi

echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo " COMPLIANCE SUMMARY"
echo "════════════════════════════════════════════════════════════════════════"
echo "  Licensed & active   : ${#COVERED[@]}"
echo "  Licensed & inactive : ${#INACTIVE[@]}"
echo "  Manual check needed : ${#MANUAL_CHECK[@]}"
echo "  EXPOSURES           : ${EXPOSURE_COUNT}"
echo ""
if [[ "$EXPOSURE_COUNT" -eq 0 ]]; then
  echo "  RESULT: COMPLIANT — No license exposures detected."
else
  echo "  RESULT: NON-COMPLIANT — ${EXPOSURE_COUNT} exposure(s) require immediate action."
  echo "          Contact your Oracle account manager or licensing team."
fi
echo "========================================================================"
} | tee "$REPORT_FILE"

log_info "Report saved to ${REPORT_FILE}"

if [[ "$EXPOSURE_COUNT" -gt 0 ]]; then
  notify_crit "Oracle License Exposure on ${ORACLE_SID}" \
    "${EXPOSURE_COUNT} unlicensed feature(s) actively in use. Review: ${REPORT_FILE}"
  exit 1
fi
