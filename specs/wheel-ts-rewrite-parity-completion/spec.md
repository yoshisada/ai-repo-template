# Feature Spec: Wheel TS Rewrite — Parity Completion (final pass)

**Branch**: `build/wheel-ts-rewrite-parity-completion-20260501`
**PRD**: `docs/features/2026-05-01-wheel-ts-rewrite-parity-completion/PRD.md`
**Constitution**: `.specify/memory/constitution.md` (v2.0.0)
**Status**: Spec — pending plan
**Foundation chain**: parity-completion → cascade (PR #200) → wait-all-redesign → 002-wheel-ts-rewrite

## 1. Overview

Audit every TypeScript dispatcher and every TypeScript hook entry point against the canonical shell wheel (`~/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.842/`), enumerate every behavioural gap in `research.md` (§dispatcher-audit, §hook-audit), and fix every gap in this branch. After this PRD lands, `/wheel:wheel-test` Phases 1–4 pass cleanly with the working-tree TS dist deployed to the plugin cache and `npx vitest run --coverage` produces a usable coverage report.

This is a **parity-completion sweep, not a redesign**. The shell wheel is the spec; TS replicates its observable behaviour for every step type and hook. New step types are out of scope. New hook event types are out of scope. New workflow-JSON or state-JSON schema fields are out of scope.

The implementer extends in-progress code on this branch (cascade tails, wait-all archive helper, engineInit-in-hooks, workflow_definition persistence). Parent-branch decisions are FROZEN — this PRD does not relitigate them.

## 2. User Stories (Given / When / Then)

### US-1 — Every fixture under `workflows/tests/` runs to completion
**Given** the working-tree TS dist deployed to plugin cache and `.wheel/state_*.json` cleaned,
**When** I run `/wheel:wheel-test`,
**Then** all 13 fixtures (Phases 1–4) report 100% pass with 0 orphan state files in `.wheel/`. Total wall-clock budget for the run is < 10 minutes.

### US-2 — count-to-100 closes #199 and runs in <5 s
**Given** a workflow `count-to-100` with `loop` step `max_iterations: 101` whose substep is a `command`,
**When** activation fires,
**Then** the loop self-cascades through all 101 iterations inside one or a small number of hook invocations and the workflow archives in < 5 s wall-clock. Baseline: 60 s per-phase timeout (workflow never completed in current TS).

### US-3 — Loop reads `max_iterations` from workflow definition
**Given** a `loop` step whose workflow JSON specifies `max_iterations: 50` (any value other than 10),
**When** the loop runs,
**Then** it iterates up to 50 times before exhaustion, regardless of what value (if any) is in `state.steps[i]`. The `max_iterations` field is read exclusively from the workflow definition (`step.max_iterations`).

### US-4 — Phase 4 team fixtures pass end-to-end
**Given** the three team fixtures (`team-static`, `team-dynamic`, `team-partial-failure`),
**When** `/wheel:wheel-test` runs Phase 4,
**Then** each fixture: (a) creates the team via TeamCreate; (b) spawns teammates with context files written to `.wheel/outputs/team-<name>/<agent>/` and `assign_inputs.json`; (c) waits for teammate completion via team-wait (with summary.json output written); (d) deletes the team via TeamDelete; (e) archives the parent workflow to `.wheel/history/success/` (or `.wheel/history/failure/` for partial-failure).

### US-5 — `/wheel:wheel-stop` actually stops the workflow
**Given** an active workflow with state file at `.wheel/state_<id>.json`,
**When** I run `/wheel:wheel-stop` (which invokes `bin/deactivate.sh`),
**Then** the post-tool-use TS hook detects the deactivate, archives the state file to `.wheel/history/stopped/`, cascades stop to child / teammate workflows, and emits `{hookEventName: "PostToolUse"}`. Currently TS only emits the hook event; the archive logic is missing.

### US-6 — `npx vitest run --coverage` produces a coverage report
**Given** `package.json` has been updated per FR-009,
**When** I run `npx vitest run --coverage` from `plugin-wheel/`,
**Then** the command exits 0 (or non-0 only because of test failures) and prints a coverage summary table. Currently it errors with `BaseCoverageProvider import failure`.

### US-7 — Internals reader sees parity comments tracing every fix to a shell line
**Given** a developer opens any TS dispatcher fixed by this PRD,
**When** they read the function body,
**Then** every behavioural change is anchored to a comment of the form `// parity: shell dispatch.sh:NNNN — <one-line behaviour summary>` so the parity reasoning is traceable in `git blame`.

## 3. Functional Requirements

Each FR maps directly to the PRD's FR-1 through FR-12 (same numbering), with parity-driven sub-requirements derived from the §dispatcher-audit / §hook-audit tables in `research.md`.

### FR-001 — `dispatchCommand` parity
- **A1**: command exec MUST run with `WORKFLOW_PLUGIN_DIR` exported into the child process env, derived from `state.workflow_file` per shell `dispatch_command` lines 1535–1544 (same logic appears in `dispatch_loop`). Currently TS calls `execAsync(step.command, …)` with no env injection; plugin-shipped commands silently fail under TS.
- **A2**: failure-path semantics MUST match shell — write command_log entry with `exit_code`, set step status `failed`, set workflow status `failed`. (Shipped in PR #200; verify no regression.)
- **A3**: terminal-flag handling MUST trigger `archiveWorkflow` directly when `step.terminal === true`, not just set `state.status='completed'` and rely on a downstream archive call. Confirm parity with shell `handle_terminal_step` (dispatch.sh:226).

### FR-002 — `dispatchAgent` parity
- **A1**: on `pending → working` transition (stop hook), MUST delete a stale `step.output` file if one exists from a prior run. Shell `dispatch_agent` lines 594–602. Without this, a leftover file from a previous run would auto-complete the step before the agent writes anything. Currently missing in TS.
- **A2**: cursor advance MUST go through `resolveNextIndex(step, stepIndex, workflow)` + `advancePastSkipped(stateFile, raw, workflow)` (shell lines 676–680, 703–705), not raw `stepIndex + 1`. Currently TS does `stepIndex + 1` (line 261).
- **A3**: after step transitions `working → done`, MUST call `state_clear_awaiting_user_input(stateFile, stepIndex)` per shell line 667 / FR-008 of wheel-user-input. Currently missing in TS.
- **A4**: after step transitions `working → done`, MUST call `contextCaptureOutput(stateFile, stepIndex, outputKey)` per shell line 664 — copies the output file into a state-tracked location. Currently TS sets `stateSetStepOutput(stateFile, stepIndex, null)` (line 259) which is a regression.
- **A5**: when terminal-step archive fires, MUST call `_chain_parent_after_archive(parentSnap, hookType, hookInput)` per shell lines 671–674 — advances the parent workflow's cursor when the child archives. Currently missing in TS dispatchAgent (FR-005 audits the dispatchWorkflow side; this FR addresses the agent-completes-as-final-step path).
- **A6**: REMOVE all `console.error('DEBUG dispatchAgent: ...')` calls (lines 251, 256, 262, 264, 267) — these are leftover debug prints, not parity behaviour.
- **Out of scope (defer)**: output-schema validation (`workflow_validate_output_against_schema`, shell lines 642–660). The TS rewrite has not implemented `wheel-typed-schema-locality` Theme H1; doing so here would balloon scope. Document in §intentional-deviations and file follow-up issue.

### FR-003 — `dispatchLoop` parity (closes #199 Bug A and Bug B)
- **A1 (Bug A)**: after a `command` substep iteration completes, when iteration count is below `max_iterations` AND the exit condition is not met, MUST recursively re-dispatch `dispatchLoop` (shell line 1555: `dispatch_loop "$step_json" "$state_file" "$step_index" "$workflow_json"`). Currently TS line 1109 returns `{decision: 'approve'}` instead, capping the loop at one iteration per hook fire — this is why count-to-100 hits the 60s timeout at iteration 10.
- **A2 (Bug B)**: the per-iteration max-iterations check at TS line 1101 reads `(reState.steps[stepIndex] as any)?.max_iterations` — from state, where the field is never written. MUST read from `step.max_iterations` (matching the initial check at TS line 1009). Same source-of-truth as shell line 1440.
- **A3**: command substep exec MUST export `WORKFLOW_PLUGIN_DIR` into the child process env (shell lines 1537–1544). Same gap as FR-001 A1, applied to substep exec.
- **A4**: cursor advance after loop done/exhausted MUST go through `resolveNextIndex` + `advancePastSkipped`, not raw `stepIndex + 1`. (Cascade tail already shipped via PR #200; this FR changes its target-index resolution.)
- **A5**: iteration-cap log line MUST match shell wording `loop: exhausted after <N> iterations` (TS already does this at line 1018 — verify).

### FR-004 — `dispatchBranch` parity
- **A1**: cursor advance to fall-through target (END branch path) MUST go through `resolveNextIndex` + `advancePastSkipped`. Currently TS does `stepIndex + 1` at line 953.
- **A2**: `WORKFLOW_PLUGIN_DIR` env injection on condition `eval` (shell evaluates condition with `eval` — TS does the same via `execAsync('eval "..."')`); ensure plugin-shipped predicates can resolve plugin-relative scripts. Lower priority than FR-001 A1 (predicates are simpler).
- **A3**: predicate eval failure MUST set step status `failed` AND set workflow status `failed` (shipped in PR #200; verify no regression).

### FR-005 — `dispatchWorkflow` (composition) parity
- **A1**: when the child workflow archives, the parent's cursor MUST advance (shell `_chain_parent_after_archive`, dispatch.sh:144). The wait-all-redesign FR-009 archive helper handles teammate slot updates; verify it ALSO handles composition parent-cursor advance. If not, add a parallel branch in `archiveWorkflow` (or call into a new `_chainParentAfterArchive` helper).
- **A2**: child workflow's first step MUST cascade inside the child's state during the parent's dispatch (shipped in PR #200 dispatchWorkflow; verify no regression).
- **A3**: composition-mega fixture (Phase 3 of `/wheel:wheel-test`) MUST pass.

### FR-006 — `dispatchTeamCreate` / `dispatchTeammate` / `dispatchTeamWait` / `dispatchTeamDelete` parity
- **A1 (TeamCreate)**: post_tool_use branch on TeamCreate detection MUST cascade into the next auto-executable step after marking the team done (shell lines 1669–1673). Verify TS does this.
- **A2 (Teammate)**: stop hook for `pending → working` transition MUST call `contextWriteTeammateFiles(outputDir, state, workflow, contextFromJson, assignJson)` per shell lines 1806, 1827 — writes per-teammate context.md and assign_inputs.json into the teammate's output_dir. Currently TS does NOT write these files (lines 591–625) — only registers the teammate in state. Team fixtures will NOT find their context.
- **A3 (Teammate)**: after registering teammates, MUST emit a single block with spawn instructions for ALL teammates collected so far via `_teammateChainNext` (shell lines 1813, 1832, 1889–2006). Currently TS spawns one-at-a-time and emits one block per teammate — protocol violation; agents cannot be batch-spawned.
- **A4 (Teammate)**: post_tool_use branch MUST detect `TaskCreate` tool calls, match the `subject` field to a registered teammate name, and update the teammate's `task_id` (shell lines 1843–1876). Currently TS dispatchTeammate has NO post_tool_use branch (line 531 returns approve).
- **A5 (TeamWait)**: on completion, MUST write a `summary.json` to the wait step's output path collecting all teammate outputs (shell lines 2288–2316). Currently TS marks the step done but does not write summary.
- **A6 (TeamWait)**: `collect_to` / `output_dir` copy logic MUST replicate shell lines 2318–2330 — copies each teammate's output into the wait step's output_dir.
- **A7 (TeamDelete)**: TS `dispatchTeamDelete` is a STUB (lines 902–910 return `{decision: 'approve'}`). MUST be implemented to match shell `dispatch_team_delete` (dispatch.sh:2375): stop-hook injects "Delete team '<name>'" instruction; post_tool_use detects TeamDelete tool call; on detection, calls `state_remove_team`, marks step done, runs terminal-step archive trigger, advances cursor, cascades into next auto-executable step.

### FR-007 — `dispatchParallel` / `dispatchApproval` parity
- **A1 (Parallel)**: audit confirms basic dispatch path is in place; verify hook-type gating, status transitions match shell. Add one minimal vitest fixture (no end-to-end fixture exists in `/wheel:wheel-test` set).
- **A2 (Approval)**: audit `teammate_idle` hook handling — shell lines 1322–1335 read `.approval` from hook input and advance on `'approved'`. Verify TS dispatchApproval (line 1186) handles this. Add minimal vitest fixture.

### FR-008 — Hook entry-point parity
For each hook script, verify against shell counterpart and fix any gap. Sub-requirements per hook:

- **A1 (post-tool-use)**: deactivate.sh detection branch MUST archive matching state files to `.wheel/history/stopped/`, cascade stop to child + teammate workflows, then emit `{hookEventName: "PostToolUse"}`. Match shell lines 81–176. Currently TS line 483 just emits the hook event with no archive — `/wheel:wheel-stop` is broken in TS.
- **A2 (post-tool-use)**: REMOVE all `console.error('DEBUG: ...')` calls (lines 390, 476, 478, 490, 492). Same hygiene cleanup as FR-002 A6.
- **A3 (stop, subagent-stop, teammate-idle)**: confirm engineInit + engineHandleHook flow (already shipped in wait-all-redesign); confirm decision JSON shape matches shell.
- **A4 (session-start)**: confirm registry build + state hydration matches shell. No known gap; verify.
- **A5 (subagent-start)**: confirm child-state init mirrors shell pattern. No known gap; verify.

### FR-009 — vitest coverage tooling fix (G5)
Per PRD FR-9: choose option (a) downgrade `@vitest/coverage-v8` to `^1.6.x` matching pinned `vitest@^1.6.1`. Default option per PRD R-2 risk note. Acceptance: `cd plugin-wheel && npx vitest run --coverage` produces a coverage report with no errors, summary table prints, exit code reflects test status (not import failure).

If option (a) fails (1.6.x of `@vitest/coverage-v8` doesn't exist or is broken), fall back to option (b) — bump `vitest` to `^3.x`. Document the choice in `research.md §FR-009-decision`.

### FR-010 — `/wheel:wheel-test` Phases 1–4 acceptance
After FR-001 through FR-009 land, the audit-pr task MUST verify:
1. `cd plugin-wheel && npm run build` succeeds (TS strict, no errors).
2. Deploy: `rm -rf $CACHE/dist && cp -r plugin-wheel/dist $CACHE/dist && cp plugin-wheel/hooks/*.sh $CACHE/hooks/`.
3. Clean: `rm -f .wheel/state_*.json && rm -rf ~/.claude/teams/test-{static,dynamic,partial-failure}-team`.
4. `/wheel:wheel-test` reports 100% pass on all 4 phases (13/13 fixtures).
5. After the run, `ls .wheel/state_*.json | wc -l` returns 0.
6. Restore plugin cache from backup at `/tmp/wheel-cache-backup-...` OR rebuild from a known-good shell-version commit, per PR #200's audit-pr cleanup procedure.

### FR-011 — Gap audit document (load-bearing artifact)
`research.md` MUST contain:
- **§baseline** — captured metrics: count-to-100 wall-clock = 60 s timeout (per `.wheel/logs/test-run-20260501T194556Z.md`); `/wheel:wheel-test` pass rate = 0/109; vitest --coverage = errors with `BaseCoverageProvider` import failure; `dispatchLoop max_iterations` cap = 10.
- **§dispatcher-audit** — 11-row table: dispatcher | shell file:line | TS file:line | gap description | fix plan (one sentence) | test fixture (file:test-name).
- **§hook-audit** — 6-row table: hook | shell file:line | TS file:line | gap description | fix plan | test fixture.
- **§intentional-deviations** — list of behaviours where TS deliberately does NOT match shell (e.g., output-schema validation deferred per FR-002 out-of-scope note). Each item: behaviour | shell ref | reason for deviation | follow-up issue link if any.
- **§FR-009-decision** — option (a) vs (b) for vitest coverage tooling, with chosen option and rationale.

Both audit tables MUST be filled in BEFORE `tasks.md` is committed. The implementer's tasks are structured around the gap rows.

### FR-012 — No regressions
After all fixes:
- All existing vitest tests pass. Baseline: 99 (96 from rewrite + 3 cascade fixtures). Implementation adds N new parity fixtures from FR-001 through FR-008.
- `/wheel:wheel-test` Phases 1–4 pass per FR-010.
- `git diff --stat 002-wheel-ts-rewrite..HEAD` shows zero new step types in workflow JSON schema and zero new hook event types (SC-6 of PRD).

### FR-013 — Scope freeze (R-1 mitigation)
The gap audit (FR-011) is itself the scope. Whatever §dispatcher-audit + §hook-audit contain when `tasks.md` is committed IS the scope of impl-wheel. Any newly-discovered gap during implementation is filed as a follow-up issue, NOT added to this PRD's task list. The auditor MUST flag any task that did not derive from a gap row as a scope violation.

## 4. Success Criteria

| ID | Criterion | Verification |
|---|---|---|
| **SC-1** | `/wheel:wheel-test` reports 100% pass on Phases 1–4 (13/13 fixtures, 0 orphan state files). | audit-pr smoke run with deployed dist, transcript saved to `.wheel/logs/`. |
| **SC-2** | count-to-100 wall-clock < 5 s. | `/wheel:wheel-test` per-workflow duration column. Baseline: 60 s timeout. |
| **SC-3** | `npx vitest run --coverage` produces a valid coverage report. | manual run; coverage table printed. |
| **SC-4** | All existing vitest tests pass + new parity fixtures pass. | `npx vitest run` exit code 0. |
| **SC-5** | `research.md §dispatcher-audit` has 11 rows; `research.md §hook-audit` has 6 rows. | manual read before tasks.md commit. |
| **SC-6** | Zero new step types in workflow JSON schema; zero new hook event types. | `git diff --stat 002-wheel-ts-rewrite..HEAD` audit by auditor. |
| **SC-7** | Every behavioural change in TS source has a `// parity: shell dispatch.sh:NNNN — …` comment. | `git grep -n "// parity:" plugin-wheel/src/lib/dispatch.ts` returns ≥ 1 match per fixed gap row. |

## 5. Acceptance Gates

1. spec, plan, tasks, contracts/interfaces.md, research.md committed BEFORE any implementation code (constitution Article I + IV; hooks enforce).
2. `research.md §dispatcher-audit` (11 rows) + `§hook-audit` (6 rows) both filled in BEFORE `tasks.md` is committed (FR-011, R-1 mitigation).
3. Each task in `tasks.md` traces to a gap row (FR-013).
4. Constitution Article VIII: each task marked `[X]` immediately on completion; commit per phase.
5. SC-1 (the smoke gate) is non-negotiable — audit-pr does NOT open the PR until Phases 1–4 are 100% green.

## 6. Out-of-Scope

Inherited from PRD §Non-Goals:
- No redesign of wheel architecture; no new step types; no new hook event types; no new state-JSON or workflow-JSON schema fields.
- No fix for shell wheel quirks (file separate issue).
- No re-litigation of cascade or wait-all redesign decisions (parent branches are FROZEN).
- No new test substrate; `/wheel:wheel-test` is the canonical smoke gate.
- Output-schema validation in dispatchAgent (Theme H1 of `wheel-typed-schema-locality`) — deferred to follow-up; documented in §intentional-deviations.

## 7. Risks (PRD R-1 through R-8 inherited; restated for traceability)

R-1 scope balloon — mitigated by FR-013 frozen-gap-list rule.
R-2 vitest 3 bump — mitigated by FR-009 default to option (a).
R-3 composition cascade — explicit FR-005; gap-row-driven.
R-4 parallel/approval not in `/wheel:wheel-test` — FR-007 vitest-only coverage; SC-1 only requires Phases 1–4.
R-5 shell quirks — FR-011 audit references shell file:line directly.
R-6 audit-pr ↔ impl-wheel ping-pong — accepted; budget for 1–3 cycles.
R-7 cache redeploy mechanic fragility — FR-010 cleanup procedure documented.
R-8 latent gap surfaces post-merge — accepted; shell wheel can be re-pinned via cache rollback.
