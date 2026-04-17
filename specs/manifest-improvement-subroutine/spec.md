# Feature Specification: Manifest Improvement Subroutine

**Feature Branch**: `build/manifest-improvement-subroutine-20260416`
**Created**: 2026-04-16
**Status**: Draft
**Input**: User description: "A reusable wheel sub-workflow (`shelf:propose-manifest-improvement`) that any workflow can invoke. Runs an agent reflection on the current run and, only when the agent identifies a concrete, actionable change to a manifest file, writes a single proposal to `@inbox/open/`. Silent no-op otherwise. Wired into `report-mistake-and-sync`, `report-issue-and-sync`, and `shelf-full-sync` as a pre-terminal sub-workflow step."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Silent no-op on runs with nothing to propose (Priority: P1)

A workflow author adds `shelf:propose-manifest-improvement` as a pre-terminal sub-workflow step to `shelf-full-sync`. On a steady-state run where nothing about the manifest vault stood out — no schema gap, no template friction, no run-grounded insight — the step exits silently: zero files written anywhere in `@inbox/open/`, zero user-visible log lines, zero side effects. The calling workflow continues to its terminal step exactly as it did before this feature existed.

**Why this priority**: The silence-on-no-op contract is the foundation of the feature. If steady-state runs produce noise, maintainers will ignore the channel and the quality bar collapses regardless of how good the exact-patch gate is. P1 because every other story depends on this invariant.

**Independent Test**: Invoke the sub-workflow standalone in a repo where the manifest vault is already in a clean, well-modeled state and the run produced no novel context. Verify no file was created in `@inbox/open/`, no log line was printed by `write-proposal`, and the caller workflow's exit status is unchanged.

**Acceptance Scenarios**:

1. **Given** a clean manifest vault and a run with no novel friction, **When** `shelf:propose-manifest-improvement` executes, **Then** no file is created in `@inbox/open/`, no log line is emitted by the write step, and exit status is 0.
2. **Given** the `reflect` step produces `{"skip": true}`, **When** `write-proposal` runs, **Then** the step produces no filesystem side effects and no stdout/stderr visible to the user.
3. **Given** the caller workflow is `shelf-full-sync` with this step wired in, **When** the step no-ops, **Then** the caller's terminal step runs and completes identically to a run where the sub-workflow was absent.

---

### User Story 2 - Exact-patch proposal lands in `@inbox/open/` when warranted (Priority: P1)

A contributor AI is running `report-mistake-and-sync` after encountering a schema gap in a manifest type file — the run produced a specific piece of evidence (a file path, a tool output, a verbatim snippet from the target file) that justifies a concrete textual change. The sub-workflow's `reflect` step produces a structured output with a target path inside the manifest vault, the exact current text it wants to replace, the exact proposed text, and a one-sentence reason grounded in the run. The `write-proposal` step writes a single markdown file to `@inbox/open/` via the Obsidian MCP, with frontmatter and four fixed H2 sections. A maintainer reviewing the inbox can accept the change in one edit.

**Why this priority**: This is the actual value the feature delivers — a specific-enough proposal the maintainer can apply without re-investigating. P1 because without it, the silent-no-op is just expensive silence.

**Independent Test**: Seed a run with context that contains a clear, manifest-grounded improvement (e.g., a missing field in a type file). Invoke the sub-workflow and verify a single file appears at `@inbox/open/<date>-manifest-improvement-<slug>.md` with the required frontmatter and four H2 sections, and that the `current` text appears verbatim in the target file at proposal time.

**Acceptance Scenarios**:

1. **Given** a run that produced specific, manifest-grounded context, **When** `reflect` identifies an actionable change with all four fields non-empty, **Then** `write-proposal` writes exactly one file to `@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md`.
2. **Given** a proposal file was written, **When** a maintainer opens it, **Then** it contains YAML frontmatter with `type: proposal`, `target: <path>`, `date: <YYYY-MM-DD>`, followed by four H2 sections in exact order: `## Target`, `## Current`, `## Proposed`, `## Why`.
3. **Given** a proposal's `why` sentence is "Add a `status_label` field to the project dashboard type so shelf status skills stop hard-coding labels", **When** the slug is derived, **Then** the filename slug is kebab-case, stop-words removed, ≤50 characters, truncated at a word boundary (e.g., `add-status-label-field-project-dashboard-type`).
4. **Given** `reflect` sets `skip: false` but `current` text does not appear verbatim in the target file, **When** the workflow validates the output, **Then** the step forces `skip: true` and no file is written.

