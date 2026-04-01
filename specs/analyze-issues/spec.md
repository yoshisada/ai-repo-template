# Feature Specification: Analyze Issues Skill

**Feature Branch**: `build/analyze-issues-20260401`  
**Created**: 2026-04-01  
**Status**: Draft  
**Input**: User description: "Analyze Issues skill (`/analyze-issues`) — a new kiln skill that reads all open GitHub issues, categorizes them, labels them, flags actionable ones, suggests closures, and offers backlog creation."

## User Scenarios & Testing

### User Story 1 - Triage Accumulated Issues (Priority: P1)

As a developer starting a session, I want to run `/analyze-issues` to quickly triage accumulated retrospective issues so I can act on the useful ones and close the rest.

**Why this priority**: This is the core value proposition. Without triage, retro findings go unreviewed and the issue list grows indefinitely.

**Independent Test**: Can be fully tested by running `/analyze-issues` on a repo with open issues and verifying each issue gets a category label and `analyzed` tag.

**Acceptance Scenarios**:

1. **Given** a repo with 14 open GitHub issues and no `analyzed` labels, **When** the user runs `/analyze-issues`, **Then** all 14 issues are read, categorized, labeled with their category (e.g., `category:skills`) and the `analyzed` tag, and a summary report is displayed.
2. **Given** a repo with 0 open issues, **When** the user runs `/analyze-issues`, **Then** the skill reports "no issues to analyze" and exits gracefully.
3. **Given** `gh` CLI is not available or not authenticated, **When** the user runs `/analyze-issues`, **Then** the skill displays a clear error message explaining the requirement and exits.

---

### User Story 2 - Skip Already-Analyzed Issues (Priority: P1)

As a developer running `/analyze-issues` a second time, I want already-analyzed issues to be skipped so I only review new issues.

**Why this priority**: Idempotency is essential for the skill to be usable in daily workflows without redundant processing.

**Independent Test**: Can be tested by running `/analyze-issues` twice and verifying the second run skips issues that already have the `analyzed` label.

**Acceptance Scenarios**:

1. **Given** a repo where 10 issues already have the `analyzed` label and 4 do not, **When** the user runs `/analyze-issues`, **Then** only the 4 unlabeled issues are processed.
2. **Given** all open issues already have the `analyzed` label, **When** the user runs `/analyze-issues`, **Then** the skill reports "no new issues to analyze" and exits.
3. **Given** previously analyzed issues exist, **When** the user runs `/analyze-issues --reanalyze`, **Then** all open issues are re-processed regardless of the `analyzed` label.

---

### User Story 3 - Flag Actionable Issues (Priority: P1)

As a developer reviewing retro findings, I want to see which issues contain actionable improvements with explanations of why they matter, so I can prioritize what to work on.

**Why this priority**: Identifying actionable issues is the primary decision-support function of the skill.

**Independent Test**: Can be tested by running the skill on issues containing bug reports and improvement suggestions, and verifying they are flagged with clear explanations.

**Acceptance Scenarios**:

1. **Given** an issue containing a concrete improvement suggestion (e.g., "add retry logic to webhook delivery"), **When** the skill analyzes it, **Then** it is flagged as actionable with a brief explanation of why it is worth acting on.
2. **Given** an issue that is purely informational (e.g., a build summary with no recommendations), **When** the skill analyzes it, **Then** it is NOT flagged as actionable.

---

### User Story 4 - Suggest and Close Issues (Priority: P2)

As a project maintainer, I want the skill to suggest closing informational, resolved, or stale issues and let me confirm before they are closed.

**Why this priority**: Reducing issue noise is valuable but secondary to identifying what matters.

**Independent Test**: Can be tested by running the skill on a mix of informational and actionable issues, verifying closure suggestions appear with reasons, and confirming that issues are only closed after user confirmation.

**Acceptance Scenarios**:

1. **Given** a purely informational issue with no actionable content, **When** the skill analyzes it, **Then** it is suggested for closure with a reason (e.g., "informational only, no action items").
2. **Given** the skill suggests 5 issues for closure, **When** the user is prompted, **Then** they can confirm individually or batch-close all suggested issues.
3. **Given** the user declines to close a suggested issue, **When** they respond "no", **Then** the issue remains open and is not modified further.

---

### User Story 5 - Create Backlog Items from Flagged Issues (Priority: P2)

As a developer, I want to create `.kiln/issues/` backlog items from selected flagged issues so actionable findings are tracked in the project backlog.

**Why this priority**: Converting findings to backlog items bridges the gap between analysis and action, but requires the flagging step first.

**Independent Test**: Can be tested by flagging issues, selecting some for backlog creation, and verifying `.kiln/issues/` entries are created via `/report-issue`.

**Acceptance Scenarios**:

