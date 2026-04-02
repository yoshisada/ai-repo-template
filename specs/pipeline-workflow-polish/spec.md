# Feature Specification: Pipeline Workflow Polish

**Feature Branch**: `build/pipeline-workflow-polish-20260401`  
**Created**: 2026-04-01  
**Status**: Draft  
**Input**: User description: "Pipeline Workflow Polish — 16 FRs from PRD at docs/features/2026-04-01-pipeline-workflow-polish/PRD.md covering: non-compiled validation gate, branch and spec directory naming enforcement, issue lifecycle auto-completion, /kiln-cleanup extension, /kiln-doctor stale issue detection, commit noise reduction, roadmap.md scaffold and /roadmap skill, and /next integration with roadmap items."

## User Scenarios & Testing

### User Story 1 - Non-Compiled Feature Validation (Priority: P1)

A plugin maintainer edits markdown skill definitions, bash hook scripts, or scaffold templates. When they reach the validation gate at the end of `/implement`, the pipeline runs structural checks instead of the 80% coverage gate — verifying frontmatter validity, bash syntax, file reference integrity, and scaffold output. The maintainer gets a clear pass/fail report showing what was validated.

**Why this priority**: The majority of changes in the plugin repo are non-compiled. Without this gate, an entire class of deliverables ships with zero automated verification — broken bash snippets, invalid frontmatter, and dead file references go undetected.

**Independent Test**: Can be tested by modifying a markdown skill file with intentional errors (bad frontmatter, broken bash, dead file reference) and verifying the validation gate catches each error type.

**Acceptance Scenarios**:

1. **Given** a feature branch with only markdown/bash changes (no `src/` edits), **When** `/implement` reaches the validation gate, **Then** the non-compiled validation runs instead of the 80% coverage check
2. **Given** a skill SKILL.md file with a bash code block containing a syntax error, **When** the validation gate runs, **Then** the error is reported with the file name and line reference
3. **Given** a markdown file referencing `plugin/agents/nonexistent.md`, **When** the validation gate runs, **Then** the broken reference is flagged
4. **Given** all modified files pass validation, **When** the validation gate completes, **Then** `init.mjs` is executed in a temp directory to verify scaffold output
5. **Given** a completed validation run, **When** the auditor generates the PR checklist, **Then** the validation results (what was checked and pass/fail) are included as evidence

---

### User Story 2 - Branch and Spec Directory Naming Enforcement (Priority: P1)

A pipeline operator runs `/build-prd` to build a feature. The team lead automatically creates a branch named `build/<feature-slug>-<YYYYMMDD>` from the current HEAD and a spec directory matching `specs/<feature-slug>/`. All agents receive the canonical branch name and spec path at spawn time, eliminating filesystem globbing and cross-feature pollution.

**Why this priority**: Inconsistent naming has been observed in at least 5 pipeline runs, causing agents to waste time searching for spec files and PRs to include commits from unrelated features.

**Independent Test**: Can be tested by running `/build-prd` and verifying the branch name matches the pattern, the spec directory matches the slug, and all agent spawn messages include the canonical paths.

**Acceptance Scenarios**:

1. **Given** a user runs `/build-prd`, **When** the team lead creates the feature branch, **Then** the branch name follows `build/<feature-slug>-<YYYYMMDD>` exactly
2. **Given** a `/build-prd` run, **When** the spec directory is created, **Then** it is named `specs/<feature-slug>/` with no numeric prefixes
3. **Given** a `/build-prd` run, **When** agents are spawned, **Then** each agent's spawn message includes the canonical branch name and spec directory path
4. **Given** an existing feature branch with the same slug, **When** `/build-prd` starts, **Then** a fresh branch is created from current HEAD (not reused)

---

### User Story 3 - Issue Lifecycle Auto-Completion (Priority: P2)

After a successful `/build-prd` run creates a PR, the pipeline scans `.kiln/issues/` for entries with `status: prd-created` whose `prd:` field matches the PRD that was just built. These issues are automatically updated to `status: completed` with the PR link and completion date. If issue archival is available, completed issues are moved to `.kiln/issues/completed/`.

**Why this priority**: Issues currently stall at `prd-created` status indefinitely, accumulating noise in the active backlog. Automating the transition keeps the backlog clean without manual intervention.

**Independent Test**: Can be tested by creating a `.kiln/issues/` entry with `status: prd-created` and a matching `prd:` field, running a simulated pipeline completion, and verifying the status updates and archival.

**Acceptance Scenarios**:

