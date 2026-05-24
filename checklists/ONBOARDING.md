# Checklist — Onboard New Developer to a Claude-Configured Repo

For when a teammate joins a repo Claude Code has already been set up on.

## For the new developer

- [ ] `git clone` the repo.
- [ ] Run `cat CLAUDE.md` and read it top to bottom (≤100 lines, takes 2 min).
- [ ] `ls .claude/skills/` — list available skills; read descriptions only.
- [ ] `ls .claude/agents/` — list subagents.
- [ ] `cat .claude/settings.json` — understand hooks (these are mandatory behaviors).
- [ ] Read `README.md` (project intent) and `docs/ARCHITECTURE.md` (system shape).
- [ ] Read `docs/GLOSSARY.md` if present (domain terms).
- [ ] Skim `docs/adr/` (decisions and why).
- [ ] Open Claude Code in the repo. Ask: "Give me a 2-minute orientation tour of this project." Verify the answer matches what you just read.

## For the tech lead (handover)

- [ ] Confirm new dev has graphify installed (if project uses it).
- [ ] Confirm new dev has all MCP servers installed — share `reference/MCP-SERVERS.md` setup notes.
- [ ] Walk them through 1 typical task end-to-end so they see which skills fire.
- [ ] Point them at the compound-engineering Stop hook output — show them how corrections evolve into rules.

## Pairing-with-Claude orientation (5 min)

The four layers:
1. **CLAUDE.md** is loaded every session. Don't bloat it.
2. **Skills** auto-load on trigger. Don't read them in advance — let Claude pick.
3. **Agents** are spawned for big context-heavy tasks. Use the Task tool.
4. **Hooks** run automatically. They block bad actions. Don't fight them — fix the underlying issue.

## Quick orientation questions to ask Claude

In a fresh session, paste these and verify good answers:
- "What does this project do?"
- "Where is X defined?" (pick a real entity)
- "How do I add a new <feature-type>?"
- "What conventions should I follow when writing tests?"
- "What's the deploy process?"

If any answer is wrong/missing, that's a gap in the Claude config — open an issue.

## When you're ready to contribute

- [ ] Branch naming convention (check CLAUDE.md or CONTRIBUTING.md).
- [ ] Commit message format (Conventional Commits unless told otherwise).
- [ ] Run the lint/test commands listed in CLAUDE.md before pushing.
- [ ] Open a PR; the `diff-reviewer` agent (if configured) will pre-review.
- [ ] Don't commit anything in `.claude/` without code review — that's harness config.

## Red flags during onboarding (escalate)

- 🚩 CLAUDE.md > 150 lines → out of policy, ask lead to trim.
- 🚩 No `.claudeignore` → Claude may read massive build artifacts; flag it.
- 🚩 Hooks reference scripts that don't exist → broken setup.
- 🚩 Skills with vague descriptions ("helpers", "utils") → won't fire correctly.
- 🚩 No ARCHITECTURE.md or GLOSSARY.md in a domain-heavy repo → missing context.
- 🚩 graphify-out/ doesn't exist on a >50 file repo → missed leverage.
