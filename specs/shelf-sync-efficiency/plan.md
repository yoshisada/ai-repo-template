# Implementation Plan: Shelf Full Sync — Efficiency Pass

**Branch**: `build/shelf-sync-efficiency-20260416`
**Spec**: `specs/shelf-sync-efficiency/spec.md`
**PRD**: `docs/features/2026-04-10-shelf-sync-efficiency/PRD.md`
**Date**: 2026-04-10
**Updated**: 2026-04-16 (v5 manifest-based architecture)

## Summary

Rewrite `plugin-shelf/workflows/shelf-full-sync.json` as v5. v4 consolidated four agent steps into two but had a confirmed regression (B-002/B-005) where doc updates overwrote LLM-inferred fields. v5 eliminates the vault-reading discovery agent entirely by introducing a local `.shelf-sync.json` manifest for hash-based diffing, and adds CREATE vs UPDATE semantics to obsidian-apply so inferred fields are generated on first sync and never touched on subsequent updates. Target: 1 agent step, manifest-based diff, no vault reads for diffing, drop-in replacement.

## Technical Context

**Language / runtime**: Bash 5.x (workflow command steps), JSON (workflow definition), Markdown (skill/agent instructions).
**Dependencies**: `jq`, existing wheel workflow engine (`plugin-wheel/`), Obsidian MCP tools (`mcp__obsidian-projects__*`), `gh` CLI (already used by v3), `git` (already used by v3). No new runtime dependencies.
**Platform**: macOS/Linux, Claude Code harness with MCP tools bound.
**Primary target**: `plugin-shelf/workflows/shelf-full-sync.json` — rewritten in place.
**Performance targets**:
- Token cost: ≤30k per run on the pinned benchmark repo (SC-001)
- Agent count: ≤1 agent step (SC-002, tightened from ≤2 in v4)
- Parity: inferred fields preserved on UPDATE, full generation on CREATE (SC-003, redefined for v5)
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

### v4 layout (shipped, regression confirmed)

Two agents: `obsidian-discover` + `obsidian-apply`. The discovery agent reads the vault and emits an index. `compute-work-list` diffs repo state vs index. Regression: bash cannot infer LLM-derived fields (summary, status, tags) for doc updates, so it hardcoded defaults that would overwrite existing vault content.

### v5 layout (target — manifest-based)

Target: 1 agent step. The discovery agent is eliminated entirely. Instead, a local `.shelf-sync.json` manifest records what has been synced and its source hash. Diffing is hash-based: no vault reads needed.

```
gather-repo-state             (command)  [unchanged]
read-shelf-config             (command)  [unchanged]
fetch-github-issues           (command)  [unchanged]
read-backlog-issues           (command)  [unchanged]
read-feature-prds             (command)  [unchanged]
detect-tech-stack             (command)  [unchanged]
read-sync-manifest            (command)  [NEW] — read .shelf-sync.json → .wheel/outputs/sync-manifest.json
compute-work-list             (command)  [MODIFIED] — hash diff vs manifest → work list JSON with source_data
obsidian-apply                (AGENT)    [MODIFIED] — CREATE (create_file + LLM inference) vs UPDATE (patch_file programmatic only)
update-sync-manifest          (command)  [NEW] — update .shelf-sync.json with new hashes from apply results
generate-sync-summary         (command, terminal)  [unchanged shape, reads new inputs]
```

Why one agent works now: v4 needed a discovery agent because commands can't call MCP tools to read the vault. v5 eliminates the need to read the vault for diffing — the manifest provides the same information (what's been synced, what hash it had). The single remaining agent (`obsidian-apply`) only needs MCP tools for writes. On CREATE, it receives `source_data` in the work list and generates inferred fields via LLM. On UPDATE, it calls `patch_file` with only programmatic fields — no vault read needed, no inferred fields touched.

Why this fixes B-002/B-005: The root cause was v4 trying to regenerate inferred fields on every sync. v5 never touches inferred fields after creation. `patch_file` on UPDATE writes only `last_synced` + programmatic identifiers. The vault's existing `summary`, `status` (for docs), `tags`, `category` are preserved as-is.

### Dashboard read-modify-write consolidation

v3 has two agents that each read-modify-write `{base_path}/{slug}/{slug}.md`: `update-dashboard-tags` and `push-progress-update`. In v5, `compute-work-list` computes the tag delta (from `detect-tech-stack` output) and the progress entry (from `gather-repo-state` output) deterministically. `obsidian-apply` then does a single read-modify-write on the dashboard: merging the new tag set AND appending the progress entry AND updating `status`/`next_step`/`last_updated` frontmatter — all in one MCP `update_file` call, preserving `Human Needed`, `Feedback`, `Feedback Log`, and `About` sections exactly.

