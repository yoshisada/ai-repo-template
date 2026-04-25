# Feature Specification: Agent Prompt Composition — Two Layers, One Architecture

**Feature Branch**: `build/agent-prompt-composition-20260425`
**Created**: 2026-04-25
**Status**: Draft
**Input**: `docs/features/2026-04-25-agent-prompt-composition/PRD.md`

## Overview

Agent prompts in this codebase get assembled at two layers, both currently ad hoc. **Theme B (compile-time include preprocessor)** introduces a directive (`<!-- @include path.md -->`) in `plugin-kiln/agents/*.md` files that resolves at scaffold/build time against shared modules — eliminating copy-paste boilerplate while preserving Anthropic prompt-cache layout. **Theme A (runtime context-injection composer)** introduces a JSON-emitting composer in `plugin-wheel/scripts/agents/` that callers (orchestrating skills) use to assemble a structured `prompt_prefix` with `WORKFLOW_PLUGIN_DIR`, task_shape, variable bindings, verb bindings, per-shape stanza, and coordination protocol — replacing freehand prose in `Agent` tool spawns.

Both layers compose: agent.md = (role identity) + {compile-time include of shared trailer} → static system prompt; spawn = (Runtime Environment block from composer) + (task) → per-call prompt. They ship together (NFR-4 — atomic, single squash-merged PR).

The PRD bundles two themes deliberately. The two implementer tracks (`impl-include-preprocessor` and `impl-runtime-composer`) touch **disjoint files** by design; FR partitioning into Theme A vs Theme B buckets in this spec is the file-conflict-prevention contract.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Compile-time include directive eliminates boilerplate (Priority: P1)

A kiln agent author wants to add the same SendMessage-relay-results coordination boilerplate to a new agent.md file without copy-pasting the same 5–10 lines that already live at the bottom of three other agents. Today every team-mode agent duplicates this prose; every update either touches all of them or accepts drift.

**Why this priority**: P1 because it's the smaller of the two themes, validates the overall composition story (compile-time stable prefix + runtime-injected variables), and unblocks Theme A's CLAUDE.md doc updates which reference the include pattern.

**Independent Test**: Refactor 2–3 existing kiln agents (e.g., `qa-engineer.md`, `prd-auditor.md`, `debugger.md`) to replace inline coordination prose with `<!-- @include _shared/coordination-protocol.md -->`. Run the resolver via the CI gate. Assert (a) compiled output contains the expanded prose at the directive site, (b) compiled output is byte-identical across two consecutive runs (cache-layout invariant — SC-7), (c) refactored agents continue to function identically when spawned (no behavioral regression).

**Acceptance Scenarios**:

1. **Given** an agent.md file with `<!-- @include _shared/coordination-protocol.md -->` on a line by itself, **When** the resolver runs, **Then** the directive line is replaced byte-for-byte by the contents of `plugin-kiln/agents/_shared/coordination-protocol.md` and emitted to the consumer install path / committed compiled output (per FR-B-1 hybrid).
2. **Given** an agent.md file with NO directive, **When** the resolver runs, **Then** output is byte-identical to input (NFR-2, no-op for un-directived files).
3. **Given** the resolver is invoked twice on the same source with no source changes, **When** outputs are compared, **Then** they are byte-identical (NFR-1 cache-layout preservation, SC-7).
4. **Given** a source agent.md that mutates without re-compiling (or vice-versa), **When** CI runs the compiled-equals-build check, **Then** CI fails with a clear diagnostic naming the drifted file (SC-2).
5. **Given** a shared module that itself contains a directive (recursion attempt), **When** the resolver runs, **Then** it exits non-zero with a diagnostic — recursion is forbidden in v1 (FR-B-4).
6. **Given** an agent body whose prose contains the literal string `<!-- @include path.md -->` inside a fenced code block (e.g., authored documentation about the syntax), **When** the resolver runs, **Then** the resolver does NOT expand directives inside fenced code blocks (R-2 mitigation; spec-pinned regex in contracts §1).

---

### User Story 2 — Runtime composer emits structured prompt_prefix (Priority: P1)

