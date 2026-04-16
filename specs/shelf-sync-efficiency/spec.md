# Feature Specification: Shelf Full Sync — Efficiency Pass

**Feature Branch**: `build/shelf-sync-efficiency-20260416`
**Created**: 2026-04-10
**Updated**: 2026-04-16 (v5 manifest-based architecture)
**Status**: In Progress
**Input**: Refactor `plugin-shelf/workflows/shelf-full-sync.json` for efficiency. v4 consolidated four agent steps into 2 but had a confirmed regression (B-002/B-005) where doc updates overwrote LLM-inferred fields with hardcoded defaults. v5 replaces the vault-reading discovery agent with a local manifest (`.shelf-sync.json`) and introduces CREATE vs UPDATE semantics that preserve inferred fields. Target: ≤1 agent step, manifest-based diff, no vault reads for diffing, drop-in replacement.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - End-of-Session Sync Without Token Anxiety (Priority: P1)

A shelf plugin user finishes a coding session and runs `/shelf-sync` to push issues, docs, tags, and progress updates to their Obsidian vault. With v3 costing 64.5k tokens, they used to skip or batch syncs; with v4 they can run it every session.

**Why this priority**: This is the headline value of the feature — cheap, routine sync unblocks the shelf plugin's intended usage pattern and is the gate users notice.

**Independent Test**: Run `/shelf-sync` on the benchmark reference repo. Record token cost via wheel-runner telemetry. Verify the run completes successfully, produces the terminal summary at `.wheel/outputs/shelf-full-sync-summary.md` with the five expected sections, and costs ≤30k tokens.

**Acceptance Scenarios**:

1. **Given** the benchmark reference repo in a clean state, **When** `/shelf-sync` invokes `shelf-full-sync`, **Then** the workflow completes successfully, spawns no more than 2 agent steps, and total token cost reported by wheel-runner is ≤30k.
2. **Given** the benchmark reference repo, **When** `shelf-full-sync` finishes, **Then** `.wheel/outputs/shelf-full-sync-summary.md` exists and contains the sections `Issues`, `Docs`, `Tags`, `Progress`, and `Errors` in that order.
3. **Given** any caller (`/shelf-sync` skill or `report-issue-and-sync` composed workflow), **When** it invokes `shelf-full-sync` by name, **Then** it succeeds without any caller-side change.

---

### User Story 2 - Behavioral Parity With v3 (Priority: P1)

A plugin maintainer verifies that v4 does not silently regress sync behavior. Running v3 and v4 against the same frozen reference repo must produce an identical set of Obsidian file creates and updates — same paths, same frontmatter, same body content.

**Why this priority**: Parity is the precondition for shipping. Cheaper sync that drifts from v3 output is a regression, not an improvement.

**Independent Test**: Capture an Obsidian-writes snapshot (paths + final frontmatter + body per file) from a v3 run on the reference fixture. Run v4 against the same fixture and capture the same snapshot. Diff the two snapshots — they must match exactly.

**Acceptance Scenarios**:

1. **Given** a frozen reference repo fixture and a baseline Obsidian snapshot captured from v3, **When** v4 runs against the same fixture, **Then** the resulting Obsidian snapshot is byte-for-byte identical to the v3 snapshot for every issue note, doc note, and dashboard file.
2. **Given** v4 running against the fixture, **When** the dashboard file is updated, **Then** all frontmatter fields preserved by v3 (`Human Needed`, `Feedback`, `Feedback Log`, `About`, tag lists, and any other fields v3 wrote or preserved) are present and unchanged in meaning.

---

### User Story 3 - Large-Vault Safety (Priority: P2)

A shelf user with a mature project (≥50 GitHub issues, ≥20 PRDs) runs `/shelf-sync`. The workflow must complete without any single agent step hitting its context ceiling — the pre-filtering of work lists in command steps is what keeps the per-agent payload small enough.

**Why this priority**: Consolidating agents is the obvious win; the risk is that a single agent now receives too much context and fails on big repos. This story gates that risk.

**Independent Test**: Point the workflow at a vault containing at least 50 issues and 20 PRDs. Run `shelf-full-sync` and verify it completes with no context-ceiling errors from any agent step.

**Acceptance Scenarios**:

1. **Given** a repo/vault with ≥50 GitHub issues and ≥20 PRDs under `docs/features/`, **When** `shelf-full-sync` runs, **Then** each agent step stays under its context ceiling and the workflow terminates successfully.
2. **Given** the same large vault, **When** the workflow runs, **Then** each agent receives only the pre-filtered work list (notes that actually need creating or updating), not the full issues JSON or the full list of existing notes.

---

### Edge Cases

