---
title: control — unmerged PRD should NOT archive
type: bug
status: prd-created
prd: docs/features/2026-04-10-unmerged/PRD.md
date: 2026-04-10
---

Control item. Its slug (`unmerged`) must NOT appear in `gh pr list --state merged`. Expected signal: `needs-review`, NOT in the bundled block.
