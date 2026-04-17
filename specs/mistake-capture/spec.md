# Feature Specification: Mistake Capture

**Feature Branch**: `build/mistake-capture-20260416`
**Created**: 2026-04-16
**Status**: Draft
**Input**: PRD at `docs/features/2026-04-16-mistake-capture/PRD.md`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Capture a corrected assumption mid-session (Priority: P1)

An AI contributor working in the repo is corrected by the user ("no, that's per-project, not per-vault"). The contributor runs `/kiln:mistake` describing the correction in free-form text. The skill activates a wheel workflow that collects the manifest-required fields, applies honesty and tag lints, and writes a conformant artifact to `.kiln/mistakes/YYYY-MM-DD-<assumption-slug>.md`. On the next sync, shelf files a proposal in `@inbox/open/` for human review.

**Why this priority**: This is the core value proposition. Without this flow, the feature does not exist. It is the only path that produces schema-conformant mistake notes at zero friction during a live session.

**Independent Test**: Run `/kiln:mistake` with a realistic free-form description in a repo that has the wheel engine and shelf plugin installed. Verify a file lands in `.kiln/mistakes/` with valid frontmatter (three-axis tags, required fields) and a filename slug derived from the `assumption:` field, and that `shelf:shelf-full-sync` is invoked as the terminal step.

**Acceptance Scenarios**:

1. **Given** an AI contributor on branch `build/foo` just received a correction from the user, **When** they run `/kiln:mistake "I assumed plugin caches live per-vault but they are per-project"`, **Then** the workflow activates, prompts for any missing manifest-required fields (severity, tags, status, body sections), writes `.kiln/mistakes/2026-04-16-plugin-caches-are-per-vault.md` with frontmatter conforming to `@manifest/types/mistake.md`, and chains into `shelf:shelf-full-sync` as a terminal step.
2. **Given** the user runs `/kiln:mistake` with no description argument, **When** the workflow starts, **Then** the `create-mistake` agent step prompts for a free-form description before collecting structured fields.
3. **Given** a mistake artifact already exists at `.kiln/mistakes/2026-04-16-foo.md`, **When** a new mistake with the same slug is captured on the same day, **Then** the workflow writes to `.kiln/mistakes/2026-04-16-foo-2.md` without overwriting the original.

---

### User Story 2 - Honesty and tag lint refuse hedged or mis-tagged drafts (Priority: P1)

When the AI submits an `assumption:` that hedges (contains "may have", "might have", "possibly", etc.) or starts without first-person past tense, the `create-mistake` step refuses the draft and re-prompts. Same for `correction:` that does not start with `I `, `The `, or `It `. Same for tag sets that miss any of the three required axes (one `mistake/*`, at least one `topic/*`, at least one stack tag).

**Why this priority**: Per PRD "Absolute Must #5": the entire point of mistake notes is honesty. A lint-free hedged draft is worse than no draft. This lint is what makes the captured notes usable as training data.

**Independent Test**: Submit a deliberately hedged assumption to `/kiln:mistake`; verify it is rejected with a re-prompt. Submit a deliberately mis-tagged draft (missing `topic/*`); verify it is rejected with a re-prompt for the missing axis. Verify no partial file is written to `.kiln/mistakes/`.

**Acceptance Scenarios**:

1. **Given** an agent submits `assumption: I may have thought caches were per-vault`, **When** the `create-mistake` step applies the honesty lint, **Then** the step rejects the field (hedge marker "may have") and re-prompts without writing the file.
2. **Given** an agent submits `assumption: Plugin caches live per-vault` (missing first-person past start), **When** the honesty lint runs, **Then** the step rejects and re-prompts requiring the `I ` prefix.
3. **Given** an agent submits tags `["mistake/assumption", "language/bash"]` (missing any `topic/*`), **When** the three-axis tag lint runs, **Then** the step rejects and re-prompts for the missing `topic/*` axis.
4. **Given** an agent submits two `mistake/*` tags for a mistake that does not genuinely span classes, **When** the three-axis tag lint runs, **Then** the step allows exactly one unless the agent explicitly confirms cross-class intent.

---

