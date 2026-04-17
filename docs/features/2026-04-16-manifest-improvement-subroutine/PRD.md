# Feature PRD: Manifest Improvement Subroutine

## Parent Product

Kiln plugin (`@yoshisada/kiln`) + shelf plugin (`@yoshisada/shelf`) — see `docs/PRD.md` for product context.

This feature lives in the shelf plugin because it writes to the Obsidian manifest vault, which is shelf's surface.

## Feature Overview

A reusable wheel sub-workflow — `shelf:propose-manifest-improvement` — that any workflow can invoke as a terminal-ish step. It runs an agent reflection on the current run, and **only if** the agent identifies a concrete, actionable change to a manifest file, it writes a single proposal to `@inbox/open/` describing the exact patch. On every other run, it exits silently.

The point is to turn every workflow invocation into a chance to improve the manifest itself — without producing noise when there's nothing to say.

## Problem / Motivation

The manifest vault (`@manifest/types/*.md`, `@manifest/templates/*.md`) defines the schemas and templates that shape every artifact shelf writes into Obsidian. Today, improving it is purely human-driven: the AI encounters a schema gap mid-run, works around it, and the lesson is lost.

We want the AI to propose improvements back to the manifest when it notices one, but only through the proposal write-flow (not direct writes), and only when the proposal is **specific enough to apply** — target file, current text, proposed text, and a one-sentence reason grounded in the run. Anything less than that is noise.

Doing this once per workflow is duplicated logic; making it a sub-workflow means every caller gets consistent behavior and a single place to evolve the quality bar.

## Goals

- A standalone wheel sub-workflow that any other workflow can invoke.
- Enforce an "exact patch or stay silent" quality gate — no vague suggestions.
- Wire it into the three workflows that run often: `report-mistake-and-sync`, `report-issue-and-sync`, `shelf-full-sync`.
- Silent no-ops — when there's nothing to propose, nothing is written anywhere.

## Non-Goals

- Auto-applying the patch. Proposals go to `@inbox/open/` for human review only.
- Scoring, ranking, or deduping proposals. One file per run, human triages.
- Scope beyond `@manifest/types/*.md` and `@manifest/templates/*.md` — NOT shelf skills, NOT plugin code, NOT any other vault folder.
- Invoking this step from `/kiln:mistake` directly. `/kiln:mistake` activates `report-mistake-and-sync`, which picks this step up for free.
- Unified-diff output format. Markdown with four headings is enough — maintainers apply by eye.

## Target Users

Shelf / kiln consumers whose workflows already touch the manifest vault. The direct users are the maintainers who review `@inbox/open/` — they are the ones who benefit from well-scoped proposals instead of vague notes.

## Core User Stories

- As a maintainer reviewing `@inbox/open/`, I want every manifest-improvement proposal to be specific enough that I can accept it in one edit, so triage stays fast.
- As an author of a wheel workflow, I want to add one step to my workflow and get manifest-reflection for free, so I don't rewrite the logic.
- As a contributor AI running a workflow, I want to propose a schema/template fix when I notice one mid-run, so the lesson is captured instead of lost.

## Functional Requirements

- **FR-1**: A new wheel workflow file `plugin-shelf/workflows/propose-manifest-improvement.json` MUST exist and be runnable as `shelf:propose-manifest-improvement`.
- **FR-2**: The workflow MUST have exactly two steps: `reflect` (agent) and `write-proposal` (command).
- **FR-3**: The `reflect` step MUST produce structured output (`.wheel/outputs/propose-manifest-improvement.json`) with ONE of two shapes:
  - `{"skip": true}` — no actionable change identified, OR
  - `{"skip": false, "target": "<path>", "section": "<heading or line-range>", "current": "<verbatim>", "proposed": "<verbatim>", "why": "<one sentence>"}`
- **FR-4**: The `reflect` step MUST restrict `target` to paths matching `@manifest/types/*.md` or `@manifest/templates/*.md`. Any other target MUST force `skip: true`.
- **FR-5**: The `reflect` step MUST only set `skip: false` when ALL four fields (`target`, `current`, `proposed`, `why`) are non-empty AND the `current` text exists verbatim in the target file at run time. If any field is missing or `current` does not match, the step MUST force `skip: true`.
- **FR-6**: The `why` field MUST cite something that happened in the current run (a specific file, workflow output, tool call, or artifact). Generic opinions are not acceptable.
- **FR-7**: The `write-proposal` step MUST be silent on `skip: true` — no file created, no log line, no side effect beyond exit 0.
- **FR-8**: The `write-proposal` step MUST, on `skip: false`, write a single file to `@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md` via the Obsidian MCP (no direct filesystem writes to the vault).
- **FR-9**: The proposal file MUST contain frontmatter with `type: proposal`, `target: <path>`, and `date: <YYYY-MM-DD>`, followed by four H2 sections in this exact order with these exact headings: `## Target`, `## Current`, `## Proposed`, `## Why`.
- **FR-10**: The `<slug>` in the proposal filename MUST be derived from the `why` sentence — kebab-case, stop-words removed, ≤50 characters, word-boundary-truncated.
- **FR-11**: `plugin-shelf/workflows/shelf-full-sync.json` MUST include `shelf:propose-manifest-improvement` as a pre-terminal sub-workflow step.
- **FR-12**: `plugin-kiln/workflows/report-issue-and-sync.json` MUST include `shelf:propose-manifest-improvement` as a pre-terminal sub-workflow step.
- **FR-13**: `plugin-kiln/workflows/report-mistake-and-sync.json` MUST include `shelf:propose-manifest-improvement` as a pre-terminal sub-workflow step.
- **FR-14**: The sub-workflow step in callers MUST sit **before** the terminal `shelf:shelf-full-sync` so that a proposal, if written, is picked up by the same sync pass.
- **FR-15**: If the Obsidian MCP is unavailable, the `write-proposal` step MUST warn once and exit 0 (NFR-aligned graceful degradation) — it MUST NOT block the calling workflow.
- **FR-16**: The sub-workflow MUST be plugin-portable — all command-step scripts MUST resolve via `${WORKFLOW_PLUGIN_DIR}` and never via repo-relative paths.

