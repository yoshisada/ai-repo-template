# Feature Specification: Cross-Plugin Resolver + Pre-Flight Plugin Registry

**Feature Branch**: `build/cross-plugin-resolver-and-preflight-registry-20260424`
**Created**: 2026-04-24
**Status**: Draft
**Input**: `docs/features/2026-04-24-cross-plugin-resolver-and-preflight-registry/PRD.md`

## Overview

Wheel today exposes only the calling workflow's plugin path (`WORKFLOW_PLUGIN_DIR`, Theme D Option B) and delegates path resolution for everything else to the agent at runtime. Agents compensate with environment-specific hardcoded fallbacks (e.g. `${WORKFLOW_PLUGIN_DIR:-/Users/ryansuematsu/.claude/plugins/cache/.../shelf/000.001.009.247}/scripts/shelf-counter.sh`) that work on the developer's machine and silently break on every consumer install. This feature makes wheel a real runtime by giving it (1) a fresh-per-workflow plugin registry built from authoritative session data, (2) a workflow JSON schema field declaring plugin dependencies explicitly, (3) a pre-flight resolver that fails loud on missing deps before any side effects, and (4) a preprocessor that templates absolute paths inline before any agent prompt is built. After this PRD ships, agent prompts contain only literal absolute paths — no `${VAR}` syntax for plugin paths.

Five themes, one feature:
- **Theme F1** — Plugin registry build (FR-F1-1..FR-F1-5)
- **Theme F2** — Workflow JSON schema additions (FR-F2-1..FR-F2-3)
- **Theme F3** — Pre-flight resolver (FR-F3-1..FR-F3-3)
- **Theme F4** — Preprocessor + tripwire (FR-F4-1..FR-F4-6)
- **Theme F5** — Atomic migration of `kiln-report-issue.json` (FR-F5-1..FR-F5-3)

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Cross-plugin script reference works on every consumer install (Priority: P1)

A workflow author writing `plugin-kiln/workflows/kiln-report-issue.json` declares `requires_plugins: ["shelf"]` at the top of the workflow and references shelf scripts as `${WHEEL_PLUGIN_shelf}/scripts/shelf-counter.sh`. The workflow runs correctly on every consumer install — marketplace cache, `--plugin-dir` development, `settings.local.json` project-scoped — because wheel resolves the absolute path from the session registry before the agent ever sees the instruction text.

**Why this priority**: This is the production bug. The cross-plugin reference in `kiln-report-issue.json` silently no-ops on consumer installs today (verified in `.wheel/history/success/kiln-report-issue-20260424-134020-...json`). Every other theme exists to make this story passable in a clean, testable, regression-resistant way.

**Independent Test**: Run `/kiln:kiln-report-issue` from a temp dir with `--plugin-dir` overrides for kiln + shelf. Assert the bg sub-agent successfully shells into the shelf-resident scripts (counter increments, log line written) and the absolute path captured in `command_log` resolves under the override location, not the source-repo cache version.

**Acceptance Scenarios**:

1. **Given** `kiln-report-issue.json` declares `requires_plugins: ["shelf"]` and references `${WHEEL_PLUGIN_shelf}/scripts/shelf-counter.sh`, **When** wheel activates the workflow, **Then** the templated instruction text contains the absolute path to the shelf install (e.g. `/abs/path/to/plugin-shelf/scripts/shelf-counter.sh`) and contains no `${...}` syntax for plugin paths.
2. **Given** a marketplace-cache install layout (`~/.claude/plugins/cache/<org-mp>/shelf/<version>/`), **When** the workflow runs, **Then** the registry resolves shelf to the cache path and the bg log line records `counter_after=N+1`.
3. **Given** a `--plugin-dir /tmp/.../plugin-shelf-dev/` override coexisting with a marketplace-cache shelf, **When** the workflow runs, **Then** the override path wins and the scripts under the override are executed (verified by a marker file written only by the override copy).
4. **Given** a `settings.local.json` enabling shelf at a project-scoped path, **When** the workflow runs, **Then** resolution succeeds and matches the local-settings path.

