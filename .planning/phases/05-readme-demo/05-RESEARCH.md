# Phase 5: README Demo — Research

**Researched:** 2026-05-25
**Domain:** Terminal recording automation (asciinema + expect + agg) + README editing + CI assertion
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Profile: `ts-next` — widest audience recognition, best-case scaffold output.
- **D-02:** Sequence: `conjure init --dry-run --profile=ts-next .` then `conjure audit`. No preflight step — starts directly at init.
- **D-03:** Target length: under 60 seconds. Init dry-run output + audit pass in ~45s at normal simulated typing speed.
- **D-04:** `scripts/record-demo.sh` is committed. It: (1) creates an isolated `mktemp -d` temp dir (no leakage to real `$HOME`). (2) runs the command sequence via an `expect` script (automated, deterministic typing — not manual). (3) wraps everything in `asciinema rec` to capture the session. (4) calls `agg` to convert the `.cast` file to a GIF. (5) copies the GIF to `.github/assets/demo.gif`.
- **D-05:** The `expect` automation means every re-recording is byte-identical in content (same commands, same simulated typing delays).
- **D-06:** Toolchain: `asciinema` (recorder) → `agg` (official GIF converter, Rust-based). No `termtosvg` (unmaintained). No SVG embed path.
- **D-07:** Output artifact: `.github/assets/demo.gif`. Git-tracked, no external hosting.
- **D-08:** CI check: assert `test -s .github/assets/demo.gif` (file exists and is non-empty). Added to existing CI job — not a new job.
- **D-09:** Demo replaces the existing Quickstart code block. New reader sees the recording before reading any instructions.
- **D-10:** Caption: *`conjure init --dry-run --profile=ts-next .` — zero mutations, fully auditable.*

### Claude's Discretion

- Exact `expect` delay timings between keystrokes (should feel natural, not rushed, within the <60s target).
- Whether to add a `# Re-record the demo` heading comment in `record-demo.sh` or keep it purely functional.
- Exact width/height passed to `agg` (standard terminal width 120 cols).
- Whether to strip the `expect` dependency from the CI check or just document it as a contributor-only tool.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DOCS-01 | README includes an asciinema→GIF demo of `conjure init` + `conjure audit` (recorded against safe dry-run) | Covered by: toolchain research (asciinema + agg), expect automation pattern, README Quickstart edit location, CI assertion syntax |
</phase_requirements>

---

## Summary

Phase 5 has three distinct deliverables: (1) a contributor-side shell script `scripts/record-demo.sh` that automates the terminal recording and GIF conversion, (2) a committed binary artifact `.github/assets/demo.gif`, and (3) edits to `README.md` and `.github/workflows/ci.yml`.

The automation strategy (D-05) uses `expect` to spawn `asciinema rec` and then programmatically "type" the commands. The critical insight confirmed by the Waleed Khan blog pattern is: **the expect script is the outer process — it spawns `asciinema rec` via `spawn`, then types into the recorded shell.** This is the only approach that makes asciinema actually record the characters as they appear to be typed. Using `asciinema rec -c expect_script.sh` would record the expect binary's output, which is not what we want.

**Important version finding:** Homebrew ships asciinema **3.2.0** (the current stable). In v3.0, `--cols`/`--rows` were replaced with a single `--window-size COLSxROWS` flag. The plan must use `--window-size` not `--cols`/`--rows`. The Debian man page (v2.x) still shows the old flags — do not rely on it. [VERIFIED: asciinema/CHANGELOG.md on GitHub]

**CI strategy:** demo.gif is committed to git before CI runs. The CI check `test -s .github/assets/demo.gif` simply guards against accidental deletion or empty replacement. `asciinema`/`agg`/`expect` are **not** installed in CI — and do not need to be.

**Primary recommendation:** Write `record-demo.sh` using the `spawn asciinema rec` inside expect pattern with `send -h` for human-like typing. Generate demo.gif locally, commit it, then add a one-liner file-existence check to the `test` job in CI.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Recording automation | Developer machine (local) | — | asciinema/expect/agg are contributor tools, not CI tools |
| GIF artifact | Git repository (.github/assets/) | — | Committed binary; served directly from GitHub by README img tag |
| README embed | Static file (README.md) | — | Markdown img tag referencing the committed asset |
| CI gate | CI (test job) | — | Asserts committed gif exists and is non-empty; never regenerates |

