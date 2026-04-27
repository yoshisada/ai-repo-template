---
name: 12-loop-and-workflow-design
status: planned
order: 12
# started: YYYY-MM-DD   # FR-020 — set when status → in-progress
# completed: YYYY-MM-DD # FR-020 — set when status → complete
---

<!--
FR-005 / PRD FR-005: phase frontmatter required keys = name, status, order.
FR-006 / PRD FR-006: body = short description + auto-maintained item list.
Contract: specs/structured-roadmap/contracts/interfaces.md §1.2.

Do NOT hand-edit the `## Items` section below — it is rewritten by
plugin-kiln/scripts/roadmap/update-phase-status.sh register <item-id>.
The description ABOVE `## Items` is author-owned.
-->

# 12-loop-and-workflow-design

Make the system's loops and workflows legible. Today wheel workflows live as JSON spread across local `workflows/` and many plugin install paths, and the documented feedback loops have a format defined but no rendered viewing surface. Without something to look at, "what runs when I invoke this command" and "what's the actual feedback loop here" are reverse-engineering exercises. Success looks like a single `/wheel:wheel-view` invocation rendering an HTML page that surfaces every available workflow with expandable steps (showing real prompts/scripts), plus — when kiln is present — the feedback-loop docs with their Mermaid diagrams alongside.

## Items

- 2026-04-25-feedback-loop-doc-format
- 2026-04-27-wheel-view-html-viewer
