# Phase 24: Integration Tests + Argus Fixture - Research

**Researched:** 2026-05-29
**Domain:** End-to-end verification of the shipped `conjure adopt` + restructure-skill pipeline (Phases 21–23) against a representative 500-file brownfield fixture, with CI-asserted safety invariants + a <30s perf bound. POSIX bash test harness (`tests/run.sh`), no product features.
**Confidence:** HIGH — every claim below was verified by reading the live source (`scripts/adopt.sh`, `lib/inventory.sh`, `tests/run.sh`, the Phase 23 gates) and by empirically running the pipeline this session. No training-data assumptions about library behavior were used.

## Summary

Phase 24 is a pure-verification phase. The pipeline it tests already ships and the full suite is green (PASS 429/0). The deliverable is (1) a `_brownfield-argus` fixture and (2) a new `▸ Phase 24` block in `tests/run.sh` asserting the five ROADMAP success criteria. CI requires **zero workflow changes** — `.github/workflows/ci.yml` already runs `bash tests/run.sh` on the OS matrix, so any new `▸ Phase 24` assertions execute everywhere automatically.

Four of the five criteria map directly onto idioms already battle-tested in the `▸ Phase 22` block (dry-run zero-writes, rollback zero-diff via per-file sha256 + `diff -r` with excludes, SIGKILL background-launch + bounded-poll + `kill -9`, the `_`-prefix fixture convention). The symlink-skip and @import-block behaviors (criterion 5) are **already-correct shipped behavior** — I verified both empirically this session; the tests *prove* them, they don't drive new source code.

There is **one source gap** the plan must decide on. ROADMAP criterion 3 says the idempotent re-run must report the literal string **"nothing to scaffold"**, but the shipped `report()` in `scripts/adopt.sh` prints `Scaffolded: 0 layer files` on a second run — the exact phrase "nothing to scaffold" appears **nowhere in the codebase**. The plan must either (a) assert the satisfiable already-true signal (`Scaffolded: 0 layer files` + zero mutations), or (b) make a small one-line source deviation in `report()` to emit "nothing to scaffold" when `created_count == 0`. This is the only judgment call in the phase.

**Primary recommendation:** Add a single `▸ Phase 24` block to `tests/run.sh` that materializes `_brownfield-argus` at test time via a generator script (repo-lean), using a `date +%s` delta with a 30s hard ceiling for perf, the Phase 22 `state.json current_step`-aware SIGKILL window for criterion 4, and a `diff -r` zero-diff comparison with the D-03 excludes. For criterion 3, assert `Scaffolded: 0 layer files` AND make the tiny `report()` deviation so the literal ROADMAP phrase "nothing to scaffold" is also true — both, so the criterion text and the test agree.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| 500-file fixture generation | Test harness (generator script under `tests/fixtures/_brownfield-argus/`) | — | Committing 500 files bloats the repo; the existing `brownfield-simple/generate-large.sh` precedent materializes files into a sandbox at test time. Repo-lean per project size-discipline ethos. |
| E2E assertions (5 criteria) | `tests/run.sh` `▸ Phase 24` block | `tests/lib/sandbox.sh` | Project standard (STACK.md: extend `run.sh`; `bats-core` unit-only). Mirror `▸ Phase 22/23` idioms. |
| Pipeline under test (adopt/rollback/recovery) | `scripts/adopt.sh` + `lib/*` (SHIPPED — unchanged) | `cli/conjure cmd_adopt` | Not this phase to modify; tests verify it. Exception: the optional criterion-3 `report()` deviation. |
| Symlink skip | `lib/inventory.sh` (SHIPPED — verified correct) | — | Two-layer skip (classify `[ -L ]` + scan `[ -L ]`); criterion 5 asserts, does not build. |
| @import pre-write block | `templates/skills/restructure/gates/audit-staged.sh` (SHIPPED) | `scripts/audit-setup.sh` | Gate exits 2 on `^@`; criterion 5 asserts the block + the never-written invariant. |
| Perf measurement (<30s) | `tests/run.sh` (`date +%s` delta) | — | Phase 21 perf-gate precedent uses `date +%s`, not `SECONDS`; CI margin baked into the 30s ceiling. |

## User Constraints (from CONTEXT.md)

> CONTEXT.md exists for this phase. Per its `## Implementation Decisions`, **all implementation choices are at Claude's discretion** (pure infrastructure phase, discuss skipped). The items below are project locks — NOT open for relitigation.

### Locked Decisions (project locks the planner MUST honor)

