#!/usr/bin/env bash
# Written by: H.Sallans templated from Joslyn Gordon SCT
# Updated by: Marco Castillo
# Date:       Jun 2025
# Filename:   rman_backup.sh
# Descr:      This script performs hot backups using RMAN (incremental level 0/1/2)
#             parameters stored in the controlfile
# Usage:      ./rman_backup.sh <ORACLE_SID> <BACKUP_LEVEL>
# Example:    ./rman_backup.sh TRNG 0
# Example:    ./rman_backup.sh TRNG 1
#
# Ported from hot_backup_LinuxDB.ksh into the Oracle DBA toolkit framework.
# Changes from original:
#   - Toolkit libs sourced (logger.sh, oracle_connect.sh, notify.sh)
#   - ORACLE_HOME read from /etc/oratab instead of oraenv
#   - RECIP removed; notifications via notify_info/notify_warn/notify_crit
#   - mailx calls replaced with notify_* functions
#   - Double delete noprompt obsolete bug fixed (removed the one without RECOVERY WINDOW)
#   - RMAN_RETENTION_DAYS config variable replaces hardcoded 7
#   - LOG_FILE uses toolkit convention under reports/backup/
#   - DATE variable redefined with timestamp format

if [ $# -ne 2 ]; then
  echo "Usage: $0 <ORACLE_SID> <BACKUP_LEVEL: 0|1|2>"
  exit 1
fi

export ORACLE_SID=$1
export BACKUP_LEVEL=$2

if [[ "$BACKUP_LEVEL" != "0" && "$BACKUP_LEVEL" != "1" && "$BACKUP_LEVEL" != "2" ]]; then
  echo "Error: BACKUP_LEVEL must be 0, 1, or 2"
  exit 2
fi

PATH=/usr/local/bin:$PATH; export PATH

# === Derive ORACLE_HOME from /etc/oratab ===
ORATAB="${ORATAB:-/etc/oratab}"
if ! grep -q "^${ORACLE_SID}:" "$ORATAB"; then
  echo "[ERROR] Database $ORACLE_SID not found in $ORATAB"
  exit 2
fi
ORACLE_HOME=$(grep "^${ORACLE_SID}:" "$ORATAB" | cut -d':' -f2)
export ORACLE_HOME
export PATH=$ORACLE_HOME/bin:$PATH

# === Toolkit bootstrap ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# === Log file setup (must precede logger.sh so _log_init uses the correct path) ===
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${TOOLKIT_ROOT}/reports/backup/${ORACLE_SID}/rman_backup_${BACKUP_LEVEL}_${DATE}.log"
mkdir -p "$(dirname "$LOG_FILE")"

source "${TOOLKIT_ROOT}/lib/logger.sh"
source "${TOOLKIT_ROOT}/lib/oracle_connect.sh"
source "${TOOLKIT_ROOT}/lib/notify.sh"

# RMAN_RETENTION_DAYS comes from thresholds.conf
# shellcheck source=/dev/null
[[ -f "${TOOLKIT_ROOT}/config/thresholds.conf" ]] && source "${TOOLKIT_ROOT}/config/thresholds.conf"

export NLS_DATE_FORMAT='DD-MON-YYYY HH24:MI:SS'

unset TWO_TASK

"$ORACLE_HOME/bin/rman" target / nocatalog >> "$LOG_FILE" 2>&1 <<EOF
backup incremental level ${BACKUP_LEVEL} database plus archivelog delete all input;
BACKUP CURRENT CONTROLFILE;
BACKUP SPFILE;
SQL 'ALTER SYSTEM ARCHIVE LOG CURRENT';
BACKUP ARCHIVELOG ALL
    NOT BACKED UP 1 TIMES
    DELETE INPUT;
DELETE NOPROMPT OBSOLETE RECOVERY WINDOW OF ${RMAN_RETENTION_DAYS:-7} DAYS;
exit;
EOF
RMAN_EXIT=$?

if [ $RMAN_EXIT -eq 0 ]; then
  kount=$(grep WARNING "$LOG_FILE" | grep -v RMAN-08137 | wc -l)

  if [ "${kount}" -eq 0 ]; then
    notify_info "RMAN Backup LVL ${BACKUP_LEVEL} Success — ${ORACLE_SID}" "$(cat "$LOG_FILE")"
  else
    notify_warn "RMAN Backup LVL ${BACKUP_LEVEL} Success with Warnings — ${ORACLE_SID}" "$(cat "$LOG_FILE")"
  fi
else
  notify_crit "RMAN Backup LVL ${BACKUP_LEVEL} FAILED — ${ORACLE_SID}" "$(cat "$LOG_FILE")"
fi
