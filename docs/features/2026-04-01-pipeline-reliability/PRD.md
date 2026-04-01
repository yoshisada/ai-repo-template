# Feature PRD: Pipeline Reliability & Health

**Date**: 2026-04-01
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)

## Background

Kiln's build-prd pipeline has three critical reliability failures that undermine its core value proposition. Across at least 8 pipeline runs (issues #9, #11, #15, #17, #18, #19, #23, #26), the pipeline has exhibited: stale Docker containers causing QA to test old code, hook gates that silently pass when they should block, and agents that stall or race past phase dependencies. These aren't edge cases — they are systemic failures that occur on nearly every containerized pipeline run and have caused complete pipeline failures, wasted QA cycles, and silent enforcement bypasses.

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [Stale Docker containers waste QA cycles](.kiln/issues/2026-04-01-stale-docker-containers-waste-qa.md) | #18, #23, #19, #17 | bug | critical |
| 2 | [Hook gate enforcement broken in 3 ways](.kiln/issues/2026-04-01-hook-gate-enforcement-broken.md) | #26, #9, #15 | bug | critical |
| 3 | [Pipeline lacks agent health-checks and phase gating](.kiln/issues/2026-04-01-pipeline-health-checks-phase-gating.md) | #11, #26, #19 | bug | critical |

## Problem Statement

The kiln pipeline's enforcement and orchestration layers are unreliable. Hook gates — the mechanism that ensures spec-first development — can be silently bypassed because they match any prior feature's spec, not the current one. The pipeline has no awareness of Docker containers, so QA agents routinely test stale builds and waste entire cycles diagnosing container issues instead of testing code. And the pipeline orchestrator has no timeout, stall detection, or phase dependency enforcement, meaning agents can hang indefinitely or race ahead of their dependencies.

These failures affect every kiln user running containerized projects and undermine trust in the pipeline's ability to enforce the spec-first workflow that is kiln's core differentiator.

## Goals

- Hook gates correctly scope to the current feature's spec artifacts, not any prior feature's
- Gate 4 (task completion check) works without chicken-and-egg hacks
- Hook allowlist matches documented behavior (blocks `src/` edits, not everything outside a narrow allowlist)
- Pipeline detects and recovers from stalled agents
- Phase dependencies in tasks.md are enforced by the orchestrator, not just documented
- QA agents verify container freshness before testing containerized projects
- Ambiguous prompts ("STOP and VALIDATE") are clarified to prevent agent self-blocking

## Non-Goals

- Full Docker orchestration or Docker Compose management — kiln only needs rebuild-awareness, not container lifecycle management
- Replacing the hook system with a different enforcement mechanism
- Adding new pipeline phases or agents
- Changing the 4-gate model itself — only fixing the implementation of existing gates

## Requirements

### Functional Requirements

#### Hook Gate Fixes

**FR-001** (from: hook-gate-enforcement-broken.md) — Hook gates must scope to the current feature. The `require-spec.sh` hook must check for `specs/<current-feature>/spec.md` (and plan.md, tasks.md) where `<current-feature>` is derived from the git branch name or a `.kiln/current-feature` marker file, not from a `specs/*/` glob that matches any feature.

**FR-002** (from: hook-gate-enforcement-broken.md) — Gate 4 must not create a chicken-and-egg deadlock. When the `/implement` skill is active (detectable via a `.kiln/implementing.lock` file or equivalent), Gate 4 should allow writes to implementation files even before a task is marked `[X]`, since marking a task requires completing the write first.

**FR-003** (from: hook-gate-enforcement-broken.md) — The hook allowlist must match documented behavior. Either: (a) only block files under `src/` as documented, or (b) expand the allowlist to include `cli/`, `templates/`, `modules/`, and other common project directories. The chosen approach must be documented in the hook file and CLAUDE.md.

**FR-004** (from: hook-gate-enforcement-broken.md) — Add a gate check that verifies `contracts/interfaces.md` exists before allowing implementation writes, enforcing the interface-contract-first workflow.

#### Pipeline Health & Phase Gating

**FR-005** (from: pipeline-health-checks-phase-gating.md) — The build-prd orchestrator must detect stalled agents. If an agent's task stays `in_progress` for longer than a configurable timeout (default: 10 minutes) without commits, task updates, or messages, the team lead must check in on the agent and escalate or reassign if unresponsive.

