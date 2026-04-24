---
agent: audit-smoke-pr
feature: coach-driven-capture-ergonomics
recorded_at: 2026-04-24
---

# Friction note — audit-smoke-pr

## Worked well

- **`audit-quality`'s compliance-report.md was the single-best hand-off artifact I received.** It told me exactly which tests to re-run standalone, which were harness-driven (and therefore out of smoke scope), and which specific NFR check the team-lead had called out. I used it as a to-do list. Every other agent hand-off this pipeline should aspire to this.
- **Tests that can be re-run standalone on the host shell.** I was able to independently re-verify 11 / 11 without firing up the kiln-test harness. That kept smoke latency low enough to actually run the full suite rather than sampling. All 8 standalone behavioural tests + 3 tripwires passed on my invocation.
- **Reader completed in 0.22 s on the live kiln repo (45 PRDs, 50 items)** — well under the 2 s NFR-001 budget. Byte-identical diff was trivial to verify. The shape of this feature (deterministic helper scripts + SKILL.md consumers) made smoke easy; the team should prefer this shape where possible.

## Friction

- **No standalone-runnable behavioural test for the modified SKILL.md bodies themselves.** `roadmap-coached-interview-*` tests are 100 % static SKILL.md grep tripwires. `audit-quality` flagged this as a follow-on; I confirm the friction: I can't prove at runtime (without spawning `claude --print` children) that the interview actually renders orientation + coached questions + accept-all. I relied on tripwires + `audit-quality`'s acknowledgement of Spec Clarification #5 (tone is a manual-review gate). This is a known follow-on — wire up the existing `test.yaml` fixtures in those test dirs once `/kiln:kiln-test` supports interactive stdin piping.
- **Attribution-fuzzy commit `216169c` (already flagged by `impl-vision-audit`'s addendum).** The three `plugin-kiln/scripts/distill/*.sh` files were committed under `impl-context-roadmap`'s Phase 2 commit rather than `impl-distill-multi`'s Phase 5 commit — a concurrent-working-tree race. Code content is correct; attribution in `git log -- plugin-kiln/scripts/distill/` is misleading. Not a compliance gap; retro item for `wheel` team-primitive hygiene.
- **Nine harness-driven tests not exercised in this smoke.** `roadmap-vision-*` (5) + `claude-audit-*` (4) require a `/kiln:kiln-test` sweep that spawns `claude --print` children. Running those inside a pipeline agent context would have consumed multi-minutes of budget and is brittle (child-process lifecycle + stdin is finicky). I deferred the sweep to Phase 6 polish T057 (first post-merge `/kiln:kiln-test plugin-kiln` run). Flagging as residual risk: if any of those 9 regress, smoke won't catch it. Mitigation: `audit-quality` hand-inspected each for real assertions and found them substantive.
- **Phase 6 polish tasks T053 / T055 / T056 / T057 unchecked at PR time.** T054 (CLAUDE.md Recent Changes) I picked up before the PR because it was trivial and hygiene-critical. The rest are non-blocking and named out in PR body + `smoke-report.md` § Known-remaining polish.
- **Wheel artifacts untracked at PR time.** `.wheel/history/success/...json` and `.wheel/state_*.json` appeared in `git status` as untracked. Per `feedback_wheel_trust_hooks.md` in memory ("Never manually dispatch embedded workflows or archive state files; let the hook system handle it"), I did not touch them. Same for `.kiln/mistakes/` and new `.kiln/roadmap/items/*.md` / `.kiln/roadmap/phases/90-queued.md` — these are out-of-scope user artifacts that arose during the run but belong on a separate commit / branch if the user wants them tracked.

## Suggestions for the retrospective

1. **Tests that run without the harness are gold.** Future spec plans should target "can this test run under `bash run.sh` directly?" as a first-class design goal, with harness-driven tests as a fallback for genuinely-must-spawn-claude scenarios.
2. **Provide a "smoke cheat-sheet" in compliance-report.md going forward.** The list of "tests I can run standalone" + "tests that are harness-only" + "team-lead's specific ask" was exactly the shape `audit-smoke-pr` needed. Formalise it in the audit-quality agent prompt.
3. **Commit-attribution race across concurrent implementers should be caught at the wheel layer, not papered over in retros.** File a structured roadmap critique after this PR merges.

## Task output

- Ran smoke suite: 11 standalone tests green, reader perf 0.22 s on live repo, byte-identical determinism confirmed, NFR-003 determinism test green.
- Wrote `specs/coach-driven-capture-ergonomics/smoke-report.md` (verdict PASS).
- Added T054 CLAUDE.md `Recent Changes` entry.
- Created PR with `build-prd` label (URL in team-lead hand-off message).
