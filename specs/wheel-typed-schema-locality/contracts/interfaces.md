# Interface Contracts: Wheel Typed-Schema Locality

**Article VII compliance**: every exported function below has an exact signature. Implementation MUST match — including parallel sub-agent work.

These contracts are the single source of truth. If a signature needs to change during implementation, update this file FIRST.

---

## §1 `workflow_validate_output_against_schema`

**Location**: `plugin-wheel/lib/workflow.sh` (next to existing `workflow_validate_inputs_outputs`).

**Purpose**: Validate that an agent step's `output_file` content has top-level keys matching the declared `output_schema:`. Returns structured diff on violation. Live runtime function — distinct from the load-time `workflow_validate_inputs_outputs` (which is a pre-flight shape check).

**Signature**:
```
workflow_validate_output_against_schema <step_json> <output_file_path>
```

| Param | Type | Description |
|---|---|---|
| `$1 step_json` | string (JSON, single-line) | The agent step JSON. Must contain `.id`, `.output_schema`. If `.output_schema` is absent or `{}`, function exits 0 silently. |
| `$2 output_file_path` | string (filesystem path) | Absolute or repo-relative path to the agent's `output_file`. Must exist and be readable. |

**Exit codes**:
- `0` — validation passed (or skipped because `output_schema` absent/empty). No stdout, no stderr.
- `1` — **schema violation** (FR-H1-2 / FR-H1-6). Stderr emits the multi-line diagnostic body verbatim per FR-H1-2 shape (no leading/trailing newlines beyond what's in the spec):
  ```
  Output schema violation in step '<step-id>'.
    Expected keys (from output_schema): <comma-separated, LC_ALL=C sorted>
    Actual keys in <output_file_path>: <comma-separated, LC_ALL=C sorted>
    Missing: <comma-separated, sorted>
    Unexpected: <comma-separated, sorted>
  Re-write the file with the expected keys and try again.
  ```
  When `Missing` is empty: the entire `Missing: …` line is omitted (not "Missing: " with trailing space). Same rule for `Unexpected`.
- `2` — **validator runtime error** (FR-H1-7 / NFR-H-7). Stderr emits a single line naming the underlying error class:
  ```
  Output schema validator error in step '<step-id>': <category>: <detail>
  ```
  Where `<category>` is one of: `output_file is not valid JSON`, `output_file not found`, `output_file is not readable`, `output_schema directive malformed at field '<field>'`. `<detail>` is a short single-line elaboration (e.g. `jq: parse error at line 1, col 5`).

**Stdout**: empty in all cases.

**Side effects**: NONE. The bad `output_file` is NOT deleted (FR-H1-5). No state mutations. No fs writes.

**Implementation notes**:
- Reads `output_schema` keys via `jq -r '.output_schema | keys_unsorted[]' <<< "$step_json"` then sorts with `LC_ALL=C sort`.
- Reads `output_file` actual top-level keys via `jq -r 'keys_unsorted[]' "$output_file_path"` then sorts the same way.
- Computes set difference both directions for `Missing` and `Unexpected`.
- v1 validates only top-level key presence — does NOT recursively validate nested paths declared in directives like `{result: {extract: "jq:.result.ok"}}`. Spec §Edge Cases.
- Empty `output_schema: {}` → exit 0 silently (treated as "no schema declared").

---

## §2 Stop-hook + post-tool-use validator wiring

**Location**: `plugin-wheel/lib/dispatch.sh::dispatch_agent`.

### §2.1 `post_tool_use` branch (primary fail-fast — FR-H1-1 / FR-H1-3)

**Insertion point**: line ~833, after the line `# Agent wrote to the output file — mark step done, advance` and BEFORE `state_set_step_status "$state_file" "$step_index" "done"`.

**Pseudocode**:
```bash
# Run output-schema validator (FR-H1-1).
local _validator_out _validator_rc
_validator_out=$(workflow_validate_output_against_schema "$step_json" "$wrote_to" 2>&1)
_validator_rc=$?
case "$_validator_rc" in
  0)
    : # Pass — silent. Fall through to existing advance logic.
    ;;
  1)
    # FR-H1-6: schema violation. Cursor stays on this step (status remains 'working').
    # FR-H1-5: bad output_file is left in place — agent overwrites on next attempt.
    declare -f wheel_log >/dev/null 2>&1 && \
      wheel_log "post_tool_use" "reason=output-schema-violation step=${step_id}"
    jq -n --arg msg "$_validator_out" '{"decision": "block", "reason": $msg}'
    return 0
    ;;
  2)
    # FR-H1-7 / NFR-H-7: validator runtime error.
    declare -f wheel_log >/dev/null 2>&1 && \
      wheel_log "post_tool_use" "reason=output-schema-validator-error step=${step_id}"
    jq -n --arg msg "$_validator_out" '{"decision": "block", "reason": $msg}'
    return 0
    ;;
esac
```

**Contract**:
- On exit 0: dispatch_agent post_tool_use branch falls through to existing `state_set_step_status … done` + advance behavior. NO behavior change for legacy steps without `output_schema` (FR-H1-8 — validator early-returns 0).
- On exit 1: returns `decision=block` to the agent's same turn with the FR-H1-2 diagnostic body. State unchanged (status remains `working`, cursor unchanged, `contract_emitted` unchanged).
- On exit 2: returns `decision=block` to the agent's same turn with the FR-H1-7 error body. State unchanged.

### §2.2 `stop` branch (defense-in-depth — FR-H1-1 belt-and-suspenders)

**Insertion point**: line ~624 in dispatch_agent's `stop` branch, inside the `if [[ -n "$output_key" && -f "$output_key" ]]; then` block, BEFORE `state_set_step_status "$state_file" "$step_index" "done"`.

**Same pseudocode shape as §2.1**. Catches the case where post-tool-use missed the write (e.g. Edit tool writing to the file when only Write was matched, edge cases in the file-path comparison).

### §2.3 `teammate_idle` branch (mirror of `stop`)

**Insertion point**: line ~713, mirroring §2.2.

### §2.4 New error reasons (FR-H1-6, FR-H1-7)

| Reason | Source | Triggered when |
|---|---|---|
| `output-schema-violation` | dispatch.sh post_tool_use + stop + teammate_idle branches | `workflow_validate_output_against_schema` exit 1 |
| `output-schema-validator-error` | dispatch.sh post_tool_use + stop + teammate_idle branches | `workflow_validate_output_against_schema` exit 2 |

Both reasons are surfaced via the standard wheel hook response (`{"decision": "block", "reason": <body>}`), logged via `wheel_log`, and visible in `.wheel/logs/wheel-<sid>.log`.

---

## §3 `context_compose_contract_block`

**Location**: `plugin-wheel/lib/context.sh`.

**Purpose**: Format the `## Resolved Inputs` + `## Step Instruction` + `## Required Output Schema` markdown for an agent step's Stop-hook feedback (Theme H2). Pure formatting — no I/O, no state mutations.

**Signature**:
```
context_compose_contract_block <step_json> <resolved_map_json>
```

| Param | Type | Description |
|---|---|---|
| `$1 step_json` | string (JSON, single-line) | The agent step JSON. Reads `.inputs`, `.instruction`, `.output_schema`. |
| `$2 resolved_map_json` | string (JSON, single-line, may be `{}`) | Resolved-inputs map produced by `resolve_inputs` (PR #166). When `{}`, the `## Resolved Inputs` section is omitted. |

**Output (stdout)**: contract markdown — empty string when NEITHER `inputs:` NOR `output_schema:` is declared (FR-H2-4 strict back-compat). Otherwise: composes sections in the deterministic order:

```
## Resolved Inputs
- **<VAR1>**: <value1>
- **<VAR2>**: <value2>
…

## Step Instruction

<post-{{VAR}}-substitution instruction text>

## Required Output Schema

```json
<jq -c '.output_schema' of step_json — single-line JSON>
```
```

**Section omission rules** (FR-H2-6):
- `## Resolved Inputs` omitted iff `resolved_map_json` is `{}` OR step's `inputs:` is absent.
- `## Step Instruction` omitted iff step's `instruction:` is absent or empty.
- `## Required Output Schema` omitted iff step's `output_schema:` is absent or `{}`.
- When ALL three are omitted: function emits empty string (FR-H2-4 back-compat path).

**`{{VAR}}` substitution**: reuses `substitute_inputs_into_instruction` from `plugin-wheel/lib/preprocess.sh` (already imported by `context_build`). Same behavior as PR #166.

**Exit codes**:
- `0` — always. Pure formatting; no failure modes.

**Side effects**: NONE.

---

## §4 State-file extensions

**Location**: `plugin-wheel/lib/state.sh`.

### §4.1 `state_set_resolved_inputs`

**Signature**:
```
state_set_resolved_inputs <state_file> <step_index> <resolved_map_json>
```

| Param | Type | Description |
|---|---|---|
| `$1 state_file` | string (path) | Absolute path to wheel state file. |
| `$2 step_index` | integer | 0-based step index. |
| `$3 resolved_map_json` | string (JSON, single-line) | The resolved-inputs map output by `resolve_inputs`. Empty `{}` is acceptable and sets the field to `{}`. |

**Effect**: writes `.steps[$step_index].resolved_inputs = <resolved_map_json>` to the state file via `jq` + atomic rewrite (mirrors existing `state_set_step_status` pattern).

**Exit codes**:
- `0` — success.
- `1` — state file missing, malformed JSON, or jq failure.

**Side effects**: in-place state file rewrite via temp + `mv` (atomic).

### §4.2 `state_set_contract_emitted`

**Signature**:
```
state_set_contract_emitted <state_file> <step_index> <true|false>
```

**Effect**: writes `.steps[$step_index].contract_emitted = <bool>` to the state file. Default before first set is `false` (read via `// false` in callers).

**Exit codes**:
- `0` — success.
- `1` — state file missing, malformed JSON, jq failure, or `$3` not in `{true, false}`.

### §4.3 `state_get_contract_emitted`

**Signature**:
```
state_get_contract_emitted <state_file> <step_index>
```

**Output (stdout)**: `true` or `false`.

**Exit code**: 0 always (returns `false` for missing field).

---

## §5 dispatch_agent stop-branch contract surfacing wiring

**Location**: `plugin-wheel/lib/dispatch.sh::dispatch_agent`, `stop` branch's "Output file expected but not yet produced — short reminder" else-leaf (line ~679).

**Insertion point**: BEFORE the existing `jq -n --arg msg "Step '${step_id}' is in progress. Write your output to: ${output_key}"` line.

**Pseudocode**:
```bash
# FR-H2-5 / FR-H2-7: emit contract block on FIRST entry per step only.
local _emitted
_emitted=$(state_get_contract_emitted "$state_file" "$step_index")
local _contract_block=""
if [[ "$_emitted" != "true" ]]; then
  local _resolved_map_persisted
  _resolved_map_persisted=$(jq -r --argjson idx "$step_index" \
    '.steps[$idx].resolved_inputs // {}' "$state_file" 2>/dev/null)
  _contract_block=$(context_compose_contract_block "$step_json" "$_resolved_map_persisted")
  if [[ -n "$_contract_block" ]]; then
    state_set_contract_emitted "$state_file" "$step_index" "true"
  fi
fi

local _reminder="Step '${step_id}' is in progress. Write your output to: ${output_key}"
local _body
if [[ -n "$_contract_block" ]]; then
  _body="${_contract_block}"$'\n\n'"${_reminder}"
else
  _body="$_reminder"
fi
jq -n --arg msg "$_body" '{"decision": "block", "reason": $msg}'
```

**Contract**:
- Legacy step (no `inputs:`/no `output_schema:`): `_contract_block` is empty → body is exactly the existing reminder. NFR-H-3 byte-identity preserved.
- Typed step, first entry: contract block prepended to reminder, `contract_emitted` flipped to `true`.
- Typed step, subsequent entries: contract block suppressed, only reminder emitted (FR-H2-5).

**Mirror in `teammate_idle` branch** (line ~759): identical insertion + pseudocode.

**No insertion in `pending → working` transition** (line ~603): the `context_build` path already prepends the resolved-inputs block to the agent's first-dispatch prompt (PR #166). Theme H2's surfacing kicks in on subsequent Stop ticks while the agent is `working`, NOT on the initial dispatch.

---

## §6 `dispatch_agent` resolved-inputs persistence (Phase 1 plumbing)

**Location**: `plugin-wheel/lib/dispatch.sh::dispatch_agent`, `stop` branch's `pending → working` transition (line ~603), AND `teammate_idle` branch's mirror (line ~693).

**Insertion point**: AFTER the `_resolved_map=$(_hydrate_agent_step …)` call AND after `context_build` succeeds, BEFORE the final `jq -n --arg msg "$context"` emission.

**Pseudocode**:
```bash
# §6: persist resolved_map for Stop-hook re-read (FR-H2-1 caching, NFR-H-5 perf).
state_set_resolved_inputs "$state_file" "$step_index" "$_resolved_map"
```

**Contract**:
- Always called, even when `_resolved_map` is `{}` — keeps the state file shape uniform.
- Failure (state_set_resolved_inputs exit 1) is non-fatal — the contract block falls back to "no resolved inputs" gracefully (Resolved Inputs section omitted). A wheel_log line is emitted but dispatch continues. (Rationale: Theme H2 is a UX nicety; a state-file write failure shouldn't block the workflow.)

---

## §7 Validator early-return invariants (FR-H1-8 back-compat)

`workflow_validate_output_against_schema` (§1) MUST early-return exit 0 with NO stderr in these cases:
- `step_json` has no `.output_schema` field.
- `step_json` has `.output_schema` set to `{}` (empty object).
- `step_json` has `.output_schema` set to `null`.

This guarantees NFR-H-3 byte-identical Stop-hook feedback for legacy workflows: the validator runs but is a no-op, and no `wheel_log` line is emitted for legacy steps.

---

## §8 Reason-code grep contract

The reason strings `output-schema-violation` and `output-schema-validator-error` are part of the public contract — they appear in `.wheel/logs/wheel-<sid>.log` and in archive `command_log` arrays, and tests grep for them. Renaming requires a contract update + tripwire fixture update. Reason codes MUST be lowercase-kebab-case (matches existing `preprocess-tripwire`, `unresolved-or-invalid` conventions).

---

## §9 Out-of-contract (NOT changed by this PRD)

- `resolve_inputs` (PR #166) — signature unchanged.
- `workflow_validate_inputs_outputs` (PR #166 load-time validator) — signature unchanged.
- `context_build` — signature unchanged. `context_build` continues to prepend `## Resolved Inputs` + `## Step Instruction` to the agent's initial dispatch prompt; Theme H2's Stop-hook surfacing is a SEPARATE composition path.
- Stop-hook wire shape (`{decision, reason, …}`) — unchanged.
- State file top-level shape — unchanged. Only the per-step record gains `resolved_inputs` (object) and `contract_emitted` (bool) fields.
