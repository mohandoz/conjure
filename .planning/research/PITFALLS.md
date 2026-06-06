# Pitfalls Research

**Domain:** Operability + DX additions to an existing zero-dependency bash+Node CLI (Conjure v0.8.0)
**Researched:** 2026-06-04
**Confidence:** HIGH — all findings derived from direct codebase inspection, proven prior failures in PROJECT.md key-decisions table, and empirical jq/bash behaviour tests run against the live repo.

---

## Critical Pitfalls

### Pitfall 1: JSONL Parse Failure Silently Produces Wrong Stats

**What goes wrong:**
`conjure stats` (and the existing `--retire-list` logic) passes a JSONL file directly to `jq` line-by-line. jq exits 5 and prints a parse error on stderr as soon as it hits any malformed line — but partial output is already written to stdout. Scripts that only check exit code 0/non-zero will silently emit truncated or empty counts.

Confirmed with live test against the repo: a file containing one invalid line causes `jq` to exit 5 yet still emit results for valid prior lines. The retire-list uses `wc -l` on jq output; if jq bails early, `count=0` is reported for skills that actually fired — they will be incorrectly flagged `[retire?]`.

**Why it happens:**
- `appendFileSync` in `skill-telemetry.mjs` is not atomic. A partial write (Node crash, SIGKILL during `conjure workspace` saga, full disk) leaves a truncated last line.
- Blank comment lines, UTF-8 BOM at file head from some Windows editors, or a literal `undefined` written by an uncaught `.toISOString()` on a null date will silently corrupt the file.
- The current `jq -r 'select(...) | .skill' file` pipeline has no guard for non-zero exit.

**How to avoid:**
- Wrap all jq invocations against JSONL files in a per-line try-parse: `jq -R -r 'try (fromjson | select(.ts and .skill)) // empty'`. This drops malformed lines rather than aborting mid-stream.
- For `conjure stats`, always check jq exit code separately. If non-zero, emit a warning and a "repair" hint: `conjure stats --repair` could filter invalid lines into a `.bak` sidecar.
- Gate the stats output clearly: "parsed N / total M lines" so partial data is never silent.

**Warning signs:**
- `jq: parse error` appears in doctor/stats stderr but the command still exits 0 because the surrounding shell ignores the subprocess exit.
- `[retire?]` shows for a skill you know fired recently.
- `conjure stats` count is lower than `wc -l` on the raw JSONL.

**Phase to address:** The phase implementing `conjure stats`. Any JSONL-reading path must be hardened before the first consumer ships.

---

### Pitfall 2: Doctor Emits False Positives Across OS Environments

**What goes wrong:**
`conjure doctor` will reuse `scripts/preflight.sh` logic and the `_detect_os` + `_fixup` table. On macOS, `command -v` finds tools installed via Homebrew, pyenv-shims, or nvm, but those paths are only available in interactive login shells — not in the non-login, non-interactive subprocess that `conjure doctor` spawns. On CI or inside Docker (debian:bookworm-slim), brew paths are absent entirely, so a tool present in the user's interactive shell appears missing to doctor.

Concrete asymmetry already in the codebase: `rg` and `shellcheck` are "optional" in `preflight.sh` but required for CI quality gates. Doctor flagging them as missing on a developer machine that has them in a non-default PATH will create noise that trains users to ignore doctor output.

The Node version parse in `eval.sh` uses `${_node_ver%%.*}` integer arithmetic after `tr -d 'v'`. If `node --version` returns something unexpected (e.g., a manager shim that appends extra text like `"v20.20.0 (npm 10.x)"`), the arithmetic comparison silently evaluates to 0, failing the gate for a valid Node install.

On WSL2, `/mnt/c/...` Windows tools are in PATH via interop entries. `command -v node` may resolve to the Windows node.exe, which does not understand POSIX paths passed from the bash side. Doctor would report node as present but `conjure eval run` would silently fail.

