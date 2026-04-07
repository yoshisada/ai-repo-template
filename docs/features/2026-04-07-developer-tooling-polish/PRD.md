# Feature PRD: Developer Tooling Polish

**Date**: 2026-04-07
**Status**: Draft

## Parent Product

[Kiln Plugin](../../PRD.md) — spec-first development workflow plugin for Claude Code. This feature addresses two tooling gaps: workflow discoverability in the wheel engine, and QA test efficiency auditing.

## Background

Two independent backlog items surfaced workflow friction:

1. **Wheel workflow discovery**: Users have no built-in way to see what workflows are available. They must manually browse `workflows/` and read JSON files. Every task runner has a `list` command — wheel needs one too.

2. **QA test redundancy**: The QA engineer agent generates and runs tests but never audits the test suite itself. Tests accumulate overlapping scenarios over time, wasting CI cycles and making suites harder to maintain. A test audit step would catch duplication during the pipeline.

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [Add wheel-list skill](.kiln/issues/2026-04-04-wheel-list-skill.md) | — | feature-request | medium |
| 2 | [QA test dedup/efficiency audit](.kiln/issues/2026-04-07-qa-engineer-test-dedup-efficiency.md) | — | improvement | medium |

## Problem Statement

Developers using the wheel engine cannot discover available workflows without reading raw JSON files. This slows adoption and makes the workflow system feel incomplete. Meanwhile, QA test suites grow unchecked — the QA engineer generates tests for each feature but never consolidates or deduplicates them, leading to slow CI runs and redundant coverage.

## Goals

- Provide a single command to list all available workflows with names, step counts, and types
- Add a QA test audit capability that identifies overlapping or redundant tests
- Both features should work with zero configuration on existing projects

## Non-Goals

- Workflow editing or deletion via CLI (just listing)
- Auto-fixing or auto-merging redundant tests (just reporting)
- Test coverage analysis (that's a separate concern — this is about test-to-test overlap)
- Workflow search or filtering (v1 is a flat list)

## Target Users

- **Workflow authors** who need to see what's already available before creating new workflows
- **Pipeline operators** who want to audit QA test efficiency after builds

## Functional Requirements

### Wheel List Skill

- **FR-001** (from: wheel-list-skill.md): A `/wheel-list` skill that scans `workflows/` directory (including subdirectories) for `.json` files and displays results.
- **FR-002** (from: wheel-list-skill.md): For each workflow, display: name, step count, step types used (command/agent/branch/loop/workflow), and whether it contains composition steps.
- **FR-003** (from: wheel-list-skill.md): Group workflows by directory (e.g., `workflows/tests/` separate from `workflows/`).
- **FR-004** (from: wheel-list-skill.md): Show validation status — indicate if a workflow has errors (invalid JSON, missing refs, circular deps) without failing the list.
- **FR-005** (from: wheel-list-skill.md): If no workflows exist, display a helpful message suggesting `/wheel-create`.

### QA Test Audit

- **FR-006** (from: qa-test-dedup.md): Add a `/qa-audit` skill that reads all test files in the project and analyzes them for overlap.
- **FR-007** (from: qa-test-dedup.md): Detect duplicate test scenarios — tests that exercise the same user flow or code path with identical or near-identical steps.
- **FR-008** (from: qa-test-dedup.md): Detect redundant assertions — multiple tests asserting the same DOM state or API response.
- **FR-009** (from: qa-test-dedup.md): Report findings as a prioritized list: which tests overlap, estimated redundancy percentage, and suggested consolidations.
- **FR-010** (from: qa-test-dedup.md): Output the audit report to `.kiln/qa/test-audit-report.md`.
- **FR-011** (from: qa-test-dedup.md): Optionally integrate into the QA engineer's workflow — run the audit after test generation but before execution, and flag issues to the implementer.

## User Stories

### US-1: Discover Workflows
As a developer, I want to run `/wheel-list` and see all available workflows so I can find the right one to run without browsing files.

### US-2: Audit Test Efficiency
As a pipeline operator, I want to run `/qa-audit` after a build to identify redundant tests so I can keep CI fast and test suites maintainable.

### US-3: Prevent Test Bloat
As a QA engineer agent, I want to check new tests against existing ones before adding them, so I don't create overlapping test scenarios.

## Success Criteria

1. `/wheel-list` displays all workflows with accurate step counts and type summaries
2. `/qa-audit` identifies at least 1 redundant test pair in a project with 10+ test files
3. Both skills work on existing projects with zero configuration
4. QA audit report is machine-readable for integration into pipeline feedback

## Tech Stack

Inherited from kiln/wheel plugins — no additions needed:
- Bash 5.x (wheel-list validation via engine libs)
- Markdown (skill definitions)
- jq (JSON parsing for workflow files)

## Absolute Musts

1. **Tech stack**: Bash 5.x + jq + Markdown skills (no new dependencies)
2. Existing workflows and QA tests must not be modified
3. Both skills are read-only — they report, they don't change files (except writing the audit report)

## Risks & Open Questions

- **QA audit accuracy**: Detecting "overlapping" tests requires semantic understanding of what each test does. Simple heuristics (same selectors, same URLs) may produce false positives. Start with conservative matching.
- **Test framework diversity**: Projects may use Playwright, Vitest, Jest, or others. The audit needs to handle at least Playwright (primary QA framework) in v1.
- Should `/qa-audit` run automatically as part of `/qa-pipeline`, or only on-demand? (Leaning on-demand for v1.)
