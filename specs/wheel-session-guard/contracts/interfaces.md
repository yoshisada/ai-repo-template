# Interface Contracts: Wheel Session Guard

## New Functions

### `guard_check` (lib/guard.sh)

```bash
# FR-002/003/004/007: Check if the current hook event comes from the workflow owner.
# If ownership is not yet stamped (empty), stamps it from hook input (first-hook stamping).
#
# Params:
#   $1 = state_file (string) — path to .wheel/state.json
#   $2 = hook_input_json (string) — raw JSON from hook stdin
#
# Output (stdout): none on allow (return 0), none on pass-through (return 1)
# Side effects: May write to state_file (first-hook stamping only)
#
# Exit codes:
#   0 = owner match (or first-hook stamp) — caller should proceed with hook logic
#   1 = non-owner or unidentifiable — caller should output pass-through JSON and exit
guard_check() {
  local state_file="$1"
  local hook_input_json="$2"
  # ...
}
```

## Modified Functions

### `state_init` (lib/state.sh)

```bash
# FR-002 (original) + FR-001 (session-guard): Initialize a new state.json from a workflow definition.
# MODIFIED: Now includes owner_session_id and owner_agent_id fields (both initialized to "").
#
# Params:
#   $1 = state file path
#   $2 = workflow JSON (string)
#   $3 = workflow file path (string, optional)
#
# Output: none (creates state file)
# Exit: 0 on success, 1 on failure
#
# New fields in output JSON:
#   owner_session_id: "" (empty — stamped by first hook event via guard_check)
#   owner_agent_id: "" (empty — stamped by first hook event via guard_check)
state_init() {
  # existing params unchanged
  # existing logic unchanged
  # ADD owner_session_id and owner_agent_id to the jq -n block
}
```

## Hook Script Integration Pattern

All 6 hook scripts follow this integration pattern (not a function — inline in each hook):

```bash
# After engine_init succeeds and before engine_handle_hook or inline logic:

# Session guard — only the owning agent can advance the workflow
if ! guard_check "$STATE_FILE" "$HOOK_INPUT"; then
  echo '{"decision": "approve"}'  # or appropriate pass-through for the hook type
  exit 0
fi

# ... existing hook logic continues ...
```

**Hook-specific pass-through responses**:

| Hook | Pass-through JSON |
|------|-------------------|
| stop.sh | `{"decision": "approve"}` |
| post-tool-use.sh | `{"hookEventName": "PostToolUse"}` |
| subagent-start.sh | `{"decision": "approve"}` |
| subagent-stop.sh | `{"decision": "approve"}` |
| teammate-idle.sh | `{"decision": "approve"}` |
| session-start.sh | `{"decision": "approve"}` |

## Files NOT Modified (FR-005)

- `plugin-wheel/skills/wheel-status/SKILL.md` — skills don't pass through hooks, guard is not applied
- `plugin-wheel/skills/wheel-stop/SKILL.md` — skills don't pass through hooks, guard is not applied
