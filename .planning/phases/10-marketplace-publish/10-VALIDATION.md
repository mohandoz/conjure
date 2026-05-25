# Phase 10: Marketplace Publish — Validation

**Phase:** 10-marketplace-publish
**Framework:** Hand-rolled bash assertions in `tests/run.sh`
**Quick run:** `bash tests/run.sh`
**Per-wave smoke:** `bash tests/run.sh && claude plugin validate . && claude plugin validate .claude-plugin/plugin.json`

---

## Phase Requirements → Test Map

| Req ID | Behavior Under Test | Test Type | Automated Command |
|--------|---------------------|-----------|-------------------|
| MKTPL-01 | `conjure publish` writes HEAD SHA + version to both JSON files | unit/integration | `bash tests/run.sh` (new assertions in Wave 3) |
| MKTPL-01 | `conjure publish` aborts with exit 2 on dirty working tree | unit | `bash tests/run.sh` |
| MKTPL-01 | `conjure publish --dry-run` writes no files | unit | `bash tests/run.sh` |
| MKTPL-02 | Version-consistency check exits non-zero when version fields drift from VERSION | unit | `bash tests/run.sh` |
| MKTPL-03 | `claude plugin validate .` exits 0 on restructured marketplace.json | smoke | `claude plugin validate .` |
| MKTPL-03 | `claude plugin validate .claude-plugin/plugin.json` exits 0 | smoke | `claude plugin validate .claude-plugin/plugin.json` |
| MKTPL-04 | `conjure publish --submit` writes `.claude-plugin/submit-entry.json` with required fields | unit | `bash tests/run.sh` |
| MKTPL-04 | `conjure publish --submit` prints checklist URL to stdout | unit | `bash tests/run.sh` |

---

## Wave Gate Commands

### After Wave 1 (10-01: Manifest restructure)
```bash
# Both manifest files must pass the official validator
claude plugin validate .
claude plugin validate .claude-plugin/plugin.json

# Versions must match VERSION file
VER=$(cat VERSION)
[ "$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)" = "$VER" ] || exit 1
[ "$(jq -r '.version' .claude-plugin/plugin.json)" = "$VER" ] || exit 1
echo "OK: wave 1 gate passed"
```

### After Wave 2 (10-02 + 10-03: Publish script + CI gates)
```bash
# Full test suite still green
bash tests/run.sh

# CLI command exists and dry-run works
CONJURE_DRYRUN=1 bash cli/conjure publish --dry-run
echo "Exit code: $? (expect 0)"

# Version-consistency check logic (simulate drift detection)
ver=$(cat VERSION)
mkt=$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)
[ "$mkt" = "$ver" ] && echo "OK: versions consistent"
```

### After Wave 3 (10-04: Tests)
```bash
# Full suite with all new MKTPL assertions
bash tests/run.sh

# Smoke: both validate calls clean
claude plugin validate . && claude plugin validate .claude-plugin/plugin.json
echo "Phase gate: passed"
```

---

## Manual Checks (non-automatable)

| Check | How to Verify |
|-------|--------------|
| `conjure publish --submit` stdout checklist is human-readable | Run `bash cli/conjure publish --submit` (or dry-run equivalent); inspect stdout for URL and ordered steps |
| `submit-entry.json` contains correct catalog fields | Run publish --submit and inspect `.claude-plugin/submit-entry.json` for `name`, `description`, `source`, `version`, `author`, `homepage` |
