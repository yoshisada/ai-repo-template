# Implementation Plan: Wheel User-Input Primitive

**Branch**: `build/wheel-user-input-20260424`
**Spec**: `specs/wheel-user-input/spec.md`
**Contracts**: `specs/wheel-user-input/contracts/interfaces.md`
**Source PRD**: `docs/features/2026-04-23-wheel-user-input/PRD.md`

## Technical Approach

The feature is almost entirely additive to `plugin-wheel/`. Five surfaces change (schema, state, CLI, hook, new skill), all independently small. A single implementer owns the whole feature. No researcher needed (no external starter code). No QA engineer (no UI). Audit + smoke + PR handled by the existing pipeline roles.

The load-bearing design decision — **pause decision is runtime, not authoring time** — is already captured in the PRD and spec. The plan just routes that into concrete file edits:

- `allow_user_input: true` is a workflow-JSON *permission*, validated once at load.
- `awaiting_user_input: true` is a *state fact*, set at runtime by the agent via `flag-needs-input`.
- The Stop hook is the single enforcement point: one conditional branch up front (silence if the flag is set) and one existing path augmented (auto-clear the flag when the step output appears).
- No cross-cutting refactor; the changes fit inside existing files and their existing logic.

### Deviation decisions from contracts/interfaces.md §8

**Decision (made here)**: Store the reason in state. Add an optional `awaiting_user_input_reason: string|null` field to `.steps[i]`. `state_set_awaiting_user_input` takes the reason as its third param and writes it; `state_clear_awaiting_user_input` also nulls it. `/wheel:wheel-status` renders it directly without a degraded `reason=?` fallback.

Rationale: observability is the primary v1 consumer. A degraded status output for every stall is a lasting UX tax paid to save one optional JSON field. Update contracts/interfaces.md §3.1 as part of T001 if not already updated.

### Tech stack (inherited — no additions)

- Bash 5.x (hook scripts, CLI bin, skill body shell blocks)
- `jq` (state JSON mutation)
- Existing wheel engine libs: `state.sh`, `workflow.sh`, `guard.sh`, `log.sh`, `dispatch.sh`, `engine.sh`
- Test harness: `/kiln:kiln-test` (`plugin-skill` substrate) for fixtures; direct bash for unit tests

## Phases

### Phase 0 — Setup (single step)

- Confirm `specs/wheel-user-input/contracts/interfaces.md` §3.1 records the `awaiting_user_input_reason` decision above. If not, patch contracts first (per Article VII: contracts lead).

### Phase 1 — State helpers + validator (foundational)

Goal: everything higher layers depend on is in place.

1. Add validator `workflow_validate_allow_user_input` to `plugin-wheel/lib/workflow.sh` and wire into `workflow_load`. (FR-001, FR-002)
2. Add `state_set_awaiting_user_input` and `state_clear_awaiting_user_input` to `plugin-wheel/lib/state.sh`. (FR-003, FR-004)
3. Unit-test both helpers via bash fixtures under `plugin-wheel/tests/unit/`. Atomic-write correctness, idempotency, schema shape.

**Exit criterion**: helpers callable from a test script; validator rejects a known-bad workflow fixture.

### Phase 2 — CLI: `wheel-flag-needs-input`

Goal: agents can pause at runtime.

1. Implement `plugin-wheel/bin/wheel-flag-needs-input` per contracts §5 (shebang, chmod +x, six-step control flow, exit codes, messages).
2. Reuse `resolve_state_file` (guard.sh) — do NOT reimplement state resolution.
3. Cross-workflow guard: scan `.wheel/state_*.json` files via a single `jq` over `find` or `ls`. Exclude the current state file by inode or path.
4. Unit test for each exit branch (no active workflow, missing permission, non-interactive, guard hit, success) — minimum 5 test cases.

**Exit criterion**: `bin/wheel-flag-needs-input "reason"` from a seeded fixture sets the flag; all denial branches exit 1 with the correct message and DO NOT mutate state.

### Phase 3 — Stop hook integration

Goal: silence while flag is set; auto-clear on advance; inject the "you may pause" note.

1. Add the silence branch at the top of the "handle" logic in `plugin-wheel/hooks/stop.sh` (after state resolution, before instruction rendering). Emit exactly `{"decision": "approve"}`. (FR-007)
2. Augment the existing advance path to call `state_clear_awaiting_user_input` on the just-completed step. (FR-008)
3. Augment the step-instruction renderer to append the injected block when `allow_user_input: true`. Locate the renderer by search; if it lives in `engine.sh`/`dispatch.sh`, edit there. (FR-009)
4. Integration test via `/kiln:kiln-test` harness fixture `wheel-user-input-flag-happy-path`: full cycle — run workflow, inside agent invoke the CLI, observe silent hook, write output, observe advance + auto-clear.

**Exit criterion**: `grep -c 'additionalContext\|systemMessage\|stopReason' .wheel/logs/stop_*.log` across a silent-phase turn returns 0.

### Phase 4 — New skill: `/wheel:wheel-skip`

Goal: recovery path for stalled interactive steps.

1. Create `plugin-wheel/skills/wheel-skip/SKILL.md` per contracts §7.
2. Body is a short bash block: resolve, guard, write sentinel output, clear flag, print confirmation.
3. Unit / fixture test: both active-flag and no-active-flag paths.

**Exit criterion**: `wheel-skip` resolves the three documented branches (flag set → sentinel + clear; no flag → friendly message; no workflow → friendly message).

### Phase 5 — `/wheel:wheel-status` augmentation

Goal: visible pending-input state.