---

### User Story 2 — Pre-flight failure on missing dependency (Priority: P1)

A workflow declares `requires_plugins: ["nonexistent"]`. Wheel fails at workflow-start with a clear, programmatically-recognizable error before any agent step is dispatched, before any state file mutation, before any side effect. The user sees `Workflow 'X' requires plugin 'nonexistent', but 'nonexistent' is not enabled in this session.` and the workflow exits non-zero.

**Why this priority**: Loud-failure on missing deps is what separates this PRD from "the agent silently no-ops." It's the entire reason to build a pre-flight phase rather than letting the agent discover the gap at the first Bash tool call.

**Independent Test**: A fixture workflow with `requires_plugins: ["nonexistent"]` is activated. Assert: (a) state file is NOT created, (b) no agent step is dispatched, (c) stderr/log contains the documented error text, (d) exit code is non-zero.

**Acceptance Scenarios**:

1. **Given** a workflow declaring `requires_plugins: ["X"]` where X is not in the session registry, **When** the workflow is activated, **Then** wheel exits non-zero with the documented error text BEFORE any step runs.
2. **Given** a plugin physically present in `~/.claude/plugins/cache/` but not in `enabledPlugins` in settings, **When** a workflow declares it as a requirement, **Then** the failure mode is identical to "not installed at all" — `'<X>' is not enabled in this session`.
3. **Given** a workflow declaring an unresolved token (`${WHEEL_PLUGIN_unknown}` with no matching `requires_plugins` entry), **When** the preprocessor runs, **Then** it fails with the documented "references unknown plugin token" error and no agent dispatch occurs.

---

### User Story 3 — No `${VAR}` syntax in any agent prompt (Priority: P1)

An auditor inspecting any wheel-spawned agent prompt — foreground or background — sees only literal absolute paths for plugin scripts. The string `${WORKFLOW_PLUGIN_DIR}`, `${WHEEL_PLUGIN_<anything>}`, or any other plugin-path variable substitution syntax NEVER appears in any dispatched instruction text.

**Why this priority**: This is the structural invariant that makes the silent-failure class of bug impossible to re-ship. As long as agents do their own variable substitution, the next plugin author hits the same gap. The tripwire enforces "wheel resolves paths; agents run literal commands."

**Independent Test**: `git grep -E '\$\{(WORKFLOW_PLUGIN_DIR|WHEEL_PLUGIN_)[^}]*\}' .wheel/history/success/*.json` returns zero matches for any agent step's `command_log` post-PRD across all migrated workflows.

**Acceptance Scenarios**:

1. **Given** any workflow run after this PRD ships, **When** an agent step's instruction is dispatched, **Then** the instruction text contains zero matches for `${WORKFLOW_PLUGIN_DIR}` or `${WHEEL_PLUGIN_<name>}` patterns.
2. **Given** a templated instruction containing the literal escape `$${WHEEL_PLUGIN_shelf}` (workflow author wants to document the syntax), **When** the preprocessor runs, **Then** the escape is decoded to the literal string `${WHEEL_PLUGIN_shelf}` and the tripwire allows it through.
3. **Given** the tripwire detects an unescaped `${` in a templated instruction, **When** dispatch is about to happen, **Then** wheel fails loud with the documented "Wheel preprocessor failed" error and no dispatch occurs.

---

### User Story 4 — Backward compat for unchanged workflows (Priority: P2)

The five workflows that don't reference cross-plugin scripts (`kiln-fix.json`, `shelf-sync.json`, etc.) and don't declare `requires_plugins` continue to behave byte-identically to today. Their state files, log files, and agent prompts produce no diff against a pre-PRD snapshot.

**Why this priority**: P2 because the PRD's core value is in P1; this story is the "do no harm" guarantee. It's mandatory but not the reason to ship.

**Independent Test**: Re-run an unchanged workflow against the post-PRD code. Diff the resulting `.wheel/state_<id>.json` and `wheel.log` lines against a recorded pre-PRD snapshot. Diff must be empty modulo timestamps and run IDs.

