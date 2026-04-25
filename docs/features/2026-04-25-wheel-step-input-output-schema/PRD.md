---
derived_from:
  - .kiln/issues/2026-04-25-cross-plugin-resolver-substitution-verified-live.md
  - .kiln/mistakes/2026-04-25-assumed-component-fixtures-equal-end-to-end-coverage.md
distilled_date: 2026-04-25
theme: wheel-step-input-output-schema
---
# Feature PRD: Wheel Step Input/Output Schema (`context_from` Rework)

**Date**: 2026-04-25
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)
**Builds on**: PR #163 (cross-plugin-resolver) + PR #165 (state persists templated workflow). Does not block either — this PRD ships independently after both have stabilized.

## Parent Product

This is the **kiln** Claude Code plugin ecosystem (`@yoshisada/kiln` + sibling plugins `wheel`, `shelf`, `clay`, `trim`). Wheel is the runtime that other plugins compose workflows on top of. This feature hardens wheel's runtime *contract* for cross-step data flow — agents currently have to fetch upstream values from disk because `context_from` only passes file pointers, not values.

## Feature Overview

Replace wheel's pointer-only `context_from:` mechanism with two new fields on workflow steps: `inputs:` (declares which upstream values, config keys, or registry lookups the step needs) and `output_schema:` (declares the named fields a step's output exposes). The wheel hook resolves `inputs:` at step-dispatch time and prepends a `## Resolved Inputs` block to the agent's instruction, with `{{VAR}}` placeholders in the instruction body substituted in place. `context_from:` survives only for pure ordering dependencies (rename to `after:` is a v1 candidate).

After this PRD ships, an agent step that today does `jq -r '.issue_file' .wheel/outputs/create-issue-result.md` instead receives `ISSUE_FILE: .kiln/issues/...` already inlined in its prompt. Zero disk fetches in the agent step for upstream data.

## Problem / Motivation

Today's `context_from:` is half-finished. It declares the dependency ("this step needs create-issue to have run") and tells the hook which file to expose, but the agent prompt only gets a file *path* footer like:

```
### Output from step: create-issue
.wheel/outputs/create-issue-result.md
```

That's a pointer, not data. The agent has to do at least one fetch (`jq`/`grep`/`cat`) per upstream consumer just to reconstruct values the wheel already computed. Concrete evidence from the live `/kiln:kiln-report-issue` smoke test in this session:

- `dispatch-background-sync` step did **5 disk fetches** to assemble its prompt: read counter via `bash shelf-counter.sh read`, `jq` the issue file path from write-issue-note's result, `cat .shelf-config` for `slug`/`base_path`, etc.
- Each fetch is a Bash tool call → permission prompt → token cost → wall-clock latency → opportunity for misinterpretation
- The `kiln-mistake` workflow had the same shape with even more fetches in the shelf-sync sub-workflow

The product impact is not just ergonomics. The kiln-report-issue and kiln-mistake workflows are **the feedback loop** that all other improvement skills (`/kiln:kiln-distill`, `/kiln:kiln-roadmap`, `/kiln:kiln-claude-audit`, `/kiln:kiln-pi-apply`) consume from. If reporting friction is high, capture rate drops, downstream skills have less signal to chew on, and the "context-informed autonomy" vision is starved at the source. Lowering the per-invocation tax on these workflows is a multiplier on the entire feedback loop.

The lesson from the cross-plugin-resolver bug shipped earlier today applies in a sibling form: wheel was doing partial hydration (resolving plugin paths but not step-input data), and agents were doing the rest with disk fetches. PR #165 closed the plugin-path side. This PRD closes the step-input side.

## Goals

