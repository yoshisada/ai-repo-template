# Research: Wheel `wait-all` Redesign

**Feature**: wheel-wait-all-redesign
**Branch**: `build/wheel-wait-all-redesign-20260430` (folds into `002-wheel-ts-rewrite`)
**Created**: 2026-04-30

## Baseline (SC-2 reconciliation)

| Field | Value |
|---|---|
| File | `plugin-wheel/src/lib/dispatch.ts` |
| Function | `dispatchTeamWait` |
| Span | line 425 → first matching `^}` (terminal close brace) |
| Measurement command | `awk 'NR>=424 { print; if (/^}/ && NR>424) { exit } }' plugin-wheel/src/lib/dispatch.ts \| wc -l` |
| **Baseline line count** | **189 lines** (including leading comment + trailing `}`) |
| Date measured | 2026-04-30 |
| Branch HEAD when measured | `build/wheel-wait-all-redesign-20260430` (first-cut TS port that mirrors shell behavior) |

### SC-2 target translation

PRD SC-2 says ≥30% reduction. Applied to baseline 189 lines:
- 30% reduction ⇒ remove ≥57 lines
- **Absolute ceiling: ≤132 lines** (189 × 0.70 = 132.3, floor to 132)

The current function contains 4 explicit branches (`stop`, `post_tool_use`, `teammate_idle`, plus an implicit fall-through approve). FR-3 collapses to 2 branches (`stop`, `post_tool_use`). The `teammate_idle` branch alone is 64 lines (lines 546–608). Removing that branch plus the inline `TaskUpdate` / `Agent` mutation logic in the `post_tool_use` branch (≈30 lines) plausibly hits the ≤132-line target without aggressive golf. Target is reachable without acrobatics.

### Reconciliation status

✅ Baseline captured against live branch state. Target (≤132 lines) is reachable. PRD SC-2 stands as written; no recalibration needed.

## Archive function location

`grep -rn "archiveWorkflow\|archive_workflow\|history/success\|history/failure"` returns **zero matches** in `plugin-wheel/src/`. The TS rewrite has not yet ported the archive helper from `plugin-wheel/lib/dispatch.sh`. The shell archive logic lives in `plugin-wheel/lib/dispatch.sh` around lines 122–318 (the `_archive_workflow` block) and is invoked at terminal-step transitions in shell dispatch.

**Implication for the implementer**: FR-1 / FR-2 require a TS archive helper. The implementer either:
- (a) ports the shell archive function to TS as part of this PRD's scope, OR
- (b) extends the existing in-progress TS archive helper if one has been added between PRD time and impl start.

The plan MUST instruct the implementer to inspect `plugin-wheel/src/lib/state.ts` and `dispatch.ts` at impl start and wire FR-1/FR-2 into whichever file owns the rename-to-history step. If no archive helper exists yet in TS, FR-1/FR-2 author the new TS helper (`archiveWorkflow` in `state.ts`) using shell `_archive_workflow` as the behavioral spec for the rename + bucket-selection logic.

## Existing teammate-status helpers

`plugin-wheel/src/lib/state.ts`:
- `stateAddTeammate(stateFile, teamStepId, teammate)` — registers teammate under `teams[<id>].teammates[<agent_id>]`
- `stateUpdateTeammateStatus(stateFile, teamStepId, agentName, status)` — mutates `teams[<id>].teammates[<agentName>].status` and stamps `started_at` / `completed_at`

These helpers operate on the LOCAL state file. FR-1 needs a sibling helper that mutates the PARENT state file (different file, requires parent's `flock`). The plan should extend `state.ts` with `stateUpdateParentTeammateSlot(parentStateFile, teamId, teammateName, status)`.

## Locking primitives

`plugin-wheel/src/lib/lock.ts` exists. Inspect during plan phase to confirm it supports per-file locking (one lock per state file path). FR-7's child→parent lock-ordering invariant builds on this.

## Open question deferrals

Q1 (state-file-disappeared grace window), Q2 (cursor advance chains team-delete?), Q3 (test-runner timeout adjustments) — deferred to plan phase per PRD. Plan author should resolve these before tasks.md.

## References

- PRD: `docs/features/2026-04-30-wheel-wait-all-redesign/PRD.md`
- Parent rewrite spec: `specs/002-wheel-ts-rewrite/`
- Shell archive: `plugin-wheel/lib/dispatch.sh:122–318`
- Current `dispatchTeamWait`: `plugin-wheel/src/lib/dispatch.ts:425–612`
- Isolated-test recipe (used to confirm bug): `plugin-wheel/docs/isolated-workflow-testing.md`
