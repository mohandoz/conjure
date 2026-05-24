# Stack Profiles

Each profile is an overlay applied AFTER base `conjure init`. Profiles add:

- Stack-specific CLAUDE.md rules
- Stack-specific skill bodies (replace template scaffolds with concrete content)
- Stack-specific hook scripts (formatters, linters, test commands)
- Recommended MCP server suggestions
- Pre-flight checks for stack tools

## Available profiles

| Profile | Stack | Test runner | Format | Lint |
| --- | --- | --- | --- | --- |
| `java-spring` | Java 17+ / Spring Boot / Gradle | `./gradlew test` | google-java-format | checkstyle, spotbugs |
| `python-fastapi` | Python 3.11+ / FastAPI / uv | `pytest` | `ruff format` | `ruff check`, `mypy` |
| `ts-next` | TypeScript / Next.js 15+ / pnpm | `pnpm test` (vitest) | prettier | eslint, tsc |
| `rust-axum` | Rust / Axum / cargo | `cargo nextest` | rustfmt | clippy, cargo-deny |
| `go-gin` | Go / Gin / go modules | `go test ./...` | gofmt | golangci-lint |
| `node-nest` | Node / NestJS / pnpm | jest | prettier | eslint |
| `monorepo` | Turborepo / Nx / pnpm workspaces | per-package | per-package | per-package |
| `polyglot` | mixed stacks | Make/Just | per-language | per-language |
| `data-science` | Python / Jupyter / dbt | pytest + nbval | ruff + nbqa | ruff + nbqa |

## Anatomy of a profile

```
profiles/<stack>/
  README.md            ← what this profile assumes
  apply.sh             ← idempotent overlay script
  CLAUDE.md.fragment   ← lines to append to CLAUDE.md
  skills/<name>/SKILL.md  ← skill overrides (replace template scaffolds)
  hooks/<name>.sh      ← hook overrides
  mcp-recommended.json ← recommended MCP servers
  preflight.sh         ← stack-tool checks (mvn? cargo? pnpm?)
```

## Adding a new profile

1. Copy `profiles/_template/` to `profiles/<name>/`.
2. Fill in stack-specific content.
3. Add row to table above.
4. Add a fixture under `tests/fixtures/<name>-<sample>/` and an assertion in
   `tests/run.sh`.
5. CHANGELOG entry.

## Applying

```bash
conjure init existing --profile=python-fastapi /path/to/repo
# Or apply to a Conjure-initialized project:
bash /u01/conjure/profiles/python-fastapi/apply.sh /path/to/repo
```
