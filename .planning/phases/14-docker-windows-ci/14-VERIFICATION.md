---
phase: 14-docker-windows-ci
verified: 2026-05-26T00:00:00Z
status: human_needed
score: 8/8 must-haves verified (3 require live CI run)
overrides_applied: 0
human_verification:
  - test: "Docker image builds and runs conjure audit with -v mount"
    expected: "`docker build -t conjure:local . && docker run --rm -v $(pwd):/work --user $(id -u):$(id -g) conjure:local audit /work` exits 0 with audit output"
    why_human: "Requires Docker daemon and built image; not available in verification environment"
  - test: "Multi-arch build and size assertion"
    expected: "docker.yml workflow_dispatch run shows both amd64 and arm64 platforms built; image size < 200MB assertion passes"
    why_human: "Requires GitHub Actions runner with containerd snapshotter and QEMU; cannot run locally without Docker Buildx"
  - test: "windows-test CI job passes full suite"
    expected: "windows-test job in ci.yml runs bash tests/run.sh on windows-latest and exits 0"
    why_human: "Requires GitHub Actions windows-latest runner; cannot simulate locally"
---

# Phase 14: Docker + Windows CI — Verification Report

**Phase Goal:** Conjure is runnable as a Docker container (multi-arch, non-root, ≤200 MB) and all existing tests pass on `windows-latest` CI
**Verified:** 2026-05-26
**Status:** human_needed (code verified; 3 items require live environment)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (Static Verification)

**DOCK-02: Non-root user (UID 1000)**
```bash
grep -c 'useradd.*-u 1000' Dockerfile  # → 1 PASS
grep -c '^USER conjure' Dockerfile      # → 1 PASS
grep -c 'CONJURE_HOME=/usr/local/share/conjure' Dockerfile  # → 2 PASS
grep -c 'ENTRYPOINT \["conjure"\]' Dockerfile  # → 1 PASS
```
Status: **PASS**

**DOCK-04: Multi-arch platforms specified**
```bash
grep -c 'linux/amd64,linux/arm64' .github/workflows/docker.yml  # → 1 PASS
grep -c '200 \* 1024 \* 1024' .github/workflows/docker.yml      # → 1 PASS
grep -c 'containerd-snapshotter' .github/workflows/docker.yml   # → 1 PASS
```
Status: **PASS (code-verified; live size confirmation human-needed)**

**DOCK-05: README Docker section**
```
grep -c '## Docker' README.md           # → 1 PASS
grep -n '$(pwd):/work' README.md        # → line 81 PASS
grep -c '%CD%:/work' README.md          # → 1 PASS
grep -c 'PWD.*:/work' README.md         # → 1 PASS
grep -c 'WSL2' README.md                # → 1 PASS
```
Status: **PASS**

**TECH-03: windows-test CI job**
```bash
grep -c 'windows-test' .github/workflows/ci.yml  # → 1 PASS
# Confirmed: job has exactly 2 steps: checkout + bash tests/run.sh with shell: bash
# windows-hook-wiring job preserved (not replaced)
python3 -c "import yaml; d=yaml.safe_load(open('.github/workflows/ci.yml')); print(list(d['jobs'].keys()))"
# → ['test', 'audit-on-fixture', 'windows-test', 'windows-hook-wiring']
```
Status: **PASS (code-verified; live CI run human-needed)**

**docker.yml: workflow_dispatch only (D-04)**
```bash
grep -c 'workflow_dispatch' .github/workflows/docker.yml  # → 1 PASS
# No push: or pull_request: triggers
grep -c 'push:' .github/workflows/docker.yml  # → 0 PASS
```
Status: **PASS**

---

## Human-Needed Verifications

1. **DOCK-01 + DOCK-02 (live):** Run `docker build -t conjure:local .` then `docker run --rm conjure:local version` and `docker inspect conjure:local | jq '.[0].Config.User'` (should return "conjure"). See 14-VALIDATION.md §DOCK-01 and §DOCK-02 for full verify commands.

2. **DOCK-04 (live):** Trigger `gh workflow run docker.yml` to test multi-arch build and size assertion on GitHub Actions runners with QEMU support.

3. **TECH-03 (live):** Push to main or open a PR to trigger the windows-test job on `windows-latest`. Monitor at GitHub Actions.

---

## Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| DOCK-01 | 14-01, 14-03 | human_needed | Dockerfile ENTRYPOINT + WORKDIR correct; live mount test needed |
| DOCK-02 | 14-01 | passed | Grep: useradd -u 1000 + USER conjure confirmed |
| DOCK-04 | 14-01, 14-02 | human_needed | platforms: linux/amd64,linux/arm64 in docker.yml; live size assertion needed |
| DOCK-05 | 14-03 | passed | README Docker section with all 3 volume forms present |
| TECH-03 | 14-03 | human_needed | windows-test job in ci.yml; live run on windows-latest needed |

Note: DOCK-03 (ghcr.io publish) is Phase 15.

---

## Tech Debt

- shellcheck is not pre-installed on `windows-latest` runners; `tests/run.sh` handles its absence gracefully with `command -v` gate (lines 151-159). Any tests that assert shellcheck output will be silently skipped. Flagged for Phase 15 or v0.5.0 investigation.
