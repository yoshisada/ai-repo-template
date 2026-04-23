# Agent Notes — impl-feedback-interview

**Scope**: Phase U (T013–T017). Files touched: `plugin-kiln/skills/kiln-feedback/SKILL.md` only.

## What went well

- **Contracts carried the load.** `contracts/interfaces.md` §5 and §6 had the exact question wording, the area map, the blank-answer handling, the skip wording, and the body shape pinned down before I started. I did not have to invent anything. Plan Decisions 4 and 5 were both fully-locked — the "don't improvise the question count" heads-up was unnecessary because the contract was unambiguous. If the contract had been looser, I would have had to ping the team lead.
- **NFR-003 called out three times (task brief, tasks.md, spec.md) made the "no wheel / no MCP / no background sync" boundary very clear.** Zero chance of accidentally importing the `/kiln:kiln-report-issue` dispatch-background-sync pattern.
- **Zero file overlap with impl-claude-audit** worked exactly as designed. No coordination required. One file owner per file made Phase U a solo walk.

## Friction

- **Verification is unavoidably manual.** The plugin has no unit test harness, so "verifying SC-005/006/007" was a mental walk-through of the skill body. That's fine for a skill body — the skill IS the unit of work — but it means a regression in the skill wording (e.g., an em-dash getting autocorrected to a hyphen in the skip option) would not be caught by anything mechanical. Consider adding a cheap grep-based assertion set that checks the skill body still contains the exact required strings (skip wording, Q1/Q2/Q3 verbatim). Low cost; catches copy-paste drift.
- **The "skip is last option at every prompt" rule is a presentation detail the skill body can only describe, not enforce.** When Claude actually runs the skill, the prompt rendering is Claude's responsibility — the skill text says "last option" but nothing verifies that Claude puts it last. The only durable safeguard is the verbatim wording check mentioned above: if the wording stays verbatim, the ordering is enforced by convention. If we care about this being bulletproof, a future hardening pass could wrap the interview in a small helper script that formats the prompt list.
- **Overlap between `## Rules` and the in-step instructions was tempting to expand.** The existing skill had a terse Rules section; the new interview logic has body-shape invariants, skip semantics, and blank-answer handling — all of which could plausibly belong in Rules too. I resisted duplicating: the in-step text is the operational instruction; Rules is a terse summary. If the skill grows further, the Rules section will bloat and duplicate — that's a known shelf-life issue but not a Phase U problem.

## Non-obvious choices worth flagging for the retrospective

1. **I added a `## Rules` line about interview-runs-by-default.** The contract didn't mandate this — the step body already says so. But the Rules block is where a reader skims for behavior invariants, and "interview runs by default; skip is the escape hatch" is the single most-likely-to-be-inverted mental model for this feature. Keeping it explicit in Rules felt worth the minor duplication.
2. **The body-shape block in Step 5 uses a commented-out placeholder (`# ONLY when Step 4b completed (not skipped)`) to show conditional structure inline.** The alternative would have been two separate code blocks (one for interview-completed, one for skipped). Inline comment is denser and less redundant; since the skill body is Markdown consumed by Claude, the inline comment is readable context, not executed code.
3. **I did not add a CLI-flag note ("`--no-interview` is NOT supported, do not add it").** The task brief flagged this explicitly as a rule, but the plan Decision 5 already makes it unambiguous and the Rules section says "No CLI flag." Repeating a negative ("do not add X") inside the skill body would be noise. If a future implementer is tempted to add a flag, they'll hit the plan and the Rules line first.

## What I did not do (and should not be mistaken for TODO)

- I did not run `/kiln:kiln-feedback` end-to-end. That's a Phase W smoke item and would require actually executing a skill — the verification above is the pre-ship walk. If Phase W / auditor want a live run, invoke the skill in a clean branch.
- I did not touch T021 (SMOKE.md). The task brief noted I'm probably not the last-lander; I finished Phase U at ~5 tasks while impl-claude-audit has 15+ tasks across R/S/T/V. They'll be the last-lander.
- I did not modify the classification prompts in Step 4. The existing "ASK if ambiguous" gate is preserved verbatim; the interview layers ON TOP at Step 4a, never replacing Step 4.

## Handoff

- **T013–T017**: all `[X]` in `tasks.md`.
- **Verification record**: `specs/kiln-self-maintenance/agent-notes/phase-u-verify.md` — SC-005/006/007 walked through, all PASS.
- **Single commit** landing the whole phase per the `tasks.md` checkpoint ("feat(kiln): /kiln:kiln-feedback interview mode (Phase U)").
- **Ready for auditor and T021 (SMOKE.md)**: whichever of us finishes last picks up SMOKE.md; I'm not the last-lander by task count.
