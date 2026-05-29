# How Conjure Compares

Honest comparison to other Claude Code scaffolding / plugin tools. Last
updated: 2026-05-24.

## TL;DR

| Tool | Best for | Conjure differs by |
| --- | --- | --- |
| **awesome-claude-code-toolkit** (rohitg00) | Browsing 100+ agents, skills, hooks | Curated kit, not a catalog |
| **claude-code-plugin-template** (ivan-magda) | Authoring marketplace plugins | Project-level harness, not plugin-author tooling |
| **TemplateClaw** | UI/dashboard scaffolding templates | Whole-project harness, not UI templates |
| **oh-my-zsh-style framework** | Bundled commands + 6-layer security | Smaller, opinionated; integrates graphify + ast-grep |
| **idea-factory** | 7-agent startup-team autonomous MVP | Foundation kit, not autonomous loop |
| **ralph loop / wiggum** | Long-running autonomous coding sessions | Conjure sets up the harness Ralph runs on |
| **CCHub** | Desktop UI for managing harness | Conjure is the harness CCHub would manage |
| **Manual `.claude/`** | Total control | Conjure is opinionated guard-rails |

## Detailed comparison

### vs. awesome-claude-code-toolkit
- **They**: massive directory (135 agents, 35 skills, 42 commands).
- **We**: focused 17 skills + 6 agents + 5 hooks, all validated against eval-data sizing rules.
- **When to use them**: shopping for a specific skill not in Conjure.
- **When to use us**: setting up a project that needs the four-layer harness done right.

### vs. claude-code-plugin-template
- **They**: scaffold for publishing your own plugin marketplace.
- **We**: scaffold for harness inside an actual project.
- **Overlap**: both ship `.claude-plugin/` manifests.
- **When to use them**: you're building plugins to distribute.
- **When to use us**: you're building software (and want Claude to help reliably).

### vs. TemplateClaw
- **They**: 32 UI / dashboard / refactoring templates as Claude Code Plugin.
- **We**: project-level configuration kit; templates are CLAUDE.md / skills / hooks, not UI components.
- **Complement**: use TemplateClaw for UI scaffolding inside a Conjure-managed project.

### vs. Manual `.claude/`
- **Manual**: total flexibility, total responsibility.
- **Conjure**: opinionated defaults backed by Anthropic + community eval data; backup-before-mutate on every change; size caps enforced; cross-platform Node.js hooks; safe migration from other tools; one-command brownfield adoption (`conjure adopt`) with full snapshot + sha256-verified rollback.
- **Trade-off**: manual is faster *for the first project*. Conjure pays back at scale (multiple projects, team handoffs, kit updates).

### vs. CursorRules → CLAUDE.md by hand
- **By hand**: 20 minutes, error-prone, loses original intent.
- **Conjure**: `conjure migrate from-cursor` → automatic backup + draft + report; original preserved as comments; rollback trivial.

## What Conjure does NOT do (yet)

| Feature | Owned by | Plan |
| --- | --- | --- |
| Autonomous loop (Ralph-style) | ralph-loop | Document as integration in v0.4 |
| Desktop UI | CCHub | Out of scope; integrate via Plugin API |
| Token-efficient tool replacement | ashlr-plugin | Recommend installing alongside |
| Browser automation | Chrome DevTools MCP | Recommend in MCP-SERVERS.md |
| Sandboxed subprocess outputs | context-mode | Recommend alongside |
| 7-agent startup team | idea-factory | Out of scope; complementary |

## When NOT to use Conjure

- Your project is <10 files and you'll touch it once. Just write a 30-line CLAUDE.md.
- You're a plugin author distributing to marketplace. Use `claude-code-plugin-template` instead.
- You want a GUI. Use CCHub.
- You want autonomous multi-hour sessions. Use ralph-loop on top of Conjure.

## Why pick Conjure

- Backup-before-mutate everywhere — no destructive surprises.
- Size caps enforced by audit (`CLAUDE.md ≤100`, `SKILL.md ≤200`, etc).
- Cross-platform hooks (bash + Node.js parallel sets).
- Safe migration from Cursor/Aider/Continue/Copilot/Windsurf/existing `.claude/`.
- 9 stack profiles + 4 compliance overlays.
- 112 self-tests; CI on every PR.
- Compound-engineering loop built in (Stop hook).
- graphify + context7 + ast-grep + repomix + Postgres-MCP first-class.
- People-lives-depend-on-it design choices: read every script before running, no `curl ... | sh` foot-guns hardcoded.
