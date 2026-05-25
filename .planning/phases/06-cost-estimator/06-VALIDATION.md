<!-- Covers: TECH-02e | COST-01, COST-02, COST-03 -->
# Phase 06 VALIDATION

## Verify cost section header appears when CONJURE_COST=1 (COST-01)

```bash
CONJURE_HOME=$(pwd)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cp -r tests/fixtures/python-fastapi/. "$TMPDIR/"
CONJURE_COST=1 bash scripts/audit-setup.sh "$TMPDIR" 2>&1 | grep '── Cost Estimate ──'
```

**Expected:** line containing `── Cost Estimate ──`

## Verify cost label has ±20% band and pricing date (COST-02)

```bash
CONJURE_HOME=$(pwd)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cp -r tests/fixtures/python-fastapi/. "$TMPDIR/"
CONJURE_COST=1 bash scripts/audit-setup.sh "$TMPDIR" 2>&1 | grep -E 'Estimate: \$[0-9]+\.[0-9]{2} ±20%'
CONJURE_COST=1 bash scripts/audit-setup.sh "$TMPDIR" 2>&1 | grep 'prices:'
```

**Expected:** first grep matches `Estimate: $X.XX ±20%`; second grep matches `prices:` with a date.

## Verify no network calls in default audit path (COST-03)

```bash
grep -v '^#' scripts/audit-setup.sh | grep -cE 'curl|fetch|http[s]?:' || true
```

**Expected:** `0` (zero network call patterns)

## Verify --exact advisory when ANTHROPIC_API_KEY is absent (COST-03)

```bash
CONJURE_HOME=$(pwd)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cp -r tests/fixtures/python-fastapi/. "$TMPDIR/"
CONJURE_COST=1 CONJURE_EXACT=1 ANTHROPIC_API_KEY="" bash scripts/audit-setup.sh "$TMPDIR" 2>&1 | grep 'ANTHROPIC_API_KEY not set'
```

**Expected:** line containing `ANTHROPIC_API_KEY not set`
