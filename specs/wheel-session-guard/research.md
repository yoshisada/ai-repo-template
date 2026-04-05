# Research: Wheel Session Guard

## Hook Input JSON Structure

**Decision**: Extract `session_id` and `agent_id` from the top-level hook input JSON object.

**Rationale**: Claude Code hook input JSON includes `session_id` at the top level for all hook events. The `agent_id` field is present when the event originates from a subagent or teammate. Both are string fields.

**Alternatives considered**: Parsing from environment variables (not available in hook context), reading from Claude Code config files (fragile, not guaranteed to exist).

## Guard Return Convention

**Decision**: Use bash exit codes — 0 for "owner, proceed" and 1 for "non-owner, pass through".

**Rationale**: Standard bash convention. Callers use `if guard_check ...; then proceed; else passthrough; fi`. Simple, no stdout parsing needed for the decision itself.

**Alternatives considered**: Stdout JSON output (adds parsing overhead), global variable (fragile across subshells).

## First-Hook Stamping vs Skill-Time Stamping

**Decision**: Stamp ownership on the first hook event, not during `/wheel-run` skill execution.

**Rationale**: Skills don't receive hook input JSON — they don't have access to `session_id` or `agent_id`. The first hook event after `state_init` reliably comes from the same agent that ran the skill due to synchronous event dispatch. The `state_init` function sets `owner_session_id` and `owner_agent_id` to empty strings, and `guard_check` stamps them on first invocation when empty.

**Alternatives considered**: Passing session context via environment variables from the skill (not reliably available), requiring the skill to read Claude Code internal state files (fragile, undocumented).

## Ownership Field Placement in state.json

**Decision**: Add `owner_session_id` and `owner_agent_id` as top-level fields in state.json, alongside `workflow_name`, `status`, `cursor`, etc.

**Rationale**: Ownership is a workflow-level concern, not a step-level concern. Top-level placement keeps the read path simple (one `jq` read) and matches the existing flat schema.

**Alternatives considered**: Nested under an `owner` object (unnecessary nesting for two fields), separate lock file (adds filesystem complexity).

## Guard Placement in Hook Scripts

**Decision**: Call `guard_check` after `engine_init` (which sets `STATE_FILE`) but before `engine_handle_hook` or any state-modifying logic.

**Rationale**: `engine_init` must run first to set the `STATE_FILE` global that `guard_check` needs. The guard must run before any state mutation. For `subagent-start.sh` which has inline logic before `engine_handle_hook`, the guard must also precede that inline logic.

**Alternatives considered**: Inside `engine_handle_hook` (would centralize but wouldn't cover the inline logic in subagent-start.sh), before `engine_init` (STATE_FILE not set yet).
