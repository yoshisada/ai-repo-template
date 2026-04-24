---
step: create-issue
status: complete
issue_path: .kiln/issues/2026-04-24-retro-proposed-prompt-improvements-never-applied.md
issue_id: 2026-04-24-retro-proposed-prompt-improvements-never-applied
title: Retrospective-proposed prompt improvements (PI-1..PI-N) never get pulled back into the source tree
severity: medium
area: workflow
duplicate_found: false
---

Created new backlog issue at `.kiln/issues/2026-04-24-retro-proposed-prompt-improvements-never-applied.md`.

Duplicate check: no prior issue mentions "PI-", "retro-applied", or the PI lifecycle gap. Closest adjacent is the recently-filed O-1 skill-test-harness feedback (shipped as PR #151), which is a different concern.

Classification:
- severity: medium — not blocking individual pipelines, but growing backlog across every pipeline's retro output
- category: workflow — lifecycle gap between retro output and source-tree updates
- 3 fix vectors captured (standalone /kiln:kiln-pi-apply skill, distill --retros filter, short-term manual triage); recommendation favors short-term manual triage on stable PIs (PI-1 first) then a propose-don't-apply skill to close the lifecycle.
