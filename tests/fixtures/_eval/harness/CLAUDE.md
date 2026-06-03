## Project

Test harness for conjure eval fixture.

## Conventions

- Always run shellcheck before committing bash scripts.
- Never use exit 1 in hooks; use exit 2.
- Backup before mutate: all file mutations route through lib/mutate.sh.