---

## Standard Stack

### Core Toolchain (contributor machine — not CI deps)

| Tool | Version | Purpose | Install |
|------|---------|---------|---------|
| asciinema | 3.2.0 | Records terminal session to `.cast` file | `brew install asciinema` |
| agg | 1.8.1 | Converts `.cast` to animated GIF | `brew install agg` |
| expect | 5.45.4 | Automates interactive shell input; drives asciinema | `brew install expect` (macOS); `apt install expect` (Linux) |

[VERIFIED: homebrew-core — all three formulae confirmed in `homebrew-core` via `brew info`]

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| expect (TCL) | pexpect (Python) | pexpect is Python-only; adds a Python dep; TCL expect is on every POSIX system |
| asciinema → agg | termtosvg | termtosvg unmaintained (last release ~2019); SVG embed doesn't work in GitHub README markdown (locked decision D-06) |
| git-committed gif | GitHub Actions with matrix | CI generation requires asciinema/agg/expect in CI environment — complex setup for a cosmetic artifact |

### Installation (contributor machine only)

```bash
# macOS
brew install asciinema agg expect

# Ubuntu/Debian
sudo apt install asciinema expect
# agg: download binary from https://github.com/asciinema/agg/releases
# or: cargo install --git https://github.com/asciinema/agg

# Verify
asciinema --version   # expect: 3.x
agg --version         # expect: 1.x
expect -version       # expect: 5.45.x
```

---

## Package Legitimacy Audit

These are system tools installed via OS package managers, not npm/PyPI packages. Slopcheck scanned the PyPI names as a proxy check; primary verification is via `homebrew-core` membership.

| Tool | Registry | Age | Source Repo | slopcheck (PyPI proxy) | Disposition |
|------|----------|-----|-------------|------------------------|-------------|
| asciinema | homebrew-core | 10+ yrs | github.com/asciinema/asciinema | [OK] | Approved |
| agg | homebrew-core | ~3 yrs | github.com/asciinema/agg | [OK] | Approved |
| expect | homebrew-core | 30+ yrs | core.tcl-lang.org/expect | N/A (not on PyPI) | Approved |

**Note:** slopcheck scans PyPI by default; these tools are not pip packages. The `[OK]` result for asciinema and agg on PyPI is a secondary signal only. Primary trust source is homebrew-core membership (canonical, curated registry). [VERIFIED: homebrew-core formulae confirmed via `brew info`]

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

---

## Architecture Patterns

### System Architecture Diagram

```
[Developer machine]
      │
      ▼
scripts/record-demo.sh
      │
      ├─ mktemp -d → DEMO_DIR (isolated temp dir)
      │   ├─ write seed CLAUDE.md + package.json
      │   └─ trap 'rm -rf "$DEMO_DIR"' EXIT
      │
      ├─ write inline-expect-script to $DEMO_DIR/demo.exp
      │
      ├─ expect $DEMO_DIR/demo.exp
      │    └─ (inside expect):
      │        spawn asciinema rec --overwrite --window-size 120x35 $CAST_FILE
      │        expect "$ "  → send -h "conjure init --dry-run --profile=ts-next .\r"
      │        expect "$ "  → send -h "conjure audit\r"
      │        expect "$ "  → send "exit\r"
      │        expect eof
      │
      ├─ agg --speed 1.5 --idle-time-limit 2 --theme dracula \
      │       --cols 120 $CAST_FILE $GIF_FILE
      │
      └─ cp $GIF_FILE .github/assets/demo.gif

[git repo]
      └─ .github/assets/demo.gif  (committed binary, ~1-5 MB)

[GitHub README]
      └─ <img src=".github/assets/demo.gif" ...>
         served directly by GitHub's CDN

[CI: .github/workflows/ci.yml — test job]
      └─ test -s .github/assets/demo.gif   (file-existence gate only)
```

### Recommended Project Structure

No new directories needed. Files added/changed:
```
scripts/
└─ record-demo.sh       # new: contributor recording script

.github/
└─ assets/
   └─ demo.gif          # new: committed binary (replaces nothing; logo.svg stays)

README.md               # edit: replace Quickstart code block with img tag

.github/workflows/
└─ ci.yml               # edit: add test -s assertion to test job
```

