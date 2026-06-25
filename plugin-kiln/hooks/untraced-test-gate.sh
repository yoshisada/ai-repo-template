#!/bin/bash
# PreToolUse(Edit|Write) — untraced test gate.
# When a test file is being written, verifies it contains an FR/AC traceability
# reference (FR-, AC:, or // FR). Blocks if no reference found.
# Non-test files → always allow. Fail open on hook errors.
# FR-UNTRACED-TEST-GATE-001

INPUT=$(cat 2>/dev/null || true)

# If no input or jq unavailable, allow
if [[ -z "$INPUT" ]] || ! command -v jq &>/dev/null; then
  exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)

# Only act on Edit and Write tools
if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)

# If no file path, allow
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Check if the target is a test file
# Patterns: *.test.*, *_test.*, *.spec.*, or under a tests/ directory
is_test_file() {
  local fp="$1"
  case "$fp" in
    *.test.*|*_test.*|*.spec.*|*/tests/*|*/test/*)
      return 0
      ;;
  esac
  return 1
}

if ! is_test_file "$FILE_PATH"; then
  exit 0
fi

# Extract the content being written/edited
# Write tool: tool_input.content
# Edit tool: tool_input.new_string
CONTENT=""
if [[ "$TOOL_NAME" == "Write" ]]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null || true)
elif [[ "$TOOL_NAME" == "Edit" ]]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null || true)
fi

# If content can't be extracted, fail open
if [[ -z "$CONTENT" ]]; then
  exit 0
fi

# Check for FR/AC traceability reference:
# Accepts: "FR-", "// FR", "AC:", "FR-NNN", "#FR-", "AC-", or "Acceptance Criteria"
if echo "$CONTENT" | grep -qE '(FR-[A-Z0-9]|//\s*FR|AC:|AC-[A-Z0-9]|Acceptance Criteria)' 2>/dev/null; then
  exit 0
fi

# No traceability reference found — block
FILENAME=$(basename "$FILE_PATH")
cat >&2 <<EOF
BLOCKED: Test file lacks FR/AC traceability — ${FILENAME}

Every test file must include at least one traceability reference to a
functional requirement or acceptance criterion. Add one of:

  // FR-NNN: <description>          (inline comment)
  // AC: <acceptance-criterion>     (acceptance criterion reference)
  # FR-NNN                          (Python/shell style)

See the spec at specs/<feature>/spec.md for FR numbers.
Without traceability the PRD audit cannot confirm coverage.
EOF
exit 2