**Acceptance Scenarios**:

1. **Given** a workflow with no `requires_plugins` field, **When** it runs against post-PRD code, **Then** the state file's `steps[]` array, the agent prompts, and the side effects are byte-identical to the pre-PRD snapshot.
2. **Given** a workflow using the legacy `${WORKFLOW_PLUGIN_DIR}` token (no migration to `${WHEEL_PLUGIN_<calling-plugin>}`), **When** it runs, **Then** the legacy token resolves correctly via the new preprocessor (subsumed Theme D code path) and the agent sees the same absolute path it would have seen pre-PRD.

---

### User Story 5 — Perf gate (Priority: P2)

Adding pre-flight resolution + preprocessing must not regress `/kiln:kiln-report-issue` foreground wall-clock or `duration_api_ms` by more than 20% over the recorded baseline. Resolver overhead alone (no deps declared) must add <200ms.

**Why this priority**: P2 because it's a quantitative quality gate, not a user-visible feature. But exceeding the gate blocks merge per Absolute Must #3.

**Independent Test**: Re-run `plugin-kiln/tests/kiln-report-issue-batching-perf/` against post-PRD code. Compare median wall-clock and median `duration_api_ms` against `results-2026-04-24-with-tokens.tsv` at commit `b81aa25`. Both must be ≤120% of baseline.

**Acceptance Scenarios**:

1. **Given** the perf fixture, **When** it runs against post-PRD code, **Then** median wall-clock and median `duration_api_ms` are within 120% of the `b81aa25` baseline.
2. **Given** a workflow with empty `requires_plugins: []` (or no field at all), **When** the resolver runs, **Then** the resolver phase adds ≤200ms to workflow start time (measured via `time` in a kiln-test fixture).

---

## Functional Requirements

### Theme F1 — Plugin registry build

- **FR-F1-1**: `plugin-wheel/lib/registry.sh::build_session_registry` MUST emit a JSON map of `{name: absolute_path}` for every plugin currently loaded in the Claude Code session, regardless of install mode (marketplace cache, `--plugin-dir`, `settings.local.json`).
- **FR-F1-2**: Discovery uses Candidate A from OQ-F-1 (`$PATH` parsing of plugin `/bin` entries). The resulting registry MUST be correct under all three install modes. Fallback to Candidate B (settings + cache walk) is implemented behind a flag and triggered only if Candidate A returns an empty registry. (Decision recorded in `research.md` §1.)
- **FR-F1-3**: The registry MUST NOT include plugins that are physically installed but not enabled in this session. Under Candidate A this is automatic (Claude Code only PATH-injects enabled plugins); under Candidate B, settings parsing enforces the rule explicitly.
- **FR-F1-4**: `--plugin-dir` overrides MUST win over marketplace cache entries with the same plugin name. Under Candidate A this is automatic (PATH order: overrides prepend); under Candidate B, the override is detected and prioritized.
- **FR-F1-5**: Registry build runs fresh on every `/wheel:wheel-run` invocation. No persistent cache. No session-level cache. A diagnostic snapshot is written to `.wheel/state/<run-id>-registry.json` for post-mortem use; deleted on workflow success, retained on workflow failure (matches OQ-F-2 v1 plan).

### Theme F2 — Workflow JSON schema additions

- **FR-F2-1**: Workflow JSON gains an optional top-level array field `requires_plugins`. Each entry is a plugin name (bare string).
- **FR-F2-2**: Existing workflows without `requires_plugins` MUST continue to behave byte-identically to today. The field's absence MUST NOT trigger registry build, resolver, or preprocessor side effects beyond the legacy `WORKFLOW_PLUGIN_DIR` templating already performed by `context_build` (which becomes a special case of the new preprocessor).
- **FR-F2-3**: Schema validation runs at pre-flight via `workflow_load`. Malformed entries (non-string, empty string, duplicate name) fail loudly with a recognizable error text.

### Theme F3 — Pre-flight resolver

