# Spec Quality Checklist — Workflow Governance

**Applied to**: `specs/workflow-governance/spec.md`
**Standard**: kiln `/speckit.checklist` / `/kiln:kiln-checklist` baseline + constitutional gates.

## Coverage

- [X] Every PRD FR has a corresponding spec FR (Traceability table in spec.md).
- [X] Every spec FR references a source PRD FR.
- [X] Every PRD NFR has a spec NFR.
- [X] Every PRD Success Criterion has a spec SC (plus one additional: SC-006 grandfathering).
- [X] Every PRD "Non-Goal" is reflected in the spec's "Out of Scope" section.
- [X] Every PRD "Risk" is addressed in the spec's "Risks & Mitigations" section, either as a resolved Clarification or an accepted follow-on.

## Clarity

- [X] Each user story has a "Why this priority" justification.
- [X] Each user story has an "Independent Test" block.
- [X] Each user story has ≥ 3 Given/When/Then acceptance scenarios.
- [X] FR wording uses MUST / SHOULD per RFC 2119 conventions (MUST for mandates, SHOULD-level optional language avoided unless justified).
- [X] No ambiguous deferrals — every PRD open question resolved via explicit Clarification or pushed to Out of Scope.

## Testability

- [X] Every FR has at least one named test fixture in tasks.md.
- [X] Every SC has a validation anchor in tasks.md's "Success Criteria Validation" section.
- [X] Edge cases enumerated in the "Edge Cases" subsection of spec.md.
- [X] Performance assertions (NFR-001, NFR-002) have measurable thresholds.
- [X] Byte-preservation (NFR-003) has an explicit bytewise-diff assertion fixture.

## Constitutional compliance

- [X] **Article I (Spec-First)**: spec.md committed before any implementation edit.
- [X] **Article II (80% coverage)**: behavior-level fixture coverage per FR; no compiled code in plugin repo so line-coverage is N/A per the repo's established convention.
- [X] **Article III (PRD source of truth)**: no divergence from frozen PRD; Clarifications only resolve PRD-internal ambiguity without contradicting it.
- [X] **Article IV (Hooks)**: no new PreToolUse hooks; existing hook unchanged (FR-001/FR-002 shipped in 86e3585).
- [X] **Article V (E2E required)**: every new skill has a `/kiln:kiln-test` fixture exercising real skill invocation.
- [X] **Article VI (Small, focused)**: each phase is one bounded area; no shell script > 500 lines; each SKILL.md addition < 200 lines.
- [X] **Article VII (Interface Contracts)**: contracts/interfaces.md published before any parallel implementation starts.
- [X] **Article VIII (Incremental completion)**: tasks.md mandates per-phase commits and `[X]` marking immediately after task completion.

## Known exceptions / follow-ons

- `--since <date>` flag on `/kiln:kiln-pi-apply` (PRD R-3 follow-on) — not spec'd here.
- Grandfathered-PRD hygiene subcheck (PRD R-5 follow-on) — not spec'd here.
- Auto-rewrite of stale PI anchors (PRD R-4 follow-on) — deliberately excluded per Clarification 6.

All three are tracked as explicit Out-of-Scope items and are safe candidates for a future roadmap capture.
