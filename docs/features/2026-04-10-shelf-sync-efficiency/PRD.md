# Feature PRD: Shelf Full Sync — Efficiency Pass

**Date**: 2026-04-10
**Status**: Draft
**Parent PRD**: docs/features/2026-04-03-shelf-sync-v2/PRD.md

## Parent Product

The shelf plugin syncs repo state (issues, docs, progress, tags) to Obsidian project dashboards via the wheel workflow engine. `shelf-full-sync` is its flagship workflow — composed into `report-issue-and-sync` and invoked directly via `/shelf-sync`. Shelf v2 (2026-04-03) established the current 4-agent structure; this feature revisits that structure now that we have token-cost data.

## Feature Overview

Restructure the `shelf-full-sync` wheel workflow to reduce token cost, latency, and failure surface **without changing sync behavior**. Specifically:

1. Consolidate the four agent steps (`sync-issues-to-obsidian`, `sync-docs-to-obsidian`, `update-dashboard-tags`, `push-progress-update`) into at most two.
2. Move deterministic diff logic (which issues/docs actually need syncing) out of agents and into command steps, so agents only act on pre-filtered work lists.
3. Shrink `context_from` injections accordingly — downstream agents no longer need to re-read every upstream output.

The workflow name, outputs, and observable behavior stay identical. All current callers work unchanged.

## Problem / Motivation

The current `shelf-full-sync` (v3) costs **64.5k tokens per run** on a modest reference repo, even after v3's context-slimming pass. The biggest remaining cost is structural: four separate wheel-runner agent spawns, each paying startup + MCP-tool-registration + `context_from` injection overhead. Two of those agents (`update-dashboard-tags` and `push-progress-update`) even read and write the *same dashboard file* in separate read-modify-write cycles.

This matters on four axes:

- **Cost** — 64.5k tokens/sync is too expensive to run every session; users skip syncs or batch them, which defeats the point of shelf.
- **Latency** — four sequential agent spawns make sync slow enough to block other work.
- **Reliability** — each agent step is a failure surface; MCP flakes, context truncations, and partial writes compound across four spawns.
- **Headroom** — we want to add more sync behavior (release notes, decisions, feedback loop) later, and the token budget must leave room for it.

## Goals

- Reduce `shelf-full-sync` token cost to **≤30k tokens** on the reference benchmark repo (~55% reduction from 64.5k).
- Reduce agent step count to **≤2** (down from 4).
- Preserve behavioral parity: file output on a reference repo is identical to v3.
- Maintain headroom for large vaults (≥50 issues, ≥20 PRDs) without hitting per-agent context ceilings.

## Non-Goals

- Changing *what* gets synced — frontmatter schema, templates, tag taxonomy, and dashboard layout all stay identical.
- Refactoring other shelf workflows (`shelf-create`, `shelf-update`, `shelf-release`, `shelf-repair`, etc.).
- Touching the wheel engine itself (context injection, agent spawning, state machine) — this feature works strictly within what wheel already provides.
- Bi-directional sync, new sync targets, new note types, or new Obsidian integrations.
- Renaming or versioning the workflow — it's a drop-in replacement at `plugin-shelf/workflows/shelf-full-sync.json`.

## Target Users

- **Shelf plugin users** running `/shelf-sync` or `/report-issue-and-sync` in any session — they get a faster, cheaper sync with no interface change.
- **Plugin maintainers** — they get structural headroom to add more sync behavior without blowing the token budget.

## Core User Stories

- As a shelf user, I want to run `/shelf-sync` at the end of every session without worrying about token cost, so I actually sync every session instead of batching.
- As a shelf user running `/report-issue-and-sync` after merging a PR, I want the sync to finish quickly and reliably so my Obsidian dashboard reflects the new state before I context-switch.
- As a shelf user with a large vault (many issues + PRDs), I want `shelf-full-sync` to complete without hitting agent context limits or requiring manual restarts.

## Functional Requirements

**FR-001**: The `shelf-full-sync` workflow MUST spawn **no more than 2 agent steps**. All current agent work (`sync-issues-to-obsidian`, `sync-docs-to-obsidian`, `update-dashboard-tags`, `push-progress-update`) must be accomplished within that limit.

**FR-002**: Deterministic diff computation — "which Obsidian notes actually need to be created or updated" — MUST happen in `command` steps (Bash + `jq`), not in agent steps. Agents receive a pre-filtered work list, not the raw GitHub issues JSON + full list of existing notes.

**FR-003**: The workflow MUST preserve exact behavioral parity with v3 on a reference repo. Running v4 and v3 against the same repo state must produce an identical set of Obsidian file creates/updates (same paths, same frontmatter, same body content) — verified by snapshot diff.

**FR-004**: The workflow file path and name MUST remain `plugin-shelf/workflows/shelf-full-sync.json`. No caller code (`/shelf-sync`, `report-issue-and-sync`, any docs) may need to change.

**FR-005**: The workflow MUST produce the same terminal summary output at `.wheel/outputs/shelf-full-sync-summary.md` with the same section structure (Issues, Docs, Tags, Progress, Errors).

