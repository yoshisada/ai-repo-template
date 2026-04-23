# Specifier friction notes — kiln-capture-fix-polish

**Agent**: specifier
**Task**: #1 (spec + plan + tasks for kiln-capture-fix-polish)
**Date**: 2026-04-22

## What went well

- PRD was tight and unambiguous on the four areas (A/B/C/D). The FR-to-spec-FR mapping was mechanical; almost no invention needed.
- The three decisions the team lead called out (reflect gate, skill name, feedback schema) all had clear PRD-level recommendations. Grep confirmed zero `distill` collisions, so Decision 2 was a free pick.
- The plan's file-ownership table fell out naturally — the two tracks have disjoint file sets apart from the rename/sweep coupling in Phase D→E.

## Friction / open items

- **Step 7.5 reuses a team-brief body shape for the inline fix-note.** T002 says "reuse the body shape that was previously inside `team-briefs/fix-record.md`". The brief is being deleted in T004, so the implementer will need to READ the brief's body section BEFORE deleting it, then port that template structure into the inline bash. A safer ordering would be T002 first (port body), then T004 (delete). Tasks.md notes Phase A tasks run serially with T001 first — verify the implementer picks up the brief contents before T004 removes them. Consider adding an explicit "copy the body template into the SKILL.md before deletion" bullet to T002 if the implementer misses it.

- **Reflect gate predicate false-negative risk.** Decision 1's deterministic gate is cheap but will miss cases where the fix touched a non-template file and the commit message never mentions `manifest`. The PRD accepts this ("leave the door open for a judgment-based upgrade"). If smoke testing reveals consistent misses, the follow-up is a "judgment upgrade" feature, not a change to this one.

- **Phase F ownership is ambiguous.** tasks.md says "whichever implementer lands last". This works in practice when both tracks check the task list, but if both finish roughly together, both may skip it. The team lead should nominate an owner when one track visibly lags, or the auditor can pick it up. Not a spec bug — a coordination seam worth flagging.

- **No contract for the "body shape" of the inline fix note.** I punted on specifying the exact markdown body template for the Obsidian fix-note write (just said "reuse the body shape that was previously inside `team-briefs/fix-record.md`"). An implementer reading only spec/plan/contracts without reading the deleted brief would be stuck. The tasks.md bullet for T002 mitigates this but the contract file itself is silent. If the implementer asks for it, point them at the existing `team-briefs/fix-record.md` before T004 deletes it.

- **`kiln-fix` SKILL.md references FR-019, FR-020, FR-023, FR-025 from a different feature's spec.** Step 7's "Constraints enforced by this step" block cites those FRs in-prose. Those numbers belong to the `fix-skill-with-recording-teams-20260420` feature, not this one. Phase A's T006 asks the implementer to leave what still applies — the implementer should understand these are cross-references to the prior spec, not self-references. If they assume they belong to the current spec they'll get confused.

## Decisions taken

- **Decision 1 (reflect gate)**: deterministic file-path predicate, three-condition union. Locked with reference bash implementation in plan.md. Implementers may rewrite but must preserve the three conditions.
- **Decision 2 (new skill name)**: `kiln-distill`. Confirmed zero collisions via `grep -rn 'distill\|kiln-distill'`.
- **Decision 3 (feedback schema)**: seven required frontmatter keys (`id`, `title`, `type: feedback`, `date`, `status: open`, `severity`, `area`, `repo`) plus two optional (`prd`, `files`). Enum values match PRD's proposed taxonomy exactly. Kept distinct from issue schema per PRD risk note on schema drift.

## Task partition sanity check

- impl-fix-polish: 9 tasks (cap 12). ✓
- impl-feedback-distill: 12 tasks (cap 12). ✓ right at the cap — no room to grow.
- Total 22 tasks (cap 24). ✓

If Phase D or E expands during implementation, the expansion should absorb T022 into the earlier-lander's track rather than growing impl-feedback-distill past 12.

## Unblocks

This spec unblocks tasks #2 and #3 simultaneously. Both implementers can start on their respective tracks as soon as the commit lands.