### Pattern 1: expect spawns asciinema (the correct integration)

**What:** The outer process is `expect`. It spawns `asciinema rec` as a child process and then drives keystrokes into the recorded shell.

**When to use:** Any time you want asciinema to capture the visual appearance of "a human typing" rather than the output of a batch script.

**Why NOT `asciinema rec -c expect_script.sh`:** That would record the expect binary's own stdout, which produces no visible terminal interaction — you'd get a blank or corrupted cast.

```tcl
# Source: blog.waleedkhan.name/automating-terminal-demos/ (verified pattern)
#!/usr/bin/env expect -f
set timeout 120
# send_human parameters: {min avg max std confidence}
# 0.04 0.08 0.15 0.02 0.5 = fast but visibly human
set send_human {0.04 0.08 0.15 0.02 0.5}

proc expect_prompt {} {
    # Match a shell prompt ending in $ (bash/zsh default)
    expect -re {[\$#]\s*$}
}

# DEMO_DIR and CAST_FILE injected from record-demo.sh via env vars
set demo_dir $env(DEMO_DIR)
set cast_file $env(CAST_FILE)

# Start the asciinema recording
spawn asciinema rec --overwrite --window-size 120x35 $cast_file
expect_prompt

# Command 1: init dry-run
send -h "conjure init --dry-run --profile=ts-next .\r"
expect_prompt

# Brief pause so viewer can read the output
sleep 2

# Command 2: audit
send -h "conjure audit\r"
expect_prompt

sleep 2

# Exit the recorded shell
send "exit\r"
expect eof
```

### Pattern 2: agg conversion with recommended flags

**What:** Convert the `.cast` file produced by asciinema to an animated GIF.

**Recommended flags for a ~45s recording:**
- `--speed 1.5` — 1.5× faster than real-time keeps total GIF under 60s
- `--idle-time-limit 2` — caps any shell pause to 2s (init output has natural pauses)
- `--theme dracula` — high contrast, readable in both light/dark GitHub themes
- No `--cols`/`--rows` override needed at this stage (already set via `--window-size` in asciinema rec)

```bash
# Source: docs.asciinema.org/manual/agg/usage/ (CITED)
agg \
  --speed 1.5 \
  --idle-time-limit 2 \
  --theme dracula \
  "$CAST_FILE" "$GIF_FILE"
```

Note: `agg` also accepts `--cols N` and `--rows N` to override geometry at conversion time if the cast header has wrong values. These differ from asciinema's `--window-size`.

### Pattern 3: record-demo.sh script structure (following regen-fixtures.sh style)

```bash
#!/usr/bin/env bash
# scripts/record-demo.sh — record animated demo of conjure init + audit.
# Usage: bash scripts/record-demo.sh
# Requires: asciinema, agg, expect (contributor machine only — not in CI)
# Output: .github/assets/demo.gif

set -euo pipefail

CONJURE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS_DIR="$CONJURE_HOME/.github/assets"

# Preflight: require the three tools
for dep in asciinema agg expect; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    printf 'record-demo.sh: %s is required but not found.\n' "$dep" >&2
    printf '  macOS:  brew install %s\n' "$dep" >&2
    exit 1
  fi
done

# Isolated temp dir (same pattern as sandbox.sh)
DEMO_DIR="$(mktemp -d)"
CAST_FILE="$DEMO_DIR/demo.cast"
GIF_FILE="$DEMO_DIR/demo.gif"
trap 'rm -rf "$DEMO_DIR"' EXIT

# Write seed files into DEMO_DIR
printf '{"name":"demo","version":"0.0.0"}\n' > "$DEMO_DIR/package.json"
# ... seed CLAUDE.md (same as regen-fixtures pattern) ...

# Write and run expect script
cat > "$DEMO_DIR/demo.exp" <<'EXPECT_SCRIPT'
#!/usr/bin/env expect -f
# ... (expect script body as in Pattern 1 above)
EXPECT_SCRIPT

export DEMO_DIR CAST_FILE
expect "$DEMO_DIR/demo.exp"

# Convert to GIF
agg --speed 1.5 --idle-time-limit 2 --theme dracula "$CAST_FILE" "$GIF_FILE"

# Copy to assets
mkdir -p "$ASSETS_DIR"
cp "$GIF_FILE" "$ASSETS_DIR/demo.gif"

printf '[record-demo] demo.gif written to %s\n' "$ASSETS_DIR/demo.gif"
printf '[record-demo] File size: %s bytes\n' "$(wc -c < "$ASSETS_DIR/demo.gif")"
```