- **Make agent step prompts self-contained.** After this PRD ships, an agent step that declares `inputs:` receives all upstream values, config values, and registry lookups inlined in a `## Resolved Inputs` block. Zero in-step disk fetches for upstream data.
- **Migrate `kiln-report-issue.json` atomically with the runtime change** to demonstrate the shape and lock in the headline metric (NFR-7 same shape as cross-plugin-resolver).
- **Preserve `context_from:` for pure ordering dependencies** (cleanup-after-X, audit-after-implementers). Document the narrowed contract; rename to `after:` in v1 is a candidate.
- **Bound the perf overhead.** Hook-time hydration adds at most 100ms per step — measured against the kiln-report-issue baseline.
- **Preserve strict backward compat.** Workflows without `inputs:`/`output_schema:` behave byte-identically to today (NFR shape lifted from cross-plugin-resolver NFR-F-5).

## Non-Goals (v1)

- **Not** a full JSONPath implementation. v1 ships a deliberately small subset: `$.steps.<id>.output.<field>`, `$config(<file>:<key>)`, `$plugin(<name>)`. Anything else is out of scope.
- **Not** migrating every workflow. v1 migrates `kiln-report-issue.json` atomically; `kiln-mistake.json` and the `shelf-*` workflows migrate in follow-on PRs (one-per).
- **Not** introducing a persistent context cache. Resolution is fresh per step (same model as cross-plugin-resolver registry).
- **Not** redesigning `context_from:`'s ordering semantics — that part of the contract stays. Only the data-passing role moves to `inputs:`.
- **Not** a workflow JSON schema migration tool. Existing workflows keep working unchanged; migration is mechanical and per-author.
- **Not** changing `output_file:` semantics. Outputs still get written to `.wheel/outputs/<step-id>-*.{txt,md,json}` for diagnostic purposes; the difference is that downstream steps consume *values* from `inputs:`, not file paths.

## Target Users

Inherited from the parent product:

- **Plugin authors** writing wheel workflow JSON files. They get a more honest contract — when a step needs a value from upstream, they declare it once in `inputs:` instead of writing fetch boilerplate in the agent prompt.
- **Plugin consumers** running `/kiln:kiln-report-issue`, `/kiln:kiln-mistake`, and similar feedback-loop workflows. They get fewer permission prompts, lower token cost, and faster wall-clock per invocation — which lowers the friction tax on capturing issues.
- **The retro/distill/roadmap pipeline** (downstream of issue capture). Higher capture rate → richer input → better-informed PRDs.

## Core User Stories

- **As a plugin author**, I want to declare `inputs: { ISSUE_FILE: "$.steps.create-issue.output.file" }` on a workflow step and have the value pre-resolved into the agent's prompt, so I don't have to write `jq -r '.file' .wheel/outputs/create-issue-result.md` boilerplate in every consumer's instruction text.
- **As a plugin consumer**, I want `/kiln:kiln-report-issue` to require fewer Bash permission prompts so I can capture friction without being interrupted from the actual work I was doing.
- **As an auditor of agent prompts** (looking at `.wheel/history/success/*.json`), I want to see resolved values in the prompt rather than file pointers, so I can verify what the agent actually had access to without dereferencing.
- **As the kiln feedback loop** (distill/roadmap/claude-audit), I want a higher rate of captured issues and mistakes so my downstream synthesis has more signal.

## Functional Requirements

### Theme G1 — Workflow JSON schema additions

- **FR-G1-1**: Workflow agent steps gain an optional `inputs:` field — an object mapping `<UPPERCASE_VAR_NAME>` → JSONPath-subset expression.
- **FR-G1-2**: Workflow steps (any type) gain an optional `output_schema:` field — an object describing the named fields the step's output exposes. For JSON outputs, fields map directly. For text/markdown outputs, each field carries an `extract:` directive (`regex:<pattern>` or `jq:<expr>` for embedded JSON).
- **FR-G1-3**: `context_from:` semantics narrow to pure ordering. The auto-appended "Context from Previous Steps" footer (current behavior) is removed when an agent step declares `inputs:` (the resolved-inputs block replaces it). When neither field is present, today's behavior is preserved (NFR-G-3 backward compat).
- **FR-G1-4**: Schema validation runs at workflow-load time. Malformed JSONPath expressions, references to undeclared upstream steps, or `output_schema:` mismatches fail loud.

### Theme G2 — JSONPath subset

The v1 grammar is deliberately narrow. The resolver supports exactly these expressions:

