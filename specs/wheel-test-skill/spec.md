# Feature Specification: Wheel Test Skill

**Feature Branch**: `build/wheel-test-skill-20260410`
**Created**: 2026-04-10
**Status**: Draft
**Input**: PRD at `docs/features/2026-04-10-wheel-test-skill/PRD.md`

## User Scenarios & Testing

### User Story 1 - Smoke test after a wheel-engine change (Priority: P1)

A wheel engine developer has just modified `plugin-wheel/lib/dispatch.sh` and wants to confirm nothing broke before committing. They invoke `/wheel-test` in their Claude Code session and wait for a single pass/fail verdict covering every workflow under `workflows/tests/`.

**Why this priority**: Without this skill, validating an engine change means hand-running 12 workflows, remembering phase ordering, and eyeballing state files for orphans. This is the central value driver of the feature.

**Independent Test**: From a clean working tree with all 12 test workflows present, run `/wheel-test`. Verify a verdict is reported, a markdown report is written, and every workflow archived to `.wheel/history/success/` or `.wheel/history/failure/` as appropriate.

**Acceptance Scenarios**:

1. **Given** `workflows/tests/` contains all current workflows and `.wheel/state_*.json` is empty, **When** the developer invokes `/wheel-test`, **Then** the skill runs every workflow, produces a pass/fail verdict, and writes a report to `.wheel/logs/test-run-<timestamp>.md`.
2. **Given** a workflow fails (e.g., `team-static` crashes in phase 4), **When** the run completes, **Then** the report marks that workflow as FAIL, the overall verdict is FAIL, and the reproduction command for that single workflow is listed in the report.
3. **Given** every workflow runs cleanly, **When** the skill finishes, **Then** the overall verdict is PASS and `.wheel/state_*.json` contains zero files.

---

### User Story 2 - Diagnose a regression (Priority: P2)

A developer sees `/wheel-test` report a failure. They open the report and immediately see which phase failed, whether orphan state files were left behind, and whether any hook errors fired during the run — so they can jump straight to the root cause without re-running anything.

**Why this priority**: Diagnosis speed is the difference between "5 minute debug loop" and "hour-long investigation". The report must explain the failure, not just flag it.

**Independent Test**: Intentionally break one workflow (e.g., rename a command in `composition-mega.json`), run `/wheel-test`, and verify the report identifies the broken workflow, its phase, any orphans, and any hook errors.

**Acceptance Scenarios**:

1. **Given** a workflow failure, **When** the developer opens the report, **Then** the per-workflow table shows the workflow's phase, expected outcome, actual status, duration, archive path, and a notes column explaining the failure.
2. **Given** orphan state files exist after the run, **When** the developer opens the report, **Then** the orphans section lists every `.wheel/state_*.json` file by name.
3. **Given** `.wheel/logs/wheel.log` contains ERROR, FAIL, or stalled entries during the run window, **When** the developer opens the report, **Then** the hook errors section quotes the matching lines.

---

### User Story 3 - Audit trail across debugging sessions (Priority: P3)

A developer running a multi-day investigation wants to compare test results across runs. Each `/wheel-test` invocation writes a timestamped report they can diff.

**Why this priority**: Audit trail is valuable but secondary — the primary loop is "run, read, fix". Historical diffing is an enabler, not the core win.

**Independent Test**: Run `/wheel-test` twice with a fix in between, open both reports from `.wheel/logs/`, and confirm they are independent files with distinct timestamps.

**Acceptance Scenarios**:

1. **Given** the skill has been run once, **When** the developer runs it again, **Then** a new report file is written without overwriting the previous one.
2. **Given** a report exists, **When** the developer examines it, **Then** the file includes a run timestamp, total duration, and the exact activation commands used, so the run is reproducible from the report alone.

---

### Edge Cases

