# Feature Specification: Pipeline Reliability & Health

**Feature Branch**: `build/pipeline-reliability-20260401`  
**Created**: 2026-04-01  
**Status**: Draft  
**Input**: User description: "Pipeline reliability fixes: hook gate scoping to current feature, Gate 4 chicken-and-egg fix, allowlist expansion, contracts gate, stall detection, phase dependency enforcement, STOP AND VALIDATE clarification, Docker rebuild step between impl and QA, QA container freshness pre-flight, qa-checkpoint container verification"

## User Scenarios & Testing

### User Story 1 - Hook Gates Scope to Current Feature (Priority: P1)

A kiln user starts a new feature while prior features already have spec artifacts in the `specs/` directory. When they try to edit source files before completing the spec workflow for the current feature, the hook gates should block them — even though prior specs exist.

**Why this priority**: This is the most critical fix because it undermines kiln's core enforcement model. Silent gate bypass means the spec-first workflow is not actually enforced.

**Independent Test**: Can be tested by creating a project with two feature spec directories, switching to a branch for a new feature that has no spec, and verifying that edits to source files are blocked.

**Acceptance Scenarios**:

1. **Given** a project with `specs/old-feature/spec.md` and branch `build/new-feature-20260401`, **When** the user edits a source file, **Then** the hook blocks the edit because `specs/new-feature/spec.md` does not exist.
2. **Given** a project with `specs/new-feature/spec.md` matching the current branch, **When** the user edits a source file and all gates pass for that feature, **Then** the hook allows the edit.
3. **Given** a branch name that does not follow the `build/<name>-<date>` pattern, **When** the hook runs, **Then** it falls back to a `.kiln/current-feature` marker file to determine the current feature.

---

### User Story 2 - Gate 4 Works During Implementation (Priority: P1)

An implementer agent runs `/implement` and needs to write code before marking the first task as complete. Gate 4 currently requires at least one `[X]` mark, creating a chicken-and-egg deadlock where the agent cannot write the code needed to complete a task.

**Why this priority**: This deadlock forces workarounds that undermine gate enforcement, defeating the purpose of Gate 4.

**Independent Test**: Can be tested by running `/implement` on a feature with all spec artifacts present but no tasks marked complete, and verifying that the first code write is allowed.

**Acceptance Scenarios**:

1. **Given** `/implement` is active (lock file exists), **When** the implementer writes to a source file with zero tasks marked `[X]`, **Then** Gate 4 allows the write.
2. **Given** `/implement` is NOT active (no lock file), **When** a user tries to write to a source file with zero tasks marked `[X]`, **Then** Gate 4 blocks the write.
3. **Given** `/implement` finishes (success or failure), **When** the lock file is checked, **Then** it has been cleaned up and does not persist.

---

### User Story 3 - Expanded Hook Allowlist (Priority: P1)

A kiln user with a project that uses `cli/`, `templates/`, or `modules/` directories (instead of or in addition to `src/`) finds that their edits are blocked by the hook system. The allowlist should cover common project directories beyond the current narrow set.

**Why this priority**: The current allowlist silently blocks legitimate project structures, causing user frustration and distrust of the hook system.

**Independent Test**: Can be tested by editing files in `cli/`, `templates/`, and `modules/` directories and verifying the hook correctly applies gate checks to these directories (rather than silently allowing or blocking them).

**Acceptance Scenarios**:

1. **Given** a project with `cli/app.js`, **When** the user edits that file without spec artifacts, **Then** the hook blocks the edit (same enforcement as `src/`).
2. **Given** a project with `templates/page.html`, **When** the user edits that file with all spec gates satisfied, **Then** the hook allows the edit.
3. **Given** edits to `docs/`, `specs/`, `scripts/`, `tests/`, or config files, **When** the hook runs, **Then** these are always allowed regardless of gate status.

---

### User Story 4 - Contracts Gate Enforcement (Priority: P2)

A kiln user tries to start implementation before creating interface contracts. The hook system should enforce that `contracts/interfaces.md` exists before allowing source file writes.

**Why this priority**: Interface contracts are a constitutional requirement but not currently enforced by hooks, creating an enforcement gap.

**Independent Test**: Can be tested by creating spec, plan, and tasks artifacts but omitting `contracts/interfaces.md`, then verifying that source file edits are blocked.

**Acceptance Scenarios**:

1. **Given** `specs/<feature>/spec.md`, `plan.md`, and `tasks.md` exist but `contracts/interfaces.md` does not, **When** the user edits a source file, **Then** the hook blocks with a message about missing contracts.
2. **Given** all artifacts including `contracts/interfaces.md` exist, **When** the user edits a source file, **Then** the hook allows the edit.

---

### User Story 5 - Pipeline Stall Detection (Priority: P2)

