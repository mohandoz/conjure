---
phase: 14
slug: docker-windows-ci
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-26
---

# Phase 14 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Requirements Covered

| Req ID | Description |
|--------|-------------|
| DOCK-01 | Docker image runs `conjure audit` against a mounted volume (`-v $(pwd):/work`) |
| DOCK-02 | Container runs non-root (UID 1000); `--user $(id -u):$(id -g)` documented |
| DOCK-04 | Base image is `debian:bookworm-slim`; uncompressed size ≤ 200 MB |
| DOCK-05 | README documents bash/PowerShell/cmd volume-mount forms |
| TECH-03 | `tests/run.sh` passes on `windows-latest` with `shell: bash` |

**Deferred:** DOCK-03 (ghcr.io publish + semantic version tags) → Phase 15.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hand-rolled bash test runner |
| **Config file** | none |
| **Quick run command** | `bash tests/run.sh` |
| **Full suite command** | `bash tests/run.sh` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run.sh`
- **After every plan wave:** Run `bash tests/run.sh`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Requirement Verification

### DOCK-01 — Docker volume mount runs `conjure audit`

```bash
# Verify WORKDIR is /work in Dockerfile
grep 'WORKDIR /work' /Users/mohandoz/u01/innovate/conjure/Dockerfile

# Verify ENTRYPOINT uses conjure
grep 'ENTRYPOINT' /Users/mohandoz/u01/innovate/conjure/Dockerfile

# Verify docker.yml smoke test mounts a volume and runs audit
grep 'conjure audit' /Users/mohandoz/u01/innovate/conjure/.github/workflows/docker.yml
grep '\-v.*:/work' /Users/mohandoz/u01/innovate/conjure/.github/workflows/docker.yml
```

---

### DOCK-02 — Non-root container; `--user` flag documented

```bash
# Verify non-root user setup in Dockerfile
grep 'useradd.*-u 1000' /Users/mohandoz/u01/innovate/conjure/Dockerfile
grep '^USER conjure' /Users/mohandoz/u01/innovate/conjure/Dockerfile

# Verify README documents --user flag
grep '\-\-user.*id -u' /Users/mohandoz/u01/innovate/conjure/README.md
```

---

### DOCK-04 — Base image is debian:bookworm-slim; size ≤ 200 MB

```bash
# Verify base image declaration
grep 'FROM debian:bookworm-slim' /Users/mohandoz/u01/innovate/conjure/Dockerfile

# Verify docker.yml asserts image size ≤ 200 MB (200 * 1024 * 1024 = 209715200 bytes)
grep '209715200\|200.*MB\|image.*size' /Users/mohandoz/u01/innovate/conjure/.github/workflows/docker.yml
```

---

### DOCK-05 — README documents bash/PowerShell/cmd volume-mount forms

```bash
# Verify all three volume-mount forms are documented
grep 'pwd.*:/work' /Users/mohandoz/u01/innovate/conjure/README.md
grep 'PWD.*:/work' /Users/mohandoz/u01/innovate/conjure/README.md
grep '%CD%:/work' /Users/mohandoz/u01/innovate/conjure/README.md

# Verify Docker section exists
grep -c '## Docker' /Users/mohandoz/u01/innovate/conjure/README.md

# Verify Windows cmd section presence
grep 'Windows cmd' /Users/mohandoz/u01/innovate/conjure/README.md
```

---

### TECH-03 — `tests/run.sh` passes on `windows-latest` with `shell: bash`

```bash
# Verify windows-test job exists in ci.yml
grep -A 10 'windows-test:' /Users/mohandoz/u01/innovate/conjure/.github/workflows/ci.yml

# Verify the job uses windows-latest runner
grep -A 2 'windows-test:' /Users/mohandoz/u01/innovate/conjure/.github/workflows/ci.yml | grep 'windows-latest'

# Verify shell: bash is set for the run step
grep -A 10 'windows-test:' /Users/mohandoz/u01/innovate/conjure/.github/workflows/ci.yml | grep 'shell: bash'

# Verify it runs tests/run.sh
grep -A 10 'windows-test:' /Users/mohandoz/u01/innovate/conjure/.github/workflows/ci.yml | grep 'bash tests/run.sh'

# Verify no forbidden install steps (apt-get / sudo / choco / winget) in windows-test job
# (should return empty — no matches expected)
awk '/windows-test:/,/windows-hook-wiring:/' /Users/mohandoz/u01/innovate/conjure/.github/workflows/ci.yml \
  | grep -E 'apt-get|sudo|choco|winget' && echo "FAIL: forbidden install step found" || echo "PASS: no forbidden install steps"

# Verify YAML is valid
python3 -c "import yaml; yaml.safe_load(open('/Users/mohandoz/u01/innovate/conjure/.github/workflows/ci.yml'))" && echo "ci.yml YAML valid"
```

---

## Deferred Requirements

### DOCK-03 — ghcr.io publish with semantic version tags (Phase 15)

DOCK-03 requires publishing the Docker image to `ghcr.io/mohandoz/conjure` with
semver tags (`:v0.4.0`, `:latest`). This is deferred to Phase 15 as it is the
release gate for the Docker distribution feature. Phase 14 builds and smoke-tests
the image locally in `docker.yml` (manual `workflow_dispatch`) but does not push.

**Verification commands (Phase 15):**
```bash
# After Phase 15: verify ghcr.io image is published
docker pull ghcr.io/mohandoz/conjure:v0.4.0
docker run --rm ghcr.io/mohandoz/conjure:v0.4.0 version
```

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `docker run --rm -v $(pwd):/work ghcr.io/mohandoz/conjure:v0.4.0 audit .` exits 0 | DOCK-01 | Requires published image (Phase 15) | After Phase 15: pull the image and run `conjure audit` against a local fixture |
| Container writes files owned by calling user | DOCK-02 | Requires Docker runtime | Run with `--user $(id -u):$(id -g)`; verify created files are owned by current user, not root |
| Image size ≤ 200 MB uncompressed | DOCK-04 | Requires Docker build | `docker image inspect --format '{{.Size}}' conjure:local` and confirm ≤ 209715200 bytes |
| `windows-latest` CI run passes all 265 tests | TECH-03 | GitHub Actions runner required | Push to a PR branch and verify the `windows-test` job is green in Actions |

---

## Validation Sign-Off

- [x] DOCK-01 verify commands documented
- [x] DOCK-02 verify commands documented
- [x] DOCK-04 verify commands documented
- [x] DOCK-05 verify commands documented
- [x] TECH-03 verify commands documented
- [x] DOCK-03 deferred to Phase 15 with rationale
- [ ] All automated bash assertions pass on CI
- [ ] `nyquist_compliant: true` set in frontmatter (pending human sign-off)

**Approval:** pending
