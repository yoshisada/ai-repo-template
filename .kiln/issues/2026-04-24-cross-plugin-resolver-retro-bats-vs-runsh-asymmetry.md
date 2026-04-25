---
status: open
source: retrospective
prd: cross-plugin-resolver-and-preflight-registry
priority: medium
suggested_command: /kiln:kiln-fix
tags: [retro, prompt-template, test-substrate, ci]
---

# Plan template lets authors name `.bats` fixtures without a bats-availability pre-flight; both implementers had to pivot to `run.sh`

**Date**: 2026-04-24
**Source**: cross-plugin-resolver retrospective; impl-registry-resolver friction note §1 + impl-preprocessor friction note §"Bats was not preinstalled" + auditor friction note §"Test posture vs spec — bats vs run.sh plan deviation"

## Description

Plan §4 of this PRD nominated 4 `.bats` fixtures by name (`registry-path-parse`, `resolve-error-shapes`, `preprocess-substitution`, `preprocess-tripwire`). On the dev box `bats-core` was not installed, and `.github/workflows/wheel-tests.yml` had no bats install step. impl-registry-resolver pivoted `registry-path-parse` and `resolve-error-shapes` to `run.sh` form (existing `agent-resolver/run.sh` convention). impl-preprocessor `brew install`'d bats locally, then added a CI install step. Net result: 2 bats files + 2 run.sh forms for the same kind of test, with no clear principle for which to prefer.

The plan template doesn't require a bats-availability pre-flight check or a preference rule. Authors choose freely; implementers absorb the pivot cost.

## Proposed prompt rewrite

**File**: `plugin-kiln/templates/plan-template.md` (Test fixture authoring guidance) + `plugin-kiln/skills/kiln-build-prd/SKILL.md` (substrate decision rule)

**Current** (plan template): No guidance on bats vs run.sh.

**Proposed** (add to plan-template.md, "Test Surface" or "Phase Gates" section):

```markdown
> **Authoring rule — test fixture format**: the default fixture format is
> `<test-name>/run.sh` (POSIX shell + `bash run.sh` invocation). Use `.bats`
> ONLY if (a) the test naturally benefits from per-`@test` isolation AND
> (b) the plan adds a CI install step for `bats-core` AND (c) the plan
> documents the local-dev install path. If any of (a)/(b)/(c) is unmet,
> default to `run.sh`. Never name `.bats` fixtures alongside `run.sh`
> fixtures in the same PRD without a stated reason — the asymmetry costs
> auditor time.
```

**Why**: The asymmetry was visible to the auditor (logged in `agent-notes/auditor.md`), forced both implementers to reason about substrate independently, and wasted ~10-15 min of impl-preprocessor's time installing bats + adding the CI step. Codifying "run.sh by default" eliminates the choice.

## Forwarding action

- Patch `plugin-kiln/templates/plan-template.md` per above.
- Optional: add a build-prd-skill check that scans `plan.md` for `.bats` mentions and warns if no CI install step is present in `tasks.md`.
