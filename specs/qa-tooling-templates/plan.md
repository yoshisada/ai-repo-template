# Implementation Plan: QA Agent Optimization, Kiln Doctor Enhancements & Template Improvements

**Branch**: `build/qa-tooling-templates-20260401` | **Date**: 2026-04-01 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/qa-tooling-templates/spec.md`

## Summary

Optimize the QA agent for speed (parallel viewports, failure-only recording, targeted waits), add build enforcement and feature-scoped reporting, enable retrospective feedback via file-based agent notes, enhance kiln-doctor with cleanup and version-sync capabilities, create a `/kiln-cleanup` skill, externalize the issue template, improve spec/PRD templates with common checklists, and implement issue archival.

## Technical Context

**Language/Version**: Markdown (skill/agent definitions), Bash 5.x (hook scripts), Node.js 18+ (init.mjs), JSON (configs)  
**Primary Dependencies**: Claude Code plugin system, GitHub CLI (`gh`), Playwright (QA config changes)  
**Storage**: Filesystem — `.kiln/` directory tree, `specs/` artifacts  
**Testing**: Manual verification via pipeline runs on consumer projects. No automated test suite for the plugin itself.  
**Target Platform**: macOS/Linux (Claude Code CLI environments)  
**Project Type**: Claude Code plugin (markdown skills, agent definitions, bash hooks, Node.js scaffold)  
**Performance Goals**: QA agent runtime reduced by 50%+ via parallel viewports and failure-only recording  
**Constraints**: Backwards-compatible template changes. No breaking changes to existing consumer projects.  
**Scale/Scope**: 15 files modified, 2 new files created, across 25 functional requirements

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Gate | Status | Notes |
|------|--------|-------|
| Spec-First Development | PASS | spec.md exists with all 25 FRs, user stories, acceptance scenarios |
| 80% Test Coverage Gate | N/A | Plugin is markdown/bash — no compiled code, no test suite |
| PRD as Source of Truth | PASS | PRD at docs/features/2026-04-01-qa-tooling-templates/PRD.md, spec does not contradict |
| Hooks Enforce Rules | PASS | Hooks are active on the branch |
| E2E Testing Required | N/A | Plugin has no CLI/API — verification via pipeline runs |
| Small, Focused Changes | PASS | 25 FRs grouped into 3 coherent themes, each touching bounded areas |
| Interface Contracts Before Implementation | PASS | contracts/interfaces.md defines all file modifications |
| Incremental Task Completion | PASS | Tasks will be marked [X] per phase |

## Project Structure

### Documentation (this feature)

```text
specs/qa-tooling-templates/
├── spec.md
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── interfaces.md    # Phase 1 output
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 output (created by /tasks)
```

### Source Code (repository root)

```text
plugin/
├── agents/
│   ├── qa-engineer.md          # Modified (FR-001–009)
│   ├── debugger.md             # Modified (FR-009)
│   ├── prd-auditor.md          # Modified (FR-009)
│   ├── smoke-tester.md         # Modified (FR-009)
│   ├── spec-enforcer.md        # Modified (FR-009)
│   └── test-runner.md          # Modified (FR-009)
├── skills/
│   ├── qa-setup/SKILL.md       # Modified (FR-001, FR-002)
│   ├── build-prd/SKILL.md      # Modified (FR-009, FR-010)
│   ├── kiln-doctor/SKILL.md    # Modified (FR-012, FR-014–017)
│   ├── kiln-cleanup/SKILL.md   # NEW (FR-013)
│   ├── report-issue/SKILL.md   # Modified (FR-018, FR-024, FR-025)
│   ├── issue-to-prd/SKILL.md   # Modified (FR-025)
│   └── analyze-issues/SKILL.md # Modified (FR-024)
├── templates/
│   ├── kiln-manifest.json      # Modified (FR-011, FR-024)
│   ├── issue.md                # NEW (FR-018)
│   ├── spec-template.md        # Modified (FR-020, FR-022)
│   └── plan-template.md        # Modified (FR-021, FR-023)
├── bin/
│   └── init.mjs                # Modified (FR-019, FR-024)
└── .claude-plugin/
    └── plugin.json             # Unchanged
