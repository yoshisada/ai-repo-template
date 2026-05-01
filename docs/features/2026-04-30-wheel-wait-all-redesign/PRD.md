# Feature PRD: Wheel `wait-all` Redesign — Inverted Control + Polling Backstop

## Parent Product

Wheel — hook-based workflow engine plugin (`plugin-wheel/`). See repo `CLAUDE.md` for product context (kiln/clay/shelf/trim/wheel plugin family). This PRD **folds into the in-progress TypeScript rewrite** on branch `002-wheel-ts-rewrite`. The pipeline branches from the current rewrite HEAD, builds on top of the existing in-progress dispatch.ts / state.ts / hook changes already committed during the rewrite, and ships as part of the same PR. After this work lands on `main`, Phase 4 team-workflow fixtures (`team-static`, `team-dynamic`, `team-partial-failure`) move from known-failing to passing.

## Feature Overview

Replace wheel's event-driven `dispatch_team_wait` with **inverted control**: child sub-workflows update their parent's teammate slot directly during archive, instead of the parent listening for `teammate_idle` / `subagent_stop` hooks. Add a defensive polling re-check on the parent's `post_tool_use` as a backstop for force-killed children that never reach the archive path.

After this change, parent workflows with a `team-wait` step advance correctly when all teammate sub-workflows complete, regardless of hook-routing edge cases or harness-induced agent-name suffixes.

This work folds into the 002-wheel-ts-rewrite branch. The implementation builds on the in-progress dispatch.ts and state.ts already committed on that branch — it does NOT replace them, it extends them with the inverted-control behavior plus the polling backstop.

## Problem / Motivation

The current `dispatch_team_wait` is broken in practice. Phase 4 team-workflow fixtures fail every run, even though all teammate sub-workflows complete and archive successfully. Root cause is a chain of three independent failure modes in the event-driven design:

1. **`guard.sh` resolves `teammate_idle` to the deepest leaf state file.** When a teammate's sub-workflow is still active, `teammate_idle` for that teammate resolves to the CHILD state file (cursor=1 do-work), not the parent. The handler runs against the child, the parent never sees the idle event in its own context, and `state_update_teammate_status` is never called on the parent.
2. **Once the child archives, the next `teammate_idle` fires with name-suffixed teammate identifiers.** Claude Code's harness suffixes Agent names when re-spawning (`worker-1-2`, `worker-2-2`). The wheel hook receives these suffixed names. `state_update_teammate_status` does a literal-name lookup against the parent's `teams.<id>.teammates` dict, which only contains the ORIGINAL names (`worker-1`, `worker-2`). Lookup fails silently, status update is a no-op.
3. **Result: parent's `wait-all` step (e.g., cursor=5) stays `pending` forever.** Workflow never advances to the post-wait steps (`report`, `cleanup`, `team-delete`). Orphan state files accumulate. The only way out is `deactivate.sh`.

This was confirmed empirically on 2026-04-30 by running `tests/team-static` in an isolated subprocess (env-wiped `claude --print` per `plugin-wheel/docs/isolated-workflow-testing.md`): all 3 worker sub-workflows archived to `history/success/`, the parent's `dispatch_team_wait` was invoked correctly via `post_tool_use`, but the parent's teammate slots stayed at `status: running` indefinitely. Wheel.log shows `teammate_idle` firing with suffixed names that don't match the parent's teammate dict.

The architectural failure mode is deeper than any of the three specific bugs: **the parent's state advance is reactive to events that may or may not fire in the right context with the right names**. Hooks are imprecise signals for cross-process synchronization. Each new edge case (harness change, cwd weirdness, name mangling) produces a new wait-all stall.

## Goals

