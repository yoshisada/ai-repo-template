---
id: 2026-04-24-wheel-workflow-speed-batching-commands
title: Investigate wheel workflow speed — consolidate multi-command agent steps into single bash scripts to reduce LLM↔tool round-trips
type: improvement
date: 2026-04-24
status: prd-created
severity: medium
area: wheel
category: performance
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-wheel/bin/activate.sh
  - plugin-wheel/hooks/post-tool-use.sh
  - plugin-kiln/workflows/kiln-report-issue.json
  - plugin-shelf/workflows
  - plugin-wheel/scripts
prd: docs/features/2026-04-24-wheel-as-runtime/PRD.md
---

## Summary

Wheel workflows are perceptibly slow. A core contributor is **LLM↔tool round-trip latency**: agent steps today often execute 3-10 small bash commands sequentially (e.g., a counter read, a jq parse, a path derivation, a subagent spawn, a result-file write) — each a separate round-trip back to the LLM before the next tool call can fire. Each round-trip carries full LLM latency (~seconds), so a step that does 5 small commands spends ~5× the baseline just waiting on the model.

The observation: many of these step-internal command sequences are **deterministic** (no LLM reasoning between steps once the step starts) and could be consolidated into a single `bash script.sh` invocation, turning N round-trips into 1.

## Where this bites today

The `dispatch-background-sync` step of `kiln:kiln-report-issue` is a clean example:
1. Bash call: `shelf-counter.sh read` → JSON output.
2. Bash call: `jq` parse the issue-note result file.
3. Agent tool call: spawn background sub-agent.
4. Write call: emit `dispatch-background-sync.txt`.

Steps 1, 2, and 4 are pure-deterministic — no LLM reasoning needed between them. A single wrapper script `dispatch-background-sync.sh` could read counter + parse JSON + emit the output file in one bash round-trip, leaving only the Agent spawn as a separate tool call.

Scaling that pattern across every multi-command agent-step would likely cut wheel workflow elapsed time noticeably, without changing workflow semantics.

## Proposed investigation

- **Audit**: walk every `"type": "agent"` step across shipped workflows (`plugin-kiln/workflows/`, `plugin-shelf/workflows/`, `plugin-wheel/workflows/`, `plugin-clay/workflows/`, `plugin-trim/workflows/`) and categorize by how many internal bash commands they currently require. Candidates for batching are steps with 3+ sequential deterministic commands.
- **Measure baseline**: add timing to a representative workflow run (`/kiln:kiln-report-issue` or `/wheel:wheel-test`) — record per-round-trip latency vs per-script latency.
- **Prototype**: pick one high-leverage step (e.g., `dispatch-background-sync`), write a single consolidating bash script that lives alongside the existing `plugin-*/scripts/` helpers, measure the elapsed-time delta.
- **Generalize**: if the prototype shows a real win, establish a convention — step-internal deterministic command sequences → `plugin-*/scripts/step-<stepname>.sh` — and port other steps where it makes sense.

## Trade-offs to consider

- **Debuggability**: a consolidated script failure surfaces as one tool-call error instead of step-by-step progress in the transcript. Mitigation: scripts should `set -e`, prefix each internal action with a log line, and emit structured success/failure JSON rather than relying on bash exit codes alone.
- **Readability**: workflow JSON becomes terser but hides more detail in external scripts. Mitigation: per-step scripts are short and single-purpose; the workflow JSON step description names what the script does.
- **Not every step batches**: steps that do need LLM reasoning mid-execution (e.g., "compose a suggestion based on repo state, then act on it") can't be flattened. Only target steps that are deterministic after kickoff.

## Other performance candidates to investigate alongside

- Whether hook dispatch itself (post-tool-use.sh latency) is contributing — measure from a cold-start workflow.
- Whether the foreground path waits on anything it could parallelize (e.g., the counter read in `dispatch-background-sync` happens before the agent spawn, but they could conceivably overlap).
- Whether child-workflow activation (`shelf:shelf-write-issue-note` invocation) has its own re-validation overhead that could be trimmed.
- Whether `WORKFLOW_PLUGIN_DIR` resolution inside scripts does disk scans on every call that could be memoized per-workflow-invocation.

## Proposed acceptance

- An audit document at `.kiln/research/` (or similar) classifying every agent-step by batchability, with a recommended target set.
- At least one high-leverage step consolidated into a `plugin-*/scripts/step-<name>.sh` wrapper, with measured before/after elapsed times demonstrating the reduction in wheel workflow latency.
- A lightweight convention doc in wheel's README or this repo's CLAUDE.md explaining when to batch step-internal commands into a script vs. leaving them as individual agent bash calls.
- Existing workflow behavior preserved — batching is a perf refactor, not a semantic change.

## Relation to other issues

- Composes with `2026-04-24-workflow-plugin-dir-not-exported-to-bg-subagents` — the proposed fix shape (option A: wheel exports `WORKFLOW_PLUGIN_DIR` globally) would make step-wrapper scripts easier to write because they could rely on the env var uniformly.
- Indirectly supports the vision's "install must not be clunky" commitment — slow background feedback during onboarding is a form of clunkiness even when nothing's broken.

## Pipeline guidance

Medium severity — not a correctness bug, but a perceptible UX drag that gets worse as workflows accumulate more steps. Investigation-first: the audit output determines whether this is a cheap refactor (3-5 high-leverage steps) or a larger cross-workflow pattern that wants a more principled solution. Avoid committing to a specific fix shape before measuring.
