# audit-pr friction note — merge-pr-and-sc-grep-guidance

**Agent**: audit-pr
**Date**: 2026-04-27
**Branch**: build/merge-pr-and-sc-grep-guidance-20260427

## What worked

- Pre-flight discipline paid off. On first activation the team-lead reissued the assignment while #1 was still `in_progress` and the spec dir was empty. Refusing to proceed (vs. running the steps verbatim and pushing an empty branch with `<FILL FROM AUDIT-COMPLIANCE>` placeholders literally in the PR body) prevented a junk PR. Team-lead confirmed the hold was correct.
- Two-channel proceed protocol ("audit-compliance done" + "tests audit passed — proceed") gave a clean, unambiguous start signal — no guessing whether one auditor's silence meant pending or done.
- audit-compliance + audit-tests both surfaced concrete numeric evidence (PRD 100%, SC-002 patched=3 then patched=0, NFR-002 27/27, preprocess-tripwire 11/11) that drops directly into the PR body — no recompute needed at this stage.
- blockers.md was already in the right shape (zero blockers, two by-design deferred items). Reconciliation reduced to a footer note rather than a hunt-for-commit-hash exercise.

## Friction

1. **PR-body template assumed numeric placeholders that auditors had already messaged.** The assignment shipped `<FILL FROM AUDIT-COMPLIANCE>` / `<FILL FROM AUDIT-TESTS>` / `<COUNT>` literals. Mechanical templating works, but the values arrive over SendMessage upstream, so the audit-pr role has to manually re-read auditor messages and substitute. A small structured-handoff (e.g. auditors include a `pr_body_fragment:` block in their proceed message) would remove a step. PI candidate.

2. **Out-of-order task-state vs. proceed signals.** audit-tests sent "tests audit passed — proceed" while their TaskList row was still `in_progress` ("Proceeding to mark task #5 complete" in their final line). The proceed signal is the human contract; the task-state lag is harmless but mildly confusing for an audit-pr that double-checks both. Acceptable as-is — flagging for awareness.

3. **Deferred-by-design SCs require post-merge action by audit-pr's role.** SC-001 + SC-007 live-fire only resolve once `/kiln:kiln-merge-pr <this-pr>` runs against the merged PR. That step happens *after* this skill invocation closes (Step 4b is in team-lead's main-chat, not mine per the assignment's "Step 4b lifecycle" note). The closure loop is correct but the ownership boundary is a place where, in a less-disciplined run, the live-fire validation could simply be forgotten. Worth a checklist item in build-prd's terminal stage.

4. **Friction-note path conventions.** audit-compliance and audit-tests both wrote to `agent-notes/<role>.md` (untracked at audit-pr arrival). The blockers.md commit naturally rolls them up if I `git add` the directory, but my assignment said only "commit the reconciled blockers.md" — strict reading would leave the auditor friction notes uncommitted. Resolved by including all three agent-notes in the same commit (cheaper than three commits, and the retro will need them on disk). Worth codifying in the build-prd skill: "audit-pr commits friction notes from prior auditors if they remain untracked at PR-creation time."

## Recommended PIs

- **PI-1 (high signal):** Auditors include a fenced `pr_body_fragment:` block in their proceed message containing the substituted compliance numbers. audit-pr concatenates verbatim. Removes one manual transcription step per build.
- **PI-2 (medium signal):** build-prd terminal-stage checklist explicitly schedules the SC-001 live-fire `/kiln:kiln-merge-pr <this-pr>` invocation for team-lead, so the deferred-by-design closure cannot silently slip.
- **PI-3 (low signal, doc-only):** audit-pr assignment text: "Commit the reconciled blockers.md AND any prior-auditor friction notes still untracked under agent-notes/."