## Absolute Musts

1. **Tech stack parity**: shelf + wheel, no new dependencies. Bash for command steps, MCP for writes, markdown for the proposal file.
2. **Exact-patch gate (FR-5/FR-6)**: the silence-on-no-op rule is worthless if the patch can be vague. Non-negotiable.
3. **Silent on skip (FR-7)**: no marker files, no log lines, no `.wheel/outputs/` artifact visible to the user. Runs that don't propose look identical to runs before this feature existed.
4. **Manifest-only scope (FR-4)**: out-of-scope targets force skip. Do not silently broaden later without a new PRD.
5. **Proposal-only writes (FR-8)**: never write directly to `<project>/mistakes/`, `@manifest/`, or any canonical vault folder. `@inbox/open/` only.
6. **Plugin portability (FR-16)**: scripts resolve from plugin cache, not the source repo.
7. **One caller pattern (FR-11/FR-12/FR-13)**: the three initial callers all use the same shape — one sub-workflow step, pre-terminal, no custom glue.

## Tech Stack

Inherited from kiln + shelf. No additions.

## Impact on Existing Features

- **`shelf-full-sync`**: gains one sub-workflow step before the self-improve / terminal steps. Steady-state behavior unchanged (silent skip).
- **`report-issue-and-sync`**: gains one sub-workflow step before the terminal `shelf-full-sync` call.
- **`report-mistake-and-sync`**: same as above. `/kiln:mistake` inherits this via its workflow.
- **`@inbox/open/` triage**: maintainers may see manifest-improvement proposals alongside issue/mistake proposals. Filenames are distinct (`manifest-improvement-*`).

No breaking changes. If the feature is disabled (sub-workflow removed from callers), everything reverts to today's behavior.

## Success Metrics

- **M1 — Silent rate**: on a steady-state run with no real improvement to propose, 0 files written, 0 log lines emitted by this step. Measured by counting `.wheel/outputs/propose-manifest-improvement.*` artifacts (there should be none except the internal reflect output, which does not leak).
- **M2 — Precision**: ≥80% of written proposals are accepted by the maintainer (merged into the manifest as-written, possibly with minor edits). Measured monthly over the first 90 days.
- **M3 — Adoption**: the sub-workflow is called at least once per day across the three initial callers (assuming normal repo activity). Measured via `.wheel/history/success/` logs.
- **M4 — Zero blast radius**: 0 incidents of this step writing outside `@inbox/open/` or causing a caller workflow to fail. Measured by error rate in wheel state logs.

## Risks / Unknowns

- **Hallucinated "current" text**: the agent might cite text that doesn't verbatim exist in the target file. FR-5 requires verification at run time — this must actually be enforced by the command step, not just trusted.
- **Over-triggering**: early runs might produce too many speculative proposals if the gate is too loose. Mitigation: FR-6 (run-grounded `why`) plus monitoring M2 (acceptance rate) in the first weeks.
- **Under-triggering**: the gate might be so strict that the step never fires. Acceptable for v1 — better silent than noisy. Revisit only if M3 adoption is zero after a month.
- **Scope creep**: pressure will emerge to expand the target scope to shelf skills, plugin workflows, or the constitution. Non-goal for this feature. New PRD required.

## Assumptions

- The manifest vault MCP (`mcp__obsidian-projects__*` or a caller-provided binding) is the canonical write path for `@inbox/open/`.
- Callers already have agent context files (agent-notes, workflow outputs) in the run's `.wheel/outputs/` that the reflect step can read.
- The `${WORKFLOW_PLUGIN_DIR}` variable is reliably exported by the wheel dispatch layer (validated end-to-end in v1143).
- Maintainers triage `@inbox/open/` regularly enough that proposals don't accumulate stale.

## Open Questions

- Should the `reflect` step be allowed to produce MULTIPLE independent proposals in one run, or is one-per-run the correct constraint? (Defaulting to one-per-run for v1 — fewer edge cases.)
- Do we want the proposal file to include a backlink to the calling workflow's state file (for provenance)? Leaning yes, cheap to add, but not specified as a FR yet.
- Should `/kiln:report-issue` and `/kiln:mistake` surface to the user "a manifest improvement was proposed" when one is written, or stay fully transparent? v1 stays transparent; revisit if triage reviewers want user-side awareness.
