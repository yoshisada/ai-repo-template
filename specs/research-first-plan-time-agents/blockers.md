# Blockers — research-first-plan-time-agents

No blocking gaps identified at spec/plan/tasks time. Open follow-on items (non-blocking) are surfaced in `spec.md` §"Risks & Open Questions" and carried into `plan.md` "Resolution of Spec Open Questions".

## Documented follow-on items (NOT blockers)

These are flagged for post-merge work; they do not block this PR:

1. **R-002 — Quantitative judge reliability measurement** (spec §Risks): the three anti-drift controls catch worst-case failure modes but don't establish a quantitative reliability number. Follow-on roadmap item to be filed by the team-lead post-merge: "Judge reliability against known-outcome corpus".
2. **OQ-1 (deferred)** — Should the judge be allowed to abstain (`unsure`)? Resolved NO in v1 (FR-012). Re-open if first-real-use produces a genuinely-tied case.
3. **OQ-3 (NEW)** — Should the synthesizer be rate-limited across all fixtures (not just per-fixture)? Defer to first-real-use; bound is currently per-fixture only via FR-006.
4. **OQ-4 (NEW)** — Should the identical-input control verdict envelope be visually distinguished from regular fixtures in the research report? Defer; current decision is one combined "Judge verdicts" section listing the control row LAST with `[control]` annotation.
5. **Live-spawn validation queued for next session** — per CLAUDE.md Rule 5, the two new agents (with extended role-specific prose) cannot be live-spawn-validated in this session. The implementer's tasks.md uses mock-spawn tests throughout. Live-spawn validation is the auditor's first follow-on activity in Task #3.
6. **First-real-use synthesized-corpus PRD commits the first concrete `fixture-schema.md`** per plan.md Decision 5 + SC-001. This PRD documents the convention but does not commit a concrete schema — that's the SC-001-anchored follow-on.
