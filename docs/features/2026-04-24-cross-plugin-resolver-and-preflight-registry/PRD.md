---
derived_from:
  - .kiln/issues/2026-04-24-kiln-report-issue-workflow-plugin-dir-cross-plugin-gap.md
  - .kiln/issues/2026-04-24-themeE-t092-shipped-without-llm-layer-measurement.md
distilled_date: 2026-04-24
theme: cross-plugin-resolver-and-preflight-registry
---
# Feature PRD: Cross-Plugin Resolver + Pre-Flight Plugin Registry

**Date**: 2026-04-24
**Status**: Draft (v2 — revised after architectural exploration)
**Parent PRD**: [docs/PRD.md](../../PRD.md)
**Builds on**: PR #161 (wheel-as-runtime), specifically Theme D Option B in `plugin-wheel/lib/context.sh::context_build`. Does NOT block #161 — this PRD ships independently after #161 merges.

## Parent Product

This is the **kiln** Claude Code plugin ecosystem (`@yoshisada/kiln` + sibling plugins `wheel`, `shelf`, `clay`, `trim`). Wheel acts as the runtime that other plugins compose workflows on top of. This feature hardens wheel's runtime contract for cross-plugin script references — making it possible to compose helpers from sibling plugins without runtime guesswork.

## Honest scope statement

This is **forward-looking architecture**, not an acute hotfix.

The cross-plugin gap exists today in exactly **one** workflow file: `plugin-kiln/workflows/kiln-report-issue.json` references three scripts in `plugin-shelf/scripts/`. The other six workflow files using `${WORKFLOW_PLUGIN_DIR}` reference scripts in their own plugin and work correctly.

The acute production bug can be closed in 30 minutes by moving those three scripts into `plugin-kiln/scripts/`. **That hotfix is documented in the "Alternatives Considered" section below, and is the right move if multi-plugin script composition is not on the roadmap.**

This PRD is for the case where multi-plugin composition IS on the roadmap — where wheel-as-runtime needs to support workflows-of-plugin-A invoking helpers-of-plugin-B as a first-class pattern, not a curiosity. The architecture is built so that "compose from a sibling plugin" is one declaration in JSON, not a search-the-filesystem-and-pray dance.

## Feature Overview

Make wheel a real runtime by giving it (1) a fresh-per-workflow plugin registry that discovers loaded plugins from authoritative session data, (2) a workflow JSON schema that declares plugin dependencies explicitly, (3) a pre-flight resolver that fails loudly on missing deps before any side effects, and (4) a wheel-side preprocessor that templates absolute paths inline before any agent prompt is built. The agent never sees `${VAR}` syntax, never has to figure out paths, never silently rewrites references.

## Problem / Motivation

