# Phase 14: Docker + Windows CI - Research

**Researched:** 2026-05-26
**Domain:** Docker multi-arch image authoring, GitHub Actions CI matrix extension
**Confidence:** HIGH

## Summary

Phase 14 has two independent workstreams: (1) build a multi-arch Docker image for
Conjure on `debian:bookworm-slim`, and (2) extend the GitHub Actions CI matrix to
run `tests/run.sh` on `windows-latest` via Git Bash.

The Docker image is straightforward — Node.js LTS can be installed on
`debian:bookworm-slim` via the NodeSource `setup_22.x` script, `jq` and
`shellcheck` install cleanly from apt, and the install layout mirrors the
Homebrew formula exactly. Estimated uncompressed image size is ~160–175 MB, safely
under the 200 MB cap. Multi-arch builds in GitHub Actions require QEMU +
`docker/setup-docker-action` (for containerd snapshotter) + `docker/setup-buildx-action`
+ `docker/build-push-action` with `load: true`. Critical: loading a multi-platform
image locally requires the containerd snapshotter feature; without it only single-
platform `--load` works.

The Windows CI extension is lower-risk than it appears. Git Bash on `windows-latest`
ships with GNU coreutils (including `seq`), `ruby` (3.3.11), `python3` (3.12.10),
`jq` (1.8.1), and `node` — all tools `tests/run.sh` needs. `shellcheck` is not
preinstalled, but `tests/run.sh` already treats it as optional. The only required CI
step change is installing `jq` and `shellcheck` for Ubuntu (already done); for
Windows we add `choco install shellcheck` to make the `shellcheck` preflight test
pass its full path. Actually, `tests/run.sh` handles `shellcheck` absence gracefully
(lines 151–159), so even that is not strictly required — the preflight test passes
either way. The full `tests/run.sh` suite should run on Windows unmodified.

**Primary recommendation:** Write a single `Dockerfile`, one `docker.yml` workflow
(workflow_dispatch, containerd snapshotter enabled, multi-arch load), and extend
`ci.yml` with a `windows-test` job that runs `bash tests/run.sh` after checking out
the repo (no extra deps needed — all are preinstalled on `windows-latest`).

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Base image is `debian:bookworm-slim`.
- **D-02:** Runtime deps: `jq`, `shellcheck`, Node.js LTS via NodeSource.
- **D-03:** Non-root: `RUN useradd -m -u 1000 conjure` + `USER conjure`.
- **D-04:** `docker.yml` uses `workflow_dispatch` only (no automatic push/PR trigger in Phase 14).
- **D-05:** `docker.yml` validates: build image, run `conjure version` smoke test, run `conjure audit` against mounted fixture. Phase 14 does NOT push to ghcr.io.
- **D-06:** Users pass `--user $(id -u):$(id -g)` for mounted-volume file ownership. No gosu/su-exec.
- **D-07:** README `## Docker` section placed after the Homebrew section. Documents three volume-mount forms (bash/zsh, PowerShell, cmd).
- **D-08:** Windows CI: add `windows-latest` job to `ci.yml`. Full `tests/run.sh` with `shell: bash`. Extend, not duplicate, the existing `windows-hook-wiring` job.
- **D-09:** Windows CI scope: all 265 existing tests with `shell: bash`. No new Windows-specific test code in Phase 14.

### Claude's Discretion

- Multi-arch build strategy: `docker buildx` with `--platform linux/amd64,linux/arm64`. Exact builder setup in CI is Claude's call.
- WORKDIR inside container: `/work`.
- Entrypoint: thin wrapper or `ENV CONJURE_HOME=...` + direct `ENTRYPOINT` — Claude's call as long as `conjure` is on PATH.
- Image size verification: `docker image inspect` in docker.yml smoke test.

### Deferred Ideas (OUT OF SCOPE)