### Pattern 4: README.md edit — Quickstart section

Current state (lines 63–76 of README.md):
```markdown
## 🚀 Quickstart

```bash
# 1. Install
curl -sSL https://raw.githubusercontent.com/mohandoz/conjure/main/install.sh | bash

# 2. Initialize a project (auto-detects new or existing)
cd /path/to/your/repo
conjure init existing --profile=python-fastapi .

# 3. Open Claude Code, paste PROMPT.md, watch the daemon obey
```

That's it. Run `conjure audit` anytime to verify health.
```

Target state (D-09, D-10):
```markdown
## 🚀 Quickstart

<div align="center">
<img src=".github/assets/demo.gif" alt="conjure init --dry-run --profile=ts-next . followed by conjure audit" width="700"/>

*`conjure init --dry-run --profile=ts-next .` — zero mutations, fully auditable.*
</div>

```bash
# 1. Install
...
```
```

Notes on the img tag:
- Width 700 is a standard readable width for GitHub README (renders well on both desktop and mobile).
- `alt` text should describe the recording for accessibility.
- The caption `*...*` is italic markdown per D-10.
- The code block that follows (install instructions) stays — the GIF **replaces** only the three-step example commands block.

### Pattern 5: CI assertion — exact location and syntax

Add to the `test` job in `.github/workflows/ci.yml`, after "Run kit test suite":

```yaml
      - name: Assert demo GIF committed
        run: test -s .github/assets/demo.gif
```

This follows the exact `test -s` syntax from D-08. It goes in the `test` job (not `audit-on-fixture` or `windows-hook-wiring`) because `test` is the main lint+quality gate.

### Anti-Patterns to Avoid

- **Using `asciinema rec -c expect_script.sh`:** Records the expect binary's direct stdout. The recorded shell prompt never appears. Use `spawn asciinema rec` inside the expect script instead.
- **Using `--cols`/`--rows` with asciinema 3.x:** These flags were removed in v3.0. Use `--window-size 120x35` instead. [VERIFIED: asciinema CHANGELOG v3.0]
- **Recording against the real `$HOME`:** The demo must run in `mktemp -d` to avoid capturing developer-specific paths or real `.claude/` state in the recording.
- **Not setting `--overwrite` in asciinema rec:** Without `--overwrite`, a second run of record-demo.sh fails if the cast file already exists in DEMO_DIR. Since DEMO_DIR is fresh each run, this is safe to always include.
- **Committing demo.gif via CI:** Commit-back-from-CI patterns require write tokens and create merge conflicts. Demo is generated locally and committed manually (or in a dedicated PR).
- **Using `--no-loop` in agg by default:** GitHub README gifs loop indefinitely; this is the expected behavior for a demo gif. Do not add `--no-loop`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Terminal session recording | Custom screen capture script | asciinema | Handles PTY, escape codes, timing — non-trivial from scratch |
| Animated GIF from cast | ffmpeg/ImageMagick pipeline | agg | agg uses terminal-aware font rendering; generic video tools produce blurry text |
| Interactive typing simulation | `printf` piped to bash | expect with `send -h` | `printf` doesn't handle interactive prompts; expect waits for specific output before proceeding |
| GIF hosting | External service (s3, imgur) | Committed binary in `.github/assets/` | External links break; GitHub CDN serves committed assets reliably |

---

## Common Pitfalls

### Pitfall 1: asciinema v3 `--window-size` flag change
**What goes wrong:** Script uses `--cols 120 --rows 35` → asciinema 3.x exits with "unknown option" error.
**Why it happens:** `--cols`/`--rows` were removed in asciinema 3.0 (September 2025); replaced with `--window-size COLSxROWS`.
**How to avoid:** Always use `--window-size 120x35` in the asciinema invocation.
**Warning signs:** `asciinema: unknown option '--cols'` in stderr.
[VERIFIED: asciinema CHANGELOG on GitHub, v3.0 entry]

