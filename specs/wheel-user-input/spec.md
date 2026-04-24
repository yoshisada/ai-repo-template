# Feature Specification: Wheel User-Input Primitive

**Feature Branch**: `build/wheel-user-input-20260424`
**Created**: 2026-04-24
**Status**: Draft
**Source PRD**: `docs/features/2026-04-23-wheel-user-input/PRD.md`

## Summary

Give wheel workflows a way to pause mid-execution, wait for the user to answer a question, and resume — without the Stop hook re-firing "write your output" every turn and spamming the user. Two primitives:

1. **Authoring-time permission**: `allow_user_input: true` on step definitions (type: agent | loop | branch). Default false. Validated by `plugin-wheel/lib/workflow.sh`.
2. **Runtime flag**: `wheel flag-needs-input <reason>` — a bash CLI the agent calls when it decides (at runtime) it actually needs the user. Sets `awaiting_user_input: true` + `awaiting_user_input_since: <ISO-8601>` on the current step's state. The Stop hook observes this flag and emits nothing until the agent writes the step output (which clears the flag automatically).

Also includes: `/wheel:wheel-skip` skill for abandoning a stalled interactive step (writes a cancel sentinel); `WHEEL_NONINTERACTIVE=1` env var that makes `flag-needs-input` exit 1 unconditionally; `/wheel:wheel-status` surfacing of pending user-input state.

