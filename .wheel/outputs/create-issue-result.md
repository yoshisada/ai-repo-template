---
step: create-issue
status: success
issue_file: .kiln/issues/2026-04-24-wheel-workflow-speed-batching-commands.md
issue_id: 2026-04-24-wheel-workflow-speed-batching-commands
title: Investigate wheel workflow speed — consolidate multi-command agent steps into single bash scripts to reduce LLM↔tool round-trips
type: improvement
severity: medium
area: wheel
category: performance
---

## Step result

Created new backlog issue: `.kiln/issues/2026-04-24-wheel-workflow-speed-batching-commands.md`

**Classification**
- type: improvement
- severity: medium
- area: wheel
- category: performance

**Duplicate scan**
No existing issues covering wheel workflow performance or round-trip batching. Closest adjacency (`shelf-sync-efficiency` roadmap item) targets sync throughput, not wheel dispatch latency.

**User description (verbatim)**
> investigate how to make wheel workflows faster.  consider creating bash files for large strings of commands to run all at once for less roundrips.
