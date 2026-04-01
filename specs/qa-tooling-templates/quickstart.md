# Quickstart: QA Agent Optimization, Kiln Doctor Enhancements & Template Improvements

**Date**: 2026-04-01

## What This Feature Does

This feature batch optimizes three areas of the kiln plugin:

1. **QA Agent Performance** — Makes the QA agent faster by enabling parallel viewports, failure-only recording, targeted waits, and adds walkthrough recording + build enforcement.
2. **Kiln Doctor Enhancements** — Adds cleanup, version-sync, and a new `/kiln-cleanup` skill for QA artifact purging.
3. **Template Improvements** — Externalizes the issue template, adds common-requirement checklists to spec/PRD templates, and implements issue archival.

## Files to Modify

### QA Agent & Setup (FR-001 through FR-010)
- `plugin/agents/qa-engineer.md` — Performance, scoping, build enforcement, friction notes
- `plugin/skills/qa-setup/SKILL.md` — Playwright config defaults
- `plugin/skills/build-prd/SKILL.md` — Agent friction notes, retrospective changes
- `plugin/agents/debugger.md` — Add friction notes section
- `plugin/agents/prd-auditor.md` — Add friction notes section
- `plugin/agents/smoke-tester.md` — Add friction notes section
- `plugin/agents/spec-enforcer.md` — Add friction notes section
- `plugin/agents/test-runner.md` — Add friction notes section

### Kiln Doctor & Cleanup (FR-011 through FR-017)
- `plugin/templates/kiln-manifest.json` — Add retention rules
- `plugin/skills/kiln-doctor/SKILL.md` — Add cleanup, version-sync, and dry-run
- `plugin/skills/kiln-cleanup/SKILL.md` — **New file** — QA artifact cleanup skill

### Templates & Archival (FR-018 through FR-025)
- `plugin/templates/issue.md` — **New file** — Extracted issue template
- `plugin/skills/report-issue/SKILL.md` — Read from template, archival, scoped scanning
- `plugin/skills/issue-to-prd/SKILL.md` — Scoped scanning (skip completed/)
- `plugin/bin/init.mjs` — Scaffold issue template and completed/ directory
- `plugin/templates/spec-template.md` — Add rename/rebrand and QA auth checklists
- `plugin/templates/plan-template.md` — Add CLI discovery and a11y guidance
- `plugin/skills/analyze-issues/SKILL.md` — Archival on close

## Implementation Order

1. QA agent performance optimizations (FR-001 through FR-004)
2. QA build enforcement (FR-005, FR-006)
3. QA scope and reporting (FR-007, FR-008)
4. Agent friction notes (FR-009, FR-010) — touches many agent files
5. Kiln manifest retention rules (FR-011)
6. Kiln doctor cleanup and version-sync (FR-012, FR-014, FR-015, FR-016, FR-017)
7. `/kiln-cleanup` skill (FR-013)
8. Issue template extraction (FR-018, FR-019)
9. Template improvements (FR-020 through FR-023)
10. Issue archival (FR-024, FR-025)

## How to Verify

Since this is a plugin source repo with no test suite, verification is done by:
1. Reading each modified file and confirming the contract changes are present
2. Running `node plugin/bin/init.mjs init` in a temp directory and checking scaffolded files
3. Running a `/build-prd` pipeline on a consumer project to exercise the QA agent changes
