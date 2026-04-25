---
id: 2026-04-24-agent-spawn-context-injection-layer
title: "Agent spawn context-injection layer — Runtime Context block at the prompt layer (prereq for 09-research-first)"
kind: feature
date: 2026-04-24
status: open
phase: 08-in-flight
state: planned
blast_radius: cross-cutting
review_cost: careful
context_cost: 4 sessions
implementation_hints: |
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

  ## Architectural constraints documented (from proof-of-concept)

  - **NEVER use `general-purpose` for specialized roles.** This is the most important rule. The
    proof-of-concept demo spawned baseline/candidate teammates as `general-purpose` because newly-
    authored agent.md files can't be tested in-session (Test 2). That was a DEMO SHORTCUT, NOT the
    production pattern. `general-purpose` has every tool — a research-runner running on it can
    write files, edit code, spawn nested agents, call any MCP. Identity-via-injection alone gives
    role differentiation but ZERO structural tool scoping. Production requires registered specialized
    subagent_types with `tools:` allowlists in their .md frontmatter. Deliverable #4 below ships those.

  - **One role per registered subagent_type, multiple spawns per run.** The architecture is NOT
    "different role → different agent type." It's "ONE registered role (e.g., `kiln:research-runner`)
    spawned MULTIPLE TIMES in parallel with different injected variables (PLUGIN_DIR_UNDER_TEST
    differs between baseline and candidate spawns)." Same agent identity, same tool scope, different
    task input. The team-instance `name` parameter (e.g., "baseline-runner", "candidate-runner") is
    a label for coordination, not a different identity.

  - **Injection is at the prompt layer, NOT the system-prompt layer.** The harness does not expose
    a per-spawn system-prompt mutation surface. The Runtime Context block is PREPENDED to the
    `prompt` parameter; the agent.md system prompt remains unchanged. This is fine — agent.md
    holds role identity (with tool scoping), prompt-layer holds runtime context. They compose.

  - **Top-level orchestration is the right pattern, not nested.** Because nested Agent calls are
    reduced (no specialized subagent_types, no model override, no run_in_background), multi-agent
    research-first MUST orchestrate at the SKILL level (the skill spawns siblings). A research-runner
    role does not nest other agents; it coordinates results that the skill aggregates.

  - **Agent registration is session-bound.** New `plugin-<name>/agents/<role>.md` files register at
    session start. Adding agents on-the-fly within a session does NOT make them spawnable until
    next start. Implication: research-first agents MUST ship with the plugin (kiln, etc.) — they
    cannot be created at PRD time.

  - **Plain-text output is invisible to team-lead.** Teammates MUST relay results via SendMessage.
    This is a load-bearing convention: every team-mode role-prose AND every per-shape stanza must
    include "Relay your final structured result via SendMessage to team-lead before going idle."

  ## Scope (4 deliverables)

  ### 1. Runtime Context block composer (the new infrastructure)

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

  Caller (the skill) is responsible for taking `prompt_prefix` and prepending it to the actual task
  prompt before passing to Agent tool's `prompt` parameter.

  ### 2. Closed task-shape vocabulary + per-shape stanzas

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

  Adding shapes requires a manifest update. Open question: is `agent` legitimately needed up front
  or speculative? Decide during implementation.

  ### 3. Plugin manifest extension for agent_bindings

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

  Validator: refuse plugin install if agent_bindings reference verbs not in the closed vocabulary
  for the agent's role. Closed verb namespace TBD during implementation; initial set:
    verify_quality, run_baseline, run_candidate, measure, synthesize_fixtures, judge_outputs

  PRD frontmatter MAY override per-PRD via `agent_binding_overrides:` — same shape, narrower scope.
  Validator: refuse PRD if overrides reference unknown agents or verbs.

  ### 4. Author 3 minimal agent .md files for research-first (each with REQUIRED tools allowlist)

  Per native Claude Code agent.md format:
    plugin-kiln/agents/research-runner.md
    plugin-kiln/agents/fixture-synthesizer.md
    plugin-kiln/agents/output-quality-judge.md

  Frontmatter: name + description + **tools** (REQUIRED — see allowlist sketch below). NO `model`
  — workflow step decides per FR-B1..B3 (already shipped in build/wheel-as-runtime-20260424).

  Body: pure role identity. NO verb tables (those come from runtime context). NO tool references
  (same). NO model selection. NO step-by-step task prose (that's the orchestrator's job — the
  skill writes the task prompt and prepends the Runtime Context block).

  ### Tools allowlists — proposed for v1, refine in plan/spec

    research-runner:        Read, Bash, SendMessage, TaskUpdate, TaskList
                            (read fixture content, invoke verify_quality verbs via Bash, relay
                             results, manage shared task list. NO Write/Edit — research is
                             read-only against candidate. NO Agent — no nested spawns. NO MCP.)

    fixture-synthesizer:    Read, Write, SendMessage, TaskUpdate
                            (read skill schema, write proposed fixtures to .kiln/research/<prd>/
                             corpus/proposed/, relay summary. NO Bash — synthesis is text-only.
                             NO Agent — no nested spawns. NO MCP.)

    output-quality-judge:   Read, SendMessage, TaskUpdate
                            (read paired baseline/candidate outputs + rubric, relay verdict.
                             NO Bash, NO Write/Edit, NO Agent, NO MCP. Judge is the most
                             tightly-scoped role for anti-drift reasons — it can't write files,
                             can't run shell, can't spawn anything. Verdict via SendMessage only.)

  ### Spawn pattern — what the orchestrator does at spawn time

    Agent({
      subagent_type: "kiln:research-runner",       ← registered, tool-scoped
      model: "haiku",                                 ← from workflow JSON step's `model:`
      team_name: "research-first-<prd-slug>",
      name: "baseline-runner",                        ← INSTANCE label, not identity
      prompt: "<Runtime Context block>\n---\n<task>"  ← composer output + actual task
    })

  Same `subagent_type` is spawned twice (with name="baseline-runner" and name="candidate-runner")
  — same identity, same tool scope, DIFFERENT injected variables. NEVER spawn `general-purpose`
  for specialized roles in production. Documented as the load-bearing rule.

  ### Example research-runner.md (illustrative — < 10 lines body)

    ---
    name: research-runner
    description: Reports empirical metrics for a baseline or candidate plugin against a fixture, given runtime-injected role variables.
    tools: Read, Bash, SendMessage, TaskUpdate, TaskList
    ---

    You are the research-runner. Your job: report empirical metrics for a baseline or candidate
    plugin against a fixture. The Runtime Environment block above tells you which role-instance
    you are (baseline or candidate), which plugin-dir to test, and which fixture to run. Use the
    verbs listed there to do the work — don't infer tools yourself, don't read source code.
    When done, relay your structured result via SendMessage to team-lead before going idle.
    Do not retry on failure; report it.

