---
name: bad-skill
description: Test skill with wrong-typed frontmatter for SCHM-01 negative test
disallowed-tools:
  Bash: true
  Write: true
---

This skill is a NEGATIVE fixture for SCHM-01.
The disallowed-tools field uses a YAML block mapping (object) instead of an array or space-string.
This is an invalid type and must cause audit to fail (exit 2).