### `context_from` scoping (FR-013)

| step | context_from | why |
|---|---|---|
| read-sync-manifest | (none) | reads .shelf-sync.json directly |
| compute-work-list | read-shelf-config, fetch-github-issues, read-backlog-issues, read-feature-prds, detect-tech-stack, gather-repo-state, read-sync-manifest | command step — context_from here is just file reads, no token cost |
| obsidian-apply | read-shelf-config, compute-work-list | only the pre-filtered work list + base_path/slug |
| update-sync-manifest | compute-work-list, obsidian-apply | needs work list (for hashes) + apply results (for success/fail) |
| generate-sync-summary | compute-work-list, obsidian-apply | for counts and error listing |

The single agent step (`obsidian-apply`) deliberately avoids pulling the raw GitHub issues JSON, the raw PRD list, or the sync manifest into context.

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

### Phase 5 — v5 manifest-based rewrite (fixes B-002/B-005)

Update `contracts/interfaces.md` to v5. Create `read-sync-manifest.sh` and `update-sync-manifest.sh` command scripts. Modify `compute-work-list.sh` to diff against manifest hashes instead of `obsidian-index.json`. Rewrite `shelf-full-sync.json` workflow to remove `obsidian-discover`, add `read-sync-manifest` + `update-sync-manifest` steps, update `obsidian-apply` agent instructions with CREATE vs UPDATE semantics. Validate JSON, smoke test, update blockers. See tasks T026-T034.

## Open questions resolved

- **"How do we list existing Obsidian notes from a command step?"** — v4 used a discovery agent. v5 eliminates the need: a local `.shelf-sync.json` manifest tracks what has been synced. No vault reads for diffing.
- **"One agent or two?"** — v5: one. The manifest eliminates the discovery agent. Only the apply agent remains, using MCP write tools.
- **"How do we avoid regressing inferred fields on update?"** — v5 splits fields into programmatic (patched on every update) and inferred (set on create, never modified). `patch_file` targets only programmatic fields. This is the fix for B-002/B-005.
- **"What happens on cold start?"** — empty manifest means all items are CREATE. Full inferred fields generated. `update-sync-manifest` creates the manifest with all hashes. Subsequent runs are fast (mostly skips).
- **"What's the benchmark reference repo?"** — `yoshisada/ai-repo-template` @ branch `main` at the tip commit recorded in Phase 1, with the `ai-repo-template` Obsidian project as the target vault project. Pinned in `specs/shelf-sync-efficiency/baseline/benchmark-repo.md`.
- **"Do we need a snapshot-diff harness?"** — yes, built in Phase 2.

## Risks & mitigations

- **Cold start cost** — first run creates everything with full LLM inference, which is expensive. Mitigation: this is a one-time cost; subsequent runs are mostly SKIPs with occasional patches. Users who already have v3 vaults will see a large CREATE run on first v5 sync.
- **Manifest corruption** — if `.shelf-sync.json` is corrupted or deleted, all items become CREATE again. Mitigation: atomic write (temp file + mv). If manifest is deleted, it's equivalent to a cold start — safe but expensive.
- **Dashboard frontmatter preservation regression** — the consolidated read-modify-write is the subtle part. Mitigation: apply agent instructions explicitly enumerate fields to preserve; parity snapshot catches regressions.
- **Snapshot non-determinism** — MCP writes might change timestamps in frontmatter (`last_synced`). Mitigation: snapshot-capture normalizes `last_synced` to `<timestamp>` before hashing.
- **`context_from` raw-output leakage** — easy to accidentally feed the agent a raw upstream JSON. Mitigation: contract specifies exactly which files the agent sees; audit catches violations.
- **`source_data` bloat on CREATE for large repos** — if many items are CREATE (cold start or large batch), the work list could be large. Mitigation: `source_data` is only included for CREATE/UPDATE items, not SKIPs. On steady state, most items are SKIP.

## Follow-ups (out of scope)

- Fixing `require-feature-branch.sh` to accept `build/*` branches (tracked separately in `.kiln/issues/2026-04-10-require-feature-branch-hook-blocks-build-prd.md`).
- Applying the same efficiency pattern to other shelf workflows (`shelf-create`, `shelf-update`, `shelf-release`, `shelf-repair`).
- Adding release notes / decision notes / feedback loop to the sync (mentioned in PRD as future headroom).
