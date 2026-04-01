# Feature Specification: Continuance Agent (/next)

**Feature Branch**: `build/continuance-agent-20260331`
**Created**: 2026-03-31
**Status**: Draft
**Input**: User description: "Continuance agent (/next) that analyzes full project state after build-prd and at session start, produces prioritized next steps mapped to kiln commands, replaces /resume"

## User Scenarios & Testing

### User Story 1 - Post-Build Pipeline Guidance (Priority: P1)

As a developer who just finished a `/build-prd` run, I want to see a prioritized list of next steps so I know exactly what to work on without manually reviewing every artifact produced during the build.

**Why this priority**: This is the core value proposition. After a build-prd completes, the developer faces a retrospective, audit results, QA findings, and possibly open blockers scattered across multiple files. Without automated guidance, critical items fall through the cracks and the developer wastes time manually triaging.

**Independent Test**: Run `/build-prd` on a project with known incomplete tasks, QA failures, and open blockers. Verify the continuance agent produces a prioritized list that surfaces all open items and maps each to a concrete kiln command.

**Acceptance Scenarios**:

1. **Given** a `/build-prd` pipeline has just completed with a retrospective, audit results, and QA findings, **When** the continuance agent runs as the final pipeline step, **Then** it produces a prioritized list of next steps covering all open gaps found across the build artifacts.
2. **Given** the build produced blockers documented in `blockers.md`, **When** the continuance agent analyzes the project state, **Then** blockers appear at the top of the recommendation list with "critical" priority.
3. **Given** the build completed with all tasks done and all tests passing, **When** the continuance agent runs, **Then** it reports the project is in good shape and suggests only low-priority improvements or backlog items.
4. **Given** the continuance agent runs at the end of `/build-prd`, **When** it completes, **Then** a summary of the top recommendations is printed in the terminal as part of the build-prd output.

---

### User Story 2 - Session Start State Recovery (Priority: P1)

As a developer starting a new session, I want to run `/next` and immediately understand the full project state and what needs attention so I can resume productive work without manually checking multiple files.

**Why this priority**: This replaces the existing `/resume` skill. Every session start is an opportunity to lose context. Providing a comprehensive, prioritized view of project state eliminates the cold-start problem and ensures nothing is forgotten between sessions.

**Independent Test**: Start a fresh session in a project with in-progress work (incomplete tasks, open issues, QA failures). Run `/next` and verify it surfaces all open items with actionable commands.

**Acceptance Scenarios**:

1. **Given** a project with incomplete tasks in `tasks.md`, open GitHub issues, and QA failures, **When** the developer runs `/next` at the start of a session, **Then** they receive a prioritized list of all open items with the exact kiln command to address each one.
2. **Given** a project with no open work items, **When** the developer runs `/next`, **Then** it reports the project is up to date and suggests checking the backlog or starting a new feature.
3. **Given** the developer runs `/next` with the `--brief` flag, **When** results are generated, **Then** only the top 5 recommendations are shown and no report file is saved to disk.
4. **Given** the developer previously used `/resume`, **When** they run `/resume` in the new system, **Then** it runs `/next` with a deprecation notice informing them to use `/next` going forward.

---

### User Story 3 - Actionable Command Mapping (Priority: P1)

As a developer reviewing next steps, I want every recommendation to include the exact kiln command to execute so I can act immediately without figuring out which command addresses each issue.

**Why this priority**: Recommendations without actionable commands create friction. The developer has to map each finding to the right kiln command themselves, which defeats the purpose of automated guidance.

**Independent Test**: Generate a continuance report for a project with diverse open items (bugs, incomplete tasks, QA gaps, backlog items). Verify every single recommendation includes a valid kiln command or specific manual action sequence.

**Acceptance Scenarios**:

1. **Given** an incomplete task in `tasks.md`, **When** the continuance agent generates a recommendation for it, **Then** the recommendation includes `/implement` as the command to run.
2. **Given** a failing test from QA results, **When** the continuance agent generates a recommendation, **Then** it includes `/fix` with a description of the issue, or `/qa-pass` if a full re-test is needed.
3. **Given** a retrospective action item about process improvement, **When** the continuance agent generates a recommendation, **Then** it maps to a concrete command sequence (e.g., `/specify` for a new feature, or a specific file edit).
4. **Given** any recommendation in the list, **When** the developer reads it, **Then** it contains a one-line description, the kiln command, a priority level (critical/high/medium/low), and the source reference.

---

### User Story 4 - Persistent Report for Review and Sharing (Priority: P2)

As a developer working on a team, I want the continuance analysis saved to disk so I can reference it later or share it with teammates who weren't present during the session.

**Why this priority**: Terminal output is ephemeral. Persisting the report enables async team workflows, historical tracking, and auditability of what was recommended versus what was done.

**Independent Test**: Run `/next` and verify a detailed report file is created at the expected path with the full analysis, all recommendations, and source references.

**Acceptance Scenarios**:

1. **Given** the continuance agent completes its analysis, **When** the report is generated, **Then** a detailed markdown file is saved to `.kiln/logs/next-<YYYY-MM-DD-HHmmss>.md` with the full analysis.
2. **Given** the `--brief` flag is used, **When** the analysis completes, **Then** no report file is saved to disk and only terminal output is produced.
3. **Given** a report was saved in a previous session, **When** the developer navigates to `.kiln/logs/`, **Then** they can find and read the historical report.

---

### User Story 5 - Automatic Backlog Gap Discovery (Priority: P2)

As a developer, I want the continuance agent to automatically create backlog entries for gaps it discovers that aren't already tracked so that nothing falls through the cracks between sessions.

**Why this priority**: Discovered gaps that aren't recorded are forgotten. Auto-creating backlog entries bridges the gap between analysis and tracking, ensuring every finding has a persistent record.