A skill author orchestrating an agent spawn (e.g., the future `09-research-first` skill) wants to call a composer with a `task_spec` and receive a JSON spec `{subagent_type, prompt_prefix, model_default}` — then prepend `prompt_prefix` to its task prompt before calling `Agent`. Today every skill reinvents the verb-table + variable-bindings + coordination-protocol assembly freehand.

**Why this priority**: P1 because every research-first PRD assumes this primitive. Without it, every research-first skill encodes verb references in its prompt freehand — exactly the prose-only enforcement that already failed elsewhere in the codebase.

**Independent Test**: Invoke the composer via `bash plugin-wheel/scripts/agents/compose-context.sh --agent-name research-runner --plugin-id kiln --task-spec <fixture.json>`. Assert (a) stdout is valid JSON matching the schema in contracts §2, (b) `prompt_prefix` contains the `## Runtime Environment` heading + variable bindings + verb bindings + per-shape stanza + coordination-protocol stanza, (c) re-invocation with same inputs produces byte-identical output (NFR-6 determinism).

**Acceptance Scenarios**:

1. **Given** the composer is invoked with `agent_name=research-runner`, `plugin_id=kiln`, and a sample `task_spec` JSON containing `task_shape=skill`, **When** it runs, **Then** stdout emits `{"subagent_type": "kiln:research-runner", "prompt_prefix": "<assembled block>", "model_default": null}` and exit code is 0 (SC-3).
2. **Given** a `task_spec` with `task_shape` not in the closed vocabulary (8 shapes per FR-A-4), **When** the composer runs, **Then** it exits non-zero with a diagnostic naming the unknown shape (FR-A-6 closed-vocabulary discipline).
3. **Given** a `prd_path` with `agent_binding_overrides:` referencing a verb not in the closed namespace, **When** the composer runs, **Then** it exits non-zero with a diagnostic naming the unknown verb (FR-A-9, SC-5).
4. **Given** a plugin manifest with `agent_bindings:` referencing a verb not in the closed namespace, **When** the validator runs at install / lint time, **Then** install is REFUSED with a clear error (FR-A-7, SC-4).
5. **Given** the same inputs, **When** the composer runs twice, **Then** outputs are byte-identical (NFR-6 determinism — required for cache-friendly re-invocation in test fixtures).
6. **Given** the composer is invoked but the calling skill chooses NOT to use the result, **When** the skill spawns an agent the legacy way, **Then** behavior is unchanged (NFR-3 backward-compat — composer is opt-in).

---

### User Story 3 — Three research-first agents shipped (Priority: P2)

A `09-research-first` PRD author needs to spawn `research-runner`, `fixture-synthesizer`, and `output-quality-judge` agents with strict tool scopes. Today only `research-runner.md` exists and the other two are missing.

**Why this priority**: P2 because it's a deliverable that depends on Theme A's composer (the agents are empty shells of role identity — verbs come from runtime context) and Theme B's include directive (the coordination-protocol stanza is the canonical shared module).

**Independent Test**: Verify that each of the three agent.md files exists at `plugin-kiln/agents/<name>.md` with (a) `tools:` allowlist matching the implementation hints, (b) NO `model:` frontmatter, (c) body that is pure role identity (no verb tables, no tool references, no model selection, no step-by-step task prose), (d) the file passes the include-preprocessor compiled-equals-build CI check.

**Acceptance Scenarios**:

1. **Given** the three agent.md files exist, **When** a spec validator inspects each, **Then** frontmatter contains `name`, `description`, `tools` and does NOT contain `model` (FR-A-10).
2. **Given** each agent body is read, **When** scanned for forbidden content, **Then** no verb tables, no `Bash(...)`-style tool references, no model directives, no enumerated step-by-step task lists are present (FR-A-11).
3. **Given** the `output-quality-judge.md` agent, **When** its `tools:` line is read, **Then** it lists exactly `Read, SendMessage, TaskUpdate` (most tightly-scoped role per implementation hints).

---

### Edge Cases

