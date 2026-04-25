# Implementation Plan: Wheel as Runtime

**Branch**: `build/wheel-as-runtime-20260424` | **Date**: 2026-04-24 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification at `specs/wheel-as-runtime/spec.md`, PRD at `docs/features/2026-04-24-wheel-as-runtime/PRD.md`

## Summary

Five thematically-aligned fixes land under one PRD because they share the same fix surface — wheel's environment, agent-resolution, and step-execution contracts. The plan partitions implementation by theme onto four parallel implementer tracks, isolates the riskiest work (hook newline preservation + `WORKFLOW_PLUGIN_DIR` export parity) onto a single track so the two "silent-failure" fixes land in one coordinated PR slice, and prescribes interface contracts that every track must honor. No new runtime dependencies.

**Technical approach at a glance**:
- **Theme A (agents)**: New resolver script at `plugin-wheel/scripts/agents/resolve.sh` emits a stable JSON spec given a path or short name. All agent files relocate to `plugin-wheel/agents/<name>.md` in ONE atomic PR with symlinks at old paths (NFR-7). Workflow JSON gains additive `agent_path:`. Kiln skills gain an option to spawn via the resolver.
- **Theme B (models)**: Workflow JSON gains additive `model:` on agent steps. Dispatch enforces the value (no silent fallback). Docs gain a one-line selection rubric.
- **Theme C (hook)**: `plugin-wheel/hooks/post-tool-use.sh` stops pre-flattening newlines. Uses `jq -r` on raw input first with a JSON-aware `python3` fallback only on parse failure. Fuzz test over hook-input shapes seals the regression.
- **Theme D (env parity)**: `WORKFLOW_PLUGIN_DIR` is exported into the workflow's lifetime env scope so every sub-agent inherits it (Option A). Consumer-install smoke test simulates the missing-source-repo layout and fires in CI.
- **Theme E (batching)**: Audit every `"type": "agent"` step across the five plugin workflow directories. Consolidate one high-leverage step (documented candidate: `dispatch-background-sync`) into a single wrapper. Raw before/after timings committed. Negative result is acceptable.

## Technical Context

