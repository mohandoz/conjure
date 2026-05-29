#!/usr/bin/env bash
# init-project.sh — bootstrap Claude Code config in target repo.
# Usage: bash init-project.sh [new|existing] [target-dir]
#
# Copies kit templates into <target>/.claude/ and seeds standard docs.
# Does NOT write CLAUDE.md content — you do that with Claude after pasting PROMPT.md.

set -euo pipefail

MODE="${1:-existing}"
TARGET="${2:-$(pwd)}"
KIT="$(cd "$(dirname "$0")/.." && pwd)"
source "$KIT/lib/mutate.sh"

if [[ "$MODE" != "new" && "$MODE" != "existing" ]]; then
  echo "Usage: $0 [new|existing] [target-dir]"
  exit 2
fi

cd "$TARGET"

echo "→ Initializing Claude Code config in: $TARGET (mode: $MODE)"
echo "→ Using kit at: $KIT"

# 1. Create .claude/ skeleton
mutate_mkdir ".claude/skills"
mutate_mkdir ".claude/agents"
mutate_mkdir ".claude/hooks"
mutate_mkdir ".claude/docs"

# 2. Copy core templates
for f in .editorconfig .gitattributes .claudeignore; do
  if [ ! -f "$f" ]; then
    mutate_cp "$KIT/templates/$f" "$f"
    echo "  ✓ created $f"
  else
    echo "  • $f exists — skipping"
  fi
done

# 3. Copy settings.json template
if [ ! -f .claude/settings.json ]; then
  mutate_cp "$KIT/templates/settings.json.tmpl" ".claude/settings.json"
  echo "  ✓ created .claude/settings.json"
else
  echo "  • .claude/settings.json exists — skipping"
fi

# 4. Copy hooks (node .mjs — works on all platforms including Windows)
for hook in "$KIT"/templates/hooks-nodejs/*.mjs; do
  name=$(basename "$hook")
  if [ ! -f ".claude/hooks/$name" ]; then
    mutate_cp "$hook" ".claude/hooks/$name"
    echo "  ✓ created .claude/hooks/$name"
  fi
done

# 5. Copy tooling skills (graphify-wrappers, MCP-wrappers)
for skill in code-graph docs-lookup web-research ast-search repo-pack sql-explorer restructure _anatomy; do
  if [ ! -d ".claude/skills/$skill" ]; then
    mutate_cp "$KIT/templates/skills/$skill" ".claude/skills/$skill"
    echo "  ✓ created .claude/skills/$skill/"
  fi
done

# 6. Copy project-skill TEMPLATES (Claude will fill these in)
for skill in architecture domain-model api-routes data-access messaging database-schema build-deploy testing debugging pr-review security-review release; do
  if [ ! -d ".claude/skills/$skill" ]; then
    mutate_cp "$KIT/templates/skills/$skill" ".claude/skills/$skill"
    echo "  ✓ created .claude/skills/$skill/ (TEMPLATE — Claude will fill in)"
  fi
done

# 7. Copy agent definitions
for agent in code-explorer.md test-writer.md migration-writer.md security-auditor.md doc-writer.md diff-reviewer.md; do
  if [ ! -f ".claude/agents/$agent" ]; then
    mutate_cp "$KIT/templates/agents/$agent" ".claude/agents/$agent"
    echo "  ✓ created .claude/agents/$agent"
  fi
done

# 8. Standard docs (only if missing)
mutate_mkdir "docs/adr"
for doc in ARCHITECTURE GLOSSARY RUNBOOK; do
  if [ ! -f "docs/$doc.md" ]; then
    mutate_cp "$KIT/templates/docs/$doc.md.tmpl" "docs/$doc.md"
    echo "  ✓ created docs/$doc.md (TEMPLATE)"
  fi
done

if [ ! -f docs/adr/0001-record-architecture-decisions.md ]; then
  mutate_cp "$KIT/templates/docs/ADR-TEMPLATE.md" "docs/adr/0001-record-architecture-decisions.md"
  echo "  ✓ created docs/adr/0001-*.md (TEMPLATE)"
fi

# 9. .env.example if missing
if [ ! -f .env.example ]; then
  ENV_CONTENT='# .env.example — every env var, with placeholder values.
# Real .env is gitignored.
#
# Add each new env var here when the code references one.

# Database
# DATABASE_URL=postgresql://user:pass@localhost:5432/dbname

# External services
# REASONER_BASE_URL=http://localhost:9009

# Secrets (placeholder values only)
# API_KEY=changeme'
  mutate_write ".env.example" "$ENV_CONTENT"
  echo "  ✓ created .env.example"
fi

# 10. Empty COMPOUND-CANDIDATES for the Stop hook to append into
if [ ! -f .claude/COMPOUND-CANDIDATES.md ]; then
  mutate_write ".claude/COMPOUND-CANDIDATES.md" "# Compound Engineering — Candidate Rules from Sessions"
fi

mutate_summary

# 11. Print next steps
cat <<EOF

═══════════════════════════════════════════════════════════════════════════
✅ Scaffold complete.

Next steps:
  1. Open Claude Code in this directory.
  2. Paste the contents of: $KIT/PROMPT.md
  3. Use INVOCATION line: [$( [ "$MODE" = new ] && echo NEW || echo EXISTING )]
  4. Claude will fill in CLAUDE.md and the project-skill templates from
     discovery (existing) or from your answers to its questions (new).
  5. Audit afterward: bash $KIT/scripts/audit-setup.sh
═══════════════════════════════════════════════════════════════════════════
EOF