**Why it happens:**
- `command -v` resolves against `$PATH` at subprocess invocation time, not the user's login environment.
- The existing `preflight.sh` uses `exit 1` for required-dep failure (line 109) — inconsistent with the project-wide `exit 2` convention. When doctor inherits or calls preflight, callers using `|| return 1` treat this correctly, but the exit code is wrong for the audit verdict gate.

**How to avoid:**
- After `command -v`, probe the tool's basic capability: `node --version >/dev/null 2>&1 || DOCTOR_NOTE "node found but unusable"`. A binary that exists but errors on `--version` should be treated as missing.
- For the Node version parse, strip everything after the first space before the `%%.*` split: `_node_ver="$(node --version 2>/dev/null | tr -d 'v' | cut -d' ' -f1)"`.
- On WSL2, warn when a resolved binary lives under `/mnt/c/`.
- Fix `preflight.sh:109` from `exit 1` to `exit 2` in the deferred-debt phase. All Conjure exits are `exit 2` — this is a known convention violation.

**Warning signs:**
- Doctor passes on developer machine but `conjure eval run` exits 2 with "node not found" on CI.
- Doctor reports tools missing in Docker despite them being installed in the image.
- Node version check says "unsupported" for a version the developer confirmed is 20.20+.

**Phase to address:** Doctor implementation phase. The `exit 1` violation in `preflight.sh` should be fixed in the deferred-debt phase that precedes it.

---

### Pitfall 3: Live LLM Eval in CI — Cost Bleed and Fork PR Blockage

**What goes wrong:**
`conjure eval run` shells out to `npx promptfoo@0.121.14 eval`. Every test case with `llm-rubric` hits the Anthropic API. At `repeat: 3` and one rubric block per CLAUDE.md rule line, a 50-line CLAUDE.md yields 50 rule assertions x 3 repeats = 150 API calls per CI run. With per-profile suite expansion (v0.8.0 goal), each new profile adds another promptfooconfig.yaml with its own rule set. Cost compounds multiplicatively: 9 profiles x 50 rules x 3 = 1,350 calls per PR.

The emitted workflow (`.github/workflows/conjure-eval.yml`) gates on `ANTHROPIC_API_KEY` being set in GitHub secrets. If the secret is absent (e.g., a fork PR), promptfoo exits with an error that the GitHub Action surfaces as a failed required check, blocking all fork contributor PRs.

**Why it happens:**
- `conjure eval --emit-workflow` emits the workflow as a required check (`on: pull_request`). There is no `if: github.event.pull_request.head.repo.full_name == github.repository` guard to skip fork PRs.
- `evaluateOptions.repeat: 3` is hardcoded in the generated config. Per-profile configs inherit this without a cost-budget safeguard.
- `FAIL_ON_THRESHOLD=80` is an integer (already correct for the promptfoo-action 0-100 scale), but the comments in `eval.sh` describe it as "0.8 fractional." A future refactor that misreads the comment and changes it to `0.8` would silently produce threshold=0 (everything passes).

**How to avoid:**
- Add a fork-PR guard to the emitted workflow: `if: github.event.pull_request.head.repo.full_name == github.repository || github.event_name != 'pull_request'`.
- For per-profile suite expansion, scope repeat down to 1 for structural (non-rubric) assertions. Add a `--budget-guard` flag to `eval init` that caps total assertion x repeat count and exits 2 if exceeded.
- Baseline regression tests should use `type: contains` or `type: not-contains` instead of `llm-rubric` wherever structural checks suffice (e.g., "CLAUDE.md was emitted with the correct stack profile header").

**Warning signs:**
- Monthly Anthropic API bill has a new line item that scales with PR count.
- Fork contributor PRs are all blocked by a required `Conjure Eval` check.
- `conjure eval run` exits 0 but the pass-rate report shows 100% pass for every assertion.

**Phase to address:** Eval suite expansion phase. The fork-PR guard must be added before per-profile configs ship.

