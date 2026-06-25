---
run_id: <uuid>
prd: docs/features/<slug>/PRD.md
date: YYYY-MM-DD
verdict: pass | fail | warn
scenarios_run: <N>
scenarios_passed: <N>
fidelity_score: null | 0-10
---

## Test Context

<!-- Agent's reasoning for what it chose to test and why -->
Tested against: PRD `docs/features/<slug>/PRD.md`, spec FRs: FR-001, FR-002, FR-003
Design verify: false

## Scenarios

### SC-001 — <derived from FR-001>
- **Route**: /
- **Auth**: not required
- **Actions**: <prose description of what the agent did>
- **Assertions**: <prose description of what the agent checked>
- **Result**: pass | fail | warn
- **Notes**: <any unexpected behavior>

### SC-002 — <derived from FR-002>
- **Route**: /
- **Auth**: not required
- **Actions**: <prose description of what the agent did>
- **Assertions**: <prose description of what the agent checked>
- **Result**: pass | fail | warn
- **Notes**: <any unexpected behavior>

## Design Fidelity (if design_verify: true)

| Route | Reference mockup | Match | Notes |
|---|---|---|---|
| / | design/features/<slug>/mockup.html | pass | |

## Summary

<One paragraph: what was tested, what passed, what failed, anything surprising>
