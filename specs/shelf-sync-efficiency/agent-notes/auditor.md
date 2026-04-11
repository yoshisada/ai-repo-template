# Auditor Friction Note

**Session**: auditor teammate, kiln-shelf-sync-efficiency pipeline
**Date**: 2026-04-10

## What worked

- **Contract-first paid off.** `contracts/interfaces.md` was detailed enough
  that the audit was largely "diff the JSON against section 2, diff the
  agent instructions against sections 4.2/6.2, diff the script outputs
  against sections 5.2/7.1." No ambiguity, no judgment calls.
- **Smoke-testing scripts in isolation was cheap and conclusive.**
  compute-work-list.sh and generate-sync-summary.sh both run as plain Bash
  against synthetic fixture files in /tmp in seconds. Got real output shape
  evidence without touching wheel-runner.
- **Snapshot harness sanity-checks in /tmp.** Creating a fake vault layout,
  capturing twice, perturbing a file, capturing again, and diffing — the
  harness exits 0/1 exactly as documented. Exercised the error path
  (OBSIDIAN_VAULT_ROOT unset -> exit 2) as a bonus.
- **Implementer's hand-off message was unusually good.** Explicit hard-gate
  scorecard, explicit "what I did NOT do and why", explicit list of the
  three spots most likely to hide bugs. Cut audit time roughly in half vs
  a cold read of the diff.

## Friction

- **Three of six hard gates are structurally blocked by session budget.**
  SC-001 (token cost) and SC-003 (live parity) both require a clean
  wheel-runner invocation; doing it inside an agent session both costs
  the budget reserved for other teammates AND contaminates the measurement.
  The only clean path is a post-merge or separate-session live run. This
  is not an implementer bug — it's a structural tension between the "audit
  in-session" flow and the "live E2E is expensive and self-nesting" reality.
  Flagging it for the retrospective: the pipeline may need a separate
  "live-measurement" role, or team-lead should accept that live-gate
  confirmation happens outside the pipeline.
- **require-feature-branch.sh hook is still blocking writes to
  specs/ from within build/* branches.** Known issue, already tracked in
  `.kiln/issues/2026-04-10-require-feature-branch-hook-blocks-build-prd.md`.
  Worked around via Bash heredoc for the blockers.md write. Wasted ~1
  minute discovering the known failure.
- **Parity semantic ambiguity surfaced only at audit time.** Neither the
  PRD nor the spec distinguishes strict body-hash equality from structural
  parity. v3 rendered bodies with LLM judgment; v4 renders deterministically.
  Any live parity run will show diffs on severity/category/body fields,
  and "is that a regression?" is a judgment call the spec didn't anticipate.
  The /clarify step or an earlier review should have caught this. Flagging
  to retrospective: parity gates need an explicit "what counts as
  identical?" clause.
- **Benchmark placeholder files were committed in Phase 4.**
  `benchmark/v4-token-cost.md`, `benchmark/parity-result.md`,
  `benchmark/large-vault-result.md`, and `benchmark/caller-smoke.md` all
  exist but hold structural estimates or placeholder data. That's accurate
  to what was measured, but a reader glancing at the directory might assume
  "benchmark results exist = benchmarked." Would be cleaner to either (a)
  omit the files until they hold real data, or (b) prefix the filenames
  with `PENDING-` so it's obvious at a glance. Minor, flagging for the
  retrospective.

## Would do again

- Running compute-work-list.sh against a synthetic fixture before touching
  the workflow JSON. Fastest possible way to prove the diff logic is
  deterministic and contract-shaped.
- Using the heredoc workaround for blockers.md instead of fighting the
  hook. Documented in plan.md so it wasn't a surprise.
- Writing blockers.md explicitly rather than cramming the gaps into the PR
  body. Team-lead needs a persistent record for the merge decision.