---

### Pitfall 4: Init Wizard TTY Pitfalls — Silent Hang or Double-Prompt

**What goes wrong:**
The init UX polish goal adds a profile-selection wizard. The pattern for interactive prompts in this codebase is `read -r -p "..." choice` reading from stdin (fd 0), and the non-TTY guard is `[ -t 0 ] || exit 2`. Two failure modes appear when adding a wizard to an already-running conjure command:

1. **Double-fd-conflict**: `resolve.sh` already uses `exec 3< "$tmpfile"` and `read <&3` to free fd 0 for the prompt loop. If the wizard reads from fd 0 inside a `while IFS= read -r line` loop that is also consuming fd 0 (common when iterating a list passed via command substitution), the inner `read -r -p` will consume list lines as user input, silently advancing past prompts.

2. **CI silent hang**: If the TTY guard fires correctly and exits 2, but the caller in a CI wrapper does `conjure init 2>/dev/null` (suppressing stderr), the exit 2 message is invisible and the build appears to hang waiting for a prompt that will never arrive.

3. **`read` EOF under `set -e`**: On macOS system bash (3.2.57), `read -r` that hits EOF returns exit code 1 (not 2). Under `set -uo pipefail`, this unintentionally triggers `set -e` termination at the `read` line rather than reaching the explicit TTY guard. The correct pattern is to check `[ -t 0 ]` before ever calling `read`.

**Why it happens:**
- Interactive prompts interact poorly with `set -uo pipefail` because a `read` that hits EOF returns exit 1, which `set -e` turns into unexpected termination.
- The existing codebase avoids this by checking `[ -t 0 ]` first and calling `exit 2` before reaching any `read`. A wizard that defers the TTY check until after a profile-detection pass will hit the `read` EOF before the guard fires.

**How to avoid:**
- Establish the TTY guard as the FIRST statement of any function that will ever call `read -r -p`. Do not defer it past any other logic.
- Use `read -r choice </dev/tty` (reads from the terminal even when stdin is redirected) rather than reading from fd 0. This is the established pattern for interactive tools that must remain CI-safe.
- In tests, always use `< /dev/null` to simulate non-TTY and verify exit 2 before testing the interactive path with a PTY fixture.
- `read` returning non-zero from EOF must be caught explicitly: `read -r choice </dev/tty || { exit 2; }`.

**Warning signs:**
- `conjure init` hangs in CI without any output.
- Wizard skips past all profile prompts and picks a default, with no user input provided.
- `expect`-based test times out waiting for a prompt that was never printed.

**Phase to address:** Init UX polish phase.

---

### Pitfall 5: `warn()` in Doctor or Stats Flips Audit Exit 1 in CI

**What goes wrong:**
This pitfall is the most frequently re-triggered in this codebase (it caused a blocker in Phase 25 and was re-enforced through Phases 26-30). `audit-setup.sh` exits 1 when `WARN > 0` (line 694). Any advisory check in `conjure doctor` or `conjure stats` that calls `warn()` instead of `note()` will flip the audit exit from 0 to 1, breaking CI pipelines that treat exit 1 as failure.

The new risk in v0.8.0: `conjure doctor` will call `audit-setup.sh` (via `cmd_preflight`) or share its advisory infrastructure. If doctor adds new `warn()` calls for advisories (e.g., "telemetry file is 90 days old", "cc-schema.json approaching staleness", "no skills have fired in 60 days"), those propagate into the holistic audit exit code.

**Why it happens:**
- The three-severity model (`ok/warn/err`) maps intuitively: warn feels like "advisory, not blocking." But the exit-code gate at the bottom of `audit-setup.sh` makes `WARN > 0` → exit 1, which shells interpret as failure.
- `conjure doctor` is a new entry point that will likely reuse `audit-setup.sh`'s infrastructure. Any advisory emitted there must use `note()` (exit 0) or be behind a `--strict` flag.

