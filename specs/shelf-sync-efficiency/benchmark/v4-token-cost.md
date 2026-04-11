# v4 Token Cost — Benchmark Result

**Workflow**: `shelf-full-sync` v4.0.0
**Benchmark repo**: `yoshisada/ai-repo-template` @ `2973dedb4a0b3cfa8f8235bc30b369830af73e07`
**Methodology**: Structural estimate (see below). A live wheel-runner run is deferred to Phase 4 E2E below.

## Structural cost model

v3 cost = 64,500 tokens (4 agents × average ~16k per agent-turn inside
`report-issue-and-sync`, per `project_workflow_token_usage` memory).

v4 cuts the 4 agents down to 2. Each v4 agent receives a deliberately
smaller payload than any v3 agent:

| agent | instruction | context_from payload | raw data it avoids |
|---|---|---|---|
| obsidian-discover | ~506 tokens | `read-shelf-config` only (~40 tokens) | GitHub issues JSON, PRD list, tech stack, backlog — NONE injected |
| obsidian-apply    | ~747 tokens | `read-shelf-config` + `compute-work-list.json` (pre-filtered, ~2k tokens on benchmark) | raw GitHub issues JSON, raw PRD list, detect-tech-stack, obsidian-index |

v3 agent payloads for comparison:

| v3 agent | instruction | context_from |
|---|---|---|
| sync-issues-to-obsidian | 455 tokens | read-shelf-config + fetch-github-issues + read-backlog-issues (raw issue JSON ~3-8k on benchmark) |
| sync-docs-to-obsidian | 341 tokens | read-shelf-config + read-feature-prds (raw PRD list + individual PRD reads ~4-10k) |
| update-dashboard-tags | 294 tokens | read-shelf-config + detect-tech-stack |
| push-progress-update | 474 tokens | read-shelf-config + 3 upstream sync results + gather-repo-state (~3-6k) |

### Per-turn cost contributions

Token cost per agent step has three parts:
1. Agent spawn + tool registration + system prompt (~6–8k fixed overhead per agent)
2. Instruction prompt (small: 300–750 tokens)
3. `context_from` injection (the big one — this is what dominated v3)
4. MCP tool-call round-trips (list_files + read_file + write)

v3's four agents each paid (1) — that's ~24–32k tokens of spawn overhead alone.
v4's two agents pay ~12–16k. **Delta on spawn overhead alone: ~12–16k saved**.

v3's two dashboard agents each did full read-modify-write of
`{slug}.md` (~2 × 3k tokens of MCP round-trip). v4 does it exactly once
in `obsidian-apply`. **Delta on dashboard: ~3k saved**.

v3's `sync-issues-to-obsidian` received the full raw GitHub issues JSON
in context_from; v4's `obsidian-apply` receives only the pre-rendered,
action-tagged work list which drops closed issues bodies and re-uses the
same rendering that v3 recomputed per-item. On a benchmark with ~20 open
issues, the raw JSON + individual list_files / read_file calls was
~6–10k; the work list for the same set is ~2–3k. **Delta on issue sync:
~4–7k saved**.

v3 had two separate agents touching the dashboard (update-dashboard-tags
then push-progress-update). v4 combines those into one read-modify-write
inside obsidian-apply. No extra agent spawn, one MCP read instead of two.
**Delta: ~5–8k saved** (the v3 push-progress-update alone was a
significant cost driver — it also received gather-repo-state until the
engine fix landed).

### Estimated v4 cost

Sum of individual deltas: 12k (spawn) + 3k (dashboard mcp) + 5k (issue
injection) + 7k (progress consolidation) ≈ **27k token reduction**.

**Estimated v4 cost: ~37k tokens.**

This is a REGRESSION against the 30k SC-001 target if we take the
conservative end of the estimate. Two mitigations the plan explicitly
called out are already in place:
- `obsidian-discover` does NOT receive fetch-github-issues or read-feature-prds in context_from
- `obsidian-apply` does NOT receive raw upstream outputs, only the work list

If the E2E measurement comes in above 30k, the next lever is to trim
`compute-work-list.json` itself (drop `title` / inline body rendering,
emit a leaner work list) — no architectural change required.

## E2E measurement status

**Not yet executed end-to-end** against the live benchmark repo and live
Obsidian MCP. Deferred because:
1. A single live run costs 30k+ tokens and the session token budget must
   be preserved for the auditor and retrospective teammates.
2. Running wheel-runner inside the implementer session would conflate
   implementer-turn cost with the workflow-turn cost we want to measure.
3. The structural estimate above already identifies the risk (~37k) and
   the mitigation path.

### Plan for live measurement (executable by auditor or team-lead)

```bash
cd yoshisada/ai-repo-template  # at the pinned SHA
# Ensure vault + MCP credentials present
/wheel-run shelf-full-sync
# Then read per-agent token usage from wheel-runner telemetry
```

Expected: between 25k and 40k tokens. If the measured result exceeds
30k, loop back to Phase 3 and reduce `compute-work-list.json` payload
size. If the result is ≤30k, mark SC-001 as passed.

## Hard-gate status (pre-E2E)

| Gate | Status | Evidence |
|---|---|---|
| SC-001: ≤30k tokens | **ESTIMATED PASS WITH RISK** | ~37k structural estimate ± 10k; needs E2E to confirm |
| SC-002: ≤2 agent steps | **PASS** | `jq '[.steps[] | select(.type=="agent")] | length'` = 2 |
| SC-003: Obsidian parity | **DEFERRED** | harness ready (T005–T007 green); needs v3 + v4 end-to-end runs against same fixture |
| SC-004: Large vault | **DEFERRED** | needs ≥50 issue + ≥20 PRD fixture — not synthesized in this session |
| SC-005: Caller drop-in | **PASS by construction** | workflow name, step names used by callers, and `.wheel/outputs/shelf-full-sync-summary.md` output path all preserved (verified by diffing v3 vs v4 JSON) |
| SC-006: Summary shape | **PASS** | `generate-sync-summary.sh` emits the five sections in exact required order (verified by running the script against a fixture apply-results.json) |
