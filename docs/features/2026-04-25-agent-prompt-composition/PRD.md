---
derived_from:
  - .kiln/roadmap/items/2026-04-24-agent-spawn-context-injection-layer.md
  - .kiln/roadmap/items/2026-04-25-agent-prompt-includes.md
distilled_date: 2026-04-25
theme: agent-prompt-composition
---
# Feature PRD: Agent Prompt Composition — Two Layers, One Architecture

**Date**: 2026-04-25
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)

## Background

Recently the roadmap surfaced these items in the **08-in-flight** phase: `2026-04-24-agent-spawn-context-injection-layer` (feature), `2026-04-25-agent-prompt-includes` (feature). They were authored as separate items but their own bodies cross-reference each other and explicitly call out that they compose at different layers of the same architecture:

> "agent.md body = (role identity) + {include shared trailer} ← compile-time
>  spawn prompt = (Runtime Env block) + (task) ← runtime"

Bundling them into one PRD recognizes that an agent's full prompt has TWO assembly layers — one happens at scaffold/build time (the agent's persistent system prompt), the other at spawn time (per-call task context). Today both layers are ad hoc: agent.md files duplicate boilerplate by copy-paste, and runtime context (which plugin to test, which fixture, which verbs to invoke) gets encoded into the prompt freehand by each calling skill. Neither is wrong, but neither is structured — and the next major work track (`09-research-first` phase) needs both layers to exist as deliberate primitives.

This PRD ships both layers together so the `09-research-first` work has a stable, documented composition story to build on.

### Source Issues

| # | Source Entry | Source | Type | GitHub Issue | Severity / Area |
|---|---|---|---|---|---|
| 1 | [Agent spawn context-injection layer](.kiln/roadmap/items/2026-04-24-agent-spawn-context-injection-layer.md) | .kiln/roadmap/items/ | item | — | feature / phase:08-in-flight, blast:cross-cutting, review:careful |
| 2 | [Agent prompt-include preprocessor](.kiln/roadmap/items/2026-04-25-agent-prompt-includes.md) | .kiln/roadmap/items/ | item | — | feature / phase:08-in-flight, blast:feature, review:moderate |

## Implementation Hints

The following blocks are rendered verbatim from the source roadmap items per FR-027 of `structured-roadmap`. They constitute the architectural specification — the implementation must follow them, not invent alternatives.

### From `2026-04-24-agent-spawn-context-injection-layer`

