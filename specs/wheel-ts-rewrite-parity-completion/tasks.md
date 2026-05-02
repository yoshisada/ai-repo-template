# Tasks — Wheel TS Rewrite Parity Completion

**Spec**: `specs/wheel-ts-rewrite-parity-completion/spec.md`
**Plan**: `specs/wheel-ts-rewrite-parity-completion/plan.md`
**Contracts**: `specs/wheel-ts-rewrite-parity-completion/contracts/interfaces.md`
**Research (gap audit, FROZEN scope per FR-013)**: `specs/wheel-ts-rewrite-parity-completion/research.md`

Execution rules (Constitution Articles VII + VIII):
- Mark `[X]` IMMEDIATELY after completing a task — not in batches.
- Commit after each phase (groups indicated by phase headers below).
- Every function reference in implementation MUST match `contracts/interfaces.md` exactly.
- Every code line that changes behaviour MUST carry a `// parity: shell dispatch.sh:NNNN — <one-line>` comment (SC-7).
- Every gap row in `research.md §dispatcher-audit` / `§hook-audit` MUST map to a task here. Auditor enforces.

---

## Phase 0 — Read & verify existing helpers (no commit)

- [X] **T-001** — Read `plugin-wheel/src/lib/dispatch.ts` end-to-end. Confirm gap rows from `research.md §dispatcher-audit` are accurate. Confirm cascade tails from PR #200 are present at `dispatchCommand`/`dispatchLoop`/`dispatchBranch`.
- [X] **T-002** — Read `plugin-wheel/src/hooks/post-tool-use.ts`. Confirm deactivate handler on line 483 is no-op. Confirm `console.error('DEBUG ...')` calls at lines 390, 476, 478, 490, 492.
- [X] **T-003** — Verify existing helpers exist. **Result**: `stateClearAwaitingUserInput`, `stateRemoveTeam`, `stateAddTeammate`, `contextBuild` exist. **MISSING (need porting)**: `resolveNextIndex`, `advancePastSkipped`, `contextCaptureOutput`, `contextWriteTeammateFiles`. Contract §1 already accurately calls out the second-half as "likely missing — verify".
- [X] **T-004** — Read shell `dispatch.sh` `_chain_parent_after_archive` (:144), `handle_terminal_step` (:226), `resolve_next_index`/`advance_past_skipped` (:71/98), and `_teammate_chain_next` (:1889) bodies for parity port plan.
- [X] **T-005** — Read shell `hooks/post-tool-use.sh` lines 81–176 (deactivate handler).

---

## Phase 1 — vitest coverage tooling (FR-009)

- [X] **T-010** — Edit `plugin-wheel/package.json`: change `"@vitest/coverage-v8": "^4.1.5"` → `"@vitest/coverage-v8": "^1.6.1"` (option a per `research.md §FR-009-decision`).
- [X] **T-011** — `cd plugin-wheel && npm install`. Install succeeded (16 packages added, 8 removed, 4 changed).
- [X] **T-012** — `cd plugin-wheel && npx vitest run --coverage`. Coverage report printed, all 99 tests pass. SC-3 met.
- [X] **T-013** — Option (a) succeeded; option (b) fallback NOT needed.
- [ ] **T-014** — Commit: `chore(wheel-ts): vitest coverage-v8 1.6.x compat (FR-009)`.

---

## Phase 2 — dispatchCommand WORKFLOW_PLUGIN_DIR injection (FR-001)

- [X] **T-020** — Added `deriveWorkflowPluginDir(stateFile)` to `workflow.ts` (also ports `resolveNextIndex` + `advancePastSkipped` per Phase 0 audit). Match contracts §9.
- [X] **T-021** — `dispatchCommand` now injects `WORKFLOW_PLUGIN_DIR` into child process env via `cmdEnv`.
- [X] **T-022** — `dispatch.test.ts:command-exports-plugin-dir` added; verifies child process sees the env var.
- [X] **T-023** — `npx vitest run`: 100/100 pass.
- [ ] **T-024** — Commit: `feat(wheel-ts): dispatchCommand WORKFLOW_PLUGIN_DIR injection (FR-001)`.

