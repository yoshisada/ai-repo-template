# `context_from:` narrowing — pure ordering only

**Status**: Active as of branch `build/wheel-step-input-output-schema-20260425` (FR-G5-1, FR-G5-2 of `specs/wheel-step-input-output-schema/`).
**Replaces (data role)**: `inputs:` (FR-G1-1, FR-G3-1).
**See also**: [`workflow-schema.md`](./workflow-schema.md), [`specs/wheel-step-input-output-schema/spec.md`](../../specs/wheel-step-input-output-schema/spec.md).

## TL;DR

> `context_from:` documents **pure ordering**. Data passing has moved to `inputs:` + `output_schema:`.

When an agent step needs **values** from upstream steps, declare `inputs:` (per `workflow-schema.md` §inputs). The wheel runtime resolves each input against state / config / session registry and prepends a `## Resolved Inputs` block to the agent's instruction — no in-step `cat`/`jq`/`grep` boilerplate is required.

When a step needs to wait for an upstream step **without** consuming its data (e.g. "obsidian-apply must run after read-shelf-config completes"), keep `context_from:` — the wait-on-step semantics are unchanged.

## What changed

| Before | After |
|---|---|
| `context_from:` was the **only** way to pass values from upstream steps. The runtime auto-appended a "## Context from Previous Steps" footer listing the upstream output **path** (not the values). Agents wrote in-step `jq -r .field .wheel/outputs/<id>.json` boilerplate to extract the values they actually wanted. | `context_from:` is **pure ordering**. The auto-appended footer is preserved when `inputs:` is absent (backward compat — NFR-G-3). When the step **also** declares `inputs:`, the footer is suppressed and the resolved-inputs block replaces it (FR-G1-3). |

## Why we narrowed instead of replacing

The audit at [`research.md` §audit-context-from](../../specs/wheel-step-input-output-schema/research.md#job-2--context_from-inventory--classification-fr-g5-3) classified all 61 shipped `context_from:` uses:

- **51 of 61 (84%)** are pure-ordering — the consumer never reads from `.wheel/outputs/<source>`. These keep `context_from:` byte-identically.
- **5 of 61 (8%)** are data-passing — these are the migration targets. `kiln-report-issue.json::dispatch-background-sync` is migrated **in this PRD** (FR-G4); the other four sites get follow-on PRs (one per workflow).
- **5 of 61 (8%)** are probable-data-passing (sub-workflow filename aliases) — same migration class as data-passing; bundled into the same follow-on PR portfolio.

Replacing `context_from:` outright would have churned every shipped workflow with no behavior change in the pure-ordering majority. Narrowing the contract documentation lets ordering uses keep the field they already use.

## Sub-workflow output filename quirk

For `type: workflow` steps, the output is written under the **sub-workflow's** filename (e.g. `shelf-write-issue-note-result.json`), **not** under the wrapping step's id. The `output_schema:` declaration on the wrapping step is what exposes those fields to downstream `inputs:` resolution — the wheel runtime follows the alias when it resolves `$.steps.<wrapping-step-id>.output.<field>`. Workflow authors do NOT have to address the sub-workflow filename directly.

Reference: [`research.md` §Job 2 Methodology](../../specs/wheel-step-input-output-schema/research.md#methodology) for the full quirk catalogue.

## Decision: defer rename to `after:`

Open question OQ-G-2 in the PRD asked whether to rename `context_from:` → `after:` in v1. The spec **deferred** the rename: cosmetic-only, would touch every shipped workflow (audited inventory above), zero migration cost to keep the existing field with documented narrowed semantics. A follow-on PRD may rename if a workflow author trips over the now-misleading name.

## When to use which

| Need | Field |
|---|---|
| "Step Y must run after step X" — no value consumption | `context_from: ["X"]` |
| "Step Y reads `.wheel/outputs/X.json` to extract a field" | `inputs: { FIELD: "$.steps.X.output.<field>" }` + `output_schema:` on X |
| Both ordering AND data | `inputs:` (which already enforces order) — drop `context_from:` for the data-only deps |

## Migration checklist for follow-on PRs

When migrating a data-passing `context_from:` use to `inputs:`:

1. Add `output_schema:` to the upstream step (declare every field the downstream needs — the validator at workflow-load time refuses references to undeclared fields).
2. Add `inputs:` to the downstream step (per `workflow-schema.md` §inputs).
3. Replace inline `cat`/`jq`/`grep` references in the downstream `instruction:` with `{{VAR}}` placeholders.
4. Drop the corresponding `context_from:` entries — keep only the pure-ordering deps.
5. Add a `/kiln:kiln-test` fixture that activates the migrated workflow and asserts the resolved-inputs block appears in the dispatched prompt (NFR-G-1 substrate).
