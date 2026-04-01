# Implementation Plan: Pipeline Reliability & Health

**Branch**: `build/pipeline-reliability-20260401` | **Date**: 2026-04-01 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/pipeline-reliability/spec.md`

## Summary

Fix three critical pipeline reliability failures: (1) hook gates that match any prior feature's spec instead of the current feature's, plus Gate 4 chicken-and-egg deadlock, allowlist gaps, and missing contracts gate; (2) pipeline orchestrator lacking stall detection, phase dependency enforcement, and clear validation language; (3) stale Docker containers causing QA to test old code. All changes are to existing Bash scripts, Markdown skill definitions, and Markdown agent prompts under `plugin/`.

## Technical Context

**Language/Version**: Bash 5.x (hook scripts), Markdown (skill/agent definitions)
**Primary Dependencies**: git CLI, jq (JSON parsing in hooks), Docker CLI (for container-aware projects)
**Storage**: N/A — file-based lock and marker files only
**Testing**: Manual pipeline runs on consumer projects (no automated test suite for the plugin itself)
**Target Platform**: macOS, Linux (any system running Claude Code)
**Project Type**: Claude Code plugin (Markdown + Bash)
**Performance Goals**: Hook execution under 100ms per invocation
**Constraints**: Backwards-compatible with existing consumer projects
**Scale/Scope**: 6 files modified, ~200 lines changed across all files

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| I. Spec-First Development | PASS | spec.md created and committed before plan |
| II. 80% Test Coverage | N/A | No test suite for the plugin itself; testing is via pipeline runs |
| III. PRD as Source of Truth | PASS | spec aligns with `docs/features/2026-04-01-pipeline-reliability/PRD.md` |
| IV. Hooks Enforce Rules | PASS | This feature improves hook enforcement |
| V. E2E Testing Required | N/A | Plugin has no compiled artifact; validated by pipeline runs |
| VI. Small, Focused Changes | PASS | 6 files, bounded scope per file |
| VII. Interface Contracts | PASS | contracts/interfaces.md defines all hook functions and prompt additions |
| VIII. Incremental Task Completion | PASS | Tasks will be marked [X] per phase |

## Project Structure

### Documentation (this feature)

```text
specs/pipeline-reliability/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0 output
├── contracts/
│   └── interfaces.md    # Hook function + prompt contracts
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (created by /tasks)
```

### Source Code (files to modify)

```text
plugin/
├── hooks/
│   └── require-spec.sh          # FR-001, FR-002, FR-003, FR-004
├── skills/
│   ├── build-prd/
│   │   └── SKILL.md             # FR-005, FR-006, FR-008
│   ├── implement/
│   │   └── SKILL.md             # FR-002 (lock mgmt), FR-007
│   └── qa-checkpoint/
│       └── SKILL.md             # FR-010
├── agents/
│   └── qa-engineer.md           # FR-009
└── templates/
    └── tasks-template.md        # FR-007 (STOP AND VALIDATE)
```

**Structure Decision**: No new directories. All changes are modifications to existing files under `plugin/`. The only new file-system artifacts are the transient `.kiln/implementing.lock` and `.kiln/current-feature` marker files created at runtime in consumer projects.

## Deployment Readiness

| Artifact | Path | Required? | Notes |
|----------|------|-----------|-------|
| Dockerfile | N/A | N/A | Plugin is not containerized |
| CI config | N/A | N/A | No CI for plugin itself |
| Env template | N/A | N/A | No env vars needed |

**Deployment notes**: Changes ship via `npm publish` from `plugin/`. Consumers get updates via `npx @yoshisada/kiln init` or plugin auto-update. Backwards compatibility is maintained — existing consumer projects with the old hook behavior will work (glob fallback when branch name doesn't match any pattern).

## Implementation Phases

### Phase 1: Hook Gate Overhaul (FR-001, FR-002, FR-003, FR-004)

**File**: `plugin/hooks/require-spec.sh`

1. Add `get_current_feature()` function — extracts feature name from branch name with fallback to `.kiln/current-feature`
2. Replace `specs/*/` globs with `specs/<current-feature>/` for all gate checks
3. Add `is_implementation_path()` function — blocklist approach replacing the current allowlist
4. Restructure the path-check logic to use `is_implementation_path()` instead of the case statement
5. Add Gate 3.5: check for `contracts/interfaces.md`
6. Add `check_implementing_lock()` function — reads `.kiln/implementing.lock`, checks timestamp freshness
7. Update Gate 4 to pass if implementing lock is active OR tasks have `[X]` marks

### Phase 2: Pipeline Health (FR-005, FR-006, FR-007, FR-008)

**Files**: `plugin/skills/build-prd/SKILL.md`, `plugin/skills/implement/SKILL.md`, `plugin/templates/tasks-template.md`

1. Add stall detection instructions to build-prd "Monitor and Steer" section (FR-005)
2. Add phase dependency enforcement instructions to build-prd dispatch logic (FR-006)
3. Add implementing.lock creation/cleanup to implement skill outline (FR-002 lock management)
4. Replace "STOP and VALIDATE" with "SELF-VALIDATE" in implement skill and tasks template (FR-007)
5. Add Docker rebuild step between impl and QA in build-prd (FR-008)

### Phase 3: Docker Container Awareness (FR-009, FR-010)

**Files**: `plugin/agents/qa-engineer.md`, `plugin/skills/qa-checkpoint/SKILL.md`

1. Add container freshness pre-flight to qa-engineer agent prompt (FR-009)
2. Add container freshness step to qa-checkpoint skill (FR-010)

## Complexity Tracking

No constitution violations to justify. All changes are bounded modifications to existing files.
