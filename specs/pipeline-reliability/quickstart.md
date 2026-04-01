# Quickstart: Pipeline Reliability & Health

## What Changed

This feature fixes three categories of pipeline reliability bugs:

1. **Hook gates** now scope to the current feature (not any prior feature), support an implementing lock for Gate 4, check for contracts, and use a broader implementation directory list.
2. **Pipeline orchestrator** now includes stall detection, phase dependency enforcement, Docker rebuild steps, and clearer validation language.
3. **QA agents** now verify container freshness before testing containerized projects.

## Verifying the Changes

### Hook Gate Scoping

To verify hook gates scope correctly:

1. Create a consumer project with two features: `specs/old-feature/spec.md` and a new branch `build/new-feature-20260401`
2. Try to edit a file in `src/` — should be blocked (new feature has no spec)
3. Create `specs/new-feature/spec.md`, `plan.md`, `tasks.md`, `contracts/interfaces.md`
4. Try again — should still be blocked (no `[X]` in tasks and no implementing lock)
5. Create `.kiln/implementing.lock` with valid JSON and fresh timestamp — edit should be allowed

### Expanded Allowlist

Files in `cli/`, `lib/`, `modules/`, `app/`, `components/` are now subject to gate checks (same as `src/`). Files in `docs/`, `specs/`, `scripts/`, `tests/`, `plugin/`, and config files remain always-allowed.

### Pipeline Health

Run `/build-prd` on a multi-phase feature and observe:
- Phase 2 agents are not dispatched until Phase 1 is complete
- Stalled agents receive check-in messages after 10 minutes of inactivity
- "SELF-VALIDATE" language appears instead of "STOP and VALIDATE"

### Docker Awareness

On a containerized project, verify:
- Docker rebuild runs between implementation and QA phases
- QA agents check container freshness before testing
- `/qa-checkpoint` verifies container freshness
