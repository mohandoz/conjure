<!-- Covers: TECH-02d | DOCS-01 -->

# Phase 05 VALIDATION

## Verify scripts/record-demo.sh exists and is executable (DOCS-01)

```bash
[ -x scripts/record-demo.sh ] && echo "PASS: executable" || echo "FAIL: missing or not executable"
```

**Expected:** `PASS: executable`

## Verify README.md contains demo recording reference (DOCS-01)

```bash
grep -iE 'demo\.gif|demo\.cast|asciinema' README.md
```

**Expected:** line containing `demo.gif`, `demo.cast`, or `asciinema`

## Verify CLI smoke: conjure version exits 0 (DOCS-01)

```bash
CONJURE_HOME=$(pwd) cli/conjure version
echo "exit: $?"
```

**Expected:** version string output followed by `exit: 0`