**Independent Test**: Run `/next` on a project that has QA failures not yet tracked in `.kiln/issues/`. Verify new issue files are created for untracked gaps with the `[auto:continuance]` tag, and that existing tracked issues are not duplicated.

**Acceptance Scenarios**:

1. **Given** the agent discovers a gap not tracked in `.kiln/issues/`, **When** it finishes analysis, **Then** a new issue file is created in `.kiln/issues/` with the naming convention `<YYYY-MM-DD>-<slug>.md` and tagged `[auto:continuance]`.
2. **Given** a gap is already tracked by an existing issue in `.kiln/issues/`, **When** the agent encounters the same gap, **Then** it does not create a duplicate issue.
3. **Given** duplicate detection is uncertain, **When** the agent cannot confidently determine if a gap is already tracked, **Then** it creates the issue (preferring false positives over missed items).

---

### Edge Cases

- What happens when the project has no specs, no PRD, and no code? The agent should detect the "fresh project" state and recommend starting with a PRD.
- What happens when GitHub CLI is not available or not authenticated? The agent should skip GitHub-dependent sources (issues, PR comments) gracefully and note them as skipped in the report.
- What happens when `.kiln/issues/` does not exist yet? The agent should create the directory before writing issue files.
- What happens when the project has dozens of open items? The terminal summary is capped at 15 items; the full report contains all items.
- What happens when `/next` is run twice in quick succession with no state change? The output should be identical (idempotent).
- What happens when `specs/` contains multiple features at different stages? The agent should analyze all features and report on each.

## Requirements

### Functional Requirements

- **FR-001**: The continuance agent MUST review all available project state sources: `specs/*/tasks.md` (incomplete tasks), `specs/*/blockers.md`, `specs/*/retrospective.md`, QA results, audit findings, `.kiln/issues/`, GitHub issues, GitHub PR comments, and `specs/*/spec.md` (unimplemented FRs).
- **FR-002**: The agent MUST produce a prioritized recommendation list ordered by: blockers first, then incomplete work, then QA/audit gaps, then backlog items, then improvements.
- **FR-003**: Each recommendation MUST include a one-line description, the kiln command to execute, a priority level (critical/high/medium/low), and a source reference identifying which artifact surfaced the item.
- **FR-004**: The agent MUST produce a terminal summary of at most 15 items grouped by priority level.
- **FR-005**: The agent MUST save a detailed markdown report to `.kiln/logs/next-<YYYY-MM-DD-HHmmss>.md` containing the full analysis, all recommendations, and source references.
- **FR-006**: When the `--brief` flag is provided, the agent MUST output only the top 5 recommendations and MUST NOT save a report file.
- **FR-007**: The agent MUST create new issue files in `.kiln/issues/` for discovered gaps not already tracked, using the naming convention `<YYYY-MM-DD>-<slug>.md` and tagging them with `[auto:continuance]`.
- **FR-008**: The agent MUST NOT create duplicate issues when a matching issue already exists in `.kiln/issues/` (matched by title/description similarity).
- **FR-009**: The `/next` skill MUST replace `/resume` as the primary session-start command.
- **FR-010**: The `/resume` skill MUST continue to function as a deprecated alias that invokes `/next` with a deprecation notice.
- **FR-011**: The continuance agent MUST run automatically as the final step of every `/build-prd` pipeline, after the retrospective agent completes.
- **FR-012**: Every recommendation MUST map to a valid kiln command or a specific manual action sequence. Vague suggestions like "review the code" are prohibited.
- **FR-013**: Running `/next` twice in the same project state MUST produce the same recommendations (idempotent).
- **FR-014**: When GitHub CLI is unavailable or unauthenticated, the agent MUST skip GitHub-dependent sources gracefully and note the skipped sources in the report.
- **FR-015**: The agent MUST NOT auto-execute any suggested commands. It recommends only; the user decides.

### Key Entities

- **Recommendation**: A single next-step item containing a description, kiln command, priority level, and source reference.
- **Continuance Report**: A persistent markdown file containing the full analysis, all recommendations, and metadata (timestamp, project state snapshot).
- **Backlog Issue**: An auto-created issue file in `.kiln/issues/` tagged with `[auto:continuance]` representing a discovered gap.

## Success Criteria

### Measurable Outcomes

- **SC-001**: 90% or more of recommendations in any given report map to a concrete, valid kiln command — verified by sampling reports and checking command validity against the available command list.
- **SC-002**: The agent surfaces all open gaps with zero missed blockers, incomplete tasks, or unaddressed QA findings — verified by cross-referencing the report against the actual project state.
- **SC-003**: Developers can understand the project state and identify their next action within 30 seconds of reading the terminal summary.
- **SC-004**: Running `/next` at the start of a session replaces the need to manually check more than 3 separate artifact files.
- **SC-005**: Auto-created backlog issues have less than 10% duplication rate against existing tracked issues.

## Assumptions

- The retrospective agent in `/build-prd` produces a `retrospective.md` file with structured content (headings, action items) that can be parsed by the continuance agent.
- GitHub CLI (`gh`) is installed and authenticated in environments where GitHub issue/PR integration is expected to work. When unavailable, those sources are skipped.
- `.kiln/issues/` follows a consistent file naming convention (`<YYYY-MM-DD>-<slug>.md`) and content format that the agent can parse for deduplication.
- The existing `/resume` skill's functionality is a strict subset of what `/next` provides, making the replacement non-disruptive.
- The kiln plugin structure supports adding new skills and agents as markdown files without requiring build steps or configuration changes beyond the file creation itself.
- QA results are stored in `.kiln/qa/` in a parseable format (markdown reports, Playwright JSON output).
