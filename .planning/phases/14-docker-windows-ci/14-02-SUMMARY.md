---
phase: 14
plan: 02
subsystem: docker
tags: [docker-workflow, multi-arch, workflow_dispatch, smoke-test, size-assertion]
dependency_graph:
  requires: [Dockerfile, .dockerignore]
  provides: [.github/workflows/docker.yml]
  affects: []
tech_stack:
  added: []
  patterns: [containerd-snapshotter, multi-arch-local-load, workflow_dispatch-only]
key_files:
  created:
    - .github/workflows/docker.yml
  modified: []
decisions:
  - "workflow_dispatch only — no push/pull_request triggers (D-04)"
  - "containerd-snapshotter enabled before buildx to support multi-platform local load (Pitfall 1)"
  - "load: true with tags: conjure:local — no push, no registry login (Phase 15 owns publishing)"
  - "Smoke test fixture copied from tests/fixtures/python-fastapi/ (existing fixture)"
  - "Image size assertion uses docker image inspect .Size (uncompressed bytes); limit 200*1024*1024"
metrics:
  duration: "~3 minutes"
  completed: "2026-05-26T00:00:00Z"
  tasks_completed: 1
  files_created: 1
---

# Phase 14 Plan 02: docker.yml Workflow Summary

**One-liner:** Manual workflow_dispatch workflow that builds a multi-arch (linux/amd64 + linux/arm64) Conjure image locally with containerd snapshotter, runs two smoke tests (version + audit), and asserts the image stays under 200 MB.

## What Was Created

### `.github/workflows/docker.yml`

A GitHub Actions workflow with `workflow_dispatch` as the sole trigger. The single `build` job runs on `ubuntu-latest` and executes 8 steps in order:

1. `actions/checkout@v4` — check out the repo
2. `docker/setup-docker-action@v4` — enable containerd snapshotter daemon feature (required for multi-platform `load: true`)
3. `docker/setup-qemu-action@v3` — register ARM64 binfmt handlers for cross-compilation on amd64 runner
4. `docker/setup-buildx-action@v3` — create a multi-platform buildx builder
5. `docker/build-push-action@v6` — build `linux/amd64,linux/arm64`, load locally as `conjure:local`, no push
6. Smoke test: `docker run --rm conjure:local version`
7. Smoke test: copy `tests/fixtures/python-fastapi/` to `/tmp/fixture/`, run `docker run --rm -v /tmp/fixture:/work --user "$(id -u):$(id -g)" conjure:local audit /work`
8. Size assertion: `docker image inspect --format '{{.Size}}' conjure:local` compared against `$((200 * 1024 * 1024))` bytes

## Verification Results

| Check | Command | Result |
|-------|---------|--------|
| `workflow_dispatch` trigger present | `grep -c 'workflow_dispatch'` | 1 — PASS |
| containerd snapshotter enabled | `grep -c 'containerd-snapshotter'` | 1 — PASS |
| Both platforms declared | `grep -c 'linux/amd64,linux/arm64'` | 1 — PASS |
| `load: true` (no push) | `grep -c 'load: true'` | 1 — PASS |
| YAML parses cleanly | `python3 -c "import yaml; yaml.safe_load(...)"` | YAML valid — PASS |
| No `push: true` in non-comment lines | `grep -v '^#' | grep -c 'push: true'` | 0 — PASS |

## Action Versions Used

| Action | Version | Purpose |
|--------|---------|---------|
| `actions/checkout` | v4 | Check out repo |
| `docker/setup-docker-action` | v4 | Enable containerd snapshotter (Pitfall 1 fix) |
| `docker/setup-qemu-action` | v3 | ARM64 emulation on amd64 runner |
| `docker/setup-buildx-action` | v3 | Multi-platform buildx builder |
| `docker/build-push-action` | v6 | Build + local load (no registry push) |

Note: SHA pinning for all third-party actions is deferred to Phase 15 (WR-01), as documented in the workflow header comment.

## Deviations from Plan

None — workflow created exactly as specified. The step order mirrors the plan's annotated YAML skeleton and addresses all documented pitfalls:

- Pitfall 1 (multi-platform `--load` silently fails without containerd snapshotter): resolved by placing `setup-docker-action` before `setup-buildx-action`.
- Phase 15 deferred items (registry login, push, SHA pinning) are explicitly absent.

## Notes

- The `conjure audit /work` smoke test uses `--user "$(id -u):$(id -g)"` so mounted fixture files are accessible under the caller's UID (mirrors D-06 from CONTEXT.md).
- The size assertion computes `200 * 1024 * 1024 = 209,715,200 bytes` (uncompressed) — consistent with Pitfall 4 guidance in RESEARCH.md.
- No registry login step is present; the `conjure:local` tag is ephemeral and exists only within the runner's lifetime.
- The fixture path `tests/fixtures/python-fastapi/` must exist in the repo for the audit smoke test to work — it was present as of Plan 14-01 verification.

## Self-Check: PASSED

- `/Users/mohandoz/u01/innovate/conjure/.github/workflows/docker.yml` — exists
- All 6 grep/YAML verification checks passed (see table above)