- **FR-G2-1**: `$.steps.<step-id>.output.<field>` — resolves to a named field of an upstream step's output (per its `output_schema:`).
- **FR-G2-2**: `$config(<file>:<key>)` — reads a key from a config file (e.g., `$config(.shelf-config:shelf_full_sync_counter)`). v1 supports `.shelf-config` (TOML-ish flat key=value) and any JSON file via `<file>:<jq-path>`.
- **FR-G2-3**: `$plugin(<name>)` — resolves to a plugin's absolute install path (delegates to `build_session_registry` from the cross-plugin-resolver feature).
- **FR-G2-4**: `$step(<step-id>)` — resolves to the absolute path of an upstream step's output file (escape hatch for cases where the agent really does need the file path, not the data).
- **FR-G2-5**: Anything else fails loud at workflow-load time. No silent fallthrough.

### Theme G3 — Hook-time hydration

- **FR-G3-1**: At each agent-step dispatch, `plugin-wheel/lib/dispatch.sh` resolves every `inputs:` entry against the current state, config files, and session registry.
- **FR-G3-2**: Resolved values are prepended to the step's instruction text as a `## Resolved Inputs` block (markdown bullet list, one entry per input).
- **FR-G3-3**: `{{VAR}}` placeholders in the instruction body are substituted with the resolved values inline (consistent with `${WHEEL_PLUGIN_<name>}` substitution from cross-plugin-resolver).
- **FR-G3-4**: Resolution failures (input refers to a step that didn't run, config key missing, plugin not in registry) produce a loud error and abort the step. No silent empty-string substitution.
- **FR-G3-5**: Tripwire: after substitution, no `{{VAR}}` placeholders remain in the instruction. Failure → loud error, no agent dispatch.

### Theme G4 — `kiln-report-issue.json` migration (atomic)

- **FR-G4-1**: `plugin-kiln/workflows/kiln-report-issue.json` adds `output_schema:` to `check-existing-issues`, `create-issue`, `write-issue-note`.
- **FR-G4-2**: The `dispatch-background-sync` step adds `inputs:` declaring the values it currently fetches: `ISSUE_FILE`, `OBSIDIAN_PATH`, `CURRENT_COUNTER`, `THRESHOLD`, `SHELF_DIR`.
- **FR-G4-3**: The `dispatch-background-sync` step's `instruction:` is rewritten to use `{{VAR}}` placeholders. The 5 disk-fetch commands the agent currently runs are removed from the instruction text.
- **FR-G4-4**: The `create-issue` step's `instruction:` similarly migrates: `SLUG`, `BASE_PATH`, etc. become inputs.
- **FR-G4-5**: Migration commits atomically with the wheel runtime change (NFR-G-7, lifted from cross-plugin-resolver NFR-F-7).

### Theme G5 — `context_from:` narrowing

- **FR-G5-1**: `context_from:` documentation updated: data-passing role moves to `inputs:`; pure ordering remains.
- **FR-G5-2**: `context_from:` continues to gate step ordering byte-identically to today (no behavior change for non-data dependencies).
- **FR-G5-3**: Audit pass over all shipped workflows identifies which `context_from:` uses are pure-ordering (keep) vs data-passing (migrate to `inputs:` in this PRD or a follow-on). Documented in `specs/wheel-step-input-output-schema/research.md` so each follow-on migration knows its scope.
- **FR-G5-4**: Optional rename `context_from:` → `after:` in v1 — decision deferred to spec phase. Old name kept as an alias if rename ships.

## Non-Functional Requirements

- **NFR-G-1 (testing — explicit)**: Every FR-G1..G4 lands with at least one test exercising it end-to-end. Substrate: `/kiln:kiln-test` for any FR depending on real agent-session behavior; pure-shell unit tests acceptable for resolver/hydration logic without an LLM in the loop. **Implementers MUST invoke `/kiln:kiln-test <plugin> <fixture-name>` for each fixture they author and cite the verdict report path (`.kiln/logs/kiln-test-<uuid>.md`) in their friction note before marking their task complete.** Writing a fixture that *could* run under kiln-test but never actually invoking it does not satisfy this NFR — the auditor's check is "verdict report exists and shows PASS," not "fixture file exists."
- **NFR-G-2 (silent-failure tripwires)**: Each documented failure mode (resolution failure, missing upstream output, malformed JSONPath, residual `{{VAR}}` post-substitution) has a regression test that fails when the failure becomes silent.
- **NFR-G-3 (backward compat — strict)**: Workflows without `inputs:` or `output_schema:` behave byte-identically to today (instruction text, agent prompt, side effects). Verified by re-running an unchanged workflow and diffing the resulting state file + log file against a pre-PRD snapshot. (Same shape as cross-plugin-resolver NFR-F-5.)
- **NFR-G-4 (live-smoke gate — NON-NEGOTIABLE)**: PRD MUST require a post-merge live `/kiln:kiln-report-issue` smoke that compares observable agent tool-call count against the baseline captured at implementation start. Audit fixtures alone are not sufficient. Direct lesson from `.kiln/mistakes/2026-04-25-assumed-component-fixtures-equal-end-to-end-coverage.md`.
- **NFR-G-5 (resolver perf)**: Hook-time hydration adds at most **100ms** per agent step on a step with up to 5 inputs. Measured via `time` in a kiln-test fixture.
- **NFR-G-6 (atomic migration)**: FR-G4's migration of `kiln-report-issue.json` lands in the same commit as the runtime change. No half-state where the workflow declares `inputs:` but the resolver isn't running.
- **NFR-G-7 (no PII or secrets in resolved-inputs block)**: The resolved-inputs block is part of the agent prompt. If a config file value contains a secret (e.g. an API key in `.shelf-config`), the resolver MUST refuse to inline it. Spec phase decides the detection mechanism (frontmatter marker on the input, allowlist of safe config keys, or pattern-based redaction). Default-deny on unknown.

## Absolute Musts

These are non-negotiable. Tech stack is always #1.

1. **Bash 5.x + `jq` + POSIX**. No new runtime dependencies. Wheel is shell-script-based; this PRD stays inside that constraint.
2. **`/kiln:kiln-test` is the substrate AND the verification gate** for any test whose claim depends on real agent-session behavior. Implementers MUST invoke `/kiln:kiln-test` against their authored fixtures before marking a task complete; the verdict report at `.kiln/logs/kiln-test-<uuid>.md` MUST show PASS and be cited in the implementer's friction note. Authoring-without-invoking is the same failure mode that shipped PR #163 — fixture exists, never run, ships broken.
3. **Headline metric is a hard gate** — see Success Metrics. If `/kiln:kiln-report-issue` doesn't measurably get faster (fewer agent tool calls + lower wall-clock) on the post-merge live smoke, this PRD does not ship.
4. **Strict backward compat** — workflows without `inputs:`/`output_schema:` behave byte-identically.
5. **Atomic migration** — `kiln-report-issue.json` migrates in the same commit as the runtime change.
6. **Live-smoke gate is NON-NEGOTIABLE** (NFR-G-4). Lesson from this session's mistake. Component fixtures + audit grep are necessary but not sufficient.
7. **Loud failure on resolution errors** — no silent empty-string substitution, no fallback to file-pointer footer.

## Tech Stack

Inherited from parent product:

- Bash 5.x + `jq` + POSIX utilities for the resolver, hydration, and schema validation
- `plugin-wheel/lib/` adds substitution logic to `dispatch.sh` and `preprocess.sh`; schema validation extends `workflow.sh::workflow_load`
- `/kiln:kiln-test` harness for end-to-end fixtures
- Reuses `build_session_registry` from cross-plugin-resolver for `$plugin(<name>)` resolution

No new dependencies.

## Impact on Existing Features

- **`context_from:` semantics narrow** — data-passing moves to `inputs:`. Existing workflows that use `context_from:` for data passing continue to work via the legacy footer until they migrate. Pure-ordering uses are unaffected.
- **`/kiln:kiln-report-issue` (the canonical migration)** becomes faster end-to-end after this PRD. The 5 in-step disk fetches in `dispatch-background-sync` collapse to 0.
- **`/kiln:kiln-mistake`, `shelf-*` workflows** — unmigrated in v1, but each becomes a candidate for follow-on PRs that demonstrate the same pattern.
- **Cross-plugin-resolver feature (PR #163, PR #165)** — composes cleanly. The `$plugin(<name>)` resolver delegates to `build_session_registry`. The `{{VAR}}` substitution runs in the same pass as `${WHEEL_PLUGIN_<name>}` substitution.
- **Workflow author ergonomics**: reduces fetch boilerplate in `instruction:` text. Authors can audit their workflows for `jq -r '...' .wheel/outputs/...` patterns and fold them into `inputs:`.

## Success Metrics

### Headline (HARD GATE — required to ship)

- **SC-G-1**: `/kiln:kiln-report-issue` post-PRD live smoke shows **≥3 fewer agent Bash/Read tool calls** in the `dispatch-background-sync` step than the pre-PRD baseline. Baseline captured from a fresh kiln-report-issue run against `main` at PR #165's merge commit (`5a4fe69`) before implementation begins. Tool-call count extracted from the agent step's `command_log` array in `.wheel/history/success/kiln-report-issue-*.json`.
- **SC-G-2**: `/kiln:kiln-report-issue` post-PRD live smoke shows **lower wall-clock from activation to dispatch-background-sync completion** than the pre-PRD baseline. Tolerance: any measurable decrease passes; regression by more than 10% fails the gate.

### Secondary (informational)

- **SC-G-3**: Per-step token usage in the migrated workflow drops measurably (output_tokens for the dispatch-background-sync step's first agent turn).
- **SC-G-4**: Permission prompt count for `/kiln:kiln-report-issue` drops by at least 3 (one per eliminated Bash call). Measured by counting Bash tool invocations in the user-facing transcript.
- **SC-G-5**: An audit pass over all shipped workflows produces a documented inventory of `context_from:` uses split into "pure ordering" vs "data passing." All data-passing uses get a follow-on migration ticket filed.

### Process

- **SC-G-6**: NFR-G-4 satisfied — the live `/kiln:kiln-report-issue` smoke test is part of the PR description's verification checklist, run by the auditor (or the team-lead on PR open) before merge.

## Risks / Unknowns

- **R-G-1 (JSONPath grammar scope creep)**: v1 deliberately ships a tiny subset. If spec phase finds a real workflow that needs richer expressions, the temptation is to expand the grammar. Mitigation: any expansion ships in a follow-on PRD; v1 holds the line at the four documented expression types.
- **R-G-2 (`output_schema:` extraction reliability)**: Markdown outputs need regex/jq extraction, which is fragile. Mitigation: fail loud on extraction failures (NFR-G-2 tripwire), prefer JSON outputs in migrated workflows where feasible.
- **R-G-3 (Secret leakage in resolved-inputs block)** — NFR-G-7 mandates default-deny for unknown config keys. Spec phase decides the exact mechanism. If this isn't designed carefully, an `inputs:` declaration could pull `OPENAI_API_KEY` from a `.env` file into an agent prompt, which becomes part of the workflow history and potentially leaks. **This is a security risk; treat as blocking for the spec phase.**
- **R-G-4 (Audit gap pattern recurrence)**: The cross-plugin-resolver bug taught that component fixtures don't catch wiring gaps. NFR-G-4 (live-smoke gate) is the structural answer. The risk: implementers may treat NFR-G-4 as "nice to have." Mitigation: bake it into the audit checklist as a hard gate.
- **R-G-5 (`context_from:` rename churn)**: Renaming to `after:` is cosmetic. If the rename ships, every existing workflow needs a touch (or an alias preserved indefinitely). Likely defer the rename to a follow-on; don't bundle.

## Assumptions

- Workflow authors will value the reduced fetch boilerplate enough to migrate workflows opportunistically over time. Adoption is opt-in; v1 only proves the pattern with one workflow.
- The pre-PRD baseline for `/kiln:kiln-report-issue` is reproducible — i.e., the tool-call count and wall-clock are stable enough across runs that a comparison is meaningful. Spec phase verifies via N=3 baseline runs.
- The hook-time hydration adds <100ms — high confidence given hydration is local jq operations against in-memory state. Spec phase confirms.
- The cross-plugin-resolver registry (`build_session_registry`) is the right primitive for `$plugin(<name>)` resolution. High confidence — it's already proven in PR #163 and PR #165.
- The `.shelf-config` file format (flat `key = value`) is stable enough to define a `$config()` resolver against. Spec phase verifies; if not stable, define a small shim in `plugin-shelf/scripts/`.

## Open Questions

- **OQ-G-1 (BLOCKING — must be answered in spec phase)**: What is the secret-detection mechanism for NFR-G-7? Three candidates:
  - **Candidate A**: Allowlist — only specific config keys are inlinable, others fail loud. Simple, secure, requires per-key declaration.
  - **Candidate B**: Frontmatter on the workflow — `inputs: { COUNTER: { from: "$config(.shelf-config:counter)", safe: true } }`. Per-input opt-in.
  - **Candidate C**: Pattern-based redaction — detect strings matching `*_KEY`, `*_TOKEN`, `*_SECRET`, etc., and refuse. Brittle.
  Decision criterion: pick the simplest mechanism that catches obvious secret patterns and fails closed on unknown. Likely Candidate A.
- **OQ-G-2**: Should `context_from:` rename to `after:` ship in v1, or wait? Tradeoff: cosmetic improvement vs. churn across all existing workflows + an alias to maintain. Spec phase decides based on inventory size.
- **OQ-G-3**: How does `inputs:` interact with `parallel` and `loop` step types? v1 may scope to `agent` steps only, with parallel/loop as v2. Spec phase confirms.

## Pipeline guidance

This wants the full `/kiln:kiln-build-prd` pipeline:

- **Specifier** produces spec + plan + interface contracts (resolver, hydration helpers, `output_schema` extractors, schema validators) + tasks. Resolves OQ-G-1 (secret detection) as the first spec-phase research task — it's the only blocking unknown.
- **Researcher** captures the pre-PRD baseline for `/kiln:kiln-report-issue` (tool-call count + wall-clock + transcript) before implementation starts. This is SC-G-1/SC-G-2's reference point — without it, the headline metric is unmeasurable. Also performs the workflow audit for FR-G5-3.
- **2 implementers in parallel**:
  - `impl-resolver-hydration`: `dispatch.sh` hydration logic + `inputs:` resolver + `{{VAR}}` substitution + tripwires
  - `impl-schema-migration`: `workflow.sh` schema validation for `inputs:`/`output_schema:` + `kiln-report-issue.json` migration (atomic with the runtime change per NFR-G-6)
  - **Both implementers MUST invoke `/kiln:kiln-test plugin-wheel <fixture>` (or `plugin-kiln <fixture>`) for every fixture they author and cite the verdict report path in their friction note. Tasks are not complete until the verdict report shows PASS.** Writing fixture files alone does not count — this is the discipline gap that allowed PR #163's wiring bug to ship; NFR-G-1 + Absolute Must #2 codify the rule.
- **No qa-engineer** (no visual surface; bash + JSON + agent prompts).
- **Auditor** verifies: all FRs have ≥1 fixture **AND each fixture has a corresponding `.kiln/logs/kiln-test-<uuid>.md` PASS verdict cited in an implementer friction note** (NFR-G-1); live-smoke headline metric satisfied (NFR-G-4 + SC-G-1 + SC-G-2); atomic migration in single commit; no `{{VAR}}` residuals in `.wheel/history/success/*.json` post-PRD. Fixture-file existence without an invocation report is a blocker.
- **Retrospective** analyzes whether the live-smoke discipline (introduced as NFR-G-4 in direct response to the cross-plugin-resolver mistake) actually caught issues during implementation, or whether it became a checkbox.