---

### User Story 3 - Target scope is clamped to the manifest vault (Priority: P1)

A contributor AI running a workflow notices that a shelf skill, a plugin workflow file, or the project constitution could be improved. The `reflect` step attempts to emit a proposal targeting one of these non-manifest paths. The sub-workflow silently forces `skip: true` because the target is outside `@manifest/types/*.md` or `@manifest/templates/*.md`. No proposal is written anywhere.

**Why this priority**: Scope creep is the named risk in the PRD. If the sub-workflow can propose changes to arbitrary vault or plugin files, the feature becomes a general-purpose refactor surface and the quality bar blurs. P1 because this constraint is how the feature stays bounded.

**Independent Test**: Craft a run where the natural improvement is to a shelf skill file and verify the sub-workflow produces no proposal. Then craft a run where the natural improvement is to a manifest type file and verify a proposal is produced. Both use the same entry point.

**Acceptance Scenarios**:

1. **Given** `reflect` emits `target: "plugin-shelf/skills/shelf-update/SKILL.md"`, **When** the output is validated, **Then** `skip` is forced to `true` and no file is written.
2. **Given** `reflect` emits `target: "@manifest/types/project-dashboard.md"`, **When** the output is validated and `current` appears verbatim, **Then** a proposal is written.
3. **Given** `reflect` emits `target: "@manifest/templates/about.md"`, **When** the output is validated and `current` appears verbatim, **Then** a proposal is written.

---

### User Story 4 - One sub-workflow step, wired into three callers identically (Priority: P2)

An author of the three core sync workflows (`shelf-full-sync`, `report-issue-and-sync`, `report-mistake-and-sync`) wires `shelf:propose-manifest-improvement` in as a single pre-terminal sub-workflow step — same shape in all three, no custom glue. On any run of any of these workflows, the sub-workflow gets a chance to reflect. If it writes a proposal, the very next terminal step (`shelf:shelf-full-sync`) picks the new file up in the same sync pass, so the proposal appears in Obsidian without requiring a second workflow run.

**Why this priority**: Uniform wiring keeps the caller shape stable and the reviewer's mental model simple. P2 because User Stories 1–3 define behavior; this story is about deployment uniformity across callers.

**Independent Test**: Inspect the three caller workflow JSON files and verify each contains exactly one step invoking `shelf:propose-manifest-improvement`, positioned immediately before the terminal `shelf:shelf-full-sync` step. Run each caller end-to-end with a seeded improvement and verify the new proposal appears in the same sync pass.

**Acceptance Scenarios**:

1. **Given** `plugin-shelf/workflows/shelf-full-sync.json`, **When** its steps are inspected, **Then** exactly one step invokes `shelf:propose-manifest-improvement` and it is the step immediately before the terminal sync step.
2. **Given** `plugin-kiln/workflows/report-issue-and-sync.json`, **When** its steps are inspected, **Then** exactly one step invokes `shelf:propose-manifest-improvement` and it is the step immediately before the terminal `shelf:shelf-full-sync` call.
3. **Given** `plugin-kiln/workflows/report-mistake-and-sync.json`, **When** its steps are inspected, **Then** exactly one step invokes `shelf:propose-manifest-improvement` and it is the step immediately before the terminal `shelf:shelf-full-sync` call.
4. **Given** any of the three callers runs and the sub-workflow writes a proposal, **When** the terminal `shelf:shelf-full-sync` step runs, **Then** the newly written proposal file in `@inbox/open/` is picked up by the sync without requiring a re-run.

---

### User Story 5 - Plugin portability: runs correctly from any consumer repo (Priority: P2)

A consumer installs the shelf plugin via the Claude Code marketplace. Their repo does not contain the shelf source at `plugin-shelf/`; the plugin lives in the plugin cache directory. When they run `shelf:propose-manifest-improvement` (directly or via a caller), every command-step script resolves from the plugin cache path — not from a repo-relative `plugin-shelf/scripts/` path that would silently be missing. The step runs to completion in the consumer repo identically to how it runs in the plugin source repo.

**Why this priority**: The portability rule is non-negotiable per the project constitution and a named must in the PRD. The symptom of violation — silent `No such file or directory` with empty step output — is the worst kind of failure because it looks like a working no-op. P2 because callers still function even if portability is wrong in the source repo; the failure surfaces only in consumer repos.

