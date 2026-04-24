---
description: "Task list for wheel-user-input feature — single implementer owns all tasks."
---

# Tasks: Wheel User-Input Primitive

**Input**: `specs/wheel-user-input/spec.md` + `specs/wheel-user-input/plan.md` + `specs/wheel-user-input/contracts/interfaces.md`
**Source PRD**: `docs/features/2026-04-23-wheel-user-input/PRD.md`

**Tests**: REQUIRED — every user story (US1..US7) has a test task (FR-016). Harness fixtures use `/kiln:kiln-test` (`plugin-skill` substrate); remaining tests are bash unit tests.

**Organization**: Phase 1 (foundational state + validator) → Phase 2 (CLI) → Phase 3 (Stop hook integration) → Phase 4 (skip skill) → Phase 5 (status surface) → Phase 6 (test fixtures) → Phase 7 (audit handoff).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel within the same phase (different files, no dependencies).
- **[Story]**: Maps to spec.md user story (US1..US7) for traceability.
- All implementation tasks must include the relevant FR comment in code per Constitution Article VII (Interface Contracts) and Article I (every function references its spec FR).
- Owner for every task: `implementer` (single implementer design).

## Path Conventions

- Plugin source: `plugin-wheel/` exclusively.
- Harness fixtures: `plugin-wheel/tests/wheel-user-input-<slug>/`.
- Unit tests: `plugin-wheel/tests/unit/test_wheel_user_input_*.sh`.

---

## Phase 0: Contracts pre-flight (5 min)

- [X] T000 Reconcile `specs/wheel-user-input/contracts/interfaces.md` §3.1 with plan.md deviation: add optional `awaiting_user_input_reason: string|null` field to the state schema. Update §3.1 and §5.3 step 6 to pass the reason through `state_set_awaiting_user_input`. Commit as a standalone contract patch before any code.

---

## Phase 1: State helpers + validator (foundational — blocks everything else)

- [X] T001 Add `workflow_validate_allow_user_input` function to `plugin-wheel/lib/workflow.sh` per contracts §4. Reject `allow_user_input: true` on step types ∉ {agent, loop, branch}. Include FR-001, FR-002 comment.
- [X] T002 Wire `workflow_validate_allow_user_input` into `workflow_load` in `plugin-wheel/lib/workflow.sh` — call after existing `workflow_validate_references` and `workflow_validate_workflow_refs`, propagate exit code.
- [X] T003 [P] Add `state_set_awaiting_user_input(state_file, step_index, reason)` helper to `plugin-wheel/lib/state.sh` per contracts §3.1. Atomic write; sets all three fields (`awaiting_user_input: true`, `awaiting_user_input_since: <ISO-8601-UTC>`, `awaiting_user_input_reason: <reason>`). Include FR-003, FR-004 comment.
- [X] T004 [P] Add `state_clear_awaiting_user_input(state_file, step_index)` helper to `plugin-wheel/lib/state.sh`. Atomic write; sets all three fields to their defaults (`false`, `null`, `null`). Idempotent. Include FR-004, FR-008 comment.
- [X] T005 [P] Write `plugin-wheel/tests/unit/test_wheel_user_input_validator.sh` — asserts good workflows pass and bad workflows fail with the documented error format. Covers US3 acceptance scenario 2.
- [X] T006 [P] Write `plugin-wheel/tests/unit/test_wheel_user_input_state_helpers.sh` — asserts set + clear round-trip correctness, idempotency, atomic replacement (state file never partially written).

**Phase 1 exit gate**: T001–T006 all marked `[X]`; running T005 + T006 locally passes. Commit with message `feat(wheel-user-input): phase 1 — validator + state helpers`.

---

## Phase 2: CLI (`wheel-flag-needs-input`)

