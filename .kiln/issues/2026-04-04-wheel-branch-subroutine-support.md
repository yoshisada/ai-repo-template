---
title: "Wheel engine needs step-level `next` field for branch subroutines"
type: improvement
severity: high
category: workflow
source: manual
github_issue: null
status: prd-created
prd: docs/features/2026-04-04-kiln-wheel-polish/PRD.md
date: 2026-04-04
---

## Description

The wheel engine uses a flat step array with linear cursor advancement (cursor+1). After a branch step routes to a target, the engine correctly jumps to that step, but when the target step completes, the cursor advances linearly into the other branch path (e.g., `cleanup-success` finishes → cursor advances into `cleanup-failure`).

This makes mutually exclusive branches and multi-step subroutines impossible with the current model.

**Proposed fix:** Add a step-level `next` field. After a step completes, if `next` is set, jump to that step ID instead of cursor+1. If `next` is omitted on a branch path's last step, the workflow ends. This enables:
- Mutually exclusive branch paths (each path's last step omits `next` or points to a merge step)
- Multi-step subroutines within a branch (chained via `next`)
- Early termination (omit `next` to end the workflow)

Engine changes needed:
- `dispatch_agent`: check for `next` field before defaulting to `step_index + 1`
- `dispatch_command`: same check
- `dispatch_branch`: already jumps by ID, no change needed
- Optionally add an `end` step type for explicit termination

## Impact

Any workflow with branch steps that have mutually exclusive paths will run both paths. This blocks realistic use of conditional logic in workflows.

## Suggested Fix

Add `next` field support to `dispatch_agent` and `dispatch_command` in `plugin-wheel/lib/dispatch.sh`. When a step has a `next` field, resolve the target step ID to an index via `workflow_get_step_index` and set the cursor there instead of `step_index + 1`.
