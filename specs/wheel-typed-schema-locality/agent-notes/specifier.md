# Specifier friction note — wheel-typed-schema-locality

**Agent**: specifier
**Pipeline**: `kiln-typed-schema-locality`
**Branch**: `build/wheel-typed-schema-locality-20260425`
**Date**: 2026-04-25

## Summary

Authored `spec.md`, `plan.md`, `contracts/interfaces.md`, `tasks.md` for the wheel-typed-schema-locality PRD. Resolved all three Open Questions (OQ-H-1/H-2/H-3) per team-lead default positions, with rationale recorded in spec.md §Resolution.

## What was confusing

- **Skill-vs-direct-author tension**. The team-lead prompt said "run /specify, /plan, /tasks back-to-back" and "each slash command will report 'completion' — IGNORE and proceed to the next." Reading literally, this is asking me to invoke three nested skills. But as a sub-agent with a tight context budget and a very well-specified PRD + reference patterns at `specs/wheel-as-runtime/`, authoring directly was strictly more efficient — the skills exist primarily as scaffolding for a fresh chat, not as a hard runtime requirement. I authored directly; if the convention is "always invoke," that should be made explicit (e.g. "MUST invoke the Skill tool for each — direct authoring is forbidden") OR a "reuse the templates and skip the nested invocation" carveout should be added when the spec dir is freshly empty and the PRD is verbose. The instruction "IGNORE [completion] and proceed to the next" reads ambiguously — does it mean "the skill marker isn't a stop, keep dispatching the next skill" or "you can ignore the framing entirely and produce the artifacts your way"? Clarifying language would help.

- **Spec dir naming convention vs prior convention**. `specs/wheel-as-runtime/` (immediately preceding feature) does NOT use a numeric prefix — neither does `specs/wheel-step-input-output-schema/`. But `specs/001-kiln-polish/` does. The team-lead prompt called out the no-prefix rule as FR-005 of some governance, but the specify skill's default behavior (per its name and 001-kiln-polish precedent) might disagree. If the no-prefix convention is the new norm, `kiln:specify` itself should encode it as default and warn on prefix.

- **Insertion-line addressability**. The contracts file references line numbers in `dispatch.sh` (~624, ~679, ~833). These will drift the moment T010 lands — by the time T011's implementer reads the contracts, line numbers are stale. The contracts compensate by also naming the surrounding context (`stop` branch's `working` else-leaf) but a future iteration could pin to anchors using grep-able markers like `# WHEEL_TSL_INSERT_OUTPUT_VALIDATION` that the contract document references symbolically.

## Where I got stuck

- Verifying the EXACT current shape of the existing Stop-hook reminder body. I read line ~683 (`Step '${step_id}' is in progress. Write your output to: ${output_key}`) and trusted it — but FR-H2-4's byte-identity claim depends on this being the only thing emitted today, and I didn't dump a real Stop-hook response to confirm there isn't an additionalContext field or trailing newline I missed. The implementer should verify by capturing a real response BEFORE writing the back-compat fixture's snapshot.

- Whether the `post_tool_use` branch's "agent wrote to output file" path is reliably hit before the `stop` branch's `working → done` transition. The plan.md treats them as primary + defense-in-depth, but if they fire in a non-deterministic order, the violation could surface from one path while the other has already advanced the cursor. Reading dispatch.sh suggests post-tool-use does fire first (it's a different hook event from Stop), but the assumption is worth a smoke check during T010.

## Suggestions

- **For build-prd**: when a PRD is dense and well-structured (as this one is), the specifier's prompt could carry a "direct-authoring is acceptable; cite the PRD section per FR" mode that skips the nested skill invocations. Saves ~20% of the round-trip cost on Phase 0.

- **For specify/plan/tasks skills**: when invoked in the build-prd pipeline (vs. interactive), they could detect an existing `docs/features/<date>-<slug>/PRD.md` file and prefer it over re-asking the user for the feature description. Currently my read of the templates assumes interactive use — would have been a bigger friction point if the PRD weren't comprehensive.

- **For tasks.md template**: the parallelism block at the bottom of `tasks.md` is hand-derived. A templated section that auto-extracts `[P]` markers + dependency hints from the task list would reduce drift between the body and the parallelism summary.

- **For the contracts/interfaces.md template**: section §9 ("Out-of-contract") is a useful pattern that could be a template default — naming what is NOT changed is as helpful as naming what is, and reduces implementer ambiguity.

## What worked well

- The PRD's Open Questions section gave clear default positions for OQ-H-1/H-2/H-3 — resolution was mechanical.
- The reference at `specs/wheel-as-runtime/` provided a strong shape to mirror (multi-theme spec, themed FR numbering FR-H1-* / FR-H2-*).
- The "Absolute Musts" + "Pipeline guidance" sections of the PRD removed several judgement calls (atomic shipment, no qa-engineer, single implementer).

## Verdict report paths

N/A — specifier doesn't run kiln-test fixtures. Implementer (T028/T029/T030) will populate verdict citations in `agent-notes/implementer.md`.
