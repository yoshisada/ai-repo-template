# Implementation Plan — Wheel TS Rewrite Parity Completion

**Spec**: `specs/wheel-ts-rewrite-parity-completion/spec.md`
**Contracts**: `specs/wheel-ts-rewrite-parity-completion/contracts/interfaces.md`
**Research**: `specs/wheel-ts-rewrite-parity-completion/research.md`

## Foundation note (READ FIRST)

This PRD is the FINAL pass on the in-progress TypeScript rewrite. The pipeline branch is `build/wheel-ts-rewrite-parity-completion-20260501`, branched from `build/wheel-ts-dispatcher-cascade-20260501` (PR #200). The in-progress code on this branch — including cascade tails, wait-all archive helper, engineInit-in-hooks, workflow_definition persistence, and `dispatchTeamWait` polling backstop — is the FOUNDATION the implementer extends. Parent-branch decisions are FROZEN.

The implementer's job is mechanical:
1. Read the gap rows in `research.md §dispatcher-audit` + `§hook-audit`.
2. Apply the fix-plan column to the corresponding TS file:line.
3. Anchor each fix with a `// parity: shell dispatch.sh:NNNN — <one-line behaviour summary>` comment (SC-7).
4. Add the test fixture from the gap row.

Per FR-013 (scope freeze): if a new gap surfaces during implementation, file a follow-up GitHub issue, do NOT add to `tasks.md` mid-implementation.

## 1. Architecture

### Where parity fixes live

```
plugin-wheel/src/
├── lib/
│   ├── dispatch.ts         ← 11 dispatchers, 9 with gaps (FR-001 through FR-007)
│   ├── context.ts          ← +contextWriteTeammateFiles, +contextCaptureOutput verify (FR-006, FR-002)
│   ├── workflow.ts         ← resolveNextIndex / advancePastSkipped (verify exist, used by all cascade tails)
│   ├── state.ts            ← +stateRemoveTeam, +stateClearAwaitingUserInput verify (FR-006, FR-002)
│   ├── engine.ts           ← archiveWorkflow composition-parent branch (FR-005)
│   └── *.test.ts           ← parity fixtures per gap row
└── hooks/
    ├── post-tool-use.ts    ← +handleDeactivate (FR-008 A1) + DEBUG cleanup (FR-008 A2)
    └── stop|subagent-stop|teammate-idle|session-start|subagent-start.ts ← read-and-confirm (FR-008 A3-A5)
```

### Cascade composition flow (parity check, no change)

```
PostToolUse hook
  ├── handleDeactivate        ← NEW, FR-008 A1
  ├── handleActivation        ← unchanged (cascade shipped in PR #200)
  └── handleNormalPath
        └── engineHandleHook
              └── dispatchStep
                    ├── dispatchCommand   ← FR-001 (env injection)
                    ├── dispatchAgent     ← FR-002 (6 sub-fixes)
                    ├── dispatchLoop      ← FR-003 (#199 Bug A + B)
                    ├── dispatchBranch    ← FR-004 (resolveNextIndex)
                    ├── dispatchWorkflow  ← FR-005 (parent-resume on child archive)
                    ├── dispatchTeamCreate, dispatchTeammate, dispatchTeamWait, dispatchTeamDelete  ← FR-006 (4 sub-fixes)
                    ├── dispatchParallel  ← FR-007 (audit confirm)
                    └── dispatchApproval  ← FR-007 (audit confirm)
```

## 2. Phase order

Phases follow gap-density order (lowest-risk fixes first to keep `npx vitest run` green continuously):

| Phase | FR | Scope | Risk |
|---|---|---|---|
| 0 | (read) | Verify existing helpers (resolveNextIndex, advancePastSkipped, contextCaptureOutput, stateClearAwaitingUserInput, stateRemoveTeam) — port any missing | low |
| 1 | FR-009 | vitest coverage tooling — package.json downgrade (option a) | low |
| 2 | FR-001 | dispatchCommand WORKFLOW_PLUGIN_DIR env injection | low |
| 3 | FR-003 | dispatchLoop #199 Bug A + Bug B + env injection | medium (changes loop semantics) |
| 4 | FR-002 | dispatchAgent 6 sub-fixes + DEBUG cleanup | medium (output-file plumbing) |
| 5 | FR-004 | dispatchBranch resolveNextIndex | low |
| 6 | FR-005 | dispatchWorkflow + archiveWorkflow composition parent-resume | medium (cross-module) |
| 7 | FR-006 | team primitives — TeamCreate, Teammate (4 sub-fixes), TeamWait, TeamDelete (full reimpl) | high (largest surface) |
| 8 | FR-007 | dispatchParallel + dispatchApproval audit + minimal fixtures | low |
| 9 | FR-008 A1 | post-tool-use handleDeactivate | medium |
| 10 | FR-008 A2-A5 | DEBUG cleanup + remaining hook audits | low |
| 11 | FR-010 | smoke gate — /wheel:wheel-test Phases 1–4 (audit-pr task) | gate |

After each phase: `npx vitest run` MUST stay green; commit as `feat(wheel-ts): <phase> (FR-NNN)` per Constitution Article VIII.

## 3. Build + smoke gate procedure (FR-010 / SC-1)

audit-pr task runs:

```bash
cd plugin-wheel
npm run build || exit 1                                         # TS strict, no errors
CACHE=~/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.009.842
# backup if not already backed up
[ -d /tmp/wheel-cache-backup-pr200 ] || cp -r "$CACHE" /tmp/wheel-cache-backup-pr200
rm -rf "$CACHE/dist" && cp -r dist "$CACHE/dist"
cp hooks/*.sh "$CACHE/hooks/"
cd ..
rm -f .wheel/state_*.json
rm -rf ~/.claude/teams/test-static-team ~/.claude/teams/test-dynamic-team ~/.claude/teams/test-partial-failure-team
# run /wheel:wheel-test from Claude Code session — verify 13/13 pass
# verify ls .wheel/state_*.json | wc -l → 0
# RESTORE cache
rm -rf "$CACHE/dist" && cp -r /tmp/wheel-cache-backup-pr200/dist "$CACHE/dist"
cp /tmp/wheel-cache-backup-pr200/hooks/*.sh "$CACHE/hooks/"
```

If `/wheel:wheel-test` reports any failure:
- audit-pr SendMessage to impl-wheel with the specific fixture name(s) that failed.
- impl-wheel reads the fixture's transcript at `.wheel/logs/test-run-<timestamp>.md`, identifies the gap, fixes it (referring back to §dispatcher-audit / §hook-audit if the gap is documented; filing a follow-up issue if NEW per FR-013), pushes the fix, and SendMessage back to audit-pr.
- audit-pr re-runs the smoke gate. PR R-6 budgets 1–3 ping-pongs.

## 4. Decision points

### D-1 — Helper reuse vs new ports
For every "use existing helper X" in the contract: at start of relevant phase, `git grep -nE "export (async )?function X|export const X" plugin-wheel/src/lib/`. If hit: use as-is. If miss: port from shell, add to contract Section 1 BEFORE using.

### D-2 — vitest option (a) vs (b)
Default (a) per `research.md §FR-009-decision`. impl-wheel verifies in Phase 1; documents outcome.

### D-3 — Composition parent-resume (FR-005 R-3)
At start of Phase 6: read `archiveWorkflow` in `engine.ts` for an existing composition-parent branch. If present: verify behaviour matches shell `_chain_parent_after_archive`. If absent: add the `_chainParentAfterArchive` helper per contract §3 and call from `archiveWorkflow`.

### D-4 — `_teammateFlushFromState` placement
Helper can live inside `dispatch.ts` (matching shell layout) or `team.ts` (new module). impl-wheel chooses based on dispatch.ts size cap (Constitution Article VI: files < 500 lines). Current dispatch.ts is 1215 lines — already over. New helpers MUST extract to a new module `dispatch-team.ts` to avoid further bloat.

### D-5 — Output-schema validation deferral (FR-002 OOS)
File a follow-up GitHub issue at end of impl phase: "Wheel TS — output-schema validation in dispatchAgent (Theme H1 of wheel-typed-schema-locality)". Reference `research.md §intentional-deviations`.

## 5. Test plan (FR-012 + SC-4)

### New parity fixtures

| Fixture file | Tests | Maps to FR |
|---|---|---|
| `dispatch-loop-iter.test.ts` | (i) max_iterations:50 runs to 50; (ii) max_iterations sourced from workflow def; (iii) early condition exits before cap. | FR-003 |
| `dispatch-agent-parity.test.ts` | (i) stale-output-file deletion on pending→working; (ii) cursor advance via resolveNextIndex; (iii) awaiting_user_input cleared on advance; (iv) contextCaptureOutput on advance; (v) parent-cursor advances after terminal child archive; (vi) no DEBUG output. | FR-002 |
| `dispatch-teammate.test.ts` | (i) contextWriteTeammateFiles writes context.md + assign_inputs.json; (ii) `_teammateChainNext` emits single batched block; (iii) post_tool_use TaskCreate detection; (iv) dynamic-spawn assign threading. | FR-006 |
| `dispatch-team-delete.test.ts` | (i) stop pending → block with "Delete team"; (ii) post_tool_use TeamDelete → state_remove_team + cascade; (iii) idempotency when team already deleted. | FR-006 A7 |
| `dispatch-team-wait.test.ts` (extend) | `:wait-summary-output`, `:collect-to-copy` | FR-006 A5/A6 |
| `dispatch-parallel.test.ts` | (i) basic dispatch path | FR-007 A1 |
| `dispatch-approval.test.ts` | (i) approval-teammate-idle advances on approved | FR-007 A2 |
| `hook-deactivate.test.ts` | (i) --all archives all; (ii) target-substring archives matching; (iii) self-only matches owner. | FR-008 A1 |
| `dispatch.test.ts` (extend) | `:command-exports-plugin-dir` | FR-001 |
| `dispatch-terminal.test.ts` (extend) | `:child-archive-advances-parent` | FR-005 |

Existing 99 tests MUST stay green continuously (run after each phase commit).

### Coverage gate

After Phase 1 completes: `npx vitest run --coverage` produces a usable report. Per Constitution Article II, new/changed code MUST achieve ≥ 80% line + branch coverage. Auditor verifies in audit-compliance task.

### Smoke gate

`/wheel:wheel-test` Phases 1–4 100% pass per FR-010. SC-1.

## 6. Out-of-scope (re-affirm)

- No new step types or workflow JSON schema fields.
- No new hook event types.
- No re-litigation of cascade or wait-all-redesign.
- No fix for shell wheel quirks.
- Output-schema validation in dispatchAgent (deferred — §intentional-deviations).

## 7. Hand-off contract for impl-wheel

When impl-wheel begins task #2:
1. Read `spec.md`, `plan.md`, `contracts/interfaces.md`, `research.md` (esp. the two audit tables).
2. Phase order = §2 of this plan. Strict.
3. Constitution Articles VII (interface contracts) + VIII (incremental task completion + commit per phase).
4. After each phase: `npx vitest run` + push commit; SendMessage to team-lead with phase summary.
5. After Phase 11 (FR-010): if `/wheel:wheel-test` is 13/13 green, SendMessage to audit-compliance.
6. Friction note in `agent-notes/impl-wheel.md` per pipeline convention.