- Empty reference repo: no issues, no PRDs, no tag changes — workflow must still produce a summary file with the five sections (each possibly empty) and not fail.
- No-op run: repo state unchanged since last sync — workflow completes, work lists are empty, no Obsidian writes occur, summary reports zero changes.
- Partial MCP failure: one of the Obsidian MCP writes fails mid-run — the `Errors` section of the summary must capture the failure, the rest of the sync must not be silently dropped.
- Workflow composed inside `report-issue-and-sync`: parent workflow must not need to change its `context_from` or downstream steps because of v4.
- Dashboard file with user edits: sections owned by the user (`About`, `Human Needed`, `Feedback Log`) must be preserved exactly — the consolidated read-modify-write must not clobber them.
- Large issue/doc counts where work-list pre-filtering still produces a payload that approaches the agent context ceiling — workflow must fall back gracefully (e.g., by splitting across the second allowed agent step).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The `shelf-full-sync` workflow MUST contain no more than 1 step of type `agent` (wheel-runner agent spawn). All agent-driven work from v3 — issue sync, doc sync, dashboard tag update, progress update — MUST be accomplished within that limit. (Tightened from <=2 in v4; the discovery agent is eliminated by the manifest approach.)
- **FR-002**: Deterministic diff computation — determining which Obsidian notes need to be created or updated — MUST be performed in `command` steps (Bash + `jq`), not in agent steps. Agent steps MUST receive a pre-filtered work list, not the raw GitHub issues JSON plus the full list of existing notes.
- **FR-003**: The workflow MUST produce behavioral parity with v3 on a frozen reference fixture. A snapshot of all Obsidian file creates and updates (file path, final frontmatter, final body) from a v4 run MUST be identical to the v3 snapshot on the same fixture.
- **FR-004**: The workflow file path and workflow name MUST remain `plugin-shelf/workflows/shelf-full-sync.json` and `shelf-full-sync`. No caller code — `/shelf-sync`, `report-issue-and-sync`, any documentation, any other workflow composing it — MAY require a change to accommodate v4.
- **FR-005**: The workflow MUST write a terminal summary to `.wheel/outputs/shelf-full-sync-summary.md` containing the sections `Issues`, `Docs`, `Tags`, `Progress`, and `Errors`, in that order, matching v3's structure.
- **FR-006**: On a reference vault with ≥50 GitHub issues and ≥20 PRDs under `docs/features/`, the workflow MUST complete successfully without any single agent step hitting its context ceiling.
- **FR-007**: Total token cost for one `shelf-full-sync` run on the pinned benchmark reference repo, measured via wheel-runner telemetry, MUST be ≤30k tokens.
- **FR-008**: All existing v3 command steps — `gather-repo-state`, `read-shelf-config`, `fetch-github-issues`, `read-backlog-issues`, `read-feature-prds`, `detect-tech-stack`, `generate-sync-summary` — MUST remain command steps in v4. This feature only restructures the agent layer and the work-list computation that feeds it.
- **FR-009**: The refactor MUST NOT introduce new runtime dependencies. The allowed tech stack is Bash 5.x, `jq`, the existing wheel engine, and the existing Obsidian MCP tools (`mcp__obsidian-projects__*`).
- **FR-010**: The v3 behavior of merging `update-dashboard-tags` and `push-progress-update` into one read-modify-write cycle on the dashboard file MUST preserve every frontmatter field v3 wrote or preserved, including `Human Needed`, `Feedback`, `Feedback Log`, and `About` sections.
- **FR-011**: The feature MUST include a snapshot-diff harness — a script that captures Obsidian write snapshots from a workflow run and diffs two snapshots — so parity verification (FR-003) can be re-run mechanically rather than by manual inspection.
- **FR-012**: The benchmark reference repo used to measure FR-007 MUST be pinned and documented in the plan artifacts so future measurements are comparable.
- **FR-013**: `context_from` injections in v5 MUST be scoped to only the upstream outputs each step actually consumes. No downstream step may receive full raw upstream output when a pre-filtered work list is available.
- **FR-014**: The workflow MUST maintain a local `.shelf-sync.json` manifest at the repo root recording the `source_hash` of each synced item. The manifest MUST be updated atomically (write-to-temp then move) after obsidian-apply completes. On cold start (manifest missing), all items are treated as CREATE.
- **FR-015**: On UPDATE, obsidian-apply MUST use `patch_file` for programmatic fields only (`source`, `github_number`/`prd_path`, `last_synced`, `project`, `status` for issues). Inferred fields (`summary`, `status` for docs, `category`, `tags` taxonomy, `severity`) MUST NOT be modified on update.
- **FR-016**: On CREATE, obsidian-apply MUST generate inferred fields (`summary`, `status`, `tags`, `category`, `severity`) by reading the source content provided in `source_data` (PRD file content for docs, issue title+body+labels for issues).

### Key Entities