A pipeline operator runs `/build-prd` and one of the agents stalls (no commits, no task updates, no messages for an extended period). The orchestrator should detect this and escalate.

**Why this priority**: A stalled agent can block the entire pipeline indefinitely with no feedback to the operator.

**Independent Test**: Can be tested by simulating a stalled agent (no activity for the timeout period) and verifying the orchestrator sends a check-in message.

**Acceptance Scenarios**:

1. **Given** an agent task stays `in_progress` with no activity for 10 minutes, **When** the stall detector runs, **Then** the team lead sends a check-in message to the agent.
2. **Given** an agent responds to the check-in, **When** activity resumes, **Then** the stall timer resets.
3. **Given** the stall timeout is configured as a different value in the skill prompt, **When** the detector runs, **Then** it uses the configured value instead of the 10-minute default.

---

### User Story 6 - Phase Dependency Enforcement (Priority: P2)

A pipeline operator runs `/build-prd` with multi-phase tasks. Phase 2 agents should not receive their prompts until all Phase 1 tasks are marked complete.

**Why this priority**: Without enforcement, agents can race ahead and build on incomplete foundations, causing cascading failures.

**Independent Test**: Can be tested by creating a tasks.md with two phases and verifying that the orchestrator dispatches Phase 2 agents only after Phase 1 completion.

**Acceptance Scenarios**:

1. **Given** tasks.md defines Phase 1 and Phase 2, **When** Phase 1 has incomplete tasks, **Then** Phase 2 agents are not dispatched.
2. **Given** all Phase 1 tasks are marked `[X]`, **When** the orchestrator checks dependencies, **Then** Phase 2 agents are dispatched.

---

### User Story 7 - STOP AND VALIDATE Clarification (Priority: P2)

An implementer agent encounters "STOP and VALIDATE" in the implement skill prompt and interprets it as waiting for external QA feedback, causing the agent to stall.

**Why this priority**: Ambiguous prompts cause agents to self-block, wasting pipeline time.

**Independent Test**: Can be tested by reviewing the implement skill prompt for unambiguous self-validation language and verifying agents do not stall at validation checkpoints.

**Acceptance Scenarios**:

1. **Given** the implement skill prompt contains validation instructions, **When** an implementer reads them, **Then** the instructions clearly state to run tests locally and self-validate (not wait for external feedback).
2. **Given** the prompt distinguishes self-validation from QA-gated checkpoints, **When** an implementer reaches a checkpoint, **Then** they know whether to proceed or wait.

---

### User Story 8 - Docker Rebuild Between Impl and QA (Priority: P3)

A pipeline operator runs `/build-prd` on a containerized project. After implementation completes and before QA begins, the pipeline should rebuild Docker containers so QA tests fresh code.

**Why this priority**: Stale containers cause QA to test old code, wasting entire QA cycles on phantom failures.

**Independent Test**: Can be tested by running a pipeline on a project with a Dockerfile, verifying that `docker build` or equivalent runs between implementation and QA phases.

**Acceptance Scenarios**:

1. **Given** a project with `Dockerfile` in the root, **When** the implementation phase completes and QA phase is about to start, **Then** the orchestrator triggers a Docker rebuild.
2. **Given** a project with no `Dockerfile`, **When** the pipeline transitions from implementation to QA, **Then** no Docker rebuild step runs.

---

### User Story 9 - QA Container Freshness Pre-Flight (Priority: P3)

A QA engineer agent starts testing on a containerized project. Before running tests, the agent verifies that the running container reflects the latest code. If stale, it rebuilds.

**Why this priority**: Even with the orchestrator rebuild step, containers can become stale if manually restarted or if the rebuild failed silently.

**Independent Test**: Can be tested by starting a container from an older image, then running the QA agent and verifying it detects staleness and rebuilds.

**Acceptance Scenarios**:

1. **Given** a running container built from an older commit, **When** the QA agent starts its pre-flight check, **Then** it detects the mismatch and triggers a rebuild.
2. **Given** a running container built from the latest commit, **When** the QA agent runs pre-flight, **Then** it proceeds directly to testing.
3. **Given** no containers are running (non-containerized project), **When** the QA agent runs pre-flight, **Then** the check is skipped.

---

### User Story 10 - QA Checkpoint Container Verification (Priority: P3)

A developer runs `/qa-checkpoint` during implementation on a containerized project. The checkpoint should verify container freshness before running its quick tests.

**Why this priority**: Checkpoint QA on stale containers wastes implementer time with misleading feedback.

**Independent Test**: Can be tested by running `/qa-checkpoint` on a containerized project with a stale container and verifying it detects and addresses staleness.

**Acceptance Scenarios**:

1. **Given** a containerized project with a stale container, **When** `/qa-checkpoint` runs, **Then** it detects staleness and rebuilds before testing.
2. **Given** a containerized project with a fresh container, **When** `/qa-checkpoint` runs, **Then** it proceeds directly to testing.

