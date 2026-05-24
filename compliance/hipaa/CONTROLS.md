# HIPAA Controls Checklist (project-level)

Maps to 45 CFR §164 Security Rule + Privacy Rule.

## Administrative safeguards (§164.308)

- [ ] Security officer designated (name in CODEOWNERS).
- [ ] Workforce access reviewed quarterly.
- [ ] Security training tracked.
- [ ] Incident response plan in `docs/RUNBOOK.md`.
- [ ] BAA on file for every service handling PHI.

## Physical safeguards (§164.310)

- [ ] Production access restricted (cite IAM policy file/line).
- [ ] Device disposal policy documented.

## Technical safeguards (§164.312)

- [ ] Unique user identification.
- [ ] Emergency access procedure documented.
- [ ] Automatic logoff configured.
- [ ] Encryption at rest (AES-256+).
- [ ] Encryption in transit (TLS 1.3+).
- [ ] Audit log of every PHI access (actor + target + timestamp).

## Approved data stores (list ALL with BAA on file)

| Store | Vendor | BAA executed | Encryption |
| --- | --- | --- | --- |

## Approved third-party services

| Service | Use case | BAA | Last review |
| --- | --- | --- | --- |