- **Workflow definition** (`plugin-shelf/workflows/shelf-full-sync.json`): Ordered list of wheel steps. Each step has an `id`, a `type` (`command` or `agent`), inputs, and outputs consumed via `context_from`. The terminal step writes the summary file.
- **Sync manifest** (`.shelf-sync.json`): Local JSON file at repo root recording the `source_hash` and vault path of every item synced. Used by `compute-work-list` to determine CREATE vs UPDATE vs SKIP without reading the vault.
- **Work list**: Pre-filtered JSON payload produced by a command step, describing exactly which Obsidian notes need to be created or updated. On CREATE, includes `source_data` for the agent to generate inferred fields. On UPDATE, the agent patches only programmatic fields. The shape is defined in `contracts/interfaces.md`.
- **Programmatic fields**: Frontmatter fields that are deterministically derived and updated on every sync: `source`, `github_number`/`prd_path`, `last_synced`, `project`, `status` (issues only).
- **Inferred fields**: Frontmatter fields set by LLM on CREATE and never modified on UPDATE: `summary`, `tags`, `category`, `severity`, `status` (docs only).
- **Obsidian snapshot**: A deterministic serialization of all Obsidian files written by a workflow run (path -> frontmatter + body), used for parity verification.
- **Benchmark reference repo**: A pinned repo/vault pair used to measure token cost and to anchor the FR-007 gate.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: One `shelf-full-sync` run on the benchmark reference repo costs ≤30k tokens, measured via wheel-runner telemetry (down from the 64.5k v3 baseline).
- **SC-002**: The `shelf-full-sync.json` workflow definition contains no more than 1 step of type `agent` (tightened from <=2 in v4).
- **SC-003**: A v4 run on the frozen reference fixture produces an Obsidian snapshot identical to the v3 snapshot on the same fixture, as reported by the snapshot-diff harness.
- **SC-004**: A `shelf-full-sync` run completes successfully on a vault with ≥50 issues and ≥20 PRDs without any agent step hitting its context ceiling.
- **SC-005**: All existing callers (`/shelf-sync`, `report-issue-and-sync`) continue to invoke `shelf-full-sync` unchanged — zero caller-side diffs required.
- **SC-006**: The terminal summary file at `.wheel/outputs/shelf-full-sync-summary.md` contains the five sections `Issues`, `Docs`, `Tags`, `Progress`, `Errors` in that order on every run.

## Architecture: v4 -> v5 Evolution

### v4 (shipped, regression confirmed)
Two agents: `obsidian-discover` (reads vault, emits index JSON) + `obsidian-apply` (writes from work list). `compute-work-list.sh` diffs repo state vs the index. Regression: for doc updates, bash hardcodes `summary = title` and `status = "Draft"` because it cannot infer these from PRD content. All 24 doc updates would regress the existing vault.

### v5 (manifest-based, fixes B-002/B-005)
One agent: `obsidian-apply` only. The `obsidian-discover` agent is eliminated entirely. Instead, a local `.shelf-sync.json` manifest records `source_hash` for each synced item. `compute-work-list` diffs hashes to determine CREATE/UPDATE/SKIP without reading the vault.

Key insight: we don't need to read the vault at all if we maintain a local manifest of what we've already synced. Context does NOT grow with vault size. No agent reads for diffing.

**CREATE vs UPDATE semantics** (the fix for B-002/B-005):
- On CREATE (item not in manifest): the agent reads `source_data`, generates inferred fields (summary, status, tags, category) via LLM, writes full frontmatter via `create_file`.
- On UPDATE (item in manifest, hash changed): the agent patches ONLY programmatic fields via `patch_file`. Inferred fields are never touched after creation.
- On SKIP (hash unchanged): do nothing.

**Cold start**: When `.shelf-sync.json` doesn't exist, `read-sync-manifest` outputs an empty manifest, `compute-work-list` treats everything as CREATE, obsidian-apply creates with full inferred frontmatter, `update-sync-manifest` creates the manifest with all hashes.

## Assumptions

- The 64.5k token baseline recorded for v3 on 2026-04-07 is representative of typical runs on the benchmark repo rather than an outlier.
- Wheel engine semantics for `context_from` injection, command step execution, and agent spawning remain stable during this work; no wheel engine changes are required.
- Obsidian MCP tools (`mcp__obsidian-projects__*`) behave identically whether invoked from one consolidated agent or from multiple agents — no per-session state that would be broken by consolidation.
- Agents cannot directly invoke Obsidian MCP tools from a `command` step; listing existing Obsidian notes for diff computation will either use `mcp__obsidian-projects__list_files` inside an agent that emits a compact notes-index, or a filesystem-level listing if the vault path is directly accessible. `/plan` will resolve which approach is used.
- A frozen reference fixture repo can be created or reused for snapshot parity testing. If none exists, producing one is in scope for the `/plan` baseline-capture phase.
- The benchmark reference repo referenced in FR-007 and SC-001 will be pinned during `/plan` (likely the same repo where the 64.5k baseline was measured on 2026-04-07).
- The feature does not change Obsidian frontmatter schema, templates, tag taxonomy, or dashboard layout — only the orchestration that produces them.
- No test-coverage gate applies in the usual sense: this feature refactors a JSON workflow and supporting shell glue, not application code. Parity via snapshot diff plus the token-budget gate stand in for line-coverage.
