# Compaction — Surviving Context Compression

When the context window fills up, Claude Code compacts: older tool outputs
clear first, then conversation history summarizes. Some things survive,
some don't. Plan accordingly.

## Survival matrix

| Artifact | Survives `/compact`? | Notes |
| --- | --- | --- |
| Root `CLAUDE.md` | YES | Re-injected from disk after compaction |
| Nested `<dir>/CLAUDE.md` | NO | Reloads only when next file in that dir is read |
| Skill bodies (last invoked) | PARTIAL | First 5k tokens kept; total skill budget = 25k |
| Skill bodies (older invocations) | NO | Dropped if total exceeds budget |
| Subagent reports | YES | Already summarized; counted as conversation |
| Tool outputs (Read/Bash/Grep) | NO | Cleared first |
| Conversation messages | SUMMARIZED | Lossy compression |
| In-conversation user rules | NO | Lost unless promoted to CLAUDE.md |
| `.claude/settings.json` (hooks) | N/A | Always available — they're not in context |

## Strategy

1. **Critical rules MUST live in root CLAUDE.md, at the TOP.**
   They re-inject after compaction. Buried rules summarize away.
2. **Frequently invoked skills survive better** than rarely used ones —
   the budget fills from most-recent-first.
3. **Use `/clear` instead of `/compact`** for unrelated new tasks. Compaction
   is opaque and lossy; `/clear` is clean.
4. **Custom "catchup" command**: after `/clear`, run a custom command that
   makes Claude read the files changed in your current git branch. Faster
   re-orientation than reading everything.
5. **Promote conversation rules to disk.** If you tell Claude "always do X"
   in conversation, that rule dies at compaction. Add it to CLAUDE.md or
   a skill.
6. **Subagents preserve context.** Long research → spawn a subagent. Only
   the summary returns; main conversation budget intact.

## Custom compaction directive in CLAUDE.md

You can guide what Claude prioritizes during compaction:

```markdown
## On compaction

When compacting this conversation, ALWAYS preserve:
- The list of files modified in this session.
- Any test commands used.
- Any decisions made (with rationale).
Drop tool outputs but keep my corrections.
```

## Watch for compaction warnings

Claude Code surfaces context-usage warnings (~70%, ~90%). At 70%, decide:
- Continue → likely hit auto-compact mid-task.
- `/clear` and re-prime with a tight prompt.
- Spawn subagent for the next verbose step.

## Sources

- [How Claude remembers your project — Anthropic Docs](https://code.claude.com/docs/en/memory)
- [Claude Code Best Practices 2026 — The Prompt Shelf](https://thepromptshelf.dev/blog/claude-code-best-practices-2026/)
