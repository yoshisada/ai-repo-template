---
derived_from:
  - .kiln/feedback/2026-04-23-add-support-for-defining-what.md
  - .kiln/feedback/2026-04-23-all-agents-should-live-in.md
  - .kiln/issues/2026-04-24-wheel-hook-flattens-newlines-breaks-activate-regex.md
  - .kiln/issues/2026-04-24-wheel-workflow-speed-batching-commands.md
  - .kiln/issues/2026-04-24-workflow-plugin-dir-not-exported-to-bg-subagents.md
distilled_date: 2026-04-24
theme: wheel-as-runtime
---
# Feature PRD: Wheel as Runtime — Centralize Agents, Per-Step Models, and Close Silent-Failure Holes

**Date**: 2026-04-24
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md) (if present)

## Background

Strategic feedback this week converged on a single architectural claim: **wheel is the runtime, and the rest of the plugins are workloads on top of it.** Two feedback entries push directly on that frame. (1) Agent definitions are scattered across `plugin-kiln/`, `plugin-shelf/`, `plugin-trim/`, etc., even though every plugin already depends on wheel for dispatch — centralizing them in wheel as **path-addressable** definitions (not a wheel-workflow-only registry) gives every caller (wheel steps, kiln skills, shelf workflows, ad-hoc `/kiln:kiln-fix` debug loops) a single shared spawn contract. Hard-coded `subagent_type: general-purpose` spawns make this worse: every step pays the full generic system prompt + tool-set tax even when a specialized agent would fit. (2) Workflows currently have **no per-step model selection** — every step runs at whatever default model the harness picked, so cheap classification work and expensive reasoning work pay the same price.

Tactical issues filed in the same window expose the cost of *not* treating wheel as a hardened runtime. Three high/medium-severity bugs all stem from wheel's plumbing being underspecified or fragile: a `tr '\n' ' '` in the PostToolUse hook silently flattens multi-line Bash tool calls and breaks the `activate.sh` regex (no error, no state file, workflow never runs); `WORKFLOW_PLUGIN_DIR` is unset in **background** sub-agents spawned via `Agent(run_in_background: true)`, which works by accident in this source repo and silently no-ops in consumer installs; and step-internal command sequences (3-10 small bash calls per agent step) eat round-trip latency that a single batched script would collapse. Each of these is the same shape of bug — *silent failure that only manifests in environments unlike the source repo.*

This PRD bundles all five into a single feature because they share a common fix surface: **wheel's environment, agent-resolution, and step-execution contracts**. Splitting the work would force the same code paths to be re-touched three times.

### Source Issues

| # | Source Entry | Source | Type | GitHub Issue | Severity / Area |
|---|--------------|--------|------|--------------|------------------|
| 1 | [Per-step model selection in workflows](.kiln/feedback/2026-04-23-add-support-for-defining-what.md) | .kiln/feedback/ | feedback | — | medium / architecture |
| 2 | [Centralize agent definitions, path-addressable](.kiln/feedback/2026-04-23-all-agents-should-live-in.md) | .kiln/feedback/ | feedback | — | high / architecture |
| 3 | [Wheel hook flattens newlines, breaks activate regex](.kiln/issues/2026-04-24-wheel-hook-flattens-newlines-breaks-activate-regex.md) | .kiln/issues/ | issue | — | high / wheel |
| 4 | [Wheel workflow speed — batch step-internal commands](.kiln/issues/2026-04-24-wheel-workflow-speed-batching-commands.md) | .kiln/issues/ | issue | — | medium / performance |
| 5 | [WORKFLOW_PLUGIN_DIR unset in bg sub-agents](.kiln/issues/2026-04-24-workflow-plugin-dir-not-exported-to-bg-subagents.md) | .kiln/issues/ | issue | — | high / portability |

## Problem Statement

Wheel is being asked to act as a runtime by every other plugin in this repo, but it has runtime-grade gaps:

- **Resolution coupling.** Agent specs only resolve through wheel-workflow JSON. A kiln skill that wants to spawn `qa-engineer` has to either duplicate the spawn plumbing or wrap itself in a wheel workflow. Wheel-the-engine and wheel-the-agent-registry are conflated.
- **No model-tier control.** Workflows can't say "this step is haiku-cheap; this step is opus-expensive." The team-primitives PRD shipped agent-team support, but model selection is still implicit per harness default.
- **Two silent-failure footguns in the dispatch path.** The PostToolUse hook destroys newlines before regex matching, and background sub-agents inherit a different env baseline than foreground ones. Both are invisible to the caller and only blow up off the source repo's happy path.
- **Per-step round-trip overhead.** Deterministic step-internal command sequences pay full LLM round-trip cost between every tool call, making workflows perceptibly slow in a way that compounds as steps multiply.

The result is that wheel works *in this repo* — the repo authors live on the happy path — but the contract it exposes to consumers and to other plugins is brittle and slow.

## Goals

**Strategic (feedback-derived):**
- Make agents **first-class, path-addressable resources** owned by wheel, callable from any plugin or skill (not just wheel workflows) via a shared resolution primitive.
- Make **per-step model selection** a first-class workflow JSON field, with a sensible default and a clear "this step is haiku-cheap" / "this step is opus-expensive" axis.

**Tactical (issue-derived):**
- Fix the PostToolUse hook so multi-line Bash tool calls activate workflows correctly. Remove the "single-line Bash call" workaround from `/wheel:wheel-run` once the fix lands.
- Fix the `WORKFLOW_PLUGIN_DIR` export so foreground AND background sub-agents inherit it identically. Add a consumer-install smoke test that fails CI if the regression returns.
- Audit and prototype step-internal command batching on at least one high-leverage step (`dispatch-background-sync` is the documented candidate). Establish a convention for when to batch.

## Non-Goals

- **Not** moving every plugin's command code into wheel (that was a separate feedback entry, deliberately deferred from this bundle per user direction).
- **Not** rewriting the agent-team primitives — those shipped in `build/wheel-team-primitives-20260409` and stay as-is. This work layers ON TOP of them.
- **Not** changing wheel workflow JSON's outer schema. New fields (e.g. `agent_path`, `model`) are additive.
- **Not** redesigning the hook execution model. Targeted fixes only.

## Requirements

### Functional Requirements

#### Theme A — Agent centralization & path-addressable resolution (FR-001 from `2026-04-23-all-agents-should-live-in.md`)

- **FR-001**: Wheel ships a shared agent-resolution primitive at a stable script path (e.g. `plugin-wheel/scripts/agents/resolve.sh`) that takes `path-or-name` as input and returns the JSON spec needed to attach to an `Agent` tool call (`subagent_type`, system-prompt path, tool allow-list).
- **FR-002**: All shipped agents (`qa-engineer`, `debugger`, `smoke-tester`, `prd-auditor`, `spec-enforcer`, `test-runner`, `ux-evaluator`, plus generic role archetypes `reconciler`, `writer`, `researcher`, `auditor`) live under `plugin-wheel/agents/<name>.md` as their canonical path. Existing scattered agent files are migrated, with redirects/symlinks during the migration window so nothing breaks atomically.
- **FR-003**: The resolver accepts three input forms: (a) absolute or repo-relative path, (b) short name resolved via a registry inside wheel, (c) unknown name passed through as-is for backward compat with current `subagent_type: general-purpose` spawns.
- **FR-004**: Wheel workflow JSON gains an additive `agent_path:` field on agent steps. When present, it's resolved through FR-001. Existing `subagent_type:` spawns continue to work unchanged during migration.
- **FR-005**: Kiln skills that currently use `Agent(subagent_type: general-purpose, prompt: …)` for specialized work (e.g. `/kiln:kiln-fix` debug loop) gain the option to spawn via the resolver, getting the right specialized agent without wrapping themselves in a wheel workflow.

