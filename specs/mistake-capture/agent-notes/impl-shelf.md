# impl-shelf friction note — Mistake Capture

**Agent**: impl-shelf (claude-opus-4-7)
**Date**: 2026-04-16 / 2026-04-17 UTC
**Branch**: `build/mistake-capture-20260416`
**Tasks completed**: T004, T018–T035 (Phase 4 in full), plus contract edits.

## What was clear

- **PRD + spec + plan + contracts** were cohesive and load-bearing. Reading contracts/interfaces.md end-to-end was enough to hold the whole Phase 4 scope in head. No backtracking to the PRD during implementation.
- **The "extend existing script" vs "add a sibling" split.** Contracts were explicit: extend `compute-work-list.sh` and `update-sync-manifest.sh`. I never had to decide.
- **Portability rule (NON-NEGOTIABLE)** from CLAUDE.md. Zero ambiguity — `${WORKFLOW_PLUGIN_DIR}/scripts/...` is the only legal path in workflow JSON. I ran the grep audit (T024, T029) as much for my own sanity as for the contract.
- **FR-014 "never re-propose filed entries"** was crisp, testable, and the contract spelled out exactly where the check lives (compute-work-list.sh short-circuit + update-sync-manifest.sh reconciliation). Verified end-to-end with a seeded manifest.

## What was ambiguous / required contract edits

### Ambiguity 1 — MCP scope for `@inbox/open/` writes (Resolved: Edit 1 in contract-edits.md)

**Contract said**: use `mcp__obsidian-projects__*` for proposal writes (§5, §6).
**Reality**: `mcp__obsidian-projects__*` has read-only access outside `/@second-brain/projects/`. Only `mcp__claude_ai_obsidian-manifest__*` has readwrite on `/@inbox/`.
**Research anticipated this** (R2 explicitly called it out as a "verify at implementation time" risk). But the contract body didn't carry the fallback clearly — I had to make the switch and file a contract edit.
**Time cost**: ~5 minutes to verify with `get_permissions` on both MCPs, ~10 minutes to patch contract + workflow. Low.
**Could have been prevented by**: specifier calling `get_permissions` during `/plan` so the contract landed with the correct scope up front. The research flagged it as a risk, but the contract took the happy-path.

### Ambiguity 2 — "update-sync-manifest.sh calls MCP" (Resolved: Edit 2)