## What

Build the resolver-side composer that assembles a `## Runtime Environment` block from plugin manifest verb-bindings + PRD overrides + task-shape stanza, and have the spawning skill prepend it to the Agent tool's `prompt` parameter. Author the 3 minimal agent.md files for research-first. Document the architectural constraints (top-level orchestration, prompt-layer injection, session-bound registration, SendMessage relay convention).

## Why now

Phase `09-research-first` has 7 feature items + 1 goal item, ALL of which assume some mechanism for spawning specialized agents (runners, judges, synthesizer) with task-specific context. Without this prereq, every research-first agent has to encode tool references in its prompt — exactly the prose-only enforcement that just failed in the obsidian-write step (forbidden MCP tool referenced in instruction text but not enforced).

Vision-aligned bonus: this enables language-agnostic plugin support. A future CLI plugin's manifest declares CLI-substrate verb bindings; same research-runner agent works against it without code change.

## Hardest part

The closed task-shape enum + closed verb namespace. Both are governance decisions. Get them wrong and either (a) shapes/verbs proliferate ad-hoc and the contract erodes, or (b) the contract is too rigid and consumers route around it. Mitigation: ship with conservative initial sets, document the gate process for adding new ones (manifest update, not ad-hoc), and accept that v1 will need at least one revision based on real usage.

## Cheaper version

Drop deliverable #3 (plugin manifest extension). Inline verb bindings into PRD frontmatter only. Means every research-first PRD restates the verb table — repetitive but functional. Saves the manifest schema work. Revise to manifest-default + PRD-override once we've seen 3-5 real research PRDs. This is the recommended v1 if scope pressure hits.

## Dependencies

- Depends on `build/wheel-as-runtime-20260424` (already shipped) — Option B WORKFLOW_PLUGIN_DIR templating, agent centralization (FR-A1..A5), per-step model selection (FR-B1..B3).
- Blocks: every item in `09-research-first` (the phase). Specifically, items #4 (fixture-synthesizer) and #5 (output-quality-judge) directly depend on minimal agent .md files existing.
- Does NOT block tools-allowlist enforcement (that's a separate queued item).