**How to avoid:**
- For all new advisory checks in doctor/stats, default to `note()`. Reserve `warn()` only for checks that should be surfaced as exit 1 in strict mode, and gate them: `[ "${CONJURE_STRICT:-0}" = "1" ] && warn "..." || note "..."`.
- The decision rule already in PROJECT.md Key Decisions: "advisory checks use `note()`, real bugs use `err()`." Apply this to every new check in doctor without exception.
- Write a test assertion for every new advisory: `run_audit && assert_exit 0` — not just `assert_output_contains`.

**Warning signs:**
- `conjure audit` starts returning exit 1 in CI after a doctor phase lands.
- `conjure audit --json` shows `"status":"warn"` for checks that should be purely informational.
- New advisory check added, CI breaks, developer upgrades advisory to `note()` in a quick-fix commit.

**Phase to address:** Doctor implementation phase, before it shares any advisory infrastructure with `audit-setup.sh`.

---

### Pitfall 6: Live-Binary Smoke Tests That Require `claude` Binary Pollute CI

**What goes wrong:**
v0.8.0 defers 4 live-system HUMAN-UAT items from v0.7.0, including "real `claude` binary smoke" and "live promptfoo enforcement." If the automation strategy is to add these to `tests/run.sh` without a skip guard, they will fail on any CI runner that does not have `claude` installed, breaking the suite for all contributors.

The existing codebase handles this for `gh` (GitHub CLI) using `mk_path_without_gh` — a careful PATH manipulation that removes all `gh` directories. There is no equivalent for `claude`. A naive `if command -v claude >/dev/null 2>&1; then ...smoke...; fi` guard silently skips the test rather than recording a `SKIP` verdict, making coverage invisible.

**Why it happens:**
- The test suite uses a simple `PASS/FAIL` counter with no `SKIP` bucket. Adding optional tests that silently skip inflates apparent coverage without actually testing anything.
- `claude` binary availability is not a stable property of the repo's CI environment. Even if installed, it requires a valid API key and a working network, making it unsuitable as an unconditional CI check.

**How to avoid:**
- Add a `SKIP` counter to `tests/run.sh` alongside `PASS`/`FAIL`. Emit `skip()` when a required binary is absent and the test is marked optional.
- Gate live-binary smoke tests behind `CONJURE_LIVE_SMOKE=1`: `if [ "${CONJURE_LIVE_SMOKE:-0}" = "1" ]; then ...smoke...; else skip "live claude smoke (CONJURE_LIVE_SMOKE not set)"; fi`.
- Document the live UAT steps in `VERIFICATION.md` under a `manual_needed` block. This was the established pattern in Phases 25/26/28 and should be continued for v0.8.0.
- Never add `CONJURE_LIVE_SMOKE=1` to the default CI workflow. Reserve it for a separate `ci-live-smoke.yml` triggered manually or on release tags only.

**Warning signs:**
- `tests/run.sh` PASS count increases after a doctor/smoke phase but no new fixtures were added.
- A contributor opens a PR and CI fails with "claude: command not found."
- The smoke test passes locally because `claude` is installed, but `VERIFICATION.md` has no entry for the feature.

**Phase to address:** Deferred-debt automation phase (the first phase of v0.8.0).

---

### Pitfall 7: README Drift — Documenting Features That Don't Exist Yet or Omitting New Ones

**What goes wrong:**
The README refresh goal is to cover v0.3-v0.7. At v0.7.0 close, the command reference in the README still reflects the v0.2.0 surface. A README rewrite written at the start of v0.8.0 planning will document `conjure doctor` and `conjure stats` — which do not yet exist. If those phases slip or are descoped, the README ships with commands that error at runtime. Conversely, writing the README at the end of v0.8.0 risks missing the docs work if time pressure causes it to be deferred again.