The wheel-as-runtime PR (#161) shipped Theme D Option B: when a workflow runs, wheel injects a "Runtime Environment" block into the agent prompt that names `WORKFLOW_PLUGIN_DIR` as the calling workflow's plugin's install path. This works for in-plugin script references but fails silently for cross-plugin references.

Concrete evidence: `plugin-kiln/workflows/kiln-report-issue.json` references `${WORKFLOW_PLUGIN_DIR}/scripts/shelf-counter.sh`, but that script lives in `plugin-shelf/scripts/`. Under Option B, `${WORKFLOW_PLUGIN_DIR}` resolves to plugin-kiln's path — the script is unreachable. The agent has been silently rewriting these paths with hardcoded fallbacks pointing at this developer's exact cache directory. Verified in `.wheel/history/success/kiln-report-issue-20260424-134020-...json`:

```bash
bash "${WORKFLOW_PLUGIN_DIR:-/Users/ryansuematsu/.claude/plugins/cache/yoshisada-speckit/shelf/000.001.009.247}/scripts/shelf-counter.sh" read
```

The hardcoded fallback works on the developer's machine; it breaks on every consumer install where home directory, plugin version, OS, or install mode (marketplace cache vs `--plugin-dir` vs `settings.local.json`) differs. Theme D's regression tripwire (`git grep -F 'WORKFLOW_PLUGIN_DIR was unset'`) does NOT catch this — the variable is set, just to the wrong plugin.

The architectural root cause: **wheel today exposes only one plugin path (the calling plugin) and delegates path resolution to the agent at runtime**. The agent compensates with environment-specific hardcoded paths. The right shape is the inverse: wheel resolves all path dependencies upfront from authoritative session data, templates absolute paths inline before the agent ever sees the instruction text, and fails loudly at workflow-start if any dependency is missing.

## Goals

- **Make cross-plugin script references work uniformly** across all three Claude Code plugin install modes (marketplace cache, `--plugin-dir`, `settings.local.json`).
- **Eliminate silent path-rewriting by agents.** After this PRD ships, no agent prompt should contain `${VAR}` syntax for plugin paths. The agent runs literal absolute paths.
- **Make plugin dependencies explicit and machine-readable.** Workflow authors declare dependencies up-front in workflow JSON. Wheel validates them before any side effects.
- **Preserve the user's intent.** Disabled plugins do not silently resolve. Explicit `--plugin-dir` overrides win over marketplace cache.
- **Bound the perf cost.** Pre-flight resolution adds at most 20% to foreground wall-clock and `duration_api_ms` of `/kiln:kiln-report-issue` (the canonical benchmark workflow). Anything beyond is a blocker.
- **Subsume Theme D's `WORKFLOW_PLUGIN_DIR` mechanism uniformly.** One code path for all path templating, in-plugin and cross-plugin.

## Non-Goals (v1)

- **Not** introducing a persistent plugin registry. Resolution is fresh-per-workflow-start, no persistent cache, no session-level cache (avoids stale paths after plugin updates).
- **Not** mid-workflow re-resolution. If a plugin updates while a workflow is running, the templated paths captured at workflow-start are used for the rest of the run. **Per user direction: not a v1 concern.**
- **Not** breaking existing workflows. Workflows without `requires_plugins` continue to behave exactly as today.
- **Not** redesigning the wheel hook execution model. The pre-flight resolver runs inside `plugin-wheel/lib/` at workflow activation; hook plumbing is unchanged.
- **Not** introducing version constraints. `requires_plugins` is a bare-string list in v1. No `min_version`, no SemVer. **Deferred to v2** — zero workflows declare dependencies today, so version pinning is speculative.
- **Not** introducing recursive sub-workflow resolution (`requires_workflows`). **Deferred to v2** — zero workflows in this repo invoke sub-workflows from other plugins. Building the recursive resolver against a synthetic fixture is cost without payoff.
- **Not** symlink-aware resolution. Claude Code does not use `current/` symlinks in the cache today (verified by `find ~/.claude/plugins/cache -type l`). v2 can revisit if Claude Code adds them.
- **Not** auto-migration of every workflow. Only `kiln-report-issue.json` has cross-plugin references. The migration touches one file plus the three scripts referenced from it.
- **Not** packaging as a separately-installable plugin. This is a wheel runtime change.

## Target Users

Inherited from the parent product:
- **Plugin authors** writing wheel workflow JSON files that compose helpers from sibling plugins.
- **Plugin consumers** running workflows in real installs (marketplace cache, `--plugin-dir` development, or `settings.local.json` project-scoped).
- **Pipeline runs** invoked via `/kiln:kiln-build-prd` and similar that depend on workflow correctness across machines.

## Solution Architecture (explicit per user request)

### Component overview

```
                          ┌──────────────────────────┐
                          │    User invokes          │
                          │ /wheel:wheel-run <name>  │
                          └──────────┬───────────────┘
                                     │
                                     ▼
                  ┌──────────────────────────────────────┐
                  │ plugin-wheel/lib/registry.sh         │
                  │ build_session_registry()             │
                  │                                      │
                  │ Reads ONE authoritative source       │
                  │ (decided in spec phase — see OQ-F-1):│
                  │                                      │
                  │   Candidate A (preferred): $PATH     │
                  │     parse plugin /bin entries        │
                  │     ~5 lines of bash                 │
                  │                                      │
                  │   Candidate B (fallback):            │
                  │     ~/.claude/settings.json +        │
                  │     <project>/.claude/settings.local │
                  │     +cache walk + plugin.json reads  │
                  │     ~50 lines of bash                │
                  │                                      │
                  │ Emits in-memory map:                 │
                  │   { plugin_name → absolute_path }    │
                  │   only LOADED+ENABLED plugins        │
                  │   --plugin-dir wins over cache       │
                  └──────────┬───────────────────────────┘
                             │
                             ▼
                  ┌──────────────────────────────────────┐
                  │ plugin-wheel/lib/resolve.sh          │
                  │ resolve_workflow_dependencies()      │
                  │                                      │
                  │ Reads workflow JSON's:               │
                  │   requires_plugins: [...]            │
                  │                                      │
                  │ For each entry:                      │
                  │   - Verify in registry.              │
                  │                                      │
                  │ On any failure: print clear error,   │
                  │   exit non-zero BEFORE step 1 runs.  │
                  └──────────┬───────────────────────────┘
                             │
                             ▼
                  ┌──────────────────────────────────────┐
                  │ plugin-wheel/lib/preprocess.sh       │
                  │ template_workflow_json()             │
                  │                                      │
                  │ For each agent step's instruction:   │
                  │   - Substitute ${WHEEL_PLUGIN_<n>}   │
                  │     → absolute path from registry    │
                  │   - Substitute ${WORKFLOW_PLUGIN_DIR}│
                  │     → calling plugin's path          │
                  │                                      │
                  │ Tripwire assertion:                  │
                  │   No literal '${' remains in the     │
                  │   templated instruction text. If     │
                  │   any present, fail loudly.          │
                  └──────────┬───────────────────────────┘
                             │
                             ▼
                ┌────────────────────────────────────┐
                │  Wheel dispatches step 1.          │
                │  Agent prompt has only literal     │
                │  absolute paths. No ${VAR} syntax.  │
                │  Bash tool calls hit real files     │
                │  every time, every machine.         │
                └────────────────────────────────────┘
```

### Data flow

1. **`/wheel:wheel-run <name>` invoked** → wheel's activate.sh resolves the workflow JSON file path (today's mechanism, unchanged).
2. **Registry build** → `build_session_registry()` runs in <50ms, produces a `name → path` map of currently-loaded plugins. In-memory only; written to a per-run scratch file at `.wheel/state/<run-id>-registry.json` for diagnostic purposes (deleted on workflow completion).
3. **Pre-flight resolution** → `resolve_workflow_dependencies()` reads the workflow JSON's new top-level `requires_plugins`, validates each entry against the registry. Any failure prints a clear error and exits before step 1.
4. **Preprocessor** → `template_workflow_json()` walks the workflow JSON object, finds every agent step's `instruction` text, substitutes all `${WHEEL_PLUGIN_<n>}` and `${WORKFLOW_PLUGIN_DIR}` tokens with absolute paths from the registry. Returns a templated JSON object.
5. **Tripwire** → assertion that no `${` remains in any instruction text (with one allowed escape: `$${` literal escape, decoded back to `${` post-tripwire for cases where workflow text genuinely needs to mention dollar-brace syntax).
6. **Dispatch** → templated JSON drives the existing wheel step-execution path. Agent prompts are built from the templated instruction text. Agent never sees `${VAR}` for plugin paths.

