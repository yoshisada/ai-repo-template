# impl-themeE-batching friction notes

**Track**: Theme E — step-internal command batching audit + prototype (FR-E1..FR-E4)
**Branch**: `build/wheel-as-runtime-20260424`
**Owner**: impl-themeE-batching

## Pipeline-contract FR-009 note

This file is written during/after work per the pipeline contract. Retrospective reads this
instead of polling the live agent.

## Running log

### 2026-04-24 — Audit kickoff (T090)

- Enumerated 35 `"type": "agent"` steps across 18 workflow JSON files in 5 plugin dirs.
- Heuristic pass (approx bash-call count via fenced-block parsing) surfaced one genuine multi-call
  deterministic sequence — `plugin-kiln/workflows/kiln-report-issue.json :: dispatch-background-sync`.
  Matches the PRD-documented candidate.
- Everything else is either single-bash-call (check-existing-issues, resolve-vault-path) or
  non-bash-orchestration (MCP writes, obsidian applies, file generation) — batching is a no-op
  or actively harmful there (fenced blocks are JSON/markdown templates, not bash).
- The high-leverage target is actually the **background sub-agent** launched by
  `dispatch-background-sync`, not the foreground step. The foreground has only 2 bash calls
  (counter read + issue-file JSON parse) and the gain from collapsing those is tiny.
  The background sub-agent makes 3 bash calls in sequence (counter increment, log append,
  optional shelf-sync branch) — that's the meaningful batching target.

## Open friction

- Auto-parsing "approx bash calls per step" from free-form `instruction` prose is noisy. The
  real count only becomes clear when you hand-inspect each step's instruction. A follow-on
  improvement would be first-class workflow-JSON schema for `internal_commands: [...]` so
  an audit like this is a `jq` one-liner, not a Python heuristic.
- No existing fixture exercises `dispatch-background-sync` in isolation. T093/T094 measurement
  needs a repeatable harness — running the full `/kiln:kiln-report-issue` workflow end-to-end
  each sample is expensive. Considering a narrow timing harness that shells the sub-agent
  prompt's bash chain directly vs. the new wrapper.
