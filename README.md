# claude-init — Production-Grade Claude Code Project Kit

Opinionated, battle-tested initialization kit for any project (new or existing,
any stack). Built on 2026 best practices from Anthropic docs + production
benchmarks (2,455-eval study, ETH Zurich findings). Designed for high-stakes
projects where people depend on the code.

## What you get

A four-layer harness that makes Claude Code reliable instead of advisory:

| Layer | File | Role | Loaded |
| --- | --- | --- | --- |
| **CLAUDE.md** | root memory | Always-on advisory rules (≤100 lines) | Every session |
| **Skills** | `.claude/skills/<name>/SKILL.md` | Lazy-loaded instructions w/ progressive disclosure | On trigger match |
| **Subagents** | `.claude/agents/<name>.md` | Isolated context for verbose work | On delegation |
| **Hooks** | `.claude/settings.json` | Deterministic shell-script enforcement | On event |

Plus integrations with: **graphify** (persistent knowledge graph), **context7**
(live docs), **repomix** (code packing), **ast-grep** (structural search),
**firecrawl** (web research), **Postgres MCP** (DB introspection).

## Usage

Pick your scenario:

| Scenario | Start here |
| --- | --- |
| Brand-new project from zero | `checklists/NEW-PROJECT.md` |
| Existing repo, no Claude config yet | `checklists/EXISTING-PROJECT.md` |
| Existing Claude config, want to audit | `checklists/AUDIT.md` |
| Onboarding new dev to repo Claude already knows | `checklists/ONBOARDING.md` |
| Just want the prompt | `PROMPT.md` — paste into Claude Code |

## Files in this kit

```
PROMPT.md                          ← THE prompt — paste into a fresh session
checklists/
  NEW-PROJECT.md                   ← greenfield step-by-step
  EXISTING-PROJECT.md              ← brownfield step-by-step
  AUDIT.md                         ← health check for existing setup
  ONBOARDING.md                    ← onboard new developer
templates/
  CLAUDE.md.tmpl                   ← root memory skeleton
  settings.json.tmpl               ← hooks + permissions
  .claudeignore                    ← skip patterns
  .editorconfig / .gitattributes   ← consistency
  skills/                          ← 17 skill scaffolds (graphify, context7,
                                    repomix, ast-grep, plus 13 project skills)
  agents/                          ← 6 subagent scaffolds
  hooks/                           ← 5 hook shell scripts
  docs/                            ← ADR / GLOSSARY / RUNBOOK / ARCHITECTURE
reference/
  BEST-PRACTICES.md                ← consolidated 2026 best practices
  TOOLS-CATALOG.md                 ← every tool worth knowing
  MCP-SERVERS.md                   ← which MCPs to install + configs
  ANTI-PATTERNS.md                 ← what NOT to do (with evidence)
  SIZING.md                        ← line counts, token budgets
  COMPACTION.md                    ← surviving context compaction
  PROMPTING-PATTERNS.md            ← trigger-action format + examples
scripts/
  init-project.sh                  ← bootstrap (new or existing)
  audit-setup.sh                   ← health check
  refresh-graph.sh                 ← rebuild graphify
  install-mcp-stack.sh             ← install recommended MCPs
```

## Core principles (read these first)

1. **Less context = better output.** ETH Zurich study: too much context REDUCES
   task success and adds 20% inference cost. Ruthlessly prune CLAUDE.md.
2. **@imports load eagerly.** They are organizational only, NOT a token saving.
   Reference files via prose (`"see X.md"`) or use Skills.
3. **Skills are the real lazy loader.** Progressive disclosure: only name +
   description load at session start; body loads on trigger match.
4. **Hooks > rules.** CLAUDE.md is advisory (~70% followed). Hooks are 100%.
   Promote non-negotiables to hooks.
5. **Subagents isolate context.** Verbose exploration in a fresh window, only
   summary returns.
6. **Persistent graph > re-reading files.** Build graphify once; query forever.
7. **Trigger-action format.** "WHEN X, DO Y" beats general guidance (eval data).
8. **Order matters.** CLAUDE.md is read top-down; later sections summarized
   first under compaction. Put non-negotiables FIRST.
9. **Compound engineering loop.** Every correction → new rule. Stop hook
   proposes CLAUDE.md edits at session end.
10. **Cite file:line for every claim.** So future-Claude can verify.

## Quick start (existing project)

```bash
cd /path/to/your/repo
bash /u01/claude-init/scripts/init-project.sh existing
# Then open Claude Code and paste contents of /u01/claude-init/PROMPT.md
```

## License

Internal. Reuse freely across projects.
