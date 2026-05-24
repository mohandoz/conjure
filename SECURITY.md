# Security Policy

## Reporting

For security issues with Conjure itself, email <33397039+mohandoz@users.noreply.github.com>.
Do NOT file a public GitHub issue.

## Supply-chain trust

Conjure is a configuration kit — it does NOT execute remote code. However:

- It installs MCP servers (per `reference/MCP-SERVERS.md`) which DO execute.
- It writes shell-script hooks that run on Claude Code events.
- It can invoke `graphify`, `ast-grep`, `gitleaks` etc. when installed.

Trust boundary: you are running Conjure in your own environment. Treat its
scripts like any other shell scripts — read before running. We provide:

- `cli/conjure init --dry-run` to preview file writes.
- `cli/conjure audit` to verify the resulting state.
- Backup-before-mutate on every modification.

## Sandboxing recommendations

For high-stakes use:

- Use a read-only Postgres role for the Postgres MCP server.
- Use a repo-scoped GitHub PAT (not org-scoped) for the GitHub MCP server.
- Run firecrawl/web-fetch MCPs in a container with network egress controls.
- Pin MCP SDK versions; subscribe to the upstream advisory feed.
  (April 2026 OX Security disclosed systemic RCE in MCP SDKs.)

## Hook security

- Hooks run in the current shell with current user privileges.
- Read every hook script before activating.
- Test hooks with `--debug` in Claude Code before enabling in shared repos.

## Skill / agent content

Skills and agents are markdown that becomes part of the LLM's context. Treat
malicious skill content as a prompt-injection vector. Code review every PR
that adds/modifies skills.

## Known limitations

- Conjure does not validate skill content for prompt-injection patterns.
- Conjure does not enforce per-skill RBAC; any session that loads a skill
  loads its full instructions.
- The Stop hook's compound-engineering loop appends candidate text from the
  session — review before promoting to CLAUDE.md.

## Versioning + integrity

- Each release is git-tagged: `vMAJOR.MINOR.PATCH`.
- Recommended: pin a specific Conjure version per project via
  `.claude/.conjure-version`.
- For high-stakes orgs: maintain an internal fork with signed commits.

## Updates

`cli/conjure update --check` shows pending kit updates and a diff before
applying. NEVER run `conjure update --auto` in production repos without
review.
