# Feature PRD: QA Agent Optimization, Kiln Doctor Enhancements & Template Improvements

**Date**: 2026-04-01
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)

## Background

Three areas of the kiln plugin have accumulated friction that compounds across pipeline runs. First, the QA agent is slow, tests too broadly, and sometimes evaluates stale builds — making QA the primary bottleneck in `/build-prd` pipelines. Second, the kiln-doctor skill lacks cleanup and version-sync capabilities, leaving stale artifacts and drifted versions for users to manage manually. Third, templates for issues and specs miss common patterns (rename verification, CLI discovery, auth docs), causing predictable rework every pipeline run.

These 10 backlog items share a common thread: they all reduce waste — wasted QA cycles, wasted disk space, wasted rework from template gaps.

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [QA engineer agent is too slow](.kiln/issues/2026-04-01-qa-engineer-performance.md) | — | friction | high |
| 2 | [Add hooks to enforce QA agent builds after every message](.kiln/issues/2026-04-01-qa-agent-build-after-message.md) | — | feature-request | high |
| 3 | [QA agent tests too broadly](.kiln/issues/2026-04-01-qa-agent-tests-too-broadly.md) | #20 | friction | medium |
| 4 | [Retrospective agent can't collect teammate feedback](.kiln/issues/2026-04-01-retrospective-agent-cant-collect-feedback.md) | #30, #28, #25, #16, #15 | friction | medium |
| 5 | [Enable kiln-doctor to clean up .kiln subfolders](.kiln/issues/2026-04-01-kiln-doctor-cleanup.md) | — | feature-request | medium |
| 6 | [Add version file sync check to kiln-doctor](.kiln/issues/2026-04-01-kiln-doctor-version-sync.md) | — | feature-request | medium |
| 7 | [Add /kiln-cleanup command to purge QA artifacts](.kiln/issues/2026-04-01-kiln-cleanup-qa-command.md) | — | feature-request | medium |
| 8 | [Create a better template for issue submission](.kiln/issues/2026-04-01-better-issue-template.md) | — | improvement | medium |
| 9 | [Spec/PRD templates miss common requirements](.kiln/issues/2026-04-01-spec-prd-templates-miss-common-requirements.md) | #22, #23, #17, #18 | friction | medium |
| 10 | [Move completed issues to a completed folder](.kiln/issues/2026-04-01-archive-completed-issues.md) | — | improvement | medium |

## Problem Statement

The QA agent is the biggest bottleneck in the kiln pipeline. It records video for every test (not just failures), runs viewports serially, uses slow `networkidle` waits, and tests the entire site instead of scoping to the feature under development. It also sometimes evaluates stale builds because there's no hook enforcing a rebuild after receiving implementer messages. Meanwhile, the retrospective agent can never collect live feedback because teammates have already shut down by the time it runs.

On the tooling side, kiln-doctor can diagnose structural problems but can't clean up accumulated artifacts or detect version drift across package manifests. QA artifacts (videos, traces, reports) pile up with no automated purge. And the templates that drive spec/PRD generation miss four common patterns that cause rework in nearly every pipeline run: rename grep verification, container CLI discovery, QA auth documentation, and local a11y validation.

## Goals

- Reduce QA agent wall-clock time by 3x+ through parallel viewports, failure-only recording, and targeted waits
- Scope QA testing to the feature under development by default, with optional regression
- Ensure QA always tests against the latest build via hook enforcement
- Enable the retrospective agent to collect agent friction data even after teammates shut down
- Add cleanup and version-sync capabilities to kiln-doctor
- Create a dedicated `/kiln-cleanup` command for QA artifact purging
- Extract issue template to a customizable file and add common-requirement checklists to spec/PRD templates
- Implement issue archival to keep the active backlog clean

## Non-Goals

- Rewriting the QA agent from scratch — this is optimization, not replacement
- Adding new QA test types (visual regression, performance) — out of scope
- Changing the core kiln-doctor manifest schema — we're adding checks, not restructuring
- Automating issue triage or prioritization — that's `/analyze-issues` territory

## Requirements

### Functional Requirements

**QA Agent Performance (high priority)**

- **FR-001** (from: qa-engineer-performance.md): Update QA agent and `/qa-setup` scaffold to default Playwright config to `video: 'retain-on-failure'` and `trace: 'retain-on-failure'` instead of `'on'`
- **FR-002** (from: qa-engineer-performance.md): Set `fullyParallel: true` in the scaffolded Playwright config so desktop, tablet, and mobile viewports run concurrently
- **FR-003** (from: qa-engineer-performance.md): Update QA agent instructions to prefer `waitForSelector`/`waitForFunction` over `networkidle`, and prohibit hardcoded `waitForTimeout` calls
- **FR-004** (from: qa-engineer-performance.md): Add a final walkthrough recording step that captures one clean run of new features after all tests pass

**QA Build Enforcement (high priority)**

- **FR-005** (from: qa-agent-build-after-message.md): Add a `SubagentStart` hook (matcher: `qa-engineer`) that injects `additionalContext` requiring the QA agent to run the project build command after every `SendMessage` it receives
- **FR-006** (from: qa-agent-build-after-message.md): Add a `TeammateIdle` prompt hook that blocks the QA agent from going idle if it hasn't run a build since its last received message

**QA Scope (medium priority)**

- **FR-007** (from: qa-agent-tests-too-broadly.md): Update QA agent to focus on the feature's test matrix first, reporting feature pass/fail as a standalone section before any regression findings
- **FR-008** (from: qa-agent-tests-too-broadly.md): Structure QA reports into two sections: (1) Feature Verdict (scoped pass/fail) and (2) Regression Findings (optional, only when feature touches shared components or explicitly requested)

**Retrospective Agent Feedback Collection (medium priority)**

- **FR-009** (from: retrospective-agent-cant-collect-feedback.md): Before each pipeline agent shuts down, it must write a friction note to `specs/<feature>/agent-notes/<agent-name>.md` documenting what was confusing, where it got stuck, and what could be improved
- **FR-010** (from: retrospective-agent-cant-collect-feedback.md): Update the retrospective agent to read `specs/<feature>/agent-notes/` instead of relying on live `SendMessage` feedback from teammates

**Kiln Doctor Cleanup (medium priority)**

- **FR-011** (from: kiln-doctor-cleanup.md): Add retention/cleanup rules to the kiln manifest (e.g., `logs: keep_last: 10`, `issues: archive_completed: true`)
- **FR-012** (from: kiln-doctor-cleanup.md): Add a `--cleanup` flag to `/kiln-doctor` that applies manifest retention rules, with `--dry-run` support for previewing changes
- **FR-013** (from: kiln-cleanup-qa-command.md): Create a `/kiln-cleanup` skill that removes stale QA artifacts from `.kiln/qa/` (test-results, playwright-report, videos, traces), with `--dry-run` support
- **FR-014** (from: kiln-cleanup-qa-command.md): Integrate `/kiln-cleanup` into `/kiln-doctor` fix mode so `kiln-doctor --fix` also purges stale QA artifacts

**Kiln Doctor Version Sync (medium priority)**

- **FR-015** (from: kiln-doctor-version-sync.md): Add a version-sync check to `/kiln-doctor` that scans for common version-bearing files (`package.json`, `*.toml`, `*.cfg`, `*.yaml`) and compares each version against the canonical `VERSION` file
- **FR-016** (from: kiln-doctor-version-sync.md): In fix mode, automatically update mismatched version files to match `VERSION`
- **FR-017** (from: kiln-doctor-version-sync.md): Support an optional `.kiln/version-sync.json` config declaring which files should track `VERSION` (opt-in additional files, exclude false positives)

**Templates (medium priority)**

- **FR-018** (from: better-issue-template.md): Extract the issue markdown structure from `/report-issue` into `plugin/templates/issue.md` and update the skill to read from the template
- **FR-019** (from: better-issue-template.md): Have `init.mjs` scaffold the issue template into consumer projects so they can customize it
- **FR-020** (from: spec-prd-templates-miss-common-requirements.md): Add a rename/rebrand checklist to PRD/spec templates: "Include an FR for grep-based verification of ALL references"
- **FR-021** (from: spec-prd-templates-miss-common-requirements.md): Add a container CLI discovery task to plan templates: "When depending on container CLI, add Phase 1 task to run `--help` and document results"
- **FR-022** (from: spec-prd-templates-miss-common-requirements.md): Add QA auth documentation to spec templates: "Document credentials and auth flow required for QA testing"
- **FR-023** (from: spec-prd-templates-miss-common-requirements.md): Add local validation guidance to plan templates: "For a11y features, run axe-core locally and fix all violations before committing"

**Issue Archival (medium priority)**

- **FR-024** (from: archive-completed-issues.md): When an issue status is set to `closed` or `done`, move the file to `.kiln/issues/completed/`
- **FR-025** (from: archive-completed-issues.md): Update `/report-issue` and `/issue-to-prd` to only scan top-level `.kiln/issues/` (not `completed/`) for active items

### Non-Functional Requirements

- **NFR-001**: QA agent performance improvements should not reduce test reliability — `retain-on-failure` must still capture full video/trace on any failure
- **NFR-002**: Kiln-doctor cleanup must never delete files without user confirmation (fix mode) or explicit `--cleanup` flag
- **NFR-003**: Version-sync checks must have zero false positives — only scan files that actually contain version strings matching the expected format
- **NFR-004**: Template changes must be backwards-compatible — existing consumer projects using old templates should not break

## User Stories

- As a **pipeline operator**, I want QA to run 3x faster so the feedback loop between implementers and QA stays tight during `/build-prd`
- As a **pipeline operator**, I want QA to always test against the latest build so false failures from stale artifacts stop wasting cycles
- As a **feature developer**, I want QA reports to clearly separate feature-specific results from sitewide regression findings so I can quickly see if my feature passes
- As a **plugin maintainer**, I want kiln-doctor to clean up stale artifacts and detect version drift so I don't manage these manually
- As a **consumer project developer**, I want the issue template and spec/PRD templates to prompt for commonly-missed requirements so my pipeline runs don't hit the same gaps repeatedly
- As a **backlog triager**, I want completed issues archived out of the active folder so scanning for actionable work is fast

## Success Criteria

- QA agent pipeline runtime decreases by at least 50% compared to current baseline (serial viewports, always-on recording)
- Zero instances of QA testing stale builds when build-enforcement hooks are active
- QA reports in `/build-prd` runs clearly separate feature verdict from regression findings
- Retrospective agent has access to agent friction notes in 100% of pipeline runs
- `kiln-doctor` detects version mismatches and stale artifacts in diagnose mode, fixes them in fix mode
- `/kiln-cleanup` successfully purges QA artifacts with dry-run preview
- Issue template is externalized and customizable by consumer projects
- Spec/PRD templates include the four new checklist items (rename grep, CLI discovery, QA auth, local a11y validation)
- Completed issues are automatically archived to `completed/` subdirectory

## Tech Stack

- Markdown (skill/agent definitions)
- Bash (hook scripts, shell commands within skills)
- Node.js (init.mjs scaffold updates)
- JSON (hooks.json, version-sync.json, manifest additions)
- Playwright (QA config changes)

## Risks & Open Questions

1. **`TeammateIdle` hook feasibility**: The `TeammateIdle` event type may not be supported by Claude Code's hook system yet. Need to verify available hook event types before implementing FR-006.
2. **Agent-notes directory pollution**: FR-009 creates a new `agent-notes/` directory per feature. Should these be cleaned up automatically, or left as permanent records?
3. **Version-sync false positives**: Files like `package-lock.json` contain version strings but shouldn't be directly edited. The allowlist/blocklist approach in FR-017 needs careful defaults.
4. **Template backwards compatibility**: Adding new checklist sections to templates could confuse the specify/plan skills if they expect the old format. Skills may need minor updates to handle new sections gracefully.