- **Literal `<!--` content in agent prose**: agent files may legitimately contain HTML-comment-shaped strings inside fenced code blocks (e.g., this very spec). The resolver MUST distinguish "directive on a line by itself" from "prose containing directive-shaped text" (R-2 mitigation, contracts §1 pins the regex).
- **Empty include target**: a shared module file that exists but is empty resolves to an empty expansion (NOT an error — supports stub modules).
- **Missing include target**: a directive pointing at a nonexistent file MUST exit non-zero with a diagnostic (no silent skip).
- **Recursive include attempt**: a shared module that itself contains a directive MUST exit non-zero (FR-B-4 single-pass discipline).
- **Composer invoked without `WORKFLOW_PLUGIN_DIR`**: exits non-zero with a diagnostic (composer cannot anchor verb-binding paths without it).
- **PRD overrides an agent that the manifest doesn't declare**: composer exits non-zero (SC-5 fixture).
- **Adding a new task shape ad hoc**: composer exits non-zero on `task_shape` not in the closed vocabulary; manifest update is the gate (FR-A-6).
- **`general-purpose` spawn for a specialized role in production code**: documentation-only enforcement (NFR-7); reviewer responsibility flagged in CLAUDE.md.
- **`research-runner.md` already exists**: the existing file pre-dates this PRD. Implementer track is responsible for confirming its frontmatter + body match FR-A-10/FR-A-11 (purge any verb tables, tool references, model selection, step-by-step task prose). If conformant, leave; if not, refactor in-place.

## Functional Requirements

### Theme B — Compile-time include preprocessor (`agent-prompt-includes`)