1. Locate the status skill (`plugin-wheel/skills/wheel-status/SKILL.md` and / or `plugin-wheel/bin/wheel-status`).
2. Add the append row per contracts §8, using the now-stored `awaiting_user_input_reason`.
3. Elapsed-time formatting helper (bash + `date` math) — small self-contained function.
4. Test: seed a state file with `awaiting_user_input_since` 4 minutes ago; assert output contains `elapsed=4m` (tolerant of ±10s drift per SC-006).

**Exit criterion**: status output shows one additional row per pending-input workflow; existing rows unchanged.

### Phase 6 — Harness fixtures for FR-016

1. Scaffold the four required `/kiln:kiln-test` fixtures under `plugin-wheel/tests/wheel-user-input-*` (contracts §10 table, first four rows).
2. Author bash-level unit tests for the remaining three user stories (US4, US6, US7) under `plugin-wheel/tests/unit/` — cheaper than the harness for pure-bash assertions.
3. Wire all tests into the existing wheel test runner (`/wheel:wheel-test` picks up `workflows/tests/*.json`; for new-style fixtures and unit tests, follow the pattern in `plugin-wheel/tests/` already present).

**Exit criterion**: all seven tests pass on a clean branch.

### Phase 7 — PRD audit + smoke + PR (handed off)

Handed to `audit-compliance` and `audit-pr` via the pipeline task graph — not this implementer's work. Implementer SendMessages the team lead on Phase 6 completion.

## File-list

New files:
- `plugin-wheel/bin/wheel-flag-needs-input` — CLI (exec, bash)
- `plugin-wheel/skills/wheel-skip/SKILL.md` — skill definition + body
- `plugin-wheel/tests/wheel-user-input-flag-happy-path/` — harness fixture
- `plugin-wheel/tests/wheel-user-input-skip-when-not-needed/` — harness fixture
- `plugin-wheel/tests/wheel-user-input-permission-denied/` — harness fixture
- `plugin-wheel/tests/wheel-user-input-noninteractive/` — harness fixture
- `plugin-wheel/tests/unit/test_wheel_user_input_state_helpers.sh`
- `plugin-wheel/tests/unit/test_wheel_user_input_validator.sh`
- `plugin-wheel/tests/unit/test_wheel_user_input_cli.sh`
- `plugin-wheel/tests/unit/test_wheel_user_input_cross_workflow_guard.sh`
- `plugin-wheel/tests/unit/test_wheel_user_input_skip_skill.sh`
- `plugin-wheel/tests/unit/test_wheel_user_input_status_surface.sh`

Modified files:
- `plugin-wheel/lib/state.sh` — add two helpers (FR-004)
- `plugin-wheel/lib/workflow.sh` — add validator; wire into `workflow_load` (FR-002)
- `plugin-wheel/hooks/stop.sh` — silence branch + auto-clear hook + (possibly) instruction-injection append (FR-007, FR-008, FR-009)
- `plugin-wheel/lib/engine.sh` or `plugin-wheel/lib/dispatch.sh` — step-instruction renderer, if the append lives there (FR-009) — TBD in Phase 3 Step 3
- `plugin-wheel/skills/wheel-status/SKILL.md` + any helper bin — observability row (FR-015)
- `plugin-wheel/README.md` — brief section describing the primitive (post-implementation, doc-only)
- `specs/wheel-user-input/contracts/interfaces.md` — update §3.1 with `awaiting_user_input_reason` per plan deviation (if not already done)

## Risks + mitigations (plan-level)

- **Step-instruction renderer location uncertainty (FR-009)** — `stop.sh` delegates to `engine_handle_hook` in `engine.sh`; the actual instruction rendering may live in a helper. Mitigation: Phase 3 Step 3 begins with a `grep`-to-locate pass before editing. If rendering is too deeply coupled to allow a clean append, the implementer files a blocker rather than hacking it in.
- **Cross-workflow guard false positives** — a stale state file with a hung `awaiting_user_input` could permanently block new pauses. Mitigation: `/wheel:wheel-skip` is the recovery path; documented in the skill body. Future enhancement could add a staleness threshold; out of scope v1.
- **Log helper dependency ordering** — `wheel_log` is sourced at hook top; the CLI must source `lib/log.sh` before using the helper. Mitigation: CLI starts with the same source-preamble pattern as existing `plugin-wheel/bin/*` scripts.
- **Test fixture flakiness** — the `plugin-skill` substrate spawns real `claude` subprocesses. Slow or flaky. Mitigation: keep harness fixtures minimal (1 step), push the bulk of assertion coverage into bash unit tests.

## Implementation order (critical path)

T001–T003 (Phase 1) MUST land before any other work. Everything else can roughly parallel-track within the single implementer's sequence, but the recommended order is Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6. See `tasks.md` for the full task graph.

## Success gates (same as spec SC-001..SC-006, repeated for the implementer)

- SC-001: zero Stop-hook reminders across a pause+resume cycle.
- SC-002: no `awaiting_user_input` ever set when agent skips the pause.
- SC-003: permission denial is a no-op on state (sha unchanged).
- SC-004: `WHEEL_NONINTERACTIVE=1` always exits 1.
- SC-005: cross-workflow guard fires cleanly in tests, no false positives.
- SC-006: elapsed time accurate to ±10s in observability output.

## Coverage target

Per Constitution Article II: >=80% line+branch coverage on new/changed code. For bash, measured by counting covered branches in unit tests against the helper / CLI / skill bodies. The implementer authors unit tests covering every exit branch in §5.2 plus both branches of the silence conditional (FR-007) and both paths of the skip skill (FR-011).
