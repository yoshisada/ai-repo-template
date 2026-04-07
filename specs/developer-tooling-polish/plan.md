# Implementation Plan: Developer Tooling Polish

**Branch**: `build/developer-tooling-polish-20260407` | **Date**: 2026-04-07 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/developer-tooling-polish/spec.md`

## Summary

Two new read-only Claude Code plugin skills: `/wheel-list` (scan and display available wheel workflows with metadata) and `/qa-audit` (analyze test files for duplication and redundancy, output report). Both are Markdown SKILL.md files with embedded Bash, following existing skill patterns. Zero new dependencies.

## Technical Context

**Language/Version**: Bash 5.x, Markdown (skill definitions)  
**Primary Dependencies**: jq (JSON parsing), existing wheel engine libs (`plugin-wheel/lib/workflow.sh`)  
**Storage**: Filesystem — reads `workflows/*.json`, writes `.kiln/qa/test-audit-report.md`  
**Testing**: Manual via running the skills on consumer projects (no test suite for plugin skills)  
**Target Platform**: macOS/Linux (Claude Code runtime)  
**Project Type**: Claude Code plugin skills  
**Performance Goals**: `/wheel-list` completes in <5s for up to 50 workflow files  
**Constraints**: Read-only skills — no modifications to existing files (except writing audit report)  
**Scale/Scope**: 2 SKILL.md files, ~100-200 lines each

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| I. Spec-First Development | PASS | spec.md exists with FRs, user stories, acceptance scenarios |
| II. 80% Test Coverage | N/A | Plugin skills are Markdown/Bash — no test suite for the plugin itself |
| III. PRD as Source of Truth | PASS | PRD at docs/features/2026-04-07-developer-tooling-polish/PRD.md is authoritative |
| IV. Hooks Enforce Rules | PASS | Existing hooks remain active |
| V. E2E Testing Required | N/A | Plugin skills tested by running on consumer projects |
| VI. Small, Focused Changes | PASS | 2 independent skills, each in its own directory |
| VII. Interface Contracts | PASS | contracts/interfaces.md will define skill structure |
| VIII. Incremental Task Completion | PASS | Tasks will be marked [X] as completed |

## Project Structure

### Documentation (this feature)

```text
specs/developer-tooling-polish/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0 output
├── contracts/
│   └── interfaces.md    # Skill interface contracts
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (/tasks command)
```

### Source Code (repository root)

```text
plugin-wheel/skills/
└── wheel-list/
    └── SKILL.md          # FR-001 to FR-005: /wheel-list command

plugin-kiln/skills/
└── qa-audit/
    └── SKILL.md          # FR-006 to FR-011: /qa-audit command
```

**Structure Decision**: Each skill lives in its respective plugin directory following the established pattern (one SKILL.md per skill directory). No shared code — each skill is self-contained.

## Implementation Phases

### Phase 1: Wheel List Skill (FR-001 to FR-005)

Create `plugin-wheel/skills/wheel-list/SKILL.md` with:

1. **Frontmatter**: name, description matching existing skill patterns
2. **Step 1 — Scan** (FR-001): Find all `.json` files in `workflows/` recursively using `find`
3. **Step 2 — Parse** (FR-002): For each workflow, extract name, step count, step types using `jq`
4. **Step 3 — Group** (FR-003): Group results by parent directory
5. **Step 4 — Validate** (FR-004): Use `workflow_load()` from `plugin-wheel/lib/workflow.sh` or inline validation to check each workflow; capture errors without failing
6. **Step 5 — Empty state** (FR-005): If no workflows found, display helpful message pointing to `/wheel-create`

### Phase 2: QA Test Audit Skill (FR-006 to FR-011)

Create `plugin-kiln/skills/qa-audit/SKILL.md` with:

1. **Frontmatter**: name, description
2. **Step 1 — Discover** (FR-006): Find test files using common patterns (`*.test.*`, `*.spec.*`, `tests/`, `__tests__/`, `e2e/`)
3. **Step 2 — Analyze** (FR-007, FR-008): Read each test file, extract test names/descriptions, identify overlapping scenarios and redundant assertions using text similarity heuristics
4. **Step 3 — Report** (FR-009, FR-010): Generate prioritized report with overlap pairs, redundancy estimates, and consolidation suggestions; write to `.kiln/qa/test-audit-report.md`
5. **Step 4 — Pipeline integration** (FR-011): Optional flag/mode for pipeline use that routes findings to implementers

### Phase 3: Verification

- Run `/wheel-list` on this repo (which has `workflows/` directory)
- Run `/qa-audit` on a project with test files
- Verify edge cases (no workflows, invalid JSON, no test files)

## File Manifest

| File | Phase | FR | Action |
|------|-------|----|--------|
| `plugin-wheel/skills/wheel-list/SKILL.md` | 1 | FR-001 to FR-005 | Create |
| `plugin-kiln/skills/qa-audit/SKILL.md` | 2 | FR-006 to FR-011 | Create |

## Complexity Tracking

No constitution violations to justify.