### Workflow JSON schema additions

One additive top-level field, optional. Existing workflows without it continue to work (backward compat per NFR-F-5).

```json
{
  "name": "kiln-report-issue",
  "version": "1.0.0",
  "requires_plugins": ["shelf"],
  "steps": [
    {
      "id": "dispatch-background-sync",
      "type": "agent",
      "instruction": "...bash \"${WHEEL_PLUGIN_shelf}/scripts/step-dispatch-background-sync.sh\"..."
    }
  ]
}
```

- `requires_plugins`: array of plugin names (bare strings). Validated at pre-flight against the registry.
- `${WHEEL_PLUGIN_<name>}`: token recognized by the preprocessor. Replaced with the named plugin's absolute install path.
- `${WORKFLOW_PLUGIN_DIR}`: existing token, preserved for backward compat. Resolves to the calling workflow's plugin's path. After this PRD, it's a special case of `${WHEEL_PLUGIN_<calling-plugin>}` — same code path.

### Registry semantics

- **Discovery sources**: in priority order — `--plugin-dir` flags (highest), `<project>/.claude/settings.local.json`, `~/.claude/settings.json`, marketplace cache walk (lowest). The exact mechanism is decided in spec phase per OQ-F-1.
- **Loaded-not-installed rule**: a plugin physically present in the cache but not enabled in settings is NOT in the registry. Workflows requiring it fail at pre-flight with `Workflow requires plugin '<name>', but '<name>' is not enabled in this session.`
- **Multiple-version rule**: when settings names a specific version, that version wins; when no version is named, the highest version dir wins.