#### Theme B — Per-step model selection (FR-006 from `2026-04-23-add-support-for-defining-what.md`)

- **FR-006**: Wheel workflow JSON's agent step gains an additive `model:` field. Accepted values: `haiku`, `sonnet`, `opus`, or an explicit model id (e.g. `claude-haiku-4-5-20251001`). Field is optional; absent → harness default unchanged.
- **FR-007**: The `model:` field is enforced at dispatch — if specified, the spawned agent uses exactly that model. Mismatches surface as activation errors, not silent fallback.
- **FR-008**: Documentation (wheel README + `/kiln:plan` template's wheel-workflow guidance) names the haiku-vs-sonnet-vs-opus axis with one-line rules of thumb (e.g. *"haiku for classification / pattern-match steps; sonnet for synthesis; opus only for hard reasoning"*) so workflow authors pick correctly.

#### Theme C — Hook newline preservation (FR-009 from `2026-04-24-wheel-hook-flattens-newlines-breaks-activate-regex.md`)

- **FR-009**: `plugin-wheel/hooks/post-tool-use.sh` MUST extract `tool_input.command` from the raw hook input WITHOUT applying a `tr '\n' ' '` flatten beforehand. Acceptable approaches: try `jq` on raw input first and fall back to JSON-aware sanitization (`python3 -c "import json,sys; …"`) only on parse failure; OR extract `tool_input.command` with `jq -r` first and operate on that value before any defensive sanitization of OTHER fields. The blanket pre-flatten is removed.
- **FR-010**: After FR-009, a multi-line Bash tool call containing `/path/to/activate.sh <workflow>` anywhere in its body MUST activate the workflow successfully (state file created, `path=activate` in `wheel.log`, `result=activate`).
- **FR-011**: The `/wheel:wheel-run` skill's "single-line Bash call" guidance is removed once FR-010 holds, eliminating the caller-side workaround.
- **FR-012**: Existing single-line activation tests under `workflows/tests/` continue to pass — this is a strict superset, not a regression.

#### Theme D — `WORKFLOW_PLUGIN_DIR` env parity for background sub-agents (FR-013 from `2026-04-24-workflow-plugin-dir-not-exported-to-bg-subagents.md`)

- **FR-013**: `WORKFLOW_PLUGIN_DIR` MUST be present in the environment of EVERY sub-agent spawned by a wheel agent step, regardless of `run_in_background: true|false`. Preferred shape per source-issue Option A: wheel exports the var into the workflow's lifetime env scope so any sub-agent inherits it.
- **FR-014**: A consumer-install smoke test (extends `/wheel:wheel-test` or adds a sibling target) simulates the consumer install layout — `plugin-shelf/` and `plugin-kiln/` removed from the repo root, plugin scripts only available under `~/.claude/plugins/cache/<org>-<mp>/<plugin>/<version>/scripts/`. The test runs a workflow that spawns a background sub-agent and asserts the sub-agent resolves its scripts via `${WORKFLOW_PLUGIN_DIR}` (NOT via the source-repo path).
- **FR-015**: CLAUDE.md's "Plugin workflow portability" section is updated to state that `WORKFLOW_PLUGIN_DIR` is available in foreground AND background sub-agents.
- **FR-016**: The `kiln:kiln-report-issue` background log line at `.kiln/logs/report-issue-bg-<date>.md` MUST show `notes=` text that does NOT contain "WORKFLOW_PLUGIN_DIR was unset" anymore — that string is the regression fingerprint and its absence is the smoke-test assertion.

#### Theme E — Step-internal command batching (FR-017 from `2026-04-24-wheel-workflow-speed-batching-commands.md`)

- **FR-017**: Audit document at `.kiln/research/wheel-step-batching-audit-<date>.md` enumerating every `"type": "agent"` step across all five plugin workflow directories, classifying each by (a) number of internal bash calls today, (b) whether the sequence is deterministic post-kickoff, (c) recommended action: batch / leave / split.
- **FR-018**: One high-leverage step is consolidated into a single `plugin-*/scripts/step-<stepname>.sh` wrapper as a worked example. `dispatch-background-sync` is the documented candidate; if the audit surfaces a higher-leverage target, that one wins.
- **FR-019**: Before/after measurement of elapsed wheel-workflow time for the chosen step is recorded in the audit doc with raw numbers (not just "faster"). The before/after MUST be measured in the same environment.
- **FR-020**: A convention doc — appended to wheel's README — explains when to batch step-internal commands (deterministic, no LLM reasoning between calls) vs. when to leave them as separate agent bash calls (mid-step LLM reasoning needed). The doc surfaces the debuggability trade-off and prescribes `set -e` + per-action log lines + structured success/failure output for batched scripts.

### Non-Functional Requirements

- **NFR-001 (testing — explicit per user direction)**: Every functional requirement above MUST land with at least one test that exercises it end-to-end. Acceptable substrates: `plugin-kiln/tests/<feature>/` skill-test fixtures, `plugin-wheel/workflows/tests/` workflow tests, or `plugin-wheel/tests/` shell-level unit tests for hook scripts. NO FR ships test-free, regardless of how mechanical the change looks.
- **NFR-002 (silent-failure tripwires)**: Every fix to a previously-silent failure (FR-009, FR-013) MUST add a test that fails when the regression returns AND emits a clearly identifiable error string (not a green-but-wrong outcome). The newline-flatten and the `WORKFLOW_PLUGIN_DIR`-unset bugs both shipped *because* their failure mode was silent — the regression tests must catch the silence itself, not just the symptom.
- **NFR-003 (hook input fuzzing)**: For FR-009 specifically, add a fuzz/property test over hook-input shapes — multi-line commands, quoted newlines, embedded control chars, valid-but-weird JSON escapes — asserting the hook never silently flattens `tool_input.command` characters that the LLM emitted.
- **NFR-004 (consumer-install simulation)**: FR-014's smoke test MUST run in CI on every PR that touches `plugin-wheel/` or any plugin's workflow JSON. Local-only smoke tests don't count — the entire bug shape is "works locally, breaks in consumer install."
- **NFR-005 (backward compat)**: `agent_path:` and `model:` are additive workflow JSON fields. Workflows that don't use them MUST behave byte-identically to today.
- **NFR-006 (perf measurement)**: FR-019's before/after measurement uses real wall-clock timing on the same hardware in the same session window. No napkin estimates.
- **NFR-007 (atomic migration window)**: FR-002's agent-file relocation runs in one PR with redirects/symlinks at the old paths, NOT a multi-PR rolling migration. Half-migrated state confuses both wheel's resolver and human readers.

## User Stories

- **As a kiln skill author**, I want to spawn the `qa-engineer` agent from `/kiln:kiln-fix` directly (not by wrapping the call in a wheel workflow), so I can use specialized agents in skill-level debug loops.
- **As a workflow author**, I want to mark a classification step as `model: haiku` and a synthesis step as `model: sonnet`, so I'm not paying opus prices for pattern-match work.
- **As a consumer running an installed plugin**, I want `/kiln:kiln-report-issue` to actually update the counter and append the bg log on my machine, not silently no-op because `WORKFLOW_PLUGIN_DIR` was unset.
- **As a workflow author who batches multi-line shell setup before activating**, I want my activation to fire even though my Bash tool call has `\n`s in it — without having to remember to split it into a single-line call.
- **As a workflow author**, I want to consolidate the deterministic command sequence inside one of my agent steps into a single wrapper script, so the workflow runs noticeably faster without changing semantics.

## Success Criteria

- **SC-001**: All FR-001..FR-020 land with passing tests (NFR-001 enforced).
- **SC-002**: Running `/kiln:kiln-report-issue` from the consumer-install simulation produces a non-empty `.kiln/logs/report-issue-bg-<date>.md` line and increments the counter — verified by FR-014's smoke test, which is wired into CI per NFR-004.
- **SC-003**: A multi-line Bash tool call that activates a workflow succeeds without a "single-line Bash call" workaround, verified by FR-009's hook-input fuzz test.
- **SC-004**: At least one wheel workflow shows a measurable wall-clock speedup from FR-018's step-batching prototype, with raw before/after numbers committed in the audit doc.
- **SC-005**: A kiln skill (one is enough — `/kiln:kiln-fix` is the documented target) demonstrates spawning a specialized agent via the FR-001 resolver path, with a test that fails if the resolver returns the wrong spec.
- **SC-006**: At least one wheel workflow uses the new `model:` field in its shipped form, demonstrating the per-step model selection path end-to-end.
- **SC-007**: `git grep -F 'WORKFLOW_PLUGIN_DIR was unset'` returns zero matches in `.kiln/logs/report-issue-bg-*.md` written after this PRD ships.

## Tech Stack

Inherited from current wheel + plugin substrate. No new dependencies.
- Bash 5.x, `jq`, POSIX utilities for hook scripts, resolver scripts, and step-batching wrappers.
- Optional `python3 -c "import json,sys; …"` for JSON-aware control-char sanitization in FR-009 fallback.
- Existing wheel team primitives (`TeamCreate`, `TaskCreate`, etc.) for any test harness needs.
- Existing kiln skill-test harness (`plugin-kiln/tests/`) and `/wheel:wheel-test` for FR-014's CI integration.

## Risks & Open Questions

- **R-001**: FR-013's "wheel exports `WORKFLOW_PLUGIN_DIR` for the workflow's lifetime" depends on whether the Agent tool's env-inheritance for background spawns is something wheel can influence at all. If the harness baselines its own env (the source-issue's hypothesis), wheel may need to fall back to FR-013 Option B (template the absolute path into the sub-agent prompt at dispatch time). The implementation phase MUST verify Option A is technically achievable before committing — if it isn't, document the constraint and ship Option B with a louder FR-016-style tripwire.
- **R-002**: FR-002's atomic agent-file migration touches every plugin in this repo. Coordination cost is real — a stale reference left in any plugin breaks the resolver. Mitigation: a dedicated test that walks every workflow JSON + every kiln skill and asserts every `agent` reference resolves through FR-001.
- **R-003**: FR-006's `model:` field interacts with the harness's billing/quota model. If specifying `opus` per-step has cost implications the harness wants to gate, the implementation may need a config knob to allow/deny model overrides per-project. Open question for the planning phase.
- **R-004**: FR-009's hook fix may surface latent bugs in OTHER hook regexes that were previously masked by the flatten. If the activate-detection regex was the only one relying on flattened input, no follow-up; if other regexes regress, they get treated as part of this PRD's blast radius and fixed in the same PR.
- **R-005**: FR-018's step-batching prototype could discover that the round-trip latency claim is wrong (e.g. dominated by something else like cold-start), in which case the audit doc should still ship with the negative result documented and the FR scope re-narrows to that finding. Don't force a positive result.
- **OQ-001**: Should the agent resolver (FR-001) live in `plugin-wheel/scripts/agents/` or be exposed as a wheel skill (`/wheel:wheel-resolve-agent`)? Skill form is more discoverable but adds ceremony for callers. Decide in the planning phase.
- **OQ-002**: For FR-006, do we want to allow `model:` to be a comma-separated fallback list (e.g. `model: haiku-4-5,sonnet-4-6`) for graceful degradation, or strictly one model per step? Deferred to planning.

## Pipeline guidance

This wants the **full pipeline** — specifier → plan (with interface contracts for the resolver) → tasks → implement (with `qa-engineer` running alongside on the hook fix) → auditor (verifies no silent-failure regression) → retrospective (focus: why these silent-failure modes shipped in the first place; what tests would have caught them earlier — feeds the FR-009/FR-013 fuzz/smoke tests as the canonical answer).
