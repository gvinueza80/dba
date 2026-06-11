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

# Guard: requires bash (not ksh/sh — 'local' and [[ ]] are bash-specific)
if [ -z "$BASH_VERSION" ]; then
  echo "ERROR: lib/notify.sh requires bash. Run 'bash' first, then source again." >&2
  return 1 2>/dev/null || exit 1
fi

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