1. **Given** 5 issues are flagged as actionable, **When** the user is offered to create backlog items, **Then** they can select which flagged issues to convert.
2. **Given** the user selects 3 of 5 flagged issues, **When** backlog creation runs, **Then** 3 `.kiln/issues/` entries are created via `/report-issue` with the issue content.

---

### User Story 6 - Category Filtering in GitHub UI (Priority: P3)

As a project maintainer, I want issues automatically labeled with their category so I can filter by area (skills, agents, hooks, etc.) in the GitHub UI.

**Why this priority**: Labeling is a side effect of analysis that improves long-term issue management but is not the primary workflow.

**Independent Test**: Can be tested by verifying that after analysis, issues have `category:*` labels and these labels are filterable in the GitHub issues UI.

**Acceptance Scenarios**:

1. **Given** an issue related to hook behavior, **When** the skill categorizes it, **Then** the label `category:hooks` is applied to the issue.
2. **Given** a category label (e.g., `category:skills`) does not yet exist in the repo, **When** the skill needs to apply it, **Then** the label is created automatically before being applied.

---

### Edge Cases

- What happens when GitHub API rate limits are hit? The skill should stop processing and report how many issues were completed vs. remaining.
- What happens when an issue has no body (title only)? The skill should categorize based on the title alone and note the limitation.
- What happens when the `--reanalyze` flag is passed but there are no open issues? Report "no issues to analyze" and exit.
- What happens when label creation fails (e.g., permission issues)? Report the error for that issue and continue processing remaining issues.
- What happens when the repo has more than 50 open issues? Process only the first 50 and report that the limit was reached.

## Requirements

### Functional Requirements

- **FR-001**: The skill MUST read all open GitHub issues from the current repo using `gh issue list`, limited to 50 issues per run.
- **FR-002**: For each issue, the skill MUST assign exactly one category from the set: `skills`, `agents`, `hooks`, `templates`, `scaffold`, `workflow`, `other`.
- **FR-003**: The skill MUST add a GitHub label `category:<name>` matching the assigned category to each issue. Labels MUST be created if they do not already exist.
- **FR-004**: The skill MUST add an `analyzed` label to each processed issue after analysis is complete.
- **FR-005**: On subsequent runs, the skill MUST skip issues that already have the `analyzed` label, unless the `--reanalyze` flag is passed.
- **FR-006**: The skill MUST flag issues containing actionable feedback (improvement suggestions, bug reports, process changes) and present each with a brief explanation of why the issue is worth acting on.
- **FR-007**: The skill MUST suggest issues to close when they are purely informational, already resolved, stale, or duplicative, providing a brief reason for each suggestion.
- **FR-008**: The skill MUST prompt the user for confirmation before closing any issue, offering both individual and batch close options.
- **FR-009**: The skill MUST offer to create `.kiln/issues/` backlog items from selected flagged issues by invoking `/report-issue` with the issue content.
- **FR-010**: The skill MUST display a summary report at the end showing: total issues analyzed, categories assigned, issues flagged as actionable, issues suggested for closure, issues closed, and backlog items created.
- **FR-011**: The skill MUST verify `gh` CLI availability and authentication before proceeding, displaying a clear error message if unavailable.
- **FR-012**: The skill MUST handle repos with 0 open issues by reporting "no issues to analyze" and exiting.

### Key Entities

- **Issue**: A GitHub issue with number, title, body, labels, and state. The primary input for analysis.
- **Category**: One of seven predefined backlog categories (skills, agents, hooks, templates, scaffold, workflow, other) assigned to each issue.
- **Label**: A GitHub issue label in the format `category:<name>` or `analyzed`, applied to issues after processing.
- **Backlog Item**: A `.kiln/issues/` file created from a flagged issue via `/report-issue`.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Running `/analyze-issues` on a repo with 14 open retro issues categorizes all 14 and labels each with both a category label and `analyzed`.
- **SC-002**: Flagged issues include a clear, specific reason explaining why they are actionable (not generic text).
- **SC-003**: Users can close suggested issues individually or in batch with a single confirmation step.
- **SC-004**: Running `/analyze-issues` a second time on the same repo processes 0 previously-analyzed issues (skips all).
- **SC-005**: Passing `--reanalyze` forces re-analysis of all open issues regardless of prior `analyzed` label.
- **SC-006**: The summary report accurately reflects all actions taken during the run.

## Assumptions

- The `gh` CLI is installed and authenticated in the user's environment (standard for kiln users).
- The repo uses GitHub Issues for tracking (not Jira, Linear, etc.).
- Issues are primarily retrospective/pipeline-generated issues; the categorization scheme (skills, agents, hooks, templates, scaffold, workflow, other) covers the expected issue types.
- The skill runs as a kiln skill (markdown + bash), not as a standalone script or compiled binary.
- Label creation requires sufficient GitHub permissions (write access to the repo).
- Up to 50 issues per run is sufficient for typical kiln repos.
