---
title: "Wheel: Move workflow cleanup into hook — detect terminal step IDs"
type: improvement
severity: medium
category: hooks
source: manual
github_issue: null
status: prd-created
prd: docs/features/2026-04-04-kiln-wheel-polish/PRD.md
date: 2026-04-04
---

## Description

When a wheel workflow reaches its final step, cleanup (archiving state.json to `.wheel/history/`, removing `.wheel/state.json`) should be handled by the hook itself rather than delegated to a workflow step that the user/agent must execute manually.

The proposal: the hook should detect when the current step has an ID of `success` or `failure` (or a similar convention for terminal steps). When it sees a terminal step ID, the hook automatically:
1. Archives `state.json` to `.wheel/history/success/` or `.wheel/history/failure/` based on the step ID
2. Removes `.wheel/state.json`

This eliminates the current friction where the "no state file" error surfaces when the workflow is already complete but state.json hasn't been cleaned up yet. Instead of treating the missing/stale state file as an error condition, the hook proactively cleans up at the right time.

**Open question:** Should we also remove the "no state file" error entirely, or keep it as a fallback for truly unexpected cases (e.g., state.json deleted mid-workflow)?

## Impact

- Users see confusing "no state file" errors after workflows complete
- Cleanup steps in workflows feel like boilerplate — every workflow needs them
- Hook-based cleanup would be automatic and consistent across all workflows

## Suggested Fix

1. In the wheel hook (`stop.sh` or equivalent), after dispatching the final step, check if the step ID matches a terminal convention (`success`, `failure`, or a `terminal: true` flag in the step definition)
2. If terminal, run the archive + cleanup logic directly in the hook
3. Consider adding a `terminal` boolean field to step definitions as a more explicit alternative to relying on step ID naming conventions
4. Decide whether to remove or soften the "no state file" error
