# .kiln/implementing.lock not gitignored

**Source**: GitHub #115 (manifest-improvement retrospective), implementer friction note
**Priority**: high
**Suggested command**: `/fix add .kiln/implementing.lock to .gitignore — every implementer has ~50% chance of accidentally staging it on the first phase commit`
**Tags**: [auto:continuance]

## Description

The `/implement` prereqs step creates `.kiln/implementing.lock`. First `git add -A` (or scoped `git add .kiln/`) stages it. Every implementer reports having to manually unstage it on the first phase commit. Trivial fix — add one line to `.gitignore`.