**Independent Test**: Install the shelf plugin into a clean consumer repo that has no `plugin-shelf/` directory. Invoke the sub-workflow from that repo. Verify no `No such file or directory` errors appear in the command step output and the step's behavior (silent skip or proposal write) matches the source-repo run for an equivalent seeded context.

**Acceptance Scenarios**:

1. **Given** the sub-workflow JSON, **When** any command step is inspected, **Then** every script path resolves via `${WORKFLOW_PLUGIN_DIR}/scripts/...` and no step references a repo-relative `plugin-shelf/scripts/...` path.
2. **Given** a consumer repo with the plugin installed via cache (no `plugin-shelf/` in the repo), **When** the sub-workflow runs, **Then** the command step's script is found, executes, and produces the same behavior as in the source repo.
3. **Given** a consumer repo without `${WORKFLOW_PLUGIN_DIR}` exported, **When** the sub-workflow runs, **Then** the failure is detected and reported — not silently masked with empty step output.

---

### User Story 6 - Graceful degradation when Obsidian MCP is unavailable (Priority: P3)

A contributor is running a caller workflow in an environment where the Obsidian MCP is not connected (e.g., Obsidian closed, MCP server down, wrong vault binding). The sub-workflow's `write-proposal` step detects the MCP is unavailable, emits a one-time warning, and exits 0. The calling workflow continues to its terminal step and completes normally. No partial file is written, no retry loop burns time, no error propagates up to fail the caller.

**Why this priority**: MCP outages are rare and the proposal write is best-effort — a dropped proposal is recoverable next run. P3 because blocking the caller on MCP availability would be a much worse failure mode than losing one proposal.

**Independent Test**: Run the sub-workflow in an environment where the Obsidian MCP is deliberately disconnected, with a reflect output that would otherwise write a proposal. Verify exactly one warning line is emitted, exit status is 0, no file is written, and any caller workflow continues past this step.

**Acceptance Scenarios**:

1. **Given** the Obsidian MCP is unavailable and `reflect` produced a non-skip output, **When** `write-proposal` runs, **Then** a single warning is logged, no file is written, and the step exits 0.
2. **Given** `write-proposal` exited 0 after an MCP unavailability warning, **When** the caller workflow continues, **Then** the terminal step runs normally and the caller's overall exit status is unaffected by this step.
3. **Given** the MCP becomes available on a subsequent run and the same improvement context recurs, **When** the sub-workflow runs, **Then** the proposal is written as if the earlier failure had not happened (no deduplication state persisted from the failed attempt).

---

### Edge Cases

- **Hallucinated `current` text**: `reflect` returns `skip: false` with a `current` string the agent believes exists in the target file but does not match verbatim — must force `skip: true`.
- **Out-of-scope target**: `reflect` targets a shelf skill, plugin workflow, the constitution, or any path outside `@manifest/types/*.md` / `@manifest/templates/*.md` — must force `skip: true`.
- **Empty field**: any of `target`, `current`, `proposed`, `why` is empty string or missing — must force `skip: true`.
- **Generic `why`**: `why` is a generic opinion with no run-grounded reference (no file path, no tool output, no artifact citation) — must force `skip: true`.
- **Slug collision**: two runs in the same day produce proposals whose `why` sentences derive the same slug — filename collision handling must produce a unique path (e.g., suffix) and must not overwrite an existing proposal.
- **`reflect` output malformed JSON**: `write-proposal` encounters invalid JSON in `.wheel/outputs/propose-manifest-improvement.json` — must treat as skip, not crash.
- **Multiple actionable improvements in one run**: `reflect` is constrained to one proposal per run in v1; extras are dropped.
- **`${WORKFLOW_PLUGIN_DIR}` not exported**: command step cannot resolve its script path — must surface as a detectable failure, not silent `No such file or directory`.
- **Obsidian MCP partially available** (connected but wrong vault): treat as unavailable per the FR-15 graceful-degradation path — warn once, exit 0.
- **Caller removes the step**: any of the three callers drops the sub-workflow step — behavior reverts exactly to pre-feature steady state, no orphaned state files or dangling artifacts.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a wheel workflow at `plugin-shelf/workflows/propose-manifest-improvement.json` runnable as `shelf:propose-manifest-improvement`.
- **FR-002**: The workflow MUST consist of exactly two steps in order: a `reflect` step (agent) followed by a `write-proposal` step (command).
- **FR-003**: The `reflect` step MUST produce a structured output artifact at `.wheel/outputs/propose-manifest-improvement.json` with exactly one of two shapes:
  - `{"skip": true}`, OR
  - `{"skip": false, "target": "<path>", "section": "<heading or line-range>", "current": "<verbatim>", "proposed": "<verbatim>", "why": "<one sentence>"}`.