**Language/Version**: Bash 5.x (hook scripts, resolver, step wrappers, tests); Markdown + JSON (workflow + skill definitions).
**Primary Dependencies**: wheel engine (`plugin-wheel/`), `jq` (JSON parsing), POSIX utilities (`grep -F`, `awk`, `sed`, `tr`), `python3` (JSON-aware fallback in hook — stdlib only, `-c "import json,sys; …"`), existing wheel team primitives (`TeamCreate`, `TaskCreate`, etc.), existing kiln skill-test harness under `plugin-kiln/tests/`, `/wheel:wheel-test` for CI integration.
**Storage**: File-based JSON state (`.wheel/state_*.json`, `.wheel/history/`); markdown audit doc at `.kiln/research/`.
**Testing**: `plugin-wheel/workflows/tests/` (workflow tests via `/wheel:wheel-test`); `plugin-wheel/tests/` (shell-level unit tests for hook scripts + resolver); `plugin-kiln/tests/<feature>/` (skill-test fixtures for kiln-side integration). NFR-3 fuzz test lives under `plugin-wheel/tests/hook-input-fuzz/`.
**Target Platform**: Claude Code CLI harness on macOS (darwin) and Linux. Consumer install layout — plugins under `~/.claude/plugins/cache/<org>-<mp>/<plugin>/<version>/` — MUST be simulated in FR-D2.
**Project Type**: Claude Code plugin source repo (markdown skills/agents + shell hooks). No compiled artifact.
**Performance Goals**: FR-E3 seeks a measurable wall-clock drop on the chosen batched step — raw before/after numbers; no numeric target (negative result is acceptable per FR-E3). NFR-4 smoke test MUST fit within current `/wheel:wheel-test` budget or earn its own CI job.
**Constraints**: NFR-5 byte-identical backward-compat for workflows that don't use the new JSON fields. NFR-7 atomic agent-migration window (one PR, symlinks at old paths). Hook changes must NEVER silently flatten `tool_input.command` — NFR-2 tripwire test required.
**Scale/Scope**: 5 plugin workflow directories audited in FR-E1; ~11 shipped agents relocated under FR-A2; 2 additive workflow JSON fields (`agent_path`, `model`); 1 hook script rewritten; 1 env-export change; 1 batched wrapper prototype; CI smoke test wired.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Spec-First (NON-NEGOTIABLE)**: PASS — `specs/wheel-as-runtime/spec.md` committed before any implementation. Every FR carries a theme tag (A/B/C/D/E).
- **II. 80% Test Coverage**: PASS — NFR-1 enforces one test per FR; NFR-2 adds regression tripwires for silent-failure fixes. Bash coverage is measured by per-test assertions (no traditional line-coverage tool needed for shell — `/wheel:wheel-test` verdicts + skill-test fixture verdicts are the enforcement).
- **III. PRD as Source of Truth**: PASS — spec derives directly from `docs/features/2026-04-24-wheel-as-runtime/PRD.md`; no divergence. PRD OQ-001 and OQ-002 flow into Open Questions and are resolved in Phase 0 research below.
- **IV. Hooks Enforce Rules**: PASS — the feature branch matches `build/*` accept-list (verified by existing hook test). Spec + plan + tasks committed before any `src/` edit.
- **V. E2E Testing Required**: PASS — FR-D2 is explicitly an E2E consumer-install smoke test running in CI; FR-C2 acceptance scenarios exercise a real workflow activation end-to-end; FR-E3 measurement is on the real workflow dispatch path.
- **VI. Small, Focused Changes**: PASS with caveat — the feature bundles five themes deliberately (shared fix surface, per PRD). Each theme is a bounded area partitioned to its own implementer track. The `impl-wheel-fixes` track bundles C+D because both touch wheel's dispatch/env plumbing; splitting them would force re-touching the same code paths. Files stay under 500 lines (new resolver script is ~100 lines estimated; hook rewrite reduces line count, doesn't grow it).
- **VII. Interface Contracts Before Implementation (NON-NEGOTIABLE)**: PASS — `contracts/interfaces.md` covers: agent resolver (FR-A1/A3), workflow JSON dispatch extensions for `agent_path` (FR-A4) and `model` (FR-B1/B2), post-tool-use hook command-extraction contract (FR-C1), `WORKFLOW_PLUGIN_DIR` export contract (FR-D1), batched step wrapper contract shape (FR-E2/E4). All four implementer tracks MUST match these signatures exactly.
- **VIII. Incremental Task Completion (NON-NEGOTIABLE)**: PASS — tasks.md partitions work by theme with phase markers; each implementer marks tasks `[X]` as they land and commits per phase.

**Result**: All gates pass. No complexity-tracking entries required.

## Project Structure

### Documentation (this feature)

```text
specs/wheel-as-runtime/
├── plan.md                        # This file
├── spec.md                        # Already committed
├── research.md                    # Phase 0 — OQ-1, OQ-2, R-001, R-003 resolutions
├── contracts/
│   └── interfaces.md              # Phase 1 — REQUIRED (Constitution Article VII)
├── data-model.md                  # Phase 1 — key entities from spec
├── quickstart.md                  # Phase 1 — "how to exercise this feature end-to-end"
├── tasks.md                       # Phase 2 (/tasks output)
├── agent-notes/
│   ├── specifier.md               # Friction note (NON-NEGOTIABLE per pipeline contract FR-009)
│   ├── impl-themeA-agents.md
│   ├── impl-themeB-models.md
│   ├── impl-wheel-fixes.md
│   └── impl-themeE-batching.md
└── checklists/
    └── requirements.md            # Already committed
```

### Source Code (repository root) — files added/modified by theme

