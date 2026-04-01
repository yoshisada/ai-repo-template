# Research: Kiln Polish

## R1: Current `/next` output structure

**Decision**: Append a "Suggested next" section after the existing Step 5 output format, before the report footer.

**Rationale**: The current output already has a well-defined format (Step 5 in SKILL.md) with priority-grouped recommendations. The suggested next line should appear after all recommendations but before the report path footer, making it the last thing the user reads before acting.

**Alternatives considered**:
- Prepending the suggestion at the top — rejected because the user needs context from the list to understand why a specific command is suggested.
- Replacing the list entirely — rejected because the full list serves users who want to review all options.

## R2: QA directory canonical structure

**Decision**: Five subdirectories: `tests/`, `results/`, `screenshots/`, `videos/`, `config/`

**Rationale**: Based on analysis of current QA skill/agent usage:
- `tests/` — Playwright test stubs (already used by `/qa-setup`)
- `results/` — consolidates reports (QA-REPORT.md, QA-PASS-REPORT.md, UX-REPORT.md, test-results.json) and the `latest/` convention
- `screenshots/` — screenshots from QA agents and UX evaluator (currently at `.kiln/qa/latest/screenshots/`)
- `videos/` — Playwright video recordings (already used by `/qa-setup`)
- `config/` — Playwright config, env templates, test matrix (currently at `.kiln/qa/` root)

**Alternatives considered**:
- `traces/` as a subdirectory — rejected; traces are testing artifacts that can go in `results/`
- `latest/` as a top-level subdirectory — rejected per PRD; symlink patterns add complexity without clear benefit
- `reports/` separate from `results/` — rejected; keeping all outputs together simplifies discovery

## R3: Backwards compatibility for QA path changes

**Decision**: QA skills create directories on-demand with `mkdir -p`. Existing files at old paths are not moved.

**Rationale**: Consumer projects may be mid-build when they upgrade. Moving files would break in-progress workflows. Skills should write to new canonical paths going forward, and create directories if missing.

**Alternatives considered**:
- Migration script to move files — rejected; too risky for mid-flight upgrades
- Dual-write to old and new paths — rejected; adds complexity for a transitional period

## R4: How to determine the "highest-priority" command

**Decision**: Take the first item from the priority-sorted recommendation list (Step 4 output). The existing classification and sorting logic already produces the correct ordering: critical > high > medium > low, then by recency within each level.

**Rationale**: No new prioritization logic is needed. The `/next` skill already does the hard work of classifying and sorting. The "Suggested next" feature simply surfaces the #1 item.

**Alternatives considered**:
- Weighted scoring algorithm — rejected; over-engineering for what is essentially "pick the first item"
- User-configurable priority — rejected; out of scope per PRD non-goals
