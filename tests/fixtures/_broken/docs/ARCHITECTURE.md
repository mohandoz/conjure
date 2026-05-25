# Architecture

## What this system does (one paragraph)

<plain-language description; no jargon>

## System diagram

```mermaid
flowchart LR
  user[User] --> api[API]
  api --> service[Service Layer]
  service --> db[(Database)]
  service --> queue[(Message Queue)]
  queue --> worker[Worker]
  worker --> db
```

## Components

| Component | Responsibility | Runtime | Owner |
| --- | --- | --- | --- |

## Data flow (happy path)

1. <step>
2. <step>
3. <step>

## External dependencies

| System | Purpose | Protocol | Failure mode |
| --- | --- | --- | --- |

## Data stores

| Store | Schema location | Backup policy | Retention |
| --- | --- | --- | --- |

## Deployment topology

```mermaid
flowchart TD
  subgraph prod
    lb[Load Balancer]
    app1[App Instance 1]
    app2[App Instance 2]
    db[(Primary DB)]
    db_replica[(Read Replica)]
  end
```

## Trust boundaries

- <internal vs external>
- <admin vs user>
- <what crosses each boundary>

## Performance characteristics

| Metric | Target | Current |
| --- | --- | --- |
| p50 latency | <ms> | <ms> |
| p99 latency | <ms> | <ms> |
| Throughput | <rps> | <rps> |

## Known limitations

- <limitation>: <why it exists, what it would take to fix>

## References

- ADRs: `docs/adr/`
- Runbook: `docs/RUNBOOK.md`
- Glossary: `docs/GLOSSARY.md`
