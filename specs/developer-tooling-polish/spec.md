# Feature Specification: Developer Tooling Polish

**Feature Branch**: `build/developer-tooling-polish-20260407`  
**Created**: 2026-04-07  
**Status**: Draft  
**Input**: User description: "Developer Tooling Polish — two skills: /wheel-list and /qa-audit"

## User Scenarios & Testing

### User Story 1 - Discover Available Workflows (Priority: P1)

As a developer using the wheel engine, I want to run `/wheel-list` and see all available workflows in my project so I can find the right one to run without manually browsing JSON files.

**Why this priority**: Workflow discoverability is a fundamental usability need. Without it, users must read raw JSON files to know what workflows exist, which slows adoption and makes the system feel incomplete.

**Independent Test**: Can be fully tested by placing workflow JSON files in `workflows/` and running `/wheel-list` — the output should display all workflows with accurate metadata.

**Acceptance Scenarios**:

1. **Given** a project with workflow JSON files in `workflows/`, **When** I run `/wheel-list`, **Then** I see a formatted table showing each workflow's name, step count, step types, and composition status.
2. **Given** workflows in both `workflows/` and `workflows/tests/`, **When** I run `/wheel-list`, **Then** workflows are grouped by directory with clear section headings.
3. **Given** a workflow with invalid JSON, **When** I run `/wheel-list`, **Then** the workflow appears in the list with an error indicator but does not cause the command to fail.
4. **Given** a project with no `workflows/` directory or no `.json` files in it, **When** I run `/wheel-list`, **Then** I see a helpful message suggesting `/wheel-create` to get started.

---

### User Story 2 - Audit Test Suite for Redundancy (Priority: P1)

As a pipeline operator, I want to run `/qa-audit` after a build to identify redundant or overlapping test scenarios so I can keep CI fast and test suites maintainable.

**Why this priority**: Test suites grow unchecked over time. Identifying duplication is essential for maintaining CI performance and developer productivity. Equal priority with US-1 since both are independent deliverables.

**Independent Test**: Can be fully tested by pointing `/qa-audit` at a project with 10+ test files containing intentional duplicates — the report should identify at least one overlapping pair.

**Acceptance Scenarios**:

1. **Given** a project with test files containing duplicate scenarios, **When** I run `/qa-audit`, **Then** I receive a prioritized report listing overlapping test pairs with estimated redundancy.
2. **Given** a project with test files, **When** I run `/qa-audit`, **Then** the audit report is written to `.kiln/qa/test-audit-report.md`.
3. **Given** a project with no test files, **When** I run `/qa-audit`, **Then** I see a message indicating no test files were found.

---

### User Story 3 - Prevent Test Bloat During Pipeline (Priority: P2)

As a QA engineer agent, I want to check new tests against existing ones before adding them, so I don't create overlapping test scenarios during the build pipeline.

**Why this priority**: This is an enhancement over US-2 — it integrates the audit into the active pipeline rather than running it standalone. It depends on the core audit capability from US-2 being built first.

**Independent Test**: Can be tested by running `/qa-audit` with integration mode during a pipeline build and verifying that findings are flagged to the implementer.

**Acceptance Scenarios**:

1. **Given** the QA engineer agent has generated new tests, **When** `/qa-audit` is invoked with pipeline integration, **Then** overlapping tests are flagged before test execution begins.

---

### Edge Cases

- What happens when workflow JSON files are deeply nested (e.g., `workflows/a/b/c/flow.json`)?
- How does the system handle workflow files with valid JSON but missing required fields (no `name`, no `steps`)?
- What happens when test files use non-standard extensions or naming conventions?
- How does the audit handle test files from multiple frameworks (Playwright + Vitest) in the same project?
- What happens when the `.kiln/qa/` directory does not exist when writing the audit report?

## Requirements

### Functional Requirements

#### Wheel List Skill

- **FR-001**: The `/wheel-list` skill MUST scan the `workflows/` directory (including subdirectories) for `.json` files and display results in a formatted list.
- **FR-002**: For each workflow, the skill MUST display: name, step count, step types used (command/agent/branch/loop/workflow), and whether it contains composition steps.
- **FR-003**: Workflows MUST be grouped by directory (e.g., `workflows/tests/` separate from `workflows/`).
- **FR-004**: The skill MUST show validation status for each workflow — indicating errors (invalid JSON, missing required fields, circular dependencies) without failing the overall list.
- **FR-005**: If no workflows exist, the skill MUST display a helpful message suggesting `/wheel-create`.

#### QA Test Audit

- **FR-006**: The `/qa-audit` skill MUST read all test files in the project and analyze them for overlap.
- **FR-007**: The skill MUST detect duplicate test scenarios — tests that exercise the same user flow or code path with identical or near-identical steps.
- **FR-008**: The skill MUST detect redundant assertions — multiple tests asserting the same state or response.
- **FR-009**: The skill MUST report findings as a prioritized list: which tests overlap, estimated redundancy percentage, and suggested consolidations.
- **FR-010**: The audit report MUST be written to `.kiln/qa/test-audit-report.md`.
- **FR-011**: The skill SHOULD optionally integrate into the QA engineer's workflow — running the audit after test generation but before execution, and flagging issues to the implementer.

## Success Criteria

### Measurable Outcomes

- **SC-001**: `/wheel-list` displays all workflows in a project with accurate step counts and type summaries, matching the actual workflow file contents.
- **SC-002**: `/qa-audit` identifies at least 1 redundant test pair in a project with 10+ test files containing overlapping scenarios.
- **SC-003**: Both skills work on existing projects with zero configuration — no setup steps required beyond having the plugin installed.
- **SC-004**: The QA audit report follows a consistent, parseable markdown format suitable for integration into pipeline feedback.
- **SC-005**: `/wheel-list` completes in under 5 seconds for projects with up to 50 workflow files.
- **SC-006**: Both skills handle edge cases gracefully — missing directories, invalid files, empty projects — without crashing or producing misleading output.

## Assumptions

- Projects using `/wheel-list` store workflow definitions as `.json` files in a `workflows/` directory at the repository root.
- The wheel engine's existing validation libraries (`plugin-wheel/lib/`) are available for reuse in validation checks.
- Test files follow common naming conventions (`*.test.*`, `*.spec.*`, `tests/`, `__tests__/`, `e2e/`) and the audit will detect files using these patterns.
- The primary test framework for v1 QA audit support is Playwright, with other frameworks (Vitest, Jest) supported via general heuristics.
- The `.kiln/qa/` directory may need to be created if it does not already exist.
- Workflow composition detection relies on step types already defined in the wheel engine schema (`workflow` type steps indicate composition).