**FR-006**: On a reference vault with ≥50 issues and ≥20 PRDs, the workflow MUST complete successfully without any single agent step hitting its context ceiling. If consolidation risks this, the work-list pre-filtering (FR-002) must shrink per-agent payload enough to stay under the ceiling.

**FR-007**: Token cost on the benchmark reference repo MUST be ≤30k tokens per run, measured via wheel-runner telemetry.

**FR-008**: All existing workflow steps that are pure-command today (`gather-repo-state`, `read-shelf-config`, `fetch-github-issues`, `read-backlog-issues`, `read-feature-prds`, `detect-tech-stack`, `generate-sync-summary`) remain command steps. This feature only restructures the agent steps and the work-list computation between them.

## Absolute Musts

1. **Tech stack** — Bash 5.x, `jq`, wheel engine, Obsidian MCP tools. No new dependencies.
2. **Drop-in replacement** — no caller changes, workflow name unchanged.
3. **Behavioral parity** — v4 output must match v3 output on a reference repo (FR-003).
4. **Token budget** — ≤30k tokens on benchmark repo (FR-007).
5. **Large-vault safety** — no agent-context-ceiling failures on ≥50 issues + ≥20 PRDs (FR-006).

## Tech Stack

Inherited from parent (`shelf-sync-v2`) — no additions or overrides:

- Bash 5.x (workflow command steps)
- `jq` (JSON parsing and work-list computation)
- Wheel workflow engine (`plugin-wheel/`)
- Obsidian MCP tools (`mcp__obsidian-projects__*`)

## Impact on Existing Features

- **`/shelf-sync` skill** — unchanged. Calls `shelf-full-sync` by name; gets a cheaper/faster run.
- **`report-issue-and-sync` workflow (composition)** — unchanged. Still composes `shelf-full-sync` as a sub-workflow.
- **`shelf-full-sync.json` file** — rewritten in place. Git diff will show substantial structural changes but no behavioral ones.
- **Token telemetry / benchmarks** — the 64.5k baseline recorded in memory becomes historical; new baseline recorded post-feature.
- **Other shelf workflows** — untouched.

## Success Metrics

**Hard gates** (must hit before this feature ships):

1. **Token cost**: `shelf-full-sync` runs in **≤30k tokens** on the benchmark reference repo (down from 64.5k).
2. **Agent count**: workflow contains **≤2 agent steps** (down from 4).
3. **Large-vault ceiling**: sync completes successfully on a vault with **≥50 issues and ≥20 PRDs** without hitting any agent context limit.

**Nice to have** (track but not gating):

- Wall-clock runtime reduced to ≤60% of v3 baseline on the reference repo.
- File-output parity with v3 verified by automated snapshot diff (rather than manual inspection).

## Risks / Unknowns

- **Single-agent context ceiling on large vaults.** Consolidating 4 agents into 1 is the cheapest path but risks hitting context limits on big repos. Mitigation: FR-002 pre-filtering shrinks the payload; if that's not enough, fall back to 2 agents (e.g., one for issues+docs, one for tags+dashboard).
- **Snapshot parity is hard to prove automatically.** Without a test harness, "identical output" may mean manual diff inspection. Risk: subtle regressions slip through. Mitigation: build a minimal snapshot diff script as part of this feature (runs v3 and v4 against a fixture repo and diffs the Obsidian writes).
- **Benchmark repo choice.** 64.5k was measured on a specific repo; if we benchmark v4 on a different repo the comparison is meaningless. Mitigation: document which reference repo is the benchmark and pin it.
- **`update-dashboard-tags` + `push-progress-update` merge.** These both read-modify-write the dashboard file. Merging them into one read-modify-write cycle is the obvious win but must preserve all existing frontmatter fields (Human Needed, Feedback, Feedback Log, About sections) exactly.
- **Wheel engine quirks.** `context_from` injection, output file paths, and agent spawning have edge cases. The refactor shouldn't trip over any of them, but this is the kind of work where "it should just work" often doesn't.

## Assumptions

- Wheel engine behavior (agent spawning, `context_from` injection, command step execution) is stable and won't change during this work.
- The 64.5k token baseline from the 2026-04-07 measurement is representative of typical runs, not an outlier.
- Obsidian MCP tools (`mcp__obsidian-projects__*`) are available and behave identically whether invoked from one agent or many.
- A reference repo exists (or can be created) that exercises all sync paths — issues, docs, tags, progress — for benchmarking.
- Pre-filtering work lists in Bash + `jq` is tractable: we can compute "which notes need updating" deterministically from `fetch-github-issues` + `mcp__obsidian-projects__list_files` output without requiring an agent.

## Open Questions

- **How do we list existing Obsidian notes from a command step?** The MCP tools are agent-invocable; if a command step can't call them, we may need one agent just to produce the "existing notes" JSON, which the next command step consumes. Needs investigation during `/plan`.
- **What's the benchmark reference repo?** Needs to be pinned before we can measure the ≤30k gate.
- **One agent or two?** Depends on the large-vault context analysis. Plan step should decide based on a quick worst-case payload calculation.
- **Do we need a snapshot diff harness as part of this feature, or is manual verification acceptable for v1?** Manual is cheaper but risks regressions; automated is safer but expands scope.
