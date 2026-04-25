---
derived_from:
  - .kiln/issues/2026-04-25-typed-inputs-outputs-live-smoke-verified.md
distilled_date: 2026-04-25
theme: wheel-typed-schema-locality
---
# Feature PRD: Wheel Typed-Schema Locality (Fail-Fast + Surface-the-Contract)

**Date**: 2026-04-25
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)
**Builds on**: PR #166 (typed `inputs:` + `output_schema:` + `{{VAR}}` substitution). Does not block — this PRD ships independently after #166 has stabilized in real workflow runs.

## Parent Product

This is the **kiln** Claude Code plugin ecosystem (`@yoshisada/kiln` + sibling plugins `wheel`, `shelf`, `clay`, `trim`). Wheel is the runtime that other plugins compose workflows on top of. PR #166 added typed step inputs/outputs to wheel — agent steps now declare `inputs:` and `output_schema:` and the runtime hydrates resolved values into the agent's prompt. This PRD harvests the next layer of correctness/UX wins from that substrate.

## Feature Overview

Two tightly-coupled changes to the wheel Stop-hook that close round-trip waste introduced — but not eliminated — by the typed-schema work in PR #166:

- **Theme H1 — Fail fast on output_schema violation**: when an agent writes its `output_file`, the Stop-hook validates against the declared `output_schema` IN THE SAME TURN. On mismatch, it returns a structured error naming expected vs. actual keys; the agent re-writes without leaving the turn. Today the mismatch only surfaces at the NEXT step's input-resolution tick — one full round-trip later.
- **Theme H2 — Surface the contract in Stop-hook feedback**: the Stop-hook feedback for an agent step includes the resolved `## Resolved Inputs` block, the agent step's `instruction:` (post-`{{VAR}}` substitution), and the declared `output_schema:` verbatim. The hook already has all three (it just templated them). Surfacing them removes the agent's need to read upstream output files or guess key names.

After this PRD ships, the agent step receives the full contract on first dispatch and any mismatch fails loud in-turn — no archaeology, no guessed-wrong retries.

## Problem / Motivation

This PRD's headline evidence is the smoke test that filed `.kiln/issues/2026-04-25-typed-inputs-outputs-live-smoke-verified.md`. Direct observations from that run:

- The `obsidian-write` step's Stop-hook feedback was just `"Step 'obsidian-write' is in progress. Write your output to: .wheel/outputs/shelf-write-issue-note-result.json"`. The agent had no way to know the required output shape without either reading the workflow JSON (forbidden by skill rules) or reading prior step outputs to infer the contract.
- The agent guessed key names (`backlog_path` instead of `issue_file`) and wrote a JSON envelope that satisfied no schema.
- The mismatch was only caught one round-trip later when `dispatch-background-sync`'s `inputs:` resolver tried to extract `$.issue_file` and failed: `"Workflow 'kiln-report-issue' step 'dispatch-background-sync' input 'ISSUE_FILE' resolves direct path '$.issue_file' against step 'write-issue-note' output but path did not match."`
- Fixing the output JSON consumed an entire extra agent turn whose only purpose was to rename one key.

That single avoidable round trip is the canonical shape of friction this PRD targets. Multiplied across all the steps in a real workflow run, it adds up. The same shape recurs whenever an LLM agent has to guess at a contract the runtime already knows.

The lesson from PR #166's pipeline applies directly: **the typed schema is the contract** — the runtime should both surface it forward (so agents follow it) and validate it backward (so violations fail loud at source). PR #166 only did half of the second half (next-step validation). This PRD closes the loop.

## Goals

- **Fail loud at source.** Output-schema violations surface in the same turn as the bad write, with structured diagnostics naming the expected vs. actual keys. Saves one round-trip per mismatch.
- **Make the contract visible to the agent.** Stop-hook feedback for an agent step carries the resolved-inputs block, the post-substitution instruction, and the output_schema. No need for the agent to read the workflow JSON or upstream output files to figure out what to write.
- **Preserve byte-identical back-compat.** Workflows without `inputs:` or `output_schema:` see Stop-hook feedback identical to today. Same shape rule as PR #166 NFR-G-3.
- **Bound the perf overhead.** Hook-tick adds at most 50ms per agent step for validation + instruction surfacing combined. Measured against the post-PR-#166 baseline.