```text
# Theme A — Agent centralization & path-addressable resolution
plugin-wheel/agents/                           # NEW canonical home for all agents
├── qa-engineer.md
├── debugger.md
├── smoke-tester.md
├── prd-auditor.md
├── spec-enforcer.md
├── test-runner.md
├── ux-evaluator.md
├── reconciler.md                              # generic archetypes
├── writer.md
├── researcher.md
└── auditor.md
plugin-wheel/scripts/agents/
├── resolve.sh                                 # FR-A1 resolver — emits JSON spec
└── registry.json                              # short-name → canonical-path map
plugin-<*>/agents/                             # OLD paths — replaced with symlinks → plugin-wheel/agents/<name>.md (NFR-7)

plugin-wheel/tests/agent-resolver/             # FR-A1/A3 unit tests
plugin-wheel/tests/agent-reference-walker/     # FR-A2 + SC-008 — assert every agent ref resolves

# Theme B — Per-step model selection
plugin-wheel/scripts/dispatch/                 # shared dispatch helpers (may exist already)
├── resolve-model.sh                           # FR-B1/B2 — maps "haiku|sonnet|opus|<id>" to concrete model id
└── dispatch-agent-step.sh                     # threads `model:` into the spawned Agent call
plugin-wheel/README.md                         # FR-B3 doc update (+ FR-E4 batching convention)
plugin-kiln/skills/plan/SKILL.md               # FR-B3 wheel-workflow guidance update

plugin-wheel/tests/model-dispatch/             # FR-B1/B2 tests — haiku spawn, explicit id, mismatch-loud-fail

# Theme C+D — Hook newline preservation + WORKFLOW_PLUGIN_DIR env parity
plugin-wheel/hooks/post-tool-use.sh            # FR-C1 rewrite — no pre-flatten
plugin-wheel/scripts/activate.sh               # touched for FR-C2 if regex needs widening
plugin-wheel/scripts/workflow-env.sh           # FR-D1 — exports WORKFLOW_PLUGIN_DIR into workflow lifetime env
plugin-wheel/scripts/dispatch-subagent.sh      # FR-D1 — ensures env is present for both fg + bg spawns
CLAUDE.md                                      # FR-D3 — note Option A/B, portability section update

plugin-wheel/tests/hook-input-fuzz/            # NFR-3 fuzz test — multi-line, control chars, JSON escapes
plugin-wheel/tests/activate-multiline/         # FR-C2 workflow-tests fixture
plugin-wheel/tests/workflow-plugin-dir-bg/     # FR-D2 consumer-install smoke test
.github/workflows/                             # NFR-4 CI wiring for FR-D2 smoke test

# Theme E — Step-internal command batching
.kiln/research/wheel-step-batching-audit-2026-04-24.md   # FR-E1 audit doc (raw numbers in FR-E3)
plugin-shelf/scripts/step-dispatch-background-sync.sh    # FR-E2 prototype wrapper (documented candidate)
# (or plugin-<X>/scripts/step-<name>.sh if audit flags a higher-leverage target)
plugin-wheel/README.md                         # FR-E4 convention doc appended

# Pipeline / retrospective agents
plugin-kiln/skills/kiln-fix/SKILL.md           # FR-A5 — option to spawn debugger via resolver (SC-005 canonical target)
plugin-kiln/tests/kiln-fix-resolver-spawn/     # SC-005 — skill test for resolver-spawned debugger
```

**Structure Decision**: This feature modifies the existing `plugin-wheel/` substrate plus cross-cuts `plugin-kiln/`, `plugin-shelf/`, and any plugin with agent references. No new top-level directories. The resolver pattern (`plugin-wheel/scripts/agents/resolve.sh` + `registry.json`) mirrors the shape of `plugin-kiln/scripts/context/read-project-context.sh` (shared script consumed by multiple skills).

## Partition Rationale

Four implementer tracks, chosen to minimize cross-track coordination cost:

- **`impl-themeA-agents`** → FR-A1..A5 + NFR-7. Owns the resolver, the atomic agent-file migration, and the workflow JSON `agent_path:` dispatch extension. This track is sequenced first among the theme tracks because FR-B (model dispatch) and the `impl-wheel-fixes` track may want to consume the resolver's contract for tests. Migration (FR-A2) is the single riskiest task — NFR-7 demands all old paths have symlinks before any caller is switched.
- **`impl-themeB-models`** → FR-B1..B3. Owns the workflow JSON `model:` dispatch extension plus documentation updates (wheel README + `/plan` template). Independent of Theme A mechanically; depends on Theme A only for the interface contract shape agreed in `contracts/interfaces.md`.
- **`impl-wheel-fixes`** → FR-C1..C4 + FR-D1..D4. Themes C and D are bundled onto ONE track because both touch wheel's dispatch/env plumbing (`post-tool-use.sh`, `activate.sh`, the workflow lifetime env scope, the sub-agent dispatch path). Splitting them would force re-touching the same code paths and creates a merge-conflict magnet. Same-track ownership is also how we can write the NFR-3 fuzz test and the FR-D2 consumer-install smoke test as one coordinated test suite.
- **`impl-themeE-batching`** → FR-E1..E4. Pure audit + prototype + doc. Independent of all other tracks. The documented candidate (`dispatch-background-sync`) currently uses the Theme-D-affected env-parity path — Theme E track should NOT block on D; instead it runs its measurement against the post-D code and records the numbers honestly.

