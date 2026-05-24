---
name: debugging
description: "Systematic debugging workflows: log analysis, attach debugger, bisect, repro recipes. Invoke when user reports a bug, asks 'why is this failing', or shares an error message."
---

# debugging

## First-response protocol

1. Reproduce locally. If can't reproduce, ask for repro steps before guessing.
2. Read the actual error/stack trace. Quote it verbatim, don't paraphrase.
3. Form a hypothesis. State it explicitly before testing.
4. Bisect: `git bisect start; git bisect bad; git bisect good <ref>`.
5. Test hypothesis with the SMALLEST possible change.
6. If hypothesis wrong, form new one — don't shotgun fixes.

## Logging

- App logs: `<location>`.
- Log level toggles: `<file / property name>`.
- DEBUG-worthy classes: `<list — e.g. ai.beyond.luminai.orchestrator.implementation.clients.DefaultReasonerClient>`.

## Common runtime tools

| Goal | Tool |
| --- | --- |
| Attach debugger | `<command>` |
| Profile CPU | `<tool>` |
| Profile memory | `<tool>` |
| Trace network | `<tool>` |
| Inspect DB | `skills/sql-explorer/SKILL.md` |

## Production debugging

- Tunnel script: `<path>`.
- Read-only DB role: `<role name>` — never log in as superuser.
- Log aggregation: `<service — Datadog / Splunk / CloudWatch>`.
- Trace IDs: `<header / propagation pattern>`.

## Bisect helper

```bash
git bisect start
git bisect bad HEAD
git bisect good <known-good-commit>
git bisect run <command-that-exits-0-when-good>
```

## Anti-patterns

- ❌ Adding `try/except` to "fix" an exception without understanding root cause.
- ❌ Bumping timeouts to mask perf bugs.
- ❌ Reverting commits without diagnosis (rerun bisect first).
- ❌ Disabling tests instead of fixing them.

## Cross-references

- Build/test commands → `skills/build-deploy/SKILL.md`.
- DB queries → `skills/sql-explorer/SKILL.md`.
- Knowledge graph queries → `skills/code-graph/SKILL.md`.
