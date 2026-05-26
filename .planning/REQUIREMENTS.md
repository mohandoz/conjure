# Requirements: Conjure v0.5.0 — Auto-Update + Healthcheck

**Goal:** Enable harnesses to stay current — detect drift from upstream, resolve
conflicts interactively, and automate updates via PR.

---

## v0.5.0 Requirements

### Drift Detection

- [ ] **DRIFT-01**: User can run `conjure check` to compare the installed harness
  against the upstream kit snapshot and see a file-level delta report (added /
  modified / removed files)
- [ ] **DRIFT-02**: `conjure check` exits 0 when harness is current and exits 1
  when drift is detected; supports `--porcelain` flag for machine-readable output
  in CI pipelines

### Auto-PR

- [ ] **AUTPR-01**: User can run `conjure update --pr` to push a harness-update
  branch and open a GitHub PR with the diff; command is idempotent (checks for an
  existing PR on the same branch before calling `gh pr create`)
- [ ] **AUTPR-02**: An optional `.github/workflows/conjure-update.yml` cron
  template ships (via `conjure init` or standalone) so teams can automate
  weekly drift checks and PR creation without manual intervention

### Conflict Resolution

- [ ] **RESOLVE-01**: User can run `conjure resolve` to interactively walk through
  all diff3 conflict sidecars; prompts `[k]eep / [a]pply / [e]dit / [s]kip` per
  file; command guards `[ -t 0 ]` and exits 2 (not 1) when run non-interactively
- [ ] **RESOLVE-02**: After user confirms each resolution, `conjure resolve` removes
  the resolved sidecar via `mutate_rm` (dry-run safe); when all sidecars are
  cleared it prints a "No conflicts remain" confirmation

### PowerShell / Windows

- [ ] **WIN-01**: `conjure.ps1` PowerShell shim (≤30 lines) locates Git Bash or
  WSL on Windows, delegates all subcommand arguments with `@args` passthrough,
  and propagates exit codes with `exit $LASTEXITCODE`; uses
  `$ErrorActionPreference = 'Continue'` so exit 2 is not swallowed
- [ ] **WIN-02**: CI matrix includes a `windows-latest` job with `shell: pwsh`
  that smoke-tests `conjure.ps1 --version` and confirms exit code propagation

### Tech Debt

- [ ] **DEBT-01**: `ci-gate` job in `release.yml` fails with an explicit error
  message when a tagged commit has zero GitHub check-runs (empty-check guard);
  includes a short retry loop to handle GitHub API propagation lag
- [x] **DEBT-02**: `conjure publish-skill` accepts a positional argument (`$2`)
  for the target `org/repo`; `TARGET_REPO` environment variable is kept as a
  deprecated fallback and emits a `WARN:` message when used

### Infrastructure (non-user-facing prerequisite)

- [x] **INFRA-01**: `lib/mutate.sh` gains a `mutate_rm` function (dry-run safe,
  consistent with existing `mutate_cp` / `mutate_write` primitives) required by
  RESOLVE-02

---

## Future Requirements

Requirements deferred to later milestones:

- Full TUI conflict resolution (side-by-side diff viewer) — v0.6.0
- `conjure check --json` structured JSON output — v0.5.x
- `conjure update --pr` auto-merge on clean apply — never (conflicts need human review)
- `conjure:full` Docker tag with optional Go/Rust tools — v0.4.x/v0.5.x
- `compatible-kit-version` manifest field in overlay — v0.4.x
- `conjure publish --dry-run` — deferred
- PowerShell `conjure.ps1` without Git Bash fallback (pure PS port) — v0.6.0

---

## Out of Scope

Explicit boundaries for this milestone:

- **No auto-merge:** `conjure update --pr` opens a PR; it never merges automatically. Conflicts always require human review.
- **No TUI:** `conjure resolve` uses a guided line-by-line prompt, not ncurses/curses.
- **No new runtime deps:** `dependencies: {}` stays empty. All features use gh CLI, diff, git, and pwsh — tools already in the preflight stack.
- **No PowerShell logic replication:** `conjure.ps1` is a shim only. No subcommand logic in PowerShell.
- **No real compliance:** Overlays reduce non-compliant output; actual compliance needs people + process.

---

## Traceability

*Filled by roadmapper — maps each REQ-ID to a phase.*

| REQ-ID     | Phase | Phase Name            |
|------------|-------|-----------------------|
| INFRA-01   | 16    | Prerequisites         |
| DEBT-02    | 16    | Prerequisites         |
| DRIFT-01   | 17    | Drift Detection       |
| DRIFT-02   | 17    | Drift Detection       |
| RESOLVE-01 | 18    | Conflict Resolution   |
| RESOLVE-02 | 18    | Conflict Resolution   |
| AUTPR-01   | 19    | Auto-PR               |
| AUTPR-02   | 19    | Auto-PR               |
| WIN-01     | 20    | Windows + CI Gate     |
| WIN-02     | 20    | Windows + CI Gate     |
| DEBT-01    | 20    | Windows + CI Gate     |