### Pitfall 2: expect prompt matching is too strict
**What goes wrong:** `expect "$ "` waits for a literal space after `$` — fails if the shell prompt uses a different format (e.g., `➜` or `(base) $` in conda envs).
**Why it happens:** The prompt inside the `asciinema rec` shell is the developer's `$SHELL` default, which varies by machine.
**How to avoid:** Use a regex match: `expect -re {[\$#]\s*$}`. This matches both `$ ` and `$ ` at end-of-line. Alternatively, launch a known minimal shell: `spawn asciinema rec -c /bin/sh ...` or set `PS1='$ '` in the expect script via `send "PS1='$ '\r"` before the demo commands.
**Warning signs:** Recording hangs indefinitely or times out.

### Pitfall 3: conjure init prompts block expect
**What goes wrong:** `conjure init` on a directory that already has `.claude/` might ask confirmation questions that expect doesn't handle.
**Why it happens:** init-project.sh has no interactive prompts in `existing` mode, but some paths could trigger it.
**How to avoid:** The demo runs `--dry-run` (D-02) — dry-run mode never writes anything, so it never asks confirmation. Additionally, the temp dir is fresh (no pre-existing `.claude/`).

### Pitfall 4: PATH does not include conjure CLI inside expect-spawned shell
**What goes wrong:** The recorded shell can't find `conjure` — "command not found" appears in the recording.
**Why it happens:** The `asciinema rec` child shell inherits the expect process's environment, which may not have `CONJURE_HOME/cli` in PATH.
**How to avoid:** Set `PATH` before spawning: `set env(PATH) "$conjure_cli_dir:[exec printenv PATH]"` in the expect script, where `conjure_cli_dir` is resolved from `$CONJURE_HOME/cli`. Or export PATH explicitly before calling `expect`.
**Warning signs:** "conjure: command not found" in the cast playback.

### Pitfall 5: GIF file size bloat
**What goes wrong:** demo.gif is 20+ MB — too large to commit and slows README load.
**Why it happens:** Long recording (>60s), high FPS cap, or no idle-time-limit.
**How to avoid:** Use `--idle-time-limit 2` (caps pauses at 2s), `--speed 1.5` (speeds up replay), and keep total recording under 60s real-time. Target GIF size < 5 MB.
**Warning signs:** `wc -c demo.gif` > 5,000,000 bytes.

### Pitfall 6: CI fails on missing demo.gif before first commit
**What goes wrong:** PR without a committed demo.gif fails `test -s .github/assets/demo.gif`.
**Why it happens:** The file is generated locally and committed manually.
**How to avoid:** Commit demo.gif in the same PR as the CI assertion. The plan must order: (1) generate and commit demo.gif, (2) add CI assertion. Or use `|| true` on the CI step during the setup PR only.

---

## Code Examples

### Minimal working expect script

```tcl
# Source: blog.waleedkhan.name/automating-terminal-demos/ — verified pattern
#!/usr/bin/env expect -f
set timeout 120
set send_human {0.04 0.08 0.15 0.02 0.5}

proc expect_prompt {} {
    expect -re {[\$#]\s*$}
}

spawn asciinema rec --overwrite --window-size 120x35 $env(CAST_FILE)
expect_prompt

send -h "conjure init --dry-run --profile=ts-next .\r"
expect_prompt
sleep 2

send -h "conjure audit\r"
expect_prompt
sleep 2

send "exit\r"
expect eof
```

### agg conversion

```bash
# Source: docs.asciinema.org/manual/agg/ [CITED]
agg \
  --speed 1.5 \
  --idle-time-limit 2 \
  --theme dracula \
  "$CAST_FILE" \
  "$GIF_FILE"
```

### README img embed

```markdown
<div align="center">
<img src=".github/assets/demo.gif" alt="conjure init --dry-run --profile=ts-next . then conjure audit" width="700"/>

*`conjure init --dry-run --profile=ts-next .` — zero mutations, fully auditable.*
</div>
```

### CI assertion (yaml snippet)

```yaml
      - name: Assert demo GIF committed
        run: test -s .github/assets/demo.gif
```

---

## Demo Output Reference