- Docker image publishing to `ghcr.io` with semantic version tags — Phase 15.
- `release.yml` wiring for Docker multi-arch build + push — Phase 15.
- Action SHA pinning for docker.yml actions (WR-01 from Phase 13 review) — Phase 15.
</user_constraints>

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Docker image build | CI (docker.yml) | Local dev | Image is a CI artifact; build script lives in Dockerfile |
| CONJURE_HOME resolution | Container (Dockerfile ENV) | Wrapper script | Must be set before `cli/conjure` runs |
| Non-root execution | Dockerfile (USER) | Docker run flags | UID baked in image; ownership via `--user` at runtime |
| Volume file ownership | Caller (`--user` flag) | — | No gosu; D-06 locked |
| Multi-arch cross-compilation | QEMU (CI) | buildx | ARM64 emulated on amd64 runner |
| Windows test execution | GitHub Actions (ci.yml) | Git Bash | shell: bash routes through Git Bash |
| Tests/run.sh execution | Shell (bash) | — | Self-contained; no CI-specific dependencies |

---

## Dockerfile

### Install Layout

The Homebrew formula installs: `cli`, `scripts`, `profiles`, `compliance`,
`migrations`, `templates`, `lib`, `VERSION` into `share/conjure/` and wraps with
a shim that sets `CONJURE_HOME`. The Docker image mirrors this exactly:

```
CONJURE_HOME=/usr/local/share/conjure
```

Files copied from repo root: `cli/`, `scripts/`, `profiles/`, `compliance/`,
`migrations/`, `templates/`, `lib/`, `VERSION`.

