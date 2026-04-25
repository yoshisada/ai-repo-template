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
  each sample is expensive. Took a narrow timing harness that shells the sub-agent
  prompt's bash chain directly vs. the new wrapper — see below for results.

### 2026-04-24 — Wrapper authored + tested + standalone timing (T091, T095, T096, T093-partial, T094-partial)

- T091: `plugin-shelf/scripts/step-dispatch-background-sync.sh` authored. Uses
  `SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` instead of
  `${WORKFLOW_PLUGIN_DIR}` for sibling-script resolution — more portable than the literal
  contract wording, still CC-2 compliant (no repo-relative paths). Documented the deviation
  in the convention-doc section.
- T096: 15-assertion test suite at `plugin-shelf/tests/step-dispatch-background-sync-wrapper/run.sh`.
  Covers contract §6 I-B1..I-B3 explicitly; tests happy path, failing-action identification,
  and set-e/set-u/pipefail preamble. All green locally.
- T095: Convention section appended to `plugin-wheel/README.md` with explicit rules
  (when to batch, when to leave, debuggability trade-off, required shape).
- T093/T094 preliminary bash-layer measurement: **NEGATIVE RESULT at bash-orchestration
  layer** (after is ~7ms slower than before, within noise). This is R-005 territory — the
  PRD's round-trip-cost hypothesis is about LLM tool-call round-trips (seconds), not bash
  process-startup (milliseconds), and pure-bash timing can't measure the former. Documented
  honestly in the audit doc's "Result" section per T094a.
- FR-E shipped scope is now: audit + wrapper + convention doc + honest negative at bash
  layer + integration-layer measurement flagged as blocked on Theme D.

### Dependencies still open

- T092 (update `plugin-kiln/workflows/kiln-report-issue.json` to invoke the wrapper
  instead of embedding the 3-call chain in the sub-agent prompt): will land AFTER
  Theme D T076/T077 ships `WORKFLOW_PLUGIN_DIR` parity so the workflow actually
  activates under consumer-install. The wrapper is ready; the workflow-JSON change
  is a 20-line diff that I'll make the moment Theme D signals.
- Integration-layer timing (real LLM round-trip): same dependency. I will offer to
  extend T093/T094 with one more sample set once Theme D is green — but per R-005,
  the audit already ships with a negative-result-documented shape that doesn't
  require the positive claim.
