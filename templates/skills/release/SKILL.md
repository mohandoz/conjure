---
name: release
description: "Version bump, changelog generation, tag creation, release notes, rollback recipe. Invoke when user asks to cut a release, bump version, or prepare release notes."
---

# release

## Versioning

Scheme: `<SemVer | CalVer | sequential>`. Source of truth: `<file>`.

Conventional Commits → automatic version bump:
- `fix:` → patch
- `feat:` → minor
- `<scope>!:` or `BREAKING CHANGE:` footer → major

## Tooling

| Goal | Tool |
| --- | --- |
| Version bump | `<standard-version | release-please | semantic-release | cargo-release | python-semantic-release>` |
| Changelog | `<conventional-changelog | git-cliff>` |
| GitHub release | `gh release create` |

## Release checklist

- [ ] `main` is green (CI passing).
- [ ] All open critical/major bugs triaged.
- [ ] Run `<version-bump-tool>` — review proposed version + changelog.
- [ ] Update version in `<file(s)>`.
- [ ] Update CHANGELOG.md.
- [ ] Commit: `chore(release): vX.Y.Z`.
- [ ] Tag: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`.
- [ ] Push: `git push && git push --tags`.
- [ ] CI builds the release artifact and pushes to `<registry>`.
- [ ] Deploy to staging; smoke-test.
- [ ] Deploy to prod (per `skills/build-deploy/SKILL.md`).
- [ ] Publish release notes from CHANGELOG.

## Rollback recipe

```bash
# Pin previous version in deploy config
<command>

# Verify
<command>

# If DB migration involved, run downgrade
<command>
```

## Post-release

- [ ] Watch error rates for `<duration>` post-deploy.
- [ ] Update `docs/RUNBOOK.md` if procedure changed.
- [ ] If hotfix needed: branch from tag, fix, tag as `vX.Y.Z+1`.

## Cross-references

- CI/CD → `skills/build-deploy/SKILL.md`.
- Migration rollback → `skills/database-schema/SKILL.md`.
