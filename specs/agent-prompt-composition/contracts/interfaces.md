# Interface Contracts: Agent Prompt Composition

**Constitution Article VII (NON-NEGOTIABLE)**: Every script entrypoint, JSON schema, file format, and closed vocabulary defined here is the single source of truth. All implementation — including parallel implementer tracks — MUST match these signatures exactly. If a signature needs to change, update THIS FILE first, then re-run affected tests.

This document covers seven contracts:

1. [Theme B — include resolver script](#1-theme-b--include-resolver-script) — FR-B-1..B-4
2. [Theme A — runtime composer script](#2-theme-a--runtime-composer-script) — FR-A-1..A-3
3. [Theme A — `agent_bindings:` JSON schema (plugin manifest)](#3-theme-a--agent_bindings-json-schema-plugin-manifest) — FR-A-7
4. [Theme A — `agent_binding_overrides:` schema (PRD frontmatter)](#4-theme-a--agent_binding_overrides-schema-prd-frontmatter) — FR-A-9
5. [Theme A — per-shape stanza file format](#5-theme-a--per-shape-stanza-file-format) — FR-A-5
6. [Closed verb namespace v1](#6-closed-verb-namespace-v1) — FR-A-8
7. [Closed task-shape vocabulary v1](#7-closed-task-shape-vocabulary-v1) — FR-A-4

---

## 1. Theme B — Include resolver script

**File**: `plugin-kiln/scripts/agent-includes/resolve.sh`
**Owner**: `impl-include-preprocessor` track (sole owner of this contract)

### Signature

```bash
# Usage:
#   plugin-kiln/scripts/agent-includes/resolve.sh <input-path>
#   plugin-kiln/scripts/agent-includes/resolve.sh -            # read from stdin (path-relative includes anchored to PWD)
#
# Arguments:
#   <input-path>   Path to a source agent .md file. Includes are resolved relative to
#                  this file's directory.
#   -              Read from stdin. Includes are resolved relative to PWD.
#
# Stdout:
#   Resolved markdown — directive lines replaced byte-for-byte by the contents of the
#   referenced file, all other lines passed through unchanged.
#
# Exit codes:
#   0  — resolved successfully (including the no-op case: file has no directives → output == input)
#   1  — input path does not exist, OR an include target does not exist, OR a recursive
#        include is detected, OR a malformed directive line (e.g., empty path) is encountered
#
# Stderr:
#   Human-readable diagnostic on exit 1. NEVER silent.
#   Format: "resolve.sh: <error-class>: <detail> (file: <path>, line: <N>)"
```

### Directive grammar (FR-B-2, R-2 mitigation)

A line is a directive iff it matches the regex (POSIX ERE):

```
^[[:space:]]*<!-- @include[[:space:]]+([^[:space:]][^>]*[^[:space:]])[[:space:]]*-->[[:space:]]*$
```

- Capture group 1 = the include path. Whitespace-trimmed.
- Path is resolved relative to the directory of the input file.

### Fenced-code-block exclusion (R-2)

The resolver is a line-oriented state machine with one bit of state: `in_code_block`.

```
in_code_block = false
for each line in input:
  if line matches /^[[:space:]]*```/:
    in_code_block = !in_code_block
    emit line as-is
    continue
  if in_code_block:
    emit line as-is
    continue
  if line matches directive regex:
    resolve include (per below)
  else:
    emit line as-is
```

Lines inside fenced code blocks are NEVER expanded, even if they match the directive regex. This is the load-bearing edge case for agent files that document the directive syntax (e.g., this very contract document, if it were ever piped through the resolver).

### Include resolution rules

- **Single-pass**: After expansion, the expanded content is NOT re-scanned. A directive inside a shared module is an ERROR (exit 1, "recursive include detected").
- **Path resolution**: Include paths are interpreted relative to the input file's directory (NOT the resolver's cwd, NOT the include source's directory — the original file's directory always wins).
- **Missing target**: Exit 1 with "include target not found".
- **Empty target**: A target file that exists but is empty resolves to an empty expansion (NO error, NO blank line — the directive line is simply replaced by zero bytes). Trailing/leading newlines around the directive line are preserved from the parent file.

### Invariants

- **I-B1**: A file containing zero directives is a no-op (output == input, byte-identical). NFR-2 backward compat.
- **I-B2**: For unchanged inputs, the resolver is **deterministic** — re-invocation produces byte-identical output. NFR-1, NFR-6, SC-7.
- **I-B3**: The resolver MUST NOT modify any file in place. Output is stdout only. The `build-all.sh` wrapper is responsible for writing files.
- **I-B4**: The resolver MUST exit non-zero on ANY error condition. NEVER silent.

### Tests (NFR-1)

- Unit: file with zero directives → output == input (I-B1).
- Unit: file with one directive on its own line → directive line replaced by include body.
- Unit: file with directive-shaped text inside a fenced code block → that line passed through (R-2).
- Unit: file with directive pointing to nonexistent target → exit 1 with diagnostic.
- Unit: file with directive pointing to a shared module that itself contains a directive → exit 1 with "recursive include detected".
- Unit: re-invocation on unchanged source → byte-identical output (I-B2, SC-7).

---

## 2. Theme A — Runtime composer script

**File**: `plugin-wheel/scripts/agents/compose-context.sh`
**Owner**: `impl-runtime-composer` track (sole owner of this contract)

### Signature

```bash
# Usage:
#   plugin-wheel/scripts/agents/compose-context.sh \
#     --agent-name <name> \
#     --plugin-id <id> \
#     --task-spec <path-to-json> \
#     [--prd-path <path>]
#
# Required arguments:
#   --agent-name <name>     Short name of the agent (must match a key in the plugin's
#                           agent_bindings: section; e.g., research-runner).
#   --plugin-id <id>        The plugin owning the agent (e.g., kiln). Used to locate
#                           plugin-<id>/.claude-plugin/plugin.json for verb bindings.
#   --task-spec <path>      Path to a JSON file conforming to the task_spec schema below.
#
# Optional arguments:
#   --prd-path <path>       Path to a PRD .md file with frontmatter. If present and the
#                           frontmatter has agent_binding_overrides:, those overrides are
#                           applied AFTER manifest defaults (overrides win).
#
# Environment (required):
#   WORKFLOW_PLUGIN_DIR     Absolute path to the orchestrating plugin. Used to anchor
#                           verb command-template paths.
#
# Stdout (on exit 0):
#   A single JSON object (single-line):
#     {
#       "subagent_type":  "<plugin-prefixed name, e.g., kiln:research-runner>",
#       "prompt_prefix":  "<assembled markdown block, ready to prepend to task prompt>",
#       "model_default":  "<haiku|sonnet|opus|null — from agent's frontmatter, null if absent>"
#     }
#
# Exit codes:
#   0  — composed successfully
#   1  — task_spec invalid (missing required field, malformed JSON)
#   2  — task_shape not in closed vocabulary (FR-A-6)
#   3  — agent_name not declared in plugin manifest's agent_bindings:
#   4  — verb in agent_bindings: or agent_binding_overrides: not in closed namespace (FR-A-7, FR-A-9)
#   5  — agent_binding_overrides: references an agent not in agent_bindings: (FR-A-9, SC-5)
#   6  — WORKFLOW_PLUGIN_DIR unset or path does not exist
#   7  — required input file (manifest, task-shape stanza, coordination-protocol stanza) missing
#
# Stderr:
#   Human-readable diagnostic on any non-zero exit. NEVER silent.
```

### `task_spec` JSON input schema

```json
{
  "task_shape":   "<one of: skill, frontend, backend, cli, infra, docs, data, agent>",
  "task_summary": "<one-sentence description of the comparative claim or task>",
  "variables":    { "<KEY>": "<value>", "...": "..." },
  "axes":         [ "<axis-name>", "..." ]
}
```

- `task_shape` (required): MUST be one of the 8 shapes (§7). Composer exits 2 if not.
- `task_summary` (required): non-empty string. Composer exits 1 if empty.
- `variables` (optional, default `{}`): flat map of `KEY: value`. Both keys and values are strings. Rendered as a markdown table in `prompt_prefix`.
- `axes` (optional, default `[]`): array of strings naming the metrics being compared (e.g., `["latency", "cost", "quality"]`). Rendered as a bulleted list in `prompt_prefix`.

### `prompt_prefix` body shape (FR-A-2)

The composer assembles `prompt_prefix` as a single markdown string with this exact section ordering:

```markdown
## Runtime Environment

WORKFLOW_PLUGIN_DIR=<absolute path from env>

### Task

- task_shape: <shape>
- task_summary: <summary>

### Variables

| Key | Value |
|---|---|
| <KEY> | <value> |
| ... | ... |

### Verbs

| Verb | Command |
|---|---|
| <verb-name> | <command-template-string> |
| ... | ... |

### Axes

- <axis-name>
- ...

### Task Shape: <shape>

<verbatim body of plugin-kiln/lib/task-shapes/<shape>.md>

### Coordination Protocol

<verbatim body of plugin-kiln/agents/_shared/coordination-protocol.md>
```

- If `variables` is empty, the `### Variables` section is omitted entirely (no empty header, no empty table).
- If `axes` is empty, the `### Axes` section is omitted entirely.
- Section ordering is INVARIANT (NFR-6 determinism — re-invocation must produce byte-identical output).
- Verbs table rows are sorted by verb name (alphabetical, `LC_ALL=C`) for determinism.
- Variables table rows are sorted by key (alphabetical, `LC_ALL=C`) for determinism.

### Verb resolution (FR-A-9 override semantics)

1. Read manifest `agent_bindings:` for `agent-name`.
2. If `--prd-path` provided AND its frontmatter contains `agent_binding_overrides:` for `agent-name`, apply per-verb: override entries REPLACE manifest entries with the same verb name; new verb names are added.
3. Resulting verb map is the source of truth for the `### Verbs` table.

### Validator script (sibling)

**File**: `plugin-wheel/scripts/agents/validate-bindings.sh`

```bash
# Usage:
#   plugin-wheel/scripts/agents/validate-bindings.sh <plugin-manifest.json>
#
# Validates that every verb name in agent_bindings: is in the closed verb namespace
# (plugin-wheel/scripts/agents/verbs/_index.json).
#
# Exit codes:
#   0  — manifest is valid
#   1  — manifest path does not exist or is malformed JSON
#   4  — at least one verb in agent_bindings: is not in the closed namespace
```

The composer (§2 main) MUST internally invoke the same validation logic on its loaded manifest before assembling the prompt. Exit code 4 from the composer indicates the same failure class as exit 1 from the validator with respect to verb membership.

### Invariants

- **I-A1**: For unchanged inputs (same `task_spec`, same manifest, same env), the composer is **deterministic** — re-invocation produces byte-identical JSON. NFR-6.
- **I-A2**: The composer NEVER calls `Agent`. It is a pure function: inputs → JSON. The calling skill is responsible for spawning.
- **I-A3**: Verb command-templates are opaque to the composer. `${VAR}` references inside command-templates are NOT resolved by the composer (the calling skill resolves them at spawn time). The composer copies the string verbatim.
- **I-A4**: The composer exits non-zero on ANY error condition. NEVER silent.
- **I-A5**: `subagent_type` is ALWAYS plugin-prefixed (`<plugin-id>:<agent-name>`). NEVER bare. NEVER `general-purpose` for known agents.

### Tests (NFR-1)

- Unit (SC-3): valid inputs → JSON shape per schema, exit 0.
- Unit (SC-4): manifest with unknown verb → validator exits 4.
- Unit (SC-5): PRD override referencing unknown agent → composer exits 5.
- Unit: PRD override referencing unknown verb → composer exits 4.
- Unit: `task_shape` not in §7 → composer exits 2.
- Unit (NFR-6): same inputs twice → byte-identical output.
- Unit: `WORKFLOW_PLUGIN_DIR` unset → composer exits 6.

---

## 3. Theme A — `agent_bindings:` JSON schema (plugin manifest)

**File**: `plugin-<name>/.claude-plugin/plugin.json`
**Owner**: `impl-runtime-composer` track adds the schema; consumers populate per-plugin.

### Schema addition

```json
{
  "name": "kiln",
  "version": "...",
  "agent_bindings": {
    "<agent-short-name>": {
      "verbs": {
        "<verb-name>": "<command-template-string>"
      }
    }
  }
}
```

- `agent_bindings:` is OPTIONAL at the manifest level. A plugin without it is valid (per NFR-3 backward compat).
- Each `<agent-short-name>` MUST correspond to an actual agent file at `plugin-<name>/agents/<agent-short-name>.md`. Validator does NOT enforce this in v1 (only verb-name validation), but installer SHOULD warn.
- Each `<verb-name>` MUST be in the closed namespace (§6). Validator REFUSES install / lint if not.
- `<command-template-string>` is an opaque string. MAY contain `${VAR}` references (e.g., `${PLUGIN_DIR_UNDER_TEST}`, `${FIXTURE_ID}`, `${WORKFLOW_PLUGIN_DIR}`) — these are resolved by the calling skill, NOT the composer.

### Example (kiln, v1)

```json
{
  "agent_bindings": {
    "research-runner": {
      "verbs": {
        "verify_quality": "/kiln:kiln-test --plugin-dir ${PLUGIN_DIR_UNDER_TEST} --fixture ${FIXTURE_ID}",
        "measure": "bash ${WORKFLOW_PLUGIN_DIR}/scripts/research/parse-stream-json.sh"
      }
    },
    "fixture-synthesizer": {
      "verbs": {
        "synthesize_fixtures": "echo 'TBD by first research-first PRD'"
      }
    },
    "output-quality-judge": {
      "verbs": {
        "judge_outputs": "echo 'TBD by first research-first PRD'"
      }
    }
  }
}
```

The "TBD by first research-first PRD" placeholder is INTENTIONAL — v1 ships the schema + 3 agent files; the first research-first PRD is the canonical site that fills in real verb command-templates via PRD-level overrides (§4).

### Validator behavior (FR-A-7)

`plugin-wheel/scripts/agents/validate-bindings.sh <manifest.json>`:

1. Parse JSON. Exit 1 if malformed.
2. If `agent_bindings:` absent, exit 0 (no-op).
3. For each agent entry, for each verb name: if not in the closed namespace (§6), exit 4 with `"unknown verb '<name>' for agent '<agent>' — closed namespace: <list>"`.
4. Exit 0.

---

## 4. Theme A — `agent_binding_overrides:` schema (PRD frontmatter)

**Location**: PRD frontmatter, e.g., `docs/features/<date>-<slug>/PRD.md`.

### Schema

```yaml
---
agent_binding_overrides:
  <agent-short-name>:
    verbs:
      <verb-name>: <command-template-string>
---
```

- Same JSON shape as `agent_bindings:` §3, expressed as YAML in PRD frontmatter.
- OPTIONAL — a PRD without it is valid (composer applies manifest defaults only).
- `<agent-short-name>` MUST match an agent declared in the plugin's `agent_bindings:`. Composer exits 5 if not (FR-A-9).
- `<verb-name>` MUST be in the closed namespace (§6). Composer exits 4 if not.
- Per-verb override semantics: override entries REPLACE manifest entries with the same name; new verb names are added.

### Example (illustrative, for first research-first PRD)

```yaml
---
agent_binding_overrides:
  research-runner:
    verbs:
      verify_quality: /kiln:kiln-test --plugin-dir ${PLUGIN_DIR_UNDER_TEST} --fixture corpus-001
      run_baseline:   bash ${WORKFLOW_PLUGIN_DIR}/scripts/research/baseline.sh
      run_candidate:  bash ${WORKFLOW_PLUGIN_DIR}/scripts/research/candidate.sh
---
```

---

## 5. Theme A — Per-shape stanza file format

**Files**: `plugin-kiln/lib/task-shapes/<shape>.md`
**Owner**: `impl-runtime-composer` track.

### Format

- Pure markdown body. NO frontmatter required.
- 5–15 lines of curated guidance per FR-A-5.
- File is read verbatim by the composer and inserted under `### Task Shape: <shape>` heading in `prompt_prefix`.
- Files MUST exist for ALL 8 shapes in §7 (composer exits 7 if a shape's stanza file is missing).

### Example (illustrative — actual stanzas authored by impl track)

```markdown
A `skill` task A/B-tests or modifies a Claude Code skill. Use the kiln-test substrate
(`/kiln:kiln-test <plugin> <test>`) — it spawns real `claude --print` subprocesses against
fixture directories. Verdict comes from the watcher classifier, not from a hard timeout.
Report: pass/fail, scratch dir on fail, captured tokens.
```

---

## 6. Closed verb namespace v1

**File**: `plugin-wheel/scripts/agents/verbs/_index.json`
**Owner**: `impl-runtime-composer` track.

### Pinned list (v1, FR-A-8)

```json
{
  "version": 1,
  "verbs": [
    "verify_quality",
    "run_baseline",
    "run_candidate",
    "measure",
    "synthesize_fixtures",
    "judge_outputs"
  ]
}
```

- **6 verbs**, no additions in v1.
- Adding a verb in v2 requires bumping `version` AND a manifest update across all consuming plugins.
- The composer + validator both read this file at runtime and consult the `verbs` array. Adding a verb to the JSON is sufficient to enable it; no script-level changes required.

### Verb semantics (informational, not enforced)

| Verb | Intended use |
|---|---|
| `verify_quality` | Run a quality gate (skill substrate, vitest run, etc.) |
| `run_baseline` | Execute the baseline path of an A/B comparison |
| `run_candidate` | Execute the candidate path of an A/B comparison |
| `measure` | Parse stream-json or other empirical metric extraction |
| `synthesize_fixtures` | Generate fixture corpus for a comparison |
| `judge_outputs` | Score paired baseline/candidate outputs against a rubric |

---

## 7. Closed task-shape vocabulary v1

**File**: `plugin-kiln/lib/task-shapes/_index.json`
**Owner**: `impl-runtime-composer` track.

### Pinned list (v1, FR-A-4)

```json
{
  "version": 1,
  "shapes": [
    "skill",
    "frontend",
    "backend",
    "cli",
    "infra",
    "docs",
    "data",
    "agent"
  ]
}
```

- **8 shapes**, including `agent` (resolves OQ-3 — the 3 new agent.md files in this PRD are the canonical exemplar).
- Each shape MUST have a corresponding `<shape>.md` stanza file at `plugin-kiln/lib/task-shapes/`.
- Adding a shape in v2 requires bumping `version`, adding the stanza file, and a manifest update.

### Shape semantics (informational, stanza body is authoritative)

| Shape | Intended use |
|---|---|
| `skill` | A/B testing or modifying a Claude Code skill (uses kiln-test substrate) |
| `frontend` | UI / visual changes (uses Playwright + visual snapshot) |
| `backend` | Server / API changes (uses vitest + coverage) |
| `cli` | CLI changes (uses stdout matching + exit code) |
| `infra` | Wheel / hooks / build / tooling |
| `docs` | README / CLAUDE.md / spec docs |
| `data` | Fixture corpus, schema migrations |
| `agent` | Meta-task: improving an agent prompt itself |

---

## Cross-contract invariants

- **NFR-6 determinism**: Both resolver (§1) and composer (§2) MUST produce byte-identical output for unchanged inputs. Any non-determinism is a bug.
- **NFR-8 disjoint partition**: No file in the spec.md "Theme Partition" table appears in both columns. The two implementer tracks coordinate ONLY through this contracts document.
- **Closed vocabularies are versioned**: Both `verbs/_index.json` (§6) and `task-shapes/_index.json` (§7) carry `version: 1`. Bumps require manifest updates across plugins.