The demo will show the following output sequence (verified by running both commands in this session):

**Command 1: `conjure init --dry-run --profile=ts-next .`**

Produces approximately 50 lines of output:
- Pre-flight checks header + dep table (node ✓, git ✓, jq ✓, etc.)
- `▸ conjure init: mode=existing profile=ts-next target=... dry_run=1`
- Per-file `[dry-run] would ...` + `✓ created ...` lines (~40 lines)
- `45 mutations skipped` summary
- "Scaffold complete / Next steps" box
- Profile ts-next applied confirmation + `1 mutations skipped`
- Version stamp line + `1 mutations skipped`

**Command 2: `conjure audit`**

Produces approximately 22 lines:
- Pre-flight checks header + dep table
- `Auditing .claude/ setup in: ...`
- 17 `✓` check lines
- Final summary: `PASS: 17    WARN: 0    FAIL: 0`

**Estimated total recording time at 1× speed:** ~40-50 seconds real-time (mostly output scrolling). With `--speed 1.5` the GIF plays back in ~28-35 seconds — well within D-03's 60-second target.

[VERIFIED: output confirmed by running both commands against ts-next fixture in this session]

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `asciinema rec --cols N --rows N` | `asciinema rec --window-size NxM` | asciinema 3.0 (Sep 2025) | Scripts written for v2 will fail on Homebrew-installed v3 |
| asciicast2gif (Docker-based) | agg (Rust binary) | ~2022 | agg is the official successor; faster, no Docker needed |
| termtosvg | agg | ~2020 | termtosvg unmaintained; SVG not renderable in GitHub markdown |

**Deprecated:**
- `--cols`/`--rows` flags for `asciinema rec`: removed in v3.0; use `--window-size` [VERIFIED: asciinema CHANGELOG]
- asciicast2gif: still functional but superseded by agg; no longer maintained by asciinema team [ASSUMED]

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `agg` with `--speed 1.5` and `--idle-time-limit 2` keeps total GIF duration under 60s | Standard Stack / Pitfall 5 | Recording may exceed 60s; adjust `--speed` up to 2.0 if needed |
| A2 | GIF file size will be under 5 MB with recommended flags | Pitfall 5 | May need to increase speed or reduce window size |
| A3 | `agg --theme dracula` renders well in GitHub's light/dark modes | Code Examples | May need to test visually and switch to `github-dark` or `monokai` |
| A4 | asciicast2gif is no longer maintained by the asciinema team | State of the Art | Low-risk assumption; agg is the documented official successor |

**Confidence on all other claims:** HIGH — verified via Homebrew formula check, CHANGELOG, direct command execution, and official documentation.

---

## Open Questions

1. **Prompt pattern in expect**
   - What we know: Standard bash prompt ends in `$ ` but macOS zsh default uses `%` and fish uses `>`
   - What's unclear: Which shell `asciinema rec` spawns inside the expect session (it uses the user's `$SHELL`)
   - Recommendation: Set `PS1='$ '` explicitly as first command in the recorded shell, before the demo commands. This costs ~1 second but makes the expect `expect -re {[\$#]\s*$}` pattern reliable.

2. **Where in README.md to place the img tag (exact line)**
   - What we know: `## 🚀 Quickstart` heading is at line 63; code block ends around line 76; `That's it. Run...` is line 78
   - What's unclear: Whether to replace only the three-step code block or also the `That's it.` sentence
   - Recommendation: Replace lines 65–76 (the code block), keep the `That's it.` sentence below the image. This preserves the narrative flow.

3. **expect availability on Linux CI (if CI check is ever expanded)**
   - What we know: CI currently uses ubuntu-latest which has `expect` in apt
   - What's unclear: Whether a future contributor will try to regenerate demo in CI
   - Recommendation: Document in a comment in `record-demo.sh` that this script is contributor-only and intentionally absent from CI.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| asciinema | record-demo.sh | ✗ (not installed) | — | Install: `brew install asciinema` |
| agg | record-demo.sh | ✗ (not installed) | — | Install: `brew install agg` |
| expect | record-demo.sh | ✓ | 5.45 | Pre-installed on macOS; `brew install expect` if missing |
| bash | record-demo.sh | ✓ | 3.2 (macOS) | — |
| git | CI + commit step | ✓ | system | — |