- **Empty test directory**: If `workflows/tests/` contains no `.json` files, the skill refuses to run and prints a clear error (FR-014).
- **Pre-existing state files**: If `.wheel/state_*.json` is non-empty before the run, the skill refuses to proceed and tells the user to archive the orphans first (FR-007).
- **Workflow hangs**: If a workflow does not archive within its phase timeout (60s for phases 1-3, 120s for phase 4), the skill marks it as a timeout and moves on to the next workflow (FR-015).
- **Expected-failure workflows**: Workflows whose names match `*-fail*` are expected to archive to `history/failure/`. Archiving to `history/success/` is treated as a regression (FR-005).
- **Stopped-archive outcome**: If a workflow archives to `.wheel/history/stopped/` instead of success or failure, it is treated as a failure with a "stopped unexpectedly" note (resolution to PRD open question Q3).
- **Phase 1 timing race**: Back-to-back activations of Phase 1 workflows must tolerate same-second starts. The hybrid archive filename format (workflow-timestamp-stateid) prevents collisions.
- **Classification surprise**: A workflow named `team-foo` that contains zero team steps MUST be classified into Phase 1/2/3 based on its actual step types, not the filename (FR-002, Absolute Must #3).

## Requirements

### Functional Requirements

- **FR-001**: The skill MUST discover all `.json` files under `workflows/tests/` at invocation time. Adding a new workflow to that directory MUST cause the next `/wheel-test` run to pick it up automatically with no configuration change.
- **FR-002**: The skill MUST classify every discovered workflow into exactly one of four phases based on the set of step types present in its JSON:
  - **Phase 1 (parallelizable, command-only)** — all steps are `command`, `branch`, or `loop`; no `agent`, `teammate`, `team-*`, or `workflow` steps.
  - **Phase 2 (serial, agent-step)** — contains at least one `agent` step but no `team-*`, `teammate`, or `workflow` steps.
  - **Phase 3 (serial, composition)** — contains at least one `workflow` (nested child) step but no `team-*` or `teammate` steps.
  - **Phase 4 (serial, team)** — contains any `team-*` or `teammate` step.
  Classification MUST be derived from the workflow JSON, not from filenames.
- **FR-003**: The skill MUST activate all Phase 1 workflows back-to-back (each activation a separate Bash tool invocation) without waiting between activations, then wait for all of them to archive before moving to Phase 2. "Parallel" in this context means activations are not gated on each other's completion, not that sub-agents are spawned.
- **FR-004**: The skill MUST run Phase 2, Phase 3, and Phase 4 workflows one at a time: activate one workflow, wait for its archive to appear in `.wheel/history/success/` or `.wheel/history/failure/`, then activate the next.
- **FR-005**: The skill MUST treat any workflow whose filename matches the pattern `*-fail*` as expected-failure: archiving to `history/failure/` counts as a pass, archiving to `history/success/` counts as a fail. All other workflows are expected-success.
- **FR-006**: For Phase 4 workflows, the skill MUST instruct the invoker to follow the wheel stop-hook flow exactly: wait for a TeamCreate instruction from the hook, call TeamCreate, wait for spawn instructions, spawn teammates via the Agent tool with `run_in_background: true`, wait for teammates to finish their sub-workflows and report results, send shutdown_requests, wait for teammate_terminated notifications, then call TeamDelete. The skill MUST explicitly document that blind-spawning before the stop-hook instructions arrive is forbidden.
- **FR-007**: Before running any workflow, the skill MUST verify that `.wheel/state_*.json` contains zero files. If any state files exist, the skill MUST list them and refuse to proceed.
- **FR-008**: After each phase, the skill MUST check for lingering `.wheel/state_*.json` files. Any that do not correspond to a workflow currently in-flight MUST be reported as orphans. Orphans count as a pipeline failure even if the workflow that produced them archived successfully.
- **FR-009**: At the start of the run the skill MUST record the current line count of `.wheel/logs/wheel.log`. After the run, it MUST scan the new lines for `ERROR|FAIL|stalled` patterns and include any matches in the report.
- **FR-010**: For each workflow that archives, the skill MUST confirm the archive file exists under `.wheel/history/success/` or `.wheel/history/failure/` with the hybrid filename format `{workflow}-{timestamp}-{state_id}.json`. Missing archives indicate a `handle_terminal_step` failure and count as a run failure.
- **FR-011**: The report MUST be a markdown document containing:
  - Header with run timestamp (UTC), total duration, overall verdict.
  - Summary table: `N passed / M failed / K orphaned / L hook errors`.
  - Per-workflow table with columns `Workflow | Phase | Expected | Status | Duration | Archive | Notes`.
  - Orphan state file section (present only if orphans exist).
  - Hook error excerpts section (present only if matches exist).
  - Reproduction commands section listing the exact activation commands used.
- **FR-012**: The report MUST be persisted to `.wheel/logs/test-run-<UTC-timestamp>.md` AND echoed to stdout. The file path MUST be printed at the end of the run.
- **FR-013**: The skill's final line of output MUST report an overall verdict: `PASS` when every workflow matched its expected outcome and there are zero orphans and zero hook errors, otherwise `FAIL` with a count of each issue type.
- **FR-014**: If `workflows/tests/` contains zero `.json` files, the skill MUST print a clear error and exit without activating anything.
- **FR-015**: The skill MUST enforce a per-workflow timeout: 60 seconds for Phase 1/2/3 workflows and 120 seconds for Phase 4 workflows. A timed-out workflow is marked as such in the report and the run continues with the next workflow. The full suite SHOULD complete within 5 minutes on a developer machine for the current 12-workflow suite.
- **FR-016**: The skill MUST NOT manually write state files, advance cursors, set step statuses, or otherwise bypass the hook system. All workflow progression MUST happen through `plugin-wheel/bin/activate.sh` and the existing hook contracts.
- **FR-017**: The skill MUST leave `.wheel/state_*.json` empty after a successful run. If the skill itself creates orphans, the run is a failure.
- **FR-018**: The skill MUST treat a workflow that archives to `.wheel/history/stopped/` as a failure with a "stopped unexpectedly" note in the report.

### Key Entities

- **Test workflow**: A JSON file under `workflows/tests/` describing a wheel workflow. Key attributes: filename, list of step types, declared expected outcome (derived from filename pattern).
- **Phase**: One of 1, 2, 3, 4. Drives ordering and parallel/serial execution semantics. Derived from the set of step types in a workflow.
- **Run result**: Per workflow: status (pass/fail/timeout/orphaned), phase, duration, archive path, notes. Aggregated into a verdict and a summary count.
- **Report**: A markdown document persisted to `.wheel/logs/test-run-<timestamp>.md` with header, summary, per-workflow table, orphans, hook errors, reproduction commands.
- **Orphan state file**: Any `.wheel/state_*.json` file remaining after a phase completes whose state id does not match a workflow currently in-flight.
- **Hook error line**: Any line in `.wheel/logs/wheel.log` added during the run window that matches `ERROR|FAIL|stalled`.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A full `/wheel-test` run over the current 12-workflow suite completes in under 5 minutes on a developer machine.
- **SC-002**: 12 of 12 current workflows produce a classification, an activation, and a report row in a single invocation (no workflows silently skipped).
- **SC-003**: When a known regression is introduced (e.g., the stale `agent_map_*` lock bug), the skill flags the failure via either an orphan report, a timeout, or a team-workflow failure on the first run. Target: regressions caught within one invocation.
- **SC-004**: After a passing run, `.wheel/state_*.json` contains zero files (measured by `ls .wheel/state_*.json 2>/dev/null | wc -l`).
- **SC-005**: The report file is written to `.wheel/logs/` on every invocation (pass or fail) and contains all seven mandated sections from FR-011 (header, summary, per-workflow table, orphans, hook errors, reproduction commands).
- **SC-006**: A developer can reproduce any single failed workflow by copy-pasting a command from the report's reproduction section — verified by selecting one failed run and re-running the quoted command successfully.

## Assumptions

- `workflows/tests/` is and will remain the canonical home for wheel test workflows.
- `plugin-wheel/bin/activate.sh` is idempotent with respect to multiple back-to-back invocations within the same session and the same wall-clock second.
- The wheel post-tool-use and stop hooks handle multiple concurrent active state files correctly; Phase 1 parallel activation is a deliberate exercise of that path.
- `.wheel/.locks/` is either unused or self-cleaning after the lock elimination shipped in commit `3283c10`. Only `workflow-dispatch-*` locks remain and those clean up with their state files.
- `jq` is available on the developer machine (it is already a wheel engine dependency).
- The hybrid archive filename format `{workflow}-{timestamp}-{state_id}.json` from commit `69d2dff` is stable and can be parsed by the skill.
- `.wheel/logs/` is gitignored (verified in implementation — added to `.gitignore` if missing).
- The skill runs in the current working directory; it does not isolate runs in a worktree (non-goal).
- The current skill invoker is either the developer or an agent running on the developer's behalf and is capable of following multi-turn stop-hook instructions for Phase 4 workflows.
- Phase 1 workflows that finish early still wait for stragglers before Phase 2 begins (resolution to PRD open question Q2 — simpler reasoning, negligible cost).
- The skill refuses to auto-archive pre-existing state files; the user must clean them up manually (resolution to PRD open question Q4 — avoids masking real problems).
- No `--verbose` / `--quiet` mode in the MVP (resolution to PRD open question Q1).
