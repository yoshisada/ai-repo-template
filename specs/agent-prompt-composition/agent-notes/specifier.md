# Specifier friction note (FR-009)

**Author**: specifier (kiln-prompt-composition pipeline)
**Date**: 2026-04-25
**Branch**: `build/agent-prompt-composition-20260425`

## What was confusing

- **`research-runner.md` already existed.** The PRD's FR-A-10 lists "3 minimal agent.md files SHIP under `plugin-kiln/agents/`: `research-runner.md`, `fixture-synthesizer.md`, `output-quality-judge.md`" but `research-runner.md` is already on disk from a prior build (its body explicitly references runtime-injected variables). Spec had to add an explicit "audit/refactor in-place" carve-out (Edge Cases + T-A-09) to avoid double-shipping. This was a derivable surprise — the PRD didn't flag it, but a 30-second `ls plugin-kiln/agents/` would have. **Suggestion**: PRDs that "ship N agent files" should pre-flight check existing files and explicitly state new vs existing in the FR table.
- **OQ-3 phrasing was lopsided.** The PRD said `agent` shape's necessity is "decided during implementation; defaults to 'include in v1' unless evidence emerges otherwise" — but the very PRD shipping is itself an `agent`-shaped task (3 new agent.md files). The "decide later" framing buried the load-bearing exemplar. Easy resolve in spec, but the PRD could have stated the resolution in the OQ itself.
- **OQ-1 hybrid resolution timing has a subtle ambiguity.** "Source authoring under `_src/`" implies all sources live there, but that's only useful for agents that USE includes. Agents with no includes (`continuance.md`, `smoke-tester.md`, etc.) should stay in-place — adding an `_src/` indirection for them would be ceremony. Resolved by clarifying in plan.md that `_src/` is per-agent opt-in. Worth pinning in PRD next time.

## Where I got stuck

- **OQ-4 (composer location).** Genuinely a coin-flip. Existing `resolve.sh` is small (~60 lines, single-purpose) and stable; conflating it with composer responsibilities (verb tables, variable bindings, stanza concatenation) felt wrong. But siblings risk a "what's the difference?" question. Resolved sibling because `resolve.sh` answers "what agent is this?" and `compose-context.sh` answers "what's the runtime context block for this agent + this task?" — different responsibilities, different change cadence. Confidence: medium-high.
- **Theme partition table.** The spec.md "Theme Partition" table is the load-bearing artifact for NFR-8 (disjoint file ownership). Took two passes to enumerate — first pass missed `CLAUDE.md` (it's a Theme A doc-update target, not Theme B even though Theme B's directive syntax is also documented there). Resolved by giving Theme A sole ownership of CLAUDE.md and having T-A-17 reference Theme B's syntax via a one-paragraph aside in the same Theme-A-owned section.

## Did the unified-PRD framing create spec-phase friction that two-PRDs-and-coordinate would have avoided?

**Mostly no, but there's a small cost.**

- The unified PRD was helpful: the implementation_hints from BOTH source items live in one PRD body, so the spec could partition FRs (`FR-A-*` vs `FR-B-*`) into clean theme buckets. The two themes genuinely compose ("agent.md = (role identity) + {compile-time include} ← compile-time; spawn = (Runtime Env) + (task) ← runtime") and bundling them lets the spec lead with that architectural framing as a User Story 1/2 paired narrative.
- The cost: maintaining the **disjoint file partition** (NFR-8) required an explicit table + audit step (T-V-03). With two separate PRDs, file partition would have been implicit-by-construction (different PRDs touch different file trees naturally). Here it had to be authored as a contract.
- **Net assessment**: bundling was worth it. The unified architecture story is the PRD's load-bearing claim; splitting would have required cross-PRD coordination prose that's strictly worse than NFR-8's table. The friction is bounded (one table to maintain, one audit step to run).
- **Caveat for retrospective**: the implementer-coordination cost is unknown until both implementers actually run in parallel. If they hit unanticipated cross-track friction (e.g., `_shared/coordination-protocol.md` body shape mismatches what the composer expects), that's a data point arguing for two-PRDs-next-time. Spec phase has no such friction to report.

## Suggestions

1. **PRD pre-flight checklist for "ships N files"**: distill should pre-check whether files in `agent_bindings:`-style FRs already exist; flag in PRD with `(EXISTS — audit only)` vs `(NEW)`.
2. **OQ resolutions in PRD**: when the answer is unambiguous from the rest of the PRD body (like OQ-3 here), state the resolution in the OQ instead of deferring to spec phase.
3. **Theme partition tables**: should be a recommended pattern for any unified PRD bundling 2+ themes. The cost of authoring it is small; the cost of NOT having it is parallel-implementer file-conflict bugs.
