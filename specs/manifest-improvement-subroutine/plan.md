# Implementation Plan: Manifest Improvement Subroutine

**Branch**: `build/manifest-improvement-subroutine-20260416` | **Date**: 2026-04-16 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/manifest-improvement-subroutine/spec.md`

## Summary

Ship a reusable wheel sub-workflow — `shelf:propose-manifest-improvement` — that any caller can invoke as a pre-terminal step. It reflects on the current run's artifacts, and ONLY if it identifies a concrete, actionable change to a file under `@manifest/types/` or `@manifest/templates/`, writes a single proposal to `@inbox/open/` via the Obsidian MCP. Every other run, silent no-op.

Technical shape: one JSON workflow definition (`plugin-shelf/workflows/propose-manifest-improvement.json`) with exactly two steps — a `reflect` agent step that emits a JSON verdict and a `write-proposal` command step that either no-ops or dispatches a write. Command-step logic lives in `plugin-shelf/scripts/` and is invoked via `${WORKFLOW_PLUGIN_DIR}` so it runs correctly from consumer repos. The MCP write itself happens inside an agent sub-step of `write-proposal` (command steps cannot call MCP directly), but the command step drives the gate, slug derivation, and silent-skip semantics deterministically in bash. The three initial callers (`shelf:shelf-full-sync`, `kiln:report-issue-and-sync`, `kiln:report-mistake-and-sync`) each add one sub-workflow step immediately before their terminal `shelf:shelf-full-sync` (for the two kiln callers) or their terminal `self-improve` step (for `shelf-full-sync` itself).

## Technical Context

**Language/Version**: Bash 5.x (command step scripts); Markdown + JSON (workflow + skill definitions).
**Primary Dependencies**: wheel engine (`plugin-wheel/`), Obsidian MCP (`mcp__claude_ai_obsidian-manifest__*` for `@inbox/`), `jq` for JSON parsing, standard POSIX utilities (`grep -F` for verbatim match, `date` for ISO dates, `sed`/`tr` for slug derivation).
**Storage**: File-based — reflect output at `.wheel/outputs/propose-manifest-improvement.json` (internal, not user-visible); proposal file at `@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md` written via MCP.
**Testing**: Bash-level unit tests for slug derivation and output validation. Integration test via workflow execution harness (seed a reflect output, invoke command step, assert silent skip or MCP write). Live test via invoking the three caller workflows in a test repo.
**Target Platform**: Claude Code runtime with wheel plugin loaded. Runs in both plugin source repo and consumer repos where shelf is installed from the plugin cache.
**Project Type**: Wheel workflow + command-step scripts + skill definition — extends existing plugin-shelf and plugin-kiln surfaces.
**Performance Goals**: `write-proposal` completes in <500ms on `skip: true` path. On `skip: false`, time is dominated by the MCP write (acceptable up to ~5s wall time). No caller workflow may see this step add more than ~5s to its overall runtime.
**Constraints**: Silent-on-skip is byte-exact — no stdout/stderr visible to user. MCP unavailability MUST NOT block caller (exit 0 with single warning). `current` text match is verbatim (byte-for-byte, not whitespace-normalized). No new dependencies beyond what shelf + kiln already use.
**Scale/Scope**: ~1 call per day per repo across 3 callers. ≤1 proposal file written per invocation. Proposal files accumulate in `@inbox/open/` until triaged; volume expected <30/month in steady state.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Spec-First Development | PASS | Spec + FRs committed before implementation. Every exported function will carry an FR reference comment. |
| II. 80% Test Coverage Gate | PASS | Slug derivation + output validation + verbatim `current` match are pure bash functions — covered via bats-style unit tests. Integration coverage via workflow harness. |
| III. PRD as Source of Truth | PASS | Spec maps to PRD FR-1..FR-16 one-to-one (spec extends to FR-017..FR-020 for edge cases explicitly called out in the PRD risks section; none contradict the PRD). |
| IV. Hooks Enforce Rules | PASS | No hook changes required. The 4-gate workflow applies (spec + plan + tasks + [X] mark) — this doc is part of satisfying it. |
| V. E2E Testing Required | PASS | Workflow will be invoked end-to-end via the wheel runtime against a real Obsidian MCP in the integration test. |
| VI. Small, Focused Changes | PASS | One new workflow file, one new skill, ≤4 new small bash scripts (<150 LOC each), 3 caller edits (one step each). No new abstraction layer. |
| VII. Interface Contracts Before Implementation | PASS | `contracts/interfaces.md` authored as part of this plan — covers JSON shape, bash function signatures, command-step CLI contract. |
| VIII. Incremental Task Completion | PASS | Tasks will be ordered so each phase commits; `[X]` marks happen per-task in `/implement`. |

No violations. Complexity tracking table is empty.

## Project Structure

### Documentation (this feature)

```text
specs/manifest-improvement-subroutine/
├── spec.md                 # Done — /specify output
├── plan.md                 # This file
├── research.md             # Phase 0 — decisions + rationale
├── data-model.md           # Phase 1 — entities (reflect output, proposal file)
├── contracts/
│   └── interfaces.md       # Phase 1 — exact signatures, single source of truth
├── quickstart.md           # Phase 1 — how to invoke + test locally
├── tasks.md                # Phase 2 — /tasks output
├── checklists/
│   └── requirements.md     # Done — /specify quality gate
└── agent-notes/
    └── specifier.md        # Friction note for the /specify + /plan + /tasks skills