1. **Given** issues in `.kiln/issues/` with `status: prd-created` matching the built PRD, **When** the pipeline creates a PR, **Then** those issues are updated to `status: completed` with `completed_date` and `pr` fields
2. **Given** issues with `status: prd-created` that do NOT match the built PRD, **When** the pipeline completes, **Then** those issues are left unchanged
3. **Given** the issue archival directory exists (`.kiln/issues/completed/`), **When** issues are marked completed, **Then** they are moved to the completed directory

---

### User Story 4 - Issue and Artifact Cleanup (Priority: P2)

A pipeline operator runs `/kiln-cleanup` to tidy up the project. In addition to purging QA artifacts, the command now scans `.kiln/issues/` for completed and stale `prd-created` issues and archives them to `.kiln/issues/completed/`. A `--dry-run` flag shows what would be archived without moving anything. Running `/kiln-doctor` reports stale `prd-created` issues as diagnostic findings.

**Why this priority**: Without cleanup automation, completed issues accumulate indefinitely in the active backlog, making it harder to identify actionable items.

**Independent Test**: Can be tested by placing completed and prd-created issue files in `.kiln/issues/`, running `/kiln-cleanup --dry-run` to verify the report, then running without `--dry-run` to verify archival.

**Acceptance Scenarios**:

1. **Given** `.kiln/issues/` contains issues with `status: completed`, **When** `/kiln-cleanup` runs, **Then** those issues are moved to `.kiln/issues/completed/`
2. **Given** `.kiln/issues/` contains issues with `status: prd-created`, **When** `/kiln-cleanup` runs, **Then** those issues are also archived
3. **Given** the `--dry-run` flag is passed, **When** `/kiln-cleanup` runs, **Then** it reports what would be archived without moving any files
4. **Given** stale `prd-created` issues exist, **When** `/kiln-doctor` runs, **Then** it reports them as a diagnostic finding

---

### User Story 5 - Commit Noise Reduction (Priority: P3)

A feature developer works on a single-phase feature. The version-increment hook stages its changes in-place for inclusion in the next commit rather than requiring a separate chore commit. Task-marking updates (`[X]` in tasks.md) are combined into phase commits. QA result snapshots are not committed to the feature branch. The result is significantly fewer commits for small features.

**Why this priority**: While annoying, commit noise is cosmetic and does not block any functionality. It becomes more impactful as the project scales and PR review burden grows.

**Independent Test**: Can be tested by implementing a single-phase feature and counting the resulting commits, comparing against the current baseline.

**Acceptance Scenarios**:

1. **Given** a code file is edited, **When** the version-increment hook fires, **Then** it modifies VERSION in-place and stages the change for inclusion in the next commit (no separate chore commit)
2. **Given** a single-phase feature, **When** `/implement` marks tasks as `[X]`, **Then** the task-marking changes are included in the phase commit rather than separate commits
3. **Given** a `/build-prd` run, **When** QA agents produce result snapshots, **Then** those files are NOT committed to the feature branch

---

### User Story 6 - Roadmap Tracking and /next Integration (Priority: P3)

A user captures a future work idea by running `/roadmap Add support for monorepo projects`. The item is appended to `.kiln/roadmap.md` under the appropriate theme group. When the user runs `/next` and there is no urgent work, the output includes a section surfacing roadmap items as suggestions.

**Why this priority**: This is a convenience feature. It prevents ideas from being lost between sessions but does not affect pipeline correctness or efficiency.

**Independent Test**: Can be tested by adding items via `/roadmap`, verifying they appear in `.kiln/roadmap.md`, then running `/next` with no pending work and verifying roadmap items are surfaced.

**Acceptance Scenarios**:

1. **Given** a user runs `/roadmap Add support for monorepo projects`, **When** the command executes, **Then** the item is appended to `.kiln/roadmap.md` under a theme group
2. **Given** `.kiln/roadmap.md` does not exist, **When** `/roadmap` is run for the first time, **Then** the file is created with a default theme structure
3. **Given** no urgent work exists (no in-progress features, no open issues), **When** the user runs `/next`, **Then** the output includes a section showing roadmap items as suggestions
4. **Given** urgent work exists, **When** the user runs `/next`, **Then** roadmap items are not shown (urgent work takes priority)

---

### Edge Cases

- What happens when `init.mjs` scaffold verification fails in the non-compiled validation gate? The failure is reported as a validation error and blocks the pipeline, same as a test failure would.
- How does the validation gate handle files with no bash code blocks? Those files skip bash syntax checking — only frontmatter and file reference checks apply.
- What if `.kiln/issues/completed/` directory does not exist when archival runs? It is created automatically.
- What if the version-increment hook fires during a parallel multi-agent edit? Each agent's edit stages its own VERSION change; the committing agent includes whatever is staged at commit time.
- What if `.kiln/roadmap.md` is manually edited with custom formatting? The `/roadmap` skill appends to the existing structure without reformatting existing content.

