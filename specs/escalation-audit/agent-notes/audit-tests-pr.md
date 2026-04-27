# Friction Note — audit-tests-pr

**Phase**: Audit tests + create PR
**Branch**: `build/escalation-audit-20260426`
**Date**: 2026-04-26

## What this agent did

1. Verified test quality on all four PRD-listed fixtures: each fixture extracts a live `bash` block from the shipped SKILL.md / scripts and runs it inside a stubbed `$TMP` scaffold (no re-implementations, real assertions).
2. Re-ran every fixture from a fresh shell at HEAD `9320bd3c` — 53/53 assertions PASS. Per-fixture verdict:
   - `plugin-kiln/tests/build-prd-auto-flip-on-merge/run.sh` → **27/27 PASS** (final line `PASS`).
   - `plugin-kiln/tests/roadmap-check-merged-pr-drift-detection/run.sh` → **9/9 PASS** (final line `PASS`).
   - `plugin-kiln/tests/build-prd-shutdown-nag-loop/run.sh` → **12/12 PASS** (final line `PASS`).
   - `plugin-kiln/tests/escalation-audit-inventory-shape/run.sh` → **5/5 PASS** (final line `PASS: 5/5 assertions`).
3. Reconciled `blockers.md` — already authoritative (SC-006 + FR-010 documented; neither gates merge). No new blockers found.
4. Committed audit-compliance working-tree handoff (T027 `[X]` flip + audit-compliance friction note) on top of the existing branch.
5. Pushed branch + opened PR with `build-prd` label.
6. Updated task #5 → completed; messaged team-lead with PR URL.

## Test-quality observations

- All four fixtures use the **extract-and-run** pattern: `awk` carves the bash fence(s) out of the shipped SKILL.md / scripts, the fixture writes a runner that injects PATH-prefix `gh`/`git` stubs, and assertions grep on the actual output. This is the strongest substrate available without a wheel-hook-bound runtime — the test exercises the SHIPPED skill body, not a parallel re-implementation, so SKILL.md edits that break the contract surface immediately.
- Stub design is uniform across fixtures: `gh`-stub returns deterministic JSON for the specific `pr view --json state,mergedAt` / `pr list --state merged --head <branch>` invocations the contract uses; `git`-stub overrides only `log` + `for-each-ref` and passes through unknown subcommands to system git. NFR-002 (no live network) is enforced.
- The shutdown-nag fixture is text-grep-only (B-1 substrate carve-out); this is documented in the fixture header and in `blockers.md`. Honest contract-vs-runtime split.

## Substrate friction (relayed from impl-theme-c + audit-compliance)

- The /kiln:kiln-test SKILL.md advertises a "run.sh-only" path that wheel-test-runner.sh does not yet implement (the harness silently bails when fixtures lack `test.yaml`). Direct `bash` invocation IS the canonical evidence here, consistent with the team-lead's earlier guidance during this build. Future: either (a) implement run.sh-only discovery in wheel-test-runner.sh, or (b) update SKILL.md to acknowledge the harness gap. This is a follow-on PRD candidate, not a blocker for this build.

## PR creation friction

None notable. `gh pr create --label build-prd` worked first try. Push was clean (8 commits ahead of `main`). Branch tracks origin.

## Blockers status (final)

- **SC-006** — substrate-blocked, deferred to post-merge maintainer step. `blockers.md` documents the manual checkout + `--check` invocation. Does NOT gate merge.
- **FR-010** — V1 via text assertions; full `/loop` integration test deferred until wheel-hook-bound substrate ships. Does NOT gate merge.

Both blockers explicitly carved out by the PRD; both reflected in the PR description.
