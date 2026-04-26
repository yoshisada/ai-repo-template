# Specifier — friction notes (escalation-audit)

**Agent**: specifier
**Pipeline**: `build/escalation-audit-20260426`
**Date**: 2026-04-26

## Workflow

Ran specify → plan → tasks back-to-back in one pass per the team-lead's prompt. PRD was already comprehensive (16 FRs, 5 NFRs, 7 SCs, 4 OQs, 4 Risks across 3 themes); the spec/plan/tasks artifacts mostly faithfully transcribe and structure those, with a few decisions resolved inline (see below).

## Decisions resolved inline

- **OQ-1 (auto-flip + phase file)** — Step 4b.5 does NOT re-run `update-phase-status.sh register`. Phase file's `## Items` list already includes shipped items per existing convention. Recorded in spec.md "Decisions Resolved".
- **OQ-2 (shutdown-nag location)** — main-session loop, not a dedicated agent. Matches verified pattern; minimizes spawn overhead.
- **OQ-3 (timestamp granularity)** — all sources normalized to ISO-8601 UTC before sort. Wheel `started_at` primary; git log `%aI`; logs filename → mtime fallback. Recorded as task T044 in tasks.md.
- **OQ-4 (concurrent-staging hazard)** — Themes A + B owned by `impl-themes-ab` exclusively; Theme C owned by `impl-theme-c`. Documented in spec.md "Concurrent-Staging Hazard" + plan.md + tasks.md "Implementer Assignment".

## Open ambiguities deliberately deferred

- **Step 4b.5 placement** — chose to insert AFTER Step 4b's archival commit and BEFORE Step 5 Retrospective (i.e., a new Step 4b.5 sub-section). This preserves the existing Step 4b's PR-#146 invariants intact and isolates the new auto-flip diagnostic line under a new prefix (`step4b-auto-flip:`) so the Step 4b grep regex (un-anchored at end-of-line) is unaffected. If the implementer later finds it more natural to embed the auto-flip INSIDE Step 4b's existing per-match loop, that's a refactor with the same external behavior — flag in agent-notes if attempted.
- **`update-item-state.sh --status` flag parsing** — left positional+flag mixing semantics to the implementer; contract §A.1 specifies the legal forms but doesn't dictate a specific getopts shape. Existing Bash style in the repo uses ad-hoc case loops; matching that idiom is fine.
- **`/loop` skill argument shape for shutdown-nag** — contract §B.1 specifies the `ScheduleWakeup` parameters but leaves the precise `loop` skill invocation phrasing (e.g., whether the team-lead writes the autonomous-loop sentinel inline, or invokes `/loop` skill text) to the implementer. The `<<autonomous-loop-dynamic>>` sentinel is the canonical form per the ScheduleWakeup tool description.

## NFR-001 baseline measurement

Did not measure live. The 5-second budget for ≤ 10 derived_from items is a generous file-I/O budget (one cached `gh pr view` + ≤ 10 atomic awk rewrites). Implementer task T070 records the observed wall-clock during Phase 8 polish; if > 5s a blocker is surfaced. Confidence is high that this trivially passes — flagged as a low-risk NFR.

## SC-006 substrate gap

SC-006 (post-merge manual `--check` run against the live 81-item roadmap) is substrate-blocked in-session per the B-PUBLISH-CACHE-LAG carve-out 2b. Plan.md's "Risks & Mitigations" section logs this; the implementer is expected to capture this in `specs/escalation-audit/blockers.md` during the Phase 8 polish. SC-006 is NOT a gate for this PR's merge.

## What confused me

- **PRD says "FR-005" twice** — once as Theme A's safety-net `--check` enhancement, once as the FR-005 anchor in `prd-derived-from-frontmatter`'s lineage. Resolved by treating spec FR-005 as scoped to THIS PRD's `--check` cross-reference; the older PRD's FR-005 is referenced via `read_derived_from()` reuse only.
- **Step 4b vs Step 4b.5 naming** — chose `Step 4b.5` for the auto-flip insertion to avoid disturbing the existing Step 4b's PR-#146 SMOKE.md invariants. Documented in tasks T011 + agent-notes above.
- **`/loop` integration test deferral (B-1)** — the wheel-hook-bound substrate gap means FR-010 verifies via direct text assertions on SKILL.md only. This is explicit in the spec + plan + contracts + tasks; the implementer should NOT attempt a live `/loop` integration test — that's a separate substrate work item.

## Hand-off summary

Artifacts produced:
- `specs/escalation-audit/spec.md` (5 user stories, 16 FRs, 5 NFRs, 7 SCs, decisions resolved inline)
- `specs/escalation-audit/plan.md` (Phase 0 research table; Phase 1 design + data shapes; structure decision; constitution check pass)
- `specs/escalation-audit/contracts/interfaces.md` (5 modules: A=auto-flip, B=shutdown-nag, C=escalation-audit + doctor, D=fixtures, E=reused)
- `specs/escalation-audit/tasks.md` (8 phases, T001..T072, owner-fixed per concurrent-staging hazard)
- `specs/escalation-audit/agent-notes/specifier.md` (this file)

Two implementers will be notified next. Phases 3/4/5 are sequential within `impl-themes-ab`. Phase 6/7 are sequential within `impl-theme-c`. The two implementer chains run in parallel.
