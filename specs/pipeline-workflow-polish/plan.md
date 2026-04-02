# Implementation Plan: Pipeline Workflow Polish

**Branch**: `build/pipeline-workflow-polish-20260401` | **Date**: 2026-04-01 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/pipeline-workflow-polish/spec.md`

## Summary

Add structural validation for non-compiled features, enforce branch/directory naming in the pipeline, auto-complete issues after builds, extend cleanup/doctor skills, reduce commit noise, and add roadmap tracking. All changes target markdown skill definitions, bash hook scripts, and the Node.js scaffold — no `src/` directory is involved.

## Technical Context

**Language/Version**: Markdown (skill definitions), Bash 5.x (hooks), Node.js 18+ (init.mjs scaffold)
**Primary Dependencies**: `jq` (JSON parsing in hooks), `bash -n` (syntax checking), `gh` CLI (GitHub operations)
**Storage**: Filesystem — `.kiln/` directory tree for issues, logs, roadmap, QA artifacts
**Testing**: Manual validation via `/build-prd` pipeline runs on consumer projects; non-compiled validation gate replaces automated test coverage for this repo
**Target Platform**: macOS, Linux (any system running Claude Code)
**Project Type**: Claude Code plugin (markdown skills + bash hooks + Node.js scaffold)
**Performance Goals**: Non-compiled validation completes in under 30 seconds for 10-20 modified files (NFR-001)
**Constraints**: Must not break consumer projects that don't use `/build-prd` (NFR-002); must preserve at least one commit per phase (NFR-003)
**Scale/Scope**: 16 FRs across 6 categories, touching ~12 existing files and creating ~4 new files

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| Spec-First Development | PASS | spec.md exists with 16 FRs and acceptance scenarios |
| 80% Test Coverage | N/A | Plugin repo has no compiled code; non-compiled validation gate (FR-001/002) substitutes |
| PRD as Source of Truth | PASS | PRD at docs/features/2026-04-01-pipeline-workflow-polish/PRD.md is authoritative |
| Hooks Enforce Rules | PASS | Hooks remain active; version-increment hook is modified but not disabled |
| E2E Testing Required | N/A | No CLI/API/user-facing tool being compiled; validation is structural |
| Small Focused Changes | PASS | Each FR targets a bounded area; no file exceeds 500 lines |
| Interface Contracts | PASS | contracts/interfaces.md will define all new/modified skill entry points |
| Incremental Task Completion | PASS | Tasks will be marked [X] and committed per phase |

## Project Structure

### Documentation (this feature)

```text
specs/pipeline-workflow-polish/
├── spec.md
├── plan.md              # This file
├── research.md
├── contracts/
│   └── interfaces.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
plugin/
├── skills/
│   ├── build-prd/SKILL.md        # Modified: FR-004, FR-005, FR-006, FR-007, FR-008, FR-013
│   ├── implement/SKILL.md        # Modified: FR-002, FR-011, FR-012
│   ├── kiln-cleanup/SKILL.md     # Modified: FR-009
│   ├── kiln-doctor/SKILL.md      # Modified: FR-010
│   ├── next/SKILL.md             # Modified: FR-016
│   ├── roadmap/SKILL.md          # NEW: FR-015
│   └── audit/SKILL.md            # Modified: FR-003
├── hooks/
│   └── version-increment.sh      # Modified: FR-011
├── agents/
│   └── (no changes)
├── templates/
│   └── roadmap-template.md       # NEW: FR-014 (template for .kiln/roadmap.md)
├── scaffold/
│   └── (updated by init.mjs)
└── bin/
    └── init.mjs                  # Modified: FR-014 (scaffold .kiln/roadmap.md)