**Cross-track interface boundaries** (hard-coded in `contracts/interfaces.md`):
- Theme B's dispatch extension consumes the `agent_path:` resolver output shape from Theme A. If Theme A revises the JSON shape, `contracts/interfaces.md` MUST be updated first and Theme B's tests re-run.
- The `impl-wheel-fixes` track's FR-D1 export contract is what every downstream sub-agent relies on for `WORKFLOW_PLUGIN_DIR`. Theme A's resolver MUST use `${WORKFLOW_PLUGIN_DIR}` (not a source-repo-relative path) wherever it emits JSON pointing at scripts — this is how Theme A avoids being consumer-install-fragile.
- Theme E's wrapper scripts MUST use `${WORKFLOW_PLUGIN_DIR}` for every path they reference (same reason).

## Phases

### Phase 0 — Research (consolidated in `research.md`)

Resolve the open questions and risks from spec.md / PRD before dispatching implementer tracks:

- **OQ-1 (resolver location)**: Decision — **script-only form** (`plugin-wheel/scripts/agents/resolve.sh`) for v1. Rationale: every current caller is a script or a skill that can shell out; adding `/wheel:wheel-resolve-agent` is ceremony without a concrete consumer today. Revisit if a future skill needs user-facing resolution.
- **OQ-2 (model fallback list)**: Decision — **strictly one model per step** for v1. Rationale: additive field, smallest possible surface, graceful-degradation lists add ambiguity to FR-B2's "surface as error, no silent fallback" invariant. Deferred as an optional future extension.
- **R-001 (env-inheritance for bg sub-agents)**: Prototype Option A FIRST inside the `impl-wheel-fixes` track's Phase 1 spike. If A is infeasible (the harness baselines its own env for background spawns), fall back to Option B (prompt-template the absolute path) AND update FR-D3 CLAUDE.md note. The FR-D2 smoke test is the invariant, not the implementation approach.
- **R-003 (model-override billing gate)**: Out of scope for this PRD. If the harness refuses `model:` values, the dispatch surfaces the harness's error string (FR-B2 loud-fail). A project-level allow-list config is deferred — file a follow-on issue if the harness's behavior motivates it.
- **R-004 (hook regex blast radius)**: Before FR-C1 lands, grep every regex in `plugin-wheel/hooks/` and `plugin-wheel/scripts/` that reads `tool_input.command` OR a flattened form of it. Any regex that assumed single-line input is a sibling-fix inside this PRD's blast radius. Record findings in `research.md` and enumerate in `tasks.md`.
- **R-005 (negative perf result)**: Acceptable. If FR-E3 finds no speedup, ship the audit with the negative finding and narrow FR-E scope — `tasks.md` carries an explicit "negative-result fallback" task so the retrospective doesn't flag it as a scope failure.

### Phase 1 — Design & Contracts

1. **`contracts/interfaces.md`** — REQUIRED. Covers: agent resolver signature + JSON output shape, workflow JSON `agent_path:` field, workflow JSON `model:` field, post-tool-use hook command-extraction contract, `WORKFLOW_PLUGIN_DIR` export contract, batched step wrapper contract shape.
2. **`data-model.md`** — Describes the six key entities (agent definition, resolver JSON output, workflow JSON agent-step extensions, consumer-install simulation, batched step wrapper, the bg-log-line regression fingerprint string).
3. **`quickstart.md`** — How a reviewer exercises this feature end-to-end: run the multi-line activation fuzz test, run the consumer-install smoke test, invoke the resolver from a kiln skill, run a workflow with `model: haiku`, run the batched-step prototype and compare timings.
4. **Agent context update** — run `.specify/scripts/bash/update-agent-context.sh claude` so CLAUDE.md's "Active Technologies" list picks up this branch.

### Phase 2 — Task generation (handled by `/tasks`)

`tasks.md` will partition by theme (A / B / C+D / E), sequence within each theme by FR order, mark cross-theme dependencies explicitly (e.g. Theme B's tests depend on Theme A's resolver contract), and include the R-004 blast-radius enumeration task under `impl-wheel-fixes`.

## Complexity Tracking

No Constitution Check violations; section intentionally empty. The feature's complexity comes from bundling five themes, which is justified by shared fix surface (PRD Background + Problem Statement) and explicitly acknowledged in Constitution Check VI.
