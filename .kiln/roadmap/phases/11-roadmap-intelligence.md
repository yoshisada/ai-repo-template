---
name: 11-roadmap-intelligence
status: planned
order: 11
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

# 11-roadmap-intelligence

Make `/kiln:kiln-roadmap` reason about its own queues. Today the skill captures one item at a time but has no model for the queue surfaces (`90-queued`, `89-brainstorming`) it produces, no priority rule for ranking next-phase candidates across capture surfaces, and no planning verb that proposes coherent phase contents from open backlog. Success looks like a single invocation that, given current backlog, produces a ranked next-phase candidate list — issues first, feedback next, queued items third, brainstorming items last — with the maintainer reviewing rather than triaging.

## Items

- 2026-04-24-roadmap-coaching-with-insight
- 2026-04-24-roadmap-planning-mode
- 2026-04-27-kiln-roadmap-queued-brainstorm-states
- 2026-04-27-roadmap-priority-ranked-next-phase