### Edge Cases

- What happens when the branch name has no recognizable feature name (e.g., `main`, `hotfix-123`)? The hook falls back to `.kiln/current-feature` marker file, and if that also doesn't exist, it falls back to the existing glob behavior.
- What happens when `implementing.lock` is left behind after a crash? The lock file must include a timestamp; hooks should treat locks older than 30 minutes as stale and ignore them.
- What happens when multiple feature specs exist and the branch name matches more than one? The hook uses the most specific match (exact feature name from branch, not partial glob).
- What happens when Docker rebuild fails between impl and QA? The orchestrator logs the failure and proceeds to QA with a warning that containers may be stale, rather than blocking the pipeline.
- What happens when `contracts/interfaces.md` is legitimately not needed (e.g., pure documentation features)? The contracts gate only applies when `src/` or other implementation directories are being edited, matching the same scope as the other gates.

## Requirements

### Functional Requirements

#### Hook Gate Fixes

- **FR-001**: The `require-spec.sh` hook MUST derive the current feature name from the git branch name (pattern: `build/<feature-name>-<date>` or `<number>-<feature-name>`) and check for `specs/<current-feature>/spec.md` (and plan.md, tasks.md) instead of using a `specs/*/` glob that matches any feature.

- **FR-002**: When a `.kiln/implementing.lock` file exists and is less than 30 minutes old, Gate 4 MUST allow writes to implementation files even if no tasks are marked `[X]` in tasks.md.

- **FR-003**: The hook allowlist MUST be restructured to use a blocklist approach: instead of allowing only known-safe paths and blocking everything else, the hook MUST check gates for `src/`, `cli/`, `lib/`, `modules/`, `app/`, `components/`, and `templates/` directories, while always allowing `docs/`, `specs/`, `scripts/`, `tests/`, `plugin/`, config files, and other non-implementation paths.

- **FR-004**: The hook MUST verify that `specs/<current-feature>/contracts/interfaces.md` exists before allowing writes to implementation directories, as a new gate between Gate 3 and the existing Gate 4.

#### Pipeline Health & Phase Gating

- **FR-005**: The build-prd orchestrator skill prompt MUST include stall detection instructions: if an agent's task stays `in_progress` for longer than 10 minutes (configurable) without commits, task updates, or messages, the team lead MUST check in on the agent.

- **FR-006**: The build-prd orchestrator skill prompt MUST enforce phase dependencies: downstream phase agents MUST NOT be dispatched until all upstream phase tasks are marked complete.

- **FR-007**: The implement skill prompt MUST replace "STOP and VALIDATE" language with explicit instructions distinguishing self-validation checkpoints ("run tests locally and verify") from QA-gated checkpoints ("wait for QA agent feedback").

#### Docker Container Awareness

- **FR-008**: The build-prd orchestrator skill prompt MUST include a Docker rebuild step between the implementation phase and QA phase when a `Dockerfile` or `docker-compose.yml` exists in the project root.

- **FR-009**: The QA engineer agent prompt MUST include a pre-flight container freshness check: before running tests on containerized projects, verify the running container reflects the latest commits and rebuild if stale.

- **FR-010**: The qa-checkpoint skill MUST include container freshness verification for containerized projects before running checkpoint tests.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Hook gates reject source file writes 100% of the time when the current feature has no spec, even if prior features have specs in the `specs/` directory.
- **SC-002**: Gate 4 allows the first write during an active `/implement` run without requiring pre-marked tasks, eliminating the chicken-and-egg deadlock.
- **SC-003**: Zero false-positive hook blocks on files in `cli/`, `templates/`, `modules/`, `lib/`, `app/`, and `components/` directories when all gates are satisfied.
- **SC-004**: Pipeline detects a simulated stalled agent within the configured timeout window and sends a check-in message.
- **SC-005**: Phase 2 agents are dispatched only after all Phase 1 tasks are marked complete — never before.
- **SC-006**: QA agents on containerized projects detect stale containers and rebuild before testing in 100% of cases.
- **SC-007**: No regression in hook enforcement for `src/` directories compared to current behavior.

## Assumptions

- Branch names follow the pattern `build/<feature-name>-<date>` or `<number>-<feature-name>`, which covers kiln's standard branch naming conventions.
- The `.kiln/current-feature` fallback file is writable by kiln skills and hooks.
- Docker CLI (`docker` command) is available on systems running containerized projects. Non-containerized projects are unaffected.
- The `implementing.lock` file is created by the `/implement` skill at the start of execution and removed at completion (success or failure).
- A 30-minute timeout for stale lock files provides sufficient buffer for legitimate long-running implementations while still recovering from crashes.
- The 10-minute stall detection timeout is a reasonable default; it can be adjusted per-project in the build-prd skill prompt configuration.
