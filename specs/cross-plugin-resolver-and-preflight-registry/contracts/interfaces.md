# Interface Contracts: Cross-Plugin Resolver + Pre-Flight Plugin Registry

**Constitution Article VII (NON-NEGOTIABLE)**: Every exported function, script entrypoint, and workflow JSON field defined here is the single source of truth. All implementation — including parallel implementer tracks — MUST match these signatures exactly. If a signature needs to change, update THIS FILE first, then re-run affected tests.

This document covers four contracts:

1. [Plugin registry — `build_session_registry`](#1-build_session_registry) — FR-F1
2. [Pre-flight resolver — `resolve_workflow_dependencies`](#2-resolve_workflow_dependencies) — FR-F3
3. [Workflow preprocessor — `template_workflow_json`](#3-template_workflow_json) — FR-F4
4. [Workflow JSON schema additions](#4-workflow-json-schema-additions) — FR-F2, FR-F4

---

## 1. `build_session_registry`

**File**: `plugin-wheel/lib/registry.sh`
**Owners**: `impl-registry-resolver` track (sole owner)

### Signature

```bash
# Usage:
#   source plugin-wheel/lib/registry.sh
#   registry_json=$(build_session_registry)
#
# Arguments: NONE.
#
# Environment (consumed):
#   PATH                          — primary discovery source (Candidate A per research §1)
#   HOME                          — used to locate ~/.claude/plugins/installed_plugins.json (Candidate B)
#   WHEEL_REGISTRY_FALLBACK       — optional. If set to "1", forces Candidate B even when A succeeds.
#                                    Default: A primary, B auto-fallback when A returns empty.
#
# Stdout (on exit 0):
#   Single-line JSON object matching this schema (validated by jq):
#   {
#     "schema_version": 1,
#     "built_at":       "<ISO-8601 UTC timestamp>",
#     "source":         "candidate-a-path-parsing" | "candidate-b-installed-plugins-json",
#     "fallback_used":  true | false,
#     "plugins": {
#       "<plugin-name>": "<absolute-path-to-plugin-install-dir>",
#       ...
#     }
#   }
#
#   Plugin-name keys are derived per research §1.B (plugin.json::name preferred,
#   directory basename as fallback). Absolute paths are the parent of the /bin
#   entry on PATH (i.e. dirname stripped of trailing /bin).
#
#   The map MUST include ONLY plugins that are loaded+enabled in this session.
#   Disabled-but-installed plugins MUST NOT appear (FR-F1-3 / EC-1).
#
# Stderr:
#   Diagnostic messages on fallback or partial failures (e.g. "candidate A returned empty, falling back to B").
#   NEVER silent — every code path either succeeds with valid JSON or emits a recognizable error string.
#
# Exit codes:
#   0  — registry built successfully (may contain zero plugins; that's a valid state)
#   1  — both Candidate A and Candidate B failed (catastrophic — cannot read PATH AND cannot read installed_plugins.json)
```

### Invariants

- **I-R-1**: Output JSON is single-line, jq-parseable, schema-version-stamped. Multi-line is forbidden (it breaks downstream `jq -c` consumers and the diagnostic snapshot writer).
- **I-R-2**: Plugin keys are unique. Multiple PATH entries pointing at the same plugin (e.g. dev override + cache version) collapse to ONE entry, with the override winning per FR-F1-4 (PATH order = priority order).
- **I-R-3**: Wheel itself MUST appear in the registry (NFR-F-8 self-hosting). If wheel is bootstrapping the registry from inside `plugin-wheel/lib/registry.sh`, it derives its own path from `BASH_SOURCE[0]` and adds itself if PATH parsing somehow misses it.
- **I-R-4**: `built_at` is the wall-clock at registry build start; used by the diagnostic snapshot for failure post-mortem.
- **I-R-5**: Idempotent — calling `build_session_registry` twice in the same shell returns identical output (modulo `built_at` timestamp). No persistent state.

### Behavior on edge cases

| Edge case | Behavior |
|---|---|
| PATH contains plugin `/bin` entries pointing at directories that don't exist on disk | Skip silently (best-effort); record in stderr diagnostic |
| Plugin `/bin` entry exists but `<plugin-dir>/.claude-plugin/plugin.json` is missing or malformed | Fall back to directory basename for plugin name; record warning on stderr |
| Two PATH entries for the same plugin name with different paths | First-occurrence wins (PATH-order priority — overrides come first) |
| `installed_plugins.json` exists but is empty | Treat as Candidate B success with zero plugins; combined with empty Candidate A this yields a valid empty-registry result, exit 0 |
| Both Candidate A AND Candidate B fail to read inputs | Exit 1 with stderr "registry: both candidate A (PATH parse) and candidate B (installed_plugins.json) failed; cannot build session registry" |

---

## 2. `resolve_workflow_dependencies`

**File**: `plugin-wheel/lib/resolve.sh`
**Owners**: `impl-registry-resolver` track (sole owner)

### Signature

```bash
# Usage:
#   source plugin-wheel/lib/resolve.sh
#   resolve_workflow_dependencies "$workflow_json" "$registry_json"
#
# Arguments:
#   $1  workflow_json   — single-line JSON, the output of workflow_load (validated shape)
#   $2  registry_json   — single-line JSON, the output of build_session_registry
#
# Environment: NONE consumed.
#
# Stdout (on exit 0):
#   Empty (success is silent on stdout). Caller proceeds to preprocessor with the validated workflow.
#
# Stderr:
#   On any failure, writes a single line matching one of the documented FR-F3-3 error shapes:
#
#     Workflow '<name>' requires plugin '<X>', but '<X>' is not enabled in this session. Enable it in ~/.claude/settings.json or pass --plugin-dir.
#
#     Workflow '<name>' references unknown plugin token '${WHEEL_PLUGIN_<X>}'. Add '<X>' to requires_plugins.
#
#     Workflow '<name>' has malformed requires_plugins entry: <reason>.
#
# Exit codes:
#   0  — all dependencies satisfied; workflow is safe to dispatch
#   1  — at least one dependency unsatisfied; documented error on stderr; caller MUST NOT proceed to dispatch
```

### Invariants

- **I-V-1**: NEVER mutates workflow state, NEVER writes to `.wheel/state/`, NEVER spawns sub-agents. Pure validation phase.
- **I-V-2**: Error text matches the documented shapes EXACTLY (verified by `plugin-wheel/tests/resolve-error-shapes.bats`). NFR-F-2 silent-failure tripwire depends on these strings.
- **I-V-3**: For workflows without `requires_plugins`, the function exits 0 with no stderr output and no side effects. NFR-F-5 byte-identical backward-compat hinges on this.
- **I-V-4**: Token-discovery scan walks every agent step's `instruction` field looking for `${WHEEL_PLUGIN_<name>}` references. Any name found in instructions but NOT in `requires_plugins` is a "references unknown plugin token" error. (`${WORKFLOW_PLUGIN_DIR}` is exempt from this check — it is auto-resolved by the preprocessor against the calling plugin.)
- **I-V-5**: Schema validation (called inline by this function or by `workflow_load` before this function — implementer's choice per research §7 U-2): each `requires_plugins` entry MUST be a non-empty string matching `[a-zA-Z0-9_-]+`. Duplicates fail with the malformed-entry error.

### Behavior on edge cases

| Edge case | Behavior |
|---|---|
| `requires_plugins: []` | Exit 0; no token-discovery scan needed because there are no declared deps to cross-check (but unknown-token check still runs against instructions) |
| `requires_plugins: ["shelf", "shelf"]` | Exit 1: malformed entry: duplicate name 'shelf' |
| `requires_plugins: ["shelf"]` but workflow instructions never mention `${WHEEL_PLUGIN_shelf}` | Exit 0 with stderr warning (not error) — declared but unused |
| `requires_plugins: ["shelf"]` AND instructions contain `${WHEEL_PLUGIN_kiln}` (declared shelf, used kiln) | Exit 1: references unknown plugin token '${WHEEL_PLUGIN_kiln}'. Add 'kiln' to requires_plugins. |
| Workflow has no `requires_plugins` field AND no `${WHEEL_PLUGIN_*}` tokens in instructions | Exit 0; pure backward-compat path |
| Workflow has no `requires_plugins` field BUT contains `${WHEEL_PLUGIN_shelf}` | Exit 1: references unknown plugin token (forces declaration) |

---

## 3. `template_workflow_json`

**File**: `plugin-wheel/lib/preprocess.sh`
**Owners**: `impl-preprocessor` track (sole owner)

### Signature

```bash
# Usage:
#   source plugin-wheel/lib/preprocess.sh
#   templated_json=$(template_workflow_json "$workflow_json" "$registry_json" "$calling_plugin_dir")
#
# Arguments:
#   $1  workflow_json        — single-line JSON, validated by resolve_workflow_dependencies
#   $2  registry_json        — single-line JSON, the output of build_session_registry
#   $3  calling_plugin_dir   — absolute path to the plugin owning this workflow file (for ${WORKFLOW_PLUGIN_DIR})
#
# Environment: NONE consumed.
#
# Stdout (on exit 0):
#   Single-line JSON matching the input workflow shape, with all agent step `instruction`
#   fields preprocessed:
#     - Every `${WHEEL_PLUGIN_<name>}` substituted with registry.plugins[<name>]
#     - Every `${WORKFLOW_PLUGIN_DIR}` substituted with $3 (calling_plugin_dir)
#     - Every `$${...}` decoded to literal `${...}`
#
#   All other JSON fields (steps[].id, steps[].type, command steps, etc.) are byte-identical
#   to the input.
#
# Stderr:
#   On tripwire violation OR substitution failure:
#     Wheel preprocessor failed: instruction text for step '<id>' still contains '${...}'. This is a wheel runtime bug; please file an issue.
#
# Exit codes:
#   0  — templating succeeded, tripwire passed
#   1  — tripwire violation OR substitution lookup failure (e.g. registry missing a plugin that the resolver should have caught — defense-in-depth)
```

### Invariants

- **I-P-1**: Output is single-line JSON, jq-parseable, byte-identical to input modulo agent-step `instruction` fields. Schema fields, command-step `command` fields, and any other text are NOT preprocessed (only agent `instruction` per FR-F4-2).
- **I-P-2**: Token grammar per research §2.A — `[a-zA-Z0-9_-]+` for the `<name>` part of `${WHEEL_PLUGIN_<name>}`. Names with dots, slashes, or other characters are NOT matched (they pass through as literal text and trip the post-substitution tripwire).
- **I-P-3**: Escape grammar per research §2.B — the escape pre-scan records `$${` byte positions BEFORE substitution; substitution skips those positions; post-substitution decode replaces `$${` → `${` only at recorded positions. (Not a global string replace, which would corrupt unrelated `$$` sequences in the text.)
- **I-P-4**: Tripwire (FR-F4-5) uses the NARROWED pattern: `\$\{(WHEEL_PLUGIN_|WORKFLOW_PLUGIN_DIR)`. Generic `${VAR}` syntax (e.g. `${files[@]}`) does NOT trip the wire (EC-4).
- **I-P-5**: Idempotent — calling `template_workflow_json` twice on already-preprocessed output is a no-op (no `${WHEEL_PLUGIN_*}` or `${WORKFLOW_PLUGIN_DIR}` tokens left to substitute; tripwire passes; output equals input).

### Behavior on edge cases

| Edge case | Behavior |
|---|---|
| Input contains `${WHEEL_PLUGIN_shelf}` AND registry has `shelf → /abs/path` | Substitute literally; output contains `/abs/path` in place of token |
| Input contains `${WHEEL_PLUGIN_shelf}` BUT registry has no `shelf` entry (resolver bug) | Exit 1 with tripwire-style error including step id; defense-in-depth |
| Input contains `$${WHEEL_PLUGIN_shelf}` (escaped) | Output contains literal `${WHEEL_PLUGIN_shelf}` (single dollar); tripwire allows it because the escape pre-scan recorded the position |
| Input contains `${WORKFLOW_PLUGIN_DIR}/scripts/foo.sh` AND $3 = `/abs/plugin-kiln` | Output contains `/abs/plugin-kiln/scripts/foo.sh` |
| Input contains `${WORKFLOW_PLUGIN_DIR:-/fallback/path}/scripts/foo.sh` (bash default-value syntax) | Substitute the un-defaulted form; the `:-/fallback/path` portion is NOT preserved (the resolver requires explicit declaration; defaults hide gaps) |
| Input contains generic `${VAR}` like `${files[@]}` | Pass through unchanged; narrowed-pattern tripwire ignores it |
| Instruction text is empty | Pass through unchanged; tripwire passes (nothing to scan) |

---

## 4. Workflow JSON schema additions

**Files**: `plugin-wheel/lib/workflow.sh` (validation), `plugin-kiln/workflows/*.json` (consumers)
**Owners**: `impl-preprocessor` (validation in workflow.sh); `impl-migration-perf` (consumer migration in kiln-report-issue.json)

### Schema delta

```jsonc
{
  "name": "string (required, existing)",
  "version": "string (required, existing)",

  // NEW (FR-F2-1) — optional top-level array
  "requires_plugins": [
    "<plugin-name-1>",
    "<plugin-name-2>"
  ],

  "steps": [
    {
      "id": "string (required, existing)",
      "type": "command | agent | workflow | ... (existing)",
      "instruction": "string (existing — NEW: may contain ${WHEEL_PLUGIN_<name>} tokens for any name in requires_plugins)",
      // ... other existing fields preserved ...
    }
  ]
}
```

### Validation rules (enforced in `workflow_load`)

- `requires_plugins` is OPTIONAL. Absence is equivalent to `[]`.
- When present, MUST be a JSON array.
- Each entry MUST be a non-empty string matching `[a-zA-Z0-9_-]+`.
- Duplicates fail with `Workflow '<name>' has malformed requires_plugins entry: duplicate name '<X>'.`
- Non-string entries (numbers, objects) fail with `Workflow '<name>' has malformed requires_plugins entry: non-string at index <N>.`

### Token grammar (enforced in `template_workflow_json`)

- `${WHEEL_PLUGIN_<name>}` — `<name>` matches `[a-zA-Z0-9_-]+`. Resolves against the registry.
- `${WORKFLOW_PLUGIN_DIR}` — resolves against the calling plugin (legacy Theme D Option B token preserved for backward compat).
- `$${...}` — escape syntax, decoded to literal `${...}` post-substitution.

### Backward compatibility statement (NFR-F-5)

A workflow JSON that does NOT contain `requires_plugins` and does NOT contain any `${WHEEL_PLUGIN_*}` token MUST behave byte-identically to its pre-PRD execution. This includes:

- Same `state.steps[]` array shape after activation.
- Same agent prompt text dispatched per step (the legacy `${WORKFLOW_PLUGIN_DIR}` template still works via the same code path).
- Same side effects (output files, log lines, sub-agent spawns).
- Verified by `plugin-kiln/tests/back-compat-no-requires/` fixture comparing against a pre-PRD snapshot.