**FR-006** (from: pipeline-health-checks-phase-gating.md) — Phase dependencies in tasks.md must be enforced by the orchestrator. Downstream phase agents must not receive their prompts until all upstream phase tasks are marked complete. The build-prd skill must dispatch implementer agents in dependency order, not all at once.

**FR-007** (from: pipeline-health-checks-phase-gating.md) — The implement skill prompt must clarify "STOP and VALIDATE" to mean "run tests locally and self-validate," not "wait for external QA feedback." The distinction between self-validation checkpoints and QA-gated checkpoints must be explicit.

#### Docker Container Awareness

**FR-008** (from: stale-docker-containers-waste-qa.md) — The build-prd orchestrator must include a Docker rebuild step between the implementation phase and QA phase for containerized projects. Detection of containerized projects can be based on the presence of a `Dockerfile` or `docker-compose.yml` in the project root.

**FR-009** (from: stale-docker-containers-waste-qa.md) — The QA engineer agent prompt must include a pre-flight check: before running tests on containerized projects, verify the running container reflects the latest commits. If stale, rebuild before proceeding.

**FR-010** (from: stale-docker-containers-waste-qa.md) — The qa-checkpoint skill must include container freshness verification for containerized projects, preventing checkpoint-level QA from testing stale builds.

### Non-Functional Requirements

- **Backwards compatibility**: Changes to hooks must not break existing consumer projects that rely on the current allowlist behavior. A migration path or kiln-doctor check should handle the transition.
- **Performance**: Stall detection must not add latency to normal pipeline runs. Health checks should be event-driven (on task update) rather than polling-based where possible.
- **Reliability**: The implementing.lock mechanism must be cleaned up on both success and failure paths to prevent stale locks from blocking future runs.

## User Stories

- **As a kiln user**, I want hook gates to only check the current feature's spec so that prior features' artifacts don't silently satisfy the gates.
- **As a pipeline operator**, I want stalled agents to be detected and escalated automatically so that a single hung agent doesn't block the entire pipeline indefinitely.
- **As a QA engineer agent**, I want to verify container freshness before testing so that I don't waste cycles testing stale builds.
- **As an implementer agent**, I want Gate 4 to allow me to write files during implementation without requiring a pre-marked task, so that I don't have to use workarounds that undermine the gate.
- **As a kiln user with a non-src project**, I want the hook allowlist to not block my `cli/`, `templates/`, or `modules/` directories, so that hooks only enforce spec-first for actual source code.

## Success Criteria

- Hook gates reject writes when current feature has no spec, even if prior features have specs — verified by testing with multiple spec directories present
- Gate 4 allows writes during active `/implement` runs without requiring pre-marked tasks
- Pipeline detects a simulated stalled agent within the configured timeout window
- Phase 2 implementer agents are not dispatched until Phase 1 tasks are complete
- QA agents on containerized projects detect and rebuild stale containers before testing
- Zero false-positive hook blocks on `cli/`, `templates/`, `modules/` directories
- No regression in hook enforcement for `src/` directories

## Tech Stack

- Bash (hook scripts — `require-spec.sh` and related)
- Markdown (agent prompts — `build-prd/SKILL.md`, `qa-engineer.md`, `implement/SKILL.md`)
- Markdown (skill definitions — `qa-checkpoint/SKILL.md`)
- Shell + git (branch name detection for feature scoping)

## Risks & Open Questions

1. **Branch name parsing**: Deriving `<current-feature>` from the branch name assumes a consistent naming convention. What happens when users have non-standard branch names? A `.kiln/current-feature` fallback file may be more reliable.
2. **Timeout tuning**: The 10-minute default for stall detection may be too aggressive for complex implementation tasks. This may need to be configurable per-project.
3. **Lock file cleanup**: The `implementing.lock` mechanism needs robust cleanup. If Claude Code crashes mid-implementation, the lock file could persist and block future Gate 4 checks.
4. **Docker detection heuristic**: Checking for `Dockerfile` in the project root may miss projects with Dockerfiles in subdirectories or projects using alternative container tools.
5. **Hook backwards compatibility**: Changing the allowlist behavior could break consumer projects that depend on the current (narrow) allowlist. Need a migration strategy.
