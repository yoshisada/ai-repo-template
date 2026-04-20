# Plan/tasks templates assume bats, repo doesn't have it

**Source**: GitHub #115 (manifest-improvement retrospective), "second quarter in a row"
**Priority**: medium
**Suggested command**: `/build-prd` — update `plugin-kiln/skills/plan/SKILL.md` to detect test-framework availability at plan time and prescribe pure-bash tests when bats is absent
**Tags**: [auto:continuance]

## Description

Two features this quarter (manifest-improvement-subroutine and one prior) had plans prescribing `.bats` test files — then implementers had to rewrite every test task to `.sh` because `bats` isn't installed. Fix options: (1) add `bats` as a dev dependency in `plugin-kiln/package.json`, or (2) update `/kiln:plan` to run `command -v bats vitest pytest npx` against the repo before selecting test extensions and prescribe pure-bash `tests/**/*.sh` when bats is absent. Rote rewriting ~10 min per feature.
