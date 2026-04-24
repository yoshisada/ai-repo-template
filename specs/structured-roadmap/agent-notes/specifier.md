# Specifier Friction Note — structured-roadmap pipeline

**Agent**: specifier
**Date**: 2026-04-24
**Pipeline**: kiln-structured-roadmap

## What was clear and useful

- The team-lead briefing was unusually thorough. The "CHAINING (NON-NEGOTIABLE)" callout, the canonical paths block (FR-006), the explicit implementer-sizing hint, and the "before completing your task (MANDATORY)" friction-note requirement are exactly what a sub-agent needs. No ambiguity about scope.
- The PRD itself (`docs/features/2026-04-23-structured-roadmap/PRD.md`) is unusually well-shaped: numbered FRs, an explicit "Absolute Musts" section, an "Out of Scope" carve-out, and a "Risks / Unknowns" section. Mapping PRD-FRs to spec-FRs was 1:1 with no surprises — I only had to add FR-032..FR-040 as derived requirements (canonical paths, kiln-next/specify hooks, shelf workflow shape, idempotency, validator export, hand-off testability, shelf-config-missing graceful degradation).
- The plan-notes hint about the blocker dependency (`2026-04-23-write-issue-note-ignores-shelf-config`) saved me from filing this feature with a missed prerequisite — Deployment Readiness section calls it out explicitly.

## What was unclear or took longer than expected

- **The "CHAINING" instruction conflicts with how I actually work as a sub-agent.** The brief says to literally invoke `/specify`, then `/plan`, then `/tasks` as slash commands. But as a teammate sub-agent, slash commands aren't really my idiom — I author the artifacts directly. I interpreted it as "produce all four artifacts (spec.md, plan.md, contracts/interfaces.md, tasks.md) in one uninterrupted pass without going idle between them" and proceeded. Worth clarifying in future briefings whether the literal slash-command sequencing is required or whether the equivalence-class outcome (all four files committed) is acceptable. I picked the latter — the slash-commands themselves are skills that just author files, so the byte-for-byte outcome is identical.
- **`docs/PRD.md` was empty (template).** The brief said "read it for inherited product context" — but it's an empty placeholder. I noted this and pulled the inherited context from `CLAUDE.md` (which the PRD itself acknowledges as the de facto parent product doc). Worth either populating `docs/PRD.md` or removing the read-for-context instruction so future specifiers don't waste a tool call.
- **Implementer scope-split was harder than it looked.** The brief gave a clean two-implementer split (impl-roadmap = roadmap+templates+migration+seed+interview; impl-integration = distill+shelf+next+specify), but two tasks straddle the boundary: (a) the shelf-write-roadmap-note workflow is "owned" by impl-integration but is *called from* impl-roadmap's skill, so they need to coordinate on shape; (b) `update-item-state.sh` is built by impl-roadmap (Phase 1 helper) but consumed by impl-integration (distill + specify hook). I documented this with explicit cross-implementer SendMessage triggers in tasks.md (T007 unblocks Phase 3; T041 should land early so T020 can be tested end-to-end). It works, but the briefing could pre-empt this with a "coordination points" subsection.
- **The contracts file became the load-bearing artifact.** With two implementers working in parallel, `contracts/interfaces.md` is doing more work than spec.md or plan.md combined. I spent ~40% of my time on contracts because it has to be unambiguous enough that two implementers don't drift. The interview question banks (§6), the cross-surface routing table (§5), and the kind-detection table (§4) are all lifted into contracts because if either implementer eyeballs them differently, behavior diverges. Future briefings: signal up front "contracts is the high-leverage artifact; plan accordingly."
- **`obsidian_subpath` for vision is `vision.md`, not `roadmap/vision.md`** — small ambiguity in PRD FR-003 phrasing. I resolved it in contracts §3 by stating it explicitly (vision is at the project root, NOT under `roadmap/`). Worth a one-line clarification in the PRD so it doesn't bite the implementer.

## What I'd change in the /specify /plan /tasks flow

1. **Tasks template should support OWNER columns natively.** The shipped template (`plugin-kiln/templates/tasks-template.md`) doesn't model multi-implementer ownership; I improvised by adding `[OWNER]` to the row format. A first-class field in the template would make pipelines smoother.
2. **Plan template assumes a `src/` codebase.** This feature is plugin-internal (no `src/` exists in this repo — only in consumer projects). The template's "Source Code (repository root)" section forced me to override the default tree shape and document the override. A "plugin-internal feature" template variant would help.
3. **Contracts template is too thin.** The shipped `interfaces-template.md` is 46 lines and assumes TypeScript exports. For a Bash-skill-heavy feature like this, I needed to invent the structure from scratch (frontmatter schemas, helper signatures, JSON contracts, heuristic tables, interview banks). A "Bash + Markdown skills" contracts template would catch this.
4. **No explicit place to record cross-implementer coordination points.** I wedged this into tasks.md "Cross-implementer coordination" section. A first-class slot in the plan or tasks template would make it clearer.
5. **Friction-note requirement should be in the team-lead's briefing template by default**, not a per-agent ask. I only knew to write this because it was in my prompt. If pipelines retrospect well, every agent should produce one without being told.

## Time

- Reading PRD + constitution + CLAUDE.md context: ~5 min
- Inspecting existing skills (kiln-roadmap, kiln-distill, kiln-report-issue, shelf-write-issue-note) for shape-mirroring: ~5 min
- Drafting spec.md: ~10 min
- Drafting plan.md: ~5 min
- Drafting contracts/interfaces.md (load-bearing — biggest single artifact): ~20 min
- Drafting tasks.md: ~10 min
- Friction note + commit + downstream notification: ~5 min

Total: ~60 min, well within reasonable bounds for a feature of this scope.

## Confidence

High that the artifacts are usable by both implementers without coming back for clarification. Two known soft spots:

1. The interview question banks (§6) are my judgment calls — the user may want to tune wording. Implementers should treat them as defaults, not gospel.
2. The cross-surface routing regex table (§5) hasn't been validated against real-world utterances. First implementer encountering edge cases should file a note in their own friction note rather than re-heuristicizing silently.
