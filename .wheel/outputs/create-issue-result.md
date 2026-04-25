# create-issue result

issue_path: .kiln/issues/2026-04-24-shelf-write-roadmap-note-needs-batching.md
duplicate_check: no exact duplicate found
related_issues:
  - .kiln/issues/2026-04-24-kiln-report-issue-workflow-cant-batch.md (sibling — kiln-report-issue workflow needs batching)
  - .kiln/issues/2026-04-24-wheel-workflow-speed-batching-commands.md (related — intra-step command batching, orthogonal scope)

classification:
  type: improvement
  area: shelf
  category: ergonomics
  severity: medium

summary: |
  shelf-write-roadmap-note dispatches one note per invocation — no list/directory mode.
  Capture flows producing many files at once (e.g. /kiln:kiln-roadmap phase + N items,
  multi-theme /kiln:kiln-distill, legacy migration) skip the mirror entirely, defeating
  the FR-030 contract. Proposal: accept ROADMAP_INPUT_DIR / ROADMAP_INPUT_LIST in
  parse-roadmap-input.sh, loop inside one wheel invocation, emit per-file result array.