## Non-Goals (v1)

- **Not** a new step type. `command` already covers deterministic local work; the conversation that produced this PRD also retired the `compute` step-type proposal as redundant.
- **Not** a generalized "validate every output" mechanism. v1 only validates outputs whose owning step declares `output_schema:`. Steps without a schema are exempt (back-compat).
- **Not** a redesign of how the Stop-hook returns feedback to Claude Code. v1 enriches the existing string body; the wire shape is unchanged.
- **Not** a migration audit of existing agent steps to use typed schemas. That's a follow-on PRD (the "audit-and-migrate" recommendation from this PRD's seed conversation) — separate scope, separate work, separate PR.
- **Not** changing what counts as a valid output_schema. The grammar shipped in PR #166 stands.

## Target Users

Inherited from the parent product:

- **Plugin authors** writing wheel workflow JSON. They get loud, in-turn failure when an agent step's output deviates from its declared `output_schema`. No more "test the workflow end-to-end and discover the schema mismatch three steps downstream."
- **The LLM agent itself** (the unusual second user). It receives the full step contract — resolved inputs, hydrated instruction, output schema — in the Stop-hook feedback, eliminating archaeology turns.
- **Plugin consumers** running workflows like `/kiln:kiln-report-issue`, `/kiln:kiln-mistake`. They see fewer "agent guessed wrong, runtime corrected, retried" turns. Lower per-invocation latency and cost.

## Core User Stories

- **As a plugin author**, I want a schema mismatch in my agent step's output to fail loud in the SAME turn the agent wrote the bad output, so I see the diagnostic before the workflow advances and corrupts downstream state.
- **As an LLM agent dispatched by a wheel workflow**, I want the Stop-hook feedback to include the resolved-inputs block, my instruction text, and my output_schema, so I don't have to read the workflow JSON or guess at the contract.
- **As a plugin consumer**, I want my second `/kiln:kiln-report-issue` invocation in a session to require the same number of round-trips as my first — schema-mismatch retries should drop to zero once the substrate is fixed.

## Functional Requirements

### Theme H1 — Fail fast on output_schema violation

- **FR-H1-1**: When the Stop-hook detects that an agent step's `output_file` was just written, it MUST run `workflow_validate_inputs_outputs` (or the dedicated output-side validator from PR #166) against the declared `output_schema:` BEFORE returning to the agent.
- **FR-H1-2**: On validation failure, the Stop-hook MUST return a structured, multi-line error in the feedback body that names: (a) the expected keys per `output_schema:`, (b) the actual keys present in the written file, and (c) the diff (missing keys + unexpected keys). Example shape:
  ```
  Output schema violation in step 'obsidian-write'.
    Expected keys (from output_schema): issue_file, obsidian_path
    Actual keys in .wheel/outputs/shelf-write-issue-note-result.json: action, backlog_path, obsidian_path, slug, success, errors
    Missing: issue_file
    Unexpected: action, backlog_path, slug, success, errors
  Re-write the file with the expected keys and try again.
  ```
- **FR-H1-3**: The agent MUST be able to re-write `output_file` and trigger another validation pass without leaving the current turn. No extra Stop tick is required between the bad write and the corrected write.
- **FR-H1-4**: When validation passes, the Stop-hook MUST emit no extra body (only the existing "step in progress" or "advance to next step" feedback). The validator is silent on success.

### Theme H2 — Surface the contract in Stop-hook feedback

