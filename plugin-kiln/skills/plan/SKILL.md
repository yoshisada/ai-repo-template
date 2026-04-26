---
name: plan
description: Generate technical implementation plans from feature specifications.
  Use after creating a spec to define architecture, tech stack, and implementation
  phases. Creates plan.md with detailed technical design.
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: templates/commands/plan.md
---

# Kiln Plan Skill

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before planning)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_plan` key
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- For each executable hook, output the following based on its `optional` flag:
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Pre-Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```
  - **Mandatory hook** (`optional: false`):
    ```
    ## Extension Hooks

    **Automatic Pre-Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}

    Wait for the result of the hook command before proceeding to the Outline.
    ```
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently

## Outline

1. **Setup**: Run `.specify/scripts/bash/setup-plan.sh --json` from repo root and parse JSON for FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, BRANCH. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load context**: Read FEATURE_SPEC and `.specify/memory/constitution.md`. Load IMPL_PLAN template (already copied).

3. **Execute plan workflow**: Follow the structure in IMPL_PLAN template to:
   - Fill Technical Context (mark unknowns as "NEEDS CLARIFICATION")
   - Fill Constitution Check section from constitution
   - Evaluate gates (ERROR if violations unjustified)
   - Phase 0: Generate research.md (resolve all NEEDS CLARIFICATION)
   - Phase 1: Generate data-model.md, contracts/, quickstart.md
   - Phase 1: Update agent context by running the agent script
   - Re-evaluate Constitution Check post-design

4. **Stop and report**: Command ends after Phase 2 planning. Report branch, IMPL_PLAN path, and generated artifacts.

5. **Check for extension hooks**: After reporting, check if `.specify/extensions.yml` exists in the project root.
   - If it exists, read it and look for entries under the `hooks.after_plan` key
   - If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally
   - Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
   - For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
     - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
     - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
   - For each executable hook, output the following based on its `optional` flag:
     - **Optional hook** (`optional: true`):
       ```
       ## Extension Hooks

       **Optional Hook**: {extension}
       Command: `/{command}`
       Description: {description}

       Prompt: {prompt}
       To execute: `/{command}`
       ```
     - **Mandatory hook** (`optional: false`):
       ```
       ## Extension Hooks

       **Automatic Hook**: {extension}
       Executing: `/{command}`
       EXECUTE_COMMAND: {command}
       ```
   - If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently

## Phases

### Phase 0: Outline & Research

1. **Extract unknowns from Technical Context** above:
   - For each NEEDS CLARIFICATION → research task
   - For each dependency → best practices task
   - For each integration → patterns task

2. **Generate and dispatch research agents**:

   ```text
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen]
   - Alternatives considered: [what else evaluated]

**Output**: research.md with all NEEDS CLARIFICATION resolved

### Phase 1: Design & Contracts

**Prerequisites:** `research.md` complete

1. **Extract entities from feature spec** → `data-model.md`:
   - Entity name, fields, relationships
   - Validation rules from requirements
   - State transitions if applicable

2. **Define interface contracts** (if project has external interfaces) → `/contracts/`:
   - Identify what interfaces the project exposes to users or other systems
   - Document the contract format appropriate for the project type
   - Examples: public APIs for libraries, command schemas for CLI tools, endpoints for web services, grammars for parsers, UI contracts for applications
   - Skip if project is purely internal (build scripts, one-off tools, etc.)

3. **Agent context update**:
   - Run `.specify/scripts/bash/update-agent-context.sh claude`
   - These scripts detect which AI agent is in use
   - Update the appropriate agent-specific context file
   - Add only new technology from current plan
   - Preserve manual additions between markers

**Output**: data-model.md, /contracts/*, quickstart.md, agent-specific file

### Phase 1.5: Research-first plan-time agents

This phase ships with `specs/research-first-plan-time-agents/` (see plan.md Decision 1 + 2 — single edit point). It is invoked unconditionally on every `/plan` run AFTER Phase 1; the **skip-path is a structural no-op** so PRDs that declare neither feature pay zero net-new agent spawns and no net-new subprocess beyond the spawn-or-skip probe (NFR-006a + NFR-006b).

**Skip-path probe constraint (NFR-006a + NFR-006b — RECONCILED 2026-04-25)**: the skip-path detector is a single jq lookup on already-parsed JSON when available OR a single `grep -E` on the raw PRD path otherwise — NEVER a fresh python3 / jq cold-fork solely for the probe. Implemented at `plugin-kiln/scripts/research/probe-plan-time-agents.sh` (~50 LoC). Asserted by `plugin-kiln/tests/plan-time-agents-skip-perf/`.

**Step 1 — Probe**:

```bash
# If Phase 0 / Phase 1 already parsed the PRD frontmatter into a JSON file,
# pass --frontmatter-json <path> to skip the grep fallback. Otherwise the
# probe will single-grep the raw PRD file.
ROUTE=$(bash "$WORKFLOW_PLUGIN_DIR/../plugin-kiln/scripts/research/probe-plan-time-agents.sh" \
  --prd "$PRD_PATH" \
  ${PRD_FRONTMATTER_JSON_PATH:+--frontmatter-json "$PRD_FRONTMATTER_JSON_PATH"})
