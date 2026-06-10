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