| FR | Description |
|---|---|
| **FR-B-1** | The preprocessor resolves directives in `plugin-kiln/agents/*.md` files via the **hybrid** approach: source authoring under `plugin-kiln/agents/_src/<role>.md` (or, if a role's source equals its compiled form, in-place under `plugin-kiln/agents/<role>.md` with no directive — see resolution decision in plan.md), compile to `plugin-kiln/agents/<role>.md` (committed compiled outputs), `plugin-kiln/bin/init.mjs` ships the compiled output. CI verifies `compiled == build(sources)` on every PR. (Resolves OQ-1.) |
| **FR-B-2** | Directive syntax is `<!-- @include <relative-path> -->` on a line by itself (leading/trailing whitespace tolerated). Path is relative to the **agent file's own directory** (resolution context locked here). HTML-comment shape preserves markdown rendering and tooling friendliness. (Resolves OQ-2.) |
| **FR-B-3** | Shared modules live at `plugin-kiln/agents/_shared/<name>.md`. Underscore-prefix sorts to the top and is visually distinct from spawnable agents. The `_shared/` directory is excluded from agent registration scans (no `name:` frontmatter required). |
| **FR-B-4** | Resolver implementation: `plugin-kiln/scripts/agent-includes/resolve.sh` (Bash + `awk`/`sed` + `cat`, ≤ 80 lines). Single-pass — recursion is forbidden in v1. The resolver reads stdin OR a path argument, writes resolved output to stdout. Exit non-zero on (a) missing include target, (b) recursive include detected, (c) malformed directive line. |
| **FR-B-5** | At least one shared module ships in v1: `plugin-kiln/agents/_shared/coordination-protocol.md` containing the SendMessage-relay-results boilerplate currently duplicated across team-mode agents. |
| **FR-B-6** | 2–3 existing kiln agents are refactored to use the include directive in v1: `qa-engineer.md`, `prd-auditor.md`, `debugger.md`. Compiled output must contain the same effective prose as the pre-refactor file (no behavioral regression). |
| **FR-B-7** | CI gate: a script `plugin-kiln/scripts/agent-includes/check-compiled.sh` re-runs the resolver against every source and asserts `compiled == build(sources)`. Wired into `/wheel:wheel-test` flow per the existing CI pattern. |
| **FR-B-8** | Document the directive syntax + resolver location + module convention in CLAUDE.md "Active Technologies" section + plan.md. |

### Theme A — Runtime context-injection composer (`agent-spawn-context-injection-layer`)

| FR | Description |
|---|---|
| **FR-A-1** | A composer at `plugin-wheel/scripts/agents/compose-context.sh` (sibling to existing `resolve.sh`, NOT extending it — sibling is cleaner per OQ-4 resolution; rationale in plan.md §Phase 0) accepts `--agent-name <name>` (or `--agent-path <path>`), `--plugin-id <id>`, `--task-spec <path-to-json>`, optional `--prd-path <path>`. Emits JSON `{subagent_type, prompt_prefix, model_default}` on stdout. |
| **FR-A-2** | The composer assembles `prompt_prefix` with the `## Runtime Environment` block containing: `WORKFLOW_PLUGIN_DIR` (existing Option B mechanism), `task_shape`, `task_summary`, variable bindings table, verb bindings table (manifest defaults + PRD overrides applied — overrides win), per-shape stanza body (from `plugin-kiln/lib/task-shapes/<shape>.md`), coordination-protocol stanza body (always for team-mode spawns). |
| **FR-A-3** | The calling skill is responsible for prepending `prompt_prefix` to its actual task prompt before passing to the `Agent` tool's `prompt` parameter. The composer does NOT call `Agent` itself. |
| **FR-A-4** | Closed task-shape vocabulary v1: `skill`, `frontend`, `backend`, `cli`, `infra`, `docs`, `data`, `agent` — **8 shapes**. The `agent` shape (meta-tasks targeting an agent prompt itself) is INCLUDED in v1 because the very work shipping in this PRD (3 new agent.md files) is the canonical exemplar; removing it would orphan the use case (resolves OQ-3). Adding shapes requires manifest update — no ad hoc proliferation. |
| **FR-A-5** | Per-shape stanzas live at `plugin-kiln/lib/task-shapes/<shape>.md`. Each is 5–15 lines of curated guidance. NO frontmatter required (markdown body only — the file IS the body). |
| **FR-A-6** | Adding a new task shape requires a manifest update at `plugin-kiln/lib/task-shapes/_index.json` (closed-vocabulary registry). Composer reads `_index.json` and refuses unknown shapes (FR-A-2 acceptance scenario). |
| **FR-A-7** | `plugin-<name>/.claude-plugin/plugin.json` schema gains an `agent_bindings:` field: `{ "<agent-short-name>": { "verbs": { "<verb-name>": "<command-template>" } } }`. A validator script at `plugin-wheel/scripts/agents/validate-bindings.sh` refuses install if any binding references a verb not in the closed namespace. |
| **FR-A-8** | Closed verb namespace v1 (pinned): `verify_quality`, `run_baseline`, `run_candidate`, `measure`, `synthesize_fixtures`, `judge_outputs`. Stored at `plugin-wheel/scripts/agents/verbs/_index.json`. |
| **FR-A-9** | PRD frontmatter MAY override per-PRD via `agent_binding_overrides:` (same shape as `agent_bindings:`, narrower scope). Composer applies overrides AFTER manifest defaults. Validator refuses PRDs with overrides referencing unknown agents or unknown verbs. |
| **FR-A-10** | Three agent.md files ship/exist under `plugin-kiln/agents/`: `research-runner.md`, `fixture-synthesizer.md`, `output-quality-judge.md`. Each carries a `tools:` allowlist (REQUIRED). NO `model:` frontmatter. |
| **FR-A-11** | Each shipped agent.md body is pure role identity. NO verb tables (those come from runtime context). NO tool references. NO model selection. NO step-by-step task prose (orchestrator's job). |
| **FR-A-12** | CLAUDE.md "Active Technologies" or sibling section documents 6 architectural rules: (a) NEVER use `general-purpose` for specialized roles in production; (b) one role per registered subagent_type, multiple spawns per run with different injected variables; (c) injection is prompt-layer NOT system-prompt-layer; (d) top-level orchestration is correct, not nested (nested `Agent` calls are reduced); (e) agent registration is session-bound; (f) plain-text output is invisible to team-lead — always relay via `SendMessage`. |

### Tools allowlists (REQUIRED, FR-A-10)

| Agent | `tools:` line |
|---|---|
| `research-runner` | `Read, Bash, SendMessage, TaskUpdate, TaskList` |
| `fixture-synthesizer` | `Read, Write, SendMessage, TaskUpdate` |
| `output-quality-judge` | `Read, SendMessage, TaskUpdate` |

## Non-Functional Requirements

| NFR | Description |
|---|---|
| **NFR-1 (Cache layout preservation)** | The include resolver MUST resolve at compile time; the agent's runtime system prompt is a stable string. Per-spawn variables in include directives are FORBIDDEN. SC-7 fixture asserts byte-identical resolved output across two consecutive resolver invocations. |
| **NFR-2 (Theme B backward compat)** | Agents without directives continue to work unchanged. Resolver is a no-op for files without directive lines. |
| **NFR-3 (Theme A backward compat)** | Skills that don't call the composer continue to spawn agents the way they do today. The composer is opt-in. |
| **NFR-4 (Atomic shipment)** | Theme A and Theme B ship together — single squash-merged PR per Path B precedent. Shipping separately would create a half-state. |
| **NFR-5 (Tools-allowlist enforcement deferred)** | Test 2 from the proof-of-concept (verifying `tools:` frontmatter is enforced by the harness) requires session restart. NOT in scope for v1. Documented as queued follow-on. |
| **NFR-6 (Live-substrate verification, deterministic output)** | Composer output for known inputs is deterministic (byte-identical re-invocation). Resolver compiled output is byte-identical for unchanged sources. Both verified by run.sh-only fixtures (substrate hierarchy tier-2). |
| **NFR-7 (No `general-purpose` in production)** | Documentation + review discipline, not code-enforced. CLAUDE.md states it explicitly. Reviewers flag any production code path that spawns `general-purpose` for a specialized role. |
| **NFR-8 (Disjoint file partition)** | Theme A and Theme B implementer tracks touch DISJOINT file sets per the plan.md "File ownership" table. No file is owned by both tracks; coordination is by interface contract only. |

## Success Criteria

- **SC-1 (Theme B include directive E2E)**: An agent.md with `<!-- @include _shared/coordination-protocol.md -->` resolves to the expanded prose at compile time AND 2–3 existing kiln agents are refactored to use the directive without behavioral regression. Verified by `plugin-kiln/tests/agent-includes-resolve/run.sh`.
- **SC-2 (Theme B CI gate)**: Mutating a source agent.md without re-compiling (or vice-versa) fails the CI compiled-equals-build check. Verified by `plugin-kiln/tests/agent-includes-ci-gate/run.sh`.
- **SC-3 (Theme A composer emits valid JSON)**: For known inputs (`plugin_id=kiln`, `agent_name=research-runner`, sample `task_spec`), the composer emits JSON matching contracts §2 schema. Verified by `plugin-wheel/tests/compose-context-shape/run.sh`.
- **SC-4 (Theme A validator catches unknown verb in manifest)**: A plugin manifest with an `agent_bindings:` entry referencing a verb not in the closed namespace is REFUSED at install/lint time. Verified by `plugin-wheel/tests/validate-bindings-unknown-verb/run.sh`.
- **SC-5 (Theme A validator catches unknown agent in PRD override)**: A PRD with `agent_binding_overrides:` referencing an agent not declared in the manifest is REFUSED at compose-time. Verified by `plugin-wheel/tests/compose-context-unknown-override/run.sh`.
- **SC-6 (3 research-first agents shipped)**: All three agent.md files exist with required `tools:` allowlists, role-identity-only bodies, and pass the structural-validity fixture. Verified by `plugin-kiln/tests/research-first-agents-structural/run.sh`.
- **SC-7 (Cache layout preserved)**: Resolved system prompt is byte-identical across two consecutive resolver invocations on unchanged input. Verified by SC-1 fixture's repeat-invocation assertion.
- **SC-8 (CLAUDE.md documents architectural rules)**: 6 rules from FR-A-12 are documented in CLAUDE.md. Reviewers can grep for canonical phrases (`never use \`general-purpose\``, `injection is prompt-layer`, etc.). Verified by `plugin-kiln/tests/claude-md-architectural-rules/run.sh`.

## Key Entities

- **Agent source file** — `plugin-kiln/agents/<role>.md` (compiled output, post-resolver). Body: role identity + resolved include expansions. Frontmatter: `name`, `description`, `tools` (REQUIRED for new agents), optionally `model` (FORBIDDEN for the 3 new research-first agents — workflow step decides).
- **Shared module** — `plugin-kiln/agents/_shared/<name>.md`. Pure markdown body (no frontmatter). Concatenated verbatim at directive site.
- **Per-shape stanza** — `plugin-kiln/lib/task-shapes/<shape>.md`. Pure markdown body. Composer injects body into `prompt_prefix`.
- **Task-shape index** — `plugin-kiln/lib/task-shapes/_index.json`. Closed-vocabulary registry: `{"version": 1, "shapes": ["skill", "frontend", "backend", "cli", "infra", "docs", "data", "agent"]}`.
- **Verb namespace index** — `plugin-wheel/scripts/agents/verbs/_index.json`. `{"version": 1, "verbs": ["verify_quality", "run_baseline", "run_candidate", "measure", "synthesize_fixtures", "judge_outputs"]}`.
- **Plugin manifest `agent_bindings:`** — JSON object in `plugin-<name>/.claude-plugin/plugin.json`. See contracts §3.
- **PRD `agent_binding_overrides:`** — YAML object in PRD frontmatter. See contracts §4.
- **`task_spec` JSON** — input to the composer. See contracts §2.

## Dependencies & Constraints

- **Bash 5.x**, `jq`, `awk`/`sed`, `cat` — no new runtime dependencies.
- **No new npm packages** — `plugin-kiln/bin/init.mjs` ships compiled outputs; no resolver runs in init.mjs at install time (per OQ-1 hybrid resolution: compile happens at PR time via CI, init.mjs ships the artifact).
- **No new MCP servers** — pure local file operations.
- **Existing wheel `WORKFLOW_PLUGIN_DIR` Option B mechanism** — composer reads it from env (FR-A-2). Already shipped in `build/wheel-as-runtime-20260424`.
- **Existing kiln-test substrate** — fixtures use the run.sh-only pattern (substrate hierarchy tier-2). Per the §Implementer Prompt rule, tier-2 fixtures are invoked directly via `bash`; pass/fail is exit code + PASS summary.

## Out of Scope (v1)

- Runtime resolution of include directives (live-reload). v2.
- Variable substitution inside include directives (`{insert path.md var=foo}`). Runtime composer is the right layer.
- Conditional includes, recursive includes, cross-plugin includes. v2.
- Generalizing the include preprocessor to non-kiln plugins (`plugin-wheel/agents/`, `plugin-shelf/agents/`). v2.
- In-session agent registration (Claude Code harness constraint).
- Tools-frontmatter enforcement testing (Test 2 — requires session restart). NFR-5 documents the queue.
- Retroactively refactoring every existing kiln agent. v1 = 2–3 agents.

## Risks & Open Questions

### Risks (carried from PRD)

- **R-1 (Closed-vocabulary scope creep)**: Both task-shape enum (FR-A-4) and verb namespace (FR-A-8) are governance decisions. **Mitigation**: ship conservative initial sets; document the gate process for additions (manifest update); accept v1 will need at least one revision based on real usage.
- **R-2 (Include resolver edge cases)**: Markdown files with literal `<!--` content could trigger false-positive directive matches. **Mitigation**: contracts §1 pins the regex (directive must be on a line by itself, not inside fenced code blocks). Recursion forbidden in v1.
- **R-3 (Composer-skill integration footprint)**: The composer is opt-in (NFR-3) but for `09-research-first` to actually use it, the orchestrating skill MUST call the composer + prepend `prompt_prefix` consistently. **Mitigation**: ship a documented integration recipe alongside the composer (plan.md §Integration Recipe). Treat first research-first PRD's specifier as the canonical reviewer for composer usage.
- **R-4 (PRD-override schema drift)**: `agent_binding_overrides:` in PRD frontmatter is a new schema surface. **Mitigation**: contracts §4 pins the shape; validator catches malformed entries.

### Open Questions (resolved by /plan — see plan.md §Phase 0)

- **OQ-1 (RESOLVED in plan.md)**: Theme B resolution timing — **hybrid**. Sources authored under `_src/` or in-place; compile to committed `plugin-kiln/agents/<role>.md`; CI verifies compiled == build(sources); init.mjs ships compiled output. Pure scaffold-time rejected (creates source-file diff drift on consumer edits). Pure build-time too rigid (refactor authors must re-run a script). Hybrid wins.
- **OQ-2 (RESOLVED in plan.md)**: Directive syntax — **`<!-- @include <relative-path> -->`** on a line by itself. HTML-comment-safe, won't break markdown rendering, mirrors mdx-prompt / POML conventions. Path relative to the agent file's directory.
- **OQ-3 (RESOLVED here)**: Is `agent` shape needed in v1? — **YES**. The 3 new agent.md files in this PRD are the canonical exemplar. Removing the shape orphans the use case.
- **OQ-4 (RESOLVED in plan.md)**: Theme A composer location — **sibling `compose-context.sh`**. `resolve.sh` is single-purpose (path/name → JSON spec) and stable; conflating with assembly responsibilities (verb tables, variable bindings, stanza concatenation) bloats the contract. Sibling is the clean separation.
- **OQ-5 (RESOLVED here)**: Shared module location — **`plugin-kiln/agents/_shared/<name>.md`**. Co-located with agents (same directory the resolver walks); underscore-prefix excludes from registration scan.

## Theme Partition (NON-NEGOTIABLE)

This is the file-conflict-prevention contract for the two parallel implementer tracks. No file appears in both columns.

| Theme B (`impl-include-preprocessor`) | Theme A (`impl-runtime-composer`) |
|---|---|
| `plugin-kiln/scripts/agent-includes/resolve.sh` | `plugin-wheel/scripts/agents/compose-context.sh` |
| `plugin-kiln/scripts/agent-includes/check-compiled.sh` | `plugin-wheel/scripts/agents/validate-bindings.sh` |
| `plugin-kiln/agents/_shared/coordination-protocol.md` | `plugin-wheel/scripts/agents/verbs/_index.json` |
| `plugin-kiln/agents/qa-engineer.md` (refactor) | `plugin-kiln/lib/task-shapes/_index.json` |
| `plugin-kiln/agents/prd-auditor.md` (refactor) | `plugin-kiln/lib/task-shapes/<shape>.md` (8 files) |
| `plugin-kiln/agents/debugger.md` (refactor) | `plugin-kiln/agents/research-runner.md` (audit/refactor — exists) |
| `plugin-kiln/agents/_src/<role>.md` (if hybrid sources used) | `plugin-kiln/agents/fixture-synthesizer.md` (NEW) |
| `plugin-kiln/tests/agent-includes-resolve/` | `plugin-kiln/agents/output-quality-judge.md` (NEW) |
| `plugin-kiln/tests/agent-includes-ci-gate/` | `plugin-kiln/.claude-plugin/plugin.json` (`agent_bindings:` add) |
| | `plugin-wheel/tests/compose-context-shape/` |
| | `plugin-wheel/tests/compose-context-unknown-override/` |
| | `plugin-wheel/tests/validate-bindings-unknown-verb/` |
| | `plugin-kiln/tests/research-first-agents-structural/` |
| | `plugin-kiln/tests/claude-md-architectural-rules/` |
| | `CLAUDE.md` (architectural rules section — FR-A-12) |

**Shared (read-only by both tracks)**: `specs/agent-prompt-composition/contracts/interfaces.md` (interface contract — both tracks consume it; neither edits it without specifier sign-off).

**Cross-track ordering**: Theme B's `_shared/coordination-protocol.md` (FR-B-5) is the canonical body that Theme A's per-shape coordination-stanza assembly reads (FR-A-2). Both ship in v1; the file lands under Theme B's ownership; Theme A's composer reads it via path. NO write conflict.
