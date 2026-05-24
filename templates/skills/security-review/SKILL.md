---
name: security-review
description: "OWASP-aligned security audit, dependency CVE scan, secret detection, threat modeling. Invoke when user asks for security review, before production deploy, or after dep upgrades."
---

# security-review

## OWASP Top 10 (2021) — codebase quick scan

| Category | What to grep / look for |
| --- | --- |
| A01 Broken Access Control | endpoints without auth annotations; horizontal privilege escalation |
| A02 Cryptographic Failures | MD5/SHA1 usage, hardcoded keys, HTTP (non-HTTPS) URLs |
| A03 Injection | string concat in SQL, `os.system`, `eval`, `exec`, template injection |
| A04 Insecure Design | missing rate limits, missing CSRF, missing input validation |
| A05 Misconfiguration | debug mode in prod, default credentials, verbose errors |
| A06 Vulnerable Components | dep scan: `<npm audit | pip-audit | cargo audit | snyk | dependency-check>` |
| A07 ID & Auth Failures | weak session mgmt, no MFA on admin, password reset flaws |
| A08 SW & Data Integrity | unsigned packages, no integrity checks on deserialization |
| A09 Logging Failures | sensitive data in logs, no audit log for privileged actions |
| A10 SSRF | URL fetched from user input without allowlist |

## Secrets scan

```bash
# Install once
brew install gitleaks   # or: pip install detect-secrets

# Run
gitleaks detect --source . --no-banner
```

Wire as PreToolUse hook on `git commit` — see `templates/hooks/pre-commit-quality-gate.sh`.

## Dependency CVE scan

| Stack | Command |
| --- | --- |
| Node | `npm audit --omit dev` |
| Python | `pip-audit` |
| Java | `./gradlew dependencyCheckAnalyze` |
| Rust | `cargo audit` |
| Go | `govulncheck ./...` |
| Generic | `trivy fs .` |

## Threat-model checklist (new feature)

1. Identify data flows: trust boundaries crossed?
2. STRIDE: Spoofing, Tampering, Repudiation, Info disclosure, DoS, Elevation.
3. List threats. For each: mitigation, residual risk, owner.
4. Document in `docs/threat-models/<feature>.md`.

## Auth review (new endpoint)

- AuthN: how is the caller identified?
- AuthZ: what role/permission gates this?
- Audit: is the action logged with actor + target?
- Rate limit: per-user or per-IP?
- Input validation: at the boundary, before any DB call?

## Don't ship until

- [ ] Secrets scan clean.
- [ ] Dep scan clean (or all known CVEs accepted with justification).
- [ ] Auth/audit on every new privileged endpoint.
- [ ] Logs don't contain PII or secrets.
- [ ] Errors don't leak stack traces to clients.

## Cross-references

- General review → `skills/pr-review/SKILL.md`.
- Web research (CVE details) → `skills/web-research/SKILL.md`.