- **Test harness:** extend the hand-rolled `tests/run.sh` + `tests/lib/sandbox.sh`. STACK.md: `bats-core` is unit-level only, no new test deps. Mirror the existing `▸ Phase 21/22/23` block idioms (`pass`/`fail` helpers, `mktemp` sandboxes, set/reset EXIT-trap discipline). The ROADMAP phase line says "bats-core tests" — **defer to STACK.md (extend `run.sh`)** unless planning finds a concrete reason bats is required; flag if so. (Research finds NO such reason — see State of the Art.)
- **Fixture naming:** the fixture dir MUST be `_`-prefixed: `tests/fixtures/_brownfield-argus/`. The generic `tests/fixtures/[^_]*/` sweep loops at `run.sh:326` (fixture audits), `:368` (golden-EXPECT), `:390` (dry-run byte-identical snapshot) skip underscore dirs — a non-underscore fixture would be swept into those loops and fail them.
- **Perf gate:** the <30s dry-run bound is measured in CI; decide the timing mechanism (`SECONDS`/`date` delta) and a sane CI margin.
- **SIGKILL simulation:** reuse the Phase 22 background-launch + bounded-poll + `kill -9` harness pattern. The non-TTY recovery exit-2 path is the automatable assertion; the interactive prompt was already PTY-verified in Phases 22/23.
- **Zero-diff comparison:** `diff -r` with excludes for conjure's own dirs (`.conjure-adopt-backups`, `.conjure-archive-*`, `RESTRUCTURE-LOG.md`, `adopt-manifest.json`, `.conjure-adopt-state`) per Phase 22 D-03.
- **Conventions:** POSIX bash 3.2+, `exit 2` never `exit 1`, shellcheck CI gate (`-S error -e SC2164,SC2044,SC2034,SC2155`), no new deps.

### Claude's Discretion

- Fixture generation strategy (committed files vs a generator script). **Research recommends a generator script** (repo-lean; matches the `brownfield-simple/generate-large.sh` precedent).
- Exact perf timing mechanism + CI margin (recommend `date +%s` delta, 30s ceiling — see Pitfall 2).
- Wave shape — the project idiom is test-first Wave 0, but this phase is mostly tests, so "Wave 0 may BE the deliverable."
- Whether to make the criterion-3 `report()` source deviation (recommend yes — see Open Questions Q1).

### Deferred Ideas (OUT OF SCOPE)

None — verification phase; discussion stayed within scope.

## Phase Requirements

> **Requirements: None.** All 23 v0.6.0 requirements map to Phases 21–23. Phase 24 has no `REQ-*` IDs; it is gated entirely by the five ROADMAP success criteria, which this research maps to observable test points in `## Validation Architecture`.

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Hand-rolled `tests/run.sh` | current (3291 lines) | The E2E assertion harness — add a `▸ Phase 24` block | Project standard; STACK.md locks it. `pass`/`fail` helpers at `run.sh:15-16`, `sandbox_setup` at `tests/lib/sandbox.sh`. [VERIFIED: read this session] |
| `git` | system (preflight dep) | `git init` + commit + untracked-file dirty-tree harness (if argus needs a git-clean tree for the live-adopt path) | Already used in `▸ Phase 22` dirty-tree harness (`run.sh:2523-2527`). Note: adopt's precondition_git **skips the dirty-tree gate on a non-git target** (`adopt.sh:157-160`), so a non-git sandbox runs the live path with no `git init` needed. [VERIFIED: read this session] |
| `jq` | system (hard preflight dep) | Read `state.json` / `adopt-manifest.json` in assertions (e.g., `.current_step`, `.files[].path`, `.restructure_steps[].status`) | Already used throughout `run.sh`. [VERIFIED] |
| `diff -r` | POSIX | Zero-diff before/after comparison (criterion 2) | Exact `▸ Phase 22` rollback idiom at `run.sh:2600-2603`. [VERIFIED] |
| `sha256sum` / `shasum -a 256` | system | Per-file hash record for the rollback verify (cross-platform fallback) | `p22_sha()` helper at `run.sh:2388-2391` is the exact pattern to reuse. [VERIFIED] |
| `date +%s` | POSIX | Perf timing delta for the <30s bound | Phase 21 perf-gate precedent at `run.sh:2333/2345`. [VERIFIED] |
| `ln -s` | POSIX | Create the real symlink fixture file (criterion 5) | The existing `brownfield-simple/symlink-target.md` is a **regular file**, not a symlink — the argus fixture must use a genuine `ln -s`. [VERIFIED: `ls -la` this session showed `.rw-r--r--`] |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `find` / `wc -l` / `tr -d ' '` | POSIX | File counts, line counts in assertions | Standard `run.sh` idiom (e.g. `find ... | wc -l | tr -d ' '`). [VERIFIED] |
| `comm -13` | POSIX | (already used inside adopt.sh) — not needed in tests | Reference only. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Generator script materializing 500 files | Committing 500 `.md` files to `tests/fixtures/_brownfield-argus/` | Committed files bloat the repo (500 files × git history) and slow `cp -r` in every sandbox setup. Generator keeps the repo lean and matches the `generate-large.sh` precedent. **Recommend generator.** A small committed "seed" of distinctive files (oversized CLAUDE.md, symlink, @import doc) + generated bulk filler is the cleanest hybrid. |
| Extend `tests/run.sh` | `bats-core` (vendored submodule) | STACK.md: bats is unit-level only; the ROADMAP "bats-core tests" phrase is superseded by the STACK.md lock per CONTEXT. E2E assertions are integration-shaped (run pipeline → assert filesystem/exit-code) — exactly what the `run.sh` loop models. **No concrete reason to adopt bats; do not.** |
| `date +%s` integer-second delta | `SECONDS` builtin | `SECONDS` works on bash 3.2 too, but Phase 21's precedent uses `date +%s` and it is unambiguous in subshells. Either is fine; `date +%s` matches precedent. |

**Installation:**
```bash
# Nothing to install. tests/run.sh + tests/lib/sandbox.sh exist; all deps (git/jq/diff/find/date) are preflight deps.
```

## Package Legitimacy Audit

