# Auditor Friction Note — workflow-governance

**Author**: auditor-2 (replacement; original auditor stalled with no output)
**Date**: 2026-04-24

## What I found

- All 13 FRs, 5 NFRs, and 6 SCs verify clean against fixtures + smoke.
- All implementer phase commits (ea0320b → adf5a24) are present. Hook fixture (5 cases), roadmap-promote (4 fixtures), distill-gate (4 fixtures), and pi-apply (6 fixtures) all green.
- The existing `.kiln/logs/pi-apply-2026-04-24T14:04:50Z.md` self-test log validates the FR-011 schema shape on an empty backlog. Per discipline directive, I did not re-run pi-apply live.

## Friction

1. **Commit `a340652` attribution mismatch**. The commit message reads `docs(workflow-governance): complementary /plan enum-check follow-on` but the payload is 15 pi-apply files (impl-pi-apply's work). impl-governance ran `git add -A` during a phase commit and swept impl-pi-apply's staged work. Detecting this required `git show --stat` cross-referencing — the commit subject alone was misleading. **Recommendation for pipeline**: add a pre-commit guard (or agent-prompt instruction) that forbids `git add -A` across separate implementer scopes; prefer `git add <specific-paths>` with the implementer's scope glob.

2. **T042 manual smoke has no CI path**. The FR-013 integration (`/kiln:kiln-next` surfacing `/kiln:kiln-pi-apply` when ≥3 retros open) requires a live GitHub retro backlog. No fixture exists to simulate this end-to-end. I couldn't close T042 from a headless audit seat. **Recommendation**: either (a) add a fixture that stubs `gh issue list --label retrospective` with ≥3 entries and asserts `kiln-next`'s output contains `/kiln:kiln-pi-apply`, or (b) document T042 explicitly as a post-merge manual gate.

3. **Auditor brief pointed at `/audit` slash command**. The original auditor's prompt says "Run `/audit`" — but slash-command-driven audits compose poorly with the team-lead's explicit step-by-step directive (read PRD → check traceability → write report → smoke → reconcile). I skipped `/audit` and wrote the report directly from PRD+spec cross-reference, because the team-lead brief is more prescriptive than `/audit`'s generic flow. **Recommendation**: pick one. Either the auditor runs `/audit` and trusts its output, or the auditor runs a bespoke traceability-matrix pass and the brief shouldn't reference `/audit`.

4. **Replacement-auditor context reconstruction cost**. Picking up after a stalled original auditor required: re-reading the PRD (138 lines), spec (224 lines), tasks.md (176 lines), plus agent-notes from three other agents to understand context. ~600 lines before any audit work started. **Recommendation for pipeline**: when an agent is replaced, the replacement's brief could bundle a pre-computed "state snapshot" (tasks completed, commits landed, fixtures green, known anomalies) — the team-lead brief already did most of this, which is why this audit completed quickly.

5. **Fixture invocation asymmetry**. Some fixtures run directly via `bash plugin-kiln/tests/<name>/run.sh` (the roadmap/distill/hook ones). Others use the `/kiln:kiln-test` harness with `test.yaml` + `assertions.sh` (all pi-apply fixtures). The divergence means a quick audit sweep can't use a single shell loop to run every fixture. **Recommendation**: standardize on one invocation path, or document the two conventions explicitly in `plugin-kiln/tests/README.md`.

## What went smoothly

- Team-lead brief was thorough — clear paths, clear discipline, clear skip-if-already-done directives (pi-apply report). Cut audit time significantly.
- All implementer phase-commits followed the kiln "commit after each phase" norm, making the audit-side `git log` scannable.
- Spec's traceability matrix (spec.md §Traceability) made FR coverage verification near-mechanical.
- Blockers-exist-check path was graceful (no file → minimal blockers.md with reconciliation summary; no synthetic blockers fabricated).