- **FR-004**: The `reflect` step MUST restrict `target` to paths matching the glob `@manifest/types/*.md` or `@manifest/templates/*.md`. Any target outside these globs MUST be transformed into `{"skip": true}` before the output artifact is finalized.
- **FR-005**: The `reflect` step MUST only emit `skip: false` when ALL of `target`, `current`, `proposed`, and `why` are non-empty strings AND the `current` text appears verbatim (byte-for-byte) in the target file at the time the output is validated. If any field is empty or `current` does not match, the output MUST be forced to `{"skip": true}`.
- **FR-006**: The `why` field MUST cite at least one concrete artifact from the current run — a file path, a tool call output, a workflow step output, an agent note, or a named artifact in `.wheel/outputs/`. Generic opinions, stylistic preferences, or statements not traceable to the current run MUST force `skip: true`.
- **FR-007**: The `write-proposal` step MUST be silent when `skip: true` — no file is created, no line is emitted to stdout or stderr visible to the user, and no side effect occurs beyond exit 0. No marker file, no `.wheel/outputs/` artifact aside from the internal `reflect` output, and no log line.
- **FR-008**: The `write-proposal` step MUST, when `skip: false`, write exactly one file to `@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md` via the Obsidian MCP. Direct filesystem writes to the Obsidian vault are prohibited.
- **FR-009**: The proposal file MUST begin with YAML frontmatter containing at minimum `type: proposal`, `target: <target path>`, and `date: <YYYY-MM-DD>`, followed by four H2 sections in this exact order with these exact headings: `## Target`, `## Current`, `## Proposed`, `## Why`.
- **FR-010**: The `<slug>` in the proposal filename MUST be derived from the `why` sentence by lowercasing, removing stop-words, replacing non-alphanumerics with hyphens, collapsing consecutive hyphens, and truncating to ≤50 characters at a word boundary. The derivation MUST be deterministic: the same `why` sentence MUST always produce the same slug.
- **FR-011**: `plugin-shelf/workflows/shelf-full-sync.json` MUST include `shelf:propose-manifest-improvement` as a sub-workflow step positioned immediately before the terminal step.
- **FR-012**: `plugin-kiln/workflows/report-issue-and-sync.json` MUST include `shelf:propose-manifest-improvement` as a sub-workflow step positioned immediately before its terminal `shelf:shelf-full-sync` step.
- **FR-013**: `plugin-kiln/workflows/report-mistake-and-sync.json` MUST include `shelf:propose-manifest-improvement` as a sub-workflow step positioned immediately before its terminal `shelf:shelf-full-sync` step.
- **FR-014**: In all three callers (FR-011 through FR-013), the sub-workflow step MUST be pre-terminal relative to the sync step so that a proposal written by `write-proposal` is picked up by the same sync pass in the same run.
- **FR-015**: If the Obsidian MCP is unavailable at the moment `write-proposal` attempts the write, the step MUST emit a single warning line, MUST NOT create any partial file, MUST NOT retry indefinitely, and MUST exit 0 — the caller workflow MUST continue unaffected.
- **FR-016**: The sub-workflow MUST be plugin-portable — every command-step script path MUST resolve via `${WORKFLOW_PLUGIN_DIR}` (or an equivalent plugin-dir-aware variable exported by the wheel dispatch layer). No command step may reference a repo-relative `plugin-shelf/scripts/...` path.
- **FR-017**: The workflow MUST be invocable standalone (not only as a sub-workflow) so that contributors can test it in isolation against a seeded run context. Standalone invocation MUST observe the same silent-on-skip and scope-clamp rules as sub-workflow invocation.
- **FR-018**: When the `reflect` step output file is missing, empty, or malformed JSON, the `write-proposal` step MUST treat the run as `skip: true` — it MUST NOT crash, MUST NOT emit an error visible to the user, and MUST exit 0.
- **FR-019**: If a proposal filename would collide with an existing file in `@inbox/open/` on the same date, `write-proposal` MUST produce a unique filename (e.g., by appending a short disambiguator) and MUST NOT overwrite the existing file.
- **FR-020**: The `reflect` step output artifact `.wheel/outputs/propose-manifest-improvement.json` is an internal step artifact only; it MUST NOT be treated as user-visible output and MUST NOT be surfaced in any user-facing log or summary.

