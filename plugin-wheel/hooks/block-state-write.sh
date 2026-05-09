#!/bin/bash
# Block direct writes to .wheel/state_*.json files.
# State files are managed exclusively by the wheel hook system.
# Must never crash — always exit 0 unless actively blocking.

INPUT=$(cat 2>/dev/null || true)

# If no input or jq not available, allow
if [[ -z "$INPUT" ]] || ! command -v jq &>/dev/null; then
  exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

# FR-C1 / R-004: the pre-existing `jq ... 2>/dev/null || true` pattern
# silently returned an empty COMMAND when jq choked on literal control
# characters in tool_input.command (Claude Code's harness emits these).
# Empty COMMAND → the state-write regex below never matched → state-file
# writes slipped through this hook undetected. NFR-2 forbids silent-drop;
# extract via jq first and fall back to a pure-node relaxed parser
# (_extract-command.mjs) which escapes literal control chars inside string
# contexts. If BOTH fail, emit an identifiable stderr diagnostic (not
# silent) and proceed with empty COMMAND. The relaxed parser replaces the
# previous python3 strict=False fallback — wheel has zero runtime python
# dependency. Tripwire coverage:
# `plugin-wheel/tests/hook-no-preflatten-tripwire/`.
COMMAND=""
if _tmp=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null); then
  COMMAND="$_tmp"
elif command -v node >/dev/null 2>&1; then
  _SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if _tmp=$(printf '%s' "$INPUT" | node "${_SCRIPT_DIR}/_extract-command.mjs" 2>/dev/null); then
    COMMAND="$_tmp"
  else
    echo "wheel block-state-write: FR-C1 command extraction failed (jq + node relaxed parser both rejected hook input)" >&2
  fi
else
  echo "wheel block-state-write: FR-C1 command extraction failed (jq rejected input, node unavailable)" >&2
fi

# Check Bash commands that write/delete state files
if [[ "$TOOL_NAME" == "Bash" ]]; then
  if echo "$COMMAND" | grep -qE '\.wheel/state_.*\.json' 2>/dev/null; then
    # Allow read-only commands (cat, jq read, ls, head, tail, wc)
    # Block writes (>, >>, rm, mv, cp, tee, jq with redirect)
    if echo "$COMMAND" | grep -qE '(>\s*\.wheel/state_|>\s*"\./\.wheel/state_|rm\s.*\.wheel/state_|mv\s.*\.wheel/state_|cp\s.*\.wheel/state_|tee\s.*\.wheel/state_)' 2>/dev/null; then
      cat >&2 <<'BLOCK'
BLOCKED: Direct modification of .wheel/state_*.json via shell is not allowed.

State files are managed exclusively by the wheel hook system.
To advance the workflow, let the PostToolUse hooks handle state
progression automatically after you complete the current step's work.

How workflow state advances:
  - command steps: hooks run the command and advance the cursor
  - agent steps: complete the agent's work, hooks detect completion and advance
  - workflow steps: hooks dispatch the sub-workflow inline and advance on completion

If you need to stop a workflow: /wheel:wheel-stop
If you need to check status: /wheel:wheel-status
BLOCK
      exit 2
    fi
  fi
  exit 0
fi

# Only check Edit and Write tools
if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

# Check if the target is a .wheel/state_ file
if echo "$FILE_PATH" | grep -qE '\.wheel/state_.*\.json' 2>/dev/null; then
  cat >&2 <<EOF
BLOCKED: Direct writes to .wheel/state_*.json are not allowed.

State files are managed exclusively by the wheel hook system.
To advance the workflow, let the PostToolUse hooks handle state
progression automatically after you complete the current step's work.

How workflow state advances:
  - command steps: hooks run the command and advance the cursor
  - agent steps: complete the agent's work, hooks detect completion and advance
  - workflow steps: hooks dispatch the sub-workflow inline and advance on completion

If you need to stop a workflow: /wheel:wheel-stop
If you need to check status: /wheel:wheel-status
EOF
  exit 2
fi

exit 0
