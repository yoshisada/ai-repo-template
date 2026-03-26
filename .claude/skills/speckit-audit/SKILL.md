---
name: "speckit-audit"
description: "Run a PRD compliance audit against the current implementation"
---

## PRD Compliance Audit

Audit the current implementation against the PRD and feature specs.

### Workflow

1. Read `docs/PRD.md` to understand the product requirements.
2. Read `.specify/memory/constitution.md` for governing principles.
3. Find all specs in `specs/*/spec.md`.
4. For each PRD functional requirement:
   - Check if a spec FR covers it
   - Check if implementation satisfies the spec FR
   - Grade as PASS / PARTIAL / FAIL
5. For each spec FR:
   - Check if a function references it
   - Check if a test validates its acceptance scenario
   - Grade as PASS / PARTIAL / FAIL
6. Check tech stack compliance (PRD vs actual).
7. Check success metrics achievability.
8. Identify gaps: PRD → spec, spec → implementation, implementation → tests.

### Output

Produce a structured report with:
- Overall compliance percentage
- Per-requirement PASS/PARTIAL/FAIL table
- Critical gaps (must fix)
- Partial gaps (should fix)
- Recommendations prioritized by severity
- Scope creep check (anything built that wasn't specified)

### Rules

- Be thorough — read actual source files, not just filenames
- Quote specific line numbers when citing gaps
- Distinguish between "not implemented" and "implemented differently than specified"
- Flag any PRD requirements that the spec intentionally diverges from