**Why it happens:**
- Documentation phases are consistently the easiest to defer under schedule pressure.
- The README contains a command reference that duplicates `cli/conjure usage()`. When `usage()` is updated, the README is not auto-updated — they drift independently.
- MIGRATION-GUIDE.md and FAILURE-MODES.md are linked from README but were last updated at v0.1.0/v0.2.0.

**How to avoid:**
- Write the README in two passes: (a) a "current state" pass covering v0.3-v0.7 at the start of v0.8.0, before any new commands exist; (b) a "new commands" pass at the end of v0.8.0 after `conjure doctor` and `conjure stats` are proven.
- Add a README golden-file test: a grep check that every subcommand in `cli/conjure usage()` also appears in `README.md`. Failing the CI gate forces README updates when commands are added.
- MIGRATION-GUIDE.md and FAILURE-MODES.md should be updated in the same phase that introduces behavioral changes, not at milestone close.

**Warning signs:**
- README references `conjure doctor` before `scripts/doctor.sh` exists in the repo.
- `conjure help` output diverges from README examples.
- `FAILURE-MODES.md` still describes v0.2.0 audit behavior after the v0.7.0 audit overhaul.

**Phase to address:** A dedicated README phase at the start of v0.8.0 (v0.3-v0.7 coverage), with a second pass as the final phase (new command documentation).

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `exit 1` in preflight.sh (`scripts/preflight.sh:109`) | Conventional POSIX meaning | Breaks `cmd_preflight \|\| return 1` callers who treat any non-zero as fatal; inconsistent with all other Conjure exits | Never — fix in deferred-debt phase |
| `jq select(...)` directly on JSONL without sanitise pass | Shorter code | Silent truncation when any line is corrupt; wrong stats counts | Never for user-facing stats commands |
| `warn()` for advisory doctor checks | Matches intuitive severity model | Propagates into audit exit 1, breaks CI | Never — use `note()` for advisories |
| Per-profile eval config inheriting `repeat: 3` | Single-config simplicity | Cost scales O(profiles x rules x repeat) | Never without a cost-budget guard |
| `command -v` without capability probe for doctor checks | Simpler code | Counts a broken shim as "present"; false-positive on WSL2 Windows binaries | Acceptable for optional tools; never for required tools (node, jq) |
| Hardcoding `CUTOFF=$(date -v-30d ...)` with BSD-only fallback | Works on macOS | Fails silently on Alpine (no GNU date, no BSD date) | Never — always test all three date fallback paths including awk epoch arithmetic |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `jq` on JSONL (stats, retire-list) | `jq -r 'select(.field) \| .field' file` exits non-zero on any malformed line, partial output silently emitted | `jq -R -r 'try (fromjson \| select(.field)) // empty' file` — per-line try/catch, invalid lines dropped |
| promptfoo fork PRs | Workflow triggers unconditionally on `pull_request`, blocks fork PRs that have no secret | Add `if: github.event.pull_request.head.repo.full_name == github.repository` guard to eval workflow job |
| `node --version` parse in doctor | `${ver%%.*}` fails if version string has unexpected prefix/suffix from nvm shim output | `node --version 2>/dev/null \| tr -d 'v' \| cut -d' ' -f1` then `%%.*` |
| BSD date for CUTOFF calculation | `date -v-30d` is macOS-only; GNU `date -d` is Linux-only; neither works on Alpine | Three-way fallback: BSD then GNU then awk epoch arithmetic — test all three paths in CI fixture |
| `read -r -p` in wizard | Blocks forever when stdin is a pipe or `/dev/null` without early TTY guard | `[ -t 0 ] \|\| exit 2` as the FIRST line; then `read -r choice </dev/tty` not fd 0 |
| Telemetry JSONL concurrent append | `appendFileSync` is not atomic; concurrent Claude sessions write simultaneously | No locking needed for reads (stats tolerates duplicate/corrupt lines via try-parse); document that JSONL is best-effort |
| `conjure doctor` advisory checks | New doctor checks call `warn()` thinking it is advisory | All new checks call `note()` unless they are deliberate CI blockers; `warn()` is reserved for `--strict` mode |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Full JSONL scan for every `conjure stats` invocation | Stats command takes seconds on a repo with years of telemetry (many thousands of lines) | Pre-filter to last N days with `awk` before piping to `jq`; document growth expectation in TELEMETRY.md | Noticeable lag starts around 100k lines (~1 MB) |
| `find ... -name SKILL.md` per skill in retire-list (current code does this once correctly; future refactor risk) | Retire-list slow on repos with many skills | Build skill list once into a temp array, then iterate; do not nest find inside a loop | Not a current problem; watch if skill count grows past 100 |
| `npx --yes promptfoo@0.121.14 eval` cold-start per CI run | 5-10 second npx cache miss penalty on first run | Cache `~/.npm` and `~/.cache/promptfoo` in CI (already in emitted workflow); do not skip the cache step when adding per-profile configs | On cold runners with no cache |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Doctor emitting install hints that include `curl \| sh` patterns | Undermines the project's explicit "no curl\|sh foot-guns" constraint | All install hints must reference package managers only (brew, apt, winget); never emit a curl pipeline |
| Stats parsing a JSONL file that a user could have tampered with, interpolating jq output into shell | Command injection via crafted field values passed through `$()` to a shell command | Never interpolate jq output directly into a shell command; assign to a variable and treat as data |
| `conjure doctor` running as root in Docker to inspect system binaries | Unintended side effects if doctor triggers binary execution | Doctor must be read-only: `command -v` and `--version` probes only; never execute a binary in a way that has side effects |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| `conjure doctor` auto-injected before every command (current pattern: `cmd_preflight` runs in `cmd_init`, `cmd_audit`, `cmd_adopt`) | Doctor output scrolls past and users tune it out | Doctor should be a standalone command, not auto-injected. Preflight stays as the minimal dep check; doctor is the deep diagnostic run on request |
| Stats showing "0 fires" for a skill that was installed after the telemetry window | User incorrectly retires a new skill | Show skill install date alongside fire count if determinable; annotate skills installed within the cutoff window |
| Init wizard asking for profile before explaining what a profile is | New users answer randomly, get wrong scaffold | Present a one-line description for each profile option in the wizard prompt; offer `--profile=?` to list profiles before committing |
| `conjure stats` with no telemetry file printing nothing | User thinks command worked; has no idea telemetry is disabled | Always emit a clear status even when JSONL is absent: "Telemetry not enabled. Add CONJURE_TELEMETRY=1 to .claude/settings.json env block to start collecting data." |