- **G1**: Phase 4 team-workflow fixtures (`team-static`, `team-dynamic`, `team-partial-failure`) pass end-to-end with no orphan state files.
- **G2**: Eliminate hook-routing as the failure mode for `team-wait` advancement. The cross-process signal is a deterministic file write, not a hook event.
- **G3**: Survive force-killed children. If a teammate sub-workflow terminates without reaching the archive path, the parent's `wait-all` recovers via the polling backstop on its next `post_tool_use`.
- **G4**: Simplify `dispatchTeamWait` from 4 dispatch branches (`stop` / `post_tool_use` / `subagent_stop` / `teammate_idle`) to ≤2 (`stop` / `post_tool_use`) by deleting hook-event-specific logic in favor of pure state-driven re-checks.

## Non-Goals

- **Not a port of the shell `dispatch_team_wait`.** The shell version is broken; this PRD does NOT preserve its behavior. Byte-identity claims in the wheel-typescript-rewrite PRD do not apply to `dispatch_team_wait` — this is an explicit, documented behavioral change. The 002-wheel-ts-rewrite spec MUST be amended (or this PRD's spec.md MUST explicitly override) to allow this deviation.
- **Not a rewrite of `team-create` / `team-delete` / teammate spawn.** Those primitives work today and stay as-is. Only `team-wait` and the archive function change.
- **Not a discard of in-progress fix code.** Any dispatch.ts / state.ts / hook changes already committed on the 002-wheel-ts-rewrite branch as of pipeline start are PRESERVED — the pipeline builds on top, it does not reset to main. The implementer reads the current branch state as their starting point.
- **Not a fix for shell wheel.** Shell wheel stays broken on Phase 4. The fix lands in TS only.
- **Not a redesign of `parent_workflow` semantics for plain workflow composition.** Composition (`type: workflow` step) already works via `_chain_parent_after_archive` and is out of scope. This PRD adds a peer code path for `team-wait` parents without touching the composition path.
- **Not lock-protocol generalization.** Existing per-state-file `flock` is reused. No new lock primitives.
- **Not a new step type.** `team-wait` step type stays. Workflow JSON schema unchanged.

## Target Users

Inherited from parent product. Specifically benefits:

- **Wheel workflow authors** writing team workflows — they get reliable `wait-all` semantics so a fan-out + join pattern actually works.
- **Kiln pipeline maintainers** — `/kiln:kiln-build-prd` uses agent teams; reliable `wait-all` is a precondition for any team-driven pipeline step.
- **Anyone running `/wheel:wheel-test`** — Phase 4 fixtures stop being permanent red.

## Core User Stories

1. **As a workflow author**, I activate a `team-static` workflow, the wheel ceremony spawns 3 teammates, all 3 sub-workflows complete and archive, and the parent's `wait-all` step advances within seconds of the last archive — without me writing any sentinel files or running `wheel-stop` to recover.
2. **As a workflow author**, one of my 3 teammates is force-killed mid-execution (no graceful archive). On the parent's next `post_tool_use`, the polling backstop detects the missing state file, marks the teammate `failed`, and the parent advances with a recorded failure — instead of stalling forever.
3. **As a kiln pipeline maintainer**, I run `/wheel:wheel-test` and see Phase 4 fixtures (`team-static`, `team-dynamic`, `team-partial-failure`) all pass green. Total Phase 4 wall time is <90s.
4. **As a wheel internals reader**, I open `dispatchTeamWait` in TS source and find a single short function with one re-check helper — not a 4-branch switch handling event types I have to mentally trace through `guard.sh`.

## Functional Requirements

### FR-1 — Archive function updates parent teammate slot

The TS archive helper (the function that moves `.wheel/state_<x>.json` → `.wheel/history/<bucket>/<archive>.json`) MUST, before performing the rename:

1. Read the child's state. If `state.parent_workflow == null`, skip to step 3 (composition-or-orphan; no parent update needed by this PRD).
2. Open the parent state file at `state.parent_workflow`. Match the child's `alternate_agent_id` against the parent's `teams[<team_id>].teammates[<name>].agent_id` field. If a match is found:
   - Set `parent.teams[<team_id>].teammates[<name>].status` to `"completed"` (when archiving to `history/success/`) or `"failed"` (when archiving to `history/failure/`).
   - Set `parent.teams[<team_id>].teammates[<name>].completed_at` to current ISO-8601 UTC.
   - Persist parent state under the parent's `flock`.
3. Continue with the archive rename.

If parent state file is missing (parent already archived or stopped), log a warning and proceed with archive without the parent update.

### FR-2 — Archive function advances parent cursor when wait-all is satisfied

After FR-1's parent state update, IF the parent's current step (`parent.steps[parent.cursor]`) has `type == "team-wait"` AND `team` field matches the team_id whose slot was just updated AND every teammate in `parent.teams[<team_id>].teammates` has `status` of `"completed"` or `"failed"`:

1. Mark the parent's `team-wait` step `status: "done"`, set `completed_at`, write summary `output` per existing `_team_wait_complete` semantics.
2. Advance the parent's cursor to `step + 1` (or run `advance_past_skipped` if the next step is conditionally skipped).
3. Persist parent state under parent's `flock`.

If the parent is at a different cursor (e.g., already past `wait-all` because a sibling teammate raced ahead), do NOT advance — just leave the slot update from FR-1 in place. The status update is idempotent.

### FR-3 — `dispatchTeamWait` simplifies to two branches

After FR-1 and FR-2 land, `dispatchTeamWait` MUST collapse to:

- **`stop` branch**: if `step.status == "pending"`, transition to `"working"`. Re-read teammate statuses. If all teammates have `status` of `"completed"` or `"failed"`, run `_team_wait_complete`. Otherwise emit `{"decision": "approve"}` so the parent goes idle and waits.
- **`post_tool_use` branch**: same re-check logic. If all done, run `_team_wait_complete`. Otherwise emit `{"hookEventName": "PostToolUse"}`.

The `subagent_stop` and `teammate_idle` cases collapse into the `post_tool_use` re-check (any nudge triggers the same pure check). The function MUST NOT contain branch-specific logic that mutates teammate status — all status mutations come from FR-1.

### FR-4 — Polling backstop on parent post_tool_use

The `post_tool_use` re-check (FR-3) MUST also detect orphaned teammates whose state files are gone but who never received an FR-1 update (force-kill, OS crash, write failure between FR-1 and the rename). For each teammate currently `status == "running"`:

1. Check whether `.wheel/state_<*>_<*>.json` with `alternate_agent_id` matching this teammate exists. If found, teammate is still working — skip.
2. If no matching state file, scan `.wheel/history/{success,failure,stopped}/` for an archive whose `parent_workflow` (recorded inside the archived state) equals THIS parent's state file path AND whose `alternate_agent_id` matches this teammate.
   - If found in `success/` — set teammate `status: "completed"`, `completed_at: now`.
   - If found in `failure/` or `stopped/` — set teammate `status: "failed"`, `completed_at: now`.
   - If not found anywhere — set teammate `status: "failed"` with `completed_at: now` and a marker field (e.g., `failure_reason: "state-file-disappeared"`). This is the orphan-recovery path.
3. After all `running` teammates are reconciled, run the FR-3 done-check.

Backstop sweeps run on every parent `post_tool_use`. Cost is bounded: ≤N `stat` calls + at most one `ls` of three small directories per parent hook.

### FR-5 — TeammateIdle and SubagentStop become wake-up nudges only

The `teammate_idle` and `subagent_stop` hook handlers MUST NOT contain `team-wait`-specific status update logic. They MUST:

1. Resolve the parent state file (same logic as today, walking up `parent_workflow` from the resolved leaf).
2. If the parent's current step is `team-wait`, dispatch to `dispatchTeamWait` with `hook_type: "post_tool_use"` (the same re-check path).
3. Otherwise, no-op (return `{"decision": "approve"}`).

Their only role is to wake the parent up. The actual status update happens via FR-1 (primary) or FR-4 (backstop).

### FR-6 — Failure semantics

When a child's terminal step marks the workflow `status: "failed"` (the workflow archives to `history/failure/`), FR-1 MUST set the parent teammate's `status: "failed"`. The parent's `_team_wait_complete` continues to honor the existing `fail_fast` / `min_completed` workflow JSON options — those are not changed by this PRD.

### FR-7 — Concurrent teammate archive correctness

Two teammates archiving simultaneously MUST both update the parent state correctly without losing either update. Each teammate's FR-1 update operates on disjoint fields (`parent.teams[<team_id>].teammates[<name>]` for distinct `<name>`s). Updates MUST acquire the parent's `flock` before reading and hold it through the write. Lock ordering is child→parent (each teammate releases its own lock before taking the parent's, OR holds both with the child lock taken first). Lock ordering invariant: nothing in wheel takes the child lock while holding the parent lock. This invariant MUST be documented in `state.ts` next to the locking helpers.

### FR-8 — Logging

Every FR-1 invocation MUST emit a wheel.log entry with phase `archive_parent_update` recording: child's `alternate_agent_id`, parent state file path, team_id, teammate name, new status, whether parent cursor advanced (FR-2 fired or skipped). Every FR-4 backstop sweep MUST emit a wheel.log entry with phase `wait_all_polling` recording: parent state file path, team_id, count of teammates reconciled, count still running.

## Absolute Musts

1. **Tech stack**: TypeScript (strict mode), Node.js 20+, `fs/promises`, `path`, no external npm deps. Inherited from `002-wheel-ts-rewrite` PRD. Same lockfile mechanism (`flock`-equivalent atomic write — whatever the rewrite chose).
2. **No regression in Phases 1–3**. `command`, `branch`, `loop`, `agent`, `workflow` (composition) step types and the existing `_chain_parent_after_archive` path stay byte-identical to the rewrite's behavior. This PRD adds a peer code path; it does not modify composition.
3. **No new public schema**. Workflow JSON schema (`team-wait` step shape, `team-create` step shape, `teammate` step shape) unchanged.
4. **Folds into the 002-wheel-ts-rewrite branch**. Pipeline branches from current rewrite HEAD, builds on existing in-progress fix code (do NOT reset, do NOT discard), and ships as part of the rewrite's PR. This PRD does not modify shell wheel.
5. **Phase 4 fixtures are the acceptance test**. `team-static`, `team-dynamic`, `team-partial-failure` MUST pass end-to-end with zero orphan state files when this PRD is implemented and `/wheel:wheel-test` runs them.

## Tech Stack

Inherited from `002-wheel-ts-rewrite` PRD. No additions or overrides.

## Impact on Existing Features

| Area | Impact |
|---|---|
| `dispatchTeamWait` | **Replaced**. Old 4-branch event-driven design removed. New 2-branch state-driven design. |
| `archiveWorkflow` (in `state.ts` or wherever the archive function lives) | **Extended**. New parent-update + cursor-advance block before the rename. |
| `subagent_stop` hook handler | **Simplified**. Loses team-wait-specific status update logic; becomes a wake-up nudge. |
| `teammate_idle` hook handler | **Simplified**. Same as above. |
| `_chain_parent_after_archive` (workflow composition path) | **Unchanged**. Composition continues to work via the existing path. |
| `team-create`, `team-delete`, `teammate` step dispatchers | **Unchanged**. |
| Workflow JSON schema | **Unchanged**. |
| `state_*.json` schema | **Unchanged**. Same `teams[<id>].teammates[<name>]` shape. |
| Phase 4 test fixtures | **Start passing**. No fixture changes required; behavior change makes them pass. |
| `/wheel:wheel-test` skill | **Unchanged**. Same Phase 4 ceremony, but it actually completes now. |
| Shell wheel | **Unchanged**. Stays broken on Phase 4. |

## Success Metrics

1. **SC-1**: All three Phase 4 fixtures (`team-static`, `team-dynamic`, `team-partial-failure`) pass on `/wheel:wheel-test`. Measured by exit-0 of the full test run with no orphan state files left in `.wheel/`. Verified within 1 week of merge.
2. **SC-2**: `dispatchTeamWait` source size shrinks by ≥30% (line count) versus the rewrite's first-cut TS port that mirrors shell. Measured by `wc -l` on the function in `plugin-wheel/src/lib/dispatch.ts` before/after this PRD.
3. **SC-3**: Force-kill recovery works. Manual test: activate `team-static`, kill one worker process before its archive completes, observe parent advance via FR-4 backstop within 30s. Verified during PR review.

## Risks / Unknowns

- **R-1**: Cross-state-file lock ordering bug. If something else in wheel ever takes the child lock while holding the parent lock, FR-7's invariant breaks and a deadlock becomes possible. Mitigation: document the invariant in `state.ts`, add an audit pass in `audit-compliance` that greps for any code path holding two state-file locks simultaneously.
- **R-2**: Archive function failure between FR-1 (parent update) and rename. If the parent update succeeds but the rename fails, the parent thinks the teammate is done while the child state file still exists. Mitigation: order is "parent update first, then rename" — if rename fails, child state stays as a re-runnable workflow; the parent's slot is idempotent (a second pass at the same teammate produces the same `completed` status).
- **R-3**: Parent at unexpected cursor when child archives. Sibling teammate may have raced and already advanced parent past `wait-all`. Mitigation: FR-2 explicitly guards on "parent at this team-wait step" before advancing; otherwise just leaves the slot update in place.
- **R-4**: Composition + team interaction. A `workflow`-step parent that contains a `team-wait` child — does FR-2's cursor advance interact correctly with `_chain_parent_after_archive`? Mitigation: this PRD's archive logic is "first try team-wait update via FR-1, then fall through to the existing composition path." The two paths are disjoint by parent step type.
- **R-5**: Polling backstop emits false positives. If FR-4 sweeps before a slow archive completes, it might mark a teammate `failed: state-file-disappeared` while the archive is in flight. Mitigation: FR-4 checks for archives in `history/{success,failure}/` BEFORE concluding orphan. Order of FR-4's checks matters — codify in spec/plan.
- **R-6**: Test fixtures currently asserting broken behavior. Unlikely (the fixtures expect Phase 4 to work) but worth a 5-minute audit during planning.

## Assumptions

- This PRD ships as part of the 002-wheel-ts-rewrite branch, not as a separate fast-follow. The rewrite spec (or this PRD's spec.md) is amended to allow the deviation in `dispatch_team_wait` behavior.
- The implementer reads the CURRENT state of `plugin-wheel/src/lib/dispatch.ts`, `state.ts`, and the shell→TS hook bindings at pipeline-start as the foundation. They extend, not replace.
- The TS rewrite preserves the `state_*.json` schema, including the `teams.<id>.teammates.<name>.agent_id` and `teams.<id>.teammates.<name>.status` fields. Verified by reading `plugin-wheel/src/lib/state.ts` at PRD time.
- `child.parent_workflow` reliably contains the absolute path to the parent's state file after teammate spawn. This is the existing contract — verified by inspecting Phase 4 sub-workflow state files (`alternate_agent_id`, `parent_workflow` are both present).
- Wheel's archive function is a single deterministic call path — every workflow that archives goes through it. (Verified for the shell version; the rewrite preserves this.)
- The polling backstop's `ls .wheel/history/<bucket>/` cost is acceptable on every parent `post_tool_use`. With <100 archived workflows in a typical session, this is a few ms per hook.

## Open Questions

- **Q1**: Should FR-4's "state-file-disappeared" failure mode include a configurable grace window (e.g., wait 5s after detecting a missing state file before declaring orphan)? Current spec says immediate — that may produce false positives during slow archives. Defer to plan-time research.
- **Q2**: When the parent's `team-wait` advances via FR-2, should it ALSO chain into the next `team-delete` step automatically (via `dispatch_step` recursion), or should it stop after the cursor bump and wait for the next parent hook fire? Current spec says "stop after cursor bump" — but this means an extra parent tool call is needed to dispatch `team-delete`. Defer to plan-time.
- **Q3**: Does the wheel-test-runner harness need any updates to run Phase 4 fixtures cleanly (e.g., timeout adjustments)? Probably not, but verify during planning.
