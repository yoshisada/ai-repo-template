# Specifier Agent Friction Notes

**Agent**: specifier
**Feature**: wheel-create-workflow
**Date**: 2026-04-06

## What was confusing or unclear

- The `/specify` skill template includes placeholders like `$ARGUMENTS` and references to scripts (`.specify/scripts/bash/create-new-feature.sh`) that assume a fresh branch needs to be created. Since the branch already existed (`build/wheel-create-workflow-20260406`), the step 2 instructions about running `create-new-feature.sh` were not applicable. Unclear whether to run it anyway or skip it.

- The `/plan` skill references `quickstart.md` as a Phase 1 output, but for a plugin skill (SKILL.md with no test suite), there is no meaningful quickstart to generate. The template lists it as expected output but it's not always relevant.

- The PRD says loop step `condition` "exits 0 to continue" but the actual `loop-test.json` workflow uses `condition` that "exits 0 to stop". This contradiction required checking the real implementation to resolve. The research.md documents this finding.

## Where I got stuck

- Did not get stuck. The PRD was well-written and the existing workflow JSON examples provided clear schema references. Having `workflow_load` source code available made validation requirements unambiguous.

## What could be improved

- The `/specify` skill should detect when it's running on an existing feature branch and skip the branch creation steps entirely, rather than requiring the agent to figure this out.

- The `/plan` skill should make `quickstart.md` optional/conditional rather than listing it as expected output for all project types. Plugin skills don't benefit from a quickstart.

- The templates could include a note about how to handle the case where all tasks modify a single file (common for SKILL.md-based features). The task template assumes multi-file projects with parallel opportunities.

- The constitution references old skill names (`/speckit.specify`) in the Development Workflow section — should be updated to current names (`/specify`).