- **FR-F3-1**: `plugin-wheel/lib/resolve.sh::resolve_workflow_dependencies` MUST run after `workflow_load` and BEFORE any state-file mutation, agent step dispatch, or side effect.
- **FR-F3-2**: For each entry in `requires_plugins`, the resolver verifies the plugin is in the registry built by `build_session_registry`. Failure → exit non-zero with the documented error text, no side effects.
- **FR-F3-3**: All failure modes (missing plugin, unresolved token, tripwire violation, malformed schema) MUST produce errors with the documented text shape so users (and tests) can recognize them programmatically. Specifically:
  - Missing plugin: `Workflow '<name>' requires plugin '<X>', but '<X>' is not enabled in this session. Enable it in ~/.claude/settings.json or pass --plugin-dir.`
  - Unresolved token: `Workflow '<name>' references unknown plugin token '${WHEEL_PLUGIN_<X>}'. Add '<X>' to requires_plugins.`
  - Tripwire violation: `Wheel preprocessor failed: instruction text for step '<id>' still contains '${...}'. This is a wheel runtime bug; please file an issue.`

### Theme F4 — Preprocessor + tripwire

- **FR-F4-1**: `plugin-wheel/lib/preprocess.sh::template_workflow_json` MUST run after the resolver and before any agent step is dispatched. It accepts the workflow JSON + the registry JSON and returns a templated workflow JSON with all path tokens substituted.
- **FR-F4-2**: For each agent step's `instruction` field, the preprocessor substitutes every `${WHEEL_PLUGIN_<name>}` token with the absolute path of the named plugin from the registry.
- **FR-F4-3**: The legacy `${WORKFLOW_PLUGIN_DIR}` token (Theme D Option B) is preserved and resolved by the same mechanism — it becomes equivalent to `${WHEEL_PLUGIN_<calling-plugin>}` where `<calling-plugin>` is derived from the workflow file's plugin install dir (same computation `context_build` uses today).
- **FR-F4-4**: Escaped tokens (`$${...}`) are preserved post-substitution as literal `${...}` strings, allowing workflow text to mention the syntax for documentation.
- **FR-F4-5**: After substitution, a tripwire assertion verifies no unescaped `${WHEEL_PLUGIN_` or `${WORKFLOW_PLUGIN_DIR` substring remains in any instruction text. Failure → loud error, no dispatch. (The tripwire pattern is narrowed to plugin-path tokens specifically per R-F-3 mitigation — generic `${VAR}` syntax in instruction text for legitimate user-typed shell substitution does not trip the wire.)
- **FR-F4-6**: After this PRD ships, no agent prompt produced by wheel contains plugin-path variable substitution syntax — only literal absolute paths. Verified by SC-F-6.

### Theme F5 — Atomic migration of `kiln-report-issue.json`

- **FR-F5-1**: `plugin-kiln/workflows/kiln-report-issue.json` is updated:
  - Add `requires_plugins: ["shelf"]` at top level (after `version`).
  - Replace `${WORKFLOW_PLUGIN_DIR}/scripts/shelf-counter.sh` with `${WHEEL_PLUGIN_shelf}/scripts/shelf-counter.sh` in the `dispatch-background-sync` step instruction.
  - Same substitution for `append-bg-log.sh` and `step-dispatch-background-sync.sh`.
- **FR-F5-2**: No other workflow JSONs need migration. The other six workflows using `${WORKFLOW_PLUGIN_DIR}` reference scripts in their own plugin and continue to work via the legacy-token code path (FR-F4-3).
- **FR-F5-3**: After migration, the cross-plugin resolution gap documented in `.kiln/issues/2026-04-24-kiln-report-issue-workflow-plugin-dir-cross-plugin-gap.md` is closed. The bg log line contains `counter_after=N+1` on a clean consumer-install run.

## Non-Functional Requirements