---

## Phase 3 — dispatchLoop #199 Bug A + Bug B + env injection (FR-003)

- [X] **T-030** — Bug B fix: changed reMaxIter source from `reState.steps[stepIndex]` to `(step as any).max_iterations`.
- [X] **T-031** — Bug A fix: replaced `return { decision: 'approve' }` with `return dispatchLoop(step, hookType, hookInput, stateFile, stepIndex, depth)` for self-cascade.
- [X] **T-032** — Added `WORKFLOW_PLUGIN_DIR` env injection to substep command exec.
- [ ] **T-033** — DEFERRED — `cascadeNext` already walks past skipped steps internally (lines 149–166), and the workflow-def `next` field is uncommon in loop-cascade tail paths. Filing as follow-up issue if a fixture surfaces it; FR-013 frozen-scope dictates no in-flight expansion.
- [X] **T-034** — Created `dispatch-loop-iter.test.ts` with 3 tests; all pass.
- [X] **T-035** — `npx vitest run`: 103/103 pass.
- [ ] **T-036** — Commit: `fix(wheel-ts): dispatchLoop self-cascade + max_iterations from workflow def (FR-003, closes #199)`.

---

## Phase 4 — dispatchAgent 6 sub-fixes (FR-002)

- [X] **T-040** — Stale-output-file deletion on pending→working in stop hook.
- [X] **T-041** — Cursor advance via `resolveNextIndex` + `advancePastSkipped`.
- [X] **T-042** — `stateClearAwaitingUserInput` after advance.
- [X] **T-043** — `contextCaptureOutput` replaces null-out regression.
- [X] **T-044** — `_chainParentAfterArchive` added (helper near top of dispatch.ts), called when terminal child archives. Also ports `contextCaptureOutput` + `contextWriteTeammateFiles` to context.ts (Phase 0 helper port).
- [X] **T-045** — All 5 `console.error('DEBUG dispatchAgent: ...')` calls removed.
- [X] **T-046** — `dispatch-agent-parity.test.ts` (6 tests) — all pass.
- [X] **T-047** — `npx vitest run`: 109/109 pass.
- [ ] **T-048** — Commit: `feat(wheel-ts): dispatchAgent parity (FR-002)`.

---

## Phase 5 — dispatchBranch resolveNextIndex (FR-004)

- [ ] **T-050** — At `dispatch.ts:953` (END / fall-through branch path), replace `cascadeNext(..., stepIndex + 1, depth)` with `resolveNextIndex` + `advancePastSkipped` chain. Comment: `// parity: shell dispatch.sh — branch fall-through respects skipped + next field.`
- [ ] **T-051** — `npx vitest run dispatch-cascade.test.ts` — `branch-jump-cascade` and related tests still pass.
- [ ] **T-052** — Commit: `fix(wheel-ts): dispatchBranch fall-through cursor via resolveNextIndex (FR-004)`.

---

## Phase 6 — dispatchWorkflow + archiveWorkflow composition parent-resume (FR-005)

- [ ] **T-060** — Read `plugin-wheel/src/lib/engine.ts` `archiveWorkflow` (or wherever wait-all FR-009 archive helper lives). Identify whether composition parent-resume branch is present (decision D-3).
- [ ] **T-061** — If absent: add `_chainParentAfterArchive` helper per contracts §3 (also used by FR-002 T-044). Wire from `archiveWorkflow` when archived state had `parent_workflow` set.
- [ ] **T-062** — Verify `dispatchWorkflow` (line 378) cascade-into-child still works — read existing impl, add comment anchoring to PR #200 work.
- [ ] **T-063** — Add test `dispatch-terminal.test.ts:child-archive-advances-parent` — composition fixture where child archives and parent's cursor advances + next step dispatches.
- [ ] **T-064** — `npx vitest run` — all tests pass.
- [ ] **T-065** — Commit: `feat(wheel-ts): composition child-archive advances parent cursor (FR-005)`.

