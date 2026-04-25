# Implementation Plan: Agent Prompt Composition

**Branch**: `build/agent-prompt-composition-20260425` | **Date**: 2026-04-25 | **Spec**: [spec.md](./spec.md)
**Input**: Feature spec at `specs/agent-prompt-composition/spec.md`, PRD at `docs/features/2026-04-25-agent-prompt-composition/PRD.md`

## Summary

Two themes — compile-time include preprocessor (Theme B) and runtime context-injection composer (Theme A) — ship under one PRD because they compose at two layers of one architecture. Implementation partitions onto two parallel implementer tracks (`impl-include-preprocessor` for Theme B, `impl-runtime-composer` for Theme A) that touch DISJOINT file sets per spec.md "Theme Partition" table. No new runtime dependencies. Single squash-merged PR per Path B (NFR-4).

**Technical approach at a glance**:
- **Theme B**: Bash + awk/sed resolver at `plugin-kiln/scripts/agent-includes/resolve.sh` (~80 lines, single-pass, no recursion). Hybrid resolution timing — sources authored, compiled outputs committed, CI gate verifies parity. One shared module ships in v1 (`_shared/coordination-protocol.md`); 2–3 existing agents refactored.
- **Theme A**: Bash + jq composer at `plugin-wheel/scripts/agents/compose-context.sh` (sibling to existing `resolve.sh`, NOT extending it). Emits JSON `{subagent_type, prompt_prefix, model_default}`. Validator script for `agent_bindings:` schema. 8-shape closed task vocabulary; 6-verb closed namespace. 3 research-first agent.md files (1 audited, 2 new).

## Phase 0 — Research / Decision Resolution