### Failure modes (each must produce a clear, recognizable error and exit before step 1)

| Mode | Trigger | Error text |
|---|---|---|
| **Plugin not loaded** | `requires_plugins: ["X"]` but X is not in registry | `Workflow '<name>' requires plugin '<X>', but '<X>' is not enabled in this session. Enable it in ~/.claude/settings.json or pass --plugin-dir.` |
| **Unresolved token** | `${WHEEL_PLUGIN_unknown}` in instruction text | `Workflow '<name>' references unknown plugin token '${WHEEL_PLUGIN_unknown}'. Add 'unknown' to requires_plugins.` |
| **Tripwire violation** | Templated instruction still contains `${...}` | `Wheel preprocessor failed: instruction text for step '<id>' still contains '${...}'. This is a wheel runtime bug; please file an issue.` |

## Functional Requirements

### Theme F1 — Plugin registry

- **FR-F1-1**: `plugin-wheel/lib/registry.sh::build_session_registry` MUST emit a JSON map of `{name: absolute_path}` for every plugin currently loaded in the Claude Code session, regardless of install mode (marketplace cache, `--plugin-dir`, `settings.local.json`).
- **FR-F1-2**: Discovery uses ONE of the candidate mechanisms documented in OQ-F-1 (decided in spec phase). Whichever wins, the resulting registry MUST be correct under all three install modes.
- **FR-F1-3**: The registry MUST NOT include plugins that are physically installed but not enabled in this session.
- **FR-F1-4**: `--plugin-dir` overrides win over marketplace cache entries with the same plugin name.
- **FR-F1-5**: Registry build runs fresh on every `/wheel:wheel-run` invocation. No persistent cache. No session-level cache. Per-run diagnostic snapshot written to `.wheel/state/<run-id>-registry.json` for debugging, deleted on workflow completion.

### Theme F2 — Workflow JSON schema additions

- **FR-F2-1**: Workflow JSON gains an optional top-level array field `requires_plugins`. Each entry is a plugin name (bare string).
- **FR-F2-2**: Existing workflows without `requires_plugins` MUST continue to behave byte-identically to today (NFR-F-5 backward compat).
- **FR-F2-3**: Schema validation runs at pre-flight. Malformed entries (non-string, empty) fail loudly.

### Theme F3 — Pre-flight resolver

- **FR-F3-1**: `plugin-wheel/lib/resolve.sh::resolve_workflow_dependencies` MUST run before any agent step is dispatched.
- **FR-F3-2**: For each entry in `requires_plugins`, the resolver verifies the plugin is in the registry. Failure → exit non-zero with the documented error text, no side effects.
- **FR-F3-3**: All failure modes (missing plugin, unresolved token, tripwire violation, malformed schema) produce errors with the documented text shape so users (and tests) can recognize them programmatically.

### Theme F4 — Preprocessor

- **FR-F4-1**: `plugin-wheel/lib/preprocess.sh::template_workflow_json` MUST run after the resolver and before any agent step is dispatched.
- **FR-F4-2**: For each agent step's `instruction` field, the preprocessor substitutes every `${WHEEL_PLUGIN_<name>}` token with the absolute path of the named plugin from the registry.
- **FR-F4-3**: The legacy `${WORKFLOW_PLUGIN_DIR}` token (Theme D Option B) is preserved and resolved by the same mechanism — it becomes equivalent to `${WHEEL_PLUGIN_<calling-plugin>}`.
- **FR-F4-4**: Escaped tokens (`$${...}`) are preserved in their decoded form (`${...}`) post-substitution, allowing workflow text to mention literal dollar-brace syntax for documentation.
- **FR-F4-5**: After substitution, a tripwire assertion verifies no unescaped `${` remains in any instruction text. Failure → loud error, no dispatch.
- **FR-F4-6**: After this PRD ships, no agent prompt produced by wheel contains plugin-path variable substitution syntax — only literal absolute paths.

### Theme F5 — Migration (right-sized to actual scope)