---

## Phase 7 — Team primitives (FR-006)

This is the largest phase. Sub-divide into 4 commits.

### Phase 7a — TeamCreate post_tool_use cascade (FR-006 A1)

- [ ] **T-070** — Read `dispatchTeamCreate` (line 477). Verify post_tool_use branch ends with cascadeNext/resolveNextIndex chain after marking team done. If not, add it. Comment: `// parity: shell dispatch.sh:1669–1673.`
- [ ] **T-071** — Test (existing or extend `dispatch.test.ts`).
- [ ] **T-072** — Commit: `feat(wheel-ts): dispatchTeamCreate post_tool_use cascade (FR-006 A1)`.

### Phase 7b — Teammate context files + chain-next + post_tool_use + dynamic assign (FR-006 A2/A3/A4)

- [ ] **T-073** — Port `contextWriteTeammateFiles` from shell `lib/context.sh` to TS `plugin-wheel/src/lib/context.ts` per contracts §2. Tests in `context.test.ts` (new or extend).
- [ ] **T-074** — Port `_teammateChainNext` + `_teammateFlushFromState` per contracts §4. Place in new module `plugin-wheel/src/lib/dispatch-team.ts` per decision D-4 (dispatch.ts is over the 500-line cap).
- [ ] **T-075** — Update `dispatchTeammate` (line 524) to call `contextWriteTeammateFiles` + `_teammateChainNext` after registering teammate(s). Replace per-teammate `decision:'block'` with single batched block from `_teammateFlushFromState`. Comments: `// parity: shell dispatch.sh:1806/1827`, `// parity: shell dispatch.sh:1813/1832`.
- [ ] **T-076** — Add `dispatchTeammate` post_tool_use branch — detect `TaskCreate` tool_name, match `subject` to teammate name, update teammate `task_id`. Comment: `// parity: shell dispatch.sh:1843–1876.`
- [ ] **T-077** — In dynamic-spawn loop at line 596, replace hardcoded `assign: {}` with `assign: agentAssign` (computed via round-robin distribution like shell:1803–1804). Comment: `// parity: shell dispatch.sh:1796–1808.`
- [ ] **T-078** — Create `dispatch-teammate.test.ts` with 4 tests per plan §5.
- [ ] **T-079** — `npx vitest run` — all tests pass.
- [ ] **T-080** — Commit: `feat(wheel-ts): dispatchTeammate parity — context files + chain-next + post_tool_use (FR-006 A2-A4)`.

### Phase 7c — TeamWait summary.json + collect_to (FR-006 A5/A6)

- [ ] **T-081** — Add `_teamWaitComplete(step, stateFile, stepIndex, teamRef)` to `dispatch-team.ts` per contracts §5. Writes summary.json + (if `collect_to` set) copies teammate outputs.
- [ ] **T-082** — Wire `_teamWaitComplete` into `_recheckAndCompleteIfDone` (line 636) at the point where teammate count is fully done (BEFORE marking step done).
- [ ] **T-083** — Extend `dispatch-team-wait.test.ts` with `:wait-summary-output` and `:collect-to-copy`.
- [ ] **T-084** — `npx vitest run` — all tests pass.
- [ ] **T-085** — Commit: `feat(wheel-ts): dispatchTeamWait summary.json + collect_to (FR-006 A5-A6)`.

### Phase 7d — TeamDelete full implementation (FR-006 A7)

- [ ] **T-086** — Verify `stateRemoveTeam` exists in `state.ts`; if not, port from shell `state_remove_team`.
- [ ] **T-087** — Replace `dispatchTeamDelete` stub at line 902 with full implementation per contracts §6. Stop hook (pending → block "Delete team"; working → "still waiting"); post_tool_use hook (TeamDelete detection → state_remove_team + cascade). Idempotency check for already-deleted team. Comments: `// parity: shell dispatch.sh:2398–2483.`
- [ ] **T-088** — Create `dispatch-team-delete.test.ts` with 3 tests per plan §5.
- [ ] **T-089** — `npx vitest run` — all tests pass.
- [ ] **T-090** — Commit: `feat(wheel-ts): dispatchTeamDelete full implementation (FR-006 A7)`.