All code changes land in `plugin-wheel/` (schema validation, state helpers, new CLI bin, Stop-hook conditional, new skill). No external deps. Existing workflows are unaffected (default `allow_user_input: false`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Agent opts into pausing when needed (Priority: P1) 🎯 MVP

A workflow step has `allow_user_input: true`. The agent reads repo state, determines it can resolve 3 of 4 questions on its own, and only needs the user for the 4th. It outputs the remaining question and runs `wheel flag-needs-input "phase assignment needed"`. The Stop hook stays silent across the user's reply turn. When the user answers and the agent writes the step output, the flag auto-clears and the workflow advances.

**Why this priority**: This is the entire reason the feature exists. Without it, interactive workflows cannot be authored. Everything else in the spec is either enabling plumbing (schema, state) or edge-case handling (skip, non-interactive).

**Independent Test**: Run a test workflow with one agent step that declares `allow_user_input: true`. From inside the step, invoke `wheel flag-needs-input "need user"`. Verify (a) the command exits 0 and sets `awaiting_user_input: true` on the step, (b) the Stop hook's next firing emits no reminder block when the flag is set, (c) after the agent writes the step output file, the flag auto-clears and the workflow advances to the next step.

**Acceptance Scenarios**:

1. **Given** a step with `allow_user_input: true` and no user-input flag set, **When** the agent runs `wheel flag-needs-input "reason"`, **Then** the state file's current-step object gains `awaiting_user_input: true` and `awaiting_user_input_since: <ISO-8601-UTC>` and the command exits 0.
2. **Given** a step with `awaiting_user_input: true`, **When** the Stop hook fires, **Then** the hook emits no step instruction / reminder block (silent) and returns without decision on main-chat output.
3. **Given** `awaiting_user_input: true` and the agent writes the step output file, **When** the Stop hook's advance logic runs on the next fire, **Then** `awaiting_user_input` is cleared to `false`, `awaiting_user_input_since` is nulled, and the workflow advances to the next step normally.

---

### User Story 2 — Agent does NOT pause when it doesn't need to (Priority: P1)

Same step, same `allow_user_input: true`. This time the agent can infer everything from repo state. It writes the step output directly without calling `flag-needs-input`. No user prompt. No wait. This is the payoff of runtime-vs-authoring-time: the pause is optional.

**Why this priority**: This is the PRD's load-bearing design choice (Absolute Must #1). If the agent can't skip the pause, we might as well have kept the authoring-time `interactive: true` design that was explicitly rejected.

**Independent Test**: Run the same test workflow from US1 with an agent prompt that says "write output immediately, do NOT call flag-needs-input." Verify (a) the workflow advances on the first Stop-hook fire with no `awaiting_user_input` ever being set, (b) no silent-hook turn is observed.

**Acceptance Scenarios**:

1. **Given** a step with `allow_user_input: true`, **When** the agent writes output without calling `flag-needs-input`, **Then** `awaiting_user_input` remains `false` throughout and the workflow advances on the first normal Stop-hook fire.
2. **Given** the agent chooses not to pause, **When** the step completes, **Then** the state file records the step output exactly as a step without `allow_user_input` would — no trace of the optional primitive.

---

### User Story 3 — Unauthorized pause attempt fails cleanly (Priority: P1)

A step has `allow_user_input: false` (default). The agent misreads its prompt and tries `wheel flag-needs-input`. The command exits 1 with "step <id> does not permit user input — finish with the context you have." The agent sees the error and proceeds without pausing.

**Why this priority**: The permission gate is the only defense against rogue workflow steps pausing unexpectedly. Without it, any agent in any step could stall the engine.

**Independent Test**: Author a test workflow with a step that does NOT set `allow_user_input`. Inside the step, run `wheel flag-needs-input "reason"`. Verify (a) exit code is 1, (b) stderr contains the phrase "does not permit user input", (c) state file is unchanged — `awaiting_user_input` is not set.

**Acceptance Scenarios**:

1. **Given** a step without `allow_user_input: true`, **When** `wheel flag-needs-input <reason>` is invoked, **Then** the command exits 1, prints a clear error to stderr, and does NOT mutate the state file.
2. **Given** the validator runs on a workflow with `allow_user_input: true` on a `type: command` step, **When** `workflow_load` is called, **Then** validation fails with a clear error naming the offending step and field.

---

### User Story 4 — User abandons a stalled step (Priority: P2)

A workflow is waiting on the user, who changes their mind. They run `/wheel:wheel-skip`. The skill writes a sentinel output (`{"cancelled": true, "reason": "user-skipped"}`) to `.wheel/outputs/<step>.json` and clears `awaiting_user_input`. Workflow advance logic proceeds per existing behavior (step treated as completed with cancel sentinel; downstream steps are expected to check output shape).

**Why this priority**: Without the escape hatch, a stalled interactive step is a soft deadlock — the user must know a bash command or hand-edit state to recover. `/wheel:wheel-skip` is the documented recovery path.

**Independent Test**: From US1's setup (step with `awaiting_user_input: true` set), run `/wheel:wheel-skip`. Verify (a) `.wheel/outputs/<step-id>.json` contains `{"cancelled": true, "reason": "user-skipped"}`, (b) `awaiting_user_input` is cleared on the state file, (c) the next Stop-hook fire advances the workflow past the cancelled step.

**Acceptance Scenarios**:

1. **Given** an active workflow with `awaiting_user_input: true`, **When** the user runs `/wheel:wheel-skip`, **Then** the step's output file is written with the cancel sentinel, `awaiting_user_input` is cleared, and the workflow advances on the next hook fire.
2. **Given** no active workflow has `awaiting_user_input: true`, **When** the user runs `/wheel:wheel-skip`, **Then** the skill reports "no interactive step to skip" and exits without mutating any state.

---

### User Story 5 — Non-interactive execution (Priority: P2)

A CI run sets `WHEEL_NONINTERACTIVE=1`. Any `wheel flag-needs-input` call exits 1 unconditionally with "non-interactive mode: user input disabled." Agents detect the error and either proceed with defaults or fail fast — their choice.

**Why this priority**: CI / automation must be deterministic. A workflow pausing forever in a headless run is a reliability bug.

**Independent Test**: Set `WHEEL_NONINTERACTIVE=1` and invoke `wheel flag-needs-input "reason"` on a step that otherwise permits user input. Verify (a) exit code 1, (b) stderr contains "non-interactive", (c) state file unchanged.

**Acceptance Scenarios**:

1. **Given** `WHEEL_NONINTERACTIVE=1` is set, **When** `wheel flag-needs-input` is invoked on ANY step (even with `allow_user_input: true`), **Then** the command exits 1 with a clear error and does NOT mutate state.
2. **Given** `WHEEL_NONINTERACTIVE=0` or unset, **When** `wheel flag-needs-input` is invoked on a permitted step, **Then** it behaves per US1.

---

### User Story 6 — Cross-workflow guard (Priority: P2)

Two workflows happen to be active simultaneously (orchestrator + teammate). One is already waiting on the user. The teammate's step tries to pause too. The second `flag-needs-input` call exits 1 with "another workflow is waiting on user input: <workflow-name> / <step-id>." One interactive step active at a time, period.

**Why this priority**: The user has one chat at a time. Two workflows both asking questions means answers route ambiguously. The guard is cheap (one `ls | jq` scan) and the alternative is unworkable.

**Independent Test**: Set `awaiting_user_input: true` on one state file, then invoke `flag-needs-input` against a second state file whose current step permits user input. Verify (a) exit 1, (b) error message names the blocking workflow.

**Acceptance Scenarios**:

1. **Given** another `.wheel/state_*.json` has `awaiting_user_input: true` on its current step, **When** `flag-needs-input` is invoked, **Then** the command exits 1 with an error that names the blocking workflow + step id.
2. **Given** no other workflow is waiting on input, **When** `flag-needs-input` is invoked, **Then** the command proceeds per US1.

---

### User Story 7 — Observability via /wheel:wheel-status (Priority: P3)

An author wonders why nothing is happening. They run `/wheel:wheel-status`. If any active workflow has `awaiting_user_input: true`, the output shows the reason and elapsed time since `awaiting_user_input_since`.

**Why this priority**: Quality-of-life, not blocking. Without this, a user could inspect state files by hand; with it, the built-in diagnostic works.

**Independent Test**: Set `awaiting_user_input: true` with `awaiting_user_input_since` 4 minutes ago on a state file. Run `/wheel:wheel-status`. Verify the output includes the step id, reason, and an elapsed-time value >= 4 minutes.

**Acceptance Scenarios**:

1. **Given** an active workflow has `awaiting_user_input: true` set 4 minutes ago, **When** `/wheel:wheel-status` is invoked, **Then** the output names the workflow, step id, reason, and elapsed time (formatted `Nm Ss` or `Ns`).
2. **Given** no workflow has `awaiting_user_input: true`, **When** `/wheel:wheel-status` is invoked, **Then** the output is unchanged from today's behavior.

---

### Edge Cases

- **Step instruction injection (FR-009)**: When `allow_user_input: true`, the Stop hook's step-instruction rendering appends a short block telling the agent the primitive exists and framing pausing as last-resort. Without this nudge, agents won't discover the primitive.
- **Race between `flag-needs-input` and hook fire**: `flag-needs-input` writes state synchronously via atomic file replace (existing `state_write` pattern). The Stop hook reads state on each fire. Well-understood ordering — no race window.
- **`flag-needs-input` with no active workflow**: Exits 1 with "no active workflow." State discovery uses the same helper as other wheel CLIs.
- **Malformed state JSON**: Command exits 1 with parse-error message; no partial mutation.
- **Agent forgets to call `flag-needs-input` but asks a question anyway**: Stop hook nags per today's behavior. FR-009's injected instruction is the mitigation; anything beyond is Claude-side judgment (documented risk).
- **`/wheel:wheel-skip` when output file already exists**: Overwrites with the cancel sentinel (explicit abandon intent).
- **Stale `awaiting_user_input_since`**: No auto-timeout in v1. `/wheel:wheel-skip` is the escape hatch. `/wheel:wheel-status` shows elapsed time so the user can spot stalls.

## Requirements *(mandatory)*

### Functional Requirements

**Schema / validation**

- **FR-001**: Workflow JSON schema MUST gain an optional boolean field `allow_user_input` on step definitions. Default is `false`.
- **FR-002**: `plugin-wheel/lib/workflow.sh` MUST reject workflows that set `allow_user_input: true` on any step whose `type` is not one of `agent`, `loop`, `branch`. Rejection emits a clear error on stderr naming the step id and field, and `workflow_load` exits non-zero.

**State**

- **FR-003**: Per-step state in `.wheel/state_*.json` MUST support two new fields: `awaiting_user_input: boolean` (default false) and `awaiting_user_input_since: string|null` (ISO-8601 UTC, default null). Both live inside each element of the `.steps[]` array.
- **FR-004**: `plugin-wheel/lib/state.sh` MUST export two helpers: `state_set_awaiting_user_input <state-file> <step-index> <reason>` sets both fields atomically; `state_clear_awaiting_user_input <state-file> <step-index>` clears both atomically.

**Runtime CLI**

- **FR-005**: A new executable MUST exist at `plugin-wheel/bin/wheel-flag-needs-input` (direct-path invocation; the plugin's top-level `wheel` CLI, if/when present, SHOULD expose it as `wheel flag-needs-input <reason>`). Direct-path invocation is the canonical form for v1.
- **FR-006**: `wheel flag-needs-input <reason>` MUST implement the following control flow in order:
  1. Resolve the current active state file via the existing `resolve_state_file` helper. If none resolves, exit 1 with "no active workflow."
  2. Read the current step index (`cursor`) and its JSON definition from the resolved state file.
  3. If the current step does NOT have `allow_user_input: true`, exit 1 with "step <id> does not permit user input."
  4. If `WHEEL_NONINTERACTIVE=1` is set in the environment, exit 1 with "non-interactive mode: user input disabled."
  5. Scan all `.wheel/state_*.json` files (excluding the current one). If ANY has `awaiting_user_input: true` on its current step, exit 1 with "another workflow is waiting on user input: <workflow-name> / <step-id>."
  6. Otherwise, call `state_set_awaiting_user_input <current-state> <cursor> <reason>`, print a one-line confirmation to stdout, exit 0.
- **FR-006a**: `<reason>` argument is MANDATORY. Omitting it exits 1 with usage. Empty string is also rejected.

**Stop hook**

- **FR-007**: `plugin-wheel/hooks/stop.sh` MUST, at the start of its "what to tell main chat" rendering logic (after state resolution, before step-instruction emission), branch on the current step's `awaiting_user_input`:
  - If `true` → emit NO reminder / step-instruction block (silent: `{"decision": "approve"}` with no `stopReason` or instruction). Return normally.
  - If `false` → existing behavior (unchanged).
- **FR-008**: The Stop hook's existing advance-bookkeeping path (which detects a step's output file and transitions the workflow forward) MUST additionally clear `awaiting_user_input` + `awaiting_user_input_since` on the just-completed step. This happens automatically on the same fire that advances the workflow — no separate "resume" command.
- **FR-009**: When the Stop hook renders a step instruction for a step with `allow_user_input: true`, it MUST append the following block verbatim to the instruction text (below the step's normal instruction body):
  > ---
  > **This step permits user input.** If you cannot resolve this step from repo state alone, you MAY output your question to the user and then run `wheel flag-needs-input "<short reason>"` (or the absolute-path form `plugin-wheel/bin/wheel-flag-needs-input "<short reason>"`) before ending your turn. The Stop hook will stay silent until you write the step output. If the question is unnecessary, skip it and write the output directly — pausing is a last resort.

**Cross-workflow guard**

- **FR-010**: Only one workflow across all `.wheel/state_*.json` files MAY have `awaiting_user_input: true` on its current step at a time. Enforced by `flag-needs-input` step 5 (FR-006).

**Abandonment**

- **FR-011**: A new skill `/wheel:wheel-skip` MUST exist at `plugin-wheel/skills/wheel-skip/SKILL.md`. Behavior:
  1. Resolve the active state file. If none, print "no interactive step to skip" and exit 0.
  2. If the current step does NOT have `awaiting_user_input: true`, print "no interactive step to skip" and exit 0.
  3. Write `.wheel/outputs/<step-id>.json` containing `{"cancelled": true, "reason": "user-skipped"}`.
  4. Call `state_clear_awaiting_user_input <state-file> <cursor>`.
  5. Print a one-line confirmation naming the skipped step id.
- **FR-012**: `on_cancel` step-level hop target is OUT OF SCOPE for v1. Cancellation writes the sentinel and lets existing advance logic proceed.

**Non-interactive mode**

- **FR-013**: `WHEEL_NONINTERACTIVE=1` in the environment disables user-input pausing globally. Enforced by `flag-needs-input` step 4 (FR-006).
- **FR-014**: Step-level `default_on_noninteractive` field is OUT OF SCOPE for v1.

**Observability**

- **FR-015**: `/wheel:wheel-status` MUST, when any active workflow has a step with `awaiting_user_input: true`, include in its output: the workflow name, step id, reason, and elapsed time since `awaiting_user_input_since` (formatted as `Nm Ss` or `Ns`). Output format: additive; existing rows are unchanged.

**Test coverage**

- **FR-016**: Every user story (US1..US7) MUST have a `/kiln:kiln-test` (`plugin-skill` substrate) test fixture under `plugin-wheel/tests/wheel-user-input-<slug>/` that exercises the acceptance scenario end-to-end against the real wheel bin + hooks. v1 MUST ship at minimum: `wheel-user-input-flag-happy-path` (US1), `wheel-user-input-skip-when-not-needed` (US2), `wheel-user-input-permission-denied` (US3), `wheel-user-input-noninteractive` (US5). US4, US6, US7 MAY ship as bash-level unit tests under `plugin-wheel/tests/unit/` instead if the harness fixture cost is prohibitive.

### Key Entities

- **Step state entry** (under `.wheel/state_*.json → .steps[i]`) — gains two fields: `awaiting_user_input: boolean` and `awaiting_user_input_since: string|null` (ISO-8601 UTC).
- **Cancel sentinel output** — `{"cancelled": true, "reason": "user-skipped"}` written to `.wheel/outputs/<step-id>.json` by `/wheel:wheel-skip`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A workflow step declaring `allow_user_input: true` and invoking `wheel flag-needs-input` completes a full pause-and-resume cycle with ZERO Stop-hook reminder emissions between the pause and the output write (measured by grepping `.wheel/logs/stop_*.log` across the affected turns).
- **SC-002**: A workflow step declaring `allow_user_input: true` that chooses NOT to pause advances on the first normal Stop-hook fire — no silent-hook turns observed, no `awaiting_user_input` ever set (proves the runtime decision is real).
- **SC-003**: Running `wheel flag-needs-input` on a step without `allow_user_input: true` exits 1 with a clear error, and the state file is byte-for-byte unchanged (verified via `sha256sum` before + after).
- **SC-004**: With `WHEEL_NONINTERACTIVE=1`, every `flag-needs-input` invocation exits 1, independent of step permission and cross-workflow state (verified across ≥3 test fixtures covering each branch).
- **SC-005**: The cross-workflow guard fires at least once in the test matrix — no false positives on single-workflow test runs; clear error when two workflows race.
- **SC-006**: `/wheel:wheel-status` shows pending user-input reason + elapsed time on a state file artificially pre-seeded to `awaiting_user_input_since` 4 minutes ago (elapsed time is within ±10 seconds of real wall-clock delta).

## Assumptions

- Main-chat Claude reliably uses the primitive when the injected instruction (FR-009) tells it to. This is consistent with how Claude follows other inline workflow instructions today.
- `.wheel/state_*.json` is the single source of truth for step state. No competing store.
- The existing `resolve_state_file` helper (in `plugin-wheel/lib/guard.sh`) correctly identifies the active state file from either hook input or CWD context. `flag-needs-input` reuses it.
- The Stop hook already reads state on every fire; extending its decision logic with one conditional branch adds negligible overhead.
- Step instruction injection (FR-009) can be implemented as a string-append in the existing step-instruction rendering path without refactoring the renderer. If it can't, the plan phase will flag it as a blocker.
- The `wheel` top-level CLI (a single entrypoint) is NOT required for v1 — direct-path invocation of `plugin-wheel/bin/wheel-flag-needs-input` is canonical. A follow-up can add `wheel <subcommand>` dispatch once more subcommands exist.

## Out of Scope (v1)

- `on_cancel: <step-id>` hop routing (FR-012).
- Step-level `default_on_noninteractive` value (FR-014).
- Automatic timeout / auto-cancel of stalled interactive steps.
- Engine-level multi-question interview templates.
- Parsing user replies into step outputs automatically.
- UI prompts / forms / rich input.
- Refactoring `/kiln:kiln-roadmap` to use this primitive (separate PRD).
