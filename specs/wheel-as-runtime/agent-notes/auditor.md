# Auditor friction note — wheel-as-runtime

**Date**: 2026-04-24
**Agent**: auditor
**Task**: #6 — Audit + smoke + create PR

## What was confusing / where I got stuck

- **Phase 7 polish task ownership**: tasks.md tags T101 + T102 to `impl-wheel-fixes` but the `impl-wheel-fixes` track concluded with all FR-shipped tasks before Phase 7 ran. T101 (CLAUDE.md "Recent Changes" entry) targets a section that has been refactored away in a sibling branch (the file now has a "Looking up recent changes" pointer instead of a changelog tail). T102 (Active Technologies entry + trim per `keep_last_n=5`) was actionable — I added the entry as part of audit finalization rather than punting it back to the implementer track. **Friction**: Phase 7 polish should land WITH the implementer's commits, not in a trailing "auditor cleans up" hand-off. Either tasks.md needs a hard "implementer cannot mark its phase complete until polish lands too" gate, or Phase 7 should belong to the auditor by design (and tasks.md should say so).

- **Quickstart vs blockers reconciliation**: spec.md called for `blockers.md` if any unfixable gap surfaced; the implementers shipped without creating one (no blockers found). T104 in tasks.md says "auditor runs quickstart end-to-end; any unfixable gap is documented in blockers.md." I ran the quickstart and found no unfixable gaps, so blockers.md is intentionally absent. **Friction**: tasks.md should say "blockers.md MAY be absent if zero unfixable gaps exist" rather than implying it's always created — auditors shouldn't have to re-derive that from context.

- **Smoke side effects**: running quickstart Step 7 (the batched wrapper) writes to `.shelf-config` (counter increment) and creates `.kiln/logs/report-issue-bg-<today>.md`. I had to revert these manually. **Friction**: smoke tests on side-effect-producing scripts should default to a tmp working dir, or the quickstart should explicitly note the side effects + a one-line revert recipe.

- **Architectural seams flagged by team-lead at audit-start time**: two cross-track seams were surfaced verbally by team-lead (orchestrator-integration follow-on for Themes A+B; cross-plugin script resolution gap in Theme E). Neither shows up in tasks.md, blockers.md, or the agent-notes I read. They're real but landed as "documented for distill, not blocking this PRD" — the PR body flags them. **Friction**: cross-track architectural seams discovered mid-pipeline need a durable home (an explicit "follow-ons" section in tasks.md or a new file like `specs/<feature>/follow-ons.md`) rather than living only in orchestrator chat.

## What worked well

- **Independent test runs**: every theme shipped its tests under `plugin-wheel/tests/<test>/` or `plugin-shelf/tests/<test>/` with a `run.sh` that exits 0/1 cleanly. I ran 10 wheel tests + 2 shelf step-wrapper tests + the kiln-fix-resolver-spawn fixture in three Bash invocations and got pass/fail verdicts in seconds. No flakiness, no environment surprises. NFR-1's "every FR ships a test" + the auditor's "I can verify it" loop closed cleanly.

- **Loud-failure invariants paid off immediately**: the resolver loud-fails when `WORKFLOW_PLUGIN_DIR` is unset AND the relative input doesn't resolve; the model resolver loud-fails on bogus input; the FR-D1 tripwire fails-loud if context.sh's Runtime Environment block is removed. As an auditor I could verify the silent-failure-shape was actually closed without having to read every test in detail — the invariants are visible at the contract level.

- **CI wiring + SC-007 grep canary**: `.github/workflows/wheel-tests.yml` runs every Theme C+D test plus the `git grep -F 'WORKFLOW_PLUGIN_DIR was unset'` canary on every PR. The canary is the right shape — a regression's *fingerprint*, not its cause. Future regressions can't ship green by accident.

## What could be improved

1. **Implementer-side Phase 7 gate**: a tasks.md convention where each track's phase complete checkbox cannot be marked until that track's Phase 7 polish tasks are done. This avoids "auditor adopts polish tasks" hand-off.

2. **`follow-ons.md` as a first-class artifact**: a `specs/<feature>/follow-ons.md` scaffold with the same shape as `blockers.md` would give cross-track architectural seams a durable home. Today they live only in team-lead messages and PR bodies, which decay quickly.

3. **Quickstart side-effect annotations**: every quickstart step that produces side effects (file writes, counter increments, log lines) should say so, with a tmp-dir incantation or a revert recipe. Auditor smoke tests should default to non-mutating runs.

4. **Audit-start "smoke before final" pre-check**: the Implementation Completeness Check (TaskList + tasks.md scan) caught the right things, but a 30-second run-the-tests pre-check before reading the spec/contracts would have validated the implementers' "tests pass" claim earlier — I caught it cleanly here, but if the suite were broken that would have been a long deferred discovery.
