# Anti-Patterns

Things that look like good ideas but degrade Claude Code performance. All
backed by eval data or production reports.

## CLAUDE.md

| Anti-pattern | Why it's bad | Fix |
| --- | --- | --- |
| 500-line CLAUDE.md "for completeness" | Adherence drops past ~200 lines; ETH study: more context → lower success rate | Cap at 100 lines; move detail to skills |
| `@import` chain for organization | Loads eagerly — same cost as monolithic | Use prose links to skill files |
| Vague rules ("write clean code") | Unenforceable; Claude interprets inconsistently | Replace with specific bans ("NEVER use `any` type") |
| Documenting what code obviously says | Wastes tokens, goes stale | Only document what Claude got wrong |
| Critical rules buried at the bottom | Compaction summarizes them first | Put non-negotiables at top |
| Repeating linter/formatter rules | Already enforced deterministically | Trust the tools; don't duplicate |
| Marketing language / preamble | Looks professional, helps nothing | Cut every line that doesn't change behavior |

## Skills

| Anti-pattern | Why it's bad | Fix |
| --- | --- | --- |
| Vague descriptions ("utilities", "helpers") | Won't fire on right user phrase | Name concrete trigger phrases in description |
| One mega-skill called "this-codebase" | Defeats progressive disclosure | Split by topic |
| Skill body that's a code dump | Stale immediately, no value over reading code | Tables of file:line refs, not code |
| Cross-skill duplication | Wastes tokens when both load | Cross-reference: "see skills/X/SKILL.md" |
| description > 2 sentences | Matching gets fuzzy | One concrete trigger sentence |
| Skill that never fires | Dead weight | Audit quarterly; remove |

## Subagents

| Anti-pattern | Why it's bad | Fix |
| --- | --- | --- |
| Subagent with all tools granted | Defeats isolation; subagent can do damage | Minimal `tools:` allowlist |
| Subagent body 300+ lines | Same problem as long CLAUDE.md | Keep ≤80 lines |
| Spawning subagent for trivial task | Overhead > savings | Only delegate verbose work |
| Subagent that does writes silently | Hard to verify | Always require subagent to report file changes in summary |

## Hooks

| Anti-pattern | Why it's bad | Fix |
| --- | --- | --- |
| `exit 1` for policy enforcement | Exit 1 is non-blocking; dangerous action proceeds | Use exit 2 |
| Matcher regex with wrong case | "Edit\|Write\|multiEdit" misses MultiEdit | Match case exactly: `Edit\|Write\|MultiEdit` |
| Hook with complex logic | Slows session, breaks unpredictably | Move logic to a skill; keep hooks <2s |
| Hook that runs the full test suite on every edit | Blocks Claude on minor edits | Only run on `git commit`; do lint at edit time |
| PostCompact hook clobbering important state | Hard to debug | Test hook with `--debug` first |
| Hook that swallows errors silently | Hides bugs in your harness | Log to `.claude/hooks.log` |

## Slash commands

| Anti-pattern | Why it's bad | Fix |
| --- | --- | --- |
| Slash command for every workflow | User-facing complexity grows; Claude loses orchestration | Let main agent spawn via Task() |
| Slash commands that duplicate skills | Two ways to do same thing → drift | Pick one |

## MCP servers

| Anti-pattern | Why it's bad | Fix |
| --- | --- | --- |
| Installing every server "in case" | Eager-loaded tool catalogs bloat context | ≤6 servers; audit yearly |
| MCP server with admin DB credentials | Catastrophic if compromised | Read-only role for AI |
| Trusting MCP output as truth | Anthropic doesn't verify servers | Verify factual claims against authoritative source |
| Server fetching untrusted content + write access | Prompt injection → destructive action | Confirm before any write driven by fetched content |

## Workflow

| Anti-pattern | Why it's bad | Fix |
| --- | --- | --- |
| Single Claude session for entire day | Context bloat, drift | Fresh session per task; `/clear` between |
| Auto-`/compact` reliance | Compaction is opaque; rules can disappear | Use `/clear` + a "catchup" command on changed files |
| Letting Claude commit `.claude/*` without review | Harness is code; review like code | Always read the diff |
| Skipping graphify on a 500-file repo | Massive missed leverage | Run on day 1 |
| Editing many files per turn | Hard to bisect when something breaks | Atomic commits per logical change |
| Saying "make it better" | Unbounded; Claude wanders | Specify what to change and why |
| Not citing file:line in skills | Future-Claude can't verify | Cite or it doesn't exist |

## Maintenance

| Anti-pattern | Why it's bad | Fix |
| --- | --- | --- |
| Never auditing the `.claude/` directory | Bit-rot; dead rules | Quarterly audit via checklists/AUDIT.md |
| Adding rules without removing | Bloat | Compound-engineering loop: every quarter, prune what hasn't fired |
| Documenting "history" in CLAUDE.md | Future you doesn't care | Put history in commit messages / ADRs |
| Editing skills without bumping version | Drift between teammates | Treat skills like code; review changes |