- **FR-F5-1**: `plugin-kiln/workflows/kiln-report-issue.json` is updated:
  - Add `requires_plugins: ["shelf"]` at top level.
  - Replace `${WORKFLOW_PLUGIN_DIR}/scripts/shelf-counter.sh` with `${WHEEL_PLUGIN_shelf}/scripts/shelf-counter.sh`.
  - Same for `append-bg-log.sh` and `step-dispatch-background-sync.sh`.
- **FR-F5-2**: No other workflow JSONs need migration. The other six workflows using `${WORKFLOW_PLUGIN_DIR}` reference scripts in their own plugin and continue to work via the legacy-token code path.
- **FR-F5-3**: After migration, the cross-plugin resolution gap documented in `.kiln/issues/2026-04-24-kiln-report-issue-workflow-plugin-dir-cross-plugin-gap.md` is closed.

## Non-Functional Requirements

- **NFR-F-1 (testing — explicit per user direction)**: Every FR-F1..F5 above MUST land with at least one test that exercises it end-to-end. The test substrate is **`/kiln:kiln-test`** for any FR whose claim depends on real agent-session behavior (registry build under `--plugin-dir`, full workflow resolution end-to-end, perf comparison). Pure-shell unit tests are acceptable for resolver / preprocessor logic that has no LLM in the loop.
- **NFR-F-2 (silent-failure tripwires)**: Each documented failure mode (plugin not loaded, unresolved token, tripwire violation) MUST have a regression test that fails when the failure becomes silent (e.g. resolver errors are swallowed, preprocessor fails open, registry returns wrong path). The tripwire test catches the SILENCE, not just the symptom.
- **NFR-F-3 (install-mode coverage)**: Test coverage MUST exercise all three install modes — marketplace cache, `--plugin-dir`, `settings.local.json` — for the registry build and for end-to-end workflow resolution. A test that passes only in the source-repo "happy path" does not count.
- **NFR-F-4 (perf gate — explicit per user direction)**: After this PRD ships, `/kiln:kiln-report-issue` median **wall-clock** AND median **`duration_api_ms`** MUST NOT regress by more than **20%** over the current Option B baseline. These two metrics are blockers — exceeding 20% blocks merge. Other metrics (output_tokens, cache_read_input_tokens, total_cost_usd) are reported but informational only — the wrapper switchover already shifts those, and resolver overhead is unlikely to dominate them. Baseline: `plugin-kiln/tests/kiln-report-issue-batching-perf/results-2026-04-24-with-tokens.tsv` at commit `b81aa25`.
- **NFR-F-5 (backward compat — strict)**: Workflows without `requires_plugins` MUST behave byte-identically to today (instruction text, agent prompt, side effects). Verified by a fixture that re-runs an unchanged workflow and diffs the resulting state file + log file against a pre-PRD snapshot.
- **NFR-F-6 (resolver perf)**: The pre-flight resolver itself MUST add no more than **200ms** to workflow start time on a workflow with 0 dependencies declared. Measured via `time` in a kiln-test fixture.
- **NFR-F-7 (atomic migration)**: FR-F5's migration of `kiln-report-issue.json` lands in the same commit as the resolver/registry/preprocessor implementation. No half-state where the workflow declares `requires_plugins` but the resolver isn't running yet.
- **NFR-F-8 (wheel self-hosting)**: Wheel itself can use `requires_plugins` in its own workflows. Pre-flight resolver bootstraps cleanly — wheel knows its own install path via `BASH_SOURCE` resolution and is included in the registry like any other plugin.

## Core User Stories

- **As a workflow author** writing a wheel workflow JSON, I want to declare `requires_plugins: ["shelf"]` at the top of my workflow and reference shelf scripts as `${WHEEL_PLUGIN_shelf}/scripts/foo.sh`, so my workflow runs correctly on every consumer install regardless of how the user installed shelf.
- **As a workflow author**, I want pre-flight failures to tell me exactly which dependency is missing (`Workflow requires plugin 'shelf', but 'shelf' is not enabled`), so I don't have to debug silent no-ops in production.
- **As a plugin consumer**, I want to know that workflows I run will fail loudly at start if a required plugin is missing, rather than silently completing with the wrong behavior.
- **As a developer** working with `--plugin-dir /Users/me/dev/plugin-shelf`, I want my override to take precedence over the marketplace-installed shelf, so I can develop against my local copy without uninstalling the marketplace version.
- **As an auditor** looking at any wheel-spawned agent prompt, I want to see only literal absolute paths and never `${VAR}` syntax, so I can trust the agent has no path-resolution work to do.