scripts/
└── validate-non-compiled.sh      # NEW: FR-001 (standalone validation script)
```

**Structure Decision**: All changes are edits to existing markdown skills and bash hooks within the `plugin/` directory, plus 3 new files: a validation script, a roadmap skill, and a roadmap template. No new directory structure is needed.

## Deployment Readiness

| Artifact | Path | Required? | Notes |
|----------|------|-----------|-------|
| npm package | plugin/package.json | Yes | Version auto-incremented by hook |
| Plugin manifest | plugin/.claude-plugin/plugin.json | Yes | Version synced from VERSION |

**Deployment notes**: After implementation, run `npm publish --access public` from `plugin/` to ship the updated plugin. No infrastructure changes needed.

## Implementation Phases

### Phase 1: Non-Compiled Validation Gate (FR-001, FR-002, FR-003)

**Goal**: Create a standalone validation script and integrate it into `/implement` and `/audit`.

**Files modified**:
- `scripts/validate-non-compiled.sh` (NEW) — standalone bash script that validates frontmatter, bash syntax, file references, and scaffold output
- `plugin/skills/implement/SKILL.md` — add non-compiled validation as alternative to 80% coverage gate
- `plugin/skills/audit/SKILL.md` — add validation results to auditor checklist

**Approach**:
1. Create `scripts/validate-non-compiled.sh` that:
   - Accepts a list of modified files (or detects via `git diff --name-only`)
   - Checks markdown frontmatter structure (YAML between `---` delimiters)
   - Extracts bash code blocks from SKILL.md files and runs `bash -n` on each
   - Scans file path references and checks they resolve to existing files
   - Runs `node plugin/bin/init.mjs init` in a temp directory to verify scaffold
   - Outputs a structured report (pass/fail per check category)
2. Add a step in `/implement` SKILL.md that detects "no `src/` changes" and runs the validation script instead of the coverage gate
3. Add a checklist item in `/audit` SKILL.md for non-compiled validation evidence

### Phase 2: Branch & Directory Naming + Issue Lifecycle (FR-004, FR-005, FR-006, FR-007, FR-008)

**Goal**: Enforce naming conventions in `/build-prd` and auto-complete issues after PR creation.

**Files modified**:
- `plugin/skills/build-prd/SKILL.md` — enforce branch naming, spec directory naming, fresh branch creation, agent broadcast, issue lifecycle completion

**Approach**:
1. Update the branch creation section (Step 5) to enforce `build/<feature-slug>-<YYYYMMDD>` exactly
2. Update the spec directory creation to use `specs/<feature-slug>/` with no numeric prefix
3. Add explicit "broadcast canonical paths" instruction to agent spawn messages
4. Add a post-PR-creation step that scans `.kiln/issues/` for matching `prd-created` issues, updates their frontmatter to `status: completed`, and moves them to `.kiln/issues/completed/` if that directory exists

### Phase 3: Cleanup, Doctor, and Commit Noise (FR-009, FR-010, FR-011, FR-012, FR-013)

**Goal**: Extend cleanup/doctor skills and reduce commit noise from hooks and task-marking.

**Files modified**:
- `plugin/skills/kiln-cleanup/SKILL.md` — add issue archival scanning
- `plugin/skills/kiln-doctor/SKILL.md` — add stale `prd-created` issue detection
- `plugin/hooks/version-increment.sh` — change from separate commit to in-place staging
- `plugin/skills/implement/SKILL.md` — combine task-marking into phase commits for single-phase features
- `plugin/skills/build-prd/SKILL.md` — add guidance that QA snapshots should not be committed

**Approach**:
1. Add a Step 2.5 to `/kiln-cleanup` that scans `.kiln/issues/` for `status: prd-created` or `status: completed` and archives to `.kiln/issues/completed/`, respecting `--dry-run`
2. Add a Step 3f to `/kiln-doctor` that greps `.kiln/issues/*.md` for `status: prd-created` and reports as diagnostic findings
3. Modify `version-increment.sh` to use `git add` to stage VERSION and package.json changes instead of the current behavior (which just writes files) — the hook already writes in-place, so the change is adding `git add VERSION plugin/package.json plugin/.claude-plugin/plugin.json` at the end
4. Add a note in `/implement` that for single-phase features, task-marking changes should be included in the phase commit
5. Add a note in `/build-prd` that QA result snapshots belong in `.kiln/qa/` (gitignored) and should NOT be committed

### Phase 4: Roadmap Tracking and /next Integration (FR-014, FR-015, FR-016)

**Goal**: Add roadmap scaffold, `/roadmap` skill, and integrate with `/next`.

**Files modified**:
- `plugin/templates/roadmap-template.md` (NEW) — default roadmap structure
- `plugin/skills/roadmap/SKILL.md` (NEW) — skill to append items
- `plugin/bin/init.mjs` — scaffold `.kiln/roadmap.md` from template
- `plugin/skills/next/SKILL.md` — surface roadmap items when no urgent work

**Approach**:
1. Create `plugin/templates/roadmap-template.md` with default theme groups (DX improvements, New capabilities, Tech debt)
2. Create `plugin/skills/roadmap/SKILL.md` that parses user input, identifies the best theme group, and appends the item
3. Update `init.mjs` to copy the roadmap template to `.kiln/roadmap.md` during scaffold
4. Add a section to `/next` that reads `.kiln/roadmap.md` and surfaces items when no urgent work exists

## Complexity Tracking

No constitution violations to justify.