Architecture validated empirically in conversation 2026-04-24 with four tests + a live team demo:

  Test 1: injecting a `## Runtime Environment` block via the `prompt` parameter composes cleanly
          with a registered agent's authored prose (kiln:test-runner). Neither layer wipes the other.

  Test 3: agents reliably self-substitute `${PLACEHOLDER}` references from a variable-bindings
          block in the same Runtime Environment block. Both pre-resolved-at-orchestrator-time and
          substitute-at-agent-time approaches work; pre-resolution is safer.

  Test 4: nested spawning has REDUCED capability. A sub-agent calling Agent only sees
          [Explore, Plan, general-purpose] subagent_types, NO model/run_in_background/isolation
          overrides, NO tools allowlist param. Teams + Tasks + SendMessage do work at depth.

  Test 2: tools-frontmatter enforcement requires session restart to test (new .md file in
          .claude/agents/ does not register in running session). Out of scope for this prereq;
          queued.

  Live demo: TeamCreate + 2 parallel teammate spawns (general-purpose, same model, DIFFERENT
          injected Runtime Environment blocks) successfully role-differentiated baseline-runner
          vs candidate-runner. Round-trip via SendMessage worked. Per-axis gate verdict aggregated.
          Mock data accidentally surfaced a cached_input_tokens regression — direct evidence
          that the cost axis (phase 09 item #3) is justified.

#### Architectural constraints documented (from proof-of-concept)

- **NEVER use `general-purpose` for specialized roles.** This is the most important rule. The proof-of-concept demo spawned baseline/candidate teammates as `general-purpose` because newly-authored agent.md files can't be tested in-session (Test 2). That was a DEMO SHORTCUT, NOT the production pattern. `general-purpose` has every tool — a research-runner running on it can write files, edit code, spawn nested agents, call any MCP. Identity-via-injection alone gives role differentiation but ZERO structural tool scoping. Production requires registered specialized subagent_types with `tools:` allowlists in their .md frontmatter. Deliverable #4 below ships those.

- **One role per registered subagent_type, multiple spawns per run.** The architecture is NOT "different role → different agent type." It's "ONE registered role (e.g., `kiln:research-runner`) spawned MULTIPLE TIMES in parallel with different injected variables (PLUGIN_DIR_UNDER_TEST differs between baseline and candidate spawns)." Same agent identity, same tool scope, different task input. The team-instance `name` parameter (e.g., "baseline-runner", "candidate-runner") is a label for coordination, not a different identity.

- **Injection is at the prompt layer, NOT the system-prompt layer.** The harness does not expose a per-spawn system-prompt mutation surface. The Runtime Context block is PREPENDED to the `prompt` parameter; the agent.md system prompt remains unchanged. This is fine — agent.md holds role identity (with tool scoping), prompt-layer holds runtime context. They compose.

- **Top-level orchestration is the right pattern, not nested.** Because nested Agent calls are reduced (no specialized subagent_types, no model override, no run_in_background), multi-agent research-first MUST orchestrate at the SKILL level (the skill spawns siblings). A research-runner role does not nest other agents; it coordinates results that the skill aggregates.

- **Agent registration is session-bound.** New `plugin-<name>/agents/<role>.md` files register at session start. Adding agents on-the-fly within a session does NOT make them spawnable until next start. Implication: research-first agents MUST ship with the plugin (kiln, etc.) — they cannot be created at PRD time.

- **Plain-text output is invisible to team-lead.** Teammates MUST relay results via SendMessage. This is a load-bearing convention: every team-mode role-prose AND every per-shape stanza must include "Relay your final structured result via SendMessage to team-lead before going idle."

#### Scope (4 deliverables)

##### 1. Runtime Context block composer (the new infrastructure)

Extend `plugin-wheel/scripts/agents/resolve.sh` (or add a sibling `compose-context.sh`) to accept:
  - agent_name (or path)
  - plugin_id (the plugin owning the role)
  - task_spec (a JSON blob with task_shape, task_summary, variables, axes, etc.)
  - prd_path (optional — for PRD-level binding overrides)

Emit a JSON spec:
  {
    "subagent_type": "<resolved>",
    "prompt_prefix": "<assembled Runtime Context block as a single string, ready to prepend>",
    "model_default": "<from agent.md frontmatter or null>"
  }

The composer pulls:
  - WORKFLOW_PLUGIN_DIR (existing Option B mechanism)
  - task_shape + task_summary (from task_spec)
  - Variable bindings (from task_spec)
  - Verb bindings (manifest defaults, PRD overrides applied)
  - Per-shape stanza (from the shape library, see #2)
  - Coordination protocol stanza (always included for team-mode spawns)

Caller (the skill) is responsible for taking `prompt_prefix` and prepending it to the actual task prompt before passing to Agent tool's `prompt` parameter.

##### 2. Closed task-shape vocabulary + per-shape stanzas

Stanzas live at `plugin-kiln/lib/task-shapes/<shape>.md`. Each is 5-15 lines of curated guidance.

Initial closed enum:
  skill        — A/B testing or modifying a /skill (uses kiln-test substrate)
  frontend     — UI / visual changes (uses Playwright + visual snapshot)
  backend      — server / API changes (uses vitest + coverage)
  cli          — CLI changes (uses stdout matching + exit code)
  infra        — wheel / hooks / build / tooling
  docs         — README / CLAUDE.md / spec docs
  data         — fixture corpus, schema migrations, etc.
  agent        — meta-task: improving an agent prompt itself

Adding shapes requires a manifest update. Open question: is `agent` legitimately needed up front or speculative? Decide during implementation.

##### 3. Plugin manifest extension for agent_bindings

Extend `plugin-<name>/.claude-plugin/plugin.json` schema:

  {
    "name": "kiln",
    "agent_bindings": {
      "research-runner": {
        "verbs": {
          "verify_quality": "/kiln:kiln-test --plugin-dir ${PLUGIN_DIR_UNDER_TEST} --fixture ${FIXTURE_ID}",
          "measure": "bash ${WORKFLOW_PLUGIN_DIR}/scripts/research/parse-stream-json.sh"
        }
      },
      "fixture-synthesizer": { "verbs": { ... } },
      "output-quality-judge": { "verbs": { ... } }
    }
  }

Validator: refuse plugin install if agent_bindings reference verbs not in the closed vocabulary for the agent's role. Closed verb namespace TBD during implementation; initial set: verify_quality, run_baseline, run_candidate, measure, synthesize_fixtures, judge_outputs

PRD frontmatter MAY override per-PRD via `agent_binding_overrides:` — same shape, narrower scope. Validator: refuse PRD if overrides reference unknown agents or verbs.

##### 4. Author 3 minimal agent .md files for research-first (each with REQUIRED tools allowlist)

Per native Claude Code agent.md format:
  plugin-kiln/agents/research-runner.md
  plugin-kiln/agents/fixture-synthesizer.md
  plugin-kiln/agents/output-quality-judge.md

Frontmatter: name + description + **tools** (REQUIRED — see allowlist sketch below). NO `model` — workflow step decides per FR-B1..B3 (already shipped in build/wheel-as-runtime-20260424).

Body: pure role identity. NO verb tables (those come from runtime context). NO tool references (same). NO model selection. NO step-by-step task prose (that's the orchestrator's job — the skill writes the task prompt and prepends the Runtime Context block).

##### Tools allowlists — proposed for v1, refine in plan/spec

  research-runner:        Read, Bash, SendMessage, TaskUpdate, TaskList
                          (read fixture content, invoke verify_quality verbs via Bash, relay results, manage shared task list. NO Write/Edit — research is read-only against candidate. NO Agent — no nested spawns. NO MCP.)

  fixture-synthesizer:    Read, Write, SendMessage, TaskUpdate
                          (read skill schema, write proposed fixtures to .kiln/research/<prd>/corpus/proposed/, relay summary. NO Bash — synthesis is text-only. NO Agent — no nested spawns. NO MCP.)

  output-quality-judge:   Read, SendMessage, TaskUpdate
                          (read paired baseline/candidate outputs + rubric, relay verdict. NO Bash, NO Write/Edit, NO Agent, NO MCP. Judge is the most tightly-scoped role for anti-drift reasons — it can't write files, can't run shell, can't spawn anything. Verdict via SendMessage only.)

##### Spawn pattern — what the orchestrator does at spawn time

  Agent({
    subagent_type: "kiln:research-runner",       ← registered, tool-scoped
    model: "haiku",                                 ← from workflow JSON step's `model:`
    team_name: "research-first-<prd-slug>",
    name: "baseline-runner",                        ← INSTANCE label, not identity
    prompt: "<Runtime Context block>\n---\n<task>"  ← composer output + actual task
  })

Same `subagent_type` is spawned twice (with name="baseline-runner" and name="candidate-runner") — same identity, same tool scope, DIFFERENT injected variables. NEVER spawn `general-purpose` for specialized roles in production. Documented as the load-bearing rule.

##### Example research-runner.md (illustrative — < 10 lines body)

  ---
  name: research-runner
  description: Reports empirical metrics for a baseline or candidate plugin against a fixture, given runtime-injected role variables.
  tools: Read, Bash, SendMessage, TaskUpdate, TaskList
  ---

  You are the research-runner. Your job: report empirical metrics for a baseline or candidate plugin against a fixture. The Runtime Environment block above tells you which role-instance you are (baseline or candidate), which plugin-dir to test, and which fixture to run. Use the verbs listed there to do the work — don't infer tools yourself, don't read source code. When done, relay your structured result via SendMessage to team-lead before going idle. Do not retry on failure; report it.

*(from: `2026-04-24-agent-spawn-context-injection-layer`)*

### From `2026-04-25-agent-prompt-includes`

#### Shape

A small preprocessor that resolves `{insert_<path>.md}` (or equivalent) directives in agent `.md` files, expanding them in-place against shared modules. User's stated form:

    xxxxxxxxxx {insert_.md}

Treat the directive as a literal verbatim include — no templating variables, no conditionals, no recursion in v1. Shared module content is concatenated at the directive's location. KISS — this is `cat` with discipline, not Jinja.

#### Where shared modules live

Recommend `plugin-kiln/agents/_shared/<name>.md`. Underscore prefix so it sorts to the top and is visually distinct from agent files. Alternative: `plugin-kiln/templates/agent-modules/<name>.md` if we want to keep `agents/` strictly for spawnable agents — defer to taste in plan.

#### Syntax candidates (decide in plan)

  1. `{insert_<path>.md}`           — user's stated form. Compact. Risk: collides with bash brace expansion if anyone ever pipes the file through a shell.
  2. `<!-- @include path.md -->`     — HTML-comment-safe, won't break markdown rendering. Slightly verbose. Mirrors mdx-prompt / POML conventions.
  3. `{{> include path.md }}`        — handlebars-partials shape. Familiar to web devs.

Recommend #2 for safety + tooling-friendliness; user's form (#1) is fine if we lock down the resolution context. Decide in plan.

#### Resolution timing

Two viable points:

  A. **Scaffold-time** in `plugin-kiln/bin/init.mjs` — when consumers run `npx @yoshisada/kiln init/update`, init.mjs walks `agents/*.md`, resolves directives, writes resolved files to the consumer's `.claude/agents/` (or wherever installed agents live). Pros: zero runtime cost; resolved file is what Claude Code reads. Cons: source-file diff drift if consumers edit resolved output.

  B. **Pre-commit / build-time** — a script run from `plugin-kiln/` that compiles sources → committed compiled outputs. Same discipline as `package-lock.json`. Pros: easy to diff; CI can verify `compiled == build(sources)`. Cons: extra commit step.

Recommend hybrid — author sources in `agents/_src/`, compile to `agents/<role>.md` via a small build script, commit both, CI verifies they match. init.mjs ships the compiled output.

#### Caching implications (load-bearing)

Trailing-include shape means: stable agent-identity prefix + stable shared trailer = full agent.md is one cacheable unit. The shared module is included ONCE per agent at compile time, so each agent's system prompt is still a stable string at runtime (no per-spawn variability). Anthropic prompt cache treats it as a single ephemeral-cache prefix — ideal cache layout. Don't break this by adding per-spawn variables to the include path; that's the spawn-time injection layer's job (see related item 2026-04-24-agent-spawn-context-injection-layer).

#### Distinction from sibling: 2026-04-24-agent-spawn-context-injection-layer

That item: runtime injection at spawn time, into the Agent tool's `prompt` parameter (NOT the system prompt). Per-spawn variable bindings, Runtime Environment block.

This item: build-time include directive into the agent's persistent system prompt (`agents/<role>.md` body). Static, no variables.

These compose: an agent's .md file = (role identity) + {insert shared trailer at compile time} → static system prompt; then at spawn time, the orchestrator prepends a Runtime Environment block to the prompt parameter for per-call context. Two different layers, both useful.

#### Initial scope (v1)

  1. Pick syntax (recommend `<!-- @include path.md -->`).
  2. Write resolver: `plugin-kiln/scripts/agent-includes/resolve.sh` (Bash + sed + cat — ~50 lines). Resolves all directives in a single pass. NO recursion in v1 (a shared module that itself includes another is an error).
  3. Author one shared trailer module: `plugin-kiln/agents/_shared/coordination-protocol.md` — the SendMessage-relay-results boilerplate that's currently duplicated across team-mode agents.
  4. Refactor 2-3 existing kiln agents to use the include directive (e.g., qa-engineer.md, prd-auditor.md, debugger.md).
  5. CI check: compiled output matches build(sources).
  6. Document in CLAUDE.md "Active Technologies" + plan.md.

#### Generalization to other plugins (defer to v2)

Same preprocessor could resolve directives in `plugin-wheel/agents/`, `plugin-shelf/agents/`, etc. v1 is kiln-scoped to bound risk. Path semantics ("relative to agent file" vs "relative to plugin root") decided in v2 if the value of generalization holds up.

#### Out of scope for v1

- Variable substitution in includes (`{insert path.md var=foo}`)
- Conditional includes (`{if SHELL=bash insert ...}`)
- Cross-plugin includes (`{insert plugin:wheel/_shared/x.md}`)
- Recursive includes
- Live-reload / runtime resolution

All of the above are tractable v2 features once the v1 directive + resolver shape is locked.

*(from: `2026-04-25-agent-prompt-includes`)*

## Problem Statement

Agent prompts in this codebase get assembled in two places, and both are currently ad hoc:

1. **At scaffold/build time**, agent `.md` files (`plugin-<name>/agents/<role>.md`) define the agent's identity + tool scope + persistent system-prompt prose. Several kiln agents already duplicate boilerplate — coordination-protocol guidance, citation discipline, scope rules — at the bottom of their files. Every update either touches all of them or accepts drift.

2. **At spawn time**, the calling skill encodes runtime context (which plugin to test, which fixture, which verbs to invoke, which baseline/candidate role-instance) by writing freehand prose into the `Agent` tool's `prompt` parameter. Each skill reinvents the structure. The recently-merged Theme A (typed inputs/outputs) hardened the WORKFLOW step contract but the AGENT spawn contract is still freehand.

The next major work track — `09-research-first` phase — has 7 feature items + 1 goal item that ALL assume some structured way to spawn specialized agents (runners, judges, synthesizers) with task-specific context. Without this PRD's primitives, every research-first PRD will encode tool references in its prompt freehand — exactly the prose-only enforcement that just failed in the obsidian-write step (forbidden MCP tool referenced in instruction text but not enforced).

The two layers compose, but they need to BE primitives before composition is meaningful.

## Goals

- **Compile-time include primitive (Theme B)**: a directive (`<!-- @include path.md -->` recommended) in `plugin-kiln/agents/*.md` files resolves at scaffold time against shared modules. One canonical source for repeated boilerplate. CI gate: compiled output == build(sources).
- **Runtime context-injection primitive (Theme A)**: a composer in `plugin-wheel/scripts/agents/` (extending `resolve.sh` or adding `compose-context.sh`) emits a JSON spec containing `prompt_prefix` (the assembled Runtime Context block) plus `subagent_type` + `model_default`. The calling skill prepends `prompt_prefix` to its task prompt.
- **Closed task-shape vocabulary**: 8 initial shapes (skill / frontend / backend / cli / infra / docs / data / agent) with per-shape stanzas at `plugin-kiln/lib/task-shapes/<shape>.md`. Adding shapes requires a manifest update — no ad hoc proliferation.
- **Plugin manifest `agent_bindings:` extension**: each plugin's `.claude-plugin/plugin.json` declares verb bindings per agent. Validator refuses install if bindings reference unknown verbs. PRD frontmatter MAY override.
- **3 research-first agent.md files**: `research-runner.md`, `fixture-synthesizer.md`, `output-quality-judge.md` shipped with required `tools:` allowlists. These are the prereq deliverables for `09-research-first`.
- **Document the architectural rules** in CLAUDE.md: never use `general-purpose` for specialized roles in production; injection is at prompt layer not system-prompt layer; agent registration is session-bound; plain-text output is invisible to team-lead (always relay via SendMessage).
- **Preserve cache layout**: the include directive resolves at compile time so the agent's runtime system prompt is still a stable string. Anthropic prompt cache treats include-resolved + identity prefix as one ephemeral-cache unit. Don't break this by adding per-spawn variables to include paths.

## Non-Goals (v1)

- **Not** runtime resolution of include directives. Includes resolve at scaffold/build time only. Live-reload is v2 if it ever proves needed.
- **Not** variable substitution inside include directives (`{insert path.md var=foo}`). Pure verbatim concatenation. The runtime Context block is the right layer for variables.
- **Not** conditional includes, recursive includes, or cross-plugin includes (`{insert plugin:wheel/_shared/x.md}`). All v2 candidates if the v1 shape holds up.
- **Not** generalizing the include preprocessor to non-kiln plugins. v1 is kiln-scoped to bound risk. `plugin-wheel/agents/`, `plugin-shelf/agents/`, etc. join in v2.
- **Not** in-session agent registration. Adding `plugin-<name>/agents/<role>.md` mid-session does NOT make it spawnable. This is a Claude Code harness constraint, not something we can change here. Documented as a constraint, not a goal.
- **Not** tools-frontmatter enforcement testing in this PRD (Test 2 from the proof-of-concept). Requires session restart. Queued separately.
- **Not** retroactively refactoring every existing kiln agent. v1 refactors 2-3 (e.g., qa-engineer, prd-auditor, debugger) to validate the include pattern. Broader rollout is incremental.

## Requirements

### Functional Requirements

#### Theme B — Compile-time include preprocessor (`agent-prompt-includes`)

- **FR-B-1** (from: `.kiln/roadmap/items/2026-04-25-agent-prompt-includes.md`): The preprocessor resolves directives in `plugin-kiln/agents/*.md` files at scaffold time (via `plugin-kiln/bin/init.mjs`) AND/OR build time (via a compile script run from `plugin-kiln/`). Hybrid approach recommended in spec phase.
- **FR-B-2**: Directive syntax is `<!-- @include path.md -->` (HTML-comment-safe, won't break markdown rendering, mirrors mdx-prompt / POML conventions). Path is relative to a documented anchor (resolution context locked in spec phase).
- **FR-B-3**: Shared modules live at `plugin-kiln/agents/_shared/<name>.md` (underscore-prefix for visual distinction from spawnable agents). Alternative `plugin-kiln/templates/agent-modules/<name>.md` deferred to plan-phase taste decision.
- **FR-B-4**: Resolver is implemented in pure Bash + sed + cat at `plugin-kiln/scripts/agent-includes/resolve.sh`. Approximately 50 lines. Single-pass — NO recursion in v1.
- **FR-B-5**: At least one shared module ships in v1: `plugin-kiln/agents/_shared/coordination-protocol.md` containing the SendMessage-relay-results boilerplate currently duplicated across team-mode agents.
- **FR-B-6**: 2-3 existing kiln agents (e.g., `qa-engineer.md`, `prd-auditor.md`, `debugger.md`) are refactored to use the include directive. No behavioral regression — agents continue to function identically post-refactor.
- **FR-B-7**: CI check verifies that compiled output matches build(sources). Fails the build if sources and compiled outputs drift.
- **FR-B-8**: Document the directive syntax + resolver location + module convention in CLAUDE.md "Active Technologies" + the feature plan.md.

#### Theme A — Runtime context-injection composer (`agent-spawn-context-injection-layer`)

- **FR-A-1** (from: `.kiln/roadmap/items/2026-04-24-agent-spawn-context-injection-layer.md`): A composer in `plugin-wheel/scripts/agents/` (extending `resolve.sh` or sibling `compose-context.sh`) accepts: `agent_name`/path, `plugin_id`, `task_spec` JSON (task_shape + task_summary + variables + axes), optional `prd_path`. Emits JSON `{subagent_type, prompt_prefix, model_default}`.
- **FR-A-2**: The composer pulls and assembles into `prompt_prefix`: `WORKFLOW_PLUGIN_DIR` (existing Option B mechanism), task_shape + task_summary, variable bindings, verb bindings (manifest defaults + PRD overrides), per-shape stanza, coordination-protocol stanza (always for team-mode spawns).
- **FR-A-3**: The calling skill is responsible for prepending `prompt_prefix` to its actual task prompt before passing to the `Agent` tool's `prompt` parameter. Composer does NOT call `Agent` itself.
- **FR-A-4**: A closed task-shape vocabulary is established. Initial 8 shapes: `skill`, `frontend`, `backend`, `cli`, `infra`, `docs`, `data`, `agent`. The `agent` shape's necessity is decided during implementation (open question).
- **FR-A-5**: Per-shape stanzas live at `plugin-kiln/lib/task-shapes/<shape>.md`. Each is 5-15 lines of curated guidance.
- **FR-A-6**: Adding a new task shape requires a manifest update — NOT ad hoc. Closed-vocabulary discipline.
- **FR-A-7**: `plugin-<name>/.claude-plugin/plugin.json` schema gains an `agent_bindings:` field declaring per-agent verb bindings. Validator refuses plugin install if bindings reference verbs not in the closed vocabulary for that agent's role.
- **FR-A-8**: The closed verb namespace ships v1 with at minimum: `verify_quality`, `run_baseline`, `run_candidate`, `measure`, `synthesize_fixtures`, `judge_outputs`. Final list pinned in spec phase.
- **FR-A-9**: PRD frontmatter MAY override per-PRD via `agent_binding_overrides:` (same shape, narrower scope). Validator refuses PRD if overrides reference unknown agents or verbs.
- **FR-A-10**: 3 minimal agent.md files ship under `plugin-kiln/agents/`: `research-runner.md`, `fixture-synthesizer.md`, `output-quality-judge.md`. Each carries a `tools:` allowlist (REQUIRED — see allowlists in implementation hints). NO `model:` (workflow step decides per FR-B1..B3 already shipped in `build/wheel-as-runtime-20260424`).
- **FR-A-11**: Each shipped agent.md body is pure role identity. NO verb tables (those come from runtime context). NO tool references. NO model selection. NO step-by-step task prose (orchestrator's job).
- **FR-A-12**: Document the architectural rules in CLAUDE.md: (a) never use `general-purpose` for specialized roles in production; (b) one role per registered subagent_type, multiple spawns per run with different injected variables; (c) injection is prompt-layer NOT system-prompt-layer; (d) top-level orchestration is correct, not nested (nested Agent calls are reduced); (e) agent registration is session-bound; (f) plain-text output is invisible to team-lead — always relay via SendMessage.

### Non-Functional Requirements

- **NFR-1 (Cache layout preservation)**: The include resolver MUST resolve at compile time, so the agent's runtime system prompt is a stable string. Anthropic prompt cache must continue to treat include-resolved + identity prefix as a single ephemeral-cache unit. Adding per-spawn variables to include directives is FORBIDDEN — that breaks the cache layout. Per-spawn variability is the runtime composer's job.
- **NFR-2 (Backward compatibility — Theme B)**: Agents that do NOT use the include directive continue to work unchanged. Resolver is a no-op for files without directives.
- **NFR-3 (Backward compatibility — Theme A)**: Skills that do NOT call the composer continue to spawn agents the way they do today. The composer is opt-in for callers that want it.
- **NFR-4 (Atomic shipment)**: Theme A and Theme B ship together (one commit OR one squash-merged PR per Path B precedent from PRs #166, #168). They're framed as one architecture; shipping them separately would create a half-state.
- **NFR-5 (Tools-allowlist enforcement deferred)**: Test 2 from the proof-of-concept (verifying that agent.md `tools:` frontmatter is enforced by the harness) requires session restart. NOT in this PRD's scope. Documented as a queued follow-on.
- **NFR-6 (Live-substrate verification)**: The composer's output for known inputs must produce a deterministic JSON spec. The resolver's compile output must be byte-identical for unchanged sources. Both verified by run.sh-only fixtures (substrate hierarchy tier-2).
- **NFR-7 (No `general-purpose` in production)**: This is a documentation + review discipline, not a code-enforced rule. CLAUDE.md MUST state it explicitly. Reviewers MUST flag any production code path that spawns `general-purpose` for a specialized role.

## User Stories

- **As a kiln agent author**, I want to write `<!-- @include _shared/coordination-protocol.md -->` at the bottom of my agent.md file so I don't have to copy-paste the SendMessage-relay boilerplate that the next agent author also won't want to copy-paste.
- **As a skill author orchestrating agent spawns** (e.g., the future research-first skill), I want to call a composer that emits a `prompt_prefix` containing the resolved Runtime Context block so I don't have to assemble verb tables, variable bindings, and coordination protocol prose by hand for every spawn.
- **As a research-first PRD author**, I want to declare `agent_binding_overrides:` in my PRD frontmatter and have the composer + validator handle the rest, so my PRD's agent task prompts stay focused on what's specific to MY PRD instead of restating the full agent contract.
- **As a plugin reviewer**, I want CI to fail the build if compiled agent.md outputs drift from sources, so we can't accidentally ship a refactored agent that didn't get re-compiled.
- **As an LLM agent reading the Anthropic cache logs**, I want the agent.md system prompt to be byte-identical across every spawn (no per-call variability) so the include-resolved prefix lives in the ephemeral cache and we don't pay for re-encoding it on every spawn.
- **As the kiln team-lead spawning a research-runner**, I want the spawn pattern documented as "same registered subagent_type, different name + different injected variables" so I don't accidentally invent role-per-agent-type and bloat the registry.

## Success Criteria

- **SC-1 (Theme B include directive works end-to-end)**: An agent .md file with `<!-- @include _shared/coordination-protocol.md -->` at the bottom resolves to a complete agent.md during scaffold (or build), AND 2-3 existing kiln agents are refactored to use the directive without behavioral regression. Verified by a run.sh fixture under `plugin-kiln/tests/`.
- **SC-2 (Theme B CI gate)**: A test run that mutates a source agent.md file without re-compiling (or vice-versa) fails the CI compiled-equals-build check.
- **SC-3 (Theme A composer emits valid JSON)**: For a known input (`plugin_id=kiln`, `agent_name=research-runner`, sample `task_spec`), the composer emits a JSON spec with the documented schema (`subagent_type`, `prompt_prefix`, `model_default`). Verified by a run.sh fixture under `plugin-wheel/tests/`.
- **SC-4 (Theme A validator catches unknown verb)**: A plugin manifest with an `agent_bindings:` entry referencing a verb not in the closed namespace is REFUSED at install time with a clear error. Verified by a fixture.
- **SC-5 (Theme A validator catches unknown agent in PRD override)**: A PRD with `agent_binding_overrides:` referencing an agent not declared in the manifest is REFUSED at distill/build time with a clear error.
- **SC-6 (3 research-first agents shipped)**: `plugin-kiln/agents/research-runner.md`, `fixture-synthesizer.md`, `output-quality-judge.md` exist with required `tools:` allowlists, role-identity-only bodies (no verb tables, no tool references, no model, no task prose), and a passing fixture that asserts each agent.md is structurally valid.
- **SC-7 (Cache layout preserved)**: A spot check confirms that an agent's resolved system prompt is byte-identical across two consecutive spawns (no per-call variability leaked from the include resolver into runtime).
- **SC-8 (CLAUDE.md documents architectural rules)**: The 6 rules from FR-A-12 are documented in CLAUDE.md "Active Technologies" or a sibling section. Reviewers can grep for them.

## Tech Stack

Inherited from the parent product:

- Bash 5.x + `sed` + `cat` + `jq` + POSIX utilities — no new languages or runtimes.
- The Theme B resolver is `plugin-kiln/scripts/agent-includes/resolve.sh` (~50 lines).
- The Theme A composer extends `plugin-wheel/scripts/agents/resolve.sh` OR adds sibling `compose-context.sh`. Decision in spec phase.
- Per-shape stanzas live at `plugin-kiln/lib/task-shapes/<shape>.md` (markdown).
- 3 new agent.md files at `plugin-kiln/agents/` (markdown with frontmatter).
- Plugin manifest `agent_bindings:` extension is JSON schema in existing `plugin-<name>/.claude-plugin/plugin.json` files.
- CI hook + fixtures use the `run.sh`-only pattern (substrate hierarchy tier-2 per the new §Implementer Prompt rule).

No new dependencies.

## Risks & Open Questions

- **R-1 (Closed-vocabulary scope creep)**: Both the task-shape enum (FR-A-4) and the verb namespace (FR-A-8) are governance decisions. Get them wrong and either (a) shapes/verbs proliferate ad hoc and the contract erodes, or (b) the contract is too rigid and consumers route around it. **Mitigation**: ship with conservative initial sets, document the gate process for additions (manifest update, not ad hoc), accept that v1 will need at least one revision based on real usage.
- **R-2 (Include resolver edge cases)**: Markdown files with literal `<!--` content (e.g., HTML comment examples in agent prose) could trigger false-positive directive matches. **Mitigation**: spec phase pins the exact regex; resolver MUST distinguish "directive" from "prose containing directive-shaped text". Recursion is forbidden in v1, so a directive inside a shared module is an error.
- **R-3 (Composer-skill integration footprint)**: The composer is opt-in (NFR-3) but for `09-research-first` to actually use it, the orchestrating skill MUST call the composer + prepend `prompt_prefix` consistently. If even one research-first skill bypasses the composer, the contract erodes. **Mitigation**: ship a documented integration recipe alongside the composer. Treat first research-first PRD's specifier as the canonical reviewer for composer usage.
- **R-4 (PRD-override schema drift)**: `agent_binding_overrides:` in PRD frontmatter is a new schema surface. If we don't lock the shape in spec, every research-first PRD will invent its own override syntax. **Mitigation**: pin the schema in `specs/<feature>/contracts/interfaces.md`; validator catches malformed entries.
- **OQ-1 (BLOCKING — must resolve in spec phase)**: Theme B resolution timing — pure scaffold-time (init.mjs), pure build-time (committed compiled outputs), or hybrid? Implementation hints recommend hybrid; spec phase commits.
- **OQ-2 (BLOCKING — must resolve in spec phase)**: Theme B directive syntax. Recommend `<!-- @include path.md -->` per implementation hints. Other candidates documented. Spec phase decides + pins in contracts.
- **OQ-3**: Is the `agent` task shape (FR-A-4) legitimately needed up front, or speculative? Decide during implementation; defaults to "include in v1" unless evidence emerges otherwise.
- **OQ-4**: Theme A — does the composer extend `plugin-wheel/scripts/agents/resolve.sh` or live as a sibling `compose-context.sh`? Spec phase decides based on whether `resolve.sh`'s existing surface fits the new responsibilities.
- **OQ-5**: Theme B — do shared modules live at `plugin-kiln/agents/_shared/<name>.md` (recommended) or `plugin-kiln/templates/agent-modules/<name>.md`? Defer to plan-phase taste; both are fine.

## Pipeline guidance

Single PRD bundling two themes. Recommend:

- **Specifier** produces spec + plan + interface contracts (resolver signature for Theme B, composer signature + agent_bindings JSON schema for Theme A, task-shape stanza format, directive syntax + resolution-timing decisions, the closed verb namespace) + tasks. Resolves OQ-1 / OQ-2 / OQ-4 first as blocking research questions.
- **Researcher (lightweight)** if needed — but most likely no external research; the architectural validation is already in the implementation hints (4 tests + live demo from 2026-04-24). Per the new §1.5 Baseline Checkpoint rule from issue #170 fix: there are no quantitative SC items here, so no baseline capture required.
- **2 implementers in parallel** (one per theme — they touch different files, can ship in parallel):
  - **`impl-include-preprocessor`** (Theme B): `plugin-kiln/scripts/agent-includes/resolve.sh`, the shared module, refactored agents, CI check, init.mjs / build-script integration. Smaller scope, validates the include pattern first.
  - **`impl-runtime-composer`** (Theme A): composer in `plugin-wheel/scripts/agents/`, task-shape stanzas, `agent_bindings:` schema + validator, 3 research-first agent.md files, CLAUDE.md doc updates.
  - Per the new §Implementer Prompt rule: cite kiln-test substrate FIRST when authoring fixtures. For run.sh-only fixtures, invoke directly via `bash` and cite exit code + PASS summary.
- **No qa-engineer** (no visual surface).
- **Auditor** verifies: SC-1..SC-8 each satisfied; FR-A and FR-B coverage by fixture; atomic shipment per NFR-4 (single PR via Path B); architectural rules documented in CLAUDE.md (FR-A-12 grep gate). Per the new §Auditor Prompt — Live-Substrate-First Rule: reach for the run.sh fixtures directly, no structural surrogates.
- **Retrospective** analyzes whether the unified-PRD framing actually helped vs. hurt — the items were authored separately and the user explicitly corrected the agent's initial split. Was bundling worth it? Did the two implementers hit coordination friction the separate-PRDs path would have avoided?