- **FR-H2-1**: For an agent step whose workflow JSON declares `inputs:`, the Stop-hook feedback body MUST include the resolved `## Resolved Inputs` block (the same one PR #166 prepends to the agent's prompt). This eliminates the agent's need to read upstream output files to learn input values.
- **FR-H2-2**: For an agent step whose workflow JSON declares an `instruction:`, the Stop-hook feedback body MUST include the post-`{{VAR}}`-substitution instruction text. The agent should never have to read the workflow JSON to learn what its task is.
- **FR-H2-3**: For an agent step whose workflow JSON declares `output_schema:`, the Stop-hook feedback body MUST include the schema declaration verbatim, formatted as a markdown code block under a `## Required Output Schema` heading. The agent then knows the contract before it writes.
- **FR-H2-4**: When an agent step has NEITHER `inputs:` NOR `output_schema:` (i.e. legacy workflow), the Stop-hook feedback MUST be byte-identical to today's behavior. Backward compat is non-negotiable (NFR-H-3).
- **FR-H2-5**: The Stop-hook MUST emit the surfaced contract exactly once per step entry — re-entering the same step (e.g. after a Theme H1 validation failure + re-write) MAY suppress the contract block to avoid duplication. Decision deferred to spec phase.

## Non-Functional Requirements

- **NFR-H-1 (testing — explicit)**: Every FR-H1-* and FR-H2-* lands with at least one fixture under `plugin-wheel/tests/`. Implementers MUST invoke `/kiln:kiln-test plugin-wheel <fixture>` for each fixture they author and cite the verdict report path in their friction note before marking their task complete (lifted directly from PR #166 NFR-G-1, including the lesson that authoring without invoking is the discipline gap the substrate was built to close).
- **NFR-H-2 (silent-failure tripwires)**: Each documented failure mode (output validation runs but emits no diagnostic; instruction surfacing skipped on a step that declared inputs/schema; back-compat regression on legacy step) has a regression test that fails when the failure becomes silent.
- **NFR-H-3 (backward compat — strict)**: Workflows without `inputs:` or `output_schema:` see byte-identical Stop-hook feedback to today. Verified by re-running an unchanged legacy workflow and diffing the feedback body against a pre-PRD snapshot. Same shape as PR #166 NFR-G-3.
- **NFR-H-4 (live-smoke gate — NON-NEGOTIABLE)**: PRD MUST require a post-merge live `/kiln:kiln-report-issue` smoke that compares observable round-trip count against the post-PR-#166 baseline. Audit fixtures alone are not sufficient — same lesson as PR #166 NFR-G-4. Direct cite: `.kiln/mistakes/2026-04-25-assumed-component-fixtures-equal-end-to-end-coverage.md`.
- **NFR-H-5 (perf budget)**: Hook-tick adds at most **50ms** combined for validation + instruction surfacing per agent step. Measured via `time` in a kiln-test fixture against a step with up to 5 inputs and a 5-key output_schema.
- **NFR-H-6 (atomic shipment)**: Theme H1 + Theme H2 land in the same commit (or same squash-merged PR per PR-#166's Path-B precedent). They are tightly coupled UX — surfacing the contract without validating output reads as "we'll tell you the rules but not enforce them"; validating output without surfacing the contract reads as "we'll punish you for guessing wrong on a contract we won't show you."
- **NFR-H-7 (loud failure on validator runtime errors)**: If `workflow_validate_inputs_outputs` itself errors (e.g. malformed `output_file` JSON, jq failure), the Stop-hook MUST emit a distinct error body — NOT silently fall through to "looks valid."

## Absolute Musts

These are non-negotiable. Tech stack is always #1.

1. **Bash 5.x + `jq` + POSIX**. No new runtime dependencies. Reuses the validator from PR #166.
2. **`/kiln:kiln-test` is the substrate AND the verification gate**. Implementers MUST invoke it on authored fixtures; verdict report paths cited in friction notes; auditor checks for invocation reports, not fixture-file existence. Same discipline as PR #166 Absolute Must #2.
3. **Headline metric is a hard gate** — see Success Metrics. If `/kiln:kiln-report-issue` doesn't measurably stop incurring schema-mismatch retries on the post-merge live smoke, this PRD does not ship.
4. **Strict backward compat** — workflows without `inputs:`/`output_schema:` see byte-identical feedback.
5. **Atomic shipment of Themes H1 + H2** — the UX is one feature in two halves.
6. **Live-smoke gate is NON-NEGOTIABLE** (NFR-H-4). Same lesson as PR #166. Component fixtures + audit grep are necessary but not sufficient.
7. **Loud failure on validator errors** — no silent "looks valid" fallthrough on jq errors or malformed output files.

## Tech Stack

Inherited from parent product:

- Bash 5.x + `jq` + POSIX utilities — extends `plugin-wheel/lib/workflow.sh` (validator already exists from PR #166), `plugin-wheel/hooks/post-tool-use.sh` and `plugin-wheel/hooks/stop.sh` (feedback body composition)
- `/kiln:kiln-test` harness for end-to-end fixtures
- Reuses the resolved-inputs hydration from PR #166's `plugin-wheel/lib/dispatch.sh`

No new dependencies.

## Impact on Existing Features

- **PR #166 (typed inputs/outputs)** — composes cleanly. This PRD harvests the next-layer wins from PR #166's substrate. Output-schema validation is a second use of the existing validator; instruction surfacing reuses the resolved-inputs block already composed at dispatch.
- **`/kiln:kiln-report-issue`** — the canonical demonstrator. After this PRD ships, the round-trip waste seen in `.kiln/issues/2026-04-25-typed-inputs-outputs-live-smoke-verified.md` (one extra turn for a key-name guess) goes to zero in steady state.
- **All other typed-schema workflows** (when they exist — `kiln-report-issue` is currently the only one) — same benefit. No code change needed in the workflow JSON; the runtime improvement is invisible to authors.
- **Legacy workflows (no `inputs:`/`output_schema:`)** — fully unaffected. Per NFR-H-3, byte-identical feedback.
- **Workflow author ergonomics** — schema-design errors become local. Today: write workflow → exercise it → discover violation three steps downstream → trace back. Tomorrow: write workflow → exercise it → see violation in the same turn that produced the bad output.

## Success Metrics

### Headline (HARD GATE — required to ship)

- **SC-H-1**: A fresh `/kiln:kiln-report-issue` post-PRD live smoke shows **zero output-schema-mismatch retries** in the resulting state-archive's `command_log` arrays. Baseline = 1 retry, observed in `.kiln/issues/2026-04-25-typed-inputs-outputs-live-smoke-verified.md` (the seed for this PRD).
- **SC-H-2**: The total round-trip count for `/kiln:kiln-report-issue` (Stop-hook ticks) drops by at least 1 in the same smoke, OR stays flat — never regresses.

### Secondary (informational)

- **SC-H-3**: Manually inject a wrong-key output write in a kiln-test fixture; verify the Stop-hook returns a structured diagnostic naming the diff in the same turn.
- **SC-H-4**: Manually neutralize the FR-H2-1/H2-2/H2-3 surfacing logic in a kiln-test fixture; verify the back-compat snapshot diff comes up empty (NFR-H-3 byte-identity).
- **SC-H-5**: Hook-tick perf measurement: validation + surfacing combined adds ≤50ms per agent step on a step with 5 inputs + 5-key output_schema.

### Process

- **SC-H-6**: NFR-H-4 satisfied — the live `/kiln:kiln-report-issue` smoke is part of the PR description's verification checklist, run before merge.

## Risks / Unknowns

- **R-H-1 (Stop-hook feedback length explosion)**: Surfacing the resolved inputs + instruction + output_schema for every agent step could make the feedback body very long for steps with many inputs or large instructions. Mitigation: feedback is only sent on Stop ticks, not on every tool call; the agent already needs this content to do the step. If size becomes a problem, add a `--terse` mode (omit instruction text, keep just inputs + schema) — defer that decision to spec phase.
- **R-H-2 (Validator runtime errors mistaken for schema violations)**: `workflow_validate_inputs_outputs` could fail for reasons unrelated to the output (jq parse error on a malformed `output_file`, missing `output_schema:` declaration). NFR-H-7 mandates distinct error bodies; spec phase decides the exact wording.
- **R-H-3 (Re-entry duplication for FR-H1-3)**: When an agent re-writes after a validation failure, should the contract block be re-emitted? FR-H2-5 leaves this open. Decision criterion: emit on first entry only — the agent already has the contract in its turn context.
- **R-H-4 (Audit-gap pattern recurrence)**: Same lesson as PR #166. The risk: implementers treat NFR-H-4 (live-smoke gate) as a checkbox rather than a real verification. Mitigation: the `/kiln:kiln-test plugin-kiln perf-kiln-report-issue` substrate is now proven (PR #166's audit used it); the auditor's prompt should reach for it explicitly.

## Assumptions

- The `workflow_validate_inputs_outputs` function shipped in PR #166 is already structured to validate outputs against an `output_schema` declaration, not just inputs. Spec phase verifies; if it's inputs-only, an output-side wrapper is straightforward (same jq plumbing, different argument ordering).
- The Stop-hook's existing feedback-body composition path is structured enough to inject extra markdown sections without breaking parsing. Spec phase verifies by reading `plugin-wheel/hooks/stop.sh`.
- The resolved-inputs block from PR #166 is computed at agent-step dispatch time and accessible to the Stop-hook (or recomputable cheaply). High confidence — the dispatch flow already composes it once.
- Round-trip savings from FR-H2 are real even on the first invocation (no caching effect required). High confidence — the agent currently spends a turn reading prior outputs to infer the contract; surfacing it eliminates that turn unconditionally.

## Open Questions

- **OQ-H-1**: Should the contract block (Theme H2 surfacing) be re-emitted on every entry to a step, or only on first entry? (FR-H2-5 leaves this open. See R-H-3.) Decision criterion: minimize duplication without making re-entry confusing.
- **OQ-H-2**: When the validator detects a wrong-shape output, should the Stop-hook automatically delete the bad output_file, or leave it for the agent to overwrite? Tradeoff: deletion is cleaner state, but the agent may want to inspect what it wrote. Spec phase decides — likely "leave it; the next write overwrites."
- **OQ-H-3**: Should validation errors flow through the same "exit reason" the existing tripwires use (`reason=preprocess-tripwire`, etc.), or get a new code (`reason=output-schema-violation`)? New code is more precise but adds surface area. Likely new code — easier to grep in archives.

## Pipeline guidance

This wants the full `/kiln:kiln-build-prd` pipeline:

- **Specifier** produces spec + plan + interface contracts (output-side validator wrapper, Stop-hook feedback composer, contract-block formatter) + tasks. Resolves OQ-H-1/H-2/H-3 in the spec phase.
- **Researcher** captures the post-PR-#166 baseline for `/kiln:kiln-report-issue` round-trip count + Stop-hook tick count BEFORE implementation starts. This is SC-H-1/SC-H-2's reference point. Without it, the headline metric is unmeasurable. (The seed run in this PRD's `derived_from:` source already provides one data point — researcher confirms or refreshes.)
- **Single implementer** — scope is small enough (Stop-hook feedback composition + validator output-side wrapper) that splitting parallelism doesn't help.
  - Implementer MUST invoke `/kiln:kiln-test plugin-wheel <fixture>` for every fixture authored AND `/kiln:kiln-test plugin-kiln perf-kiln-report-issue` (the live-smoke substrate proven in PR #166) before marking task complete. Cites verdict report paths in friction note.
- **No qa-engineer** (no visual surface).
- **Auditor** verifies: every FR-H1-*/FR-H2-* has a fixture; every fixture has a `.kiln/logs/kiln-test-<uuid>.md` PASS verdict cited in the implementer's friction note (NFR-H-1); atomic shipment of H1 + H2 in single commit (NFR-H-6); back-compat byte-identical snapshot diff for legacy step (NFR-H-3); live-smoke headline metric satisfied (NFR-H-4 + SC-H-1 + SC-H-2). Fixture-file existence without an invocation report is a blocker.
- **Retrospective** analyzes whether the live-smoke discipline (NFR-H-4) actually caught issues during implementation, or whether it became a checkbox AGAIN. Direct comparison to the PR #166 retrospective findings — same gate, same risk pattern, separate occurrence.
