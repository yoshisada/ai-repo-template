# Agent Friction Notes: audit-compliance

**Feature**: merge-pr-and-sc-grep-guidance
**Date**: 2026-04-27

## What Was Confusing

- The pre-flight check said "confirm task #2 AND #3 are `completed`" but both were `pending` when I first polled — leading to a blocking message to team-lead. This was correct behavior, but the prompt could clarify that the agent should poll periodically rather than just send one message and wait passively. In practice I waited for a teammate message to re-check.
- The LIVE-SUBSTRATE-FIRST rule says to run `/kiln:kiln-test plugin-kiln auto-flip-on-merge-fixture` (the harness), but the team-lead's unblock message clarified that `bash plugin-kiln/tests/auto-flip-on-merge-fixture/run.sh` is the correct substrate. The discrepancy between the skill name in the prompt (`/kiln:kiln-test`) and the actual invocation path (`bash ... run.sh`) took one round of team-lead clarification to resolve.
- tasks.md had T060/T061/T062 (impl-roadmap-and-merge handoff tasks) and T070/T071 (impl-docs setup tasks) showing as `[ ]` at audit time. The team-lead confirmed both tasks #2 and #3 are `completed` in the task system, and the friction note files exist in agent-notes/. This discrepancy between the task-system state and the `[ ]` markers in tasks.md was noise I had to filter out. A note in the prompt like "unchecked setup/handoff tasks in tasks.md are cosmetic — verify the task system, not the checkboxes" would have helped.

## Where I Got Stuck

- Initial block: waited for impl-roadmap-and-merge (task #2) to move from `pending` → `completed`. No action needed beyond the block message, but there was no self-scheduling mechanism in this prompt (no `ScheduleWakeup` instruction). I received the impl-docs teammate message first, then a team-lead unblock.
- The NFR-002 check required understanding which fixture file is canonical: the team-lead said to use `plugin-kiln/tests/build-prd-auto-flip-on-merge/run.sh` (PASS=27 FAIL=0 per impl) for byte-identity, and the new `auto-flip-on-merge-fixture/run.sh` for SC-002. Both passed on live run.
- SC-007 spans two concerns: (a) helper idempotency (validated by the fixture's second run), and (b) live-fire on the actual PR merge (deferred to audit-pr stage). The prompt conflates them slightly — "run /kiln:kiln-test ... and cite the verdict" can only cover (a) pre-merge; (b) happens in the audit-pr lifecycle step by design. Documented as deferred-by-design, not a gap.

## What Could Be Improved

- **Prompt should clarify polling vs. waiting**: currently says "message team-lead and wait" but doesn't say whether to self-schedule a re-check. Adding `ScheduleWakeup` or "re-poll TaskList every few minutes" would make the wait deterministic.
- **Clarify SC-007 scope for pre-PR-merge audit**: SC-007 as written requires running `/kiln:kiln-merge-pr` on the actual PR, which can only happen in audit-pr. The live-fixture second-run covers the helper's idempotency gate. The prompt should explicitly say "SC-007 pre-merge evidence = fixture second run (patched=0); full SC-007 live-fire is the audit-pr gate."
- **tasks.md `[ ]` vs task-system conflict**: either the tasks.md `[ ]` markers should be authoritative (and implementers must check them), or the task system is authoritative (and auditors should ignore tasks.md for handoff/setup tasks). Currently the two sources are out of sync, creating noise. Prefer task-system as authority; update prompt accordingly.
- **FR-011 implementation deviation (minor)**: spec says `gh pr list --state merged --search "head:<branch>"` but code uses `--head <branch>`. Both accomplish the same thing; `--head` is the cleaner API. Spec should be updated to use `--head` to match implementation, or at minimum note that `--head` is equivalent and preferred.
