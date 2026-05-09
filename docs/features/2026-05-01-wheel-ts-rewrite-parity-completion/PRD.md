# Feature PRD: Wheel TS Rewrite — Parity Completion (final pass)

## Parent Product

Wheel — hook-based workflow engine plugin (`plugin-wheel/`). See repo `CLAUDE.md` for product context. This PRD is the **final** pass on the in-progress TypeScript rewrite. It folds into the chain `build/wheel-ts-dispatcher-cascade-20260501` → `build/wheel-wait-all-redesign-20260430` → `002-wheel-ts-rewrite`. Once this PRD ships, the entire chain merges to `main` as one consolidated TS-rewrite + parity-completion PR. **Hard user constraint: PR #200 (cascade) MUST NOT merge to main until this PRD ships and `/wheel:wheel-test` Phases 1–4 actually pass.**

## Feature Overview

**Audit every TS dispatcher and every hook entry point against the canonical shell wheel, enumerate every behavioral gap, and fix all of them in one pass.** This is a parity-completion sweep, not a redesign — the goal is to make the TS implementation produce the same observable behavior as `lib/dispatch.sh` + the shell hook scripts for every workflow type the test harness exercises. After this PRD lands, `/wheel:wheel-test` Phases 1–4 pass cleanly with the working-tree TS dist deployed to plugin cache.

## Problem / Motivation

The TS rewrite has been worked in three preceding PRDs, each of which surfaced the next latent gap at the smoke gate:

1. **`2026-04-30-wheel-wait-all-redesign`** — exposed: `archiveWorkflow` not wired into terminal-step dispatch (B-3); `Stop` / `SubagentStop` / `TeammateIdle` hooks didn't call `engineInit` (so engine module-globals were empty and dispatch short-circuited); `handleActivation` didn't persist `workflow_definition` into the state file. All three fixes shipped on the wait-all branch.
2. **`2026-05-01-wheel-ts-dispatcher-cascade`** (PR #200) — exposed: `dispatchCommand` / `dispatchLoop` / `dispatchBranch` had no inline cascade (returned after one step), so chained workflows stalled at `cursor=0` after activation. Fix shipped: cascade tail in each + `handleActivation` triggers initial cascade. SC-1 (Phases 1–3 green) was deferred because the cascade smoke run surfaced #199.
3. **Issue #199** — exposed: `dispatchLoop` itself doesn't self-cascade between iterations (Bug A), and reads `max_iterations` from `state.steps[i]` which doesn't carry it (Bug B), so loops cap at 10 iterations regardless of the workflow definition.

**The pattern is structural.** Each PRD's scope is correct in isolation but `/wheel:wheel-test` is end-to-end — the gate stays red until the LAST gap closes. The retrospective for #200 (issue #201, insight_score 4) explicitly recommended: stop spawning incremental PRDs that surface the next gap; do one holistic parity audit and fix everything together.

This PRD is that audit. It enumerates every dispatcher and every hook against the shell version, lists every gap, and ships fixes for all of them in one branch.

## Goals

- **G1 (acceptance gate)**: `/wheel:wheel-test` reports 100% pass on **Phases 1–4** with no orphan state files. Baseline: `.wheel/logs/test-run-20260501T194556Z.md` reports 0/109 passes.
- **G2 (every dispatcher)**: every step type (`command`, `agent`, `loop`, `branch`, `workflow`, `team-create`, `teammate`, `team-wait`, `team-delete`, `parallel`, `approval`) produces shell-equivalent behavior.
- **G3 (every hook)**: every hook entry point (`post-tool-use`, `stop`, `subagent-stop`, `teammate-idle`, `session-start`, `subagent-start`) routes to the engine correctly, resolves state, and produces shell-equivalent decisions.
- **G4 (#199 close)**: `dispatchLoop` self-cascades between iterations and reads `max_iterations` from the workflow definition. count-to-100 (`max_iterations: 101`) completes in <5s wall-clock.
- **G5 (test infrastructure)**: `package.json` is updated so `npx vitest run --coverage` actually works (currently broken because `@vitest/coverage-v8@4.x` requires `vitest@3+` but `vitest@1.6.x` is pinned). The `≥80%` coverage gate from the constitution becomes runnable.
- **G6 (no regressions)**: all 99 existing vitest tests still pass. The 3 cascade fixtures from PR #200 still pass. New parity tests added per the gap-by-gap fix list.

## Non-Goals

- **Not a redesign of any wheel architecture.** No new step types. No new hook types. No changes to the workflow JSON schema. No changes to the `state_*.json` schema. The shell version is the spec; the TS code matches it.
- **Not new functionality.** If a behavior doesn't exist in shell wheel, it doesn't ship in this PRD either.
- **Not a fix for shell wheel.** The shell version is the reference. If shell has a quirk, TS replicates it. If shell has a real bug, file a separate issue — out of scope for this PRD.
- **Not a re-litigation of work already shipped.** The wait-all redesign and cascade work are committed on parent branches; this PRD builds on top, doesn't revisit those decisions.
- **Not a CLAUDE.md / docs cleanup.** Documentation reads of the existing TS implementation are in scope only as audit input, not output.
- **Not a new test substrate.** `/wheel:wheel-test` is the canonical gate. No new harness needed.
- **Not a backport to `main` until this PRD lands.** PR #200 stays open, marked deferred. The chain merges once parity is reached.

## Target Users

Inherited from parent product. Specifically benefits:

- **Anyone who runs `/wheel:wheel-test`** — finally goes green end-to-end on the TS implementation.
- **Plugin authors** writing kiln/clay/shelf/trim workflows — TS wheel actually progresses workflows, not just sits at cursor=0.
- **The 002-wheel-ts-rewrite branch** — completes the rewrite goal: shell can be retired, TS becomes canonical.
- **Future contributors** — one parity audit covers everything; no whack-a-mole.

## Core User Stories

1. **As a workflow author**, I activate any of the 13 fixtures under `workflows/tests/` from any cwd. The workflow runs to completion (or expected-failure) without my touching anything else. State files archive to the right `history/<bucket>/`. No orphan state files left behind.
2. **As `/wheel:wheel-test`**, I run all four phases and report pass for every fixture. Total wall-clock budget per fixture: matches the shell version's actual wall-clock (typically <5s, never >60s).
3. **As a plugin developer**, I run `npx vitest run --coverage` and it actually produces a coverage report. The `≥80%` gate is enforceable.
4. **As a wheel internals reader**, when I open any TS dispatcher and compare to the shell version, the boundary semantics match: which hooks route to which dispatchers, what status transitions happen, what cursor advances happen, what archive triggers fire.
5. **As the maintainer**, I merge ONE PR (the chain rolled up) and the TS rewrite is done. Shell wheel can be retired. No more deferred-gate caveats.

## Functional Requirements

The implementation pattern for every FR below: **(a) read shell behavior from `~/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.842/lib/dispatch.sh` (or relevant hook script); (b) compare to TS code on this branch; (c) document the gap explicitly in `specs/wheel-ts-rewrite-parity-completion/research.md §dispatcher-audit` (or §hook-audit); (d) fix the gap in TS; (e) write a vitest fixture or `/wheel:wheel-test` evidence proving parity.**

The specifier owns the gap audit. The implementer owns the fixes. The auditor verifies the gap-by-gap fix list is complete.

### FR-1 — Audit + fix dispatchCommand

Compare TS `dispatchCommand` against shell `dispatch_command`. Verify:
- Auto-cascade behavior (already shipped in PR #200; should match shell's recursion).
- Failure-path semantics (shell sets step status `failed` and halts cascade; TS should match).
- Output capture (stdout vs stderr, command_log entry shape).
- Terminal-flag handling (`step.terminal === true` triggers archive — match shell's exact trigger).

Document any gaps; fix; add a parity vitest fixture if not already covered by FR-10.

### FR-2 — Audit + fix dispatchAgent

Compare TS `dispatchAgent` against shell `dispatch_agent`. Verify:
- Hook-type gating (shell only acts on `stop` and `post_tool_use`; TS should match).
- Output-file detection — shell polls for `step.output` file existence; TS does the same; ensure timing/race semantics match.
- Cursor-advance ownership: shell advances cursor inside dispatchAgent when output file appears; TS does the same; verify no double-advance.
- Block reason text (shell injects "Step '<id>' is in progress. Write your output to: <path>"; TS should produce the same string for parity in test reports).
- Post-agent cascade trigger: when output file appears and step transitions to done, the NEXT step should cascade per FR-2/3/4 of the cascade PRD. Verify TS does this.

Document gaps; fix; vitest fixture for the post-agent cascade trigger if not already covered.

### FR-3 — Audit + fix dispatchLoop (closes #199)

Compare TS `dispatchLoop` against shell `dispatch_loop`. Verify:
- **Bug A (#199)**: shell self-cascades between iterations within a single hook invocation; TS must do the same. After running one substep iteration, if the loop's exit condition is not met AND iteration count is below `max_iterations`, recursively call into dispatchLoop (or `cascadeNext` against the SAME stepIndex) until the loop exits.
- **Bug B (#199)**: shell reads `max_iterations` from the workflow definition; TS must do the same. Read from `WORKFLOW.steps[stepIndex].max_iterations` (or `state.workflow_definition.steps[stepIndex].max_iterations` since FR-005 of wait-all-redesign persists this), NOT from `state.steps[stepIndex]` which doesn't carry it.
- Substep dispatch: shell dispatches each iteration's substep through the standard step-type routing; TS must too.
- Exit condition evaluation: shell evaluates a string predicate against state; TS must evaluate the same predicate the same way.
- Iteration cap behavior: when `max_iterations` is hit, shell sets step status `failed` with an `iteration_cap_exceeded` log line; TS must match.

Document; fix both bugs; add vitest fixtures: (i) loop with `max_iterations: 50` runs to 50; (ii) loop reads `max_iterations` from workflow definition not state; (iii) loop exits early when condition is met before cap.

### FR-4 — Audit + fix dispatchBranch

Compare TS `dispatchBranch` against shell `dispatch_branch`. Verify:
- Predicate evaluation matches shell (same predicate string syntax, same evaluation semantics).
- Target-step resolution: shell uses a target field (`if_true`, `if_false`, or `END`); TS uses the same field names and same `END` semantics.
- Cascade after branch jump: TS already cascades to the target step (shipped in PR #200); verify this matches shell.
- "Skipped step" semantics: when branch skips over intermediate steps, shell handles cursor properly; TS must match.

Document; fix; vitest fixture for the END branch target if not already covered.

### FR-5 — Audit + fix dispatchWorkflow (composition)

Compare TS `dispatchWorkflow` against shell `dispatch_workflow`. Verify:
- Child workflow activation: shell creates a child state file with `parent_workflow` set; TS must too.
- Child cursor cascade: shell's child runs its own cascade independently; TS must too.
- Parent-resume on child archive: shell uses `_chain_parent_after_archive` to advance the parent cursor when the child archives; TS must do the same (the wait-all-redesign FR-009 archive helper handles teammate slot updates — verify it ALSO handles composition parent advance, OR add a separate path).
- State-file isolation: child state file owns its own cursor; doesn't leak into parent. TS must match.
- composition-mega test fixture (Phase 3 of `/wheel:wheel-test`) must pass.

Document; fix; verify Phase 3 passes.

### FR-6 — Audit + fix dispatchTeamCreate / dispatchTeammate / dispatchTeamWait / dispatchTeamDelete

Compare each against shell counterparts (`dispatch_team_create`, `dispatch_teammate`, `dispatch_team_wait`, `dispatch_team_delete`). Verify:
- Block-reason text matches shell exactly (parity for test report parity).
- Hook-type gating matches.
- State mutations match (status transitions, cursor advances, team/teammate slot updates).
- The wait-all-redesign FR-009 archive wiring + FR-004 polling backstop are already in place (parent branch); verify TS dispatch paths use them correctly.
- team-static / team-dynamic / team-partial-failure (Phase 4 fixtures) all pass.

Document; fix; verify Phase 4 passes.

### FR-7 — Audit + fix dispatchParallel + dispatchApproval

Compare against shell counterparts. Verify hook-type gating, state mutations, block-reason text. These step types are not exercised by the standard `/wheel:wheel-test` fixture set today, but they exist in the dispatcher router and must match shell to prevent latent bugs. Add minimal vitest fixtures (one per dispatcher) covering the basic dispatch path. Out of scope: full e2e fixtures for parallel/approval — only need basic parity coverage.

### FR-8 — Audit + fix every hook entry point

For each hook script — `post-tool-use.ts`, `stop.ts`, `subagent-stop.ts`, `teammate-idle.ts`, `session-start.ts`, `subagent-start.ts` — compare against the shell version (`hooks/*.sh`). Verify:
- stdin parsing matches (preserve newlines, handle control chars).
- State file resolution (via `resolveStateFile` in `guard.ts` from wait-all-redesign).
- `engineInit` invoked before `engineHandleHook` (already done in wait-all-redesign for stop/subagent-stop/teammate-idle).
- Decision output format matches shell (same JSON shape, same fields).
- Edge case: no state file → `{decision: 'approve'}` pass-through.
- Edge case: workflow already terminal → archive trigger via FR-009 (wait-all-redesign).

Document; fix any gap; add a fixture per hook entry point that exercises the complete state-resolution + dispatch + decision path.

### FR-9 — Fix vitest coverage tooling (G5)

`package.json` currently pins `vitest@^1.6.1` and `@vitest/coverage-v8@^4.1.5`. The latter requires vitest 3+. Choose ONE:
- **Option (a)**: Pin `@vitest/coverage-v8@^1.6.x` to match vitest 1.6.x. Simplest. Risk: 1.6.x may be old.
- **Option (b)**: Bump `vitest` to `^3.x` and let `@vitest/coverage-v8` stay at `^4.x`. Bigger blast radius — vitest 3 has API changes.

The implementer should evaluate at plan-time and pick the option with lower risk. Acceptance: `npx vitest run --coverage` produces a coverage report with no errors. The `≥80%` constitution gate becomes mechanically verifiable.

### FR-10 — `/wheel:wheel-test` Phases 1–4 acceptance

After all of FR-1 through FR-9 land:
- Build TS dist: `cd plugin-wheel && npm run build`.
- Deploy dist + hooks to plugin cache: `rm -rf $CACHE/dist && cp -r plugin-wheel/dist $CACHE/dist && cp plugin-wheel/hooks/*.sh $CACHE/hooks/`.
- Clean state: `rm -f .wheel/state_*.json && rm -rf ~/.claude/teams/test-static-team ~/.claude/teams/test-dynamic-team ~/.claude/teams/test-partial-failure-team`.
- Run `/wheel:wheel-test`.
- All 13 fixtures pass per phase classification (Phase 1: count-to-100, loop-test, team-sub-fail; Phase 2: agent-chain, branch-multi, command-chain, example, sync, team-sub-worker; Phase 3: composition-mega; Phase 4: team-static, team-dynamic, team-partial-failure).
- `.wheel/state_*.json` is empty after the test run.
- Restore cache to shell-only after smoke (per the audit-pr cleanup procedure from PR #200).

The audit-pr task in this PRD's pipeline owns this verification.

### FR-11 — Gap audit document

The specifier MUST produce `specs/wheel-ts-rewrite-parity-completion/research.md` with TWO sections:

1. **§dispatcher-audit** — table with rows for every dispatcher (11 rows). Columns: dispatcher name, shell file:line, TS file:line, gap description, fix plan (one sentence), test fixture (file:test-name).
2. **§hook-audit** — table with rows for every hook entry point (6 rows). Same column structure.

Both tables MUST be filled in BEFORE tasks.md is finalized. The implementer's tasks.md is structured around these tables — one task per gap row.

This is the load-bearing artifact of the PRD. Without it, the implementer can't know what to fix.

### FR-12 — No regressions

After all fixes:
- All 99 existing vitest tests pass (96 from the rewrite + 3 cascade fixtures from PR #200).
- All new parity fixtures from FR-1 through FR-8 pass.
- `/wheel:wheel-test` Phases 1–4 pass per FR-10.

Specifically: the wait-all-redesign FR-009 archive wiring tests must still pass. The cascade fixtures must still pass. Any TS code touched in this PRD must not break upstream-of-this-branch tests.

## Absolute Musts

1. **Tech stack**: TypeScript (strict mode), Node 20+, `fs/promises`, `path`, no external runtime npm deps. May add ONE dev dependency (vitest version bump per FR-9 if option b chosen). Inherited from parent rewrite PRD.
2. **Shell wheel is the spec.** The TS implementation MUST match shell's observable behavior for every step type and hook. If TS deviates, the deviation MUST be documented in research.md §intentional-deviations with a justification — and the auditor MUST flag any undocumented deviation as a gap.
3. **`/wheel:wheel-test` Phases 1–4 ALL pass — this is the ship gate.** No deferred-caveat fallback. If the smoke gate fails, the PRD is not done; the implementer iterates until it greens. Audit-pr does NOT open the PR until this gate is clear.
4. **Lands in the build chain — does NOT branch off main.** Pipeline branches from current HEAD which is the cascade branch tip. This PRD's branch chains: build/wheel-ts-rewrite-parity-completion-20260501 → build/wheel-ts-dispatcher-cascade-20260501 → build/wheel-wait-all-redesign-20260430 → 002-wheel-ts-rewrite. Once this lands, the entire chain merges to main as one PR.
5. **PR #200 (cascade) stays open until this PRD ships.** The user's hard constraint: do NOT merge cascade-only. Merge the parity-complete chain.
6. **No new feature code beyond shell-parity.** If a fix involves adding behavior not present in shell, that fix is rejected. Match the shell version literally.

## Tech Stack

Inherited from parent rewrite PRD. No additions or overrides except the FR-9 vitest coverage tooling fix.

## Impact on Existing Features

| Area | Impact |
|---|---|
| Every TS dispatcher (11 dispatchers) | **Audited and fixed.** Each gets a parity-with-shell pass. Gap list lives in research.md §dispatcher-audit. |
| Every TS hook entry point (6 hooks) | **Audited and fixed.** Each verified to call engineInit + engineHandleHook with proper state resolution. Gap list lives in research.md §hook-audit. |
| `dispatchLoop` | **Both #199 bugs fixed.** Self-cascade between iterations. `max_iterations` from workflow def. Three new vitest fixtures. |
| `package.json` (dev deps) | **Updated.** Either `@vitest/coverage-v8` pinned to 1.6.x OR `vitest` bumped to 3+. Implementer picks at plan-time. |
| `/wheel:wheel-test` smoke harness | **Unchanged** — fixture set stays as-is. The harness is the test for this PRD; it doesn't get modified. |
| Wait-all redesign work (parent branch) | **Unchanged.** This PRD builds on top, doesn't revisit. |
| Cascade work from PR #200 | **Unchanged.** Cascade tails stay; the cascade fixtures keep passing. |
| Shell wheel | **Unchanged.** Shell stays canonical until this PRD merges to main and the rewrite goes live. |
| Workflow JSON schema | **Unchanged.** |
| State JSON schema | **Unchanged.** |
| All 13 `workflows/tests/` fixtures | **Start passing.** No fixture changes; behavior change makes them work. |

## Success Metrics

1. **SC-1 (THE acceptance gate)**: `/wheel:wheel-test` reports 100% pass on Phases 1–4 with the working-tree TS dist deployed to plugin cache. 13/13 fixtures green. 0 orphan state files. Baseline: 0/109 (per `.wheel/logs/test-run-20260501T194556Z.md`). Verified by audit-pr in the pipeline; non-negotiable for PR creation.
2. **SC-2**: count-to-100 wall-clock <5s (closes #199 Bug A + B). Baseline: 60s timeout. Verified in the wheel-test report's per-workflow duration column.
3. **SC-3**: `npx vitest run --coverage` produces a valid coverage report with no errors. Baseline: errors out with `BaseCoverageProvider` import failure. Verified by running the command.
4. **SC-4**: 99 existing vitest tests + N new parity fixtures all pass. Baseline: 99/99. Verified by `npx vitest run`.
5. **SC-5**: research.md §dispatcher-audit has 11 rows (one per dispatcher) and §hook-audit has 6 rows (one per hook entry point). Baseline: 0 rows. Verified by reading research.md before tasks.md is finalized.
6. **SC-6**: `git diff --stat 002-wheel-ts-rewrite..HEAD` shows zero new step types in workflow JSON schema and zero new hook event types. Verified by the auditor — proves the PRD didn't drift into "new feature" territory.

## Risks / Unknowns

- **R-1 (scope balloon)**: a comprehensive parity audit could surface a dozen unexpected gaps. Mitigation: the gap audit (FR-11) is itself the scope. Whatever the gap list contains is the scope; whatever it doesn't is out of scope. If the implementer finds a gap NOT on the list during implementation, they file it as a follow-up issue; the gap list doesn't grow mid-implementation. Hard ceiling: gap list is frozen when tasks.md is committed.
- **R-2 (vitest 3 bump blast radius)**: FR-9 option (b) bumps vitest by 2 major versions. Some test-helper API changes are likely. Mitigation: prefer option (a) (`@vitest/coverage-v8` downgrade) unless the implementer finds that 1.6.x lacks needed coverage features. Document the choice in research.md.
- **R-3 (composition cascade interaction)**: FR-5 mentions `_chain_parent_after_archive` for shell composition. The wait-all-redesign FR-009 archive helper handles teammate slot updates but composition is a peer code path. Risk: the existing TS archive helper might need a parallel "advance parent cursor for composition" branch. Mitigation: FR-5 explicitly calls this out; the gap audit at FR-11 should surface the answer; impl-wheel handles it.
- **R-4 (parallel/approval untested in `/wheel:wheel-test`)**: FR-7 audits these but they have no e2e fixture in the standard set. Risk: parity claim for parallel/approval is vitest-only. Mitigation: SC-1 only requires Phases 1–4 fixtures (parallel/approval aren't in any phase). The vitest coverage is sufficient for "no regression"; deeper validation is out of scope.
- **R-5 (shell wheel quirks)**: shell may have undocumented behaviors (e.g., specific log line formats, specific failure-path handling) that aren't obvious from reading dispatch.sh. Risk: TS replicates the wrong thing. Mitigation: research.md §dispatcher-audit table includes "shell file:line" — implementer reads the shell code directly, doesn't infer from prose docs.
- **R-6 (smoke run iteration count)**: SC-1 requires Phases 1–4 to pass. If they don't pass on the first audit-pr smoke run, audit-pr loops back to impl-wheel. Could iterate 3+ times. Mitigation: budget for 1-3 audit-pr ↔ impl-wheel ping-pongs. Each one is fast (~5 min). Acceptable.
- **R-7 (cache redeploy mechanic fragility)**: audit-pr deploys TS dist to cache for the SC-1 smoke run. The cleanup mechanic (restore-from-backup at `/tmp/wheel-cache-backup-...`) is fragile — backup may not exist on a fresh machine. Mitigation: per PR #200's audit-pr feedback, document the canonical cleanup path in audit-pr's prompt (`claude plugin install` or rebuild from a known-good shell-version commit). Don't rely on the `/tmp/wheel-cache-backup-...` directory.
- **R-8 (latent gap surfaces post-merge)**: even with a comprehensive audit, a workflow author might find a gap after the rewrite ships. Mitigation: this is a real possibility; ship the rewrite, accept that some maintenance work may follow. The shell wheel can be re-pinned via cache rollback if the regression is severe.

## Assumptions

- The shell wheel at `~/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.842/lib/dispatch.sh` (and sibling hook scripts) is the canonical reference. It's known-working (proven by years of use) and its observable behavior is the spec.
- The wait-all-redesign and dispatcher-cascade work on parent branches is correct and shipped. This PRD builds on top, doesn't revisit those decisions.
- The 13 fixtures under `workflows/tests/` cover the meaningful workflow types. Phases 1–4 passing is sufficient acceptance evidence.
- `/wheel:wheel-test` runs in a reasonable wall-clock budget (under 10 min total for all 4 phases) when the implementation is correct.
- The plugin cache deployment mechanism (`cp -r plugin-wheel/dist $CACHE/dist`) works for verification runs. The backup-restore cleanup mechanism works on the maintainer's machine (verified during PR #200 work).

## Open Questions

- **Q1**: FR-9 option choice — pin `@vitest/coverage-v8` to 1.6.x (option a) OR bump `vitest` to 3+ (option b)? Implementer evaluates at plan-time and picks the lower-risk option. Default: option (a).
- **Q2**: Composition-step parent-resume (FR-5 R-3) — does the existing wait-all-redesign archive helper handle the composition path, or does it need a parallel branch? Resolved at plan-time after reading the existing code.
- **Q3**: parallel / approval dispatcher minimum-coverage threshold (FR-7) — one vitest fixture each is enough? Implementer's call, document in plan.md.
- **Q4**: After this PRD lands, does PR #200 merge first (chain merge) OR get superseded by the parity PR? Cleanest: this PRD's PR supersedes the chain — close PR #200 and merge the parity PR. Resolve at PR-creation time.