---

## "Looks Done But Isn't" Checklist

- [ ] **`conjure doctor`:** Often missing a non-TTY path test — verify `conjure doctor < /dev/null` exits 0 (doctor should be non-interactive) or exits 2 (if any interactive element exists).
- [ ] **`conjure stats` JSONL parsing:** Often missing a corrupt-line test — verify that a JSONL file with one malformed line still returns correct counts for valid lines (not 0, not error exit).
- [ ] **Per-profile eval configs:** Often missing a cost-budget guard — verify total assertion count (rules x skills x repeat) is bounded before adding a new profile.
- [ ] **Emitted eval workflow:** Often missing a fork-PR guard — verify that a PR from a fork without `ANTHROPIC_API_KEY` does not block the PR with a required check failure.
- [ ] **README command reference:** Often missing parity with `cli/conjure usage()` — verify every subcommand in usage() appears in README with a correct example.
- [ ] **Live-binary smoke tests:** Often missing a `SKIP` verdict — verify that tests guarded by `CONJURE_LIVE_SMOKE=1` emit a `skip()` call (not a silent skip) and appear in the test summary.
- [ ] **`conjure doctor` exit codes:** Often exits 1 for missing optional deps (inherited from `preflight.sh:109` violation) — verify exit code is 2 for required-dep failures, 0 for optional-only advisories.
- [ ] **BSD/GNU date in stats CUTOFF:** Often only tested on macOS — verify the fallback chain produces a valid ISO8601 timestamp on Alpine Linux (no GNU date, no BSD date).

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| JSONL corruption from partial write | LOW | Add `conjure stats --repair` that filters invalid lines into `.bak` sidecar, rewrites clean file; document in FAILURE-MODES.md |
| Doctor false-positives from PATH asymmetry | LOW | Add `--path` flag to doctor to specify which PATH to probe; document CI invocation pattern |
| Eval cost bleed from per-profile configs | MEDIUM | Add `--dry-run` to `conjure eval run` that counts assertions x repeat without making API calls; gate per-profile configs behind `--profile` flag to eval init |
| Fork PR blocked by required eval check | LOW | Edit the emitted workflow to add the fork guard; re-emit with `conjure eval --emit-workflow`; commit |
| `warn()` in new doctor check breaks CI | LOW | Change `warn()` to `note()` in the offending check; no other changes required |
| README documents non-existent commands | LOW | Remove the undocumented-command section; add the CI grep gate to prevent recurrence |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| JSONL parse fragility | Stats implementation phase | Test: JSONL with one corrupt line yields correct counts for valid lines; test: truncated last line handled gracefully |
| Doctor false-positives across OSes | Doctor implementation phase | Test: `doctor` in Docker debian:bookworm-slim with all tools present; test: doctor on WSL2 with Windows node shim |
| Live LLM eval cost bleed | Eval suite expansion phase | Test: `--dry-run` assertion count gate; test: fork PR workflow does not trigger with missing secret |
| Wizard TTY pitfalls | Init UX polish phase | Test: `conjure init < /dev/null` exits 2 if interactive; PTY test for interactive path using expect fixture |
| `warn()` flip in doctor/stats | Doctor implementation phase (before any new advisory check) | CI assertion: `conjure audit` exits 0 after doctor phase lands with no new WARN increments |
| Live-binary smoke in CI | Deferred-debt phase | Verify `SKIP` counter exists in run.sh; verify no `claude` binary calls without `CONJURE_LIVE_SMOKE=1` guard |
| README drift | Two-pass docs phase (first pass at milestone start; second as final phase) | CI grep gate: every `conjure <sub>` in usage() appears in README.md |
| `exit 1` in preflight.sh | Deferred-debt phase (first phase of v0.8.0) | shellcheck / grep gate: `grep -rn 'exit 1' scripts/ lib/` returns only documented intentional exceptions |