## Absolute Musts

These are non-negotiable. Tech stack is always #1.

1. **Bash 5.x + `jq` + POSIX**. No new runtime dependencies. Wheel is shell-script-based; this PRD stays inside that constraint.
2. **`/kiln:kiln-test` is the substrate** for any test whose claim depends on real agent-session behavior. Pure-shell unit tests are not sufficient for end-to-end install-mode coverage or perf measurements.
3. **20% perf gate** on `/kiln:kiln-report-issue` foreground wall-clock and `duration_api_ms`. Use the existing `plugin-kiln/tests/kiln-report-issue-batching-perf/` fixture as the baseline.
4. **No persistent registry**. Resolution is fresh per workflow-start. No staleness from plugin updates.
5. **Loaded-not-installed**. Disabled plugins do NOT silently resolve.
6. **Atomic migration**. The kiln-report-issue.json migration lands in the same commit as the runtime change. No half-state.
7. **Strict backward compat**. Workflows without `requires_plugins` behave byte-identically to today.

## Tech Stack

Inherited from parent product:
- Bash 5.x + `jq` + POSIX utilities for resolver, registry, and preprocessor scripts.
- `plugin-wheel/lib/` adds three new files: `registry.sh`, `resolve.sh`, `preprocess.sh`.
- `/kiln:kiln-test` harness for end-to-end install-mode tests.
- Existing `plugin-kiln/tests/kiln-report-issue-batching-perf/` fixture for the perf gate.

No new dependencies.

## Impact on Existing Features

- **Theme D Option B (`WORKFLOW_PLUGIN_DIR`) is subsumed.** The variable continues to work via the new preprocessor. Existing workflows that use it are unaffected.
- **One workflow JSON is migrated** (FR-F5). All other workflows continue to use the legacy `${WORKFLOW_PLUGIN_DIR}` token via the same code path.
- **`/kiln:kiln-report-issue`** specifically: the T092 switchover commit (`a36fba1`) becomes correct under all install modes. The current silent-failure window closes.
- **Theme D's `WORKFLOW_PLUGIN_DIR was unset` regression fingerprint** is preserved; this PRD adds a complementary fingerprint for the cross-plugin case (e.g. `Workflow requires plugin '<X>', but '<X>' is not enabled in this session`).

## Test Surface (per user requirement: heavy `/kiln:kiln-test` coverage)

Each fixture lives under `plugin-kiln/tests/<fixture-name>/` (kiln-test substrate convention). Right-sized to v1 scope.

### Install-mode coverage (FR-F1, NFR-F-3)

1. **`registry-marketplace-cache/`** — scaffolds a fake marketplace layout under `/tmp/...` with `~/.claude/plugins/cache/<org-mp>/<plugin>/<version>/`, runs `wheel-run` against a workflow with `requires_plugins`, asserts the registry resolves correctly.
2. **`registry-plugin-dir/`** — invokes `claude --plugin-dir /tmp/.../plugin-shelf-dev/` and asserts the registry picks the override path, not the cache version.
3. **`registry-settings-local-json/`** — scaffolds a `settings.local.json` with a project-scoped enabledPlugins entry, asserts resolution succeeds.

### Pre-flight resolver coverage (FR-F3)

4. **`resolve-missing-plugin/`** — `requires_plugins: ["nonexistent"]`. Asserts pre-flight fails with the documented error text before any side effects.
5. **`resolve-disabled-plugin/`** — plugin physically present in cache but not in `enabledPlugins`. Asserts pre-flight fails with "not enabled in this session".

### Preprocessor coverage (FR-F4)

6. **`preprocess-tripwire/`** — workflow JSON with a `${WHEEL_PLUGIN_unknown}` token (no matching `requires_plugins` entry). Asserts the tripwire fires at preprocess time, no agent dispatch happens.

### Backward compat (NFR-F-5)

7. **`back-compat-no-requires/`** — unchanged shipped workflow without `requires_plugins`. Asserts the resulting state file + log file are byte-identical to a pre-PRD snapshot.

### Perf gate (NFR-F-4)