- **NFR-F-1 (testing substrate)**: Every FR-F1..F5 above MUST land with at least one test that exercises it end-to-end. The test substrate is **`/kiln:kiln-test`** for any FR whose claim depends on real agent-session behavior (registry build under `--plugin-dir`, full workflow resolution end-to-end, perf comparison). Pure-shell unit tests are acceptable for resolver / preprocessor logic that has no LLM in the loop (e.g. preprocess-tripwire token substitution).
- **NFR-F-2 (silent-failure tripwires)**: Each documented failure mode (plugin not loaded, unresolved token, tripwire violation) MUST have a regression test that fails when the failure becomes silent (e.g. resolver errors are swallowed by `|| true`, preprocessor fails open, registry returns wrong path with no error). The tripwire test catches the SILENCE, not just the symptom — verified by mutation: deliberately weaken the failure handling and assert the test fails.
- **NFR-F-3 (install-mode coverage)**: Test coverage MUST exercise all three install modes — marketplace cache, `--plugin-dir`, `settings.local.json` — for the registry build and for end-to-end workflow resolution. A test that passes only in the source-repo "happy path" does not count.
- **NFR-F-4 (perf gate — blocker)**: Post-PRD `/kiln:kiln-report-issue` median **wall-clock** AND median **`duration_api_ms`** MUST NOT regress by more than **20%** over the Option B baseline at commit `b81aa25` (`plugin-kiln/tests/kiln-report-issue-batching-perf/results-2026-04-24-with-tokens.tsv`). Other metrics (output_tokens, cache_read_input_tokens, total_cost_usd) are reported but informational only.
- **NFR-F-5 (backward compat — strict)**: Workflows without `requires_plugins` MUST behave byte-identically to today (instruction text, agent prompt, side effects). Verified by `back-compat-no-requires/` fixture (#7) which re-runs an unchanged workflow and diffs the resulting state file + log file against a pre-PRD snapshot.
- **NFR-F-6 (resolver perf)**: The pre-flight resolver itself MUST add no more than **200ms** to workflow start time on a workflow with 0 dependencies declared. Measured via `time` in the perf fixture.
- **NFR-F-7 (atomic migration)**: FR-F5's migration of `kiln-report-issue.json` lands in the same commit as the resolver/registry/preprocessor implementation. No half-state where the workflow declares `requires_plugins` but the resolver isn't running yet.
- **NFR-F-8 (wheel self-hosting)**: Wheel itself can use `requires_plugins` in its own workflows. Pre-flight resolver bootstraps cleanly — wheel knows its own install path via `BASH_SOURCE` resolution and is included in the registry like any other plugin.

## Success Criteria

- **SC-F-1**: All FR-F1..F5 land with passing tests. NFR-F-1 enforced.
- **SC-F-2**: All three install modes (marketplace cache, `--plugin-dir`, `settings.local.json`) verified end-to-end via `/kiln:kiln-test` fixtures. NFR-F-3 enforced.
- **SC-F-3**: `kiln-report-issue.json` declares `requires_plugins: ["shelf"]` and uses `${WHEEL_PLUGIN_shelf}/scripts/...` for cross-plugin references. The cross-plugin gap is closed.
- **SC-F-4**: Running the perf fixture against post-PRD code shows median wall-clock and median `duration_api_ms` within 120% of the `b81aa25` baseline. NFR-F-4 satisfied.
- **SC-F-5**: A consumer-install simulation of `/kiln:kiln-report-issue` (run from a temp dir with `--plugin-dir` overrides for kiln + shelf) succeeds and writes the expected bg log line.
- **SC-F-6**: `git grep -E '\$\{(WORKFLOW_PLUGIN_DIR|WHEEL_PLUGIN_)[^}]*\}' .wheel/history/success/*.json` returns zero matches for plugin-path tokens in any agent step's `command_log` post-PRD. The agent never sees `${VAR}` syntax for plugin paths.
- **SC-F-7**: Each documented failure mode produces its documented error text, verified by the corresponding NFR-F-2 tripwire test.

## Edge Cases

- **EC-1 (plugin not in PATH but in cache)**: A plugin that has been installed but is disabled in `enabledPlugins` MUST NOT appear in the registry. Candidate A handles this automatically (Claude Code does not PATH-inject disabled plugins). Verified by `resolve-disabled-plugin/` fixture.
- **EC-2 (multiple versions in cache)**: When the registry detects multiple version directories under the same plugin (`~/.claude/plugins/cache/<org-mp>/<plugin>/<v1>` AND `<v2>`), the version actually loaded in the session is the only one in PATH; that wins. Candidate B fallback uses settings to pick the named version, falling back to the highest version dir.
- **EC-3 (workflow declares plugin not yet loaded mid-session)**: If a user enables a plugin in settings without restarting the session, the new plugin is not in PATH. The next `/wheel:wheel-run` call sees the registry without it. Pre-flight fails with the "not enabled in this session" message — user is told to restart.
- **EC-4 (legitimate `${...}` in instruction text)**: A workflow author writes `for f in "${files[@]}"; do ...` in an instruction. The narrowed tripwire pattern (matches only `${WHEEL_PLUGIN_*}` and `${WORKFLOW_PLUGIN_DIR}`) does NOT trigger. Verified by `back-compat-no-requires/` fixture using a workflow that contains generic `${VAR}` syntax.
- **EC-5 (escaped token `$${WHEEL_PLUGIN_shelf}`)**: Decoded to literal `${WHEEL_PLUGIN_shelf}` post-preprocess; tripwire allows it (post-decode the escaped form looks identical to a violation but the preprocessor records the escape position and skips it).

## Assumptions

- **A-1**: Candidate A (`$PATH` parsing) works under all three install modes. Verified for marketplace-cache mode in the source-repo session (PATH inspection above). Verified for `--plugin-dir` in the spec-phase research (research.md §1.B). Verified for `settings.local.json` in the spec-phase research (research.md §1.C). If verification fails for any mode, fall back to Candidate B per FR-F1-2.
- **A-2**: The `/kiln:kiln-test` harness can scaffold install-mode fixtures (fake `~/.claude/plugins/cache/`, fake `settings.json`, `--plugin-dir` invocation) under `/tmp/kiln-test-<uuid>/`. High-confidence given the harness already scaffolds full plugin directories for skill testing.
- **A-3**: The current Option B mechanism (Theme D) does not have downstream consumers outside this repo whose behavior would be affected by subsuming it under the new preprocessor — `WORKFLOW_PLUGIN_DIR` continues to work via the same code path.
- **A-4**: Wheel itself is in the session registry. `BASH_SOURCE` resolution from `plugin-wheel/lib/*.sh` produces an absolute path that the registry can use to bootstrap before any other plugin's path is computed.

## Dependencies

- **D-1**: Theme D Option B (`plugin-wheel/lib/context.sh::context_build`) — this PRD subsumes Option B's `WORKFLOW_PLUGIN_DIR` templating. The Option B code is not removed; it is refactored to call the new preprocessor under the hood.
- **D-2**: `plugin-kiln/tests/kiln-report-issue-batching-perf/` fixture — this PRD's perf gate (NFR-F-4) reuses the fixture and the recorded baseline at commit `b81aa25`.
- **D-3**: `/kiln:kiln-test` substrate — this PRD heavily uses it for end-to-end install-mode and tripwire fixtures (NFR-F-1, NFR-F-3).
- **D-4**: `plugin-wheel/lib/workflow.sh` (workflow_load) — this PRD adds schema validation for `requires_plugins` here.
- **D-5**: `plugin-wheel/scripts/dispatch/` — the resolver + preprocessor outputs feed into the existing dispatch path. No dispatcher rewrite.

## Out of Scope (v1)

- Persistent or session-level registry cache (deferred to v2 if perf becomes a concern).
- Mid-workflow re-resolution after plugin updates (deferred to v2; per user direction).
- Breaking changes to existing workflows; all backward-compat per NFR-F-5.
- Version constraints on `requires_plugins` (e.g. `min_version`) — deferred to v2.
- Recursive sub-workflow resolution (`requires_workflows`) — deferred to v2.
- Symlink-aware resolution — Claude Code does not use `current/` symlinks today.
- Auto-migration of every workflow — only `kiln-report-issue.json` is migrated.
- Packaging as a separately-installable plugin — this is a wheel runtime change.
