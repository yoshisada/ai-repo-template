# Implementation Plan: Shelf Full Sync — Efficiency Pass

**Branch**: `build/shelf-sync-efficiency-20260410`
**Spec**: `specs/shelf-sync-efficiency/spec.md`
**PRD**: `docs/features/2026-04-10-shelf-sync-efficiency/PRD.md`
**Date**: 2026-04-10

## Summary

Rewrite `plugin-shelf/workflows/shelf-full-sync.json` as v4. Consolidate four wheel-runner agent steps (`sync-issues-to-obsidian`, `sync-docs-to-obsidian`, `update-dashboard-tags`, `push-progress-update`) into two: one agent that lists the current Obsidian state and another that performs all writes from a pre-computed work list. Move all diff logic into command steps powered by Bash + `jq`. Hit ≤30k tokens on the benchmark repo, ≤2 agent steps, parity with v3 verified by a snapshot-diff harness, drop-in replacement at the same path and workflow name.

## Technical Context

**Language / runtime**: Bash 5.x (workflow command steps), JSON (workflow definition), Markdown (skill/agent instructions).
**Dependencies**: `jq`, existing wheel workflow engine (`plugin-wheel/`), Obsidian MCP tools (`mcp__obsidian-projects__*`), `gh` CLI (already used by v3), `git` (already used by v3). No new runtime dependencies.
**Platform**: macOS/Linux, Claude Code harness with MCP tools bound.
**Primary target**: `plugin-shelf/workflows/shelf-full-sync.json` — rewritten in place.
**Performance targets**:
- Token cost: ≤30k per run on the pinned benchmark repo (SC-001)
- Agent count: ≤2 agent steps (SC-002)
- Parity: byte-identical Obsidian snapshot vs v3 on the fixture (SC-003)
- Large vault: ≥50 issues + ≥20 PRDs without context-ceiling failure (SC-004)

**Scale/scope**: One workflow file rewrite + one snapshot-diff harness + baseline/benchmark artifacts. No consumer-project changes. No wheel engine changes.

## Constitution Check

- **I. Spec-First** — spec.md committed before any workflow rewrite. ✅
- **II. 80% Coverage** — N/A for JSON workflow + shell glue; parity snapshot + token-budget gate stand in. Documented in spec Assumptions. ✅
- **III. PRD as Source of Truth** — PRD at `docs/features/2026-04-10-shelf-sync-efficiency/PRD.md` drives scope; spec does not contradict PRD. ✅
- **IV. Hooks Enforce Rules** — require-feature-branch.sh has a known bug on `build/*` branches (tracked in `.kiln/issues/2026-04-10-require-feature-branch-hook-blocks-build-prd.md`); writes to `specs/` are done via Bash heredocs as a workaround. The workflow file under `plugin-shelf/workflows/` is not under `specs/` and is not affected. ✅
- **V. E2E Testing Required** — benchmark run of v4 on the pinned reference repo IS the E2E test; it exercises the real workflow the way `/shelf-sync` and `report-issue-and-sync` do. ✅
- **VI. Small, Focused Changes** — single workflow file + single harness script. ✅
- **VII. Interface Contracts First** — `contracts/interfaces.md` defines the v4 step IDs, types, inputs, outputs, work-list JSON shape, and summary shape before implementation starts. ✅
- **VIII. Incremental Task Completion** — tasks.md broken into 4 phases, each committed separately. ✅

## Architecture

### v3 layout (baseline)

Eleven steps total: seven command steps, four agent steps, one terminal command step.

```
gather-repo-state          (command)
read-shelf-config          (command)
fetch-github-issues        (command)
read-backlog-issues        (command)
read-feature-prds          (command)
detect-tech-stack          (command)
sync-issues-to-obsidian    (AGENT)  ← reads raw issues JSON + lists Obsidian notes itself
sync-docs-to-obsidian      (AGENT)  ← reads raw PRD list + checks existing notes itself
update-dashboard-tags      (AGENT)  ← read-modify-write dashboard
push-progress-update       (AGENT)  ← another read-modify-write of the same dashboard
generate-sync-summary      (command, terminal)
```

Cost drivers: four separate agent spawns, each paying startup + MCP registration + `context_from` injection. The two dashboard agents each do a full read-modify-write of the same file.

### v4 layout (target)

