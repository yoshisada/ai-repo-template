# Feature Specification: Wheel as Runtime — Centralize Agents, Per-Step Models, and Close Silent-Failure Holes

**Feature Branch**: `build/wheel-as-runtime-20260424`
**Created**: 2026-04-24
**Status**: Draft
**Input**: `docs/features/2026-04-24-wheel-as-runtime/PRD.md`

## Overview

Wheel is being asked to act as a runtime by every other plugin in this repo, but it exposes runtime-grade gaps — agent definitions are scattered (not path-addressable), per-step model selection is absent, a hook silently flattens newlines and breaks workflow activation, `WORKFLOW_PLUGIN_DIR` is unset in background sub-agents, and deterministic step-internal command sequences pay full LLM round-trip cost. This feature bundles five thematically-aligned fixes under one PRD because they share a common fix surface: **wheel's environment, agent-resolution, and step-execution contracts**.

Five themes, one feature:
- **Theme A** — Agent centralization & path-addressable resolution (FR-A1..FR-A5)
- **Theme B** — Per-step model selection (FR-B1..FR-B3)
- **Theme C** — Hook newline preservation (FR-C1..FR-C4)
- **Theme D** — `WORKFLOW_PLUGIN_DIR` env parity (FR-D1..FR-D4)
- **Theme E** — Step-internal command batching (FR-E1..FR-E4)

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Fix silent newline flatten in activation hook (Priority: P1)

A workflow author issues a multi-line Bash tool call (setup commands followed by `/path/to/activate.sh <workflow>`). Today the PostToolUse hook flattens newlines before a regex match, the activate path silently misses, no state file is created, and the workflow never runs. The author sees no error.

**Why this priority**: Silent failure in the activation path blocks every downstream theme and every workflow authored with multi-line scaffolding. Fix the root cause of the "works here, breaks there" shape before anything else.

**Independent Test**: Run a multi-line Bash tool call that invokes `activate.sh` anywhere in its body (not just the last line). Assert the state file exists at `.wheel/state_<id>.json`, `wheel.log` contains `path=activate` + `result=activate`, and single-line activations still pass (strict superset, no regression).

**Acceptance Scenarios**:

1. **Given** a multi-line Bash tool call whose body contains `/absolute/path/to/activate.sh some-workflow`, **When** the PostToolUse hook processes the tool input, **Then** the workflow activates (state file created, log line emitted) — identical to the single-line case.
2. **Given** the existing single-line activation tests under `workflows/tests/`, **When** they run after the hook fix, **Then** they all continue to pass with no regression.
3. **Given** a fuzz/property test over hook-input shapes (quoted newlines, embedded control chars, valid-but-weird JSON escapes), **When** the hook runs, **Then** it never silently drops `tool_input.command` characters that the LLM emitted.

---

### User Story 2 — `WORKFLOW_PLUGIN_DIR` available in background sub-agents (Priority: P1)

A consumer installs the plugin via the Claude Code marketplace. They run `/kiln:kiln-report-issue`. The foreground skill dispatches a background sub-agent (via `Agent(run_in_background: true)`) which tries to resolve `${WORKFLOW_PLUGIN_DIR}/scripts/shelf-counter.sh`. Today the var is unset in the bg sub-agent's env — the sub-agent silently no-ops, the counter never increments, the bg log line either vanishes or says "WORKFLOW_PLUGIN_DIR was unset". On this source repo it works by accident because the relative path exists.

**Why this priority**: The silence is the bug — the consumer has no signal. A CI-gated consumer-install smoke test is the only way to stop it from re-shipping.

**Independent Test**: Simulate a consumer install (source-repo `plugin-*/` directories removed; plugin scripts only under `~/.claude/plugins/cache/<org>-<mp>/<plugin>/<version>/scripts/`). Run a workflow that spawns a bg sub-agent. Assert the sub-agent resolves its scripts via `${WORKFLOW_PLUGIN_DIR}` AND that `git grep -F 'WORKFLOW_PLUGIN_DIR was unset'` returns zero matches in the bg log.

**Acceptance Scenarios**:

