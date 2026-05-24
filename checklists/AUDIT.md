# Checklist — Audit Existing Claude Code Setup

Run periodically (monthly, or after major refactors). Automatable via
`scripts/audit-setup.sh`.

## Quantitative (size budgets)

- [ ] Root `CLAUDE.md` ≤100 lines (hard cap; warn at 80).
- [ ] Each `.claude/skills/*/SKILL.md` ≤200 lines.
- [ ] Each `.claude/agents/*.md` ≤80 lines.
- [ ] Each nested `<dir>/CLAUDE.md` ≤50 lines.
- [ ] Total `.claude/` directory token estimate ≤25k (rough: chars/4).

## Structural integrity

- [ ] Zero `@imports` in root CLAUDE.md (`grep -n "^@" CLAUDE.md` returns empty).
- [ ] Every SKILL.md has YAML frontmatter with `name:` and `description:` fields.
- [ ] Every skill `description:` names a concrete trigger phrase (not vague like "database stuff").
- [ ] Every agent `description:` describes WHEN main thread should delegate.
- [ ] `.claude/settings.json` is valid JSON.
- [ ] Hook scripts are executable (`chmod +x`).
- [ ] Hook scripts exit 2 (not 1) for blocking.

## Accuracy (claims vs code)

- [ ] Spot-check 5 random file:line citations across skills — do they still exist and contain what's claimed?
- [ ] Routing table in CLAUDE.md points to skills that actually exist.
- [ ] Build/test commands in CLAUDE.md actually work (run them).
- [ ] graphify-out/ (if used) age — rebuild if >7 days OR >20 commits since.

## Trigger coverage (does it actually fire?)

- [ ] Pick 5 realistic developer requests. For each, predict which skill should fire. Test in a fresh session — does it?
  - Example: "Load this CSV into Postgres" → csv-import-pattern OR sql-explorer.
  - Example: "Where is User authentication?" → code-graph OR architecture.
  - Example: "Add an endpoint for X" → api-routes OR architecture.

## Anti-pattern scan

- [ ] No skill description longer than 2 sentences.
- [ ] No skill body that's "everything about this codebase" (over-broad scope).
- [ ] No CLAUDE.md rules that linter/formatter already enforces.
- [ ] No CLAUDE.md rule that Claude has never violated (delete unused rules).
- [ ] No vague rules ("write clean code"). Replace with specific bans ("NEVER use `any` type").
- [ ] No duplication across skills (cross-reference instead).
- [ ] No commented-out content in CLAUDE.md / settings.json.

## Compaction survival check

- [ ] Open a long session, run `/compact`, then ask: "What are the non-negotiable rules?" If Claude can't name them, they're not at the top of CLAUDE.md.

## Hook health

- [ ] PostToolUse formatter hooks actually format (run a sample edit; verify).
- [ ] PreToolUse blockers actually block (try a forbidden action; verify exit 2).
- [ ] Stop hook ran at last session end (check logs).
- [ ] SessionStart hook completes in <2s (timing matters; user feels every ms).

## Compound-engineering loop

- [ ] Review the last 10 corrections you made to Claude. How many became:
  - CLAUDE.md rules? (target: high)
  - skills? (target: medium)
  - hooks? (target: only non-negotiables)
- [ ] If <30% became durable rules, your Stop hook isn't doing its job.

## When to retire content

A rule, skill, or hook should be removed if:
- It hasn't fired in 3 months (skill) OR Claude hasn't violated it in 3 months (rule).
- The underlying code/convention changed and the artifact is now wrong.
- It duplicates another rule/skill.
- It's vague enough that Claude interprets it inconsistently.

Be ruthless. Less is more (ETH Zurich finding: more context REDUCES success rate).
