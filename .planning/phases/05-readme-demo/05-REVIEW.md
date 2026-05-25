---
phase: 05-readme-demo
reviewed: 2026-05-25T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - scripts/record-demo.sh
  - .github/workflows/ci.yml
  - README.md
findings:
  critical: 1
  warning: 2
  info: 2
  total: 5
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-05-25
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Three deliverables were reviewed: the contributor recording script
(`scripts/record-demo.sh`), the updated CI workflow
(`.github/workflows/ci.yml`), and the Quickstart section of `README.md`.

The shell script has a correctness defect that causes the demo to record
against the invoker's current directory instead of the seeded isolated
environment. The CI workflow has a dead-code step that runs the audit
script twice. Two info-level observations cover a missing error message in
a CI assertion and a minor README markup inconsistency.

---

## Critical Issues

### CR-01: expect script records against invoker CWD, not isolated DEMO_DIR

**File:** `scripts/record-demo.sh:63-91` (expect heredoc) / `scripts/record-demo.sh:80`

**Issue:** The bash script seeds a clean ts-next scenario in `$DEMO_DIR`
(package.json + CLAUDE.md, lines 40-58) and then writes an expect script to
`$DEMO_DIR/demo.exp`. However, the expect script never changes to `$DEMO_DIR`
before sending the demo commands. The shell that asciinema spawns inherits
whatever directory the contributor invoked the script from (typically the
conjure repo root). When line 80 sends:

```
conjure init --dry-run --profile=ts-next .
```

the `.` refers to the repo root — not `$DEMO_DIR`. The seeded `package.json`
and `CLAUDE.md` files are completely ignored. The recorded output reflects the
actual repo structure rather than the intended clean ts-next fixture.

Additionally, `DEMO_DIR` is never exported (only `CAST_FILE` is exported,
line 94), so the expect script cannot reference `$env(DEMO_DIR)` even if it
tried.

**Fix:** Export `DEMO_DIR` and insert a `cd` command into the expect script
before the demo commands. Change line 94 and the expect heredoc as follows:

```bash
# line 94 — export both
export CAST_FILE
export DEMO_DIR
```

Inside the heredoc (after the PS1 normalization block, before the conjure
commands):

```tcl
# Navigate to the isolated demo directory
send "cd $env(DEMO_DIR)\r"
expect_prompt
```

The full corrected command sequence in the heredoc becomes:

```tcl
send "PS1='$ '\r"
expect_prompt

send "cd $env(DEMO_DIR)\r"
expect_prompt

# D-02: Command 1 — init dry-run
send -h "conjure init --dry-run --profile=ts-next .\r"
expect_prompt
sleep 2
```

---

## Warnings

### WR-01: audit-on-fixture job runs audit-setup.sh twice — first run is dead code

**File:** `.github/workflows/ci.yml:51-55`

**Issue:** The "Audit fixture" step executes `audit-setup.sh` twice
back-to-back. The first invocation (line 52) discards all output with `|| true`
and has no observable effect. The second invocation (lines 54-55) is the real
check — it captures output to `/tmp/audit.log` and greps for `PASS:`. The
first run wastes CI time, obscures intent, and can mask side effects if the
script mutates state on first run.

```yaml
# Current (lines 51-55) — first run is dead code:
bash "$GITHUB_WORKSPACE/scripts/audit-setup.sh" /tmp/fixture || true
# Verify the script ran without crashing — that's the real CI check.
bash "$GITHUB_WORKSPACE/scripts/audit-setup.sh" /tmp/fixture > /tmp/audit.log 2>&1 || true
grep -q "PASS:" /tmp/audit.log
```

**Fix:** Remove the dead first invocation:

```yaml
- name: Audit fixture
  run: |
    # Fresh fixture has no CLAUDE.md yet. Accept any exit code.
    bash "$GITHUB_WORKSPACE/scripts/audit-setup.sh" /tmp/fixture > /tmp/audit.log 2>&1 || true
    grep -q "PASS:" /tmp/audit.log
```

---

### WR-02: "Assert demo GIF committed" step produces no diagnostic output on failure

**File:** `.github/workflows/ci.yml:33-34`

**Issue:** The step uses `test -s .github/assets/demo.gif` bare. When the
file is missing or empty, the step fails with exit code 1 and no output in
the CI log. Contributors and maintainers will see only "Process exited with
code 1" with no guidance on what to do.

**Fix:** Wrap in an explicit error message:

```yaml
- name: Assert demo GIF committed
  run: |
    test -s .github/assets/demo.gif || {
      echo "ERROR: .github/assets/demo.gif is missing or empty."
      echo "Run 'bash scripts/record-demo.sh' on a machine with asciinema/agg/expect and commit the result."
      exit 1
    }
```

---

## Info

### IN-01: Quickstart div block lacks blank line after opening tag (inconsistent with top-of-file div)

**File:** `README.md:65-69`

**Issue:** The top-of-file `<div align="center">` (line 1) has a blank line
after the tag before the `<img>` — this is the pattern that GitHub's cmark-gfm
parser uses to allow markdown rendering within the block. The Quickstart div
(line 65) omits the blank line:

```html
<div align="center">
<img src=".github/assets/demo.gif" .../>

*`conjure init ...`*
</div>
```

GitHub currently renders the italic caption (`*...*`) correctly, but the
omission of a blank line after `<div align="center">` is inconsistent with the
established pattern in the same file and relies on GitHub-specific lenient
parsing. If rendered by a strict GFM renderer (e.g., pandoc, mkdocs), the
italic markers may appear as literal asterisks.

**Fix:** Add a blank line after the opening `<div>` tag:

```html
<div align="center">

<img src=".github/assets/demo.gif" alt="conjure init --dry-run --profile=ts-next . then conjure audit" width="700"/>

*`conjure init --dry-run --profile=ts-next .` — zero mutations, fully auditable.*
</div>
```

---

### IN-02: sleep inside expect script pads blank screen time after prompt returns

**File:** `scripts/record-demo.sh:82,87`

**Issue:** `sleep 2` appears after `expect_prompt` on both demo commands (lines
82 and 87). `expect_prompt` already blocks until the shell prompt is visible,
so the sleeps do not improve timing reliability — they only add 4 cumulative
seconds of blank-prompt screen to the cast before the next command is typed.
This increases the recorded GIF duration and adds idle frames that `agg
--idle-time-limit 2` then has to cap anyway, partially defeating the flag.

**Fix:** Move each `sleep` to immediately after the `send -h` line and before
`expect_prompt`, so the delay gives the command time to produce output rather
than padding after the prompt has already returned:

```tcl
send -h "conjure init --dry-run --profile=ts-next .\r"
sleep 2
expect_prompt

send -h "conjure audit\r"
sleep 2
expect_prompt
```

---

_Reviewed: 2026-05-25_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