1. **Given** a workflow whose agent step spawns a sub-agent with `run_in_background: true`, **When** the sub-agent executes, **Then** `WORKFLOW_PLUGIN_DIR` is set to the plugin's install-path directory and matches the value a foreground sub-agent would see.
2. **Given** a consumer-install simulation (source-repo `plugin-shelf/`, `plugin-kiln/` directories moved aside), **When** `/kiln:kiln-report-issue` runs, **Then** `.kiln/logs/report-issue-bg-<date>.md` contains a non-empty line with `counter_before=N | counter_after=N+1 | threshold=10 | action=increment` and does NOT contain the string `WORKFLOW_PLUGIN_DIR was unset`.
3. **Given** the consumer-install smoke test, **When** it runs in CI on every PR touching `plugin-wheel/` or any workflow JSON, **Then** a regression that removes the env export fails CI loudly (exit non-zero + identifiable error string).

---

### User Story 3 — Centralize agents as path-addressable resources (Priority: P2)

A kiln skill author wants to spawn the `qa-engineer` agent from `/kiln:kiln-fix` without wrapping the call in a wheel workflow. Today every plugin scatters its own agent definitions, every `Agent()` tool call hard-codes `subagent_type: general-purpose` (paying the full generic system-prompt + toolset tax), and there's no shared way for a kiln skill to say "spawn the debugger agent" with one call.

**Why this priority**: P2 because this is a refactor with ergonomic payoff (spawn specialized agents from any caller, not just wheel workflows) and a cost-reduction lever (replace generic spawns with specialized ones). It's not blocking any shipping workflow.

**Independent Test**: A kiln skill (e.g. `/kiln:kiln-fix`) spawns the `debugger` agent via the resolver path. Swap the resolver to return the wrong spec and assert the test fails.

**Acceptance Scenarios**:

1. **Given** the resolver script at `plugin-wheel/scripts/agents/resolve.sh`, **When** it's called with a short name (`qa-engineer`), **Then** it returns the JSON spec (path, subagent_type, tools) for that agent — pulling from `plugin-wheel/agents/qa-engineer.md`.
2. **Given** the resolver is called with a repo-relative path (`plugin-wheel/agents/debugger.md`), **When** it resolves, **Then** it returns the same JSON shape as the short-name form.
3. **Given** the resolver is called with an unknown name, **When** no agent matches, **Then** it passes through unchanged (back-compat for current `subagent_type: general-purpose` spawns).
4. **Given** a wheel workflow JSON with `agent_path: plugin-wheel/agents/qa-engineer.md` on an agent step, **When** the workflow dispatches that step, **Then** the resolver attaches the right spec and the step runs on that agent. Workflows using the legacy `subagent_type:` continue to work byte-identically.
5. **Given** a migration PR that moves every agent file to `plugin-wheel/agents/<name>.md`, **When** the PR lands, **Then** old paths contain either redirect files or symlinks (atomic migration, no half-migrated state), and a test walks every workflow JSON + every kiln skill asserting every `agent` reference resolves via the FR-A1 resolver.

---

### User Story 4 — Per-step model selection in workflows (Priority: P2)

A workflow author has a classification step (should be haiku-cheap) and a synthesis step (should be sonnet-balanced). Today every step runs on whatever default model the harness picked, so the classification step pays opus/sonnet prices for pattern-match work.

**Why this priority**: P2 because it's additive (absent `model:` preserves current behavior byte-identically), the savings compound as workflows multiply, and it's a prerequisite for future cost-conscious workflow authoring.

**Independent Test**: Ship one workflow that specifies `model: haiku` on one step and `model: sonnet` on another; assert the spawned agents use exactly those models. A mismatch must surface as an activation error, not a silent default.

**Acceptance Scenarios**:

