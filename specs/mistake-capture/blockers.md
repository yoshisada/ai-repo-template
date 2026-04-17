---
description: "PRD audit blockers for the Mistake Capture feature. Documents any unfixable gaps uncovered during /kiln:audit + smoke test."
---

# Mistake Capture — Audit Blockers

**Audit date**: 2026-04-16
**Auditor**: auditor agent (Task #4, team build-prd mistake-capture)
**Feature branch**: `build/mistake-capture-20260416`
**Head commits audited**: `8bda712` (impl-kiln), `026ef7c` (impl-shelf)

## Compliance Summary

| Axis | Coverage | Notes |
|---|---|---|
| PRD → Spec (FR mapping) | 16 / 16 (100%) | Every PRD FR-1..FR-16 has a matching spec FR-001..FR-016. |
| Spec → Code (FR → artifact) | 16 / 16 (100%) | All code artifacts present on branch; see FR-by-FR table below. |
| Spec → Test (acceptance scenarios) | 16 / 16 validated via `quickstart.md` + surrogate smoke | Plan explicitly declines an automated unit-test harness for plugin assets; per `CLAUDE.md` "There is no test suite for the plugin itself". Validation is end-to-end via `quickstart.md` + Phase 5 smoke. |
| Portability (Absolute Must #6) | CLEAN | `grep -E 'plugin-(kiln\|shelf)/scripts/' plugin-*/workflows/*.json` returns no matches on the branch. |
| Branch hygiene | CLEAN | Feature branch contains three commits: `4eb1919` (spec), `8bda712` (impl-kiln), `026ef7c` (impl-shelf). |

### FR-by-FR verification

| FR | Spec location | Code artifact | Smoke evidence |
|---|---|---|---|
| FR-001 | spec.md §FR-001 | `plugin-kiln/skills/mistake/SKILL.md` (frontmatter `name: mistake`) | Direct-file inspection. |
| FR-002 | spec.md §FR-002 | `plugin-kiln/skills/mistake/SKILL.md` Steps 1–3 + Rules block | Skill delegates to `/wheel-run kiln:report-mistake-and-sync`; no structured prompting in skill. |
| FR-003 | spec.md §FR-003 | `plugin-kiln/skills/mistake/SKILL.md` §Step 2 "LLM Guardrails" | All four guardrail topics quoted (honesty, severity, "not about the human", slug-names-trap). |
| FR-004 | spec.md §FR-004 | `plugin-kiln/workflows/report-mistake-and-sync.json` | `jq` validates: `name: report-mistake-and-sync`, `version: 1.0.0`, 3 steps with exact ids/types, `terminal: true` on `full-sync`. |
| FR-005 | spec.md §FR-005 | `plugin-kiln/scripts/check-existing-mistakes.sh` + workflow step 1 | Direct-run smoke: produces `## Existing Local Mistakes` + `## Recent Session Mistakes` H2 blocks. Workflow step uses `bash "${WORKFLOW_PLUGIN_DIR}/scripts/check-existing-mistakes.sh"` (portable). |
| FR-006 | spec.md §FR-006 | Workflow step 2 `create-mistake.instruction` | 9 numbered sub-steps present. All 7 frontmatter fields + 5 body sections explicitly enumerated. |
| FR-007 | spec.md §FR-007 | Workflow step 2 §Step 5 (honesty lint) | All 8 hedge markers enumerated. `I ` prefix rule for assumption; `I `/`The `/`It ` prefix rule for correction. No bypass flag. |
| FR-008 | spec.md §FR-008 | Workflow step 2 §Step 6 (three-axis lint) | All 7 `mistake/*` tags enumerated; `topic/*` required; all 6 stack-tag families listed. |
| FR-009 | spec.md §FR-009 | Workflow step 2 §Step 7 (slug algorithm) | 7-step algorithm spelled out; ≤50-char word-boundary truncation; slug names the trap, not the action. |
| FR-010 | spec.md §FR-010 | Workflow step 3 `full-sync` | `type: workflow`, `workflow: shelf:shelf-full-sync`, `terminal: true`. |
| FR-011 | spec.md §FR-011 | `plugin-shelf/scripts/compute-work-list.sh:268–490` | Live smoke: fixture `.kiln/mistakes/2026-04-16-assumed-audit-fixture-cleanup-autonomous.md` was discovered, emitted `action: create`, `counts.mistakes.create: 1`, all 9 `source_data` fields populated. Fixture removed — re-run emits empty `mistakes: []` cleanly. |
| FR-012 | spec.md §FR-012 | `plugin-shelf/workflows/shelf-full-sync.json` `obsidian-apply` instruction (new loop step 5) | MCP scope `mcp__claude_ai_obsidian-manifest__*` per contract-edits.md Edit 1 (research.md R2 anticipated this). Proposal frontmatter shape matches contracts §5.1 (`type: manifest-proposal`, `kind: content-change`, `target: @second-brain/projects/<slug>/mistakes/...`, body calls out "mistake draft"). |
| FR-013 | spec.md §FR-013 | `compute-work-list.sh` sha256-based hash diff | Hash computed via existing `shasum -a 256` pattern; stored as `sha256:<hex>`; compared to manifest-stored prior hash to emit `create`/`update`/`skip`. |
| FR-014 | spec.md §FR-014 | `compute-work-list.sh` filed-state short-circuit + `update-sync-manifest.sh` reconciliation | `proposal_state == "filed"` always emits `skip`, even on hash change. Reconciliation (open→filed transition) runs in `obsidian-apply` agent step (contract-edits Edit 2, contracts §5.3) because the agent step has `list_files` MCP access. `filed → open` is unreachable by reduce-predicate design. |
| FR-015 | spec.md §FR-015 | `plugin-kiln/.claude-plugin/plugin.json` `workflows` array | Lists both `workflows/report-issue-and-sync.json` AND `workflows/report-mistake-and-sync.json`. Skills are auto-discovered (no `skills:` list) per T013 note. |
| FR-016 | spec.md §FR-016 | Portability grep | `grep -E 'plugin-(kiln\|shelf)/scripts/' plugin-kiln/workflows/*.json plugin-shelf/workflows/*.json` → no matches. |

## Blockers

### Blocker 1 — Phase 5 end-to-end smoke tests T036/T037/T038 are NOT fully executed on this branch

**Tasks affected**: T036 (quickstart walk-through), T037 (consumer-only install portability smoke), T038 (`.wheel/history/success/` hygiene check after 3 runs).

**Why blocked**: The wheel workflow discovery function (`plugin-wheel/lib/workflow.sh` `workflow_discover_plugin_workflows`) reads from `~/.claude/plugins/cache/yoshisada-speckit/<plugin>/<version>/workflows/`. The new `report-mistake-and-sync.json` exists in the source repo at `plugin-kiln/workflows/`, but the plugin cache does NOT yet contain it — the latest cached version `000.000.000.1143` still only ships `report-issue-and-sync.json`. To truly exercise `/wheel-run kiln:report-mistake-and-sync` end-to-end, the kiln plugin must first be re-published to the marketplace and re-installed to the cache.

**Why not a P1 rejection**: All static contract checks pass:

- JSON parses cleanly (`jq '.' plugin-kiln/workflows/report-mistake-and-sync.json`).
- Portability grep clean on branch (Absolute Must #6).
- The workflow registration in `plugin-kiln/.claude-plugin/plugin.json` lists the new file.
- All 9 agent sub-steps, all lints, all field enumerations are textually present in the workflow JSON.
- Command step 1 (`check-existing-mistakes.sh`) executes cleanly from direct invocation and produces the required two-H2-block output — the `${WORKFLOW_PLUGIN_DIR}` portability variable is the only indirection, and wheel exports it per `plugin-wheel/lib/dispatch.sh` post-`005e259`.

**Surrogate smoke performed by auditor**: The shelf-side half of the pipeline was exercised with a real fixture:

1. Seeded `.kiln/mistakes/2026-04-16-assumed-audit-fixture-cleanup-autonomous.md` (7-field frontmatter + 5 body sections + 3-axis tags + honesty-clean assumption/correction).
2. Ran `bash plugin-shelf/scripts/compute-work-list.sh` → emitted `counts.mistakes.create: 1`, `mistakes[0].action: "create"`, all `source_data` fields populated with correct values, and `proposal_path: @inbox/open/2026-04-16-mistake-assumed-audit-fixture-cleanup-autonomous.md`.
3. Deleted the fixture; re-ran compute-work-list.sh → emitted empty `mistakes: []`, `counts.mistakes: {create:0, update:0, skip:0}` cleanly (no errors on empty `.kiln/mistakes/`).

**Resolution path**: T036/T037/T038 are run after merge + `npm publish` + marketplace re-install. A follow-up issue should be filed against the build to perform the full end-to-end smoke from a consumer checkout once the new plugin version is cached.

**Status**: DEFERRED — not a merge-blocker, but must be run in the first post-merge session before announcing the feature as live.

## Non-blocker observations

- **Contract edit 1 (MCP scope switch)**: `plugin-shelf/workflows/shelf-full-sync.json` routes `@inbox/open/` writes via `mcp__claude_ai_obsidian-manifest__*` rather than `mcp__obsidian-projects__*` because projects-MCP is read-only outside `@second-brain/projects/`. Research R2 anticipated this. Contract was updated in `contracts/interfaces.md` FIRST (per constitution VII), edit documented in `agent-notes/contract-edits.md`.
- **Contract edit 2 (reconciliation ownership moved command → agent)**: The `open → filed` reconciliation requires `list_files` MCP access, which is only available inside an agent step. It was therefore moved from `update-sync-manifest.sh` (a command step, no MCP) into the `obsidian-apply` agent step. `update-sync-manifest.sh` consumes the agent's emitted `results.mistakes.reconciliation[]` array and applies the transitions to the manifest row. Documented in `agent-notes/contract-edits.md`.
- **Contract edit 3 (mistakes_prior_state projection)**: `compute-work-list.sh` emits a `mistakes_prior_state[]` projection at the top level so the `obsidian-apply` agent receives prior-manifest state via `context_from`. Contracts §4 updated.

All three contract edits were applied pre-implementation and every touched implementation matches the updated contract.
