# Implementer foundation notes (T-001)

Read of current branch (`build/wheel-wait-all-redesign-20260430`, folds into `002-wheel-ts-rewrite`) on 2026-04-30.

## `dispatchTeamWait` shape

`plugin-wheel/src/lib/dispatch.ts:425–612` — 188 lines (function span). Three top-level branches:

- `hookType === 'stop'` (lines 452–491): pending→working transition, count completed/failed, mark step done if all done, else block.
- `hookType === 'post_tool_use'` (lines 492–545): inline `Agent` registration (sets `agent_id = name@team_name`, status running) AND inline `TaskUpdate` matcher (substring match on `subject`/`name` to flip teammate `completed`). Then re-counts and marks done.
- `hookType === 'teammate_idle'` (lines 546–608): builds `<name>@<team_name>`, scans live `.wheel/state_*.json` for that `alternate_agent_id`, infers archive when none found and flips teammate to `completed`. Re-checks all-done. **This is the branch FR-003 mandates removing.**

No archive helper called from here — archive is the shell `_archive_workflow` (`plugin-wheel/lib/dispatch.sh:122–321`).

## TS `archiveWorkflow`

**Does not exist.** `grep -rn "archiveWorkflow\|history/success" plugin-wheel/src/` → 0 hits. Need to author per contract; behavioral reference is shell `handle_terminal_step` + `_archive_workflow` at `plugin-wheel/lib/dispatch.sh:226–321` (rename + bucket-selection: `state.status == "failed"` OR step `status == "failed"` OR step id contains "failure" → `failure/` else `success/`).

## `lock.ts` API surface

`plugin-wheel/src/lib/lock.ts` — mkdir-based locking (NOT flock; the plan/contract's "flock" terminology is shorthand for the project's atomic lock primitive):

- `acquireLock(lockPath: string, ttlMs?: number = 30000): Promise<boolean>` — `mkdir` lock dir; TTL cleanup via `setTimeout`.
- `releaseLock(lockPath: string): Promise<void>` — `rm -rf` lock dir.
- `withLock<T>(lockPath, fn): Promise<T>` — convenience wrapper. **This is what FR-001/004 should use.**

Lock path convention: caller passes a path; helper appends `.lock` if absent.

## `log.ts` API surface

`plugin-wheel/src/lib/log.ts:20` — `logHookEvent(event: HookEvent): Promise<void>` writes pipe-delimited line to `.wheel/hook-events.log`. Schema: `timestamp | hookType | toolName | sessionId | agentId | decision | error`.

**Does NOT match the FR-008 phase-tagged contract.** Plan says "implementer confirms actual signature at impl start and adapts callers". I will add a sibling helper `wheelLog(phase: string, fields: Record<string, unknown>)` (or extend `logHookEvent`) that appends to `.wheel/wheel.log` with phase + JSON-style fields, and call it from `stateUpdateParentTeammateSlot` and `_runPollingBackstop`. Keeping the new helper next to `logHookEvent` so the existing log surface is undisturbed.

## Hook-routing entry point for `teammate_idle` / `subagent_stop`

- `plugin-wheel/src/hooks/teammate-idle.ts` (26 lines) → `engineHandleHook('teammate_idle', ...)`.
- `plugin-wheel/src/hooks/subagent-stop.ts` (26 lines) → `engineHandleHook('subagent_stop', ...)`.
- `plugin-wheel/src/lib/engine.ts:73 engineHandleHook` reads parent state, gets cursor, calls `dispatchStep(step, hookType, ...)`. The hook type is plumbed straight to `dispatchTeamWait`, where the dead `teammate_idle` branch lives.

FR-005 lands in **`engine.ts`** (or a thin wrapper) — when current step is `team-wait`, remap `teammate_idle`/`subagent_stop` → `post_tool_use` before reaching `dispatchTeamWait`. That keeps hook entry points unchanged (each is 26 lines of stdin→engine glue) and centralizes the routing.

## Reconciliation notes for the spec

- **Specifier flag (3) — Agent/TaskUpdate inline registration**: Confirmed it lives only in `dispatchTeamWait`'s `post_tool_use` branch (lines 496–522). The `Agent` (spawn) registration block sets `teammates[name].agent_id = "<name>@<team_name>"`. `dispatchTeammate` does NOT do this — it only adds slots with `agent_id = name`. So binding the harness-assigned agent_id to the slot today *only* happens here. Per Phase 2 plan + my read: I'll move this to `dispatchTeammate` (the slot owner) to keep the wait-step pure. Will document the move in the implementer friction note when I finish Phase 2.
- **Specifier flag (1) — no TS archive helper**: Confirmed; FR-009 means I author one in `state.ts`.
- **Specifier flag (2) — `failure_reason`**: Optional additive field on `TeammateEntry`. `plugin-wheel/src/shared/state.ts:62–70` does NOT include it today. I will extend the type with `failure_reason?: string` (FR-010 explicitly calls this out as the only schema addition).
