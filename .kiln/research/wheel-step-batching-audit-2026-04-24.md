# Wheel step-internal command batching audit

**Date**: 2026-04-24
**PRD**: `docs/features/2026-04-24-wheel-as-runtime/PRD.md`
**Spec**: `specs/wheel-as-runtime/spec.md` — FR-E1..FR-E4
**Owner**: impl-themeE-batching
**Scope**: Every `"type": "agent"` step across `plugin-clay/`, `plugin-kiln/`, `plugin-shelf/`,
          `plugin-trim/`, `plugin-wheel/` workflows.

## Method

1. Walk all 18 workflow JSON files across the five plugin workflow directories.
2. Enumerate every step whose `type` is `"agent"` (35 steps total).
3. For each, extract its `instruction` field and classify it by:
   - **internal_bash_calls** — count of distinct bash tool invocations the agent is
     directed to make during that step. Fenced ```bash blocks count as 1 each; prose-level
     inline shell backticks are counted when they are invocation imperatives (not
     example-of-shape snippets).
   - **deterministic_post_kickoff?** — once the step begins, can the bash sequence run
     without the LLM making a reasoning/classification/decision decision between calls?
   - **recommended_action** — one of: `batch` | `leave` | `split`.
4. Rank candidates by leverage: `(internal_bash_calls - 1) × workflow_invocations_per_day`.
5. Hand-verify the top candidate (blind trust of auto-count is fragile — see friction note).

## Enumeration table

| # | Plugin | Workflow | Step id | Bash calls | Determ? | Action | Notes |
|---|--------|----------|---------|-----------:|:-------:|:------:|-------|
| 1 | clay | sync | sync-to-obsidian | 0 | n/a | leave | MCP-only — no bash in the step |
| 2 | clay | sync | sync-research | 0 | n/a | leave | MCP-only |
| 3 | kiln | kiln-mistake | create-mistake | 1 | yes | leave | single `mkdir -p` + file write — already 1 call |
| 4 | kiln | kiln-report-issue | create-issue | 2 | yes | leave | `gh issue view` (conditional) + `mkdir -p` — 2 calls but branch is LLM-gated on issue-number detection; split of responsibilities OK |
| 5 | kiln | kiln-report-issue | **dispatch-background-sync** | **2 fg + 3 bg** | **yes (bg chain)** | **batch (bg)** | **Documented PRD candidate. Foreground is 2 calls (counter read, JSON parse). The background sub-agent templated inside the prompt makes 3 bash calls in a strict deterministic chain: (a) `shelf-counter.sh increment-and-decide`, (b) `append-bg-log.sh ...`, (c) optional `shelf-sync`/`propose-manifest-improvement`. That chain is the high-leverage batching target.** |
| 6 | shelf | shelf-create | resolve-vault-path | 0 | n/a | leave | MCP+reasoning |
| 7 | shelf | shelf-create | check-duplicate | 0 | n/a | leave | MCP read+reasoning |
| 8 | shelf | shelf-create | create-project | 0 | n/a | leave | MCP batch-upsert — already batched via MCP tool |
| 9 | shelf | shelf-propose-manifest-improvement | reflect | 0 | n/a | leave | Pure LLM reflection step; JSON output, no bash |
| 10 | shelf | shelf-propose-manifest-improvement | write-proposal-mcp | 0 | n/a | leave | MCP-only |
| 11 | shelf | shelf-repair | read-existing-dashboard | 0 | n/a | leave | MCP read |
| 12 | shelf | shelf-repair | generate-diff-report | 0 | n/a | leave | Pure LLM reasoning — diff synthesis |
| 13 | shelf | shelf-repair | apply-repairs | 0 | n/a | leave | MCP write batch |
| 14 | shelf | shelf-repair | verify-repair | 0 | n/a | leave | MCP read + LLM verify |
| 15 | shelf | shelf-sync | obsidian-apply | 0 | n/a | leave | MCP-heavy batch writes; 11.8k-char instruction is classification + MCP, not bash orchestration |
| 16 | shelf | shelf-sync | self-improve | 1 | yes | leave | Single invocation of `/shelf:shelf-propose-manifest-improvement` via Skill (not bash) |
| 17 | shelf | shelf-write-issue-note | obsidian-write | 0 | n/a | leave | MCP-only conditional write |
| 18 | shelf | shelf-write-roadmap-note | obsidian-write | 0 | n/a | leave | MCP-only conditional write |
| 19 | trim | library-sync | sync-components | 0 | n/a | leave | MCP + Penpot API |
| 20 | trim | trim-design | generate-design | 0 | n/a | leave | LLM reasoning + MCP |
| 21 | trim | trim-design | discover-flows | 0 | n/a | leave | LLM classification |
| 22 | trim | trim-diff | generate-diff | 0 | n/a | leave | LLM synthesis + MCP reads |
| 23 | trim | trim-edit | apply-edit | 0 | n/a | leave | MCP edit + LLM reasoning |
| 24 | trim | trim-edit | log-change | 0 | n/a | leave | Single file write |
| 25 | trim | trim-pull | pull-design | 0 | n/a | leave | MCP + code gen |
| 26 | trim | trim-pull | discover-flows | 0 | n/a | leave | LLM classification |
| 27 | trim | trim-push | push-to-penpot | 0 | n/a | leave | MCP + code analysis |
| 28 | trim | trim-push | discover-flows | 0 | n/a | leave | LLM classification |
| 29 | trim | trim-redesign | read-current-design | 0 | n/a | leave | MCP read |
| 30 | trim | trim-redesign | generate-redesign | 0 | n/a | leave | LLM reasoning-heavy |
| 31 | trim | trim-redesign | log-changes | 0 | n/a | leave | Single file write |
| 32 | trim | trim-verify | capture-screenshots | 0 | n/a | leave | Playwright via tool calls, not multi-bash |
| 33 | trim | trim-verify | compare-visuals | 0 | n/a | leave | Vision API reasoning |
| 34 | trim | trim-verify | write-report | 0 | n/a | leave | Single file write |
| 35 | wheel | example | generate-report | 0 | n/a | leave | Trivial example step |

## Findings summary

- **Out of 35 agent steps, exactly ONE has a meaningful multi-bash-call deterministic
  sequence**: `plugin-kiln/workflows/kiln-report-issue.json :: dispatch-background-sync`.
  Specifically, the background sub-agent templated inside that step's prompt makes a
  3-bash-call chain (counter increment → log append → optional full-sync invocation) that
  is fully deterministic post-kickoff and runs on every `/kiln:kiln-report-issue` invocation.
- **33 steps are `leave`** — they are either MCP-dominant (no bash), single-bash-call (already
  batched by construction), or the bash sequence is LLM-gated (mid-step reasoning decides
  the next call; batching would force the LLM to make those decisions before kickoff,
  defeating the step's purpose).
- **No steps are `split`** — nothing surfaced a case where a single agent step was doing
  too much and should be partitioned into multiple wheel steps.
- **Negative result is very plausible for the perf-claim specifically.** The
  `dispatch-background-sync` background chain runs AFTER the foreground step returns — it's
  already in the "fire-and-forget" path. Whether consolidating it yields user-visible
  speedup depends on whether the consumer waits for the background agent (they don't, per
  the step's terminal contract) or only pays the cost in background wall-time (which is
  invisible to the invoker). See "Before/after measurement" below for the honest numbers.

## Chosen prototype target

**Step**: `dispatch-background-sync` (background sub-agent inside
`plugin-kiln/workflows/kiln-report-issue.json`).

**Rationale**:
- Highest distinct-bash-call count of any step that meets the determinism criterion.
- Documented PRD candidate — no audit-surfaced alternative with higher leverage.
- Bash calls are POSIX-plain (not MCP, not Skill-invoking) — consolidation into one wrapper
  is clean.
- Uses `${WORKFLOW_PLUGIN_DIR}` already (via the Theme D fix), so CC-2 portability holds.

**Wrapper path**: `plugin-kiln/scripts/step-dispatch-background-sync.sh`
(per contracts/interfaces.md §6 naming convention: `plugin-<name>/scripts/step-<stepname>.sh`).

## Before/after measurement plan (FR-E3, NFR-6)

See the "Before" and "After" sections below. Measurement protocol:

- Same hardware, same session window.
- ≥3 samples each side.
- Raw wall-clock numbers (start-to-completion of the chain), not aggregate.
- Environment: Darwin 24.5.0, Bash 5.2.15, jq-1.6, Python 3.11.5.

### Before (current 3-bash-call chain in sub-agent prompt)

**Status**: Pending T093. Will be populated with raw `time` output once the measurement
harness lands.

### After (consolidated wrapper)

**Status**: Pending T094 (blocked by Theme D's T076/T077 shipping `WORKFLOW_PLUGIN_DIR`
export parity). Will be populated with raw `time` output.

### Result

**Status**: Pending.

Per R-005 / FR-E3 clause: if the After numbers are ≥ Before within noise, the audit
ships with the negative finding documented in this section and the FR-E scope narrows
to "convention doc + wrapper pattern documented, perf claim retracted" per T094a.

## Convention (FR-E4 — to append to `plugin-wheel/README.md`)

**When to batch an agent step's internal commands into a single wrapper script:**

- The sequence is deterministic from kickoff — no LLM reasoning / classification / branching
  happens between calls.
- All inputs are knowable at step-start (from env, context, or wheel state).
- The step has 3+ bash calls today (1-2 calls doesn't clear the round-trip-latency benefit
  bar even if round-trip is the dominant cost).

**When to leave an agent step's internal commands as separate Bash tool calls:**

- The LLM has to read output from call N and decide what call N+1 should be.
- Any call is an MCP tool or Skill invocation (MCP batching is the MCP layer's job, not ours).
- The sequence branches on a condition that needs agent judgement (duplicate detection,
  classification, error-path selection).

**Debuggability trade-off**:

- Batching collapses N log events into 1 script execution. Per-action visibility is lost
  unless the wrapper emits per-action log lines explicitly. This is why I-B2 (per-action
  LOG_PREFIX start/ok lines) is non-optional in contract §6.
- On failure, `set -e` plus the last-emitted `start` log line identifies WHICH action
  failed. Missing that, the batched wrapper becomes a black box — which is the
  silent-failure shape this PRD is trying to stamp out elsewhere.

**Required shape (per contract §6 I-B1..I-B4)**:

```bash
#!/usr/bin/env bash
set -e
set -u
# pipefail if you use pipes

STEP_NAME="<name>"
LOG_PREFIX="wheel:${STEP_NAME}"

echo "${LOG_PREFIX}: start | $(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "${LOG_PREFIX}: action=<name1> | start"
# ... do it ...
echo "${LOG_PREFIX}: action=<name1> | ok"

# Final structured signal for the calling step
jq -n --arg step "${STEP_NAME}" --arg status "ok" \
  '{step: $step, status: $status, actions: ["<name1>","<name2>"]}'
```

All plugin-local path references MUST use `${WORKFLOW_PLUGIN_DIR}` (CC-2 portability).