1. **Given** a workflow JSON agent step with `model: haiku`, **When** the step dispatches, **Then** the spawned agent runs on haiku (or the project-configured haiku model id).
2. **Given** a workflow JSON agent step with an explicit model id (`claude-haiku-4-5-20251001`), **When** the step dispatches, **Then** the spawned agent runs on exactly that id.
3. **Given** a workflow JSON agent step with no `model:` field, **When** the step dispatches, **Then** behavior is byte-identical to today's harness-default spawn.
4. **Given** `model: <unsupported-or-unavailable-id>`, **When** dispatch runs, **Then** the step fails loudly with an identifiable error string — NO silent fallback to a different model.
5. **Given** documentation updates (wheel README + `/plan` template's wheel-workflow guidance), **When** a workflow author reads them, **Then** they find a one-line rule of thumb for haiku / sonnet / opus selection (e.g. *"haiku for classification, sonnet for synthesis, opus only for hard reasoning"*).

---

### User Story 5 — Step-internal command batching for deterministic sequences (Priority: P3)

A workflow author has an agent step that runs 3-10 small bash calls back-to-back (e.g. `dispatch-background-sync`). Each call pays a full LLM round-trip between tool uses even though no LLM reasoning happens between them. The workflow is perceptibly slow.

**Why this priority**: P3 because it's a perf optimization with a documented audit-first approach. The round-trip claim may turn out to be wrong (negative-result is an acceptable outcome per R-005), in which case we ship the audit with the honest finding.

**Independent Test**: Pick the documented candidate (`dispatch-background-sync` or whichever the audit flags as higher-leverage). Record before/after wall-clock time for the step in the same environment. Ship one batched wrapper and the audit doc.

**Acceptance Scenarios**:

1. **Given** an audit doc at `.kiln/research/wheel-step-batching-audit-<date>.md`, **When** a reviewer reads it, **Then** they see every `"type": "agent"` step across all five plugin workflow directories enumerated, classified by (a) number of internal bash calls today, (b) whether the sequence is deterministic post-kickoff, (c) recommended action (batch / leave / split).
2. **Given** one high-leverage step chosen from the audit, **When** it is consolidated into a single `plugin-*/scripts/step-<name>.sh` wrapper, **Then** the workflow's wall-clock time for that step drops (with raw before/after numbers committed to the audit doc; same-hardware, same-session measurement).
3. **Given** a convention doc appended to wheel's README, **When** a workflow author reads it, **Then** they find clear guidance on when to batch (deterministic, no LLM reasoning between calls) vs. when to leave separate (mid-step LLM reasoning needed) — with the debuggability trade-off surfaced and `set -e` + per-action log lines + structured success/failure output prescribed.
4. **Given** the audit's measurement finds NO speedup (round-trip latency wasn't the dominant cost), **When** the audit ships, **Then** the negative result is documented and the FR scope re-narrows accordingly — no forced positive result.

---

### Edge Cases

- **Multi-line activation with heredoc body**: The hook fix must handle a Bash tool call that uses `<<EOF ... EOF` with embedded newlines in the command body.
- **Activate.sh path containing spaces or special chars**: The regex must still match when `/path/to/activate.sh` is preceded or followed by arbitrary shell tokens.
- **Agent resolver called before migration completes**: If a reference still points at an old agent-file location during the migration window, the redirect/symlink must return the same JSON spec as the new canonical path (so callers don't see a transitional failure).
- **Background sub-agent spawned from a foreground sub-agent** (two levels deep): `WORKFLOW_PLUGIN_DIR` must propagate through both spawn hops. If the harness's env-inheritance model makes this infeasible (PRD R-001 Option A), the implementation falls back to Option B — template the absolute path into the sub-agent prompt at dispatch time — and FR-D3's smoke test MUST still pass.
- **`model:` override in a project that gates model selection**: If the harness enforces quotas or allow-lists per project, a disallowed `model:` value must fail loudly (identifiable error string) rather than silently falling back to the default.
- **Batched step wrapper fails partway**: `set -e` in the wrapper must surface the failing action's log line; the workflow must NOT continue with empty step output (which is the silent-failure shape we're trying to stamp out).

## Requirements *(mandatory)*

### Functional Requirements

#### Theme A — Agent centralization & path-addressable resolution

> **PARTIAL REVERSAL 2026-04-25** (see `.kiln/feedback/2026-04-25-fr-a1-wheel-agent-centralization-shipped-2026-04-24.md`): FR-A1 (canonical-path-in-wheel) and FR-A2 (atomic migration TO wheel) reversed — wheel is dispatch infrastructure and should own NO agents. The 10 centralized agents migrated back to `plugin-kiln/agents/<name>.md` (their actual consumer). Symlinks deleted, `plugin-wheel/agents/` directory removed. The resolver primitive (FR-A3), `agent_path:` workflow JSON field (FR-A4), and resolver-spawn alternative (FR-A5) are PRESERVED — those work whether agents live in wheel or in their consumer plugins. Empirical justification: zero wheel workflows consumed any of the 10 agents; all 10 were kiln-consumed; the four "generic role archetypes" the original 2026-04-23 feedback assumed would be hosted alongside (reconciler/writer/researcher/auditor) were never authored, so the centralization moved files but never delivered the cross-plugin-shared layer that was supposed to be the payoff.

