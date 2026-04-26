# Audit-PR Friction Note — research-first-foundation

**Agent**: audit-pr
**Date**: 2026-04-25
**PR**: https://github.com/yoshisada/ai-repo-template/pull/176

## What I Did

1. Waited for both audit-compliance (PRD 100%, 0 blockers) and audit-smoke (SC-001/002/004 PASS, SC-003 FAIL) to signal.
2. Reconciled `blockers.md` — promoted from "CLEAR" to "1 KNOWN ISSUE" capturing the SC-003 TOKEN_TOLERANCE calibration gap surfaced live by audit-smoke. Documented as non-blocking-for-merge with rationale (substrate correct, calibration constant needs widening; v1 gate semantics verified by SC-002).
3. Committed audit artifacts + the FR-S-002/FR-S-003 inline-comment fix audit-compliance staged on `plugin-wheel/scripts/harness/research-runner.sh`.
4. Pushed `build/research-first-foundation-20260425` to origin.
5. Opened PR with `build-prd` label and honest SC matrix (3/4 PASS, SC-003 FAIL with explicit follow-up).

## Friction

- **17 untracked `docs/` files appeared in `git status`** that are unrelated to this branch (Mintlify scaffolding from an earlier session). I deliberately did NOT `git add` them — only staged research-first-foundation artifacts + the runner FR-comment fix. `gh pr create` warned about uncommitted changes; the warning is correct but the PR diff is clean (only feature-relevant files).
- **PR template's "Smoke Verdicts" section assumed all PASS** — I reshaped it to be explicit about the SC-003 FAIL rather than papering over it. The "Test plan" checkbox for "Smoke matrix all PASS" is intentionally left UNCHECKED to make the calibration gap discoverable to reviewers.
- **The SC-003 calibration gap is a real surprise**, not a typo: the TOKEN_TOLERANCE=±10 was calibrated for isolated 2-run measurements (research.md §NFR-001 measured ±3 tokens), but the runner executes 6 interleaved invocations where LLM non-determinism produces 600–32000 token swings. This is a design-vs-runtime mismatch that audit-smoke caught precisely because it ran the live gate. PR body and blockers.md both call this out so the follow-up isn't lost.

## What Would Help Next Time

- **Pipeline pre-flight should ignore unrelated untracked files in `git status`** so audit-pr doesn't have to manually decide what to stage. A `git status -uno` or explicit branch-scope diff at PR-creation time would eliminate the "17 uncommitted changes" warning noise.
- **The PR template should accommodate non-passing SC verdicts** by default (e.g., a `<PASS|FAIL>` placeholder per SC plus a "blockers vs follow-ups" reconciliation paragraph). The current template implicitly assumes all-green, which forces the audit-pr agent to reshape it under time pressure.
- **TOKEN_TOLERANCE calibration should be relative from day one**. Absolute thresholds work for isolated single-fixture tests but break for any multi-arm runner. This is a v1 lesson worth threading into the next iteration's plan.

## Addendum: Race condition with team-lead PAUSE signal (PI candidate)

After PR #176 was opened, team-lead messaged a PAUSE signal asking audit-pr to hold on `gh pr create` until impl-runner shipped a SC-003 calibration fix-up and audit-smoke re-verified. The PAUSE arrived AFTER audit-pr had already pushed + opened the PR (the spawn instruction said "wait for both audits to signal unblock," and both had — audit-pr had no signal that team-lead might inject a fix-up between audit-smoke completion and PR open).

**Resolution**: PR #176 flipped to draft via `gh pr ready --undo 176`, with a comment explaining the calibration fix is in flight. Body will be edited to flip SC-003 → PASS once audit-smoke re-verifies; PR flipped back to ready via `gh pr ready 176`.

**PI candidate for retrospective**: audit-pr's spawn instruction should add a third gate after the audit signals — an explicit "all-green, proceed-to-PR" signal from team-lead — so a PAUSE for in-flight fix-ups can interpose between audits-complete and PR-open without race. Today's protocol couples "audits complete" with "team-lead approves PR open"; decoupling them would let team-lead inject calibration fixes (or other surprises surfaced in audit) without forcing a draft-flip dance after the PR is already public.

## Task Status

Task #6 (audit-pr) → completed (PR shipped). Draft-flip + body-edit + ready-flip are a small fix-up under the same task per team-lead direction.