Executable placed at `/usr/local/bin/conjure` (thin wrapper or symlink).
WORKDIR set to `/work` (maps to user's `$(pwd)` via `-v $(pwd):/work`).

### Node.js LTS Selection

[VERIFIED: nodejs.org release schedule] As of May 2026:
- Node 22 (22.x): LTS maintenance, EOL April 2027
- Node 24 (24.x): Active LTS since October 2025, EOL April 2028

Node 22 is the safer choice — it matches what the CI runs implicitly (ubuntu-latest
ships Node 18–22) and has broader compatibility. Use NodeSource `setup_22.x`.

[ASSUMED] Node 24 (`setup_24.x`) would also work but has less ecosystem soak time.

### Exact apt-get Commands (Dockerfile RUN layer) [VERIFIED: nodesource/distributions, CI experience]

```dockerfile
RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl gnupg \
       jq shellcheck \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
```

**Why single layer:** Combining all installs + cleanup in one RUN keeps that
layer's net size minimal (apt cache is removed before the layer is committed).

**Known NodeSource pitfall on Bookworm:** On Debian 12, the default `debian`
repo ships an older `nodejs` package. Always run the NodeSource setup script
before `apt-get install nodejs`; the setup script pins priority 600 for the
NodeSource package so apt prefers it. [CITED: github.com/nodesource/distributions/issues/1601]

### Full Dockerfile Structure

```dockerfile
FROM debian:bookworm-slim

# Install deps in one layer to minimize size
RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl gnupg \
       jq shellcheck \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user (DOCK-02, D-03)
RUN useradd -m -u 1000 -s /bin/bash conjure

# Install conjure kit (mirrors Homebrew formula layout)
ENV CONJURE_HOME=/usr/local/share/conjure
COPY cli/       $CONJURE_HOME/cli/
COPY scripts/   $CONJURE_HOME/scripts/
COPY profiles/  $CONJURE_HOME/profiles/
COPY compliance/ $CONJURE_HOME/compliance/
COPY migrations/ $CONJURE_HOME/migrations/
COPY templates/ $CONJURE_HOME/templates/
COPY lib/       $CONJURE_HOME/lib/
COPY VERSION    $CONJURE_HOME/VERSION

# Make CLI executable and put it on PATH
RUN chmod +x $CONJURE_HOME/cli/conjure \
    && printf '#!/bin/bash\nexport CONJURE_HOME=%s\nexec %s/cli/conjure "$@"\n' \
       "$CONJURE_HOME" "$CONJURE_HOME" > /usr/local/bin/conjure \
    && chmod +x /usr/local/bin/conjure

# Switch to non-root user
USER conjure

WORKDIR /work

ENTRYPOINT ["conjure"]
```

### Entrypoint Decision

**Chosen: thin shell wrapper at `/usr/local/bin/conjure`** (matches Homebrew pattern
exactly). The wrapper sets `CONJURE_HOME` and `exec`s the real script. This means:

- `docker run conjure:local conjure version` works (ENTRYPOINT + CMD)
- `docker run --entrypoint bash conjure:local` still works for debugging
- No `ENTRYPOINT ["bash", "-c"]` awkwardness

Alternative (`ENV CONJURE_HOME + ENTRYPOINT ["cli/conjure"]`) was rejected: it
puts `cli/conjure` on the ENTRYPOINT which requires knowing the full path and
breaks if CONJURE_HOME is ever remapped.

### .dockerignore

To exclude test artifacts, planning files, and node_modules (none here but for safety):

```
.planning/
tests/output/
tests/tmp/
.git/
*.gif
.github/
Formula/
examples/
reference/
checklists/
CHANGELOG.md
CODE_OF_CONDUCT.md
CODEOWNERS
COMPARISON.md
CONTRIBUTING.md
FAILURE-MODES.md
MIGRATION-GUIDE.md
PROMPT.md
SECURITY.md
SUPPORT.md
TELEMETRY.md
install.sh
```

### Layer Size Estimate [ASSUMED — based on public Docker Hub data]

| Layer | Approx Uncompressed |
|-------|---------------------|
| debian:bookworm-slim base | ~75 MB |
| ca-certificates + curl + gnupg | ~25 MB |
| jq | ~2 MB |
| shellcheck | ~10 MB |
| Node.js 22.x (NodeSource) | ~55 MB |
| apt cache removal (saves) | −20 MB |
| conjure kit source (COPY) | ~5 MB |
| **Total estimate** | **~152 MB** |

The `node:22-bookworm-slim` official image (which uses the same base + Node.js)
is reported at ~220–240 MB uncompressed [CITED: hub.docker.com/layers/library/node/22-bookworm-slim].
Our image adds `jq` + `shellcheck` but saves on Docker metadata/npm overhead —
estimate ~160–175 MB. The 200 MB cap should be met comfortably.

---

## docker.yml Workflow

### Multi-Arch Local Build Pattern [VERIFIED: docs.docker.com/build/ci/github-actions/multi-platform/]

**Critical discovery:** Loading a multi-platform image locally (with `load: true`)
requires enabling Docker's **containerd snapshotter** feature. Without it, `--load`
only works for a single platform. The `docker/setup-docker-action@v5` with a daemon
config block enables this.

### Annotated YAML Skeleton

```yaml
name: Docker Build

on:
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Required for multi-platform local load (containerd snapshotter)
      - name: Set up Docker daemon (containerd snapshotter)
        uses: docker/setup-docker-action@v4
        with:
          daemon-config: |
            {
              "features": {
                "containerd-snapshotter": true
              }
            }

      # Required for linux/arm64 cross-compilation on amd64 runner
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      # Required for buildx multi-platform builds
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build multi-arch image (no push)
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          load: true
          tags: conjure:local

      # Smoke test 1: version command
      - name: Smoke test — conjure version
        run: docker run --rm conjure:local version

      # Smoke test 2: audit against a minimal fixture
      - name: Scaffold fixture
        run: |
          mkdir -p /tmp/fixture
          cp -r tests/fixtures/python-fastapi/. /tmp/fixture/

      - name: Smoke test — conjure audit
        run: |
          docker run --rm \
            -v /tmp/fixture:/work \
            --user "$(id -u):$(id -g)" \
            conjure:local audit /work

      # Size assertion: .Size is uncompressed bytes; 200 MB = 209715200 bytes
      - name: Assert image size ≤200 MB
        run: |
          SIZE=$(docker image inspect --format '{{.Size}}' conjure:local)
          LIMIT=$((200 * 1024 * 1024))
          echo "Image size: $SIZE bytes (limit: $LIMIT)"
          [ "$SIZE" -lt "$LIMIT" ] || { echo "FAIL: image exceeds 200 MB"; exit 1; }
```

### Action Versions [ASSUMED — based on training data; verify at github.com/marketplace at plan time]

| Action | Version Used | Note |
|--------|-------------|------|
| docker/setup-docker-action | v4 | Enables containerd snapshotter |
| docker/setup-qemu-action | v3 | ARM64 emulation on amd64 |
| docker/setup-buildx-action | v3 | Multi-platform buildx |
| docker/build-push-action | v6 | Build + load (no push) |

Phase 15 (DEFERRED) will add SHA pinning per WR-01.

---

## Windows CI Changes

### What the New Job Covers

Per D-08 and D-09: a new `windows-test` job in `ci.yml` that runs `tests/run.sh`
on `windows-latest` with `shell: bash`. This adds TECH-03 coverage on top of the
existing `windows-hook-wiring` job (which tests only `.mjs` hook wiring).

### ci.yml Diff Shape

Add after the `windows-hook-wiring` job:

```yaml
  windows-test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run kit test suite (Git Bash)
        shell: bash
        run: bash tests/run.sh
```

No dependency installation needed — see compatibility analysis below.

**Note on `windows-hook-wiring`:** Per D-08, extend rather than duplicate. The
existing job tests hook wiring specifically. The new `windows-test` job runs the
full suite. They are separate jobs, not a matrix, because they have different
purposes and setup.

---

## Windows Test Compatibility

### Preinstalled Tools on windows-latest [VERIFIED: actions/runner-images Windows2022-Readme.md]

| Tool | Available | Version | Test Implication |
|------|-----------|---------|-----------------|
| bash (Git Bash) | YES | 5.3.9 | All `shell: bash` steps work |
| node | YES | bundled | Telemetry hook tests (TLMY-*) work |
| jq | YES | 1.8.1 | MKTPL-* and JSON tests work |
| ruby | YES | 3.3.11 | BREW-01 (`ruby -c`) works |
| python3 | YES | 3.12.10 | SKILL-01 (201-line generation) works |
| git | YES | 2.54.0 | All git -C sandbox tests work |
| shellcheck | NO | — | Handled gracefully (see below) |
| seq | YES (Git Bash) | GNU | FM size-cap test (line 341) works |

### shellcheck on Windows

`shellcheck` is NOT preinstalled on `windows-latest`. However, `tests/run.sh` treats
it as optional at two points:

1. **Preflight test (lines 151–159):** The test checks `if ! command -v shellcheck >/dev/null 2>&1;`
   and passes with a `skip` message when shellcheck is absent.
2. **Preflight fix-it test (lines 130–145):** When node is stripped from PATH, the
   fix-it output is checked for `apt|winget`. On Git Bash, `uname -s` returns
   `MINGW64_NT-*`, which `preflight.sh` maps to `windows-gitbash` → winget hints.
   So `grep -qE "apt|winget"` passes on Windows. [VERIFIED: scripts/preflight.sh line 30]

**shellcheck not needed for Windows CI job** — all tests handle its absence.

If shellcheck IS wanted (for the lint step), install via:
`choco install shellcheck` — but this is NOT needed for `tests/run.sh` to pass.

### Known Compatibility Issues

**1. PATH in `sandbox.sh` (LOW risk)**

`sandbox.sh` sets `PATH="$CONJURE_HOME/cli:${_node_dir:+...}:/usr/local/bin:/usr/bin:/bin"`.
On Git Bash for Windows, `/usr/local/bin`, `/usr/bin`, `/bin` are virtual MSYS paths
that map to Git's bundled tools. `$CONJURE_HOME/cli` is an absolute path like
`/c/Users/runner/work/conjure/conjure/cli` — valid in Git Bash. [ASSUMED: tested
pattern based on windows-hook-wiring job which uses CONJURE_HOME=$GITHUB_WORKSPACE]

**2. `mktemp -d` path format (LOW risk)**

On Git Bash, `mktemp -d` returns a path like `/tmp/tmpXXXXXX` which maps to
`C:\Users\RUNNER\AppData\Local\Temp\...`. All bash tools (`cp -r`, `rm -rf`,
`diff -r`) accept these MSYS-style paths. [ASSUMED: standard Git Bash behavior]

**3. `git` identity for sandbox git repos (LOW risk)**

Several tests (`MKTPL-*`, `SKILL-*`, `OVLY-*`) create temporary git repos with
`git -C "$MKTPL_DIR" config user.email "test@conjure"`. On windows-latest the
git identity is not globally set, but each test sets it locally — this is safe.
[VERIFIED: tests/run.sh lines 767–768]

**4. `seq` availability (CONFIRMED safe)**

Git for Windows bundles GNU coreutils via its MSYS2 environment, including `seq`.
Used in `tests/run.sh` line 341 for the size-cap failure mode test. [ASSUMED:
standard Git for Windows behavior; not explicitly listed in runner-images README
but is a core GNU utility bundled with all MSYS2 environments]

**5. `diff -r` for dry-run snapshot tests (SAFE)**

Git Bash ships GNU `diff` which supports `-r`. Used in TEST-05 snapshot tests.

**6. `ruby -c` for BREW-01 (VERIFIED safe)**

Ruby 3.3.11 is preinstalled. `ruby -c Formula/conjure.rb` will pass.

**7. `python3 -c` for SKILL-01 (VERIFIED safe)**

Python 3.12.10 is preinstalled. The 201-line SKILL size-cap test works.

### Tests Expected to Pass Without Modification

All 265 assertions. The test suite was written defensively:
- All shellcheck-dependent tests are already `command -v`-guarded or grace-exit
- `uname -s` detection in preflight tests handles `MINGW64_NT-*` via the
  `else` branch checking `apt|winget` [VERIFIED: tests/run.sh lines 132–145]
- All temp dir usage via `mktemp -d` is MSYS2-compatible

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-arch Docker build | Custom buildx scripts | `docker/build-push-action` with `platforms:` | Action handles QEMU registration, builder setup, manifest list |
| ARM64 emulation on amd64 | Manual QEMU setup | `docker/setup-qemu-action` | Action registers binfmt handlers |
| Local multi-platform load | `docker manifest` tricks | `docker/setup-docker-action` + containerd snapshotter | Without containerd store, `--load` silently ignores arm64 layer |
| Image size assertion | `docker images ls` parsing | `docker image inspect --format '{{.Size}}'` | Returns uncompressed bytes directly; no text parsing |
| Node.js install on Debian | Manual tarball download | NodeSource `setup_22.x` | APT-managed updates; matches CI environment exactly |

---

## Common Pitfalls

### Pitfall 1: Multi-platform `--load` silently fails without containerd snapshotter

**What goes wrong:** `docker buildx build --platform linux/amd64,linux/arm64 --load`
succeeds (exit 0) but only loads the amd64 layer. The arm64 platform is silently
omitted from the local image store with the default Docker engine.

**Why it happens:** The default overlay2 storage driver does not support multi-
platform image manifests in the local store. Only the containerd snapshotter does.

**How to avoid:** Add `docker/setup-docker-action@v4` with daemon config enabling
`containerd-snapshotter: true` before the buildx step.

**Warning signs:** `docker image inspect conjure:local | jq '.[].Architecture'`
only shows `amd64`, not both platforms.

[VERIFIED: docs.docker.com/build/ci/github-actions/multi-platform/]

### Pitfall 2: NodeSource package priority race with Debian's nodejs

**What goes wrong:** After running the NodeSource setup script, `apt-get install nodejs`
installs Debian's older `nodejs` package instead of NodeSource's, leaving npm missing.

**Why it happens:** On Debian 12, `nodejs` exists in both the Debian repo and
NodeSource, and apt priority conflicts can occur if the setup script hasn't fully
propagated its preferences.

**How to avoid:** Always run the setup script and then immediately `apt-get install nodejs`
in the same `RUN` layer. Do not split into separate `RUN` commands. [CITED: github.com/nodesource/distributions/issues/1601]

**Warning signs:** `npm --version` fails after install, or `which npm` points to
`/usr/bin/npm` (Debian's location, not NodeSource's `/usr/bin/npm`).

### Pitfall 3: WORKDIR /work owned by root, confuse writes by USER conjure

**What goes wrong:** `WORKDIR /work` created before `USER conjure` is owned by root.
The `conjure` user cannot write to `/work` at all without the caller passing `--user`.

**Why it happens:** `WORKDIR` creates the directory as the current user at build
time (root by default). After `USER conjure`, the WORKDIR is inaccessible for writes.

**How to avoid:** Either create `/work` with `RUN mkdir -p /work && chown conjure:conjure /work`
before switching user, or create WORKDIR AFTER `USER conjure`. Since we use `--user`
at runtime anyway, the cleanest approach is `RUN mkdir -p /work` as root, then
`USER conjure`, then `WORKDIR /work`. The `--user $(id -u):$(id -g)` flag overrides
the file creation UID at runtime regardless.

### Pitfall 4: `docker image inspect .Size` reports uncompressed bytes

**What goes wrong:** The size reported by `docker image inspect --format '{{.Size}}'`
is the *uncompressed* (on-disk) size, not the compressed registry pull size. The
CI must compare against 200 MB = 209,715,200 bytes in this context.

**How to avoid:** Use `LIMIT=$((200 * 1024 * 1024))` (= 209,715,200). The CONTEXT.md
constraint says ≤200 MB — interpret this as the uncompressed image size.

### Pitfall 5: Windows CI job inherits Ubuntu-specific install steps

**What goes wrong:** Copying the Ubuntu test job to windows-latest and including
`apt-get install` steps, or `sudo install ...`, causes immediate failures (no apt, no sudo).

**How to avoid:** The new `windows-test` job should have ONLY `actions/checkout@v4`
and `bash tests/run.sh`. All required tools are preinstalled on `windows-latest`.

### Pitfall 6: Git identity not set for MKTPL/SKILL/OVLY tests

**What goes wrong:** Tests that create temp git repos use `git commit` which fails
if `user.email`/`user.name` are not configured globally on the runner.

**Why it's not a problem here:** Each test block explicitly sets local git config:
`git -C "$MKTPL_DIR" config user.email "test@conjure"`. This is self-contained.

**Warning signs:** Tests fail with `Author identity unknown` — only happens if the
explicit `git config` lines were removed from `tests/run.sh`.

---

## Code Examples

### Image Size Assertion in docker.yml

```bash
# Source: docs.docker.com/reference/cli/docker/image/inspect/
SIZE=$(docker image inspect --format '{{.Size}}' conjure:local)
LIMIT=$((200 * 1024 * 1024))
echo "Image size: $SIZE bytes (limit: $LIMIT)"
[ "$SIZE" -lt "$LIMIT" ] || { echo "FAIL: image exceeds 200 MB"; exit 1; }
```

### Non-root User Creation in Dockerfile

```dockerfile
# Source: CONTEXT.md D-03; mirrors Homebrew formula approach
RUN useradd -m -u 1000 -s /bin/bash conjure
USER conjure
```

### CONJURE_HOME Wrapper (mirrors Homebrew formula)

```bash
# Source: Formula/conjure.rb (Homebrew shim pattern)
#!/bin/bash
export CONJURE_HOME=/usr/local/share/conjure
exec /usr/local/share/conjure/cli/conjure "$@"
```

### Windows CI Job (ci.yml)

```yaml
# Source: CONTEXT.md D-08; existing windows-hook-wiring job as model
windows-test:
  runs-on: windows-latest
  steps:
    - uses: actions/checkout@v4
    - name: Run kit test suite (Git Bash)
      shell: bash
      run: bash tests/run.sh
```

### README Docker Section Pattern

```markdown
## Docker

Run Conjure without installing it:

**bash / zsh:**
```bash
docker run --rm \
  -v $(pwd):/work \
  --user $(id -u):$(id -g) \
  ghcr.io/mohandoz/conjure:v0.4.0 audit .
```

**PowerShell:**
```powershell
docker run --rm `
  -v ${PWD}:/work `
  --user "$(id -u):$(id -g)" `
  ghcr.io/mohandoz/conjure:v0.4.0 audit .
```

**Windows cmd:**
```cmd
docker run --rm -v %CD%:/work ghcr.io/mohandoz/conjure:v0.4.0 audit .
```

> **File ownership:** Pass `--user $(id -u):$(id -g)` on Linux/macOS so files
> written to your mounted directory are owned by you. On Docker Desktop for Windows
> with WSL2, file ownership is handled by the WSL2 backend — `--user` is optional.
```

---

## Environment Availability

| Dependency | Required By | Available on ubuntu-latest | Available on windows-latest | Fallback |
|------------|------------|---------------------------|----------------------------|---------|
| docker buildx | docker.yml | YES (bundled) | N/A | — |
| QEMU | docker.yml multi-arch | YES (via action) | N/A | — |
| bash (Git Bash) | Windows CI | N/A | YES (5.3.9) | — |
| jq | tests/run.sh, docker.yml | YES (apt) | YES (1.8.1) | — |
| node | tests/run.sh | YES | YES | — |
| ruby | tests/run.sh BREW-01 | YES | YES (3.3.11) | — |
| python3 | tests/run.sh SKILL-01 | YES | YES (3.12.10) | — |
| shellcheck | CI lint step | YES (apt) | NO | Handled gracefully in tests |
| seq | tests/run.sh FM size-cap | YES (GNU) | YES (Git Bash/GNU) | — |

**Missing dependencies with no fallback:** None blocking Phase 14.

**Missing dependencies with fallback:**
- `shellcheck` on windows-latest: `tests/run.sh` passes without it (optional dep);
  CI lint step runs only on ubuntu-latest where shellcheck is installed via apt.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hand-rolled bash (`tests/run.sh`) |
| Config file | none |
| Quick run command | `bash tests/run.sh` |
| Full suite command | `bash tests/run.sh` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DOCK-01 | `conjure audit .` with `-v $(pwd):/work` | smoke | docker.yml step | ❌ Wave 0 (docker.yml) |
| DOCK-02 | Non-root USER conjure UID 1000 | smoke | `docker run --user` in docker.yml | ❌ Wave 0 |
| DOCK-04 | ≤200 MB, linux/amd64 + linux/arm64 | assertion | `docker image inspect` in docker.yml | ❌ Wave 0 |
| DOCK-05 | README docs $(pwd)/${PWD}/%CD% | manual | N/A | ❌ Wave 0 (README edit) |
| TECH-03 | windows-latest full test suite | integration | ci.yml windows-test job | ❌ Wave 0 (ci.yml) |

### Wave 0 Gaps

- [ ] `Dockerfile` — must exist before docker.yml smoke test can run
- [ ] `.github/workflows/docker.yml` — new workflow (workflow_dispatch)
- [ ] `.dockerignore` — prevent unnecessary context upload
- [ ] `ci.yml` — add `windows-test` job

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `seq` is available in Git Bash on windows-latest via GNU coreutils | Windows Compatibility | One test (FM size-cap) would fail; easy to work around with a `{1..205}` brace expansion alternative |
| A2 | Image size will be ~160–175 MB uncompressed | Dockerfile / Layer Estimate | Could exceed 200 MB cap if Node 22 LTS has grown; verify with actual build |
| A3 | docker/setup-docker-action@v4, setup-qemu-action@v3, setup-buildx-action@v3, build-push-action@v6 are current versions | docker.yml | Outdated version tags; verify at marketplace.github.com before pinning |
| A4 | `mktemp -d` on Git Bash returns MSYS-style paths that all bash tools accept | Windows Compatibility | Test isolation could break; low probability — this is standard Git Bash behavior |
| A5 | NodeSource `setup_22.x` installs correctly on debian:bookworm-slim in Docker without the npm/priority conflict | Dockerfile | Could need explicit `apt-get install -y nodejs=22.*` pinning; testable in CI build |

---

## Open Questions (RESOLVED)

1. **Node 22 vs Node 24 for Docker**
   - Node 22 is in LTS maintenance (EOL April 2027). Node 24 is the active LTS.
   - CONTEXT.md says "Node.js LTS" without specifying.
   - Recommendation: use Node 22 for stability; swap to 24 in Phase 15 if desired.

2. **`setup_22.x` curl pipe to bash**
   - The NodeSource install uses `curl ... | bash -` which is a `curl | sh` pattern.
   - CLAUDE.md constraint: "no `curl | sh` foot-guns" — this applies to Conjure's
     own scripts, not to Dockerfile build-time setup. Docker build-time is acceptable.
   - If desired, use the explicit GPG key method (download script, verify, run).
   - Recommendation: use the curl pipe for simplicity; it's a build-time step, not
     a user-facing installer.

3. **`--user` in docker.yml smoke test**
   - The smoke test in docker.yml runs as `USER conjure` (UID 1000) by default.
   - The `conjure audit` smoke test reads files from a mounted fixture — this is
     read-only so no ownership issue. No `--user` flag needed for the read-only audit.
   - For the `conjure init` write test (if added), `--user $(id -u):$(id -g)` would
     be needed. Phase 14 scope is audit only.

---

## Sources

### Primary (HIGH confidence)
- `docs.docker.com/build/ci/github-actions/multi-platform/` — multi-platform build with containerd snapshotter; `--load` requirement
- `github.com/actions/runner-images` Windows2022-Readme.md — preinstalled tools on windows-latest (ruby, python3, jq, bash version)
- `cli/conjure` (project source) — CONJURE_HOME resolution pattern
- `Formula/conjure.rb` (project source) — install layout to mirror in Docker
- `tests/run.sh` (project source) — full test suite analysis for Windows compat
- `.github/workflows/ci.yml` (project source) — existing CI structure

### Secondary (MEDIUM confidence)
- `github.com/nodejs/docker-node/blob/main/22/bookworm-slim/Dockerfile` — Node.js 22 binary install method; version 22.22.3
- `github.com/nodesource/distributions` — NodeSource setup_22.x for apt-managed Node.js on Debian
- `github.com/nodesource/distributions/issues/1601` — NodeSource/Debian priority conflict on Bookworm

### Tertiary (LOW confidence)
- Hub.docker.com node:22-bookworm-slim size data (~220–240 MB) — used to bound image size estimate

## Metadata

**Confidence breakdown:**
- Dockerfile structure: HIGH — based on project source + official Node.js Dockerfile + NodeSource docs
- docker.yml workflow: HIGH — based on official Docker CI docs (containerd snapshotter requirement verified)
- Windows compatibility: HIGH for tool availability (runner-images README); MEDIUM for `seq` (not listed but standard MSYS2)
- Image size estimate: MEDIUM — bounded by public Docker Hub data, actual size must be verified in CI

**Research date:** 2026-05-26
**Valid until:** 2026-08-26 (90 days — Docker action versions may change; runner-images updates frequently)
