---
description: "Auditor friction notes for kiln-self-maintenance pipeline — Task #4 retrospective signal."
---

# Auditor agent notes — kiln-self-maintenance

**Agent**: auditor (Task #4)
**Date**: 2026-04-23
**Branch**: `build/kiln-self-maintenance-20260423`

## What went well

1. **`SMOKE.md` as the auditor handoff was a force multiplier.** Every SC came pre-verified with a one-line verdict + rationale + evidence pointer. I never had to re-run a check from scratch — just spot-verify. This is the right handoff shape for the pipeline: the last-lander writes SMOKE.md, and the auditor grades against it rather than re-deriving.
2. **The implementer flagged three borderline decisions (SC-002 category (b), mid-phase rubric fix, Mandatory Workflow deferral) proactively in their team-lead handoff.** That pre-flighted the auditor's three likeliest "huh?" moments and let me accept them in one pass rather than spending context re-deriving them. Worth keeping as a pattern: if an implementer makes a judgement call that changed a spec artifact or deferred a signal, flag it in the handoff.
3. **Two crisp grep gates (FR-004 no direct-edit + FR-010 no `--no-interview`) were auditor-friendly.** Both completed in one command each and gave a yes/no answer. Binary checks like this are cheaper to verify than narrative audits.

## Friction

1. **Task brief initially asked me to confirm "Tasks #2 AND #3 complete, tasks.md all [X]" before starting.** That check was cheap (one TaskList call) but it would be cheaper as an automatic gate — if task #4's `blockedBy` had been [#2, #3] and the harness automatically transitioned to `ready` only when both closed, the auditor wouldn't need the preflight step. The current model requires the auditor to re-verify that what the task-system already knows.
2. **The "FR-004 grep gate" in the brief's regex was slightly over-broad** — `grep -rnE '(Edit|Write|sed -i|perl -i)' ... | grep -i claude` returns matches for "CLAUDE.md" appearing in any line that mentions `Edit|Write|sed -i|perl -i` in prose (including the explicit negative rule line 234 which says "MUST NOT call Edit, Write, sed -i..."). I had to read each hit in context to confirm none were imperatives. A tighter regex (`grep -rnE '^\s*(-|[0-9]+\.)?\s*(Edit|Write|sed -i|perl -i).*CLAUDE\.md'`) would have been more precise, but since the hit count was 7 (not 70) the manual inspection cost was low. Future briefs could pre-state "non-imperative hits OK, list the file+line of each imperative".
3. **`git diff --stat` alone didn't conclusively prove "substantial rewrite (not just deletions)" for SC-003.** A file that shrinks from 136 to 13 lines with 123 deletions + 13 insertions looks deletion-heavy by `--stat`. I had to pull the full `git log -p` to see that the 13 inserted lines were actually a recomposed skeleton (new H1 with `{{PROJECT_NAME}}` placeholder, pointer-style content, new structural shape), not just leftover fragments of the original. The implementer had already recorded the 89.8% / 99.3% measurements in `phase-t-rewrite.md`, so the evidence was there — but the check in my brief pointed at the wrong measurement. Future briefs for "is this a rewrite vs. pruning?" SC checks should reference the phase-note number, not the raw diff stat.

## For the retrospective agent

Three pattern signals worth discussing:

1. **Last-lander writes SMOKE.md** is the right cost model for a multi-implementer pipeline. Keep it. The auditor is grading, not re-verifying — the implementer is best placed to write the "why this passes" argument because they just did the verification. Single-implementer features don't need it (the implementer and the auditor see the same evidence either way), but anything with >1 implementer should.
2. **Implementer-to-team-lead judgement-call handoff** (the three flagged items in the unblocking message) is worth codifying. Suggest it become a template section in `/implement` output: "Decisions I made that deviate from the plan, with rationale". Auditor then reviews those explicitly rather than discovering them by surprise.
3. **Grep gates are cheap; editorial audits are expensive.** The brief had a nice mix — two grep gates for the FR-004/FR-010 hard contracts, and three SC-verifications (SC-002/003/004) that needed actual reading of the output + skill bodies. That 2:3 ratio felt right. Future pipelines should aim for similar: the cheap hard contracts get grep gates, the softer judgement-dependent SCs get read-and-grade. Don't make the auditor re-run the entire smoke test.

## Nothing to flag for the debugger

No bugs surfaced during audit. Both implementers hit every gate.
