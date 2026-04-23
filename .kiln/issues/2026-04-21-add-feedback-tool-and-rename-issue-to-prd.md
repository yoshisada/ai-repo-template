---
id: 2026-04-21-add-feedback-tool-and-rename-issue-to-prd
title: Add feedback capture tool and rename issue-to-prd to distill both issues and feedback
category: enhancement
priority: high
status: prd-created
prd: docs/features/2026-04-22-kiln-capture-fix-polish/PRD.md
created: 2026-04-21
repo: https://github.com/yoshisada/ai-repo-template
---

## Description

Add a dedicated feedback tool (`/kiln:kiln-feedback` or similar) for capturing what is wrong with the core product or mission. This is distinct from `/kiln:kiln-report-issue` which captures bugs and friction — feedback targets fundamental product direction and strategic concerns.

## Proposed Changes

1. **New feedback capture skill** — A `/kiln:kiln-feedback` command that writes entries to `.kiln/feedback/` (or a new designated directory). Feedback entries should capture:
   - What is wrong with the core product or mission
   - Suggested direction or correction
   - Priority/severity from a product perspective

2. **Rename `/kiln:kiln-issue-to-prd`** — The current skill only distills issues into PRDs. It should be renamed to something like `/kiln:kiln-distill` or `/kiln:kiln-backlog-to-prd` that reflects its expanded scope of consuming both issues and feedback.

3. **Feedback weighted higher than issues** — When the renamed skill distills items into a PRD, feedback entries should be weighted higher than issues because they highlight core product changes rather than incremental fixes. This means:
   - Feedback items should appear first or be prioritized in the PRD
   - The PRD narrative should be shaped around feedback themes before addressing issue-level fixes
   - Feedback can override or deprioritize issues that conflict with the product direction

## Rationale

Issues capture what's broken or friction-heavy. Feedback captures what's fundamentally misaligned with the product vision. Both feed into PRDs, but feedback should drive the strategic direction while issues inform tactical fixes.
