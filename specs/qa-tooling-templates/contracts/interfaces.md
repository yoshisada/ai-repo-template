# Interface Contracts: QA Agent Optimization, Kiln Doctor Enhancements & Template Improvements

**Date**: 2026-04-01  
**Spec**: [spec.md](../spec.md)

> This project is a Claude Code plugin composed of markdown skills, markdown agent definitions, bash hook scripts, JSON configs, and a Node.js scaffold script. There are no compiled functions or exported APIs. The "interfaces" below define the contracts for each file that will be created or modified, specifying the exact sections, keys, or behaviors that must be present.

---

## 1. QA Agent Definition (`plugin/agents/qa-engineer.md`)

### Modifications Required

| Section | Change | FR |
|---------|--------|----|
| Playwright config snippet | Change `video: 'on'` to `video: 'retain-on-failure'` | FR-001 |
| Playwright config snippet | Change `trace: 'on'` to `trace: 'retain-on-failure'` | FR-001 |
| Playwright config snippet | Add `fullyParallel: true` | FR-002 |
| Test Writing Rules | Add rule: prefer `waitForSelector`/`waitForFunction` over `networkidle`; prohibit `waitForTimeout` | FR-003 |
| New section: Walkthrough Recording | After all tests pass, record one clean walkthrough of new feature flows | FR-004 |
| New section: Build After Message | After every `SendMessage` received, run the project build command before proceeding | FR-005, FR-006 |
| New section: Feature-Scoped Testing | Test feature matrix first; report Feature Verdict before Regression Findings | FR-007 |
| QA Report template | Restructure into (1) Feature Verdict and (2) Regression Findings sections | FR-008 |
| New section: Agent Friction Notes | Before completing work, write friction note to `specs/<feature>/agent-notes/qa-engineer.md` | FR-009 |

---

## 2. QA Setup Skill (`plugin/skills/qa-setup/SKILL.md`)

### Modifications Required

| Section | Change | FR |
|---------|--------|----|
| Playwright Config generation | Change `video: 'on'` to `video: 'retain-on-failure'` | FR-001 |
| Playwright Config generation | Change `trace: 'on'` to `trace: 'retain-on-failure'` | FR-001 |
| Playwright Config generation | Add `fullyParallel: true` to `defineConfig()` | FR-002 |
| Playwright Config generation | Add tablet viewport project (`{ name: 'tablet', viewport: { width: 768, height: 1024 } }`) | FR-002 |
| Test stub template | Change `video: 'on'` to `video: 'retain-on-failure'` | FR-001 |
| Test stub template | Change `trace: 'on'` to `trace: 'retain-on-failure'` | FR-001 |

---

## 3. Build-PRD Skill (`plugin/skills/build-prd/SKILL.md`)

### Modifications Required

| Section | Change | FR |
|---------|--------|----|
| Agent team design | Add instruction: all pipeline agents must write friction notes before completing | FR-009 |
| Retrospective section | Read `specs/<feature>/agent-notes/` instead of sending `SendMessage` to teammates | FR-010 |

---

## 4. Pipeline Agent Definitions (all agents in `plugin/agents/`)

### Modifications Required — Each Agent

Each agent definition (`debugger.md`, `prd-auditor.md`, `qa-engineer.md`, `smoke-tester.md`, `spec-enforcer.md`, `test-runner.md`) must include:

| Section | Change | FR |
|---------|--------|----|
| New section: Agent Friction Notes | Before completing, write to `specs/<feature>/agent-notes/<agent-name>.md` with: what was confusing, where stuck, what to improve | FR-009 |

---

## 5. Kiln Manifest (`plugin/templates/kiln-manifest.json`)

### Modifications Required

| Key | Change | FR |
|-----|--------|----|
| `directories[".kiln/logs"].retention` | Add `{ "keep_last": 10 }` | FR-011 |
| `directories[".kiln/issues"].retention` | Add `{ "archive_completed": true }` | FR-011 |
| `directories[".kiln/qa"].retention` | Add `{ "purge_artifacts": true }` | FR-011 |
| `directories[".kiln/issues/completed"]` | Add new directory entry `{ "required": false, "tracked": true }` | FR-024 |

---

## 6. Kiln Doctor Skill (`plugin/skills/kiln-doctor/SKILL.md`)

### Modifications Required

| Section | Change | FR |
|---------|--------|----|
| Step 1: Determine Mode | Add `--cleanup` mode (applies retention rules) with `--dry-run` support | FR-012 |
| New Step: Retention Cleanup | Read retention rules from manifest; apply `keep_last`, `archive_completed`, `purge_artifacts` | FR-012 |
| New Step: Version Sync Check | Scan version-bearing files, compare against `VERSION` | FR-015 |
| Fix mode: Version Sync | Auto-update mismatched version files to match `VERSION` | FR-016 |
| New Step: Version Sync Config | Read `.kiln/version-sync.json` for include/exclude lists | FR-017 |
| Fix mode: QA Cleanup | Integrate `/kiln-cleanup` behavior — purge stale QA artifacts | FR-014 |

