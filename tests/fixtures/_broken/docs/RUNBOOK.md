# Runbook

Operational procedures for this service.

## Owners / on-call

- Primary: <name / @handle / pager>
- Secondary: <name>
- Escalation: <name>
- Slack: `#<channel>`

## Health check

```bash
<command that confirms service is healthy>
```

## Common operations

### Deploy

See `skills/build-deploy/SKILL.md` and `skills/release/SKILL.md`.

```bash
<deploy command>
```

### Rollback

```bash
<rollback command>
```

Verify:
```bash
<verification>
```

### Restart

```bash
<restart command>
```

### Scale up / down

```bash
<command>
```

## Incidents

### Symptom: <description>

**Likely causes**:
- <cause>
- <cause>

**Diagnosis**:
```bash
<commands to gather info>
```

**Mitigation**:
1. <step>
2. <step>

**Resolution**:
1. <step>

**Post-incident**:
- File ticket: <where>
- Update this runbook with anything learned.

## Dashboards

| Name | URL | What to watch |
| --- | --- | --- |

## Alerts

| Alert | Severity | Action |
| --- | --- | --- |

## Backups & restore

- Backup schedule: <when>
- Backup location: <where>
- Restore procedure: <command + expected duration>
- Tested last: <date>

## Maintenance windows

- <recurring window>: <impact>
