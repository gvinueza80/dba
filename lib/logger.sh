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