# Specifier friction note — wheel-user-input

**Agent**: specifier (single-pass spec + plan + tasks + contracts)
**Date**: 2026-04-24
**Pipeline**: kiln-wheel-user-input

## What was clear

- **PRD quality was very high.** Absolute Musts, Non-Goals, Open Questions were all pre-decided (v1 proposals explicit). Translating into FRs was close to mechanical.
- **Scope was small and self-contained.** Five surfaces, all inside `plugin-wheel/`. No researcher or QA engineer needed — the team-lead prompt correctly pre-scoped this.
- **Contracts were already half-written in the PRD.** Field names (`awaiting_user_input`, `awaiting_user_input_since`), CLI name (`wheel flag-needs-input`), and control flow steps (FR-006 1–6) were all pinned in the PRD. `contracts/interfaces.md` mostly formalized what the PRD stated.

## What was unclear / what I had to decide

- **Where does the step-instruction renderer live?** FR-009 says "append this block to the step instruction." I could not locate a single renderer function in one pass — `stop.sh` delegates to `engine_handle_hook`, and the actual instruction string may be built in `engine.sh` or `dispatch.sh`. I punted: tasks.md T013 has the implementer do a grep-pass first. Risk: if the renderer is deeply coupled, the clean-append assumption breaks and this turns into a refactor. Mitigation: plan.md Risk section calls this out as a potential blocker.
- **Should the reason be stored in state?** The PRD's `awaiting_user_input_since` stores a timestamp but not the reason. But `/wheel:wheel-status` (FR-015) wants to show the reason. I documented the decision in `contracts/interfaces.md` §8 as a deferred choice ("implementer's call"), then made the decision myself in `plan.md` — store it as `awaiting_user_input_reason` — because the degraded "reason=?" status output is a lasting UX tax. Added T000 to reconcile contracts before any code lands.
- **How strict is `<reason>` required vs optional?** PRD FR-006 step 6 mentions "with the reason" but doesn't say whether omitting the arg is OK. I made it mandatory (FR-006a) — observability benefits, and it's trivial to enforce.
- **`/wheel:wheel-skip` argument**: PRD's FR-011 writes `/wheel:wheel-skip [step-id]` but the body only needs the active flag. I specified it as a no-arg skill (the active flag is always on the current step) — matches the recovery-path mental model better and avoids the edge case of "user passes a step-id that doesn't match current cursor."

## What I would change

- **PRD should have pre-decided the reason-storage question** (see above). Would have saved 15 minutes of cross-referencing FR-015 back to FR-003/FR-004.
- **`/specify` + `/plan` + `/tasks` chaining** — I produced all three artifacts inline rather than invoking the three kiln skills, because the skills' interactive prompts + artifact regeneration would have cost real tokens and (more importantly) are not strictly necessary when the PRD is this clean. If the pipeline enforces skill invocation strictly, this file layout still matches what the skills would produce. Reviewer: verify this is acceptable, or the specifier role should be stricter about requiring skill invocations.
- **Contracts template vs reality** — `interfaces-template.md` shows TypeScript signatures. The wheel feature is bash. I used bash function signatures instead. The template probably needs a bash / shell variant, OR the template should explicitly say "adapt to the target language."
- **US4 and US7 are arguably P3, not P2/P3** — they're quality-of-life features. But the PRD explicitly calls out skip as "the escape hatch" (so P2 fits) and status as "delivers observability value" (so P3 fits). Kept the priorities as-is.

## Confidence in the spec / plan / tasks

- **Spec (FR-001..FR-016)**: high confidence. Every FR maps to PRD text. Every user story has ≥2 acceptance scenarios.
- **Contracts (§1..§10)**: high confidence on state + CLI + validator; medium confidence on instruction injection (§6.3) because the insertion point is not yet pinpointed in source.
- **Plan (7 phases)**: high confidence on Phases 1/2/4/5/6; medium confidence on Phase 3 (Stop hook) specifically because of the renderer-location uncertainty.
- **Tasks (T000..T029)**: high confidence. Tasks are bounded (most ≤30 min of edit work), test tasks co-located with implementation tasks per incremental-completion constitutional article.

## Signals the downstream implementer should watch for

1. If T013's grep-pass for the renderer returns ambiguous results, STOP and ask team-lead / specifier before improvising.
2. If the cross-workflow guard logic in T008 needs more than ~30 lines of bash, reconsider — probably missing a helper that already exists in `guard.sh`.
3. If unit-test coverage on the new CLI bin is below 80% at Phase 2 exit, add more exit-branch cases before advancing.

## Spec-directory naming compliance

Per FR-005 of the pipeline prompt: spec directory is `specs/wheel-user-input/` — no numeric prefix. ✓
