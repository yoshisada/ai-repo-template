# Blockers — escalation-audit

Tracks substrate-blocked or scope-deferred items from the spec.

## SC-006 — Post-merge manual `--check` verification (substrate gap)

**Status**: deferred to post-merge maintainer step.
**Source**: spec.md SC-006; PRD SC-006.
**Carve-out**: B-PUBLISH-CACHE-LAG carve-out 2b — verifying `--check` against the live 81-item roadmap requires THIS PRD's PR to be merged (so `gh pr list --state merged --head <branch>` returns the PR for previously-shipped items). Cannot be exercised in the build session that ships the change.

**Maintainer follow-up** (after this PRD's PR merges):
1. `git checkout main && git pull`
2. Run `/kiln:kiln-roadmap --check`
3. Expected outcomes:
   - The 8 items shipped via PR #186 (already at `state: shipped`) are NOT flagged.
   - Any pre-existing drifted item (`state: distilled | specced` + populated `prd:` + a merged build PR) IS flagged with the PR number and a copy-paste fix command.
4. Apply fix commands as needed; commit cleanup.

This blocker does NOT gate the PR's merge.

## FR-010 — Full `/loop` integration test (substrate gap B-1)

**Status**: V1 verification via direct text assertions on `kiln-build-prd/SKILL.md` Step 6 only.
**Source**: spec.md FR-010, PRD FR-010.
**Reason**: full `/loop` integration test requires a wheel-hook-bound substrate that's not yet shipped. Documented in spec + plan + tasks (T033, T034).
**Follow-on**: when wheel-hook-bound `/loop` substrate lands, add a live integration fixture under `plugin-kiln/tests/build-prd-shutdown-nag-loop-live/`.

This blocker does NOT gate the PR's merge.
