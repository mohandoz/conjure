---
phase: quick
plan: 260605-sdw
type: execute
wave: 1
depends_on: []
files_modified:
  - Makefile
autonomous: true
requirements: [QK-SDW-260605]

must_haves:
  truths:
    - "make install symlinks cli/conjure into BINDIR (~/.local/bin by default)"
    - "conjure version runs after install without sudo"
    - "make uninstall removes the symlink cleanly"
    - "PREFIX and BINDIR variables can override the install destination"
    - "make (or make help) lists all targets"
  artifacts:
    - path: "Makefile"
      provides: "install, uninstall, help targets"
      contains: "BINDIR"
  key_links:
    - from: "Makefile install target"
      to: "cli/conjure"
      via: "ln -sf $(CURDIR)/cli/conjure $(BINDIR)/conjure"
      pattern: "ln -sf"
---

<objective>
Add a Makefile to the repo root so contributors can run `make install` to get a
live-reloading symlink of `cli/conjure` on their PATH for local development,
without cloning into ~/.conjure or touching any other files.

Purpose: Eliminate the "conjure: command not found" friction for contributors
working from a checkout. The symlink means edits in cli/conjure are immediately
live — no re-install step needed.

Output: Makefile with install, uninstall, and help targets.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/quick/260605-sdw-add-makefile-with-install-uninstall-targ/260605-sdw-PLAN.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create Makefile with install, uninstall, and help targets</name>
  <files>Makefile</files>
  <action>
Create `Makefile` in the repo root. Key design rules:

**Variables (top of file):**
- `PREFIX ?= $(HOME)/.local` — conventional override root
- `BINDIR ?= $(PREFIX)/bin` — where the symlink lands
- `REPO_ROOT := $(CURDIR)` — absolute path to repo, used in symlink target so the symlink is absolute and works regardless of cwd

**Targets:**

`help` (default target, first in file so bare `make` prints it):
- Print a short usage block listing all targets with descriptions.
- Use `@printf` or `@echo` for each line; no external tool required.
- Mark as `.PHONY`.

`install`:
- Mark `.PHONY`.
- Recipe steps (each line prefixed with a tab, using `@` to suppress echo where appropriate):
  1. `chmod +x $(REPO_ROOT)/cli/conjure` — ensure executable bit set.
  2. `mkdir -p $(BINDIR)` — create BINDIR if not present.
  3. `ln -sf $(REPO_ROOT)/cli/conjure $(BINDIR)/conjure` — create/replace symlink. `-f` makes it idempotent.
  4. Print a confirmation line: "installed: $(BINDIR)/conjure -> $(REPO_ROOT)/cli/conjure".
  5. PATH check — use a shell one-liner:
     ```
     @case ":$$PATH:" in \
       *":$(BINDIR):"*) printf "  conjure version: $$($(BINDIR)/conjure version)\n" ;; \
       *) printf "  NOTE: $(BINDIR) is not on PATH. Add to your shell rc:\n"; \
          printf "    export PATH=\"$(BINDIR):\$$PATH\"\n" ;; \
     esac
     ```
     This avoids invoking `conjure` bare (which would fail if BINDIR not on PATH yet) and instead invokes the full symlink path for verification.

`uninstall`:
- Mark `.PHONY`.
- Recipe: `rm -f $(BINDIR)/conjure` then print "uninstalled: $(BINDIR)/conjure".

**Compatibility notes:**
- Use only POSIX make features: `?=`, `:=`, `.PHONY`, tab-indented recipes, `@`.
- Do NOT use `$(shell ...)` with `command -v` in a way that requires GNU make 4+; the PATH check runs in the recipe shell, not in make's variable expansion.
- macOS ships GNU make 3.81 — `?=` and `:=` are safe; no `!=` (BSD-only) and no `$(shell )` at variable assignment level beyond CURDIR.
- No `.DEFAULT_GOAL` directive needed; first target is `help` which is the default.