---

## Sources

- Direct codebase inspection: `scripts/audit-setup.sh`, `scripts/eval.sh`, `scripts/preflight.sh`, `scripts/resolve.sh`, `templates/hooks-nodejs/skill-telemetry.mjs`, `cli/conjure`, `lib/log.sh`
- Live empirical tests run against the repo: jq JSONL parse behaviour on corrupt lines (confirmed exit 5 with partial stdout output), jq truncated last line (confirmed exit 5), BSD vs GNU date incompatibility on macOS (GNU `date -d` fails; BSD `date -v` succeeds)
- `.planning/PROJECT.md` Key Decisions table: `warn()` flips CI (Phase 25 enforcement), EXIT-trap clobbers (Phase 27), YAML-injection (Phase 28), argv-over-env (Phase 29), `git -C "$VAR"` empty-var (deferred tech debt)
- `.planning/STATE.md` deferred items: `git -C "$VAR"` empty-var guard, HUMAN-UAT gaps (Phases 25/26/28 carried into v0.8.0)
- Existing retire-list code in `audit-setup.sh` lines 631-680: confirmed the CUTOFF uses BSD-first date chain; confirmed the `wc -l` on jq output is the fragile point

---
*Pitfalls research for: v0.8.0 "Operability + DX" — doctor, stats, eval expansion, init wizard, live smoke, README*
*Researched: 2026-06-04*
