# Phase 3: Sandboxed Per-Profile Fixtures - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-24
**Phase:** 3-Sandboxed Per-Profile Fixtures
**Areas discussed:** Fixture content depth, Sandbox mechanism, Broken fixture design, Fixture generation approach

---

## Fixture Content Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Harness only (.claude/) | Just the Claude Code layer: CLAUDE.md, skills/, agents/, hooks/, settings.json. Minimal, easy to maintain. | |
| Stub project files | Add a realistic but minimal stub: package.json, pom.xml, Cargo.toml, etc. Makes conjure audit more meaningful — profile-specific preflight.sh checks trigger against real-ish project files. | ✓ |
| Full sample app | Complete runnable project per profile. High maintenance, overkill for audit testing. | |

**User's choice:** Stub project files
**Notes:** Manifest-only (one manifest file per profile, no src/ tree). Enough to trigger profile preflight checks without maintenance overhead.

---

## Sandbox Mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Bash helper in tests/lib/ | A sourced tests/lib/sandbox.sh that exports HOME/XDG_CONFIG_HOME/CLAUDE_CONFIG_DIR/PATH. Reusable. Follows lib/ pattern from Phase 2. | ✓ |
| Wrapper script per fixture | Each tests/fixtures/<profile>/run.sh sets its own env. Explicit but duplicates the pattern 9 times. | |
| Inline in tests/run.sh | Expand the existing test runner directly. Keeps everything in one file but harder to unit-test. | |

**User's choice:** Bash helper in tests/lib/

| Option | Description | Selected |
|--------|-------------|----------|
| Copy to temp dir | sandbox.sh copies fixture to mktemp -d, sets HOME/XDG/PATH to temp copy, runs conjure audit there. Original fixture never touched. | ✓ |
| Run in-place with read-only guard | Audit against committed fixture directly. Faster, but risks accidental mutation. | |

**User's choice:** Copy to temp dir
**Notes:** Follow the existing mktemp -d + trap pattern already in tests/run.sh.

---

## Broken Fixture Design

| Option | Description | Selected |
|--------|-------------|----------|
| tests/fixtures/_broken/ | Single _broken/ directory, underscore sorts first, signals intent clearly. | ✓ |
| tests/fixtures/broken-claude-md/ | Named by what it breaks. Couples dir name to a specific violation. | |
| Inline in an existing fixture | Second CLAUDE.md variant inside a profile fixture. Mixes green and red fixtures. | |

**User's choice:** tests/fixtures/_broken/

| Option | Description | Selected |
|--------|-------------|----------|
| CLAUDE.md size cap (>100 lines) | Pad CLAUDE.md to 105 lines. Deterministic, easiest to assert against exact finding string. | ✓ |
| Missing skill frontmatter | A SKILL.md missing required name:/description: fields. Tests a different audit path. | |
| Anti-pattern in CLAUDE.md (@import) | Include a forbidden @import in CLAUDE.md. Tests anti-pattern detector. | |

**User's choice:** CLAUDE.md size cap (>100 lines)

| Option | Description | Selected |
|--------|-------------|----------|
| EXPECT file with grep patterns | tests/fixtures/_broken/EXPECT contains one grep pattern per expected finding. Phase 4's runner asserts each matches audit output. | ✓ |
| Inline assertions in run.sh | Hardcode expected string directly in run.sh with grep -q. Ties assertion to run.sh rather than fixture. | |
| Structured JSON manifest | EXPECT.json with {rule, finding}. Type-safe but adds JSON-parsing requirement to run.sh. | |

**User's choice:** EXPECT file with grep patterns

---

## Fixture Generation Approach

| Option | Description | Selected |
|--------|-------------|----------|
| conjure init-generated, then committed | Run conjure init --profile <p> against a seed stub, commit output. Regen command refreshes them. Fixtures always reflect actual init output. | ✓ |
| Hand-crafted from scratch | Write each fixture by hand without running conjure init. Explicit but drifts from actual init output. | |
| Generated at test time, not committed | tests/run.sh generates fixtures into temp dir on every run. Nothing to commit but makes fixture contents invisible and Phase 4 diffs harder. | |

**User's choice:** conjure init-generated, then committed

| Option | Description | Selected |
|--------|-------------|----------|
| scripts/regen-fixtures.sh script | Standalone scripts/regen-fixtures.sh that re-runs conjure init per profile and overwrites tests/fixtures/. Users run manually when profiles change. | ✓ |
| conjure update --fixtures subcommand | Expose regen as a conjure subcommand. More discoverable but adds CLI surface area. | |
| Makefile / task target | make regen-fixtures target. Convenient for CI but adds Makefile as a dependency. | |

**User's choice:** scripts/regen-fixtures.sh script

---

## Claude's Discretion

- Exact content of each manifest stub (minimal vs slightly richer package.json etc.)
- Whether scripts/regen-fixtures.sh accepts a --profile <p> flag for single-profile regen
- Exact grep pattern in tests/fixtures/_broken/EXPECT (match actual conjure audit output)

## Deferred Ideas

None — discussion stayed within phase scope.