**Not applicable.** Phase 24 installs **zero external packages** (CLAUDE.md locks `dependencies: {}` empty; STACK.md: no new test deps; CONTEXT: "no new deps"). All tooling is POSIX/system binaries already required by the project. No npm/PyPI/crates package is added, so the slopcheck gate has nothing to audit.

## Architecture Patterns

### System Architecture Diagram

```
                          tests/run.sh  ── ▸ Phase 24 block (NEW) ──┐
                                                                     │
   ┌─────────────────────────────────────────────────────────────────────────────────┐
   │  Per criterion:  mktemp -d sandbox  →  materialize _brownfield-argus  →  run      │
   │                  pipeline  →  assert observable signal  →  rm -rf + trap - EXIT    │
   └─────────────────────────────────────────────────────────────────────────────────┘
        │                    │                      │                      │
        ▼                    ▼                      ▼                      ▼
  generator script     scripts/adopt.sh       lib/inventory.sh      gates/audit-staged.sh
  (materializes 500    (SHIPPED pipeline       (SHIPPED symlink-     (SHIPPED @import
   .md + 1 symlink +    under test:             skip, verified)       block, verified)
   oversized CLAUDE +   dry-run/snapshot/
   @import doc)         inventory/scaffold/
                        audit/rollback/
                        recovery/apply-step)

  Criterion → observable signal flow:
   C1 dry-run  → git-porcelain clean + no manifest/state under target + <30s (date delta)
   C2 rollback → per-file sha256 == before  +  diff -r (excl. D-03 dirs) empty
   C3 idempot. → second run: created[]==0 + report "Scaffolded: 0" (+ "nothing to scaffold"*)
   C4 SIGKILL  → bg-launch + poll state.json current_step + kill -9 + re-run --rollback → zero-diff
   C5 symlink  → manifest files[] excludes the symlink ; @import staged file → audit-staged exit 2
                                                              (*requires the report() deviation — Q1)
```

### Recommended Project Structure

```
tests/
├── run.sh                              # ADD: ▸ Phase 24 block near end (after ▸ Phase 23, before Summary at :3285)
├── lib/sandbox.sh                      # UNCHANGED (reuse sandbox_setup)
└── fixtures/
    └── _brownfield-argus/              # NEW (underscore-prefixed — swept-loop-safe)
        ├── generate-argus.sh           # NEW: materializes 500 .md into a passed target dir
        ├── CLAUDE.md                    # seed: oversized/sprawling (or generated) — for the report
        ├── _seed/                       # OPTIONAL committed distinctive seed files:
        │   ├── with-import.md           #   (criterion 5 @import staged-content source)
        │   └── ...                      #   the symlink is created by ln -s at gen time, NOT committed
        └── (bulk filler generated at test time, never committed)
```

> Note: a committed symlink inside a fixture is fragile across `cp -r`/git/Windows. **Create the symlink with `ln -s` inside the generator**, not as a committed file.

### Pattern 1: Sandbox + set/reset EXIT-trap discipline (the per-section skeleton)

**What:** Every Phase 24 assertion section creates a `mktemp -d` target, sets a cleanup `trap`, runs, asserts, then `rm -rf` + `trap - EXIT`. This is the exact `▸ Phase 22` shape.
**When to use:** Every section.
**Example:**
```bash
# Source: tests/run.sh:2399-2449 (Phase 22 dry-run section)
P24_DRY_TARGET="$(mktemp -d)"
trap 'rm -rf "$P24_DRY_TARGET"' EXIT
bash "$ARGUS_GEN" "$P24_DRY_TARGET"          # materialize 500 files
# ... run + assert ...
rm -rf "$P24_DRY_TARGET"
trap - EXIT
```

### Pattern 2: Presence guard for graceful RED (Wave-0 test-first)

**What:** Gate each section behind a presence check so a missing fixture/generator reports a clear `fail "... Wave N must create ..."` instead of crashing.
**When to use:** If the plan writes the test block before the generator exists (test-first Wave 0). Since the *pipeline* already ships, the only thing to guard is the **generator/fixture** presence.
**Example:**
```bash
# Source: tests/run.sh:2372-2374 (P22_ADOPT_OK pattern)
P24_ARGUS_GEN="$CONJURE_HOME/tests/fixtures/_brownfield-argus/generate-argus.sh"
P24_ARGUS_OK=0
[ -f "$P24_ARGUS_GEN" ] && P24_ARGUS_OK=1
# each section: if [ "$P24_ARGUS_OK" -ne 1 ]; then fail "... generator missing ..."; else ... ; fi
```

### Pattern 3: Background-launch + bounded-poll + kill -9 (criterion 4)

**What:** Launch adopt in the background, poll a bounded loop for the state-transition signal, `kill -9`, `wait`, then re-run and assert recovery.
**When to use:** Criterion 4 (SIGKILL after snapshot, before scaffold).
**Example:**
```bash
# Source: tests/run.sh:2702-2712 (Phase 22 SIGKILL harness) — adapt the poll target
DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P24_SK_TARGET" >/dev/null 2>&1 &
P24_SK_PID=$!
for _i in $(seq 1 100); do
  # Kill strictly AFTER snapshot, BEFORE scaffold: poll state.json current_step.
  _step="$(jq -r '.current_step // ""' "$P24_SK_TARGET/.conjure-adopt-state/state.json" 2>/dev/null || true)"
  case "$_step" in snapshot|inventory) break ;; esac    # snapshot done, scaffold not yet
  kill -0 "$P24_SK_PID" 2>/dev/null || break
  sleep 0.05
done
kill -9 "$P24_SK_PID" 2>/dev/null || true
wait "$P24_SK_PID" 2>/dev/null || true
```

