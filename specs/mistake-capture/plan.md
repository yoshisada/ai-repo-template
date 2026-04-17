# Implementation Plan: Mistake Capture

**Branch**: `build/mistake-capture-20260416` | **Date**: 2026-04-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/mistake-capture/spec.md`
**PRD**: `docs/features/2026-04-16-mistake-capture/PRD.md`

## Summary

Add `/kiln:mistake` as a thin skill that activates the `report-mistake-and-sync` wheel workflow. The workflow has three steps — `check-existing-mistakes` (command), `create-mistake` (agent, enforces `@manifest/types/mistake.md` schema + honesty lint + three-axis tag lint), and `full-sync` (terminal sub-workflow to `shelf:shelf-full-sync`). Shelf is extended so its existing work-list computation discovers `.kiln/mistakes/*.md` on every sync and writes `@inbox/open/` proposal notes via Obsidian MCP. The `@inbox/open/` route is mandatory — no direct writes to `<project>/mistakes/`.

Architectural parity with `/report-issue` → `report-issue-and-sync.json` is the single strongest design constraint. Every deviation from that pattern must be justified in this plan.

## Technical Context

**Language/Version**: Markdown (skill/workflow definitions), Bash 5.x (command-step scripts and discovery helpers), JSON (wheel workflow definition). No new runtime languages.
**Primary Dependencies**: Kiln plugin (`@yoshisada/kiln`), shelf plugin (`plugin-shelf`), wheel engine (`plugin-wheel` — post-`005e259` `WORKFLOW_PLUGIN_DIR` export REQUIRED), Obsidian MCP (`mcp__obsidian-projects__*` assumed pending research verification; manifest MCP is a fallback).
**Storage**: File-based — `.kiln/mistakes/*.md` (local mistake artifacts), `.wheel/outputs/*.{txt,md,json}` (ephemeral step outputs), `.wheel/history/` (archived workflow state), `@inbox/open/` (Obsidian proposals), sync manifest at `.wheel/outputs/sync-manifest.json` (or wherever shelf currently persists it; extended schema documented in data-model.md).
**Testing**: Manual end-to-end via `/wheel:wheel-run report-mistake-and-sync`. No automated test suite for plugin artifacts (consistent with `CLAUDE.md` — "There is no test suite for the plugin itself"). Smoke-test target is `/wheel:wheel-run report-mistake-and-sync` from a consumer-only install.
**Target Platform**: Claude Code CLI (macOS, Linux, Windows) via plugin marketplace. Must work from both (a) source repo checkout and (b) installed-plugin cache path.
**Project Type**: Claude Code plugin (kiln) + sibling plugin extension (shelf). No `src/` — plugin assets only.
**Performance Goals**: ≤30 s wall-clock from `/kiln:mistake` invocation to `.kiln/mistakes/` file write (excluding agent-think time); zero added MCP writes per sync when no new mistakes exist.
**Constraints**: (1) Absolute wheel parity with `/report-issue`. (2) Manifest-conformance non-negotiable; no partial writes. (3) Plugin portability — command-step scripts via `${WORKFLOW_PLUGIN_DIR}/scripts/...` only. (4) No direct writes to `<project>/mistakes/`; proposal flow through `@inbox/open/` only. (5) No new runtime dependencies.
**Scale/Scope**: Individual developer / small-team volume — tens of mistake notes per month per contributor, bounded by honest-capture rate. No concurrency requirements beyond wheel's existing single-run-per-workflow guard.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-First (NON-NEGOTIABLE) | PASS | `specs/mistake-capture/spec.md` committed before any plan work. FR-001 through FR-016 trace 1:1 to PRD FR-1 through FR-16. |
| II. 80% Test Coverage Gate (NON-NEGOTIABLE) | N/A | Kiln/shelf plugin assets are Markdown + Bash + JSON; there is no test suite for the plugin itself (per `CLAUDE.md`). Smoke-test via `/wheel:wheel-run` replaces line-coverage gate. Document this as a justified deviation in Complexity Tracking. |
| III. PRD as Source of Truth | PASS | PRD at `docs/features/2026-04-16-mistake-capture/PRD.md` is authoritative. Spec does not diverge from it. |
| IV. Hooks Enforce Rules | PASS | No hook changes required. The existing kiln 4-gate hook set does not cover plugin-asset edits (`plugin-kiln/`, `plugin-shelf/`) — edits to those paths are permitted without `src/` gating. |
| V. E2E Testing Required | PASS | User Story 1, 3, 4 acceptance scenarios are all end-to-end through the real wheel engine. Smoke path documented in `quickstart.md`. |
| VI. Small, Focused Changes | PASS | The feature adds one skill file, one workflow JSON, at most one script under `plugin-kiln/scripts/`, and an extension to one existing shelf script + one workflow agent step. No file will exceed 500 lines. |
| VII. Interface Contracts Before Implementation (NON-NEGOTIABLE) | PASS | `contracts/interfaces.md` produced in Phase 1 of this plan (see below). Covers: skill activation contract, workflow JSON schema, `check-existing-mistakes.sh` script signature, shelf work-list-extension signature, proposal frontmatter contract. |
| VIII. Incremental Task Completion (NON-NEGOTIABLE) | PASS | `/tasks` will produce dependency-ordered tasks with explicit commit-after-phase boundaries. Implementers mark `[X]` inline as they go. |

**Gate result**: PASS with one documented deviation (II — no automated unit test suite; smoke test substitutes). See Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/mistake-capture/
├── plan.md                              # This file
├── spec.md                              # Already written
├── research.md                          # Phase 0 output (this /plan run)
├── data-model.md                        # Phase 1 output (this /plan run)
├── quickstart.md                        # Phase 1 output (this /plan run)
├── contracts/
│   └── interfaces.md                    # Phase 1 output (this /plan run) — contract source of truth
├── agent-notes/
│   └── specifier.md                     # Friction note (written before task-complete)
├── checklists/
│   └── requirements.md                  # Spec quality checklist (already written)
└── tasks.md                             # Phase 2 output (/tasks — NOT this plan)
```

### Source Code (repository root)

This feature touches plugin assets, not `src/`. The layout below lists every file the implementation will create or modify, grouped by plugin.

```text
plugin-kiln/
├── skills/
│   └── mistake/
│       └── SKILL.md                     # NEW — thin /kiln:mistake skill
├── workflows/
│   └── report-mistake-and-sync.json     # NEW — wheel workflow, 3 steps
└── scripts/
    └── check-existing-mistakes.sh       # NEW — command step for Step 1 (portable)

plugin-shelf/
├── scripts/
│   └── compute-work-list.sh             # MODIFIED — extended to discover .kiln/mistakes/*.md
├── workflows/
│   └── shelf-full-sync.json             # MODIFIED — obsidian-apply agent step gains
│                                        #            mistakes-array handling + @inbox/open/ writes
└── scripts/
    └── update-sync-manifest.sh          # MODIFIED — manifest gains "mistakes" array

specs/mistake-capture/
└── agent-notes/                          # NEW — specifier, impl-kiln, impl-shelf, auditor, retrospective notes land here

.kiln/
└── mistakes/                             # NEW directory — created by the workflow on first write
    └── YYYY-MM-DD-<assumption-slug>.md   # Artifacts
```

**Structure Decision**: Plugin-asset change. No `src/` involvement. Two plugins touched: `plugin-kiln` (owns the skill, workflow, and command-step script) and `plugin-shelf` (owns the discovery extension and the proposal-write agent-step logic). Implementation tasks split cleanly along this boundary — impl-kiln owns everything under `plugin-kiln/` plus the spec artifacts, impl-shelf owns everything under `plugin-shelf/`. See tasks.md for the explicit ownership split.

## Phase 0: Research

Consolidated research findings are in [research.md](./research.md). Summary of decisions:

1. **Single vs separate command-step script**: Use a single new script `plugin-kiln/scripts/check-existing-mistakes.sh` invoked from the workflow via `${WORKFLOW_PLUGIN_DIR}/scripts/check-existing-mistakes.sh`. Rationale: parity with how shelf factors its command steps (`read-sync-manifest.sh`, `compute-work-list.sh`, etc.) and avoids embedding complex listing logic inline in the workflow JSON. The existing `report-issue-and-sync.json` inlines its `check-existing-issues` step, but that step is a trivial `ls`. Ours has to handle two directories plus structured output for the agent to consume — factor it out.
2. **MCP scope for `@inbox/open/` writes**: Research note — the working assumption is that `mcp__obsidian-projects__*` has write access across the whole Obsidian vault including `@inbox/`. Fallback is `mcp__claude_ai_obsidian-manifest__*`. Verification during implementation (impl-shelf) — if `mcp__obsidian-projects__create_file` with `path: "@inbox/open/<filename>.md"` fails due to scope, switch to the manifest MCP and document the finding. No code branching for MCP scope is needed upfront.
3. **Proposal filename convention in `@inbox/open/`**: `YYYY-MM-DD-mistake-<assumption-slug>.md` — the `mistake-` infix keeps proposal listings scannable in the inbox. Source slug is re-used from the local `.kiln/mistakes/` filename. See contracts/interfaces.md §5.
4. **Tracking "filed" state (FR-014 resurrection prevention)**: Extend the existing sync manifest (`.wheel/outputs/sync-manifest.json`) with a new top-level `mistakes:` array parallel to `issues:` and `docs:`. Each entry records `path`, `filename_slug`, `source_hash`, `proposal_path`, and `proposal_state: "open" | "filed"`. On sync, shelf reads the state of `@inbox/open/<proposal>` via MCP (or infers from absence → filed) and updates the manifest. Filed entries are never re-proposed. Alternative considered: a frontmatter marker on the local `.kiln/mistakes/` file itself — rejected because it would mutate the artifact and complicate content-hash comparison.
5. **Honesty-lint and tag-lint location**: Both live inside the `create-mistake` agent step's `instruction:` field, NOT as a separate script. Rationale: the lint is natural-language regex applied to free-form agent input, and the agent is already going to re-prompt — offloading to a shell script would require round-tripping which breaks the UX. The `instruction:` text is long but single-point-of-enforcement is the correct structural choice.
6. **Model ID detection for `made_by`**: The workflow's agent step asks the agent to infer from its own runtime context (e.g., "claude-opus-4-7", "claude-sonnet-4-6") and kebab-case it. The agent then confirms with the user. No programmatic detection via shell or environment variable — all Claude-model detection is done from the agent's own knowledge of its model. Rationale: the model ID is available to the agent directly; a shell script has no reliable way to determine which Claude model is orchestrating the workflow.
7. **Three-step structure vs four-step**: Keep to three steps (command → agent → terminal workflow). Absolute parity with `report-issue-and-sync.json`. Adding a fourth step (e.g., a "write-artifact" command step after the agent step) would duplicate work the agent step already does and break parity.
8. **Local-override path for workflow**: Accept both `plugin-kiln/workflows/report-mistake-and-sync.json` (source of truth) and consumer-repo `workflows/report-mistake-and-sync.json` (override). Wheel's existing discovery handles this — no new logic needed.

## Phase 1: Design & Contracts

### Data model

See [data-model.md](./data-model.md). Entities:
1. Mistake Artifact (frontmatter schema per `@manifest/types/mistake.md` + five-section body)
2. Proposal Note (frontmatter: `type: manifest-proposal`, `kind: content-change`, `target:`)
3. Sync Manifest `mistakes[]` entry (`path`, `filename_slug`, `source_hash`, `proposal_path`, `proposal_state`)
4. Workflow Step Outputs (`.wheel/outputs/check-existing-mistakes.txt`, `.wheel/outputs/create-mistake-result.md`)
5. Workflow State File (`.wheel/state_*.json` → archived to `.wheel/history/<status>/`)

### Interface contracts

See [contracts/interfaces.md](./contracts/interfaces.md). Contracts cover:
1. Skill activation contract (`/kiln:mistake` SKILL.md — what argument shape, what workflow to activate, no structured prompting).
2. Workflow JSON shape for `report-mistake-and-sync.json` (three steps, exact `id`/`type`/`output`/`context_from` per step).
3. Command-step script `check-existing-mistakes.sh` — inputs (none from env beyond `WORKFLOW_PLUGIN_DIR`), outputs (format of `.wheel/outputs/check-existing-mistakes.txt`).
4. Shelf work-list-extension contract — the extension point in `compute-work-list.sh` (a new `mistakes_actions` array parallel to `issues_actions` and `docs_actions`) plus the extended top-level JSON schema at `.wheel/outputs/compute-work-list.json`.
5. Proposal write contract — frontmatter fields shelf must write to `@inbox/open/<filename>`, filename convention, body template.
6. Sync-manifest extension — the `mistakes[]` array shape and the `proposal_state` state machine (`open` → `filed`).

### Quickstart

See [quickstart.md](./quickstart.md). Walks through: (a) run `/kiln:mistake` with a sample correction, (b) watch the three wheel steps execute, (c) verify the `.kiln/mistakes/` artifact matches schema, (d) verify the `@inbox/open/` proposal appears, (e) accept the proposal by moving it out of `@inbox/open/` and confirm the next sync does not resurrect it.

### Agent context update

`/update-agent-context.sh claude` will append the following under "Active Technologies":
- Bash 5.x (mistake-capture command step + shelf extension), Markdown (skill + workflow instruction), JSON (workflow + manifest) + Wheel workflow engine, Obsidian MCP — build/mistake-capture-20260416

No new runtime languages, frameworks, or dependencies — everything is inherited from the existing kiln + shelf + wheel + Obsidian MCP stack.

## Phase 2 Planning (Task Generation) — handled by `/tasks`

Not produced here. `/tasks` will:
- Group tasks by owner (`impl-kiln`, `impl-shelf`) per the plugin boundary.
- Order tasks by dependency — skill + workflow JSON depend on the `check-existing-mistakes.sh` script existing; shelf extension depends on the workflow existing so smoke tests have something to drive.
- Include a phase boundary for "commit plugin-kiln changes", "commit plugin-shelf changes", and a final "smoke test" phase that runs `/wheel:wheel-run report-mistake-and-sync` end-to-end.
- Attach contract references (`see contracts/interfaces.md §N`) to every task that writes a file the contract governs.

## Complexity Tracking

| Violation / Deviation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Constitution II. 80% Test Coverage Gate — no automated unit tests | Plugin assets are Markdown + Bash + JSON. There is no test harness for kiln or shelf plugin assets (per `CLAUDE.md`: "There is no test suite for the plugin itself"). Writing a unit-test harness for a wheel workflow is out of scope for this feature and is tracked separately. | Building a workflow unit-test harness would multiply the feature's scope by 3–5× and the feature itself is a zero-friction capture tool — gating it behind an untested test harness inverts the value prop. Smoke test via `/wheel:wheel-run` substitutes and exercises every integration point (skill activation → workflow dispatch → command step → agent step → sub-workflow) on real artifacts. Smoke-test acceptance documented in `quickstart.md`. |
| Extending sync manifest to add `mistakes[]` array | FR-013 (skip-on-unchanged) and FR-014 (no resurrection) both require per-file state tracking across syncs. The existing manifest already tracks per-path state for `issues[]` and `docs[]`; adding a parallel `mistakes[]` array is the minimum-delta approach. | Using a sibling state file (e.g., `.wheel/outputs/mistakes-state.json`) was rejected because it would fragment sync state across two files and require `compute-work-list.sh` and `update-sync-manifest.sh` to read/write two files. Keeping everything in the one manifest preserves the single-file invariant shelf already relies on. |