### User Story 3 - Shelf discovers mistakes and files `@inbox/open/` proposals (Priority: P1)

On `shelf:shelf-full-sync`, shelf's work-list computation discovers `.kiln/mistakes/*.md` alongside the existing `.kiln/issues/*.md` discovery. For each new or changed mistake artifact, shelf writes a proposal to `@inbox/open/` via Obsidian MCP with `type: manifest-proposal`, `kind: content-change`, and `target: @second-brain/projects/<slug>/mistakes/<filename>`. Unchanged mistake files are skipped via the existing content-hash strategy. Accepted proposals (moved out of `@inbox/open/`) are not re-proposed.

**Why this priority**: Without this pickup the local artifact is stranded. The proposal flow through `@inbox/open/` is the manifest-mandated path (Absolute Must #4 — no direct writes to `<project>/mistakes/`).

**Independent Test**: Add one hand-crafted conformant mistake file to `.kiln/mistakes/`, run `/wheel:wheel-run shelf-full-sync`, verify one proposal note appears in `@inbox/open/` with correct frontmatter and target. Re-run the sync; verify no duplicate proposal is created. Move the proposal out of `@inbox/open/` and re-run; verify it is not resurrected.

**Acceptance Scenarios**:

1. **Given** `.kiln/mistakes/2026-04-16-foo.md` exists and has never been synced, **When** `shelf:shelf-full-sync` runs, **Then** shelf writes a proposal to `@inbox/open/` with `type: manifest-proposal`, `kind: content-change`, and `target: @second-brain/projects/<project-slug>/mistakes/2026-04-16-foo.md`.
2. **Given** `.kiln/mistakes/2026-04-16-foo.md` was synced previously and its content hash is unchanged, **When** `shelf:shelf-full-sync` runs again, **Then** shelf does not write a new proposal for that file.
3. **Given** a proposal for `foo.md` was accepted and moved out of `@inbox/open/`, **When** `shelf:shelf-full-sync` runs again, **Then** shelf does not re-propose the same file (tracked via state entry or frontmatter marker).

---

### User Story 4 - Plugin-portable workflow runs from consumer repo install (Priority: P2)

The workflow `report-mistake-and-sync.json` runs successfully from a consumer project where only the installed-plugin cache path exists (not the source `plugin-kiln/` tree). Every command step resolves its script via `${WORKFLOW_PLUGIN_DIR}/scripts/...` rather than repo-relative paths like `plugin-kiln/scripts/...`.

**Why this priority**: Per PRD "Absolute Must #6" and `CLAUDE.md` portability rule: a workflow that silently works in the source repo and silently breaks in consumer repos is a P1 bug. Marked P2 here only because v1 of this feature adds very few command-step scripts (mostly MCP agent calls), so the blast radius is smaller than for `report-issue-and-sync` — but the rule is non-negotiable.

**Independent Test**: Run `/wheel:wheel-run report-mistake-and-sync` from a fresh consumer checkout where only `~/.claude/plugins/cache/...` contains the plugin, and confirm the command step(s) resolve and produce non-empty output in `.wheel/outputs/`.

**Acceptance Scenarios**:

1. **Given** the plugin is installed only at `~/.claude/plugins/cache/yoshisada-speckit/kiln/<version>/`, **When** a user runs `/wheel:wheel-run report-mistake-and-sync` from a consumer repo, **Then** every command-step script resolves (no "No such file or directory") and step outputs land in `.wheel/outputs/` non-empty.
2. **Given** the workflow JSON is being authored, **When** a reviewer searches for `plugin-kiln/scripts/` or `plugin-shelf/scripts/` in `report-mistake-and-sync.json`, **Then** no matches are found (only `${WORKFLOW_PLUGIN_DIR}/scripts/...`-style references).

---

### User Story 5 - Filename slug summarizes the assumption, not the action (Priority: P2)

The filename under `.kiln/mistakes/` is `YYYY-MM-DD-<assumption-slug>.md`, where `<assumption-slug>` is kebab-cased from the `assumption:` sentence (stop-words stripped, truncated to ≤50 chars). The slug names the trap future agents should watch for, not what the AI did about it.

**Why this priority**: Per PRD "Absolute Must #7": training-data discoverability depends on this. Future agents grepping `.kiln/mistakes/` rely on slugs that describe the assumption class.

**Independent Test**: Submit `assumption: I assumed plugin caches live per-vault`, `correction: I moved the caches to per-project`. Verify the filename uses the assumption stem (e.g. `plugin-caches-are-per-vault`) and NOT the correction (not `moved-caches-to-per-project`).

**Acceptance Scenarios**:

1. **Given** `assumption: I assumed the WORKFLOW_PLUGIN_DIR variable was always exported` and `correction: It is only exported after wheel dispatch`, **When** the filename is derived, **Then** the slug resembles `workflow-plugin-dir-always-exported` (or equivalent assumption-centric kebab phrase), not `export-workflow-plugin-dir-before-dispatch`.
2. **Given** the derived slug would exceed 50 characters, **When** the filename is formed, **Then** the slug is truncated at a word boundary and no ≥50-char filename is written.

---

### Edge Cases

- **Empty workflow invocation**: If the skill is called with no free-form description, the `create-mistake` agent step prompts for one before proceeding. The workflow never writes an empty artifact.
- **Filename collision**: Two mistakes captured on the same date with identical slugs produce `-2`, `-3`, ... suffixes. The workflow never overwrites.
- **Missing MCP scope for `@inbox/open/`**: If the MCP server providing write access to `@inbox/open/` is unavailable, shelf's proposal write fails; the local `.kiln/mistakes/` artifact remains and shelf logs the failure for retry on the next sync. The local file is never deleted or marked filed just because the MCP write failed.
- **Model ID detection for `made_by`**: The workflow infers a default from the runtime model ID (lowercased, kebabed), then asks the agent to confirm. If confirmation is skipped (automated context), the inferred default stands. If inference is impossible, the agent must supply `made_by` explicitly before the write proceeds.
- **Honesty lint false positives**: If an agent legitimately needs hedge-like wording (rare — "I assumed X might happen"), v1 has no bypass flag. The agent must rephrase. This is intentional; escape hatches defeat the lint.
- **Proposal accepted then file re-edited locally**: If a proposal was accepted (moved out of `@inbox/open/`) and then the local `.kiln/mistakes/` file is edited, shelf MUST NOT re-propose the edited version in v1. It is treated as already-filed. Re-filing an edit is a later-phase feature.
- **Manifest-type schema drift**: If `@manifest/types/mistake.md` adds a new required field during implementation, the workflow's field collection list must be updated. v1 assumes the schema in the manifest at feature-merge time is stable.
- **Two `mistake/*` tags allowed only when genuine**: The lint permits a second `mistake/*` tag only when the agent explicitly confirms cross-class intent. Default rejection keeps the taxonomy clean.

## Requirements *(mandatory)*

### Functional Requirements

#### Skill entrypoint

- **FR-001**: The system MUST expose a `/kiln:mistake` skill at `plugin-kiln/skills/mistake/SKILL.md` that is user-invocable via the standard slash-command convention and discoverable in the kiln plugin's skill listing. (PRD FR-1)
- **FR-002**: The `/kiln:mistake` skill MUST be a thin wheel-workflow wrapper whose only responsibilities are (a) capturing the user's free-form description from the slash-command argument, (b) activating the `report-mistake-and-sync` wheel workflow via the plugin's wheel activation path, and (c) stopping. It MUST NOT prompt for structured fields, run lints, validate, or write files itself — parity with the existing `/report-issue` skill. (PRD FR-2)
- **FR-003**: The skill's `SKILL.md` MUST include LLM guardrails quoted or summarized from `@manifest/types/mistake.md` — honesty principle, severity calibration, "do not write mistake notes about the human", and "filename slug names the trap" — as read-only reference context for the invoking agent. Enforcement lives in the workflow's agent step, not in the skill. (PRD FR-3)

#### Wheel workflow

- **FR-004**: The system MUST ship a wheel workflow at `plugin-kiln/workflows/report-mistake-and-sync.json`, versioned `1.0.0` on initial release, with exactly three steps in order: (1) `check-existing-mistakes` of `type: command`, (2) `create-mistake` of `type: agent`, (3) `full-sync` of `type: workflow` with `terminal: true`. Step shape parity with `plugin-kiln/workflows/report-issue-and-sync.json`. (PRD FR-4)
- **FR-005**: Step 1 (`check-existing-mistakes`, `type: command`) MUST list `.kiln/mistakes/*.md` and — if present — `@manifest/recent-session-mistakes/` so the `create-mistake` agent can detect duplicates. It MUST write its output to `.wheel/outputs/check-existing-mistakes.txt`. If the step invokes any script, all paths MUST be of the form `${WORKFLOW_PLUGIN_DIR}/scripts/...` — no `plugin-kiln/scripts/...` repo-relative paths. (PRD FR-5)
- **FR-006**: Step 2 (`create-mistake`, `type: agent`) MUST be the single point where manifest schema conformance is enforced. Its `instruction:` field MUST direct the agent to:
  1. Read the workflow activation context for the user's free-form mistake description.
  2. Collect every required field from `@manifest/types/mistake.md`: `date` (ISO-8601, default today), `status` (`unresolved` | `worked-around` | `fixed` | `accepted`), `made_by` (lowercase-kebab model name, inferred from runtime with agent confirmation), `assumption` (one sentence, first-person past tense), `correction` (one sentence, first-person present tense), `severity` (`minor` | `moderate` | `major`), `tags` (three-axis per FR-008), and an H1 title.
  3. Collect the five body sections `What happened`, `The assumption`, `The correction`, `Recovery`, `Prevention for future agents`. Empty sections MUST be written as `_none_` (never omitted).
  4. Apply the honesty-principle lint (FR-007).
  5. Apply the three-axis tag lint (FR-008).
  6. Derive the filename slug from the `assumption:` field per FR-009.
  7. Write the artifact to `.kiln/mistakes/YYYY-MM-DD-<assumption-slug>.md` using the structure in `@manifest/templates/mistake.md`, with the template's metadata block stripped.
  8. Refuse to overwrite existing files — append `-2`, `-3` suffix on collision.
  9. Write a confirmation summary to `.wheel/outputs/create-mistake-result.md` listing the filename, assumption, severity, and tags. (PRD FR-6)
- **FR-007**: The `create-mistake` step MUST enforce a honesty-principle lint:
  - Reject `assumption:` values containing any of: `may have`, `might have`, `possibly`, `could have`, `somewhat`, `a bit`, `arguably`, `perhaps` (case-insensitive substring match).
  - Reject `assumption:` that does not begin with `I ` (first-person past).
  - Reject `correction:` that does not begin with one of `I `, `The `, `It `.
  - On rejection, re-prompt the agent for the offending field. No bypass flag in v1. (PRD FR-7)
- **FR-008**: The `create-mistake` step MUST enforce a three-axis tag lint:
  - Exactly one `mistake/*` tag from the manifest vocabulary (`mistake/assumption`, `mistake/tool-use`, `mistake/scope`, `mistake/context`, `mistake/fabrication`, `mistake/premature-action`, `mistake/communication`). A second `mistake/*` tag is permitted only when the agent explicitly confirms the mistake genuinely spans classes.
  - At least one `topic/*` tag.
  - At least one tag matching `language/*`, `framework/*`, `lib/*`, `infra/*`, `testing/*`, or `blockchain/*`.
  - On rejection, re-prompt for the missing axis. (PRD FR-8)
- **FR-009**: The filename slug MUST be derived from the `assumption:` sentence — not the `correction:`, and not the action taken. The slug MUST be kebab-cased, stop-words stripped, truncated at a word boundary to ≤50 characters. Matches the manifest rule that the slug names the trap future agents should watch for. (PRD FR-9, Absolute Must #7)
- **FR-010**: Step 3 (`full-sync`, `type: workflow`, `terminal: true`) MUST invoke `shelf:shelf-full-sync` as a terminal sub-workflow, identical in shape to how `report-issue-and-sync.json` chains into `shelf:shelf-full-sync`. After the sub-workflow completes, the outer workflow state MUST archive to `.wheel/history/success/` or `.wheel/history/failure/`. (PRD FR-10)

#### Shelf pickup and proposal flow

- **FR-011**: The system MUST extend `plugin-shelf/workflows/shelf-full-sync.json` so that its work-list computation discovers `.kiln/mistakes/*.md` in the same pass that discovers `.kiln/issues/*.md`. The discovery MUST live in `plugin-shelf/scripts/compute-work-list.sh` (extended) or a sibling script under `plugin-shelf/scripts/`, invoked from the workflow via `${WORKFLOW_PLUGIN_DIR}/scripts/...`. (PRD FR-11)
- **FR-012**: For each new or changed mistake artifact, shelf MUST generate a proposal note in `@inbox/open/` via the appropriate Obsidian MCP server, with frontmatter `type: manifest-proposal`, `kind: content-change`, `target: @second-brain/projects/<project-slug>/mistakes/<filename>`, and a body that explicitly calls out "this is a mistake draft" per the workaround path in `@manifest/systems/projects.md`. Shelf MUST NEVER write directly to `@second-brain/projects/<slug>/mistakes/`. (PRD FR-12, Absolute Must #4)
- **FR-013**: Shelf skip-on-unchanged MUST apply: a `.kiln/mistakes/` file whose content hash matches the prior sync MUST NOT be re-proposed. Uses the same content-hash strategy already used for issues/docs in `update-sync-manifest.sh`. (PRD FR-13)
- **FR-014**: Once a proposal has been accepted (moved out of `@inbox/open/`), shelf MUST NOT re-propose the same source file. The local `.kiln/mistakes/` artifact is retained for history but is marked as "filed" via a sibling state entry or frontmatter marker to prevent resurrection loops. (PRD FR-14)

#### Infrastructure / portability

- **FR-015**: The skill/workflow pair MUST be registered and discoverable. If `plugin-kiln/.claude-plugin/plugin.json` maintains an explicit `skills:` listing, the new skill MUST be added; otherwise filesystem auto-discovery is sufficient. `plugin-kiln/workflows/` MUST contain the workflow JSON. A local-override copy MAY be placed at the consumer-repo `workflows/report-mistake-and-sync.json`, matching the existing override pattern shelf uses. (PRD FR-15)
- **FR-016**: The workflow MUST run cleanly in both the source repo and the installed-plugin cache context. Every command-step script MUST be reachable via `${WORKFLOW_PLUGIN_DIR}/scripts/...` so a consumer-only install produces non-empty step outputs. No `plugin-kiln/scripts/...` or `plugin-shelf/scripts/...` repo-relative paths are permitted in the workflow JSON. (PRD FR-16, Absolute Must #6, `CLAUDE.md` portability rule)

### Key Entities

- **Mistake Artifact** (`.kiln/mistakes/YYYY-MM-DD-<assumption-slug>.md`): Local-first, schema-conformant Markdown file. Frontmatter per `@manifest/types/mistake.md` (`date`, `status`, `made_by`, `assumption`, `correction`, `severity`, `tags`). Body has five fixed sections. Produced by the `create-mistake` step, consumed by shelf, retained as history after filing.
- **Proposal Note** (`@inbox/open/<proposal-filename>.md`): Obsidian note with `type: manifest-proposal`, `kind: content-change`, `target: @second-brain/projects/<slug>/mistakes/<source-filename>`. Body identifies this as a mistake draft. Produced by shelf's MCP write step. Consumed by a human reviewer who accepts or rejects the proposal.
- **Work-List Entry**: Shelf's internal record of a discovered artifact keyed by path + content hash. Used for skip-on-unchanged and filed-state tracking.
- **Workflow State File** (`.wheel/state_*.json`): Per-run JSON state persisted by the wheel engine. Archived to `.wheel/history/success/` or `.wheel/history/failure/` after the terminal step. Auditable trail of every `/kiln:mistake` invocation.
- **Workflow Step Outputs** (`.wheel/outputs/*.txt`, `.wheel/outputs/*.md`): Ephemeral per-step outputs. Specifically `.wheel/outputs/check-existing-mistakes.txt` (Step 1) and `.wheel/outputs/create-mistake-result.md` (Step 2).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: ≥80% of mistake notes produced by the workflow in the first month pass manifest schema validation on first try — three-axis tags present, required fields filled, filename format correct, honesty lint clean — without re-prompting. Measured by parsing `.kiln/mistakes/` against the manifest schema. (PRD Success Metric 1)
- **SC-002**: Zero direct writes to `@second-brain/projects/<slug>/mistakes/` over the first month. Every note that lands there arrives via the `@inbox/open/` proposal path. Measured by spot-checking file-creation source in the Obsidian audit log. (PRD Success Metric 2, Absolute Must #4)
- **SC-003**: The first real mistake captured in this repo completes the full round trip — `/kiln:mistake` → wheel activation → `.kiln/mistakes/` write → `shelf:shelf-full-sync` → `@inbox/open/` proposal → accepted into `<project>/mistakes/` — within 7 days of feature merge. (PRD Success Metric 3)
- **SC-004**: Every `/kiln:mistake` invocation produces exactly one state file in `.wheel/history/success/` or `.wheel/history/failure/`, with zero orphaned `.wheel/state_*.json` files after completion. Measured after 10 runs. (PRD Success Metric 4)
- **SC-005**: An agent can go from "user just corrected me" to a conformant mistake note committed to `.kiln/mistakes/` in ≤30 seconds of wall-clock interaction time, excluding any time spent thinking about what to write. Measured by timing five captures end-to-end.
- **SC-006**: The workflow produces zero "No such file or directory" errors when run from a consumer-only install (plugin cache path present, source `plugin-kiln/` tree absent). Measured by running `/wheel:wheel-run report-mistake-and-sync` in a fresh consumer checkout and inspecting `.wheel/outputs/` for non-empty step outputs.

## Assumptions

- `@manifest/types/mistake.md` (last_updated 2026-04-16), `@manifest/templates/mistake.md`, and `@manifest/systems/projects.md` are stable and will not change under the implementation during the feature build.
- `@inbox/open/` is writable via one of the available Obsidian MCP servers. The specific scope (`mcp__obsidian-projects__*` vs. `mcp__claude_ai_obsidian-manifest__*`) is resolved during `/plan`. If no scope can write to `@inbox/open/`, the proposal write falls back to a local file the user hand-files — this fallback is acceptable for v1 but flagged as a blocker to resolve.
- The post-`005e259` wheel portability fix (i.e., `WORKFLOW_PLUGIN_DIR` exported from `plugin-wheel/lib/dispatch.sh` before command-step dispatch) is a hard prerequisite and is already merged on `main`.
- The consumer repo has either the kiln plugin installed via the Claude Code marketplace, or is running the source repo where `plugin-kiln/` lives at the project root.
- Contributors invoking `/kiln:mistake` have enough session context to answer the workflow prompts accurately. If they do not, the correct behavior is to skip the capture rather than to produce a hedged or fabricated note.
- Model-ID detection for `made_by` is best-effort: the workflow infers from the runtime context (lowercased, kebabed) and asks the agent to confirm. Inference failure does not block the capture as long as `made_by` is eventually supplied.
- Shelf's content-hash strategy in `update-sync-manifest.sh` is already load-bearing for issues/docs and can be extended to `.kiln/mistakes/` without schema changes to the sync manifest.
- Auto-capture from hook/agent/tool-call errors, retroactive transcript backfill, `led_to_decision` / `prompted_by_mistake` cross-link automation, formal `mistake-draft` proposal kind registration, and severity auto-calibration are all explicitly out of scope for v1.

## Out of Scope (v1)

- Direct writes to `@second-brain/projects/<slug>/mistakes/` — manifest mandates proposal flow through `@inbox/open/`. Bypass is a rejection.
- Auto-capture from hook failures, agent errors, tool-call errors. V1 is human-invoked only.
- Backfill tooling that synthesizes historical mistake notes from session transcripts.
- Registering a formal `mistake-draft` proposal kind. V1 uses existing `kind: content-change` with an explanatory body.
- Severity auto-calibration. The skill asks; it does not decide.
- Cross-linking automation (`led_to_decision`, `prompted_by_mistake`). V1 lets the user fill these manually.
- The `## Mistakes` Dataview rollup in `<project>/<project>.md`. Tracked as a separate downstream change.