### Pattern 4: Zero-diff rollback verification (criterion 2)

**What:** Snapshot a pristine pre-adopt copy OUTSIDE the target, record per-file sha256 in a file OUTSIDE both trees, live-adopt, rollback, then assert per-file sha256 == before AND `diff -r` (with D-03 excludes) empty.
**When to use:** Criterion 2.
**Example:**
```bash
# Source: tests/run.sh:2560-2608 (Phase 22 rollback section) — verbatim idiom
P24_RB_PRE="$(mktemp -d)"; P24_RB_HASHES="$(mktemp)"   # hashes OUTSIDE both trees or they pollute the diff
# ... cp pristine, record sha256, adopt, rollback ...
P24_RB_DIFF="$(diff -r \
  -x '.conjure-adopt-backups' -x '.conjure-archive-*' \
  -x 'RESTRUCTURE-LOG.md' -x 'adopt-manifest.json' -x '.conjure-adopt-state' \
  "$P24_RB_PRE" "$P24_RB_TARGET" 2>&1)"
[ -z "$P24_RB_DIFF" ] && pass "..." || fail "..."
```

### Anti-Patterns to Avoid

- **Naming the fixture `brownfield-argus` (no underscore):** it would be swept by `run.sh:326/368/390` `[^_]*` loops — those run `audit-setup.sh` and `conjure init --dry-run` against every non-underscore fixture and assert green/byte-identical. An argus fixture (oversized CLAUDE.md, @import doc) would fail those alien assertions. **MUST be `_brownfield-argus`.**
- **Committing the symlink file:** symlinks survive `git` and `cp -r` inconsistently (Windows, archive tooling). Create it with `ln -s` at generation time.
- **Recording rollback hashes inside the target tree:** the hash file then appears in the `diff -r` and breaks the zero-diff assertion. Keep it in a `mktemp` OUTSIDE both trees (Phase 22 does exactly this at `run.sh:2562`).
- **Killing on `.conjure-adopt-backups` existence alone (criterion 4 precision):** the backups dir appears at the snapshot step, but inventory then runs before scaffold. For "after snapshot, before scaffold" precision, poll `state.json .current_step` ∈ {snapshot, inventory} (see Pattern 3). The Phase 22 backups-dir poll is a looser proxy and is acceptable if the plan documents that snapshot→scaffold spans inventory.
- **Asserting a perf bound with a tight margin (e.g. <8s):** CI runners are slow + variable. Use the ROADMAP's 30s ceiling directly; do not tighten it.
- **Modifying `scripts/adopt.sh` / gates / skill beyond the criterion-3 `report()` deviation:** out of scope (CONTEXT `## Phase Boundary`). If a test reveals a different bug, fix at source as an explicit deviation and document it.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Sandbox isolation | A new temp-dir + env-reset helper | `sandbox_setup` (`tests/lib/sandbox.sh`) | Already resets `HOME`/`XDG`/`PATH`, registers EXIT trap, keeps git/jq/node reachable on Git Bash (WR-01). |
| Cross-platform sha256 | Inline `sha256sum` calls | `p22_sha()` (`run.sh:2388`) | Handles the macOS `shasum -a 256` fallback. Copy the helper or call the same shape. |
| SIGKILL timing | A blind `sleep N` then kill | Bounded poll on `state.json .current_step` | A fixed sleep is flaky; the durable state manifest gives a deterministic transition signal. |
| 500-file generation | A bespoke loop in `run.sh` | A `generate-argus.sh` script (mirror `generate-large.sh`) | Keeps `run.sh` readable; the fixture owns its own generation; reusable across sections. |
| Zero-diff comparison | A custom file-walk comparator | `diff -r` with the D-03 `-x` excludes | POSIX, recursive, exact Phase 22 idiom. |

**Key insight:** Phase 22's `▸ Phase 22` block is a complete, green, idiom library for *every* assertion Phase 24 needs. The phase is 90% "copy the Phase 22 section shape, point it at `_brownfield-argus`, scale the assertions to 500 files." Do not invent new harness machinery.

## Runtime State Inventory

> This is a fixture+test phase, not a rename/refactor/migration. No runtime state is renamed or migrated. Included for completeness per the rename-phase checklist trigger — all categories are explicitly "none."

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — verified: the phase adds a test fixture + assertions; touches no datastore, no collection, no user_id. | none |
| Live service config | None — verified: no external service, no UI-stored config, no CI service. The only CI touch is that the existing `bash tests/run.sh` step picks up the new block automatically (`ci.yml:58/93`). | none |
| OS-registered state | None — verified: no Task Scheduler / launchd / systemd / pm2 registration. The SIGKILL test spawns + kills a background bash process within the test, fully self-contained. | none |
| Secrets/env vars | None — verified: the test sets only `CONJURE_*`/`DRY_RUN` env vars locally per-invocation (already the Phase 22 contract). No secret key referenced. | none |
| Build artifacts | None — verified: no compiled artifact, no egg-info, no Docker tag. The generator materializes files into ephemeral `mktemp -d` dirs that are `rm -rf`'d. | none |

