# Interface Contracts: Wheel as Runtime

**Constitution Article VII (NON-NEGOTIABLE)**: Every exported function, script entrypoint, workflow JSON field, and hook contract defined here is the single source of truth. All implementation — including parallel implementer tracks — MUST match these signatures exactly. If a signature needs to change, update THIS FILE first, then re-run affected tests.

This document covers six contracts:

1. [Agent resolver script](#1-agent-resolver-script) — FR-A1, FR-A3
2. [Workflow JSON `agent_path:` field](#2-workflow-json-agent_path-field) — FR-A4
3. [Workflow JSON `model:` field](#3-workflow-json-model-field) — FR-B1, FR-B2
4. [Post-tool-use hook command-extraction contract](#4-post-tool-use-hook-command-extraction-contract) — FR-C1, NFR-3
5. [`WORKFLOW_PLUGIN_DIR` env export contract](#5-workflow_plugin_dir-env-export-contract) — FR-D1, FR-D4
6. [Batched step wrapper contract](#6-batched-step-wrapper-contract) — FR-E2, FR-E4

---

## 1. Agent resolver script

**File**: `plugin-wheel/scripts/agents/resolve.sh`
**Owners**: `impl-themeA-agents` track (sole owner of this contract)

### Signature

```bash
# Usage:
#   plugin-wheel/scripts/agents/resolve.sh <path-or-name>
#
# Arguments:
#   <path-or-name>  Either:
#                     (a) absolute path to an agent file (e.g. /abs/path/to/debugger.md)
#                     (b) repo-relative path (e.g. plugin-wheel/agents/debugger.md)
#                     (c) short name (e.g. debugger, qa-engineer) resolved via registry.json
#                     (d) unknown name — passed through unchanged (back-compat)
#
# Environment (required):
#   WORKFLOW_PLUGIN_DIR  — used to resolve (b) and (c) under consumer-install layouts
#                          where the repo root does not contain plugin-wheel/
#
# Exit codes:
#   0  — resolved successfully, JSON on stdout
#   0  — unknown name (d) — passes through as a JSON shape indicating passthrough, stdout still JSON
#   1  — resolver could not read registry.json, could not read the agent file, or input is empty
#
# Stdout (on exit 0):
#   A single JSON object (no trailing newline sensitivity — single-line JSON):
#   {
#     "subagent_type":      "<wheel-runner|general-purpose|...>",
#     "system_prompt_path": "<absolute-or-WORKFLOW_PLUGIN_DIR-rooted path to the agent .md>",
#     "tools":              ["Read", "Edit", "Bash", "..."],
#     "source":             "<short-name|path|unknown>",      // which of (a)/(b)/(c)/(d) matched
#     "canonical_path":     "<path under plugin-wheel/agents/ if known, else the raw input>",
#     "model_default":      "<haiku|sonnet|opus|null>"        // the agent's preferred model if stated in frontmatter
#   }
#
# Stderr:
#   Human-readable diagnostic on exit 1. NEVER silent.
```

### Invariants

- **I-R1**: Input form (d) — unknown name passthrough — MUST still return a valid JSON object (with `"source": "unknown"`, `"subagent_type"` echoed from the input or `"general-purpose"`, remaining fields null-or-empty). Callers relying on the pre-resolver `subagent_type: general-purpose` spawn pattern MUST NOT see a behavior change.
- **I-R2**: The resolver is **idempotent** — calling it twice with the same argument in the same env returns byte-identical JSON.
- **I-R3**: The resolver consults `plugin-wheel/scripts/agents/registry.json` for form (c). The registry's schema is:
  ```json
  {
    "version": 1,
    "agents": {
      "<short-name>": {
        "path": "plugin-wheel/agents/<name>.md",
        "subagent_type": "<type>",
        "tools": ["..."],
        "model_default": "<haiku|sonnet|opus|null>"
      }
    }
  }
  ```
- **I-R4**: The resolver MUST use `${WORKFLOW_PLUGIN_DIR}` to anchor relative paths when the repo root doesn't contain `plugin-wheel/`. If `WORKFLOW_PLUGIN_DIR` is unset AND the repo-relative path doesn't resolve, exit 1 with a diagnostic — do NOT silently emit a broken path.
- **I-R5**: `system_prompt_path` in the JSON output MUST be a real filesystem path the caller can read. It MAY be either absolute or `WORKFLOW_PLUGIN_DIR`-prefixed; callers MUST NOT assume form.

### Tests (NFR-1)

- Unit: each of the four input forms (a–d) returns the expected JSON shape.
- Unit: `WORKFLOW_PLUGIN_DIR` unset + non-absolute input → exit 1 with diagnostic (no silent broken path).
- Unit: unknown name → exit 0, passthrough shape with `"source": "unknown"`.
- Integration: the resolver is invoked from a kiln skill (`/kiln:kiln-fix`) and the resulting spawn uses the right spec (SC-005).
- Reference walker (SC-008): every `agent_path:` in every workflow JSON + every `subagent_type:`/agent-reference in every kiln skill resolves through this resolver without exit 1.

---

## 2. Workflow JSON `agent_path:` field

**File**: `plugin-wheel/workflows/*.json` + dispatched via `plugin-wheel/scripts/dispatch/dispatch-agent-step.sh`
**Owners**: `impl-themeA-agents` (field schema); `impl-wheel-fixes` (dispatch integration may overlap)

### Schema addition

```json
{
  "type": "agent",
  "name": "step-name",
  "agent_path": "<path-or-name>",   // NEW — optional. Consumed by resolver §1.
  "subagent_type": "...",            // EXISTING — stays supported.
  "model": "haiku|sonnet|opus|<id>", // NEW — see §3.
  "prompt": "..."
}
```

### Invariants

- **I-A1**: `agent_path:` is **optional**. Absent field = current behavior (NFR-5 byte-identical).
- **I-A2**: When both `agent_path:` and `subagent_type:` are present, `agent_path:` wins (its resolved `subagent_type` from §1 output overrides). Dispatcher emits an INFO log line `agent_path overrides explicit subagent_type` — NOT silent.
- **I-A3**: If `agent_path:` resolves to `{ "source": "unknown" }` (resolver exit 0, passthrough), the dispatcher falls back to the step's explicit `subagent_type:` (or the workflow default). This preserves back-compat for legacy values in the field.
- **I-A4**: If the resolver exits 1 for a given `agent_path:`, the workflow step fails loudly with the resolver's stderr propagated — NEVER silent pass.

### Tests (NFR-1)

- Workflow-test: a test workflow with `agent_path: debugger` dispatches and the spawned agent's system prompt is `plugin-wheel/agents/debugger.md`.
- Workflow-test: `agent_path:` absent → byte-identical state file to pre-PRD baseline (NFR-5).
- Workflow-test: `agent_path: <nonsense-path>` → dispatcher fails loudly, workflow state shows the failure (not an empty-output advance).

---

## 3. Workflow JSON `model:` field

**File**: `plugin-wheel/workflows/*.json` + `plugin-wheel/scripts/dispatch/resolve-model.sh`
**Owners**: `impl-themeB-models`

### Schema addition

```json
{
  "type": "agent",
  "name": "step-name",
  "model": "haiku|sonnet|opus|<explicit-model-id>"  // NEW — optional
}
```

### `resolve-model.sh` signature

```bash
# Usage:
#   plugin-wheel/scripts/dispatch/resolve-model.sh <model-spec>
#
# Arguments:
#   <model-spec>  One of:
#                   "haiku"    → resolves to project-default haiku model id
#                   "sonnet"   → resolves to project-default sonnet model id
#                   "opus"     → resolves to project-default opus model id
#                   "<id>"     → passed through if it matches /^claude-[a-z0-9-]+$/
#
# Exit codes:
#   0  — resolved successfully, model id on stdout
#   1  — unrecognized tier, unrecognized id shape, or project config missing
#
# Stdout (on exit 0):
#   <concrete-model-id>    (e.g. "claude-haiku-4-5-20251001")
#
# Stderr:
#   Human-readable diagnostic on exit 1. NEVER silent.
```

### Invariants

- **I-M1**: `model:` is **optional**. Absent field = current harness-default behavior (NFR-5).
- **I-M2**: On resolve failure (unrecognized tier, malformed id), dispatch fails LOUDLY with an identifiable error string (`"wheel: model resolution failed for step '<name>': <detail>"`). **NEVER silent fallback to the default model.** This is the FR-B2 invariant.
- **I-M3**: Valid explicit ids are admitted via the regex `^claude-[a-z0-9-]+$`. The resolver does NOT round-trip the id to the harness to validate — if the harness rejects the id, that rejection surfaces at dispatch time, also loudly.
- **I-M4**: The tier → concrete-id mapping lives in `plugin-wheel/scripts/dispatch/model-defaults.json` and is version-controlled. Future tier-default changes update this file.

### Tests (NFR-1)

- Unit: `resolve-model.sh haiku` → non-empty stdout matching `^claude-haiku-`.
- Unit: `resolve-model.sh claude-haiku-4-5-20251001` → echoes input.
- Unit: `resolve-model.sh bogus` → exit 1, identifiable stderr.
- Workflow-test: a shipped workflow uses `model: haiku` on a classification step (SC-006) and the spawned agent's model matches.
- Workflow-test: `model: claude-nonexistent-id` → dispatch fails loudly (FR-B2 invariant).

---

## 4. Post-tool-use hook command-extraction contract

**File**: `plugin-wheel/hooks/post-tool-use.sh`
**Owners**: `impl-wheel-fixes` (sole owner)

### Contract

```bash
# Input (stdin):
#   Raw hook JSON from the Claude Code harness. Expected shape (simplified):
#   {
#     "tool_name": "Bash",
#     "tool_input": {
#       "command": "<arbitrary string, MAY contain \n, quoted newlines, control chars>",
#       "description": "..."
#     },
#     "tool_response": { ... }
#   }
#
# Processing contract (FR-C1):
#   1. Extract tool_input.command via `jq -r '.tool_input.command // ""'` FIRST.
#      This preserves all characters in the command string, including newlines.
#   2. Do NOT apply `tr '\n' ' '` or any blanket flatten to the command string.
#   3. If jq fails (malformed JSON), fall back to a JSON-aware sanitizer:
#        python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))"
#      This path MUST still preserve newlines in the command.
#   4. Defensive sanitization of OTHER fields (e.g. logging metadata) is allowed
#      but MUST NOT touch the command string.
#
# Regex match (FR-C2):
#   The activate-detection regex MUST match `/path/to/activate.sh <workflow>` anywhere
#   in the (non-flattened) command string, across multiple lines. Use a regex that
#   does not anchor to line start/end, OR iterate lines.
#
# Output:
#   Same as today (exit code + state-file side effect + log line).
#
# NEVER:
#   - Silently drop characters the LLM emitted.
#   - Advance the workflow with an empty-detected command.
#   - Pre-flatten newlines before regex evaluation.
```

### Invariants

- **I-H1**: Multi-line Bash tool calls containing `activate.sh <workflow>` anywhere in the body MUST activate the workflow (FR-C2).
- **I-H2**: Single-line Bash tool calls MUST continue to activate workflows byte-identically to pre-PRD behavior (FR-C4 strict-superset).
- **I-H3**: Hook input that is malformed JSON MUST produce an identifiable error — either via the python3 fallback succeeding, or via a loud diagnostic. **Silent drop is forbidden** (NFR-2).
- **I-H4**: Blast-radius: other regexes in `plugin-wheel/hooks/` and `plugin-wheel/scripts/` that previously assumed single-line input MUST be enumerated during Phase 0 R-004 research and fixed as sibling tasks inside this PRD.

### Tests (NFR-1, NFR-2, NFR-3)

- Unit: multi-line Bash tool call with activation in the last line → workflow activates.
- Unit: multi-line Bash tool call with activation in the middle → workflow activates.
- Unit: single-line activation (existing fixture) → still passes.
- Unit: heredoc-embedded activation (`<<EOF ... activate.sh … EOF`) → activates.
- Fuzz (NFR-3): property test over hook-input shapes with quoted newlines, `\t`, `\r`, ` `, valid-but-weird JSON escapes — no silent flatten, no silent drop.
- Regression tripwire (NFR-2): a test that inserts `tr '\n' ' '` back into the hook MUST fail loudly with an identifiable error string.

---

## 5. `WORKFLOW_PLUGIN_DIR` env export contract

**File (Option B — shipped)**: `plugin-wheel/lib/context.sh` (`context_build` prepends the Runtime Environment block).
**File (Option A — not shipped)**: ~~`plugin-wheel/scripts/workflow-env.sh` + `plugin-wheel/scripts/dispatch-subagent.sh`~~ — these files **do not exist**. See §5 addendum below.
**Owners**: `impl-wheel-fixes` (sole owner)

### §5 Addendum — Option B shipped (post-implementation note)

Per research.md R-001 and the Phase 0 T020 verdict in `specs/wheel-as-runtime/agent-notes/impl-wheel-fixes.md`, **Option A is infeasible** for agent-step sub-agents. Wheel's agent step returns a hook response and the hook process dies before the harness spawns the sub-agent — wheel does not own the spawn boundary, so no env var wheel exports ever reaches the sub-agent.

The originally-named anchor files (`plugin-wheel/scripts/workflow-env.sh`, `plugin-wheel/scripts/dispatch-subagent.sh`) were aspirational Option-A paths. Neither file is present in the shipped implementation. **The Option B implementation lives in `plugin-wheel/lib/context.sh`'s `context_build`**, which prepends a `## Runtime Environment (wheel-templated, FR-D1)` block to every agent step's instruction text. The absolute `WORKFLOW_PLUGIN_DIR` value is derived from `state.workflow_file` (same derivation as `dispatch_command`'s direct env export for command steps).

Agent-step authors read the block and propagate the value into Bash tool calls (`export WORKFLOW_PLUGIN_DIR='<abs>'`) and nested sub-agent prompts (verbatim line at the top). Command steps continue to receive the var via direct env export in `plugin-wheel/lib/dispatch.sh`'s `dispatch_command` — no change there.

Invariants I-E1, I-E2, I-E3 (below) are all satisfied by the Option B shape and enforced by the tests listed in the "Tests" subsection. The FR-D4 regression fingerprint invariant is likewise enforced unchanged. Auditors and future readers should treat `plugin-wheel/lib/context.sh` as the authoritative Option-B implementation anchor; the contract's "File" field above now reflects this.

### Contract

```bash
# WORKFLOW_PLUGIN_DIR is the absolute path to the plugin's install directory.
#
# For a source-repo run:    <repo-root>/plugin-<name>/
# For a consumer install:   ~/.claude/plugins/cache/<org>-<mp>/<plugin>/<version>/
#
# Invariant (FR-D1):
#   WORKFLOW_PLUGIN_DIR MUST be present in the environment of EVERY sub-agent
#   spawned by a wheel agent step, regardless of Agent(run_in_background: true|false).
#
# Implementation Option A (preferred):
#   wheel exports WORKFLOW_PLUGIN_DIR into the workflow-lifetime env scope at
#   dispatch time. Any sub-agent (foreground or background) inherits it via
#   normal process env inheritance. Validate via the FR-D2 smoke test before
#   declaring Option A viable.
#
# Implementation Option B (fallback only):
#   If Option A is infeasible (the harness baselines its own env for bg spawns
#   and wheel cannot influence it), fall back to templating the absolute path
#   into the sub-agent's prompt at dispatch time (e.g. "WORKFLOW_PLUGIN_DIR=...")
#   AND surface this in CLAUDE.md FR-D3.
#
# Invariant (FR-D4):
#   The string "WORKFLOW_PLUGIN_DIR was unset" MUST NOT appear in any
#   .kiln/logs/report-issue-bg-*.md line written post-PRD.
#   This string is the regression fingerprint. Its absence is the smoke-test
#   assertion (git grep -F returns zero matches).
```

### Invariants

- **I-E1**: Foreground and background sub-agents see IDENTICAL `WORKFLOW_PLUGIN_DIR` values. No divergence.
- **I-E2**: The consumer-install smoke test (FR-D2) MUST simulate the layout where `plugin-shelf/`, `plugin-kiln/` are absent from the repo root — scripts only available under the install-cache path. A test that passes only because source-repo paths happen to resolve is insufficient (this is what shipped the original bug).
- **I-E3**: NFR-4: the smoke test MUST run in CI on every PR touching `plugin-wheel/` or any plugin's workflow JSON. Local-only runs don't count.

### Tests (NFR-1, NFR-2, NFR-4)

- Smoke test (FR-D2): in a staging dir where source-repo plugin dirs are moved aside, run a workflow that spawns a background sub-agent and assert the sub-agent resolves its scripts via `${WORKFLOW_PLUGIN_DIR}`.
- Assertion: `grep -F 'WORKFLOW_PLUGIN_DIR was unset' .kiln/logs/report-issue-bg-*.md` returns zero matches in lines dated after the smoke test's start timestamp.
- Regression tripwire (NFR-2): a test that removes the Option B Runtime Environment block from `plugin-wheel/lib/context.sh` MUST fail the FR-D2 smoke test with an identifiable error string. (Shipped at `plugin-wheel/tests/workflow-plugin-dir-tripwire/run.sh` — asserts the string `"FR-D1 Runtime Environment block missing"`. Original Option-A-phrased tripwire targeting `workflow-env.sh` is moot since that file does not exist.)
- CI wiring (NFR-4): `.github/workflows/wheel-tests.yml` runs the FR-D2 smoke test on every PR touching `plugin-wheel/**` or `plugin-*/workflows/**`.

---

## 6. Batched step wrapper contract

**File**: `plugin-<name>/scripts/step-<stepname>.sh` (documented candidate: `plugin-shelf/scripts/step-dispatch-background-sync.sh`)
**Owners**: `impl-themeE-batching`

### Contract

```bash
#!/usr/bin/env bash
# A batched step wrapper consolidates a previously-multi-call deterministic
# sequence (typically 3-10 bash calls the agent was making back-to-back) into
# a single shell script.
#
# Required structure (FR-E4 convention):

set -e
set -u
# Optional: set -o pipefail — recommended for any pipelined action.

STEP_NAME="<name>"
LOG_PREFIX="wheel:${STEP_NAME}"

# Prefer reading inputs from env vars set by the calling workflow
# (WORKFLOW_PLUGIN_DIR, WHEEL_STATE_FILE, step-specific vars).
# Fall back to $1, $2, … only if env is not appropriate.

echo "${LOG_PREFIX}: start | $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- Action 1 ----
echo "${LOG_PREFIX}: action=<name1> | start"
# … do the work …
echo "${LOG_PREFIX}: action=<name1> | ok"

# ---- Action 2 ----
echo "${LOG_PREFIX}: action=<name2> | start"
# … do the work …
echo "${LOG_PREFIX}: action=<name2> | ok"

# ---- Final structured output ----
# MUST emit a single-line JSON object on stdout as the final line
# so the calling step has a parseable success/failure signal:
jq -n --arg step "${STEP_NAME}" --arg status "ok" \
  '{step: $step, status: $status, actions: ["<name1>","<name2>"]}'

echo "${LOG_PREFIX}: done | $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

### Invariants

- **I-B1**: `set -e` (hard-fail on error) and `set -u` (undefined-var protection) MUST be at the top. `pipefail` SHOULD be set when any pipeline is used.
- **I-B2**: Each action MUST emit `start` and `ok` (or error-propagated-by-set-e) log lines with the `LOG_PREFIX`. Debuggability is a first-class trade-off with batching (FR-E4).
- **I-B3**: The wrapper MUST emit a final JSON object on stdout with at least `{ "step": "<name>", "status": "ok", "actions": [...] }`. This is the parseable success signal for the calling step. A non-zero exit (from `set -e`) is the failure signal.
- **I-B4**: The wrapper MUST use `${WORKFLOW_PLUGIN_DIR}` to reference any plugin-local script (not a repo-relative path). This is the same portability invariant that §5 establishes.
- **I-B5**: FR-E3 before/after measurements are recorded in `.kiln/research/wheel-step-batching-audit-<date>.md` with:
  - wall-clock time for the step BEFORE consolidation (3+ samples, same session, same hardware)
  - wall-clock time AFTER consolidation (3+ samples, same session, same hardware)
  - raw numbers, not "faster/slower"
  - environment details (OS, Bash version, harness version)

### Tests (NFR-1, NFR-6)

- Unit: the wrapper runs end-to-end in a tmp dir and the final JSON matches `{"step":..., "status":"ok", ...}`.
- Unit: a deliberately-failing action mid-wrapper → wrapper exits non-zero, per-action log prefix identifies WHICH action failed.
- Integration: the workflow that calls the wrapper completes with the same state-file shape as before batching (semantic equivalence).
- Perf (NFR-6): before/after measurements committed to the audit doc. Negative result (no speedup) is acceptable per FR-E3 — the audit MUST be honest.

---

## Cross-contract invariants

- **CC-1 (back-compat)**: NFR-5. Workflows that use NEITHER `agent_path:` NOR `model:` MUST produce byte-identical `.wheel/state_*.json` on a pre-PRD vs post-PRD run. This is verified by a diff test on at least one shipped workflow.
- **CC-2 (portability)**: Every new script in this PRD (resolver, dispatch helpers, step wrapper) MUST use `${WORKFLOW_PLUGIN_DIR}` for plugin-local path references. Hardcoded `plugin-<name>/scripts/…` is a portability bug regardless of whether it works in this source repo (per CLAUDE.md "Plugin workflow portability" section).
- **CC-3 (loud-failure)**: Every new failure mode (resolver exit 1, dispatch model-resolve failure, hook malformed JSON, env export missing, wrapper action failure) MUST emit an identifiable error string to stderr or the log. Silent-no-op is the original bug shape and is forbidden (NFR-2).
- **CC-4 (atomic migration)**: Theme A's agent-file migration (FR-A2, NFR-7) lands in ONE PR. Symlinks at old paths MUST be created in the same commit as the canonical-path files, so the resolver's reference-walker (SC-008) never sees a half-migrated state.
