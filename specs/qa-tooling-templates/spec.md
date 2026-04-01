# Feature Specification: QA Agent Optimization, Kiln Doctor Enhancements & Template Improvements

**Feature Branch**: `build/qa-tooling-templates-20260401`  
**Created**: 2026-04-01  
**Status**: Draft  
**Input**: User description: "QA Agent Optimization, Kiln Doctor Enhancements & Template Improvements — 25 FRs from PRD at docs/features/2026-04-01-qa-tooling-templates/PRD.md"

## User Scenarios & Testing

### User Story 1 - Faster QA Pipeline Runs (Priority: P1)

As a pipeline operator running `/build-prd`, I want the QA agent to complete its test pass significantly faster so the feedback loop between implementers and QA stays tight and doesn't bottleneck the pipeline.

**Why this priority**: QA is the primary bottleneck in pipeline runs. Parallel viewports, failure-only recording, and targeted waits directly reduce wall-clock time by eliminating the three biggest time sinks.

**Independent Test**: Run a `/build-prd` pipeline and measure QA agent wall-clock time. Compare against the current baseline where viewports run serially and all recordings are always-on.

**Acceptance Scenarios**:

1. **Given** a consumer project with Playwright configured via `/qa-setup`, **When** the QA agent runs tests, **Then** desktop, tablet, and mobile viewports execute concurrently (not serially)
2. **Given** a test run where all tests pass, **When** the run completes, **Then** no video or trace files are retained (only retained on failure)
3. **Given** a test run where one test fails, **When** the run completes, **Then** video and trace files are retained only for the failing test
4. **Given** the QA agent writing test code, **When** it needs to wait for page state, **Then** it uses `waitForSelector` or `waitForFunction` instead of `networkidle` or `waitForTimeout`

---

### User Story 2 - QA Tests Latest Build (Priority: P1)

As a pipeline operator, I want the QA agent to always test against the latest build so false failures from stale artifacts stop wasting cycles.

**Why this priority**: Testing stale builds produces false negatives that waste debugging time and erode trust in QA results. This is a correctness issue, not just efficiency.

**Independent Test**: Send a message to the QA agent during a pipeline run and verify it triggers a rebuild before evaluating.

**Acceptance Scenarios**:

1. **Given** a running pipeline with the QA agent active, **When** the QA agent receives a `SendMessage` from an implementer, **Then** it runs the project build command before proceeding with testing
2. **Given** a QA agent that has received a message but not yet rebuilt, **When** it attempts to go idle, **Then** it is blocked from idling until a build has been executed

---

### User Story 3 - Feature-Scoped QA Reports (Priority: P2)

As a feature developer, I want QA reports to clearly separate feature-specific results from sitewide regression findings so I can quickly determine if my feature passes without wading through unrelated results.

**Why this priority**: QA testing too broadly makes reports noisy and slows down developer response to feedback. Scoped reports give clear, actionable signal.

**Independent Test**: Run a QA pass on a feature and verify the report has distinct Feature Verdict and Regression Findings sections.

**Acceptance Scenarios**:

1. **Given** a QA agent running tests for a specific feature, **When** it generates its report, **Then** the report contains a "Feature Verdict" section with scoped pass/fail for the feature's test matrix
2. **Given** a QA report, **When** the feature does not touch shared components, **Then** the "Regression Findings" section is omitted or marked as not applicable
3. **Given** a QA report, **When** the feature touches shared components, **Then** the "Regression Findings" section contains regression test results separate from the feature verdict

---

### User Story 4 - Walkthrough Recording of New Features (Priority: P2)

As a pipeline operator reviewing QA results, I want a clean walkthrough recording of new features captured after all tests pass so stakeholders can see the feature in action without test harness noise.

**Why this priority**: A final walkthrough provides visual proof-of-work that is useful for PR reviews and stakeholder demos.

**Independent Test**: After all QA tests pass, verify a walkthrough video exists that demonstrates the new feature flows.

**Acceptance Scenarios**:

1. **Given** all QA tests have passed, **When** the QA agent completes its run, **Then** it records one clean walkthrough demonstrating the new feature flows
2. **Given** some tests have failed, **When** the QA agent completes its run, **Then** no walkthrough recording is produced (only failure recordings)