Do not add a `.PHONY: all` or an `all` target — it is unused and confusing for a tool repo.
  </action>
  <verify>
    <automated>cd /Users/mohandoz/u01/innovate/conjure && make --dry-run install 2>&1 | grep -q "ln -sf" && echo "PASS: ln -sf present" || echo "FAIL: ln -sf missing"</automated>
  </verify>
  <done>
- `Makefile` exists at repo root.
- `make --dry-run install` shows `ln -sf` step and `chmod +x` step.
- `make --dry-run uninstall` shows `rm -f` step.
- `make help` (or bare `make`) prints the target list without error.
- `make install BINDIR=/tmp/test-conjure-bin` creates symlink at `/tmp/test-conjure-bin/conjure` pointing to `cli/conjure` in the repo.
  </done>
</task>

<task type="auto">
  <name>Task 2: Smoke-test install end-to-end</name>
  <files></files>
  <action>
Run a self-contained smoke test using a temp BINDIR to verify the full install/uninstall cycle without touching the user's real PATH:

1. Create a temp dir: `TMPBIN=$(mktemp -d)`.
2. Run `make install BINDIR="$TMPBIN"` from repo root. Capture output.
3. Verify symlink was created: `test -L "$TMPBIN/conjure"`.
4. Verify the symlink resolves to cli/conjure in the repo: `readlink "$TMPBIN/conjure"` should contain `cli/conjure`.
5. Verify `conjure version` works via full path: `"$TMPBIN/conjure" version` exits 0 and prints a version string.
6. Run `make uninstall BINDIR="$TMPBIN"` and verify `$TMPBIN/conjure` no longer exists.
7. Clean up: `rm -rf "$TMPBIN"`.

If any step fails, print what failed and exit 2 (per project conventions for script-level failures). Report PASS/FAIL at the end.

This smoke test is run manually by the executor — it is not added to tests/run.sh (the install infra is dev-environment tooling, not a fixture-testable unit).
  </action>
  <verify>
    <automated>
cd /Users/mohandoz/u01/innovate/conjure && \
TMPBIN=$(mktemp -d) && \
make install BINDIR="$TMPBIN" >/dev/null 2>&1 && \
test -L "$TMPBIN/conjure" && \
"$TMPBIN/conjure" version >/dev/null 2>&1 && \
make uninstall BINDIR="$TMPBIN" >/dev/null 2>&1 && \
test ! -e "$TMPBIN/conjure" && \
rm -rf "$TMPBIN" && \
echo "PASS: install/uninstall cycle verified" || echo "FAIL: smoke test failed"
    </automated>
  </verify>
  <done>
- `make install BINDIR=<tmpdir>` creates a working symlink.
- `<tmpdir>/conjure version` exits 0 and prints a version string.
- `make uninstall BINDIR=<tmpdir>` removes the symlink.
- No files outside BINDIR were modified.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| make recipe → filesystem | Symlink creation in user-controlled BINDIR; no privilege escalation |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-SDW-01 | Tampering | ln -sf target | accept | Symlink points to $(CURDIR)/cli/conjure (absolute, repo-local); attacker would need write access to the checkout already |
| T-SDW-02 | Elevation of Privilege | BINDIR default | accept | Default is ~/.local/bin (user-owned); sudo never required; PREFIX override is user-initiated |
</threat_model>

<verification>
Run both automated verify commands above in sequence. Full pass means:
1. `make --dry-run install` prints the ln -sf line.
2. The smoke-test cycle exits 0 and prints "PASS".
</verification>

<success_criteria>
- `make install` works from a fresh checkout with no arguments and no sudo.
- `conjure version` runs correctly when BINDIR is on PATH.
- When BINDIR is not on PATH, the exact `export PATH=...` line is printed.
- `make uninstall` removes the symlink.
- `make` (no target) prints a help/usage listing.
- Bare `make install BINDIR=<custom>` installs to the custom dir.
</success_criteria>

<output>
Create `.planning/quick/260605-sdw-add-makefile-with-install-uninstall-targ/260605-sdw-SUMMARY.md` when done.
</output>