---

## 7. New Skill: `/kiln-cleanup` (`plugin/skills/kiln-cleanup/SKILL.md`)

### File Contract

```yaml
name: kiln-cleanup
description: Remove stale QA artifacts from .kiln/qa/. Supports --dry-run for preview.
```

### Required Sections

| Section | Purpose | FR |
|---------|--------|----|
| Step 1: Parse Args | Support `--dry-run` flag | FR-013 |
| Step 2: Scan Artifacts | List files in `.kiln/qa/test-results/`, `playwright-report/`, `videos/`, `traces/` | FR-013 |
| Step 3: Purge or Preview | In dry-run: list files. Otherwise: delete files and report count/size freed | FR-013 |

---

## 8. Issue Template (`plugin/templates/issue.md`)

### New File Contract

Must contain the exact markdown structure currently hardcoded in `/report-issue`:

```markdown
---
title: "<title>"
type: <bug|friction|improvement|feature-request>
severity: <blocking|high|medium|low>
category: <skills|agents|hooks|templates|scaffold|workflow|other>
source: <retro|manual|github-issue|pipeline-run>
github_issue: <number or null>
status: open
date: YYYY-MM-DD
---

## Description

<Full description of the issue>

## Impact

<Who/what is affected and how>

## Suggested Fix

<Brief idea of what the fix looks like, if known. "TBD" is fine.>
```

| Contract | FR |
|----------|-----|
| Template file at `plugin/templates/issue.md` | FR-018 |
| `/report-issue` reads from template instead of hardcoding | FR-018 |
| `init.mjs` copies template to `.kiln/templates/issue.md` | FR-019 |

---

## 9. Report Issue Skill (`plugin/skills/report-issue/SKILL.md`)

### Modifications Required

| Section | Change | FR |
|---------|--------|----|
| Step 3: Create Backlog Entry | Read template from `plugin/templates/issue.md` (or consumer's `.kiln/templates/issue.md`) instead of hardcoding | FR-018 |
| Step 1: Parse Input scan path | Only scan top-level `.kiln/issues/` (not `completed/`) for duplicate detection | FR-025 |

---

## 10. Issue-to-PRD Skill (`plugin/skills/issue-to-prd/SKILL.md`)

### Modifications Required

| Section | Change | FR |
|---------|--------|----|
| Step 1: Read issues | Only read `.md` files in top-level `.kiln/issues/` (not `completed/` subdirectory) | FR-025 |

---

## 11. Scaffold Script (`plugin/bin/init.mjs`)

### Modifications Required

| Section | Change | FR |
|---------|--------|----|
| `scaffoldProject()` | Add `copyIfMissing` for issue template: `plugin/templates/issue.md` → `.kiln/templates/issue.md` | FR-019 |
| `scaffoldProject()` | Add `ensureDir` for `.kiln/templates/` | FR-019 |
| `scaffoldProject()` | Add `ensureDir` for `.kiln/issues/completed/` | FR-024 |

---

## 12. Spec Template (`plugin/templates/spec-template.md`)

### Modifications Required

| Section | Change | FR |
|---------|--------|----|
| User Scenarios comment block | Add: "If feature involves a rename/rebrand: include an FR for grep-based verification of ALL references" | FR-020 |
| User Scenarios comment block | Add: "Document credentials and auth flow required for QA testing" | FR-022 |

---

## 13. Plan Template (`plugin/templates/plan-template.md`)

### Modifications Required

| Section | Change | FR |
|---------|--------|----|
| Technical Context comment block | Add: "When depending on container CLI, add Phase 1 task to run `--help` and document results" | FR-021 |
| Technical Context comment block | Add: "For a11y features, run axe-core locally and fix all violations before committing" | FR-023 |

---

## 14. Issue Archival Logic

### Locations That Need Archival Behavior

| File | Change | FR |
|------|--------|----|
| `/report-issue` skill | When setting status to `closed`/`done`, move file to `.kiln/issues/completed/` | FR-024 |
| `/analyze-issues` skill | When closing an issue, move file to `.kiln/issues/completed/` | FR-024 |
| `/report-issue` skill | Scan only top-level `.kiln/issues/` for active items | FR-025 |
| `/issue-to-prd` skill | Scan only top-level `.kiln/issues/` for active items | FR-025 |

---

## 15. Version Sync Config (`.kiln/version-sync.json`)

### New File Contract (Optional — created by user)

```json
{
  "include": [
    "package.json",
    "plugin/package.json"
  ],
  "exclude": [
    "package-lock.json"
  ]
}
```

| Contract | FR |
|----------|-----|
| `/kiln-doctor` reads this file if it exists | FR-017 |
| If absent, defaults to scanning `package.json` and `plugin/package.json` | FR-017 |