**Contract said** (§6): `update-sync-manifest.sh` calls `mcp__obsidian-projects__list_files` for `@inbox/open/` reconciliation.
**Reality**: `update-sync-manifest.sh` is a wheel command step — pure bash/jq. Command steps cannot invoke MCP tools (that's agent-step-exclusive). The contract mixed up which step owns reconciliation.
**Resolution**: moved reconciliation into the `obsidian-apply` agent step (§5.3 new), passed results through to `update-sync-manifest.sh` via the existing `.wheel/outputs/obsidian-apply-results.json` path. `update-sync-manifest.sh` now consumes `results.mistakes.reconciliation[]` and applies state transitions.
**Time cost**: ~10 minutes. The fix was structurally clean (the agent step already has MCP + the reconciliation logic naturally fits next to the create/update loop).
**Could have been prevented by**: the contract author separating "which step has MCP authority" from "where state transitions happen" up front. An explicit "MCP access table per step" in the contract would have caught this.

### Ambiguity 3 — how the agent receives prior manifest state (Resolved: added `mistakes_prior_state` to §4)

The §5.3 reconciliation needs a list of "prior mistakes with proposal_state=open" so it knows what to check against `list_files` output. The agent receives `compute-work-list.json` via `context_from`, so the natural path is to ship this projection from compute-work-list. I added `mistakes_prior_state[]` to the top-level output shape + updated the contract.

## Assumptions I made

- **YAML frontmatter parsing in bash.** The `compute-work-list.sh` extension parses frontmatter with `awk` + `grep` + `sed` instead of calling a YAML lib. This is fragile for weird corner cases (multi-line values, complex tag lists) but consistent with the rest of the script (it already does this for the shelf config). If mistake notes start having multi-line `correction:` values or `tags:` as JSON inline, the parser will degrade to "best-effort" — but the consumer (the `obsidian-apply` agent) is an LLM and will tolerate messy fields. Good enough for v1.
- **The agent will build `mistake_class` correctly.** The contract says "the single mistake/* tag"; the instruction I wrote tells the agent to pick the first tag starting with `mistake/`. If the user has two (per FR-008 rare cross-class allowance), the contract says first wins. Might surprise users; worth a retro note.
- **`create_if_missing` semantics on `append_file` extend to `create_file`.** Did NOT assume this — stuck to the contract's explicit "already exists → patch_file fallback" pattern.
- **The agent will produce correct ISO-8601 UTC timestamps in the `last_synced` field.** Didn't try to inject a pre-computed timestamp via `context_from` because the agent step runs asynchronously and will have its own "now".

## What I wish the contract had been more explicit about

1. **MCP access matrix per step.** "Step X can call these MCP tools; step Y cannot call MCP at all." Would have caught Edits 1 + 2 in review.
2. **Concrete scope ownership of `@inbox/`, `@manifest/`, `@ai/` at plan time.** A one-line `get_permissions` check + a line in research.md like "inbox writes go via manifest MCP" would have prevented Edit 1.
3. **Whether the agent's results JSON is merged or overwritten with the existing (e.g., issues) counts.** I assumed the agent rewrites the whole file each run (the existing instruction does this) but there's no explicit contract clause.

## Upstream bugs I noticed but did NOT fix (out of scope)

- **#102 `tags: []` in dashboard patch**: still there; the contract for mistakes doesn't touch the dashboard, so I left it alone. Flagged in the team-lead briefing.
- **#103 progress appended on no-change syncs**: my step 2 guard now also includes `mistakes` in the "no work" check, which slightly improves the no-change case, but #103 is a broader progress-block issue that predates this feature.
- **#105 dashboard patched even when values unchanged**: untouched for the same reason.

## What slowed me down

- **Waiting for Task #1 (specifier)** — inherent to the dependency. I used the wait productively by reading all reference files (shelf-full-sync.json, compute-work-list.sh, update-sync-manifest.sh, .shelf-sync.json), calling `get_permissions` on both MCPs (this is what surfaced Edit 1), and reading the PRD end-to-end.
- **The initial `$results` undefined error** in update-sync-manifest.sh — I added `$results` references in the jq block but forgot to add `--argjson results "$results"` to the args list. Caught it on first run, fixed in ~60 seconds. Low friction, but a reminder that jq's late-binding of `$var` names is forgiving and fails loud on the first reference — which is the best behavior.
- **`move_file` argument name**: first call used `source_path`/`destination_path`, the MCP wanted `from_path`/`to_path`. Two retries. Minor.

## What went well

- **The existing `compute-work-list.sh` pattern was easy to extend.** The script already had hash-based diff logic for PRDs and a manifest-lookup pattern for issues. Mirroring those for mistakes was ~80 lines of new code with zero surprise.
- **The contract split into §4/§5/§6** matched the three files I needed to touch (`compute-work-list.sh`, `shelf-full-sync.json`, `update-sync-manifest.sh`) 1:1. Zero scope drift.
- **Fixture-driven testing** (T030–T032) let me exercise every state transition locally without needing the full wheel-engine round-trip. Saved the live smoke for Phase 5.

## Retrospective signals for the team

- **Specifier**: the MCP-scope risk was correctly flagged in research.md §R2. Recommend for future plans: call `get_permissions` explicitly during `/plan` when any new MCP write path is introduced, and bake the result into the contract body (not just the research appendix). Would have avoided Edits 1+2.
- **Auditor**: verify end-to-end from a consumer install (Phase 5 smoke) because the plugin-cache indirection was NOT exercised here — my sanity runs used the source-repo scripts directly.
- **Retrospective**: the two contract edits were ambiguity-driven, not sloppiness. The research flagged the risk; the contract didn't internalize it. That gap is the interesting signal.