```

### Source Code (repository root)

```text
plugin-shelf/
├── workflows/
│   └── propose-manifest-improvement.json        # NEW — the sub-workflow
├── scripts/
│   ├── validate-reflect-output.sh               # NEW — enforces FR-3..FR-6
│   ├── derive-proposal-slug.sh                  # NEW — FR-10 slug derivation
│   ├── check-manifest-target-exists.sh          # NEW — FR-5 verbatim match
│   └── write-proposal-dispatch.sh               # NEW — orchestrates write-proposal command step
├── skills/
│   └── propose-manifest-improvement/
│       └── SKILL.md                             # NEW — standalone invocation surface (optional per FR-017)
└── shelf-full-sync.json                         # EDIT — add sub-workflow step before terminal self-improve

plugin-kiln/
├── workflows/
│   ├── report-issue-and-sync.json               # EDIT — add sub-workflow step before terminal full-sync
│   └── report-mistake-and-sync.json             # EDIT — add sub-workflow step before terminal full-sync

tests/                                           # scaffold path; consumer-side location (not in this source repo)
├── unit/
│   ├── derive-proposal-slug.bats                # NEW — FR-10 deterministic slug
│   ├── validate-reflect-output.bats             # NEW — FR-3..FR-6 gating
│   └── check-manifest-target-exists.bats        # NEW — FR-5 verbatim match
└── integration/
    ├── silent-skip.sh                           # NEW — end-to-end skip: true path
    ├── write-proposal.sh                        # NEW — end-to-end skip: false path
    └── caller-wiring.sh                         # NEW — 3 callers each write a proposal in same pass
