---
title: "require-feature-branch.sh blocks specs/ writes on build/* branches used by /build-prd"
type: bug
severity: high
category: hooks
source: retrospective
github_issue: null
repo: https://github.com/yoshisada/ai-repo-template
status: prd-created
date: 2026-04-10
prd: docs/features/2026-04-24-workflow-governance/PRD.md
files:
  - plugin-kiln/hooks/require-feature-branch.sh
  - plugin-kiln/skills/build-prd/SKILL.md
---

## Description

The PreToolUse hook at `plugin-kiln/hooks/require-feature-branch.sh` blocks `Write`/`Edit` operations on files under `specs/` when the current branch matches `build/*`. The hook only recognises `###-` (three-digit) or `YYYYMMDD-HHMMSS-` prefixes as valid feature-branch naming schemes.

However, `/build-prd` creates pipeline branches with the format `build/<feature-slug>-<YYYYMMDD>` (e.g. `build/wheel-test-skill-20260410`). This format is neither `###-` nor `YYYYMMDD-HHMMSS-`, so the hook refuses any `Write`/`Edit` against `specs/<feature-slug>/` for the entire pipeline run.

Every agent the pipeline spawns — specifier, implementer, auditors, retrospective — ends up needing to write to `specs/<feature-slug>/` (artifacts, `agent-notes/`, `tasks.md` checkbox updates, `blockers.md`). They all hit the hook.

## Impact

**High** — this breaks every future `/build-prd` run in a subtle way:

- Pipeline agents cannot use the `Write`/`Edit` tools for their own spec artifacts
- During the wheel-test-skill pipeline (2026-04-10), two auditors (`audit-compliance`, `audit-smoke`) had to bypass the hook by writing their `agent-notes/*.md` files via Bash heredocs and Python scripts
- Agents that silently fail the Write tool burn tokens retrying or fall back to workarounds that deviate from the spec
- Friction scales with team size: a 5-teammate pipeline produces 5 blocked writes minimum; a complex team with multiple implementers/auditors multiplies that

Observed in the `wheel-test-skill` `/build-prd` run — documented in retrospective issue [#88](https://github.com/yoshisada/ai-repo-template/issues/88) and the pipeline log `.kiln/logs/build-wheel-test-skill-20260410.md`.

## Reproduction

1. Run `/build-prd <any-feature>` — the skill creates a branch named `build/<slug>-<YYYYMMDD>`
2. Any spawned teammate (specifier, implementer, auditor) tries to `Write` or `Edit` a file under `specs/<slug>/`
3. The `PreToolUse:Write` / `PreToolUse:Edit` hook fires `require-feature-branch.sh`
4. Hook checks the current branch name against its allowed patterns, fails to match `build/<slug>-<YYYYMMDD>`, and returns non-zero
5. Claude Code blocks the tool call, surfacing a "blocked by pre-tool-use hook" error to the agent

## Root cause

`plugin-kiln/hooks/require-feature-branch.sh` needs to add `build/*` to its accept list. The `build-prd` pipeline branch naming convention was introduced in the build-prd skill but the hook was never updated to recognise it.

## Suggested fix

Single-line fix in `plugin-kiln/hooks/require-feature-branch.sh`: add `build/*` to the allowed-branch regex. The retrospective issue #88 contains the exact proposed patch.

Alternative (more permissive): allow any branch under `build/` unconditionally, since `build-prd` pipeline branches are always derived from a committed PRD path and the branch name is enforced by the skill itself (`build/<slug>-<YYYYMMDD>`).

## Related

- Retrospective issue: #88
- Pipeline log: `.kiln/logs/build-wheel-test-skill-20260410.md`
- Wheel-test pipeline PR: #87

## Status
Open — proposed fix documented in retrospective #88, awaits implementation.