## Requirements

### Functional Requirements

**Non-Compiled Validation Gate**

- **FR-001**: System MUST provide a validation step for non-compiled features that checks: (a) all modified markdown files have valid frontmatter structure, (b) all bash snippets in skill SKILL.md files are syntactically valid via `bash -n`, (c) all file path references in modified files resolve to existing files, (d) `init.mjs` runs successfully in a temp directory to verify scaffold output
- **FR-002**: System MUST integrate the non-compiled validation gate into `/implement` as an alternative to the 80% coverage gate — when no `src/` changes exist, run the markdown/scaffold validation instead
- **FR-003**: System MUST add validation results to the auditor's checklist so the PR includes evidence of what was verified

**Branch & Directory Naming**

- **FR-004**: System MUST enforce branch naming convention `build/<feature-slug>-<YYYYMMDD>` in the `/build-prd` skill — the team lead MUST create the branch following this exact pattern
- **FR-005**: System MUST enforce spec directory naming to match the feature slug — `specs/<feature-slug>/` with no numeric prefixes, matching the branch name's feature portion
- **FR-006**: Each `/build-prd` run MUST create a fresh branch from the current HEAD (not reuse an existing feature branch), and the team lead MUST broadcast the canonical branch name and spec directory path to all teammates at spawn time

**Issue Lifecycle Completion**

- **FR-007**: At the end of the `/build-prd` pipeline (after PR creation, before retrospective), the system MUST scan `.kiln/issues/` for entries with `status: prd-created` whose `prd:` field matches the PRD that was just built, and update their status to `completed` with a `completed_date` and `pr` field linking to the created PR
- **FR-008**: If the `.kiln/issues/completed/` directory exists, the system MUST move completed issues there as part of the same step

**Issue & Artifact Cleanup**

- **FR-009**: The `/kiln-cleanup` skill MUST scan `.kiln/issues/` for issues with `status: prd-created` or `status: completed` and move them to `.kiln/issues/completed/` (archival), with `--dry-run` support
- **FR-010**: The `/kiln-doctor` skill MUST report stale `prd-created` issues as a diagnostic finding (issues bundled into a PRD but never built)

**Commit Noise Reduction**

- **FR-011**: The version-increment hook MUST stage its changes for inclusion in the next commit rather than requiring a separate chore commit — the hook modifies files in-place and lets the implementing agent include them in the phase commit
- **FR-012**: The `/implement` skill MUST combine task-marking updates (`[X]` in tasks.md) into the phase commit for features with a single implementation phase, rather than creating separate task-marking commits
- **FR-013**: The `/build-prd` skill MUST include guidance that QA result snapshots and incremental test-result files should NOT be committed to the feature branch

**Roadmap Tracking**

- **FR-014**: The scaffold MUST include a `.kiln/roadmap.md` file — a simple markdown list grouped by theme (e.g., "DX improvements", "New capabilities", "Tech debt") with no frontmatter or status tracking
- **FR-015**: The system MUST provide a `/roadmap` skill that appends items to `.kiln/roadmap.md` with a one-liner description
- **FR-016**: The `/next` skill MUST optionally surface roadmap items when there is no urgent work — "Nothing pressing. Here are some ideas from your roadmap..."

## Success Criteria

### Measurable Outcomes

- **SC-001**: Non-compiled features run a validation gate that checks frontmatter, bash syntax, file references, and scaffold output — no more "N/A" coverage results
- **SC-002**: 100% of `/build-prd` branches follow `build/<slug>-<YYYYMMDD>` and spec directories match `specs/<slug>/`
- **SC-003**: `prd-created` issues are automatically marked `completed` and archived after successful pipeline runs with zero manual intervention
- **SC-004**: `/kiln-cleanup` archives stale issues in addition to purging QA artifacts in a single command
- **SC-005**: Commit count for single-phase features is reduced by at least 40% compared to current baseline
- **SC-006**: `.kiln/roadmap.md` exists in scaffolded projects and `/next` surfaces roadmap items when no urgent work is available

## Assumptions

- The plugin repo does not have a `src/` directory — all implementation targets are markdown skills, agent definitions, hook scripts, templates, and `init.mjs`
- Bash syntax validation uses `bash -n` (syntax check only) — it does not verify that referenced commands exist on the system
- The `.kiln/issues/` frontmatter format includes `status:` and `prd:` fields as used by existing kiln tooling
- The version-increment hook currently creates separate commits; changing it to stage-only is backwards compatible with the hook execution model
- Consumer projects that do not use `/build-prd` are unaffected by branch naming enforcement
- The roadmap file is intentionally simple — no status tracking, priorities, or dates (that is what `.kiln/issues/` is for)