---

### User Story 5 - Retrospective Agent Collects Friction Data (Priority: P2)

As a plugin maintainer, I want the retrospective agent to have access to agent friction notes even after pipeline teammates have shut down, so retrospectives produce actionable improvement data.

**Why this priority**: The retrospective agent currently can't collect live feedback because teammates shut down before it runs. File-based notes solve this timing problem.

**Independent Test**: Run a pipeline, verify each agent writes friction notes before shutdown, and verify the retrospective agent reads them.

**Acceptance Scenarios**:

1. **Given** a pipeline agent finishing its work, **When** it shuts down, **Then** it has written a friction note to `specs/<feature>/agent-notes/<agent-name>.md` documenting what was confusing, where it got stuck, and what could be improved
2. **Given** the retrospective agent starting, **When** it collects feedback, **Then** it reads from `specs/<feature>/agent-notes/` instead of sending `SendMessage` requests to defunct teammates

---

### User Story 6 - Kiln Doctor Cleanup and Version Sync (Priority: P2)

As a plugin maintainer, I want kiln-doctor to clean up stale artifacts and detect version drift across package manifests so I don't have to manage these manually.

**Why this priority**: Accumulated artifacts waste disk space and version drift causes subtle bugs. Automated detection and cleanup prevents manual toil.

**Independent Test**: Run `kiln-doctor` in diagnose mode on a project with stale artifacts and mismatched versions, then run fix mode and verify corrections.

**Acceptance Scenarios**:

1. **Given** a kiln manifest with retention rules defined, **When** running `/kiln-doctor` in diagnose mode, **Then** it reports artifacts exceeding retention limits
2. **Given** stale artifacts and `--cleanup` flag, **When** running `/kiln-doctor --cleanup`, **Then** it applies retention rules and removes excess files (with `--dry-run` support for previewing)
3. **Given** a project where `package.json` version differs from `VERSION` file, **When** running `/kiln-doctor` in diagnose mode, **Then** it reports the version mismatch
4. **Given** version mismatches in fix mode, **When** running `/kiln-doctor --fix`, **Then** it updates mismatched files to match `VERSION`
5. **Given** a `.kiln/version-sync.json` config, **When** running version sync checks, **Then** only files declared in the config (plus defaults) are scanned

---

### User Story 7 - Dedicated QA Artifact Cleanup (Priority: P3)

As a developer, I want a `/kiln-cleanup` command to purge accumulated QA artifacts (videos, traces, reports) so my project stays clean without manual file management.

**Why this priority**: QA artifacts accumulate quickly and can consume significant disk space. A dedicated command makes cleanup a one-step operation.

**Independent Test**: Populate `.kiln/qa/` with test artifacts, run `/kiln-cleanup`, and verify they are removed. Test `--dry-run` shows what would be removed without deleting.

**Acceptance Scenarios**:

1. **Given** stale QA artifacts in `.kiln/qa/` (test-results, playwright-report, videos, traces), **When** running `/kiln-cleanup`, **Then** all stale artifacts are removed
2. **Given** the `--dry-run` flag, **When** running `/kiln-cleanup --dry-run`, **Then** it lists artifacts that would be removed without deleting them
3. **Given** kiln-doctor running in fix mode, **When** stale QA artifacts exist, **Then** `/kiln-cleanup` is triggered as part of the fix

---

### User Story 8 - Better Templates for Issues and Specs (Priority: P3)

As a consumer project developer, I want issue and spec/PRD templates to prompt for commonly-missed requirements so my pipeline runs don't hit the same gaps repeatedly.

**Why this priority**: Predictable template gaps cause rework every pipeline run. Proactive prompts eliminate this recurring waste.

**Independent Test**: Run `/report-issue` and verify it uses the externalized template. Run `/specify` and verify new checklist items appear. Run `init.mjs` and verify the template is scaffolded.

**Acceptance Scenarios**:

1. **Given** the `/report-issue` skill, **When** it generates an issue, **Then** it reads the markdown structure from `plugin/templates/issue.md` instead of hardcoding it
2. **Given** a consumer project running `init.mjs`, **When** scaffolding completes, **Then** the issue template is copied into the project for customization
3. **Given** a PRD/spec template, **When** a feature involves a rename or rebrand, **Then** the template includes a checklist item for grep-based verification of all references
4. **Given** a plan template, **When** a feature depends on a container CLI, **Then** the template includes a Phase 1 task to run `--help` and document results
5. **Given** a spec template, **When** a feature requires QA testing, **Then** the template includes a section for documenting credentials and auth flow
6. **Given** a plan template, **When** a feature involves accessibility, **Then** the template includes guidance to run axe-core locally before committing

---

### User Story 9 - Issue Archival (Priority: P3)

As a backlog triager, I want completed issues automatically archived to a `completed/` subdirectory so scanning for actionable work is fast and the active backlog stays clean.

**Why this priority**: Mixing completed and active issues slows triage. Archival keeps the working set small.

**Independent Test**: Close an issue and verify it moves to `.kiln/issues/completed/`. Run `/report-issue` and verify it only scans top-level `.kiln/issues/`.

**Acceptance Scenarios**:

1. **Given** an issue with status `closed` or `done`, **When** the status is set, **Then** the issue file is moved to `.kiln/issues/completed/`
2. **Given** archived issues in `.kiln/issues/completed/`, **When** `/report-issue` scans for active items, **Then** it only scans top-level `.kiln/issues/` (not `completed/`)
3. **Given** archived issues in `.kiln/issues/completed/`, **When** `/issue-to-prd` scans for active items, **Then** it only scans top-level `.kiln/issues/` (not `completed/`)

---

### Edge Cases

- What happens when the QA agent receives multiple messages in rapid succession — does it rebuild after each one or batch them?
- What happens when `VERSION` file doesn't exist but version-sync is configured?
- What happens when `/kiln-cleanup` is run on a project with no `.kiln/qa/` directory?
- What happens when an agent crashes before writing its friction note?
- What happens when `version-sync.json` references a file that doesn't exist?
- What happens when the issue template file is missing or corrupted in a consumer project?

## Requirements

### Functional Requirements

**QA Agent Performance**

- **FR-001**: QA agent and `/qa-setup` scaffold MUST default Playwright config to `video: 'retain-on-failure'` and `trace: 'retain-on-failure'` instead of `'on'`
- **FR-002**: QA agent and `/qa-setup` scaffold MUST set `fullyParallel: true` in the Playwright config so desktop, tablet, and mobile viewports run concurrently
- **FR-003**: QA agent instructions MUST prefer `waitForSelector`/`waitForFunction` over `networkidle`, and MUST prohibit hardcoded `waitForTimeout` calls
- **FR-004**: QA agent MUST perform a final walkthrough recording step that captures one clean run of new features after all tests pass

**QA Build Enforcement**

- **FR-005**: A hook MUST inject context requiring the QA agent to run the project build command after every `SendMessage` it receives
- **FR-006**: A hook MUST block the QA agent from going idle if it hasn't run a build since its last received message

**QA Scope and Reporting**

- **FR-007**: QA agent MUST focus on the feature's test matrix first, reporting feature pass/fail as a standalone section before any regression findings
- **FR-008**: QA reports MUST be structured into two sections: (1) Feature Verdict (scoped pass/fail) and (2) Regression Findings (optional, only when feature touches shared components or explicitly requested)

**Retrospective Agent Feedback Collection**

- **FR-009**: Before each pipeline agent shuts down, it MUST write a friction note to `specs/<feature>/agent-notes/<agent-name>.md` documenting what was confusing, where it got stuck, and what could be improved
- **FR-010**: The retrospective agent MUST read `specs/<feature>/agent-notes/` instead of relying on live `SendMessage` feedback from teammates

**Kiln Doctor Cleanup**

- **FR-011**: Kiln manifest MUST support retention/cleanup rules (e.g., `logs: keep_last: 10`, `issues: archive_completed: true`)
- **FR-012**: `/kiln-doctor` MUST support a `--cleanup` flag that applies manifest retention rules, with `--dry-run` support for previewing changes
- **FR-013**: A `/kiln-cleanup` skill MUST exist that removes stale QA artifacts from `.kiln/qa/` (test-results, playwright-report, videos, traces), with `--dry-run` support
- **FR-014**: `/kiln-cleanup` MUST be integrated into `/kiln-doctor` fix mode so `kiln-doctor --fix` also purges stale QA artifacts

