# Research — Wheel TS Rewrite Parity Completion

This document is the **load-bearing artifact** of the PRD (FR-011). The §dispatcher-audit (11 rows) and §hook-audit (6 rows) below define the scope of impl-wheel. The implementer's `tasks.md` is structured around these tables — one task (or a small task cluster) per gap row.

Per FR-013 of `spec.md`, this gap list is FROZEN when `tasks.md` is committed. Newly-discovered gaps during implementation are filed as follow-up issues, NOT added here.

---

## §baseline

Captured 2026-05-01 on branch `build/wheel-ts-rewrite-parity-completion-20260501`. HEAD = cascade tip (PR #200).

| Metric | Source / command | Value | Notes |
|---|---|---|---|
| count-to-100 wall-clock | `.wheel/logs/test-run-20260501T194556Z.md` | **60 s timeout — never completes** | SC-2 baseline. Loop caps at 10 iterations (#199 Bug B) and never self-cascades (Bug A); test runner's per-phase budget expires. |
| `/wheel:wheel-test` pass rate | `.wheel/logs/test-run-20260501T194556Z.md` | **0/109** (0 pass / 109 expected results) | SC-1 baseline. Orphan state files cascade across fixtures, contaminating downstream test counts. |
| `npx vitest run --coverage` | `cd plugin-wheel && npx vitest run --coverage` | **errors with `BaseCoverageProvider` import failure** | SC-3 baseline. `@vitest/coverage-v8@^4.1.5` requires `vitest@3+`; we pin `vitest@^1.6.1`. |
| `dispatchLoop max_iterations` cap | `plugin-wheel/src/lib/dispatch.ts:1009` + line 1101 | **effectively 10** (default) | #199 Bug B baseline. Read from `state.steps[i].max_iterations` (line 1101) which is never written; default kicks in. |
| Existing vitest tests | `cd plugin-wheel && npx vitest run` | **99/99 pass** (pre-this-PRD) | SC-4 baseline. 96 from 002-wheel-ts-rewrite + 3 cascade fixtures from PR #200. |

---

## §dispatcher-audit (11 rows — per FR-011)

| Dispatcher | Shell ref | TS ref | Gap | Fix plan | Test fixture |
|---|---|---|---|---|---|
| **dispatchCommand** | `dispatch.sh:1085` (esp. lines 1535–1544) | `dispatch.ts:304` | Missing `WORKFLOW_PLUGIN_DIR` env injection on `execAsync(step.command)`. Shell exports it derived from `state.workflow_file`'s plugin dir; plugin-shipped commands fail under TS. | Compute `wfPluginDir` from `state.workflow_file` (two-level dirname) and pass `{ env: { ...process.env, WORKFLOW_PLUGIN_DIR } }` to `execAsync`. | covered by `/wheel:wheel-test` `command-chain` + new `dispatch.test.ts:command-exports-plugin-dir`. |
| **dispatchAgent** | `dispatch.sh:572` (lines 588–715) | `dispatch.ts:222` | Six gaps: (i) no stale-output-file deletion on pending→working (shell:594–602); (ii) cursor advance uses raw `stepIndex+1` instead of `resolveNextIndex`+`advancePastSkipped` (shell:676–680); (iii) missing `state_clear_awaiting_user_input` after working→done (shell:667); (iv) missing `contextCaptureOutput` on advance — TS sets output to `null` (line 259) which is a regression vs shell:664; (v) missing `_chain_parent_after_archive` after terminal-step archive (shell:671–674); (vi) leftover `console.error('DEBUG ...')` calls (lines 251, 256, 262, 264, 267). | (i) port stale-file unlink; (ii) port `resolveNextIndex` + `advancePastSkipped` from existing TS helpers (workflow.ts) or shell-equivalent; (iii) port `stateClearAwaitingUserInput` (likely already in state.ts); (iv) port `contextCaptureOutput` (context.ts) — preserve existing context module; (v) port `_chainParentAfterArchive` helper used by FR-005; (vi) delete debug prints. | new `dispatch-agent-parity.test.ts` (one test per sub-fix); covered by `/wheel:wheel-test agent-chain` + `composition-mega`. |
| **dispatchLoop** | `dispatch.sh:1424` (esp. lines 1551–1556, 1440) | `dispatch.ts:993` | Two bugs: (Bug A) after command substep at line 1109, returns `{decision:'approve'}` instead of recursively calling `dispatchLoop` like shell:1555; loop caps at 1 iter per hook fire. (Bug B) line 1101 reads `(reState.steps[stepIndex] as any)?.max_iterations` from state — field is never written; should read `step.max_iterations` like line 1009 does. Also: no `WORKFLOW_PLUGIN_DIR` injection for substep command (shell:1537–1544); cursor advance uses raw `stepIndex+1` not `resolveNextIndex`+`advancePastSkipped`. | (Bug A) replace `return { decision: 'approve' };` at line 1109 with `return dispatchLoop(step, hookType, hookInput, stateFile, stepIndex, depth);`. (Bug B) read `step.max_iterations` at line 1101, not `reState.steps[stepIndex]`. Add `WORKFLOW_PLUGIN_DIR` env injection. Update cascade tail to use `resolveNextIndex`. | new `dispatch-loop-iter.test.ts` with three tests: (i) max_iterations:50 runs to 50; (ii) max_iterations from workflow def not state; (iii) early condition exits before cap. Plus `/wheel:wheel-test count-to-100` end-to-end. |
| **dispatchBranch** | `dispatch.sh:1347` | `dispatch.ts:913` | Cursor advance to fall-through target uses raw `stepIndex+1` (line 953) — should use `resolveNextIndex`+`advancePastSkipped`. Otherwise: parity. | Update fall-through cascade to call `resolveNextIndex(step, stepIndex, workflow)` + `advancePastSkipped`. | covered by existing `dispatch-cascade.test.ts:branch-jump-cascade` + `/wheel:wheel-test branch-multi`. |
| **dispatchWorkflow** | `dispatch.sh:339` (esp. `_chain_parent_after_archive` at :144) | `dispatch.ts:378` | Composition: child archive must advance parent cursor via `_chain_parent_after_archive`. Wait-all-redesign FR-009 archive helper handles teammate slot updates; verify whether it ALSO handles composition parent-cursor advance. If not, add a parallel branch in `archiveWorkflow` (or new `_chainParentAfterArchive` helper). | Inspect `archiveWorkflow` (`engine.ts` / archive helper); if composition-parent-resume branch is missing, add it: `if state.parent_workflow → read parent state, advance cursor, dispatch next step via cascadeNext`. | new `dispatch-terminal.test.ts:child-archive-advances-parent` + `/wheel:wheel-test composition-mega`. |
| **dispatchTeamCreate** | `dispatch.sh:1579` (esp. lines 1669–1673) | `dispatch.ts:477` | post_tool_use branch on TeamCreate detection should cascade into next auto-executable step. | Verify TS post_tool_use branch ends with `cascadeNext(...)` after marking team done; if not, add it. | covered by `/wheel:wheel-test team-static`. |
| **dispatchTeammate** | `dispatch.sh:1694` (lines 1806, 1827, 1813, 1832, 1843–1876, helpers `_teammate_chain_next` :1889, `_teammate_flush_from_state` :1927) | `dispatch.ts:524` | Four major gaps: (i) MISSING `contextWriteTeammateFiles(outputDir, state, workflow, contextFromJson, assignJson)` — writes context.md + assign_inputs.json into teammate output_dir (shell:1806, 1827); without this, spawned agents have no context. (ii) MISSING `_teammateChainNext` — collects all registered teammates and emits a SINGLE block with batched spawn instructions; TS spawns one-at-a-time with one block each (lines 591–625 / 609–625). (iii) MISSING post_tool_use branch — should detect `TaskCreate` tool calls and update teammate `task_id` (shell:1843–1876); TS line 531 returns approve. (iv) MISSING `state_add_teammate` parameters: `assign_json` is dropped on the floor in dynamic-spawn loop (shell:1808 passes `agent_assign`; TS line 596 hardcodes `{}`). | (i) port `contextWriteTeammateFiles` from shell `context.sh` to TS `context.ts`. (ii) port `_teammateChainNext` + `_teammateFlushFromState` to a new helper module or extend `dispatch.ts`. (iii) add post_tool_use branch matching shell:1842–1876. (iv) thread `agentAssign` through dynamic-spawn loop. | new `dispatch-teammate.test.ts` (4 tests, one per sub-fix). End-to-end via `/wheel:wheel-test team-dynamic` + `team-static`. |
| **dispatchTeamWait** | `dispatch.sh:2007` (esp. `_team_wait_complete` :2248, lines 2288–2316, 2318–2330) | `dispatch.ts:675` | Two gaps: (i) MISSING `summary.json` write on completion — collects all teammate outputs into the wait step's output path. (ii) MISSING `collect_to` / output_dir copy logic — copies each teammate's output into the wait step's output_dir per shell:2318–2330. | Add `_teamWaitComplete` helper to TS that mirrors shell `_team_wait_complete` — writes summary.json, copies teammate outputs. Hook into `_recheckAndCompleteIfDone`. | extend `dispatch-team-wait.test.ts` with `:wait-summary-output` and `:collect-to-copy`. End-to-end via `/wheel:wheel-test team-partial-failure`. |
| **dispatchTeamDelete** | `dispatch.sh:2375` | `dispatch.ts:902` | **STUB** — TS function returns `{decision: 'approve'}` only. NO implementation. Shell does: stop hook injects "Delete team '<name>'" instruction; post_tool_use detects TeamDelete tool call, calls `state_remove_team`, marks step done, runs terminal-step archive trigger, advances cursor, cascades into next auto-executable step. | Implement full dispatchTeamDelete matching shell — port `state_remove_team` to TS state module if not present; both stop and post_tool_use branches; idempotency check (no-op if team already deleted, shell:2399–2417). | new `dispatch-team-delete.test.ts`. End-to-end via `/wheel:wheel-test team-static`. |
| **dispatchParallel** | `dispatch.sh:1215` | `dispatch.ts:1122` | Audit: basic dispatch path appears in place. Verify hook-type gating (shell only acts on stop / post_tool_use), status transitions (pending → working → done), block-reason text matches shell. | Read both functions side by side; document any concrete gap or write "no gap" + record the comparison in §intentional-deviations. | new `dispatch-parallel.test.ts` (1 minimal test exercising basic dispatch path). No end-to-end fixture in `/wheel:wheel-test`. |
| **dispatchApproval** | `dispatch.sh:1300` (esp. lines 1322–1335) | `dispatch.ts:1186` | Audit: shell reads `.approval` from teammate_idle hook input and advances on `'approved'`. Verify TS handles teammate_idle for approval steps. | Read both functions; if TS missing teammate_idle branch, add it. | new `dispatch-approval.test.ts:approval-teammate-idle`. No end-to-end fixture in `/wheel:wheel-test`. |

**Summary of gap density**: 9/11 dispatchers have at least one gap. dispatchTeamDelete is the largest (full reimplementation). dispatchTeammate is the second largest (4 sub-gaps including missing `contextWriteTeammateFiles` which blocks all team fixtures). dispatchLoop has the most user-visible gap (#199 Bug A is why count-to-100 hits 60 s timeout).

---

## §hook-audit (6 rows — per FR-011)

| Hook | Shell ref | TS ref | Gap | Fix plan | Test fixture |
|---|---|---|---|---|---|
| **post-tool-use** | `post-tool-use.sh:1–368` (esp. lines 81–176 deactivate branch) | `post-tool-use.ts:1–523` (esp. line 483) | Two gaps: (i) deactivate.sh handler is a NO-OP (line 483 just emits `{hookEventName: "PostToolUse"}`) — shell does full archive to `.wheel/history/stopped/` + cascade stop to child + teammate sub-workflows (shell:81–176). `/wheel:wheel-stop` is BROKEN under TS today. (ii) Leftover `console.error('DEBUG: ...')` calls at lines 390, 476, 478, 490, 492 — pollute hook stderr; not parity. | (i) Port shell deactivate logic to TS: parse `--all` / target-substring / default-self-only modes; archive matching state files; cascade stop to child workflows (parent_workflow points to non-existent file); cascade stop to team sub-workflows (teammate agent_ids). (ii) Delete debug prints. | new `hook-deactivate.test.ts` (3 tests: --all, target-substring, self-only) + `/wheel:wheel-test` indirectly via fixture cleanup. |
| **stop** | `stop.sh:1–99` | `stop.ts:1–57` | Audit: TS already calls engineInit + engineHandleHook (wait-all-redesign). Verify decision JSON shape matches shell. No known gap; sanity check. | Read both files end-to-end; if no gap, write "no gap" entry in §intentional-deviations with rationale. | covered by all `/wheel:wheel-test` fixtures (every workflow ends in stop hook fires). |
| **subagent-stop** | `subagent-stop.sh:1–54` | `subagent-stop.ts:1–55` | Audit: small file, mostly delegates to engine. Verify teammate-completion-status transition triggers archive check correctly (interaction with `dispatchTeamWait` polling backstop, dispatch-team-wait.test.ts). | Confirm engineHandleHook in subagent-stop path correctly transitions teammate to `completed` and triggers `_recheckAndCompleteIfDone`. | covered by `dispatch-team-wait.test.ts` + `/wheel:wheel-test team-static`. |
| **teammate-idle** | `teammate-idle.sh:1–84` | `teammate-idle.ts:1–53` | Audit: shell scans `.wheel/state_*.json` for archived child state file (shell dispatch.sh:2199–2209); verify TS does same archive-detection logic for teammate workflows that already archived. | Confirm engineHandleHook in teammate-idle path includes archive-detection; if missing, port from shell. | covered by `dispatch-team-wait.test.ts:teammate-idle-archive-detection` + `/wheel:wheel-test team-dynamic`. |
| **session-start** | `session-start.sh:1–48` | `session-start.ts:1–26` | Audit: small TS file (26 lines vs 48 shell). Verify registry build + state hydration matches shell. | Read both end-to-end; document any gap. Likely no behavioural gap given small surface. | covered by `engine.test.ts:registry-build` + `/wheel:wheel-test` warm-up. |
| **subagent-start** | `subagent-start.sh:1–69` | `subagent-start.ts:1–26` | Audit: TS smaller than shell (26 vs 69 lines). Verify child-state init mirrors shell pattern (Phase 4 fixtures depend on this; team-* sub-workflows kick off here). | Read both end-to-end; if shell does state init that TS skips, port it. | covered by `/wheel:wheel-test team-dynamic` (dynamic teammate spawn → subagent-start fires). |

**Summary**: post-tool-use has the load-bearing gap (deactivate.sh is broken). The other 5 hooks are smaller files; they need read-and-confirm passes, not big rewrites.

---

## §intentional-deviations

| Behaviour | Shell ref | Reason for deviation | Follow-up issue |
|---|---|---|---|
| Output-schema validation in `dispatchAgent` (`workflow_validate_output_against_schema`) | shell:642–660 | TS rewrite has not implemented the `wheel-typed-schema-locality` Theme H1 wrapper. Porting it would balloon scope. spec.md FR-002 explicitly defers. Schema-violation block is not test-fixture parity (no fixture asserts on the violation message). | TBD — implementer files at end of pipeline. |
| `WheelLogPhase` type strictness | parent rewrite | `wheelLog(phase: string, fields)` accepts any string in TS — shell uses freeform string. No deviation in observable behaviour. | n/a |
| `dispatchLoop` cascade tail uses raw `stepIndex+1` | shell `dispatch_loop` :1551 | The `cascadeNext` helper already walks past skipped steps (`dispatch.ts:149-166`). `step.next` field is uncommon in loop tail paths — the only difference is when a workflow author adds `next` to a `loop` step, which is uncommon. T-033 deferred per FR-013 frozen scope; will file follow-up issue if a fixture surfaces it. | TBD |
| `stop.ts` / `subagent-stop.ts` / `teammate-idle.ts` / `session-start.ts` / `subagent-start.ts` | various | TS hooks all delegate to `engineInit` + `engineHandleHook` (wait-all-redesign foundation). End-to-end audit confirmed parity. The TS files are intentionally smaller than shell because the engine modularisation collapsed per-hook bookkeeping into shared helpers. | n/a |

Add additional rows during implementation if any further deliberate deviations surface. The auditor MUST flag any undocumented deviation.

---

## §FR-009-decision

**Choice**: Option (a) — pin `@vitest/coverage-v8` to a 1.6.x-compatible version.

**Rationale**:
- vitest 3 introduces breaking changes to test-helper APIs (mock factories, expect-pool semantics).
- Existing 99 vitest tests are stable on 1.6.x; bumping to vitest 3 risks 1–10 test failures unrelated to parity work.
- `@vitest/coverage-v8@^1.0.0` shipped on npm matches vitest 1.x; the registry has compatible versions.
- Risk of option (a) is bounded: if 1.6.x coverage-v8 is missing a feature we need, downgrade to a compatible version like `0.34.x` is still simpler than vitest 3 bump.

**Validation step (impl-wheel runs at FR-009 time)**: `cd plugin-wheel && npm install @vitest/coverage-v8@^1.6.1 --save-dev && npx vitest run --coverage`. If exit 0 with coverage table → ship. If still broken → fall back to option (b) (vitest 3 bump) and re-run all 99 tests, fix any breakage, document in this section.

---

## §source-of-truth references

- Shell canonical: `~/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.842/lib/dispatch.sh` (2489 lines), `hooks/*.sh` (6 files, 720 lines total).
- TS current: `plugin-wheel/src/lib/dispatch.ts` (1215 lines), `src/hooks/*.ts` (6 files, 740 lines total).
- Engine: shell `lib/engine.sh` (354 lines), TS `src/lib/engine.ts` (236 lines) — `archiveWorkflow` lives here, plus `engineHandleHook` post-dispatch advance.
- Existing TS tests: `plugin-wheel/src/lib/{dispatch,engine,state,archive-workflow,dispatch-cascade,dispatch-status,dispatch-team-wait,dispatch-terminal}.test.ts`.

---

## Reconciliation notes

- **R-1 (scope balloon)**: this audit produces 11 + 6 = 17 gap rows. Several rows expand to multiple sub-gaps (dispatchAgent has 6, dispatchTeammate has 4). Total impl-task count is ~30. This is the frozen scope per FR-013.
- **R-3 (composition cascade)**: requires reading `archiveWorkflow` to determine whether composition parent-resume branch already exists. impl-wheel resolves at start of FR-005 work.
- **R-7 (cache redeploy fragility)**: audit-pr's prompt MUST document the canonical cleanup path — restore from `/tmp/wheel-cache-backup-...` IF it exists; ELSE rebuild from `git show 5e61699b:plugin-wheel/dist/...` (last known shell-only cache state). PR #200's audit-pr learned this; reuse procedure.