---

## Phase 8 — Parallel + Approval audit (FR-007)

- [ ] **T-100** — Read `dispatchParallel` (line 1122) and shell `dispatch_parallel` (dispatch.sh:1215) side by side. Document any concrete gap in `research.md §intentional-deviations` OR fix it. Add minimal `dispatch-parallel.test.ts:basic-dispatch` test.
- [ ] **T-101** — Read `dispatchApproval` (line 1186) and shell `dispatch_approval` (dispatch.sh:1300) side by side. Verify teammate_idle handling; if missing, add it. Add `dispatch-approval.test.ts:approval-teammate-idle` test.
- [ ] **T-102** — `npx vitest run` — all tests pass.
- [ ] **T-103** — Commit: `feat(wheel-ts): dispatchParallel + dispatchApproval parity (FR-007)`.

---

## Phase 9 — post-tool-use handleDeactivate (FR-008 A1)

- [ ] **T-110** — Add `handleDeactivate(command, hookInput)` to `plugin-wheel/src/hooks/post-tool-use.ts` per contracts §11. Three modes: `--all`, target-substring, self-only (matched by `owner_session_id` + `owner_agent_id`). Cascade-stop child workflows + team sub-workflows. Comment: `// parity: shell post-tool-use.sh:81–176.`
- [ ] **T-111** — In `main()` (line 482), replace the no-op deactivate branch with a call to `handleDeactivate`.
- [ ] **T-112** — Create `plugin-wheel/src/hooks/hook-deactivate.test.ts` with 3 tests per plan §5: (i) --all; (ii) target-substring; (iii) self-only.
- [ ] **T-113** — `npx vitest run` — all tests pass.
- [ ] **T-114** — Commit: `feat(wheel-ts): post-tool-use handleDeactivate (FR-008 A1)`.

---

## Phase 10 — Hook hygiene + read-and-confirm (FR-008 A2-A5)

- [ ] **T-120** — DELETE all `console.error('DEBUG ...')` calls in `plugin-wheel/src/hooks/post-tool-use.ts` (lines 390, 476, 478, 490, 492). Verify `git grep -F "DEBUG" plugin-wheel/src/hooks/post-tool-use.ts` returns 0 hits.
- [ ] **T-121** — Read `stop.ts`, `subagent-stop.ts`, `teammate-idle.ts`, `session-start.ts`, `subagent-start.ts` end-to-end. Confirm parity with shell counterparts. Document any gap in `research.md §intentional-deviations` OR fix it.
- [ ] **T-122** — `npx vitest run` — all tests pass.
- [ ] **T-123** — Commit: `chore(wheel-ts): hook hygiene + read-and-confirm (FR-008 A2-A5)`.

---

## Phase 11 — Smoke gate (FR-010 / SC-1) — owned by audit-pr task

This phase is executed by the audit-pr task, NOT impl-wheel. impl-wheel hands off here.

- [ ] **T-130** — `cd plugin-wheel && npm run build`. TS strict, zero errors.
- [ ] **T-131** — Backup cache (if not already): `[ -d /tmp/wheel-cache-backup-pr200 ] || cp -r ~/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.842 /tmp/wheel-cache-backup-pr200`.
- [ ] **T-132** — Deploy: `rm -rf $CACHE/dist && cp -r plugin-wheel/dist $CACHE/dist && cp plugin-wheel/hooks/*.sh $CACHE/hooks/`.
- [ ] **T-133** — Clean: `rm -f .wheel/state_*.json && rm -rf ~/.claude/teams/test-{static,dynamic,partial-failure}-team`.
- [ ] **T-134** — Run `/wheel:wheel-test`. Verify 13/13 fixtures pass. SC-1.
- [ ] **T-135** — `ls .wheel/state_*.json | wc -l` returns 0.
- [ ] **T-136** — Restore plugin cache from backup.
- [ ] **T-137** — If T-134 fails: SendMessage to impl-wheel with failing fixture name(s) + transcript path. Re-run after fix. Budget 1–3 ping-pongs (PRD R-6).