### Key Entities *(include if feature involves data)*

- **Reflect Output Artifact**: The JSON file at `.wheel/outputs/propose-manifest-improvement.json` produced by the `reflect` step. Carries the structured decision (skip or proposal payload) to the `write-proposal` step. Not user-visible.
- **Proposal File**: The markdown file written to `@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md`. Has fixed frontmatter (`type: proposal`, `target`, `date`) and four fixed H2 sections (`## Target`, `## Current`, `## Proposed`, `## Why`). One file per non-skip run.
- **Manifest Target**: A file under `@manifest/types/` or `@manifest/templates/` that a proposal may target. Targets outside this scope are silently rejected.
- **Caller Workflow**: One of `shelf-full-sync`, `report-issue-and-sync`, or `report-mistake-and-sync` — each invokes the sub-workflow as a pre-terminal step.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001** — **Silent rate on no-op runs**: On runs where nothing actionable is identified, 0 files are created in `@inbox/open/` by this sub-workflow and 0 log lines are emitted by the `write-proposal` step. Measured over 20 consecutive steady-state runs of any caller — zero variance tolerated.
- **SC-002** — **Proposal precision**: At least 80% of proposals written to `@inbox/open/` are accepted by a maintainer (merged into a manifest type or template file, possibly with minor edits) within 7 days of being written. Measured monthly over the first 90 days following feature deployment.
- **SC-003** — **Scope compliance**: 100% of proposal files written by this sub-workflow target a path matching `@manifest/types/*.md` or `@manifest/templates/*.md`. A single proposal outside that scope is a defect requiring an immediate fix.
- **SC-004** — **Caller stability**: 0 caller-workflow failures attributable to this sub-workflow over the first 90 days. The sub-workflow exits 0 on every invocation — success, skip, or MCP-unavailable — and never propagates a non-zero exit to its caller.
- **SC-005** — **Adoption**: The sub-workflow is invoked at least once per day on average across the three initial callers, assuming normal repo activity. Measured via run logs in `.wheel/history/success/`.
- **SC-006** — **Proposal structural validity**: 100% of written proposal files parse as valid markdown, contain the required frontmatter keys (`type`, `target`, `date`), and contain the four H2 sections in the mandated order with the exact heading text. Any deviation is a defect.
- **SC-007** — **Plugin portability in consumer repos**: The sub-workflow executes successfully in at least one consumer repo that does not have the shelf source repo checked out. A "No such file or directory" error on a command step in a consumer repo is a critical defect.
- **SC-008** — **Review turnaround**: A maintainer reviewing `@inbox/open/` can read and decide on a proposal (accept / reject / defer) in under 2 minutes on average, because the four H2 sections provide exact target, current text, proposed text, and run-grounded reason without requiring further investigation.

## Assumptions

- The Obsidian MCP (`mcp__obsidian-projects__*` or a caller-provided binding) is the canonical write path for `@inbox/open/`. Direct filesystem writes to the vault are out of scope and prohibited.
- Callers already produce agent context (agent-notes, step outputs, tool traces) under the run's `.wheel/outputs/` that the `reflect` step can read as evidence.
- The `${WORKFLOW_PLUGIN_DIR}` variable is reliably exported by the wheel dispatch layer. If it is not, that is a wheel bug to surface — not something to paper over with repo-relative paths.
- Maintainers triage `@inbox/open/` regularly enough (at least weekly) that proposals do not accumulate stale beyond the 7-day window in SC-002.
- One proposal per run is acceptable for v1. Multiple independent improvements surfacing in one run will be revisited only if under-triggering proves problematic.
- Filename collisions within the same day are rare in practice; the disambiguation suffix in FR-019 is a safety net, not a hot path.
- Maintainers apply proposals by hand (copy-paste) — no diff-apply tooling is assumed. The four H2 sections are formatted to support by-eye application.
- The three initial callers (`shelf-full-sync`, `report-issue-and-sync`, `report-mistake-and-sync`) are the only callers for v1. Additional callers require explicit wiring and are out of scope here.
