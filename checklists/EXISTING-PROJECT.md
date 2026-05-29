# Checklist — Existing Project (Brownfield)

Use when adding Claude Code config to a repo that already has code.

## Fast path — `conjure adopt`

For most repos, one rollback-capable command does the brownfield onboarding:

```bash
conjure adopt --dry-run .   # inspect the 5-step plan (zero writes)
conjure adopt .             # snapshot → inventory → scaffold → audit → report
# Undo anytime: conjure adopt --rollback .   (sha256-verified restore)
```

It snapshots before mutating, scaffolds only missing harness layers (existing
files untouched), archives (never deletes) stale files, and installs a
human-gated `restructure` skill to condense an oversized `CLAUDE.md` through
pre-write safety gates. Refuses a dirty git tree — commit/stash first (or
`--force`). Then open Claude Code and run the `restructure` skill to approve the
CLAUDE.md condensation step-by-step. The manual steps below remain useful for
deep customization (knowledge graph, per-area skills).

## Pre-Claude (5-minute prep)

- [ ] Confirm clean working tree (`git status`) or stash. Claude shouldn't fight uncommitted work.
- [ ] Read your own README.md and skim recent `git log -20`. Refresh your own mental model first.
- [ ] Note any in-flight work, deprecations, or refactors — Claude needs to know what NOT to touch.
- [ ] Identify the 1-3 areas Claude will touch most (these become deep-dive skills).
- [ ] If you have an existing `CLAUDE.md` or `.cursorrules`, preserve it for reference; Claude can merge.

## Phase 0 — Knowledge Graph (highest leverage)

If ≥50 source files:
```bash
# install graphify if missing — see reference/TOOLS-CATALOG.md
graphify . --mode deep --wiki --mcp
```

Inspect:
- [ ] `graphify-out/GRAPH_REPORT.md` — does the community clustering match your mental model? If not, run `--cluster-only` with adjusted params.
- [ ] `graphify-out/wiki/` — these become drafts for skill bodies.
- [ ] Edges marked INFERRED — sanity check; these are graph's best guesses, not ground truth.

## With Claude (paste PROMPT.md with `[EXISTING]` invocation)

- [ ] Claude spawns parallel Explore agents (or uses graph output if Phase 0 ran).
- [ ] Review the file tree Claude proposes BEFORE accepting. Push back if it's bloated.
- [ ] Verify every skill description matches a real user trigger phrase.
- [ ] Walk through 3 realistic scenarios and confirm the right skill auto-loads.

## Hardening (after first scaffold)

- [ ] Add `.claudeignore` with: build outputs, lock files, large fixtures, generated code, vendor dirs.
- [ ] Migrate non-negotiables from CLAUDE.md → hooks (any rule violated even once becomes a hook).
- [ ] If pre-commit framework exists, ensure Claude hooks don't duplicate — orchestrate via one of them.
- [ ] Add a Stop hook for compound-engineering: append session corrections as candidate CLAUDE.md edits.
- [ ] If the repo has secrets-in-history risk, install `gitleaks` and wire into a PreToolUse hook on `git commit`.

## Monorepo specifics

- [ ] Add nested `<package>/CLAUDE.md` for each package with its own conventions. Keep each ≤50 lines.
- [ ] Per-package test/build commands belong in that package's CLAUDE.md, not root.
- [ ] If packages share a domain model, build ONE deep-dive skill at root that all packages reference.
- [ ] Consider `--filter` rules for dependency installs (PNPM/Turborepo monorepos): make it a CLAUDE.md non-negotiable.

## Validation

- [ ] `conjure audit .` passes (or `bash /u01/conjure/scripts/audit-setup.sh .`).
- [ ] Open a fresh Claude Code session. Ask: "What does this project do? How is it organized?" Confirm answer is accurate WITHOUT Claude having to read more than CLAUDE.md + 1 skill.
- [ ] Ask Claude a typical task ("add endpoint X" / "fix Y") and verify it loads only the relevant skill.

## Anti-patterns to avoid (existing project edition)

- ❌ Dumping the entire existing README into CLAUDE.md. README is for humans; CLAUDE.md is rules.
- ❌ Skipping graphify because "I know the codebase." You're a worse navigator after 6 months. Build the graph anyway.
- ❌ Auto-importing every doc with `@docs/X.md`. They load eagerly.
- ❌ One mega-skill called "this-codebase". Defeats progressive disclosure.
- ❌ Migrating all `.cursorrules` content verbatim. Most of it is now obsolete or duplicated by code conventions.
- ❌ Letting Claude commit the `.claude/` setup without you reading it line by line first.