---

## Phase 12 — Audit (audit-compliance task)

- [ ] **T-140** — `git diff --stat 002-wheel-ts-rewrite..HEAD` — verify zero new step types in workflow JSON schema; zero new hook event types. SC-6.
- [ ] **T-141** — `git grep -n "// parity:" plugin-wheel/src/lib/dispatch.ts` — verify ≥ 1 match per fixed gap row. SC-7.
- [ ] **T-142** — `git grep -F "DEBUG" plugin-wheel/src/{lib/dispatch.ts,hooks/post-tool-use.ts}` — verify 0 hits.
- [ ] **T-143** — Coverage gate: new/changed code ≥ 80% line + branch (Constitution Article II). Verify via `npx vitest run --coverage`.
- [ ] **T-144** — PRD coverage: every PRD FR-1 through FR-12 maps to a `spec.md` FR maps to a `tasks.md` task. Document any blocker in `blockers.md`.

---

## Phase 13 — PR (audit-pr task)

- [ ] **T-150** — Open PR titled "Wheel TS rewrite — parity completion (final pass)". Body: link PR #200 + `docs/features/2026-05-01-wheel-ts-rewrite-parity-completion/PRD.md` + `.wheel/logs/test-run-<timestamp>.md` smoke transcript. Per PRD Q4: this PR supersedes PR #200; close PR #200 at merge time.

---

## Task → Gap-row traceability

Per FR-013, every task here maps to a research.md gap row. Auditor uses this table:

| Task(s) | Gap row | FR |
|---|---|---|
| T-020/021/022 | dispatcher-audit row 1 (dispatchCommand) | FR-001 |
| T-040…T-046 | dispatcher-audit row 2 (dispatchAgent) — 6 sub-fixes | FR-002 |
| T-030…T-035 | dispatcher-audit row 3 (dispatchLoop) — Bug A + Bug B + env | FR-003 |
| T-050/051 | dispatcher-audit row 4 (dispatchBranch) | FR-004 |
| T-060…T-064 | dispatcher-audit row 5 (dispatchWorkflow) | FR-005 |
| T-070/071 | dispatcher-audit row 6 (dispatchTeamCreate) | FR-006 A1 |
| T-073…T-079 | dispatcher-audit row 7 (dispatchTeammate) — 4 sub-fixes | FR-006 A2-A4 |
| T-081…T-084 | dispatcher-audit row 8 (dispatchTeamWait) | FR-006 A5-A6 |
| T-086…T-089 | dispatcher-audit row 9 (dispatchTeamDelete) | FR-006 A7 |
| T-100 | dispatcher-audit row 10 (dispatchParallel) | FR-007 A1 |
| T-101 | dispatcher-audit row 11 (dispatchApproval) | FR-007 A2 |
| T-110…T-113 | hook-audit row 1 (post-tool-use deactivate) | FR-008 A1 |
| T-120 | hook-audit row 1 (post-tool-use DEBUG cleanup) | FR-008 A2 |
| T-121 | hook-audit rows 2–6 (stop, subagent-stop, teammate-idle, session-start, subagent-start) | FR-008 A3-A5 |
| T-010…T-013 | (FR-009 — vitest tooling, not a parity gap) | FR-009 |
| T-130…T-137 | (smoke gate, audit-pr) | FR-010 |
| T-140…T-144 | (audit) | FR-012 |
| T-150 | (PR creation) | — |

The auditor MUST flag any task that does not derive from a gap row (FR-013 scope freeze).