8. **`perf-kiln-report-issue/`** — re-runs the existing `plugin-kiln/tests/kiln-report-issue-batching-perf/` fixture against the post-PRD code. Asserts median wall-clock and median `duration_api_ms` are within 120% of the recorded baseline at commit `b81aa25`. Token / cost metrics are reported but informational.

(The 200ms resolver-overhead check from NFR-F-6 is folded into fixture #8 — same harness, additional assertion on the no-deps case.)

## Success Metrics

- **SC-F-1**: All FR-F1..F5 land with passing tests. NFR-F-1 enforced.
- **SC-F-2**: All three install modes (marketplace cache, `--plugin-dir`, `settings.local.json`) verified end-to-end via `/kiln:kiln-test` fixtures. NFR-F-3 enforced.
- **SC-F-3**: `kiln-report-issue.json` declares `requires_plugins: ["shelf"]` and uses `${WHEEL_PLUGIN_shelf}/scripts/...` for cross-plugin references. The cross-plugin gap is closed.
- **SC-F-4**: Running the perf fixture against post-PRD code shows median wall-clock and median `duration_api_ms` within 120% of the `b81aa25` baseline. NFR-F-4 satisfied.
- **SC-F-5**: A consumer-install simulation of `/kiln:kiln-report-issue` (run from a temp dir with `--plugin-dir` overrides for kiln + shelf) succeeds and writes the expected bg log line.
- **SC-F-6**: `git grep -E '\\$\\{[^}]*\\}' .wheel/history/success/*.json` returns zero matches for plugin-path tokens in any agent step's command_log post-PRD. The agent never sees `${VAR}` syntax for plugin paths.
- **SC-F-7**: Each documented failure mode produces its documented error text, verified by the corresponding NFR-F-2 tripwire test.

## Risks / Unknowns

- **R-F-1 (perf gate at risk)**: Adding ~200ms of resolver overhead to a 2-second `kiln-report-issue` foreground (the read-counter step) is 10% — well within the 20% budget. But if the resolver implementation has any quadratic or recursive cost we don't anticipate, perf could slip. Mitigation: the perf fixture (test #8) catches this early.
- **R-F-2 (test scaffolding cost)**: Building three install-mode fixtures (marketplace cache, `--plugin-dir`, `settings.local.json`) requires fake-cache scaffolding + `claude --plugin-dir` invocations. Risk: if the kiln-test harness can't be told to bypass the user's actual settings.json without contaminating the test, the fixtures get more complex. Mitigation: spec phase verifies the harness can isolate per-fixture settings (high confidence given the harness already scaffolds full plugin directories).
- **R-F-3 (token tripwire false-positives)**: SC-F-6's grep for `${...}` in command logs may catch legitimate user-typed shell substitution that isn't a plugin-path token (e.g. an instruction that says `for f in "${files[@]}"; do ...`). Mitigation: the SC-F-6 grep narrows to `${WHEEL_PLUGIN_*}` and `${WORKFLOW_PLUGIN_DIR}` patterns specifically.

## Assumptions

- The `/kiln:kiln-test` harness can be extended to scaffold install-mode fixtures (fake `~/.claude/plugins/cache/`, fake `settings.json`, `--plugin-dir` invocation) under `/tmp/kiln-test-<uuid>/`. This is high-confidence given the harness already scaffolds full plugin directories for skill testing.
- The current Option B mechanism (Theme D) does not have downstream consumers outside this repo whose behavior would be affected by subsuming it under the new preprocessor.
- "Discovery via $PATH" is a viable mechanism — Claude Code reliably places every loaded plugin's `/bin` directory on `$PATH` at session start. Verified by inspection in the source repo. Spec phase confirms this holds for `--plugin-dir` and `settings.local.json` install modes too.

## Open Questions

- **OQ-F-1 (BLOCKING — must be answered before spec phase starts)**: What is the authoritative source for "what plugins are loaded in this Claude Code session, with their absolute install paths"?

  Three candidates:

  - **Candidate A (preferred — verified in source repo):** `$PATH` parsing. Claude Code prepends each loaded plugin's `/bin` directory to `$PATH` at session start. Visible in any subprocess. Inspection of the current session shows entries like `/Users/.../plugins/cache/yoshisada-speckit/kiln/000.001.009.247/bin`. Wheel parses these out, derives the plugin install dir as `dirname` of `/bin`, and the plugin name as the directory basename one level up. ~5 lines of bash. **Spec phase MUST verify this works for `--plugin-dir` and `settings.local.json` install modes** — the source-repo session uses marketplace install only.

  - **Candidate B (fallback):** Read `~/.claude/plugins/installed_plugins.json` (a known file in Claude Code's plugin state) plus parse `~/.claude/settings.json::enabledPlugins` and `<project>/.claude/settings.local.json` to determine which are enabled. Walk `~/.claude/plugins/cache/<org-mp>/<plugin>/` for version directories. ~50 lines of bash. More edge cases to handle (multiple installed versions, disabled-but-installed) but works without relying on Claude Code's PATH conventions.

  - **Candidate C (research item):** Claude Code may expose an env var or session file naming all loaded plugins explicitly — needs investigation. If such a thing exists, it's the most direct source.

  **Decision criterion for spec phase**: pick the simplest mechanism that works correctly under all three install modes. If A works, ship A. If A fails for `--plugin-dir` or `settings.local.json`, fall back to B. C is a research item — if it exists, it overrides everything.

- **OQ-F-2**: For diagnostic logging, should the per-run registry snapshot at `.wheel/state/<run-id>-registry.json` be retained on workflow failure for post-mortem? V1 plan: yes, keep on failure (matches existing `.wheel/history/success/` and `.wheel/history/failed/` patterns), delete on success.

## Alternatives Considered

### Alternative 1: Hot-fix only (no PRD)

Move `shelf-counter.sh`, `append-bg-log.sh`, `step-dispatch-background-sync.sh` from `plugin-shelf/scripts/` into `plugin-kiln/scripts/`. Update `kiln-report-issue.json` to reference them via the existing `${WORKFLOW_PLUGIN_DIR}` token (which works for in-plugin references). Done in 30 minutes.

**Pros**: closes the production bug today; zero new architecture; no risk of perf regression; no new APIs to maintain.

**Cons**: leaves the architectural pattern broken — the next workflow that wants to compose a sibling plugin's script will hit the same gap; doesn't establish a path for multi-plugin composition; doesn't eliminate the silent-failure shape (just shifts where it can occur).

**When to choose**: if multi-plugin composition is NOT on the roadmap and the kiln-report-issue script ownership is fine to consolidate into kiln.

### Alternative 2: This PRD (forward-looking architecture)

Build the registry + resolver + preprocessor + schema. Migrate the one workflow that needs it. Establish a pattern for future cross-plugin composition.

**Pros**: closes the production bug AND establishes the architectural pattern; eliminates silent path-rewriting at the runtime layer; sets up `requires_workflows` and `min_version` follow-ons cleanly.

**Cons**: real engineering cost (~1-2 weeks); introduces new APIs that future workflow authors must learn; perf gate adds risk surface.

**When to choose**: if multi-plugin composition is on the roadmap, OR if the silent path-rewriting class of bug is unacceptable as a runtime behavior.

### Alternative 3: Hot-fix now + this PRD as v2

Ship the hot-fix on PR #161 (or a follow-up) to close the production bug immediately. Build this PRD as v2 architecture once multi-plugin composition is actually on the roadmap.

**Pros**: closes the production bug today; defers architecture cost to when there's real demand for it; PRD work doesn't compete with #161 merge.

**When to choose**: if you want to be safe today but preserve the architectural option for later. **Recommended unless multi-plugin composition is imminent.**

## Pipeline guidance

This wants the full `/kiln:kiln-build-prd` pipeline:
- specifier produces spec + plan + interface contracts (resolver, registry, preprocessor, schema validators) + tasks; **resolves OQ-F-1 as the first spec-phase research task**
- 2-3 implementers in parallel: registry + resolver, preprocessor + tripwire, migration + perf fixture (third implementer can be folded into one of the first two if scope permits)
- qa-engineer NOT needed (no visual surface; this is bash + workflow JSON + tests)
- auditor verifies all 8 fixtures pass + perf gate satisfied + atomic migration of kiln-report-issue.json
- retrospective analyzes how `/kiln:kiln-test` substrate adoption felt for an architectural feature (this is the first time a non-perf PRD heavily uses kiln-test; lessons feed forward into the build-prd skill's substrate guidance — see `.kiln/issues/2026-04-24-build-prd-substrate-list-omits-kiln-test.md`)