**The canonical question:** After the test block + fixture are added, no runtime system holds any cached/stored/registered string — every sandbox is `mktemp -d` and trap-cleaned.

## Common Pitfalls

### Pitfall 1: The fixture name sweep (criterion-blocking if missed)
**What goes wrong:** Naming the fixture without the `_` prefix causes `run.sh:326/368/390` `tests/fixtures/[^_]*/` loops to run `audit-setup.sh` + `conjure init --dry-run` against it and assert green/byte-identical — which an oversized-CLAUDE/@import argus fixture will fail.
**Why it happens:** The three loops are generic over all non-underscore fixtures; a new fixture is silently opted-in.
**How to avoid:** Name it `tests/fixtures/_brownfield-argus/`. STATE.md lesson + Phase 22/23 precedent (`_adopt-restructure-steps`, `_restructure-gates`).
**Warning signs:** New unexplained failures in the "Fixture audits", "Golden-file EXPECT", or "Dry-run byte-identical snapshot" sections after adding the fixture.

### Pitfall 2: Perf flakiness on CI runners
**What goes wrong:** A tight perf assertion (or measuring with sub-second precision) flakes on loaded/variable CI runners.
**Why it happens:** GitHub Actions runners are shared and variable; 500-file `find`+classify timing varies.
**How to avoid:** Use the ROADMAP's 30s ceiling as the literal bound with `date +%s` integer-second deltas (Phase 21 precedent, `run.sh:2333-2351`). **Empirically measured this session: full `conjure adopt --dry-run` on 512 `.md` files = 6s** — a ~5x margin under 30s. Do not tighten.
**Warning signs:** Intermittent perf-section failures only on CI, never locally.

### Pitfall 3: SIGKILL window imprecision (criterion 4)
**What goes wrong:** Killing too early (before snapshot completes) leaves no recoverable state; killing too late (after scaffold) tests the wrong window.
**Why it happens:** The pipeline order is snapshot → **inventory** → scaffold (`adopt.sh:675/691/716`); "after snapshot, before scaffold" actually spans the inventory step.
**How to avoid:** Poll `state.json .current_step` and break the poll when it is `snapshot` or `inventory` (snapshot completed at `adopt.sh:686`, scaffold not started until `:718`). Then `kill -9`. Then re-run with `CONJURE_ADOPT_ROLLBACK=1` and assert zero-diff (Pattern 4) — that is the automatable "choosing rollback restores cleanly."
**Warning signs:** Re-run reports "no .conjure-adopt-state found" (killed too early) or `current_step=scaffold/audit` in the killed state (killed too late).

### Pitfall 4: Rollback hash-file pollutes the diff
**What goes wrong:** Recording the pre-adopt sha256 manifest inside the target tree makes it show up in `diff -r`, breaking the zero-diff assertion.
**How to avoid:** Store the hash record in a `mktemp` file OUTSIDE both the pristine copy and the live target (Phase 22 does this at `run.sh:2562`).
**Warning signs:** `diff -r` reports `Only in <target>: <hashfile>`.

### Pitfall 5: macOS `cp -a` snapshot self-copy (already mitigated, but the test should not regress it)
**What goes wrong:** A snapshot whose destination is inside the copied tree recurses infinitely on macOS.
**Why it happens:** Documented Pitfall 3 in PITFALLS-equivalent; mitigated by `snapshot_guarded()` (`adopt.sh:186-220`) which snapshots into a temp root then relocates.
**How to avoid:** Nothing to build — the live-adopt sections inherently exercise this. The existing `▸ Phase 22 — snapshot self-copy regression` already guards it; Phase 24's 500-file live adopt is an additional stress on the same path. Optionally add a `find -mindepth 2 -name '.conjure-adopt-backups'` nesting check (mirror `run.sh:2902`).

### Pitfall 6: Non-git sandbox skips the dirty-tree gate
**What goes wrong:** A test author assumes the live adopt enforces a git-clean precondition, but a `mktemp -d` sandbox is not a git repo, so `precondition_git()` prints "not a git repo — skipping dirty-tree gate" and proceeds.
**Why it happens:** `adopt.sh:157-160` returns 0 for non-git targets by design (snapshot still backs up the filesystem).
**How to avoid:** For criteria 1/2/3/4/5 the live path runs fine in a non-git sandbox — this is the simplest setup and is correct. Only `git init` the sandbox if a test specifically needs the dirty-tree gate (criterion 3 of *Phase 22*, not Phase 24). Phase 24's criteria do NOT require git.

## Code Examples