# ROUTE ∈ {synthesizer, judge, both, skip}
```

If `ROUTE == skip`: return immediately. NO spawn. NO net-new subprocess. NO further work in Phase 1.5.

**Step 2 — Synthesizer path** (when `ROUTE` ∈ {`synthesizer`, `both`}, i.e. `fixture_corpus: synthesized`):

1. **Schema pre-check (FR-003)** — verify `plugin-<skill-plugin>/skills/<skill>/fixture-schema.md` exists. If not, halt with `Bail out! fixture-schema-missing: <expected-path>`. Do NOT spawn the synthesizer if the schema is missing.

2. **Spawn via composer recipe (CLAUDE.md "Composer integration recipe")**:

   ```bash
   SPEC_JSON=$(bash "$WORKFLOW_PLUGIN_DIR/scripts/agents/resolve.sh" kiln:fixture-synthesizer)
   SUBAGENT_TYPE=$(jq -r .subagent_type <<<"$SPEC_JSON")
   PREFIX=$(bash "$WORKFLOW_PLUGIN_DIR/scripts/agents/compose-context.sh" \
     --agent-name fixture-synthesizer \
     --plugin-id kiln \
     --task-spec /tmp/fixture-synth-spec.json \
     --prd-path "$PRD_PATH" | jq -r .prompt_prefix)
   # The Agent({...}) call is made by /plan with subagent_type=$SUBAGENT_TYPE
   # and prompt = "$PREFIX\n---\n<per-call task>". name="synth-<prd-slug>".
   ```

   Role-instance variables per `specs/research-first-plan-time-agents/contracts/interfaces.md §6`: `skill_id`, `empirical_quality`, `schema_path`, `target_count` (= `min_fixtures` from rigor row), `proposed_corpus_dir` (= `<repo-root>/.kiln/research/<prd-slug>/corpus/proposed/`), `prd_slug`, `existing_fixtures_summary` (empty list on initial spawn).

3. **Per-fixture confirm-never-silent review (FR-005)** — after the synthesizer relays success, render each `proposed/fixture-NNN.md` with its 3-line summary header and prompt the user with: `accept | reject [reason] | edit | accept-all | abandon`. No fixture is moved to the committed path without an explicit accept (per-fixture or via `accept-all`). `abandon` aborts Phase 1.5 — proposed-corpus directory is preserved for inspection.

4. **Reject-then-regenerate (FR-006)** — on `reject`, re-spawn the synthesizer with regenerate role-instance vars: `rejection_reason`, `rejected_fixture_summary`, `regeneration_attempt` (1-indexed), `target_fixture_id`. Bounded by `max_regenerations` per fixture (default 3, frontmatter-overridable via `max_regenerations: <int>`). On exhaustion (regeneration_attempt > max_regenerations) halt with `Bail out! regeneration-exhausted: fixture-<id> rejected <N> times`.

5. **Finalize (FR-007)** — on `accept-all` or full per-fixture acceptance, MOVE accepted fixtures from `proposed/` to one of:
   - `.kiln/research/<prd-slug>/corpus/` when `promote_synthesized: false` (default — one-off per-PRD scratch).
   - `plugin-<skill-plugin>/fixtures/<skill>/corpus/` when `promote_synthesized: true` (committed shared corpus).

   Pre-write collision check on the promotion target — bail with `Bail out! promotion-collision: <existing-path>` if the target file already exists.

6. **Synthesis report (FR-007 + NFR-009)** — write `.kiln/research/<prd-slug>/synthesis-report.md` logging per-fixture which target path was used + the regeneration counter so token spend is auditable. Header: `Regeneration budget used: <N>/<corpus_size × max_regenerations>`.

**Step 3 — Judge path** (when `ROUTE` ∈ {`judge`, `both`}, i.e. PRD declares an `empirical_quality[].metric: output_quality` axis):

The judge is NOT spawned by `/plan` directly. The judge spawn happens INSIDE `plugin-wheel/scripts/harness/evaluate-output-quality.sh` (which is invoked downstream by the per-axis gate in `specs/research-first-axis-enrichment/contracts/interfaces.md §4`). `/plan`'s job at this phase is to ensure the orchestrator's prerequisites are in place:

1. **Resolve `judge-config.yaml` (FR-014, two-path resolution per Decision 4)**:
   1. `<repo-root>/.kiln/research/judge-config.yaml` (per-developer override; gitignored).
   2. `<repo-root>/plugin-kiln/lib/judge-config.yaml.example` (committed default).
   3. Else halt with `Bail out! judge-config-missing: looked at .kiln/research/judge-config.yaml + plugin-kiln/lib/judge-config.yaml.example`.

2. **Verify rubric_verbatim available** — `parse-prd-frontmatter.sh` (extended in T005 / FR-010) already validated that every `metric: output_quality` entry has a non-empty `rubric:`. This is a guard against late-stage drift; the validator's exit code is the source of truth.

3. **Surface the banner** — print `Pinned judge model: <model> (source: <local-config | example-fallback>)` so the human reviewer sees the resolved config before downstream gate-eval runs the judge.

**Step 4 — Mock-injection contract (CLAUDE.md Rule 5)**: agents shipped in this PR are NOT live-spawnable in the same session. Test fixtures under `plugin-kiln/tests/` set `KILN_TEST_MOCK_SYNTHESIZER_DIR` / `KILN_TEST_MOCK_JUDGE_DIR` to inject pre-baked envelopes; the same env-var pattern is honored by `evaluate-output-quality.sh` and by Phase 1.5 review-loop helpers. Live-spawn validation is the auditor's first follow-on activity in Task #3.

## Wheel-workflow guidance (FR-B3)

If the plan emits wheel workflow JSON for any agent step, pick the `model:` tier explicitly rather than relying on the harness default. Rule of thumb:

- **`haiku`** — classification / pattern-match / routing steps.
- **`sonnet`** — synthesis, drafting, most multi-file work.
- **`opus`** — hard reasoning only (architecture decisions, thorny debugging, long-context synthesis where the cost is justified).

Absent `model:` = harness default, byte-identical to pre-`model:` workflows. Mismatches (unrecognized tier or malformed id) fail loudly — never silent fallback. See `plugin-wheel/README.md#per-step-model-selection`.

## Key rules

- Use absolute paths
- ERROR on gate failures or unresolved clarifications
