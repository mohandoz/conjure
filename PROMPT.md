# THE PROMPT

Paste the entire block below into a fresh Claude Code session at the **root**
of your repo. Pick ONE invocation line at the top (NEW or EXISTING) before
sending.

---

```
INVOCATION (pick one — delete the other):
  [NEW]      Bootstrap a fresh Claude Code config for this brand-new project.
  [EXISTING] Bootstrap a Claude Code config for this existing repo. Discover
             first; do not assume.

GOAL
Set up the full four-layer Claude Code harness following 2026 best practices:
  • Root CLAUDE.md (≤100 lines, advisory always-on)
  • .claude/skills/*/SKILL.md (lazy-loaded via progressive disclosure)
  • .claude/agents/*.md (isolated-context subagents)
  • .claude/settings.json (hooks for deterministic enforcement)
  • .claudeignore (skip patterns)
Plus integrate persistent knowledge tools (graphify, context7) and structural
search (ast-grep, repomix) where applicable.

CONSTRAINTS (NON-NEGOTIABLE)
  1. Root CLAUDE.md ≤100 lines HARD CAP. Each SKILL.md ≤200 lines. Each nested
     CLAUDE.md ≤50 lines. Each agent.md ≤80 lines.
  2. NEVER use @imports in CLAUDE.md — they load eagerly (same token cost as
     monolithic). Reference files via prose only.
  3. Trigger-action format for rules: "WHEN X, DO Y" or "NEVER X". No vague
     guidance.
  4. Non-negotiable rules go at the TOP of CLAUDE.md (compaction summarizes
     later sections first).
  5. Skill descriptions must be Claude-matchable: one sentence naming the
     trigger user request. Bad: "database helpers". Good: "Query the codebase
     knowledge graph — invoke when user asks where X is used, what depends on
     Y, or how A connects to B."
  6. Every factual claim cites file:line so future Claude can verify.
  7. Hook scripts use exit code 2 for BLOCK (exit 1 is non-blocking). Matcher
     regex is case-sensitive: "Edit|Write|MultiEdit" exactly.
  8. Each SKILL.md is self-contained — readable without siblings; cross-refs
     via "see skills/X/SKILL.md".
  9. Skip irrelevant skills — no messaging skill if no queues, no
     database-schema if NoSQL. Adapt to the actual stack.
 10. For each line written, ask "would removing this cause Claude to make a
     mistake?" If no, cut it.

═══════════════════════════════════════════════════════════════════════════
PHASE 0 — KNOWLEDGE GRAPH (recommended for EXISTING projects ≥50 files)
═══════════════════════════════════════════════════════════════════════════
If graphify is installed AND scope qualifies, run:

  graphify . --mode deep --wiki --mcp &

Outputs:
  graphify-out/graph.json        — persistent queryable graph
  graphify-out/GRAPH_REPORT.md   — audit summary (USE AS DISCOVERY INPUT)
  graphify-out/wiki/             — agent-crawlable index.md + per-community
                                    articles (USE AS DRAFTS for skill bodies)
  MCP stdio server               — query graph at runtime cheaply

Skip if: project <50 files, no graphify install, or strict no-external-tools
policy. Greenfield projects skip Phase 0 entirely.

═══════════════════════════════════════════════════════════════════════════
PHASE 1 — DISCOVERY (read-only; parallel agents; do NOT write yet)
═══════════════════════════════════════════════════════════════════════════
For EXISTING projects, spawn 3-4 parallel Explore subagents (each ≤400 lines
returned):
  • Stack + top-level layout + entrypoints + build/test/deploy commands
  • Domain model + data access + persistence (entities, repos, schemas,
    migrations)
  • Cross-cutting concerns: messaging, auth, config, external integrations,
    secrets/env vars
  • Conventions worth capturing: naming, layering, error handling, test
    patterns, in-flight work (open TODOs, recent commits)

Read README, top-level config files, and `git log -20` yourself in parallel.

If Phase 0 ran: agents START FROM graphify-out/GRAPH_REPORT.md and verify
claims against code rather than re-discovering everything.

For NEW projects, skip discovery; ask the user 5-7 high-leverage questions
instead (stack, primary language, test framework, DB, deployment target,
team size, any existing conventions to honor). Wait for answers before
writing anything.

═══════════════════════════════════════════════════════════════════════════
PHASE 2 — ROOT CLAUDE.md (≤100 lines, top-to-bottom priority order)
═══════════════════════════════════════════════════════════════════════════
Structure exactly in this order:

  1. NON-NEGOTIABLE RULES (5-10 lines) — trigger-action format.
     Examples: "NEVER commit *.csv|*.sql|*.sh at repo root."
              "WHEN editing src/legacy/**, ASK before changing."
              "WHEN adding a dependency, prefer existing @repo/shared package."
  2. BUILD/TEST/RUN commands (5-10 lines, exact strings).
  3. ARCHITECTURE (3-8 lines) — stack one-liner + entry point + layering rule.
  4. ROUTING — prose links to skills.
     Format: "For <topic>, see skills/<name>/SKILL.md."
     One row per skill, ≤1 line each.
  5. CONVENTIONS (5-15 lines) — only non-obvious things Claude got wrong OR
     would get wrong without the rule. Skip anything linters enforce.
  6. REPO HYGIENE — files Claude should not commit (workbench files, secrets,
     large binaries, generated code).

═══════════════════════════════════════════════════════════════════════════
PHASE 3 — SKILLS (.claude/skills/<name>/SKILL.md) — TRUE LAZY LOAD
═══════════════════════════════════════════════════════════════════════════
Each SKILL.md begins with YAML frontmatter:

---
name: <kebab-case-unique>
description: "<one-sentence trigger description — Claude matches user requests
              against this. Name concrete user phrases that should invoke it.>"
---

Body ≤200 lines. Self-contained. File:line citations. Forbidden actions
included. Tables over prose.

CORE TOOLING SKILLS (install if the tool exists):
  • code-graph       — wraps graphify query/path/explain. (Phase 0 dep.)
  • docs-lookup      — wraps context7 MCP for live framework docs.
  • web-research     — wraps firecrawl/exa for current web info.
  • sql-explorer     — wraps Postgres MCP / pg CLI for schema introspection.
  • ast-search       — wraps ast-grep for structural code search.
  • repo-pack        — wraps repomix for full-codebase context dumps.

PROJECT SKILLS (build only the ones that apply):
  • architecture      • domain-model       • api-routes
  • data-access       • messaging          • database-schema
  • build-deploy      • testing            • debugging
  • pr-review         • security-review    • release

DEEP-DIVE SKILLS (build one per heavy data cluster / hot subsystem):
  • <subsystem>-model — e.g. tag-zone-model for refinery orchestrator
  • <pattern>-pattern — e.g. csv-import-pattern for repeated workflows

═══════════════════════════════════════════════════════════════════════════
PHASE 4 — NESTED CLAUDE.md (path-scoping for monorepos / large subsystems)
═══════════════════════════════════════════════════════════════════════════
For each package or major subsystem dir, optionally add a CLAUDE.md (≤50
lines). Loads automatically when Claude reads any file in that subtree; NOT
re-injected after /compact until next file read in that subtree.

Use for: subsystem-scoped test commands, dependency-management rules,
local conventions that override root.

═══════════════════════════════════════════════════════════════════════════
PHASE 5 — SUBAGENTS (.claude/agents/<name>.md)
═══════════════════════════════════════════════════════════════════════════
For verbose work that would bloat main context. YAML frontmatter:

---
name: <name>
description: "<delegation trigger — when should main thread spawn this>"
tools: <comma-separated allowlist; minimize>
model: sonnet | opus | haiku   # optional override
memory: project                  # scope memory inheritance
---

Default set (skip irrelevant):
  • code-explorer      — read-only file locator + call-graph queries
  • test-writer        — generates tests matching project conventions
  • migration-writer   — schema migrations with rollback verification
  • security-auditor   — OWASP / dep audit / secret scan
  • doc-writer         — README/ADR/runbook drafts
  • diff-reviewer      — pre-PR review

═══════════════════════════════════════════════════════════════════════════
PHASE 6 — HOOKS (.claude/settings.json) — DETERMINISTIC ENFORCEMENT
═══════════════════════════════════════════════════════════════════════════
GOTCHAS:
  • Exit 2 = BLOCK. Exit 1 is non-blocking — do NOT use for policy.
  • PreToolUse uses hookSpecificOutput.permissionDecision; other events use
    top-level "decision".
  • Matcher regex is case-sensitive. "Edit|Write|MultiEdit" exactly.
  • Hooks must finish in <2 seconds. Long logic = skill instead.

BASELINE HOOK SET:
  • PostToolUse on Edit|Write|MultiEdit → run formatter on changed file
  • PreToolUse on Bash matcher "git commit" → block if tests/lint not green
  • PreToolUse on Bash matcher "git add" → block if workbench-file patterns
  • Stop → compound-engineering loop: reflect, propose CLAUDE.md edits
  • SessionStart → load dynamic context (current branch, in-flight work, graph
    freshness check)

═══════════════════════════════════════════════════════════════════════════
PHASE 7 — .claudeignore + STANDARD DOCS
═══════════════════════════════════════════════════════════════════════════
Create .claudeignore for patterns Claude should never read:
  node_modules/, target/, build/, dist/, .git/, large generated files
  fixtures/large/, *.lock files (Claude rarely needs them)

If missing, scaffold these standard docs (≤100 lines each):
  • docs/ARCHITECTURE.md     — high-level system diagram (Mermaid OK)
  • docs/GLOSSARY.md         — domain terms (especially for domain-heavy projects)
  • docs/RUNBOOK.md          — ops procedures (deploy, rollback, incident)
  • docs/adr/0001-record-architecture-decisions.md (Michael Nygard ADR template)
  • .env.example             — every env var, with placeholder values
  • CONTRIBUTING.md          — how to contribute
  • SECURITY.md              — vulnerability disclosure
  • CODEOWNERS               — review routing

═══════════════════════════════════════════════════════════════════════════
PHASE 8 — VERIFY (mandatory before declaring done)
═══════════════════════════════════════════════════════════════════════════
  1. Line counts within caps (CLAUDE.md ≤100; SKILL.md ≤200; agent ≤80;
     nested CLAUDE.md ≤50).
  2. Grep root CLAUDE.md for "@" — must find ZERO @imports.
  3. Every SKILL.md description names a concrete trigger user phrase.
  4. Walk through a sample task scenario: "User says 'load this CSV' / 'add
     endpoint' / 'fix bug in X'." Confirm correct skill auto-triggers and
     correct subagent gets delegated. Fix descriptions if wrong skill loads.
  5. Every factual claim cites file:line.
  6. settings.json: hook matchers case-correct, exit codes correct, schema
     fields correct per event type.
  7. Run `bash /u01/claude-init/scripts/audit-setup.sh` (if available).

═══════════════════════════════════════════════════════════════════════════
OUTPUT (when done)
═══════════════════════════════════════════════════════════════════════════
  • File tree with line counts.
  • One-paragraph "first scenario" walkthrough showing which files load for
    a typical task in this project.
  • List of recommended MCP servers to install (see reference/MCP-SERVERS.md
    if /u01/claude-init/ is accessible).
  • List of known gaps / TODOs deferred to next iteration.

No prose recap of what you built. The file tree is the receipt.
```

---

## Tuning add-ons (append to prompt as needed)

```
• Stack constraint: <Java/Spring | Python/FastAPI | TS/Next | Rust/Axum | ...>.
  Skip skills irrelevant to this stack.
• Monorepo: packages live under <packages|services|apps>/*. Add nested
  CLAUDE.md per package.
• Hot subsystem: <name> is touched daily — build a deep-dive skill for it.
• Domain-heavy: include GLOSSARY.md and a domain-model deep-dive skill.
• Pre-commit framework already in use: <gitleaks|husky|pre-commit|lefthook>.
  Wire Claude hooks to complement, not duplicate.
• Compliance: <HIPAA|PCI|SOC2|GDPR>. Add security-review skill + Stop hook
  that scans for PII patterns.
• Performance-critical: add hyperfine benchmarks to testing skill; performance
  budgets to non-negotiable rules.
• Ad-hoc work language: <python | bash | node>. Note in CLAUDE.md conventions.
• MCP stack: install <context7, firecrawl, postgres, sequential-thinking>
  per reference/MCP-SERVERS.md.
```

## After Claude finishes

Run `bash /u01/claude-init/scripts/audit-setup.sh /path/to/repo` for a final
quality check. Fix any flagged items before committing.