- **FR-A1** [REVERSED 2026-04-25 — primitive preserved, canonical-path-in-wheel moot]: Wheel MUST ship a shared agent-resolution primitive at a stable script path (e.g. `plugin-wheel/scripts/agents/resolve.sh`) that accepts `path-or-name` as input and emits the JSON spec needed to attach to an `Agent` tool call: `subagent_type`, system-prompt path, tool allow-list.
- **FR-A2** [REVERSED 2026-04-25]: All shipped agents (`qa-engineer`, `debugger`, `smoke-tester`, `prd-auditor`, `spec-enforcer`, `test-runner`, `ux-evaluator`, plus generic role archetypes `reconciler`, `writer`, `researcher`, `auditor`) MUST live under `plugin-wheel/agents/<name>.md` as their canonical path. Existing scattered agent files are migrated in ONE PR with redirects/symlinks at old paths (NFR-7 — atomic migration window). **(Reversed: agents now live in `plugin-<consumer>/agents/<name>.md`; for the existing 10 that's `plugin-kiln/agents/`.)**
- **FR-A3**: The resolver MUST accept three input forms: (a) absolute or repo-relative path, (b) short name resolved via a registry inside wheel, (c) unknown name passed through as-is for backward compat with current `subagent_type: general-purpose` spawns.
- **FR-A4**: Wheel workflow JSON MUST gain an additive `agent_path:` field on agent steps. When present, it is resolved through FR-A1. Existing `subagent_type:` spawns MUST continue to work unchanged during and after migration.
- **FR-A5**: Kiln skills that currently use `Agent(subagent_type: general-purpose, prompt: …)` for specialized work (e.g. `/kiln:kiln-fix` debug loop) MUST gain the option to spawn via the resolver, getting the right specialized agent without wrapping themselves in a wheel workflow.

#### Theme B — Per-step model selection

- **FR-B1**: Wheel workflow JSON's agent step MUST gain an additive `model:` field. Accepted values: `haiku`, `sonnet`, `opus`, or an explicit model id (e.g. `claude-haiku-4-5-20251001`). Field MUST be optional; absent → harness default unchanged.
- **FR-B2**: The `model:` field MUST be enforced at dispatch — if specified, the spawned agent uses exactly that model. Mismatches surface as activation errors with identifiable error strings, NOT silent fallback.
- **FR-B3**: Documentation (wheel README + `/plan` template's wheel-workflow guidance) MUST name the haiku-vs-sonnet-vs-opus axis with one-line rules of thumb so workflow authors pick correctly.

#### Theme C — Hook newline preservation

- **FR-C1**: `plugin-wheel/hooks/post-tool-use.sh` MUST extract `tool_input.command` from the raw hook input WITHOUT applying a `tr '\n' ' '` flatten beforehand. Acceptable approaches: try `jq` on raw input first and fall back to JSON-aware sanitization (`python3 -c "import json,sys; …"`) only on parse failure; OR extract `tool_input.command` with `jq -r` first and operate on that value before any defensive sanitization of OTHER fields. The blanket pre-flatten MUST be removed.
- **FR-C2**: After FR-C1, a multi-line Bash tool call containing `/path/to/activate.sh <workflow>` anywhere in its body MUST activate the workflow successfully (state file created, `path=activate` in `wheel.log`, `result=activate`).
- **FR-C3**: The `/wheel:wheel-run` skill's "single-line Bash call" guidance MUST be removed once FR-C2 holds, eliminating the caller-side workaround.
- **FR-C4**: Existing single-line activation tests under `workflows/tests/` MUST continue to pass — this is a strict superset, not a regression.

#### Theme D — `WORKFLOW_PLUGIN_DIR` env parity for background sub-agents

- **FR-D1**: `WORKFLOW_PLUGIN_DIR` MUST be present in the environment of EVERY sub-agent spawned by a wheel agent step, regardless of `run_in_background: true|false`. Preferred implementation per PRD R-001 Option A: wheel exports the var into the workflow's lifetime env scope so any sub-agent inherits it. Fallback Option B (template the absolute path into the sub-agent prompt at dispatch time) is acceptable if and only if Option A is technically infeasible AND FR-D3's smoke test still passes.
- **FR-D2**: A consumer-install smoke test (extends `/wheel:wheel-test` or adds a sibling target) MUST simulate the consumer install layout — `plugin-shelf/` and `plugin-kiln/` removed from the repo root, plugin scripts only available under `~/.claude/plugins/cache/<org>-<mp>/<plugin>/<version>/scripts/`. The test MUST run a workflow that spawns a background sub-agent and assert the sub-agent resolves its scripts via `${WORKFLOW_PLUGIN_DIR}` (NOT via the source-repo path).
- **FR-D3**: CLAUDE.md's "Plugin workflow portability" section MUST be updated to state that `WORKFLOW_PLUGIN_DIR` is available in foreground AND background sub-agents, with a one-line note on the Option A vs Option B choice that shipped.
- **FR-D4**: The `kiln:kiln-report-issue` background log line at `.kiln/logs/report-issue-bg-<date>.md` MUST show `notes=` text that does NOT contain the string `"WORKFLOW_PLUGIN_DIR was unset"` anymore — that string is the regression fingerprint and its absence is the smoke-test assertion (`git grep -F 'WORKFLOW_PLUGIN_DIR was unset' .kiln/logs/` returns zero matches in lines written after this PRD ships).

#### Theme E — Step-internal command batching

- **FR-E1**: Audit document at `.kiln/research/wheel-step-batching-audit-<date>.md` MUST enumerate every `"type": "agent"` step across all five plugin workflow directories, classifying each by (a) number of internal bash calls today, (b) whether the sequence is deterministic post-kickoff, (c) recommended action (batch / leave / split).
- **FR-E2**: One high-leverage step MUST be consolidated into a single `plugin-*/scripts/step-<stepname>.sh` wrapper as a worked example. `dispatch-background-sync` is the documented candidate; if the audit surfaces a higher-leverage target, that one wins.
- **FR-E3**: Before/after measurement of elapsed wheel-workflow time for the chosen step MUST be recorded in the audit doc with raw numbers (not just "faster"). The before/after MUST be measured in the same environment (same hardware, same session window). A negative result (no speedup) is an acceptable outcome — document honestly, narrow scope, and ship the audit.
- **FR-E4**: A convention doc — appended to wheel's README — MUST explain when to batch step-internal commands (deterministic, no LLM reasoning between calls) vs. when to leave them as separate agent bash calls (mid-step LLM reasoning needed). The doc MUST surface the debuggability trade-off and prescribe `set -e` + per-action log lines + structured success/failure output for batched scripts.

### Non-Functional Requirements

- **NFR-1 (testing — explicit per user direction)**: Every FR above MUST land with at least one test that exercises it end-to-end. Acceptable substrates: `plugin-kiln/tests/<feature>/` skill-test fixtures, `plugin-wheel/workflows/tests/` workflow tests, or `plugin-wheel/tests/` shell-level unit tests for hook scripts. NO FR ships test-free, regardless of how mechanical the change looks.
- **NFR-2 (silent-failure tripwires)**: Every fix to a previously-silent failure (FR-C1, FR-D1) MUST add a test that fails when the regression returns AND emits a clearly identifiable error string (not a green-but-wrong outcome). The newline-flatten and the `WORKFLOW_PLUGIN_DIR`-unset bugs both shipped *because* their failure mode was silent — the regression tests must catch the silence itself, not just the symptom.
- **NFR-3 (hook input fuzzing)**: For FR-C1 specifically, a fuzz/property test over hook-input shapes — multi-line commands, quoted newlines, embedded control chars, valid-but-weird JSON escapes — MUST assert the hook never silently flattens `tool_input.command` characters that the LLM emitted.
- **NFR-4 (consumer-install simulation in CI)**: FR-D2's smoke test MUST run in CI on every PR that touches `plugin-wheel/` or any plugin's workflow JSON. Local-only smoke tests DO NOT COUNT — the entire bug shape is "works locally, breaks in consumer install."
- **NFR-5 (backward compat)**: `agent_path:` and `model:` MUST be additive workflow JSON fields. Workflows that don't use them MUST behave byte-identically to today.
- **NFR-6 (perf measurement)**: FR-E3's before/after measurement MUST use real wall-clock timing on the same hardware in the same session window. No napkin estimates.
- **NFR-7 (atomic migration window)**: FR-A2's agent-file relocation MUST run in one PR with redirects/symlinks at the old paths, NOT a multi-PR rolling migration. Half-migrated state confuses both wheel's resolver and human readers.

### Key Entities

- **Agent Definition**: A markdown file at `plugin-wheel/agents/<name>.md` describing a specialized agent (system prompt, tool allow-list, role). Consumed by the resolver and any caller that wants to spawn that agent.
- **Resolver Output (JSON spec)**: `{ "subagent_type": string, "system_prompt_path": string, "tools": [string] }` — the shape attached to an `Agent` tool call.
- **Workflow JSON agent step**: Existing shape extended with two optional fields: `agent_path: <path-or-name>` and `model: haiku|sonnet|opus|<explicit-id>`.
- **Consumer-install simulation**: A test environment where `plugin-shelf/`, `plugin-kiln/` directories are absent from the repo root and plugin scripts only live under `~/.claude/plugins/cache/<org>-<mp>/<plugin>/<version>/scripts/` — the layout real consumers see.
- **Batched step wrapper**: A single shell script (e.g. `plugin-<name>/scripts/step-<stepname>.sh`) that consolidates a previously-multi-call deterministic sequence under `set -e` with per-action log lines.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of FR-A1..FR-E4 land with passing tests (NFR-1 enforced).
- **SC-002**: Running `/kiln:kiln-report-issue` from the consumer-install simulation produces a non-empty `.kiln/logs/report-issue-bg-<date>.md` line with a correctly-incremented counter — verified by FR-D2's smoke test, wired into CI per NFR-4.
- **SC-003**: A multi-line Bash tool call that activates a workflow succeeds without a "single-line Bash call" workaround — verified by FR-C1's fuzz test and by a workflow test under `workflows/tests/`.
- **SC-004**: At least one wheel workflow shows a measurable wall-clock speedup from FR-E2's step-batching prototype, with raw before/after numbers committed to the audit doc. A negative result is also acceptable if documented honestly (per FR-E3).
- **SC-005**: At least one kiln skill (`/kiln:kiln-fix` is the documented target) demonstrates spawning a specialized agent via the FR-A1 resolver path, with a test that fails if the resolver returns the wrong spec.
- **SC-006**: At least one wheel workflow uses the new `model:` field in its shipped form, demonstrating the per-step model selection path end-to-end.
- **SC-007**: `git grep -F 'WORKFLOW_PLUGIN_DIR was unset' .kiln/logs/report-issue-bg-*.md` returns zero matches in log lines written after this PRD ships.
- **SC-008**: Every `agent` reference in every workflow JSON + every kiln skill resolves successfully through the FR-A1 resolver — verified by a test that walks all references.
- **SC-009**: Existing workflows that don't use `agent_path:` or `model:` behave byte-identically to their pre-PRD behavior (NFR-5 verified by a diff of state-file output on a pre-PRD-vs-post-PRD workflow run).

## Assumptions

- The Agent tool's env-inheritance for background spawns can be influenced by wheel (PRD R-001 Option A). If implementation surfaces this is NOT true, Option B (prompt-templating the absolute path) is an acceptable fallback — the FR-D3 smoke test is the invariant, not the implementation approach.
- `jq` and `python3` are available in the consumer environment (both are already runtime deps per CLAUDE.md's Active Technologies section).
- The harness supports `model:` override per agent spawn. If a harness-side change is needed to honor the field, that becomes a blocker surfaced in plan.md, NOT a silent-fallback ship.
- No new runtime dependencies are introduced — everything rides on Bash 5.x + `jq` + POSIX utilities.
- Test-execution time for the consumer-install simulation (FR-D2) stays under the existing `/wheel:wheel-test` budget. If it blows the budget, the test gets its own CI job rather than being dropped.
- The agent-file migration (FR-A2) does not rename any agent (name preservation is part of the atomic migration); only paths change.

## Open Questions

- **OQ-1** (from PRD OQ-001): Should the agent resolver live as a script at `plugin-wheel/scripts/agents/resolve.sh` or be exposed as a wheel skill (`/wheel:wheel-resolve-agent`)? Script form is the working default. Decide in `/plan`.
- **OQ-2** (from PRD OQ-002): Do we allow `model:` to be a comma-separated fallback list (e.g. `haiku-4-5,sonnet-4-6`) for graceful degradation, or strictly one model per step? Working default: strictly one — deferred to `/plan`.
