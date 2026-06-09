# Agent Friction Notes — audit-compliance

**Pipeline**: wheel-viewer-definition-quality (build-prd run, branch `build/wheel-viewer-definition-quality-20260509`)
**Role**: audit-compliance (final PRD compliance audit, post-impl + post-QA)
**Date**: 2026-05-09

Per FR-009 of the build-prd retrospective protocol, capturing what worked / what didn't / what to change for the next run.

## What worked

- **Hard blocker check before starting.** The spawn prompt mandated waiting until tasks #2–#5 all showed `completed`. I refused to start until that condition was met (sent two "audit blocked" / "still waiting" messages to team-lead). This kept the audit valid — findings are anchored to final-state code, not in-progress code that would have shifted underneath me.
- **Audit-midpoint handoff was substantive.** When team-lead relayed audit-midpoint's structural pass, the FR-6.4 traceability gap and the T027 deviation came through with enough context that I could verify them directly at final audit. The `lint-fixture-broken.json` non-issue (flat .json silently skipped by wheel-test-runner) was also resolved upstream so I didn't have to re-investigate.
- **Contract-driven verification was fast.** `contracts/interfaces.md` made spot-checking exported function shapes a single Read + diff exercise per module. All four `lib/*.ts` modules matched byte-for-byte; no chasing.
- **Tests authored well.** Every `*.test.ts` file in `viewer/src/lib/` had FR-numbered comments at the top of every `describe` block. SC-014 (lint coverage) was straightforward to verify against the rule reference table in spec.md. No stubs (`grep -F 'expect(true).toBe(true)'` zero matches).
- **Coverage gate was a clean run.** `npx vitest run --coverage` finished in <300ms. The earlier branch-coverage concern on `layout.ts` (77.17% per impl-data-layer's report) had been resolved by impl-graph's commit `f8e4f6b7` before I ran the gate — measured 86.17% live. No follow-up needed.

## What was rough

- **Screenshot path divergence between PRD and spec.** PRD says `docs/features/.../screenshots/`. spec.md line 192 says "committed under `specs/.../screenshots/` (mirrored in the PRD directory)". qa-engineer captured them at the spec path; the PRD-path mirror was missing. I did the mirror as part of audit cleanup (12-file copy — small, safe, deterministic), but earlier process clarity could have prevented this entirely. **Recommendation**: pick ONE canonical location in the spec template and have qa-engineer publish there; mirror via a build script if both paths are needed.
- **`specs/.../blockers.md` not used at all.** The spawn prompt told me to "re-read every blocker… check git log for resolved blockers… commit the updated blockers.md." But no `blockers.md` was ever created during implementation — every FR was implemented, no genuine blocker accrued. The audit prompt should make `blockers.md` truly conditional: "if it exists, reconcile; if not, do not create one." (I noted "0 open blockers" in §12 of the report instead of inventing a file.)
- **The F-6.4 part-3 ambiguity.** The spec language "the `localOverride` field's existing semantic… extends to: source shadows installed for direct-checkout authors actively editing" could be read two ways: (a) source workflows should have `localOverride: true` set in their data, OR (b) source workflows should be visually distinguishable so the user can tell which one shadows which. The implementation chose (b) — visual distinguishability via the `(source)` tag — and I judged that adequate because the load-bearing requirement is "BOTH render in the sidebar" (FR-6.4 first sentence), which is fully met. But future authors editing this code may be confused. **Recommendation**: tighten FR-6.4's second sentence to specify the visual-vs-data semantic explicitly.
- **`WorkflowDetail.tsx` is now a vestigial 33-LOC stub.** T027's deviation (lint banner + mode switch implemented in `app/page.tsx` instead) is acceptable per Article VI, but `WorkflowDetail.tsx` now barely earns its place as a separate file. **Recommendation**: either fold it into `page.tsx` or expand its responsibility back to the original spec. Not a blocker — just architectural drift to monitor.

## Observations for next run

1. **Make `blockers.md` truly opt-in.** Add a line to the audit-compliance spawn prompt: "If the implementation surfaced no blockers, do NOT create `blockers.md`. Document `0 open blockers` in your audit-compliance.md instead."
2. **Tighten the screenshot path contract.** Either drop the spec.md "mirrored in PRD directory" sentence, or have build-prd generate both paths automatically. Today's manual mirror works but is a recurring papercut.
3. **Tasks.md should explicitly cite EVERY FR in at least one task header.** FR-6.4 was implicit in T023 ("Source AND installed both visible") but not by ID. Audit-midpoint caught this; an explicit FR-cited-by-task gate during /tasks would have caught it earlier.
4. **The hand-rolled layered layout shipped well.** No new npm dep, 100% line coverage, 86.17% branch coverage, deterministic. The plan.md D-1 sketch was the right call vs reaching for dagre. Codify this preference: "for visualization-internal layout, prefer hand-rolled when <250 LOC + ≥80% achievable" — a kiln-roadmap or kiln-feedback item.

## Coordination notes

- audit-midpoint's structural pass was the right pre-flight gate. It caught the FR-6.4 traceability gap and the lint-fixture-location concern before I ran the full audit, which kept this final audit fast and focused.
- Two messages to team-lead before starting (initial blocker check + ack of impl-data-layer with layout.ts coverage concern) were the right cadence — visible-but-not-spammy. The third message (FR-6.4 noted from audit-midpoint handoff) was useful because it documented my checklist commitment.
- Final notification to audit-pr should carry the §13 verdict + recommendations explicitly. They have the smoke-test + PR creation work; my findings should make their job easier, not just a hand-off.
