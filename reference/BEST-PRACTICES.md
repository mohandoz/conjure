# Best Practices — Consolidated 2026

Sourced from: Anthropic official docs, the 2,455-evaluation community benchmark
(Sonnet + Opus), ETH Zurich repo-context study, and production teams' setups.

## The four-layer harness

| Layer | Purpose | Trade-off |
| --- | --- | --- |
| **CLAUDE.md** | Persistent advisory rules | Always loads → costs tokens every session |
| **Skills** | On-demand instructions | True lazy load via progressive disclosure |
| **Subagents** | Isolated-context delegation | Only summary returns to main thread |
| **Hooks** | Deterministic enforcement | 100% reliable, but only for shell-scriptable rules |

## Size rules (research-backed)

| Artifact | Hard cap | Practical sweet spot |
| --- | --- | --- |
| Root `CLAUDE.md` | 200 lines (Anthropic) | 50-80 lines (eval data) |
| Each `SKILL.md` body | 200 lines | 80-150 lines |
| Each agent definition | 80 lines | 30-50 lines |
| Each nested `CLAUDE.md` | 50 lines | 20-40 lines |
| `.claude/` total tokens | 25k | 10-15k |

ETH Zurich finding: repository context files tend to REDUCE task success rates
compared to no context, while adding >20% to inference cost. Less is more.

## `@import` is organizational only

`@docs/X.md` in CLAUDE.md loads X.md EAGERLY into the session context — same
cost as inlining. It does NOT save tokens. The only way to truly lazy-load:

- Reference files via prose: "For X, read skills/X/SKILL.md".
- Use Skills (progressive disclosure: metadata first, body on trigger).
- Use nested CLAUDE.md (loads only when files in that subtree are read).

## Trigger-action format

Eval data shows "WHEN X, DO Y" outperforms general guidance. Examples:

| Bad | Good |
| --- | --- |
| "Write clean code." | "NEVER use `any` type — use `unknown` and narrow." |
| "Be careful with the database." | "WHEN editing migrations/, run `./gradlew updateTestingRollback` before commit." |
| "Follow conventions." | "WHEN naming a test, use `should_<behavior>_when_<condition>` form." |

## Order matters in CLAUDE.md

Read top-to-bottom. Compaction summarizes later sections FIRST. Put
non-negotiables at the top:

1. Non-negotiable rules
2. Build/test commands
3. Architecture summary
4. Routing table (links to skills)
5. Conventions
6. Repo hygiene

## Compaction survival

| Artifact | Survives `/compact`? |
| --- | --- |
| Root `CLAUDE.md` | YES (re-injected from disk) |
| Nested `<dir>/CLAUDE.md` | NO (until next file in that dir is read) |
| Loaded skill bodies | Partial — last invocation kept up to 5k tokens, total cap 25k |
| Subagent summaries | YES (already condensed) |
| Tool outputs | NO (cleared first) |
| In-conversation rules | NO (lost) |

Put anything that must survive compaction in the root CLAUDE.md.

## Compound engineering loop

Every correction is data. Boris Cherny (Anthropic) principle:

```
user corrects Claude → Claude proposes rule → user accepts → CLAUDE.md grows
```

Implement via Stop hook (`templates/hooks/stop-compound-engineering.sh`).
Reviews session at the end and appends candidate rules to
`.claude/COMPOUND-CANDIDATES.md`.

## When to use what

| Need | Tool |
| --- | --- |
| Rule that applies every session | CLAUDE.md |
| Workflow that applies sometimes | Skill |
| Verbose research / exploration | Subagent |
| Non-negotiable rule | Hook |
| Live framework docs | context7 MCP |
| Persistent codebase knowledge | graphify |
| Structural code search | ast-grep (skill) |
| Full-codebase dump | repomix (skill) |
| Web research | firecrawl / WebFetch |

## Don't fight the agent

- If Claude keeps making the same mistake, the CLAUDE.md rule is unclear or
  buried. Promote it (top of file) or convert to a hook.
- If a skill loads when it shouldn't, the description is too broad. Rewrite.
- If a skill doesn't load when it should, the description doesn't match
  user phrasing. Rewrite using user's actual words.

## Anti-patterns (eval-confirmed)

- ❌ Monolithic 500-line CLAUDE.md → adherence drops sharply past 200 lines.
- ❌ Embedding code or docs verbatim → goes stale immediately.
- ❌ Slash commands for everything → user-facing complexity grows; Claude
  loses orchestration freedom.
- ❌ Installing 10+ MCP servers → context bloat with marginal returns.
- ❌ Vague rules ("write good code") → unenforceable.
- ❌ Skipping discovery on existing repos → Claude invents conventions.

## Cite for verification

Every factual claim about the codebase should include `file:line` so future
Claude (in a different session, after refactors) can re-verify.

## Sources

- [Best practices for Claude Code — Anthropic](https://code.claude.com/docs/en/best-practices)
- [How Claude remembers your project — Anthropic](https://code.claude.com/docs/en/memory)
- [Extend Claude with skills — Anthropic](https://code.claude.com/docs/en/skills)
- [How Claude Code works in large codebases — Anthropic blog](https://claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start)
- [Designing CLAUDE.md correctly: 2026 — ObviousWorks](https://www.obviousworks.ch/en/designing-claude-md-right-the-2026-architecture-that-finally-makes-claude-code-work/)
- [Claude Code Best Practices 2026 — The Prompt Shelf](https://thepromptshelf.dev/blog/claude-code-best-practices-2026/)
- [Claude Code Hooks: Complete 2026 Reference — The Prompt Shelf](https://thepromptshelf.dev/blog/claude-code-hooks-complete-reference-2026/)