**Kiln Doctor Version Sync**

- **FR-015**: `/kiln-doctor` MUST include a version-sync check that scans for common version-bearing files (`package.json`, `*.toml`, `*.cfg`, `*.yaml`) and compares each version against the canonical `VERSION` file
- **FR-016**: In fix mode, `/kiln-doctor` MUST automatically update mismatched version files to match `VERSION`
- **FR-017**: An optional `.kiln/version-sync.json` config MUST be supported for declaring which files should track `VERSION` (opt-in additional files, exclude false positives)

**Templates**

- **FR-018**: The issue markdown structure MUST be extracted from `/report-issue` into `plugin/templates/issue.md`, and the skill MUST read from the template
- **FR-019**: `init.mjs` MUST scaffold the issue template into consumer projects so they can customize it
- **FR-020**: PRD/spec templates MUST include a rename/rebrand checklist item: "Include an FR for grep-based verification of ALL references"
- **FR-021**: Plan templates MUST include a container CLI discovery task: "When depending on container CLI, add Phase 1 task to run `--help` and document results"
- **FR-022**: Spec templates MUST include QA auth documentation: "Document credentials and auth flow required for QA testing"
- **FR-023**: Plan templates MUST include local validation guidance: "For a11y features, run axe-core locally and fix all violations before committing"

**Issue Archival**

- **FR-024**: When an issue status is set to `closed` or `done`, the file MUST be moved to `.kiln/issues/completed/`
- **FR-025**: `/report-issue` and `/issue-to-prd` MUST only scan top-level `.kiln/issues/` (not `completed/`) for active items

### Key Entities

- **Agent Note**: A markdown file written by each pipeline agent before shutdown, stored in `specs/<feature>/agent-notes/<agent-name>.md`, containing friction data (confusion, blockers, improvement suggestions)
- **Version Sync Config**: A JSON file at `.kiln/version-sync.json` declaring which files should track the canonical `VERSION` file, with include/exclude lists
- **Issue Template**: A markdown template at `plugin/templates/issue.md` used by `/report-issue` to structure new issues, scaffolded into consumer projects by `init.mjs`
- **Retention Rules**: Configuration within the kiln manifest defining cleanup policies for `.kiln/` subdirectories (log count limits, archive rules, artifact purge policies)

## Success Criteria

### Measurable Outcomes

- **SC-001**: QA agent pipeline runtime decreases by at least 50% compared to current baseline (serial viewports, always-on recording)
- **SC-002**: Zero instances of QA testing stale builds when build-enforcement hooks are active
- **SC-003**: QA reports in pipeline runs clearly separate feature verdict from regression findings in 100% of runs
- **SC-004**: Retrospective agent has access to agent friction notes in 100% of pipeline runs
- **SC-005**: `kiln-doctor` detects version mismatches and stale artifacts in diagnose mode and fixes them in fix mode with zero false positives
- **SC-006**: `/kiln-cleanup` successfully purges QA artifacts with dry-run preview, removing all targeted artifact types
- **SC-007**: Issue template is externalized to `plugin/templates/issue.md` and customizable by consumer projects after scaffold
- **SC-008**: Spec/PRD templates include the four new checklist items (rename grep, CLI discovery, QA auth, local a11y validation)
- **SC-009**: Completed issues are automatically archived to `completed/` subdirectory when status changes to closed/done

## Assumptions

- The Claude Code hook system supports `SubagentStart` event types for injecting additional context into agents (FR-005). If `TeammateIdle` is not supported, FR-006 will be implemented as guidance in the QA agent prompt instead of a hook.
- Consumer projects using existing templates will not break when new checklist sections are added — skills will handle both old and new template formats gracefully.
- The `VERSION` file is the canonical source of truth for version strings. Files like `package-lock.json` are excluded from version sync by default.
- Agent notes are permanent records per feature and are not automatically cleaned up (they serve as retrospective input).
- The kiln manifest format can be extended with retention rules without breaking existing manifests that lack them.
- QA artifact cleanup targets only `.kiln/qa/` subdirectories — it does not touch spec artifacts, logs, or issues.
