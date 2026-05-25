---
name: pr-review
description: "PR/MR review checklist focusing on bugs, security, logic errors — NOT style nits. Invoke when user asks to review a PR, review a diff, or 'is this ready to merge'."
---

# pr-review

Focus on bugs, security, logic errors. Skip style/format nits — linters handle those.

## Output format

One line per finding:
```
<file:line> <severity> <problem>. <fix>.
```

Severity levels: `critical` / `major` / `minor`. No praise sections, no scope creep.

## Checklist (run mentally on every diff)

### Correctness
- [ ] Does the diff do what the PR description says?
- [ ] Edge cases: empty input, null, zero, negative, overflow, unicode, timezone, leap year.
- [ ] Off-by-one: `<` vs `<=`, inclusive vs exclusive bounds.
- [ ] Concurrency: shared mutable state, race conditions, deadlocks.
- [ ] Error handling: are exceptions caught at the right layer? Are they logged?

### Security
- [ ] User input validated at boundary?
- [ ] SQL/NoSQL/command injection — parameterized queries used?
- [ ] AuthN/AuthZ checks on new endpoints?
- [ ] Secrets in code? In tests? In logs?
- [ ] Dependencies added — license + CVE check.
- [ ] PII handling — redaction in logs, encryption at rest where applicable.

### Performance
- [ ] N+1 query? Use eager fetch or batch.
- [ ] Loop over DB calls? Batch.
- [ ] New allocations in hot path?
- [ ] Index needed for new query pattern?

### Data integrity
- [ ] Migration: rollback included and tested?
- [ ] Backward compatibility for in-flight readers?
- [ ] Constraints (NOT NULL, FK, UNIQUE) match domain rules?

### Tests
- [ ] New code has new tests.
- [ ] Tests test behavior, not implementation.
- [ ] Tests are deterministic (no `time.now()`, no `random()` without seed).

### Documentation
- [ ] Public API change → docs updated?
- [ ] Migration → ADR or CHANGELOG entry?

## Anti-patterns to flag

- Adding mocks instead of integration tests.
- Catching Exception/Throwable broadly.
- TODOs in production code without a tracked issue.
- `// quick fix` style comments — they always survive longer than intended.
- Disabled tests (`@Ignore`, `.skip`) without a linked issue.

## Cross-references

- Security depth → `skills/security-review/SKILL.md`.
- Migration review → `skills/database-schema/SKILL.md`.