**Missing dependencies with no fallback:**
- `asciinema` and `agg` are required on the contributor machine to regenerate the GIF. CI never calls record-demo.sh so they are not CI blockers.

**Missing dependencies with fallback:**
- None blocking CI execution.

**CI note:** `.github/workflows/ci.yml` `test` job installs only `jq` and `shellcheck` via apt. It does **not** install asciinema/agg/expect — and does not need to. The `test -s .github/assets/demo.gif` check requires only that the file was committed by the developer.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Hand-rolled `tests/run.sh` (project convention) |
| Config file | `tests/run.sh` |
| Quick run command | `bash tests/run.sh` |
| Full suite command | `bash tests/run.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DOCS-01 | demo.gif exists and is non-empty in repo | smoke | `test -s .github/assets/demo.gif` | ✅ (CI step) |
| DOCS-01 | demo.gif is a valid GIF (magic bytes) | smoke | `file .github/assets/demo.gif \| grep GIF` | ❌ Wave 0 (optional) |

**Note:** The primary automated gate is the CI `test -s` check. A local `file` magic-bytes check is optional defense-in-depth. Tests for `record-demo.sh` itself (shellcheck, preflight behavior) are lightweight and belong in the existing shellcheck CI step.

### Sampling Rate

- **Per task commit:** `bash tests/run.sh` (175 existing tests must stay green; record-demo.sh shellcheck via CI lint step)
- **Per wave merge:** `bash tests/run.sh` + visual inspection of demo.gif
- **Phase gate:** Full suite green + demo.gif committed and non-empty

### Wave 0 Gaps

- [ ] `test -s .github/assets/demo.gif` is not in tests/run.sh yet — added via CI yaml edit (D-08)
- No new test framework needed; existing `tests/run.sh` does not need changes for this phase

*(No gaps in test infrastructure — this phase is primarily a file creation + CI assertion.)*

---

## Security Domain

This phase has no authentication, network egress, input validation, or cryptography concerns. The only security-relevant surface is the committed binary:

- **demo.gif is a committed binary.** It is read by GitHub's CDN, not executed. No code execution risk.
- **record-demo.sh runs `expect` which spawns subprocesses.** Runs only on contributor machines, not in CI. The script uses `mktemp -d` + `trap EXIT` for isolation — no leakage to developer's real `$HOME`.
- **ASVS categories:** None applicable (no authentication, sessions, access control, or cryptography in scope).

---

## Sources

### Primary (HIGH confidence)
- `asciinema/CHANGELOG.md` (GitHub) — confirmed `--window-size` flag change in v3.0 replacing `--cols`/`--rows`
- `brew info asciinema` — version 3.2.0 confirmed in homebrew-core
- `brew info agg` — version 1.8.1 confirmed in homebrew-core
- `brew info expect` — version 5.45.4 confirmed in homebrew-core
- Direct command execution: `conjure init --dry-run --profile=ts-next` and `conjure audit` — output content verified in this session
- Debian man page (asciinema v2.x) — `--command/-c`, `--stdin`, `--overwrite` flags confirmed
- `docs.asciinema.org/manual/agg/usage/` — agg `--speed`, `--idle-time-limit`, `--theme`, `--cols`, `--rows` flags confirmed [CITED]

### Secondary (MEDIUM confidence)
- blog.waleedkhan.name/automating-terminal-demos/ — `spawn asciinema rec` inside expect pattern (community source, technically verified against expect docs)
- Homebrew formula pages for agg and asciinema — installation commands confirmed

### Tertiary (LOW confidence)
- asciicast2gif unmaintained claim — based on training knowledge [ASSUMED]

---

## Metadata

**Confidence breakdown:**
- Standard stack (asciinema, agg, expect): HIGH — all confirmed via homebrew-core
- v3 flag change (`--window-size`): HIGH — confirmed via CHANGELOG
- expect scripting pattern: MEDIUM — community source verified against expect docs; actual invocation needs smoke test on dev machine
- Architecture (GIF size, timing): MEDIUM/LOW — timing estimates based on observed output length; real values depend on machine speed

**Research date:** 2026-05-25
**Valid until:** 2026-11-25 (stable toolchain; asciinema v3 flag change already captured)