### Idempotent re-run assertion (criterion 3) — the measured reality
```bash
# Empirically verified this session:
#   First live adopt:  "Scaffolded:  42 layer files"
#   Second run (state cleared): "Scaffolded:  0 layer files"  ← zero mutations
# The literal phrase "nothing to scaffold" is NOT emitted by the shipped report().
# Assert the satisfiable signal + (recommended) the deviation phrase:
P24_RERUN_OUT="$(DRY_RUN=0 CONJURE_HOME="$CONJURE_HOME" bash "$P22_ADOPT_SH" "$P24_TARGET" 2>&1)"
if printf '%s\n' "$P24_RERUN_OUT" | grep -Eq 'Scaffolded:[[:space:]]*0[[:space:]]+layer'; then
  pass "idempotent re-run: zero layers scaffolded (criterion 3)"
fi
# created[] count must be 0 on the second run:
P24_CREATED="$(jq -r '.created | length' "$P24_TARGET/.conjure-adopt-state/state.json" 2>/dev/null || echo NA)"
[ "$P24_CREATED" = "0" ] && pass "idempotent re-run: created[]==0 (criterion 3)"
# IF the report() deviation is made, ALSO assert the ROADMAP phrase:
# printf '%s\n' "$P24_RERUN_OUT" | grep -qi 'nothing to scaffold' && pass "..."
```
> Note on the second-run mechanics: the recovery dispatch (`adopt.sh:803`) treats a leftover `.conjure-adopt-state` as a partial run and exits 2 non-interactively. So a true "idempotent re-run" assertion must either (a) `--start-fresh`, or (b) `rm -rf .conjure-adopt-state` between runs (Phase 22's self-copy section does exactly this at `run.sh:2896`), or (c) the first run must complete fully (state still present → treated as partial). **Recommended: clear `.conjure-adopt-state` between the two runs**, matching the established Phase 22 idiom, so the second run is a clean idempotent scaffold and the report reads `Scaffolded: 0`.

### Symlink-skip assertion (criterion 5) — verified-correct behavior
```bash
# Verified this session: a real `ln -s` markdown file is ABSENT from manifest files[].
# The generator must create a genuine symlink (NOT a committed regular file):
ln -s real.md "$P24_TARGET/docs/linked.md"
# After live adopt, the symlink must not appear in files[]:
if ! jq -e --arg p 'docs/linked.md' '.files[]?|select(.path==$p)' \
     "$P24_TARGET/adopt-manifest.json" >/dev/null 2>&1; then
  pass "symlink skipped by inventory — absent from files[] (criterion 5)"
fi
```

### @import pre-write block assertion (criterion 5) — shipped gate
```bash
# Source: tests/run.sh:2982-2990 (Phase 23 audit-staged gate). The gate exits 2 on ^@.
P24_AUD="$CONJURE_HOME/templates/skills/restructure/gates/audit-staged.sh"
printf '# CLAUDE\n@.claude/skills/x/SKILL.md\n' > "$P24_TARGET/.conjure-adopt-state/staging/CLAUDE.md"
CONJURE_HOME="$CONJURE_HOME" bash "$P24_AUD" "$P24_TARGET/.conjure-adopt-state/staging/CLAUDE.md" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass "@import proposed CLAUDE.md blocked (exit 2) before approval (criterion 5)"
# "never written": the staged file is never applied to the target CLAUDE.md because the gate
# blocks before approval. Assert the target CLAUDE.md does NOT contain the @import line:
grep -q '^@' "$P24_TARGET/CLAUDE.md" && fail "@import leaked to target CLAUDE.md" \
                                     || pass "@import never written to target CLAUDE.md (criterion 5)"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ROADMAP phase line: "bats-core tests covering..." | Extend hand-rolled `tests/run.sh` (no bats) | STACK.md lock (2026-05-24) + CONTEXT lock | Defer to STACK.md per CONTEXT. **Research finds no concrete reason bats is required** — all five criteria are integration-shaped (run pipeline → assert filesystem + exit code), which the `run.sh` loop models directly. Adopting bats would add a submodule + maintenance for zero benefit here. Flag resolved: extend `run.sh`. |
| ROADMAP criterion 3: report "nothing to scaffold" | Shipped report emits `Scaffolded: 0 layer files` | Phase 22 report() shipped (2026-05-28) | The literal phrase does not exist in code (verified by grep). Plan must choose: assert the real signal, or make a 1-line `report()` deviation. See Open Questions Q1. |

**Deprecated/outdated:**
- The `brownfield-simple/symlink-target.md` name implies a symlink but is a **regular file** — do not copy it expecting symlink behavior; create a real `ln -s` for the argus symlink-skip test.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A generator-script fixture (vs committed files) is the right call. | Standard Stack / Discretion | Low — it is explicitly Claude's Discretion in CONTEXT and matches the `generate-large.sh` precedent. If the team prefers committed files, the test structure is unaffected (same assertions, different setup). |
| A2 | "Nothing to scaffold" (criterion 3) is satisfied by asserting `Scaffolded: 0` + `created[]==0`, with an optional 1-line `report()` deviation to also emit the literal phrase. | Open Questions Q1 | Low/Medium — if a reviewer insists on the literal ROADMAP phrase being emitted by the tool, the deviation is required (and recommended). The behavior (zero mutations) is already correct either way. |

**All other claims in this research are VERIFIED (read source + ran the pipeline this session) — no other assumptions.**

## Open Questions (RESOLVED)

> All three resolved during planning; resolutions recorded in 24-VALIDATION.md "## Planning Resolutions" (O-1/O-2/O-3) and encoded in plans 24-01/24-02.

1. **Criterion 3 "nothing to scaffold" — assert the real signal, or make a source deviation?**
   - What we know: the shipped `report()` (`scripts/adopt.sh:236-245`) prints `Scaffolded: ${created_count} layer files`. On an idempotent re-run, `created_count == 0` (empirically verified). The literal string "nothing to scaffold" exists nowhere in the codebase.
   - **RESOLVED — do BOTH (O-1):** (a) assert the already-true signals (`Scaffolded: 0 layer files`, `state.json .created|length==0`, `diff -r` excl D-03 between run-1-after and run-2-after empty); (b) make a minimal 1-line additive `report()` deviation emitting the literal `nothing to scaffold` when `created_count` is 0, so the ROADMAP criterion text and the test agree. Scoped as a documented deviation in plan 24-01; 429-green no-regression is an acceptance criterion. See 24-VALIDATION.md O-1.

2. **Does the live-adopt path need a git-clean tree for argus?**
   - **RESOLVED — no `git init` needed (O-2):** `precondition_git()` skips the gate on a non-git target (`adopt.sh:157-160`); a `mktemp -d` sandbox is non-git so live adopt runs the full path. Criteria 1–5 run in a plain non-git sandbox. See 24-VALIDATION.md O-2.

3. **Where in `run.sh` does the `▸ Phase 24` block go?**
   - **RESOLVED — after `:3280` (O-3):** insert the `▸ Phase 24` block after the end of the Phase 23 block (`:3280`) and before the gh-stub cleanup/Summary, behind a `P24_ARGUS_OK` guard, mirroring the section-banner style. See 24-VALIDATION.md O-3 + plan 24-02.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `bash` 3.2+ | the whole harness | ✓ | 3.2+ (macOS default), 5.x (CI ubuntu) | — |
| `git` | optional dirty-tree harness (not needed for Phase 24 criteria) | ✓ | system | non-git sandbox runs fine |
| `jq` | reading state.json / manifest in assertions | ✓ | system (hard preflight dep) | — |
| `diff`, `find`, `wc`, `tr`, `date`, `ln` | assertions + fixture gen | ✓ | POSIX | — |
| `sha256sum` / `shasum` | rollback per-file verify | ✓ | one or the other present | `p22_sha()` falls back to `shasum -a 256` |
| `shellcheck` | CI lint gate | ✓ (CI) | per `ci.yml:23` (`-S error -e SC2164,SC2044,SC2034,SC2155`) | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none — every tool is already a project/preflight dependency.

## Validation Architecture

> This phase **is** validation, so this section is the core of the doc. nyquist_validation is enabled (config.json `workflow.nyquist_validation: true`).

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hand-rolled `tests/run.sh` (project standard; `bats-core` unit-only per STACK.md) — add a `▸ Phase 24` block |
| Config file | none — `run.sh` self-contained; sandbox via `tests/lib/sandbox.sh` |
| Quick run command | `bash tests/run.sh 2>&1 \| grep -E "Phase 24\|✗"` |
| Full suite command | `bash tests/run.sh` |
| CI invocation | `.github/workflows/ci.yml:58` + `:93` already run `bash tests/run.sh` on the OS matrix — **no workflow change needed** |

### The 5 Criteria → Observable Test Points

| # | ROADMAP Criterion | Observable Signal(s) | Test Type | Deterministically Automatable? | Notes |
|---|-------------------|----------------------|-----------|-------------------------------|-------|
| C1 | dry-run on 500 files: <30s AND zero files written to fixture | (a) `git status --porcelain` clean (non-git: no `adopt-manifest.json` + no `.conjure-adopt-state` under target); (b) `date +%s` delta < 30 | integration | **Yes** | Perf needs a **CI margin note**: bound is 30s; measured 6s on 512 files (~5x headroom). Mirror `run.sh:2409-2447` (zero-write) + `:2333-2351` (timing). |
| C2 | live adopt then `--rollback`: zero diff (sha256 every file) | (a) per-file sha256 == recorded before-hash; (b) `diff -r` with D-03 excludes empty; (c) `[ROLLBACK]` in log; (d) created[] files gone | integration | **Yes** | Verbatim `run.sh:2560-2608` idiom, scaled to 500 files. Hash file lives OUTSIDE both trees. |
| C3 | idempotent re-run: zero mutations + reports "nothing to scaffold" | (a) `Scaffolded: 0 layer files` in report; (b) `state.json .created \| length == 0`; (c) `diff -r` (excl. D-03) between run-1-after and run-2-after empty; (d) **optional** literal "nothing to scaffold" | integration | **Yes** (signal a/b/c); (d) needs the `report()` **source deviation** | Clear `.conjure-adopt-state` between runs (Phase 22 idiom `run.sh:2896`) so run 2 is a clean idempotent scaffold, not a recovery prompt. |
| C4 | SIGKILL after snapshot before scaffold → recovery prompt; rollback restores cleanly | (a) non-TTY re-run exits 2 with "last completed:" + `--rollback/--resume/--start-fresh` (mirror `run.sh:2724-2743`); (b) driving `--rollback` then `diff -r` (excl. D-03) empty | integration | **Yes** | Interactive `[r]/[c]/[s]` prompt is **manual-only** (PTY) — already UAT'd in Phase 22/23. Automatable path = non-TTY exit-2 + explicit `CONJURE_ADOPT_ROLLBACK=1` re-run → zero-diff. Kill window: poll `state.json .current_step ∈ {snapshot,inventory}` (Pattern 3 / Pitfall 3). |
| C5 | symlink skipped by inventory; @import CLAUDE.md blocked, never written | (a) symlink path absent from manifest `files[]` (verified-correct); (b) `audit-staged.sh` on an `@import` staged file exits 2 (`run.sh:2984-2990`); (c) target CLAUDE.md never gains an `^@` line | integration | **Yes** | Both behaviors verified shipped-correct this session. The symlink MUST be a real `ln -s`, not a committed regular file. |

### Sampling Rate
- **Per task commit:** `bash tests/run.sh 2>&1 | grep -E "Phase 24|✗"`
- **Per wave merge:** `bash tests/run.sh` (full suite — must not regress the 429 green assertions)
- **Phase gate:** Full suite green + `shellcheck -S error -e SC2164,SC2044,SC2034,SC2155` clean on the new generator + any `report()` deviation, before `/gsd-verify-work`.
- **Max feedback latency:** ~60s (full suite) — empirically the 500-file argus sections add ~6–15s.

### Wave 0 Gaps
- [ ] `tests/fixtures/_brownfield-argus/generate-argus.sh` — materializes 500 `.md` files + a real `ln -s` symlink + an oversized/sprawling CLAUDE.md + an `@import` staged-content seed, into a passed target dir. Mirror `generate-large.sh` shape.
- [ ] `▸ Phase 24` block in `tests/run.sh` (after `:3280`) — five sections, one per criterion, behind a `P24_ARGUS_OK` presence guard, mirroring the Phase 22 section shapes.
- [ ] (optional, recommended) 1-line `report()` deviation in `scripts/adopt.sh` for criterion 3's literal "nothing to scaffold" — document as a deviation.
- [ ] `# shellcheck` inline directives matching the project style on the new generator script.

> Framework install: **none** — `tests/run.sh` + `tests/lib/sandbox.sh` already exist; the pipeline under test already ships. All gaps are new fixtures/assertions (+ one optional source deviation).

### Manual-Only Verifications
| Behavior | Criterion | Why Manual | Test Instructions |
|----------|-----------|------------|-------------------|
| Interactive `[r]/[c]/[s]` recovery prompt via real TTY | C4 | TTY interaction not reliably automatable in CI; non-TTY exit-2 path IS automated | Already PTY-verified in Phase 22/23 UAT. Optionally re-confirm: `conjure adopt` on argus, `kill -9` mid-run, re-run in a terminal, confirm prompt + each choice. |

## Security Domain

`security_enforcement` is not present in config.json (`features: {}`, no `security_enforcement` key). This is an internal test-harness phase with **no external input surface, no auth, no network, no crypto, no new attack surface** — it spawns and kills a local background process and writes to `mktemp -d` dirs. The pipeline's own security gates (path-traversal guard `resolve_under` at `adopt.sh:448`, op-allowlist at `:487`, protected-dir rejection at `:532`) were built and tested in Phase 22/23 (14/14 threats closed per the milestone audit) and are not re-litigated here. **No ASVS category applies to a self-contained bash test block.** Section included for completeness; no security controls are introduced or required by Phase 24.

## Sources

### Primary (HIGH confidence — read source + ran pipeline this session)
- `scripts/adopt.sh` (full, 817 lines) — pipeline order, report(), rollback, recovery dispatch, state transitions, snapshot_guarded.
- `lib/inventory.sh` (full, 439 lines) — two-layer symlink skip (`:48`, `:224`), 500-file cap, manifest emit.
- `tests/run.sh` (header `:1-100`; Phase 21 perf `:2322-2355`; Phase 22 `:2363-2910`; Phase 23 `:2922-3280`; fixture sweep loops `:326/368/390`) — every idiom Phase 24 reuses.
- `tests/lib/sandbox.sh` (full) — `sandbox_setup` isolation.
- `templates/skills/restructure/gates/audit-staged.sh` (full) — @import block exit-2 behavior.
- `cli/conjure cmd_adopt` (`:194-219`) — `--rollback/--resume/--start-fresh` → `CONJURE_ADOPT_*` env wiring.
- `.github/workflows/ci.yml` (`:23/58/93`) — shellcheck flags + `bash tests/run.sh` matrix invocation.
- `.planning/phases/22-.../22-VALIDATION.md` — the Validation Architecture template mirrored here.
- **Empirical runs this session:** idempotent re-run report (`Scaffolded: 42` → `Scaffolded: 0`); real `ln -s` symlink absent from manifest (`total_files=2`); `conjure adopt --dry-run` on 512 files = 6s.

### Secondary (MEDIUM)
- `.planning/research/STACK.md`, `PITFALLS.md`, `ARCHITECTURE.md` — locks + the documented Pitfall 3 self-copy mitigation + CR-7 perf gate.
- `.planning/ROADMAP.md` Phase 24 section — the five success criteria.
- `.planning/phases/24-.../24-CONTEXT.md` — locks + discretion.

### Tertiary (LOW)
- None. All claims are tool-verified or read directly from source.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every tool is a confirmed project/preflight dep; harness idioms read from live `run.sh`.
- Architecture (test structure): HIGH — directly mirrors the shipped, green Phase 22/23 blocks.
- Pitfalls: HIGH — fixture-sweep, perf-flakiness, SIGKILL-window, hash-pollution all derived from reading the actual loops + running the pipeline.
- Criterion-3 source gap: HIGH on the fact (grep + empirical run confirm "nothing to scaffold" is absent); MEDIUM on the resolution choice (it is a judgment call flagged for the plan).

**Research date:** 2026-05-29
**Valid until:** 2026-06-28 (stable — internal harness; only the shipped pipeline's behavior could drift, and it is locked v0.6.0).