- [X] T007 Create `plugin-wheel/bin/wheel-flag-needs-input` per contracts §5 — shebang `#!/usr/bin/env bash`, `set -euo pipefail`, sources `lib/guard.sh` + `lib/state.sh` + `lib/log.sh` using the same preamble pattern as existing `plugin-wheel/bin/*` scripts. `chmod +x`. Include FR-005, FR-006, FR-006a, FR-010, FR-013 comments.
- [X] T008 Implement control-flow steps 1–6 from contracts §5.3 in `wheel-flag-needs-input`: argument validation (step 1), state resolution (step 2), permission gate (step 3), non-interactive gate (step 4), cross-workflow guard (step 5), state write + stdout confirmation (step 6).
- [X] T009 [P] Write `plugin-wheel/tests/unit/test_wheel_user_input_cli.sh` — one assertion per exit branch in contracts §5.2 (success + 6 failure modes). State-unchanged assertion via `sha256sum` before/after for denial branches (SC-003).
- [X] T010 [P] Write `plugin-wheel/tests/unit/test_wheel_user_input_cross_workflow_guard.sh` — seeds two `.wheel/state_*.json` files, asserts second `flag-needs-input` call exits 1 with the blocking workflow's name in stderr. Covers US6.

**Phase 2 exit gate**: T007–T010 `[X]`; tests pass. Commit `feat(wheel-user-input): phase 2 — wheel-flag-needs-input CLI`.

---

## Phase 3: Stop hook integration

- [X] T011 Add silence branch to `plugin-wheel/hooks/stop.sh` per contracts §6.1: after state resolution, before the call that renders / emits step instructions, check `.steps[cursor].awaiting_user_input`. If `true`, emit exactly `{"decision": "approve"}` via `printf`/`jq -n`, log via `wheel_log`, exit 0. Include FR-007 comment. (Refined: silence is conditional on output-file absence so the advance path still runs once the agent writes output.)
- [X] T012 Augment advance-bookkeeping path (inside `engine_handle_hook` or wherever the hook advances cursor after output-file detection) to call `state_clear_awaiting_user_input "$STATE_FILE" "$just_completed_index"` after the cursor advance, before the next step's instruction rendering. Include FR-008 comment. (Added at three advance points in `dispatch_agent`: stop working→done, no-output auto-complete, post_tool_use output-write.)
- [X] T013 Locate the step-instruction renderer (grep for the current "write your output" reminder string across `plugin-wheel/lib/` + `plugin-wheel/hooks/`). Document the file + function location in a comment at the top of the patch. (Renderer lives in `lib/context.sh::context_build`; injection happens there.)
- [X] T014 Append the FR-009 instruction block (verbatim from contracts §6.3) to the rendered instruction when the step has `allow_user_input: true`. Include FR-009 comment.
- [X] T015 Write `plugin-wheel/tests/wheel-user-input-flag-happy-path/` harness fixture — one-step workflow, agent calls `wheel-flag-needs-input`, asserts silent hook fires, then agent writes output, asserts advance + auto-clear. Covers US1 scenarios 1–3. (Also added unit-level integration test `test_wheel_user_input_stop_hook.sh` for cheap local coverage of FR-007/FR-008/FR-009.)

**Phase 3 exit gate**: T011–T015 `[X]`; harness fixture passes. Commit `feat(wheel-user-input): phase 3 — stop hook silence + instruction injection`.

---

## Phase 4: Skip skill

- [ ] T016 Create `plugin-wheel/skills/wheel-skip/SKILL.md` per contracts §7 — frontmatter + short bash body implementing the five-step logic. Include FR-011 comment in the body.
- [ ] T017 Write `plugin-wheel/tests/unit/test_wheel_user_input_skip_skill.sh` — three cases per contracts §7: flag-set → sentinel written + flag cleared; no flag → friendly message + exit 0; no workflow → friendly message + exit 0. Covers US4.

**Phase 4 exit gate**: T016–T017 `[X]`; test passes. Commit `feat(wheel-user-input): phase 4 — /wheel:wheel-skip skill`.

---

## Phase 5: Status surface

- [ ] T018 Locate `/wheel:wheel-status` implementation (skill + / or `plugin-wheel/bin/wheel-status`). Document path in comment.
- [ ] T019 Add the pending-input row per contracts §8: for each state file whose current step has `awaiting_user_input: true`, render a line with workflow name, step id, reason, and elapsed time. Implement an elapsed-time formatter (`date -u +%s` math, format `Nm Ss` / `Ns`). Include FR-015 comment.
- [ ] T020 Write `plugin-wheel/tests/unit/test_wheel_user_input_status_surface.sh` — seeds a state file with `awaiting_user_input_since` set 4 minutes ago, runs status, asserts output contains the expected row with elapsed ~ `4m` (±10s per SC-006). Covers US7.

