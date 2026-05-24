# Tools Catalog — Companions for Claude Code

The right CLI/MCP/skill tools amplify Claude Code dramatically. Install what
matches your work; skip the rest.

## Tier 1 — install for almost any project

| Tool | What it does | Install |
| --- | --- | --- |
| **ripgrep / ugrep** | Fast text search (Claude Code uses ugrep on macOS/Linux internally) | `brew install ripgrep ugrep` |
| **fd** | Faster, friendlier `find` | `brew install fd` |
| **jq** | JSON query/transform | `brew install jq` |
| **gh** | GitHub CLI — PRs, issues, releases, Actions | `brew install gh` |
| **gitleaks** | Secret scanner | `brew install gitleaks` |
| **bat** | `cat` with line numbers + syntax highlighting | `brew install bat` |
| **delta** | Better git diff viewer | `brew install git-delta` |

## Tier 2 — code understanding tools (highest leverage for AI agents)

| Tool | What it does | Why it matters |
| --- | --- | --- |
| **ast-grep** | Structural search/rewrite via tree-sitter AST | Finds patterns regex can't (e.g. "all async functions without try/catch") |
| **repomix** | Pack entire repo into AI-friendly file (+70% compression w/ tree-sitter) | Full-codebase context for external LLMs or audits |
| **graphify** | Build persistent knowledge graph w/ community detection | Cross-document surprise + survives sessions; query via CLI or MCP |
| **universal-ctags** | Symbol index | Fast `file:line` lookup; some IDEs use it |
| **difftastic** | Structural diff (AST-aware) | Cleaner review of AI-generated diffs (no whitespace noise) |
| **comby** | Cross-language structural search/replace (no parser needed) | Complement ast-grep for less common langs |
| **hyperfine** | CLI benchmarking with statistics | When asking Claude to "optimize X", get real numbers |
| **shellcheck** | Shell-script linter | AI generates lots of shell; this catches `rm -rf $UNSET/` style bugs |

## Tier 3 — pre-commit / lint orchestration

| Tool | Stack | Notes |
| --- | --- | --- |
| **pre-commit** (framework) | Generic | YAML-driven, supports many hooks |
| **lefthook** | Generic | Fast, no Python dep |
| **husky + lint-staged** | Node | Industry default for JS/TS |
| **rusty-hook / cargo-husky** | Rust | |
| **direnv** | Generic | Auto-load `.envrc` per directory |
| **mise / asdf** | Generic | Runtime version pinning (`.tool-versions`) |

## Tier 4 — domain-specific

### Python
| Tool | Replaces | Notes |
| --- | --- | --- |
| **uv** | pip + venv + pip-tools | Astral's fast everything-tool |
| **ruff** | flake8 + isort + black | Same author; fast |
| **mypy** / **pyright** | type checker | Pyright is faster |
| **pytest + hypothesis** | unittest | Property-based testing |
| **pip-audit** | safety | CVE check |

### TypeScript / Node
| Tool | Notes |
| --- | --- |
| **tsc --noEmit** | Type check only |
| **eslint + prettier** | Standard |
| **vitest** | Faster jest replacement |
| **type-coverage** | Track `any` regressions |
| **npm audit** / **pnpm audit** | CVE check |

### Java / JVM
| Tool | Notes |
| --- | --- |
| **gradle / maven** | Build |
| **checkstyle / spotbugs** | Linting |
| **jacoco** | Coverage |
| **dependency-check** | CVE scan |
| **sonarqube** | Aggregate quality |

### Go
| Tool | Notes |
| --- | --- |
| **gofmt / goimports** | Format |
| **golangci-lint** | Lint aggregator |
| **govulncheck** | CVE scan |
| **go test -race** | Race detector |

### Rust
| Tool | Notes |
| --- | --- |
| **rustfmt** | Format |
| **clippy** | Lint |
| **cargo-audit** | CVE scan |
| **cargo-deny** | License/dep policy |
| **cargo-nextest** | Faster test runner |

## Tier 5 — agent orchestration extras

| Tool | Notes |
| --- | --- |
| **claude-mem** | Persistent cross-session memory (already in this env) |
| **semgrep** | Pattern-based static analysis with security rule packs |
| **trivy** | Container + filesystem CVE scan |
| **syft** | SBOM generation |
| **grype** | Vulnerability scanner |

## Anti-pattern

❌ Installing every tool "just in case". Each MCP server consumes context.
Each CLI you don't use is noise. Pick ≤6 MCP servers, ≤10 CLIs that fit
your workflow. Audit yearly; retire what didn't fire.

## Sources

- [Supercharging Claude Code with the right tools — batsov.com](https://batsov.com/articles/2026/02/17/supercharging-claude-code-with-the-right-tools/)
- [Repomix on GitHub](https://github.com/yamadashy/repomix)
- [ast-grep docs](https://ast-grep.github.io/)
- [grep, ripgrep, and AI-powered text search — ceaksan.com](https://ceaksan.com/en/grep-ripgrep-and-text-search-in-the-age-of-ai)