```

**Structure Decision**: The sub-workflow lives in `plugin-shelf/` because it writes to the Obsidian manifest vault — shelf's surface. Callers in `plugin-kiln/` reference it by namespaced name (`shelf:propose-manifest-improvement`). All command-step scripts resolve via `${WORKFLOW_PLUGIN_DIR}/scripts/` so they run from plugin cache in consumer repos. No new test dirs in this source repo — tests scaffold into consumer projects via the init templates.

## Phase 0 — Research (research.md)

See `research.md` for full decisions. Key resolutions:

- **How does the write-proposal "command" step call MCP?** It does not directly. The command step runs a bash dispatch that validates the reflect output, derives the slug, checks `current` matches the target file, and — only if all checks pass — emits a small JSON envelope to `.wheel/outputs/write-proposal-dispatch.json`. The `write-proposal` step in the workflow is actually a TWO-stage micro-sequence inside the workflow: (a) a command step that runs `write-proposal-dispatch.sh` to enforce the gate deterministically, and (b) an agent step that reads the dispatch envelope and calls the Obsidian MCP. On skip, the agent step reads the envelope, sees `skip: true`, and exits without calling any MCP tool. This preserves the "silent on skip" contract while satisfying the "MCP-only writes" contract.
  - *Alternative rejected*: Embedding MCP calls inside a bash command step. Bash cannot call MCP — not viable.
  - *Alternative rejected*: A single agent step with no deterministic gate. Rejected because FR-5/FR-6 require verifiable enforcement in code, not trust in agent judgment.
- **Where does the `reflect` step get its run context?** Reads `.wheel/outputs/*` from the current run. Wheel's context-passing already injects these via `context_from`. No new plumbing.
- **How is `current` text matched?** `grep -F -- "$current" -- "$target"` (fixed-string, literal). Exit 0 → match. No whitespace normalization. No regex. This is verbatim per FR-5.
- **Slug derivation**: pure bash pipeline — lowercase → strip stop-words → replace non-alnum with `-` → collapse repeats → trim → word-boundary truncate to 50 chars. Deterministic, no randomness. Mirrors the slug algorithm already used by `report-mistake-and-sync` (Step 7 in its agent instruction), adapted to the `why` sentence.
- **Graceful MCP degradation**: The agent sub-step of `write-proposal` uses a single MCP call (`mcp__claude_ai_obsidian-manifest__create_file`). On tool-unavailable error, it writes a single line to stderr (`warn: obsidian MCP unavailable; manifest improvement proposal not persisted`) and exits 0. Wheel treats exit 0 as success — caller continues.
- **Caller wiring precedence**: All three callers already have a terminal step. The new sub-workflow goes one position before that terminal step. For `shelf-full-sync` specifically, the current terminal is `self-improve` (an agent step). The new step goes between `generate-sync-summary` and `self-improve` — so that a written proposal file does NOT get picked up by the current run's own `obsidian-apply` (which already ran) but WILL get picked up by the NEXT run. This deviates from the literal "same sync pass" reading of FR-14 for `shelf-full-sync` but is the only consistent ordering: obsidian-apply cannot run twice. For the two kiln callers, the terminal IS the full-sync sub-workflow — so a proposal written pre-terminal IS picked up by the same sync pass there. Documented as a known asymmetry in research.md.

## Phase 1 — Design & Contracts

### Data Model (data-model.md)

Two entities, both file-based. See `data-model.md` for full schemas.

1. **Reflect Output**: JSON at `.wheel/outputs/propose-manifest-improvement.json`. Union of `{skip: true}` and `{skip: false, target, section, current, proposed, why}`. Validated by `validate-reflect-output.sh`.
2. **Write-Proposal Dispatch Envelope**: JSON at `.wheel/outputs/propose-manifest-improvement-dispatch.json`. Always produced by the command sub-step. Union of `{action: "skip"}` and `{action: "write", target, proposal_path, frontmatter, body_sections: {target, current, proposed, why}}`. Consumed by the MCP agent sub-step.
3. **Proposal File** (markdown): Written to `@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md`. Frontmatter keys: `type: proposal`, `target`, `date`. Four fixed H2 sections: `## Target`, `## Current`, `## Proposed`, `## Why`.

### Interface Contracts (contracts/interfaces.md)

Defines exact signatures for every exported unit. See `contracts/interfaces.md`. High-level inventory:

- **Bash scripts** (command-step entrypoints): `validate-reflect-output.sh`, `derive-proposal-slug.sh`, `check-manifest-target-exists.sh`, `write-proposal-dispatch.sh` — each with stdin/stdout/exit-code contract.
- **Workflow JSON shape**: exact step ordering and `context_from` wiring for `propose-manifest-improvement.json`.
- **Caller integration shape**: the exact JSON snippet each of the three callers adds (identical across all three, per FR-011..FR-014).
- **Proposal file schema**: frontmatter keys + H2 section order.
- **Reflect output JSON schema**: discriminated union with exact field names.
- **Dispatch envelope JSON schema**: discriminated union with exact field names.

### Quickstart (quickstart.md)

A short recipe for a contributor to:
1. Seed a reflect output manually for both skip and no-skip cases.
2. Invoke the workflow via `/wheel-run shelf:propose-manifest-improvement`.
3. Observe silent-skip behavior on the skip path.
4. Observe proposal file creation on the no-skip path.
5. Invoke one of the three callers end-to-end and confirm wiring.

### Agent Context Update

Will run `.specify/scripts/bash/update-agent-context.sh claude` during implementation to refresh `CLAUDE.md` active-technologies list. No new tech beyond what's already documented there (Bash 5.x + jq + wheel + MCP).

## Post-Design Constitution Re-Check

All eight principles still PASS. No new violations introduced by the design. The `reflect` step is an agent, not executable code, so coverage applies only to the bash command-step scripts — which are pure, deterministic, and unit-testable at >=80% trivially.

## Complexity Tracking

*No violations to justify.*