**Phase 5 exit gate**: T018–T020 `[X]`; test passes. Commit `feat(wheel-user-input): phase 5 — /wheel:wheel-status observability`.

---

## Phase 6: Remaining harness fixtures (FR-016 tail)

- [ ] T021 [P] Scaffold `plugin-wheel/tests/wheel-user-input-skip-when-not-needed/` — agent writes output directly without calling the CLI; assert no `awaiting_user_input` ever set; workflow advances on first hook fire. Covers US2 scenarios 1–2.
- [ ] T022 [P] Scaffold `plugin-wheel/tests/wheel-user-input-permission-denied/` — step without `allow_user_input`; CLI call exits 1; state file sha unchanged. Covers US3 scenario 1.
- [ ] T023 [P] Scaffold `plugin-wheel/tests/wheel-user-input-noninteractive/` — `WHEEL_NONINTERACTIVE=1`; CLI exits 1 regardless of permission. Covers US5 scenarios 1–2.

**Phase 6 exit gate**: T021–T023 `[X]`; all four harness fixtures pass under `/kiln:kiln-test`. Commit `test(wheel-user-input): phase 6 — harness fixtures for all user stories`.

---

## Phase 7: Polish + docs (implementer-owned)

- [ ] T024 Update `plugin-wheel/README.md` with a short "User input" section: describe the primitive, link to a two-paragraph usage example (`allow_user_input: true` in workflow + `wheel flag-needs-input` in agent prompt).
- [ ] T025 Run the full wheel test suite (`/wheel:wheel-test` + the new unit tests) locally; confirm no regressions. Record pass / fail summary in `specs/wheel-user-input/agent-notes/implementer.md`.
- [ ] T026 Write `specs/wheel-user-input/agent-notes/implementer.md` — friction note per pipeline convention: what was clear / unclear in the spec + contracts, what drifted vs plan, what to fix next cycle.

**Phase 7 exit gate**: T024–T026 `[X]`; `agent-notes/implementer.md` exists. Final commit `docs(wheel-user-input): readme + implementer notes`. SendMessage to team-lead: "Phase 7 complete — ready for audit-compliance (task #3)."

---

## Phase 8: Handoff (audit-compliance + audit-pr own, not implementer)

- [ ] T027 [audit-compliance] PRD audit per `/kiln:audit` — every FR traces to code + test. Failures documented in `specs/wheel-user-input/blockers.md`.
- [ ] T028 [audit-compliance] Smoke test per `smoke-tester` agent — the wheel plugin still boots, existing workflows still run, new CLI is discoverable.
- [ ] T029 [audit-pr] Create PR with `build-prd` label, title `feat(wheel): user-input primitive — allow_user_input + wheel flag-needs-input`, body summarizes FR → commit mapping.

---

## Traceability matrix (FR → task)

| FR | Task(s) | User story |
|-----|---------|-----------|
| FR-001 | T001 | US3 |
| FR-002 | T001, T002, T005 | US3 |
| FR-003 | T000, T003 | US1 |
| FR-004 | T003, T004, T006 | US1, US4 |
| FR-005 | T007 | US1 |
| FR-006 (1–6) | T008 | US1, US3, US5, US6 |
| FR-006a | T008, T009 | US3 |
| FR-007 | T011, T015 | US1 |
| FR-008 | T012, T015 | US1 |
| FR-009 | T013, T014 | US1 |
| FR-010 | T008, T010 | US6 |
| FR-011 | T016, T017 | US4 |
| FR-013 | T008, T009 | US5 |
| FR-015 | T019, T020 | US7 |
| FR-016 | T015, T021, T022, T023 + T009, T010, T017, T020 | all |

## Completion criteria (for marking task #2 done)

- All T000–T026 marked `[X]`.
- All unit tests + harness fixtures pass locally.
- `specs/wheel-user-input/agent-notes/implementer.md` exists.
- Final commit pushed to `build/wheel-user-input-20260424`.
- SendMessage to team-lead with summary + test results.
