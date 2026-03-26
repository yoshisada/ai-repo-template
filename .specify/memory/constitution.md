# Project Constitution

## Core Principles

### I. Spec-First Development (NON-NEGOTIABLE)
No implementation begins without a written spec. Every feature must have user stories with Given/When/Then acceptance scenarios, functional requirements with unique IDs (FR-001), and measurable success criteria. Every function must reference its spec FR in a comment. Every test must reference the acceptance scenario it validates. The spec must be committed to git before any implementation.

### II. 80% Test Coverage Gate (NON-NEGOTIABLE)
Every task must achieve >=80% line and branch coverage on new and modified code before it can be marked complete. A task that does not meet the threshold is not done, regardless of whether the feature works manually.

### III. PRD as Source of Truth
The PRD at `docs/PRD.md` is the authoritative source for scope, goals, and success criteria. Specs must not contradict the PRD. If a spec needs to diverge, the PRD must be updated first with a documented reason.

### IV. Hooks Enforce Rules
Claude Code hooks in `.claude/settings.json` physically block code changes without specs and prevent secret commits. These hooks are non-negotiable and must not be disabled.

### V. E2E Testing Required
Every CLI, API, or user-facing tool must have end-to-end tests that exercise the real compiled artifact the way a user would use it. Unit tests are not sufficient — if `kit create my-app && cd my-app && bun dev` doesn't work, the unit tests are lying. E2E tests run the actual binary against real file operations in temp directories.

### VI. Small, Focused Changes
Each task touches one bounded area. Files stay under 500 lines. No premature abstractions.

## Development Workflow

1. Read this constitution
2. Check PRD at `docs/PRD.md`
3. Write spec in `specs/<feature>/spec.md`
4. Commit spec before code
5. Implement with FR traceability
6. Write tests with scenario traceability
7. Verify: tests pass, >=80% coverage, build succeeds

## Governance

This constitution supersedes all other practices. Amendments require a version bump.

**Version**: 1.0.0 | **Ratified**: 2026-03-26
