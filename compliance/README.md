# Compliance Overlays

Opt-in profiles for projects subject to specific regulatory regimes. Each
overlay adds:

- Mandatory CLAUDE.md non-negotiables specific to the regime.
- Skills focused on the controls (PII handling, audit logging, retention).
- Hooks that enforce baseline safeguards (e.g. block commits containing PII patterns).
- A checklist mapped to the regime's control families.

## Available overlays

| Overlay | For | Adds |
| --- | --- | --- |
| `hipaa/` | US healthcare (PHI) | PHI patterns, BAA notes, audit log requirements, encryption-at-rest rules |
| `soc2/` | SaaS sec compliance | Change management, access review, vendor mgmt, incident response |
| `gdpr/` | EU personal data | DPIA template, data-subject rights flow, retention controls, lawful basis check |
| `pci/` | Card data | PAN handling, segmentation, scoping rules, log redaction |

## Apply

```bash
# After base init + stack profile
bash /u01/conjure/compliance/hipaa/apply.sh /path/to/repo
```

## What overlays do NOT do

- They do NOT make you compliant. Compliance is people + process + audit, not config.
- They DO make the AI assistant less likely to produce non-compliant code.
- They DO surface required controls in front of every relevant change.

## Anti-pattern

Adding all four overlays "to be safe" → 400-line CLAUDE.md, conflicting rules,
worse adherence. Apply only the regimes you actually fall under.