This PRD has NO quantitative SC items requiring baseline measurement (per the new §1.5 rule from issue #170 fix). The architectural validation is already in implementation_hints (4 tests + live demo from 2026-04-24). Phase 0 is decision-resolution only.

### OQ-1 — Theme B resolution timing: HYBRID

**Decision**: Sources authored at `plugin-kiln/agents/_src/<role>.md` (when a role uses includes) OR in-place at `plugin-kiln/agents/<role>.md` (when a role has no directives — the resolver is a no-op for un-directived files per NFR-2). Compile-and-commit pattern: a build script (`plugin-kiln/scripts/agent-includes/build-all.sh`) walks `_src/`, runs the resolver, writes compiled output to `plugin-kiln/agents/<role>.md`. Both source AND compiled forms are committed. CI gate (`check-compiled.sh`) re-runs build and asserts compiled == build(sources).

**Rationale**:
- Pure scaffold-time (init.mjs runs the resolver at consumer install) creates source-file diff drift if consumers ever edit resolved output. Also pushes resolver-availability into consumer environment (Bash + awk/sed everywhere — fine, but unnecessary if we precompile).
- Pure build-time (committed compiled outputs only — no sources) is fine but loses the "single source of truth for shared boilerplate" win that motivates the feature.
- **Hybrid wins**: sources are the single source of truth; compiled outputs are the artifact init.mjs ships; CI catches drift.

**init.mjs impact**: NONE. init.mjs already copies `plugin-kiln/agents/*.md` to consumer's install path; it copies the compiled output, never the `_src/`. `_src/` is a kiln-source-repo-only concept.

### OQ-2 — Theme B directive syntax: `<!-- @include <relative-path> -->`

**Decision**: HTML-comment-safe form on a line by itself. Path is relative to the **agent file's own directory** (so `plugin-kiln/agents/qa-engineer.md` references `_shared/coordination-protocol.md` as `<!-- @include _shared/coordination-protocol.md -->`).

**Rationale**:
- User's stated form `{insert_<path>.md}` collides with bash brace expansion if the file is ever piped through a shell.
- Handlebars-partial `{{> include path.md }}` is unfamiliar in this codebase and adds a syntax surface that's only used here.
- HTML-comment shape mirrors mdx-prompt / POML conventions (industry-aligned), preserves markdown rendering (the directive becomes invisible in any markdown viewer), and is trivially regex-detectable on a line-by-line scan.

**Regex**: `^[[:space:]]*<!-- @include[[:space:]]+([^[:space:]][^>]*[^[:space:]])[[:space:]]*-->[[:space:]]*$`. Whitespace-tolerant on either end of the line. Path captured from group 1. Resolver MUST skip directive-shaped strings inside fenced code blocks (lines between matched ` ``` ` markers — see contracts §1 for the full state-machine sketch).

### OQ-3 — Is `agent` shape needed in v1? YES

**Decision**: Include `agent` in the 8-shape closed vocabulary v1.

**Rationale**: This very PRD ships 3 new agent.md files. A "meta-task targeting an agent prompt itself" is the canonical exemplar. Removing the shape would orphan the use case at the moment the use case is being proven.

### OQ-4 — Theme A composer location: SIBLING `compose-context.sh`

**Decision**: New script at `plugin-wheel/scripts/agents/compose-context.sh`. Does NOT extend `resolve.sh`.

**Rationale**:
- `resolve.sh` (~60 lines, single-purpose: path-or-name → JSON spec with `subagent_type`/`tools`/`canonical_path`) is stable, used by `/kiln:kiln-fix` and workflow dispatch. Conflating it with prompt-prefix assembly (verb tables, variable bindings, stanza concatenation) bloats its contract and increases the blast radius of any change.
- Sibling separation: `resolve.sh` answers "what agent is this?"; `compose-context.sh` answers "what's the runtime context block for this agent + this task?" Different responsibilities, different change cadence.
- Composition at the call site: callers that want both invoke `resolve.sh` for the spec, then pass `agent_name` to `compose-context.sh` for the prefix. Clean.

### OQ-5 — Shared module location: `plugin-kiln/agents/_shared/<name>.md`

**Decision**: Co-located with agents under the underscore-prefixed `_shared/` subdirectory.

**Rationale**:
- Co-location: the resolver walks `plugin-kiln/agents/`, sees both spawnable agents and shared modules in one tree. No cross-directory path semantics to debate.
- Underscore-prefix: sorts to the top of `ls`, visually distinct from spawnable agents, follows existing conventions (`_index.json`, `_src/`).
- The agent-registration scan that picks up `name:` frontmatter ignores `_shared/` (no `name:` field in shared modules — they're pure body).

## Technical Context

**Language/Version**: Bash 5.x (resolver, composer, validator scripts); Markdown + JSON (agent files, manifests, task-shape stanzas, verb index).
**Primary Dependencies**: existing wheel engine + `WORKFLOW_PLUGIN_DIR` Option B mechanism (already shipped); `jq` (JSON parsing); `awk`/`sed` (directive matching + replacement); existing kiln-test substrate (`plugin-kiln/tests/<feature>/run.sh`).
**Storage**: File-based (markdown agent files, JSON indexes, JSON test fixtures). No DB, no state files beyond what already exists.
**Testing**: `plugin-kiln/tests/<feature>/run.sh` (substrate hierarchy tier-2: invoke directly via `bash`, exit code + PASS summary). `plugin-wheel/tests/<feature>/run.sh` for composer + validator tests. NO Playwright (no UI surface).
**Target Platform**: macOS (darwin) + Linux. Both POSIX `awk`/`sed` and GNU variants must work — resolver tested on both. macOS BSD `sed` quirks (no `-i ''` requirement) handled via `awk`-first design.
**Project Type**: Claude Code plugin source repo (markdown skills/agents + shell scripts). No compiled artifact at install time; `_src/` → `<role>.md` compiled at PR time.
**Performance Goals**: NFR-6 — composer + resolver outputs are deterministic + byte-identical for unchanged inputs. No throughput target.
**Constraints**:
- NFR-1 — cache-layout preservation (per-spawn variables in include directives FORBIDDEN).
- NFR-4 — atomic shipment (single squash-merged PR).
- NFR-8 — disjoint file partition (spec.md "Theme Partition" table).
- R-2 — directive regex MUST exclude fenced code blocks.
**Scale/Scope**: 1 resolver script (~80 lines), 1 composer script (~150 lines), 1 validator script (~60 lines), 1 build script, 1 CI-gate script, 1 shared module, 3 refactored agents, 2 new agents, 1 audit of an existing agent, 8 task-shape stanzas, 1 task-shape index, 1 verb index, 1 plugin-manifest extension, ~6 test fixtures.

## Constitution Check

*GATE: Must pass before Phase 1 design.*

- **I. Spec-First (NON-NEGOTIABLE)**: PASS — `spec.md` committed before any implementation. Every FR carries a theme tag (A/B).
- **II. 80% Test Coverage**: PASS — every FR has at least one `run.sh` fixture per the SC table. Bash coverage measured by per-test assertions; tier-2 substrate (run.sh exit code + PASS summary) is the enforcement.
- **III. PRD as Source of Truth**: PASS — spec derives directly from `docs/features/2026-04-25-agent-prompt-composition/PRD.md`; OQ-1 / OQ-2 / OQ-4 resolved here in Phase 0; no PRD divergence.
- **IV. Hooks Enforce Rules**: PASS — feature branch matches `build/*` accept-list. Spec + plan + tasks committed before any code edit.
- **V. E2E Testing Required**: PASS — SC-1 fixture refactors real agents and re-spawns to verify no behavioral regression; SC-3 fixture invokes composer end-to-end; SC-4/SC-5 validators exercised against real malformed manifest/PRD fixtures.
- **VI. Small, Focused Changes**: PASS — two themes deliberately bundled (composing layers of one architecture); each theme is a bounded area on its own implementer track. NO file is owned by both tracks (NFR-8). Largest single new file estimated at ~150 lines (composer) — well under the 500-line cap.
- **VII. Interface Contracts Before Implementation (NON-NEGOTIABLE)**: PASS — `contracts/interfaces.md` covers: include-resolver signature (Theme B), composer signature + JSON output schema (Theme A), `agent_bindings:` JSON schema, `agent_binding_overrides:` JSON schema, per-shape stanza file format, closed verb namespace v1, closed task-shape vocabulary v1.
- **VIII. Incremental Task Completion (NON-NEGOTIABLE)**: PASS — `tasks.md` partitions tasks by theme with phase markers; each implementer marks `[X]` as they land and commits per phase.

**Result**: All gates pass. No complexity-tracking entries required.

## Project Structure

### Documentation (this feature)

```text
specs/agent-prompt-composition/
├── plan.md                        # This file
├── spec.md                        # Already committed
├── contracts/
│   └── interfaces.md              # REQUIRED (Constitution Article VII)
├── tasks.md                       # /tasks output
├── agent-notes/
│   ├── specifier.md               # Friction note (NON-NEGOTIABLE per pipeline FR-009)
│   ├── impl-include-preprocessor.md
│   └── impl-runtime-composer.md
└── checklists/
    └── requirements.md            # Optional, populated as needed
```

### Source code (added/modified by theme)

```text
# Theme B — Compile-time include preprocessor (impl-include-preprocessor)
plugin-kiln/scripts/agent-includes/
├── resolve.sh                     # NEW — directive resolver, ~80 lines
├── build-all.sh                   # NEW — walks _src/, invokes resolve.sh, writes compiled outputs
└── check-compiled.sh              # NEW — CI gate: re-runs build, asserts compiled == build(sources)

plugin-kiln/agents/_shared/
└── coordination-protocol.md       # NEW — SendMessage-relay-results boilerplate

plugin-kiln/agents/_src/           # NEW (only for agents that use includes)
├── qa-engineer.md                 # source — replaces inline coordination prose with directive
├── prd-auditor.md                 # source
└── debugger.md                    # source

plugin-kiln/agents/                # COMPILED outputs (committed)
├── qa-engineer.md                 # MODIFIED — compiled from _src/
├── prd-auditor.md                 # MODIFIED — compiled from _src/
└── debugger.md                    # MODIFIED — compiled from _src/

plugin-kiln/tests/
├── agent-includes-resolve/run.sh  # NEW — SC-1 fixture
└── agent-includes-ci-gate/run.sh  # NEW — SC-2 fixture

# Theme A — Runtime context-injection composer (impl-runtime-composer)
plugin-wheel/scripts/agents/
├── compose-context.sh             # NEW — composer, ~150 lines
├── validate-bindings.sh           # NEW — manifest+override validator, ~60 lines
└── verbs/
    └── _index.json                # NEW — closed verb namespace v1

plugin-kiln/lib/task-shapes/
├── _index.json                    # NEW — closed task-shape vocabulary v1
├── skill.md                       # NEW
├── frontend.md                    # NEW
├── backend.md                     # NEW
├── cli.md                         # NEW
├── infra.md                       # NEW
├── docs.md                        # NEW
├── data.md                        # NEW
└── agent.md                       # NEW

plugin-kiln/agents/
├── research-runner.md             # AUDIT/refactor — already exists
├── fixture-synthesizer.md         # NEW
└── output-quality-judge.md        # NEW

plugin-kiln/.claude-plugin/plugin.json  # MODIFIED — adds agent_bindings: section

CLAUDE.md                          # MODIFIED — adds 6 architectural rules (FR-A-12)

plugin-wheel/tests/
├── compose-context-shape/run.sh             # NEW — SC-3 fixture
├── compose-context-unknown-override/run.sh  # NEW — SC-5 fixture
└── validate-bindings-unknown-verb/run.sh    # NEW — SC-4 fixture

plugin-kiln/tests/
├── research-first-agents-structural/run.sh  # NEW — SC-6 fixture
└── claude-md-architectural-rules/run.sh     # NEW — SC-8 fixture
```

## Phase 1 — Design Artifacts

### Data model (key entities)

See spec.md §"Key Entities". The plan-phase additions:

- **Composer input contract**: `task_spec` JSON shape — `{"task_shape": "<one-of-8>", "task_summary": "<sentence>", "variables": {...}, "axes": [...]}` — pinned in contracts §2.
- **Composer output contract**: `{"subagent_type": "kiln:<role>", "prompt_prefix": "<assembled markdown>", "model_default": "haiku|sonnet|opus|null"}` — pinned in contracts §2.
- **`prompt_prefix` body shape** — markdown with a top-level `## Runtime Environment` heading followed by sections: `### Variables`, `### Verbs`, `### Task Shape: <shape>` (stanza body inlined), `### Coordination Protocol` (stanza body inlined). Pinned in contracts §2.
- **`agent_bindings:` schema** — `{"<agent-short-name>": {"verbs": {"<verb-name>": "<command-template-string>"}}}`. Command-template strings MAY contain `${VAR}` references resolved at runtime by the calling skill (NOT by the composer — composer treats them as opaque strings).
- **`agent_binding_overrides:` schema** — same shape as `agent_bindings:`, in PRD frontmatter under the `agent_binding_overrides:` key.

### Integration recipe (R-3 mitigation)

A research-first orchestrating skill SHOULD use the composer like this:

```bash
# 1. Resolve agent identity (existing resolve.sh)
SPEC_JSON=$(bash "$WORKFLOW_PLUGIN_DIR/scripts/agents/resolve.sh" research-runner)
SUBAGENT_TYPE=$(echo "$SPEC_JSON" | jq -r .subagent_type)

# 2. Compose runtime context block
PREFIX=$(bash "$WORKFLOW_PLUGIN_DIR/scripts/agents/compose-context.sh" \
  --agent-name research-runner \
  --plugin-id kiln \
  --task-spec /tmp/task-spec.json \
  --prd-path docs/features/<prd>.md | jq -r .prompt_prefix)

# 3. Spawn (the calling skill is responsible for prepending PREFIX to the actual task)
# Agent({
#   subagent_type: SUBAGENT_TYPE,
#   prompt: PREFIX + "\n---\n" + actual_task,
#   team_name: "...",
#   name: "baseline-runner"
# })
```

This recipe is documented in plan.md (here) and in CLAUDE.md as part of FR-A-12's documentation block.

### Agent registration (CC constraint)

Per the implementation hints, agent registration is session-bound. The 3 new agent.md files (`research-runner.md`, `fixture-synthesizer.md`, `output-quality-judge.md`) WILL NOT be spawnable in the session that ships them. Acceptance fixtures (SC-6 structural-validity) verify file shape only — NOT live spawn. Live spawn validation is queued for the first `09-research-first` PRD, which will run in a fresh session.

## Phase 2 — Tasks

See `tasks.md`. Two implementer tracks; tasks partitioned to match the spec.md "Theme Partition" table.

## Risks & Mitigations (from spec)

Carried verbatim from spec §"Risks". Plan-phase additions:

- **R-2 fenced-code-block edge case**: contracts §1 pins the regex AND the state-machine sketch (toggle on ` ``` `). Resolver test `agent-includes-resolve/run.sh` includes a fixture file with directive-shaped text inside a code block.
- **R-3 composer-skill integration**: integration recipe documented above + in CLAUDE.md. First research-first PRD's specifier reviews composer usage.
- **R-4 PRD-override schema drift**: contracts §4 pins shape; validator catches malformed entries (SC-5 fixture).

## Out of Scope (carried from spec)

- Runtime resolution of include directives.
- Variable substitution inside include directives.
- Conditional / recursive / cross-plugin includes.
- Generalizing to non-kiln plugins.
- In-session agent registration.
- Tools-frontmatter enforcement testing.
- Retroactively refactoring every existing kiln agent.

## Phase 3 — Pipeline Coordination

- **2 implementers in parallel** (`impl-include-preprocessor` Theme B, `impl-runtime-composer` Theme A) — disjoint file sets per spec §"Theme Partition" + NFR-8. No coordination friction expected; per-track friction notes filed in `agent-notes/`.
- **No qa-engineer** — no visual surface.
- **No researcher** — Phase 0 decisions are resolved here in plan.md from PRD's implementation_hints.
- **Auditor** verifies SC-1..SC-8 + FR-A/FR-B coverage by fixture + atomic shipment per NFR-4 + architectural rules in CLAUDE.md (FR-A-12 grep gate).
- **Retrospective** analyzes whether the unified-PRD framing helped or hurt — see specifier friction note for the spec-phase data point.
