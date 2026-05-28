---
phase: 21
slug: foundation-libs-inventory
status: verified
threats_open: 0
asvs_level: 1
created: 2026-05-28
---

# Phase 21 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

Register authored at plan time across the four `21-0N-PLAN.md` `<threat_model>`
blocks. Each declared mitigation was verified present in the implementation
(file:line evidence), not inferred from documentation. Verification by
`gsd-security-auditor`, ASVS L1, `block_on: high` — no blockers.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| fixture files → test harness | Authored fixture contents; no untrusted input | Static markdown |
| generate-large.sh `$1` → filesystem | Script writes to caller-supplied temp dir | Path argument |
| tests/run.sh mktemp paths → filesystem | Test temp dirs created and torn down | Local temp paths |
| caller src path → mutate_archive | Repo-local path, not user-typed | File path |
| caller archive_root → filesystem | Derived from CONJURE_ARCHIVE_ROOT | Directory path |
| find output → inventory_classify | Repo-local paths, passed as vars never eval'd | File paths |
| CLAUDE.md content → link extraction | grep output used in `grep -qxF`, never eval | Markdown link text |
| file paths → jq --arg | All path values injection-safe via jq | File paths |
| CONJURE_HOME → source | Resolved from `dirname "$0"`, not user input | Directory path |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-21-01 | Tampering | generate-large.sh target path | mitigate | `TARGET="${1:-}"` + empty-guard exit; quoted `"${DEST}"`/`"${TARGET}"` in mkdir/printf (generate-large.sh L9-22) | closed |
| T-21-02 | Tampering | tests/run.sh Phase 21 mktemp paths | mitigate | All temp dirs via `mktemp -d`, always quoted; `rm -rf` + `trap` cleanup per section (tests/run.sh Phase 21 block) | closed |
| T-21-03 | Tampering | mutate_archive src path | mitigate | `local src="$1"`; `"${src}"`/`"${dest}"` quoted in cp/sha256/rm; no eval (lib/mutate.sh L86,107-130) | closed |
| T-21-04 | Tampering | mutate_archive dest path | mitigate | `rel="${src#/}"` → `dest="${archive_root}/${rel}"`; never a user-supplied dest arg (lib/mutate.sh L104-105) | closed |
| T-21-05 | Tampering/Denial | unverified-copy-delete | mitigate | copy → sha256 → mismatch `rm -f dest`+`return 1` (src untouched) → `rm -f src` only on match → ledger; D-13 order intact (lib/mutate.sh L107-134) | closed |
| T-21-06 | Tampering | log entry injection via filename | mitigate | `mutate_write` uses `printf '%s'` not echo; ledger via `printf '%s\t'`; inventory JSON via `jq --arg`/`--argjson`; no eval (lib/mutate.sh L62-64,132; lib/inventory.sh L122-134) | closed |
| T-21-07 | Tampering | path traversal in manifest paths | mitigate | `rel="${filepath#"${target}"/}"`; only `${rel}` stored; find scoped to `"${target}"`; no eval (lib/inventory.sh L50,148,165-187,276) | closed |
| T-21-08 | Tampering | shell injection via filenames | mitigate | `while IFS= read -r filepath`; `"${filepath}"` quoted in test -L/wc/tr/cmp/grep; `jq --arg` (lib/inventory.sh L212,215,224,270,289-306) | closed |
| T-21-09 | Tampering | inventory DRY_RUN bypass | mitigate | DRY_RUN=1 redirects to `/tmp/adopt-manifest-dryrun.json` before write; write via `mutate_write` internal guard (lib/inventory.sh L409-411; lib/mutate.sh L56-60) | closed |
| T-21-10 | Denial | 500-file cap bypass via symlink farm | accept | See Accepted Risks. Symlinks skipped by `test -L` (lib/inventory.sh L215); `total_found` raw find count; local-fs only | closed |
| T-21-11 | Tampering | snapshot cp -a wrong backup_root | mitigate | `snap_dir="${backup_root}/conjure-adopt-${ts}"`; backup_root is caller positional `$2` (lib/snapshot.sh L19,22) | closed |
| T-21-12 | Tampering | CONJURE_HOME path injection via env | mitigate | `: "${CONJURE_HOME:="$(cd "$(dirname "$0")/.." && pwd)"}"` sets only if unset; script-relative fallback; in-repo caps.sh (scripts/audit-setup.sh L8,10) | closed |
| T-21-13 | Tampering | audit-setup.sh behavior change | accept | See Accepted Risks. caps.sh `CLAUDE_MD_CAP=100`/`SKILL_MD_CAP=200`/`AGENT_MD_CAP=80` identical to replaced literals (lib/caps.sh L9-11) | closed |
| T-21-SC | Tampering | npm/pip/cargo installs | accept | See Accepted Risks. Zero npm/pnpm/yarn/pip/cargo/curl/wget across all 7 implementation files | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-21-01 | T-21-10 | Symlinks skipped by `test -L` before processing; `total_found` is raw `find` count; scan is local-fs only and cannot traverse outside `${target}`. Residual risk negligible / local-only. | gsd-security-auditor | 2026-05-28 |
| AR-21-02 | T-21-13 | Call-site-only change: cap constants in lib/caps.sh are byte-identical to the literals they replaced; exit codes and output for identical inputs unchanged. Residual risk: none. | gsd-security-auditor | 2026-05-28 |
| AR-21-03 | T-21-SC | Phase 21 invokes zero package managers and fetches nothing from the network; verification grep over the seven implementation files returned no install/fetch invocations. Residual risk: none. | gsd-security-auditor | 2026-05-28 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-05-28 | 14 | 14 | 0 | gsd-security-auditor (ASVS L1) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-05-28