```

**Structure Decision**: This is a plugin source repo. All changes are to markdown skill/agent definitions, JSON configs, markdown templates, and the Node.js scaffold script. No `src/` or `tests/` directories are involved.

## Deployment Readiness

| Artifact | Path | Required? | Notes |
|----------|------|-----------|-------|
| npm package | plugin/package.json | Yes | Version bump + publish after merge |
| Dockerfile | N/A | No | Plugin has no Docker deployment |
| CI config | N/A | No | No CI pipeline for the plugin itself |
| Env template | N/A | No | No environment variables needed |

**Deployment notes**: After merge, run `./scripts/version-bump.sh feature` and `npm publish --access public` from `plugin/`.

## Implementation Phases

### Phase 1: QA Agent Performance (FR-001 through FR-004)

**Files**: `plugin/agents/qa-engineer.md`, `plugin/skills/qa-setup/SKILL.md`

1. Update Playwright config snippets in qa-engineer.md: `video`/`trace` → `retain-on-failure`
2. Update Playwright config snippets in qa-setup SKILL.md: same changes + add `fullyParallel: true` + tablet viewport
3. Add `waitForSelector`/`waitForFunction` preference rule to qa-engineer.md Test Writing Rules
4. Add walkthrough recording section to qa-engineer.md

### Phase 2: QA Build Enforcement + Scope (FR-005 through FR-008)

**Files**: `plugin/agents/qa-engineer.md`

1. Add "Build After Message" section requiring rebuild after every received `SendMessage`
2. Add idle-blocking instruction (refuse to go idle without building since last message)
3. Add "Feature-Scoped Testing" section: test feature matrix first, then optional regression
4. Restructure QA Report template into Feature Verdict + Regression Findings sections

### Phase 3: Agent Friction Notes + Retrospective (FR-009, FR-010)

**Files**: `plugin/agents/qa-engineer.md`, `plugin/agents/debugger.md`, `plugin/agents/prd-auditor.md`, `plugin/agents/smoke-tester.md`, `plugin/agents/spec-enforcer.md`, `plugin/agents/test-runner.md`, `plugin/skills/build-prd/SKILL.md`

1. Add "Agent Friction Notes" section to each agent definition
2. Update build-prd skill: instruct all agents to write friction notes before completing
3. Update build-prd retrospective section: read from `specs/<feature>/agent-notes/` instead of `SendMessage`

### Phase 4: Kiln Doctor Cleanup + Version Sync (FR-011 through FR-017)

**Files**: `plugin/templates/kiln-manifest.json`, `plugin/skills/kiln-doctor/SKILL.md`, `plugin/skills/kiln-cleanup/SKILL.md` (new)

1. Extend kiln-manifest.json with retention rules on directory entries
2. Add `--cleanup` mode to kiln-doctor with `--dry-run` support
3. Add version-sync check to kiln-doctor diagnose mode
4. Add version-sync fix to kiln-doctor fix mode
5. Add `.kiln/version-sync.json` config support to kiln-doctor
6. Create `/kiln-cleanup` skill (new SKILL.md)
7. Integrate `/kiln-cleanup` into kiln-doctor fix mode

### Phase 5: Templates + Issue Archival (FR-018 through FR-025)

**Files**: `plugin/templates/issue.md` (new), `plugin/skills/report-issue/SKILL.md`, `plugin/skills/issue-to-prd/SKILL.md`, `plugin/skills/analyze-issues/SKILL.md`, `plugin/bin/init.mjs`, `plugin/templates/spec-template.md`, `plugin/templates/plan-template.md`

1. Create `plugin/templates/issue.md` by extracting template from report-issue
2. Update report-issue to read from template file
3. Update init.mjs to scaffold issue template and `completed/` directory
4. Add rename/rebrand checklist to spec-template.md
5. Add QA auth documentation prompt to spec-template.md
6. Add container CLI discovery task to plan-template.md
7. Add local a11y validation guidance to plan-template.md
8. Add archival logic to report-issue (move closed/done to `completed/`)
9. Update report-issue and issue-to-prd to scan only top-level `.kiln/issues/`
10. Update analyze-issues to archive on close
11. Add `.kiln/issues/completed/` to kiln-manifest.json

## Complexity Tracking

No constitution violations. All changes are bounded, backwards-compatible, and follow existing patterns.