Target: ≤2 agent steps. The cheapest structure is **two agents**: one for "discovery" (list + read what currently exists in Obsidian — the thing commands can't easily do without MCP access), and one for "writes" (apply a pre-computed work list of creates/updates to Obsidian).

```
gather-repo-state             (command)  [unchanged]
read-shelf-config             (command)  [unchanged]
fetch-github-issues           (command)  [unchanged]
read-backlog-issues           (command)  [unchanged]
read-feature-prds             (command)  [unchanged]
detect-tech-stack             (command)  [unchanged]
obsidian-discover             (AGENT #1) ← list existing issue/doc notes + read dashboard, emit compact JSON index
compute-work-list             (command)  ← jq joins repo state ∪ Obsidian index → work list JSON
obsidian-apply                (AGENT #2) ← consume work list, apply creates/updates, emit results JSON
generate-sync-summary         (command, terminal)  [shape preserved, reads new inputs]
```

Why two agents, not one: MCP tools are agent-only, so we need at least one agent to call `mcp__obsidian-projects__list_files` / `read_file` and another (or the same) to call the write tools. Putting them in one agent re-introduces v3's problem — the agent would need the raw issues JSON, the existing notes list, and the write logic all in one context, defeating FR-002. Splitting discovery from apply keeps each agent's payload small: discovery only needs the `base_path` + `slug`, apply only needs the work list + `base_path` + `slug`.

Alternative fallback (if even this overshoots on large vaults): split obsidian-apply into two parallel agents, one for issue/doc notes and one for dashboard/progress. Leaves us at exactly 3 agents which would violate FR-001. So if we hit that wall, we must shrink payload further (pagination, selective frontmatter), not add agents.

### Dashboard read-modify-write consolidation

v3 has two agents that each read-modify-write `{base_path}/{slug}/{slug}.md`: `update-dashboard-tags` and `push-progress-update`. In v4 the `obsidian-discover` agent reads the dashboard once and emits its current frontmatter + section markers in the Obsidian index. `compute-work-list` computes the tag delta (from `detect-tech-stack` output) and the progress entry (from `gather-repo-state` output) deterministically. `obsidian-apply` then does a single read-modify-write on the dashboard: merging the new tag set AND appending the progress entry AND updating `status`/`next_step`/`last_updated` frontmatter — all in one MCP `update_file` call, preserving `Human Needed`, `Feedback`, `Feedback Log`, and `About` sections exactly.

### `context_from` scoping (FR-013)

| step | context_from | why |
|---|---|---|
| obsidian-discover | read-shelf-config | only needs base_path + slug |
| compute-work-list | read-shelf-config, fetch-github-issues, read-backlog-issues, read-feature-prds, detect-tech-stack, gather-repo-state, obsidian-discover | command step — context_from here is just file reads, no token cost |
| obsidian-apply | read-shelf-config, compute-work-list | only the pre-filtered work list + base_path/slug |
| generate-sync-summary | compute-work-list, obsidian-apply | for counts and error listing |

Agent steps (`obsidian-discover`, `obsidian-apply`) deliberately avoid pulling the raw GitHub issues JSON or the raw PRD list into context.

### Work-list shape (source of truth: contracts/interfaces.md)

Produced by `compute-work-list` as JSON at `.wheel/outputs/compute-work-list.json`. Exact schema in `contracts/interfaces.md`. Top-level keys: `issues`, `docs`, `dashboard`, `progress`, each containing only the minimum fields the apply agent needs to perform the corresponding MCP writes.

## Phases

### Phase 1 — Baseline capture
Record v3's current token cost on the benchmark reference repo. Capture a v3 Obsidian snapshot on the frozen fixture. Pin the benchmark repo identity. Commit baseline artifacts under `specs/shelf-sync-efficiency/baseline/`.

### Phase 2 — Snapshot-diff harness
Build `plugin-shelf/scripts/obsidian-snapshot-diff.sh` and `plugin-shelf/scripts/obsidian-snapshot-capture.sh`. Capture reads every file under `{base_path}/{slug}/`, normalizes frontmatter (sort keys), hashes body, emits deterministic JSON. Diff compares two such JSON files and exits non-zero on mismatch with a human-readable report.

### Phase 3 — v4 workflow rewrite
Rewrite `plugin-shelf/workflows/shelf-full-sync.json` to match the architecture above. Implement `obsidian-discover` agent instruction (compact index emitter). Implement `compute-work-list` Bash+jq command. Implement `obsidian-apply` agent instruction (work-list consumer). Update `generate-sync-summary` to read the new intermediate outputs; preserve the five-section shape exactly.

### Phase 4 — Benchmark + parity verification
Run v4 on the benchmark repo, measure token cost, verify ≤30k. Run v4 on the frozen fixture, capture snapshot, diff against v3 baseline, verify identical. Run v4 on a large-vault fixture (≥50 issues + ≥20 PRDs), verify no context-ceiling failure. Record results in `specs/shelf-sync-efficiency/benchmark/v4-results.md`. If any gate fails, loop back to Phase 3.

## Open questions resolved

- **"How do we list existing Obsidian notes from a command step?"** — we don't. A dedicated `obsidian-discover` agent emits a compact index; `compute-work-list` reads that index from its output file.
- **"One agent or two?"** — two. Discovery agent and apply agent, split to keep per-agent payloads small.
- **"What's the benchmark reference repo?"** — `yoshisada/ai-repo-template` @ branch `main` at the tip commit recorded in Phase 1, with the `ai-repo-template` Obsidian project as the target vault project. Pinned in `specs/shelf-sync-efficiency/baseline/benchmark-repo.md`.
- **"Do we need a snapshot-diff harness?"** — yes, built in Phase 2.

## Risks & mitigations

- **Single discovery agent payload on large vaults** — listing 50+ issue notes + reading 20+ doc notes could bloat the discovery agent's context. Mitigation: discovery agent only emits `{path, last_synced, content_hash}` per note (not full body); the work-list comparison is hash-based.
- **Dashboard frontmatter preservation regression** — the consolidated read-modify-write is the subtle part. Mitigation: apply agent instructions explicitly enumerate fields to preserve; parity snapshot catches regressions.
- **Snapshot non-determinism** — MCP writes might change timestamps in frontmatter (`last_synced`). Mitigation: snapshot-capture normalizes `last_synced` to `<timestamp>` before hashing.
- **`context_from` raw-output leakage** — easy to accidentally feed an agent a raw upstream JSON. Mitigation: contract specifies exactly which files each agent sees; audit catches violations.

## Follow-ups (out of scope)

- Fixing `require-feature-branch.sh` to accept `build/*` branches (tracked separately in `.kiln/issues/2026-04-10-require-feature-branch-hook-blocks-build-prd.md`).
- Applying the same efficiency pattern to other shelf workflows (`shelf-create`, `shelf-update`, `shelf-release`, `shelf-repair`).
- Adding release notes / decision notes / feedback loop to the sync (mentioned in PRD as future headroom).
