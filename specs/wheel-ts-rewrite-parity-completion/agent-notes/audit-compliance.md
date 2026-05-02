# Agent Friction Notes: audit-compliance

**Feature**: Wheel TS Rewrite — Parity Completion (final pass)
**Date**: 2026-05-01

## What Was Confusing

1. **SC-6 diff baseline ambiguity**: The task said `git diff --stat 002-wheel-ts-rewrite..HEAD`. That diff includes changes from ALL parent branches (wait-all-redesign, dispatcher-cascade, this PRD). `shared/state.ts` showed +7 lines in that diff, which looked like a schema change. Took two extra git commands to confirm those lines were from parent branch commits (`11c34aa5` from wait-all-redesign), not from this PRD's commits. The audit instruction should specify the diff base as the cascade tip (`5e61699b`) when checking ONLY this PRD's scope drift.

2. **Coverage display truncation**: The coverage output shows `...07-653,659-660` for uncovered lines in `post-tool-use.ts`. The leading `...` makes it ambiguous whether `handleDeactivate` (lines 474-604) is actually covered or not. Had to run `grep -n "handleDeactivate"` and trace test imports to confirm the 3 hook-deactivate tests DO exercise the new function. The v8 coverage display truncates long line ranges — this makes it hard to audit file-level coverage for large files with many uncovered pre-existing paths.

3. **git grep vs direct grep discrepancy**: `git grep -n "// parity:" plugin-wheel/src/hooks/post-tool-use.ts` returned empty, but direct `grep` found line 613. This wasted a few cycles. Possibly a git index vs working-tree timing issue in the session, or shell encoding. The SC-7 verification command is specified only for `dispatch.ts`; adding `post-tool-use.ts` to the check required a separate invocation.

4. **Contract §4 module path**: The contract said `_teammateChainNext` lives in `dispatch.ts`. impl-wheel moved it to `dispatch-team.ts` (D-4 decision, documented in friction note). The contract was not updated before the signature change, violating Article VII. Found this during Phase B spot-checks when I compared the contract signature to the actual dispatch-team.ts export. Required updating contracts/interfaces.md.

## Where I Got Stuck

1. **Identifying pre-existing vs new coverage gaps**: `post-tool-use.ts` at 23.33% looks alarming. Spent time tracing which lines were pre-existing engine dispatch logic vs new `handleDeactivate` code. The file mixes old code (lines 100-473: activation/state resolution) with new code (474-604: handleDeactivate) — both share the same coverage report with no visual separation. Constitution Article II says "new/changed code" but the tooling reports file-level. There's no automated way to verify "only new functions" coverage without reading the file and cross-referencing line numbers against git diff.

2. **SC-7 verification scope**: The spec says `git grep -n "// parity:" plugin-wheel/src/lib/dispatch.ts` returns ≥1 per gap row. That's the test for dispatch.ts. But FR-008 changes are in `post-tool-use.ts`, which uses JSDoc `* parity:` style for `handleDeactivate`'s docblock + `// parity:` in `main()`. Needed to decide whether the JSDoc form satisfies SC-7. Determined yes (the spirit is preserved; the code-level comment also exists at line 613).

## What Could Be Improved

1. **SC-6 should specify the diff base more precisely**: Instead of `002-wheel-ts-rewrite..HEAD` (cumulative chain), say "diff from last non-this-PRD commit (`git log --oneline | grep -v '^[0-9a-f]\{8\} spec('` to find the boundary)" or just say "diff the parity-completion commits only." In a multi-PRD chain like this one, the cumulative diff makes it hard to attribute schema changes to the right PRD.

2. **Coverage: add new-code-only coverage annotation**: Ideally, the coverage config would exclude pre-existing functions from the 80% gate. One approach: use Istanbul `/* istanbul ignore */` comments on unchanged-in-this-PRD functions. Alternatively, run coverage on only the commits that changed files (requires generating a per-PR coverage diff, which `vitest --coverage` doesn't natively do). For now, auditors should read file diffs before interpreting low coverage numbers.

3. **Contract updates should be part of impl tasks**: The impl-wheel D-4 decision (new module) changed function signatures. The task list had no explicit "if signatures change, update contracts/interfaces.md FIRST" reminder. Adding a `[X] Update contracts/interfaces.md if any signatures changed` checkpoint to each implementation phase would prevent Article VII violations.

4. **Parity comment format in hooks**: `dispatch.ts` uses `// parity:` inline code comments. `post-tool-use.ts` uses JSDoc `* parity:` in the function docblock. These two styles produce different SC-7 grep results. Standardizing on inline `// parity:` inside function bodies (not just docblocks) would make SC-7 verification uniform across all files.

5. **post-tool-use.ts module-gating for tests**: impl-wheel's decision to gate `main()` behind `process.argv[1].endsWith(...)` is correct but means the bulk of the file (lines 107-473: engine dispatch functions) is never imported in tests. These functions ARE tested indirectly via the engine fixtures, but their coverage contribution doesn't show in `post-tool-use.ts`'s file-level stats. A note in research.md or the plan would help future auditors understand this structure.

## Coverage Summary (informational)

| File | Line | Branch | New code exercised? |
|---|---|---|---|
| `dispatch.ts` | 80.63% | 54.11% | ✓ 29 parity-annotated paths |
| `dispatch-team.ts` (new) | 93.15% | 30.95% | ✓ 4 test files |
| `state.ts` | 88.51% | 74% | ✓ archiveWorkflow composition branch |
| `workflow.ts` | 73.52% | 73.33% | ✓ resolveNextIndex/advancePastSkipped/deriveWorkflowPluginDir — error paths in catch blocks only |
| `context.ts` | 66.95% | 30% | ✓ contextCaptureOutput + contextWriteTeammateFiles (main paths); contextBuild pre-existing |
| `post-tool-use.ts` | 23.33% | 55.88% | ✓ handleDeactivate (3 targeted tests); pre-existing lines 107-473 not unit-tested |

## What Worked Well

- impl-wheel's friction note was excellent — the 5 audit-relevant flags matched exactly the things I needed to check (especially the post-tool-use.ts module gating note, the dispatch-cascade test update, and the DEBUG count correction).
- 125/125 tests pass with no flakiness.
- SC-5 (11+6 research.md rows) easy to verify — research.md tables are clean.
- SC-6 (no schema drift) clean once the parent-branch vs this-PRD attribution was sorted.
- The git commit series is clean and PR-readable: each commit is one FR, messages are descriptive.
