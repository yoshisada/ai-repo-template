# Specifier — Friction Notes

**Task**: #1 (specify + plan + tasks + contracts for kiln-self-maintenance)
**Run**: 2026-04-23

## What went smoothly

- The PRD was unusually well-shaped: the Risks & Open Questions section mapped 1:1 to the 5 decisions the team lead asked me to lock. I could read them in one pass and resolve each with a short paragraph in `plan.md`. No re-interrogation of the PRD author needed.
- Two-implementer split was obvious from the PRD's Implementation Ordering Note (CLAUDE.md track vs. feedback track). Partitioning `plugin-kiln/skills/kiln-feedback/SKILL.md` to `impl-feedback-interview` and everything else to `impl-claude-audit` meant no file had two owners — zero coordination overhead at the contract level.
- The existing `/kiln:kiln-feedback` SKILL.md and `kiln-doctor/SKILL.md` files gave me concrete insertion points to reference in the contracts (`Step 4a/4b between existing 4 and 5`, `Step 3g in the doctor sweep`). That's cheaper to specify and cheaper to review than abstract "add the interview step".

## Friction points

- **Consumer-override precedence (Decision 1)** was the only decision where I had to make a non-obvious call. The PRD risks section said "repo override > plugin default" but didn't specify whether that's per-rule (override wins on named rules, plugin defaults apply elsewhere) or full-file (override replaces the whole rubric). I picked per-rule merge, which matches `.shelf-config`'s precedent and is more forgiving to consumers who only want to tune one threshold. If the pipeline wants full-file replacement instead, plan.md Decision 1 is the single place to edit.
- **Editorial-signal failure semantics** aren't in the PRD. I added an edge case for "LLM editorial signal unavailable → record as `inconclusive` in the diff" and a contract clause in §2 Notes. If the audit is expected to hard-fail when the editorial model is down, plan phase needs to flip that.
- **Phase T audit-clean verification** (T011) creates a mini-chicken-egg: the scaffold has to pass the rubric, but the rubric gets finalized in Phase R. If an implementer over-constrains the rubric (e.g., requires a section the minimal skeleton doesn't have), T011 fails. I added a contract §4 explicit audit-clean requirement AND a "update contracts/interfaces.md FIRST" nudge in T011 to avoid silent rubric rewrites. Worth watching in review.
- **SMOKE.md last-lander** convention (T021) assumes the two implementers can coordinate on who lands last. If they land concurrently, either could claim it; the task is fine either way — it's just a docs rollup. No file conflict.

## Things the PRD was right to leave flexible

- The PRD hedged on whether audit was a dedicated skill or a `kiln-doctor` subcheck. I locked BOTH — dedicated `/kiln:kiln-claude-audit` runs the full rubric; `kiln-doctor` runs only cheap signals (Decision 2 path (c)). This avoids the "editorial LLM every doctor run" token cost AND gives the maintainer a dedicated entrypoint when they actually want the full audit. Two surfaces, one rubric.
- The PRD left interview question count at "3–6 max". I picked 5 cap (3 + 2 × area). 6 felt like fatigue territory; 4 (3 + 1) felt like it didn't earn the area-specific split. 5 is the sweet spot.

## Open signals for implementers to watch

- **impl-claude-audit, Phase R**: if the CLAUDE.md reference inventory (T001) turns up a section that's currently referenced but actually stale (e.g., a skill references a section that should itself be deleted), flag it in the inventory note and let the Phase V review decide. The rubric's `load-bearing` signal would mark the section to KEEP; an exception flag in the inventory is the right place to stage that exception.
- **impl-feedback-interview, Phase U**: the interview runs AFTER the existing classification gate, not before. If classification is ambiguous, the skill still hard-asks (existing contract). The interview is additive, not a replacement for the classification gate. Contract §5 "Placement" line is the single source of truth here.

## What I'd change next time

- The friction-note format itself could be a template in `.specify/templates/` instead of a freeform file. Right now every specifier invents the shape. One for a future pipeline to standardize.

## Completion status

All four spec artifacts committed to `specs/kiln-self-maintenance/`:
- `spec.md` — 11 FRs, 4 NFRs, 8 SCs, all traceable to PRD by `(PRD FR-NNN)` tags.
- `plan.md` — 5 locked decisions, phase table, constitution check PASS with no complexity entries.
- `tasks.md` — 21 tasks across 6 phases (R/S/T/U/V/W), owner-partitioned, dependencies named.
- `contracts/interfaces.md` — 7 numbered sections locking every downstream interface (rubric schema, audit I/O, doctor subcheck, scaffold shape, interview questions, feedback body shape, override shape).

Task #1 ready to be marked complete; both implementers unblocked simultaneously.
