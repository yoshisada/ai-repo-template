#!/bin/bash
# Block Edit/Write on src/ files unless the full speckit workflow is complete:
# Gate 1: spec.md exists
# Gate 2: plan.md exists
# Gate 3: tasks.md exists
# Gate 4: tasks.md has at least one [X] mark (proves /speckit.implement ran)
# Allows edits to docs, specs, config, scripts, tests, and non-src files always.

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only check Edit and Write tools
if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

# If no file path, allow
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Always allow edits to non-src files
case "$FILE_PATH" in
  */docs/*|*/specs/*|*/scripts/*|*/.claude/*|*/.specify/*|*/tests/*|\
  *CLAUDE.md|*README.md|*.yml|*.yaml|*.toml|*.gitignore|\
  */.env*|*/node_modules/*)
    exit 0
    ;;
esac

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
MISSING=""

# Gate 1: spec.md exists
if ! ls "$PROJECT_DIR"/specs/*/spec.md >/dev/null 2>&1; then
  MISSING="$MISSING\n  - spec.md (run /speckit.specify)"
fi

# Gate 2: plan.md exists
if ! ls "$PROJECT_DIR"/specs/*/plan.md >/dev/null 2>&1; then
  MISSING="$MISSING\n  - plan.md (run /speckit.plan)"
fi

# Gate 3: tasks.md exists
if ! ls "$PROJECT_DIR"/specs/*/tasks.md >/dev/null 2>&1; then
  MISSING="$MISSING\n  - tasks.md (run /speckit.tasks)"
fi

# Gate 4: tasks.md has at least one checked task [X] (proves /speckit.implement ran)
if ls "$PROJECT_DIR"/specs/*/tasks.md >/dev/null 2>&1; then
  TASKS_FILE=$(ls "$PROJECT_DIR"/specs/*/tasks.md 2>/dev/null | head -1)
  if ! grep -q '\[[xX]\]' "$TASKS_FILE" 2>/dev/null; then
    MISSING="$MISSING\n  - No tasks marked complete (run /speckit.implement)"
  fi
fi

# If nothing missing, allow
if [[ -z "$MISSING" ]]; then
  exit 0
fi

# Block with specific guidance
cat >&2 <<EOF
BLOCKED: Speckit workflow incomplete. Missing:
$(echo -e "$MISSING")

Required workflow before editing source files:
1. /speckit.specify   → creates spec.md
2. /speckit.plan      → creates plan.md
3. /speckit.tasks     → creates tasks.md
4. /speckit.implement → executes tasks, marks [X], runs PRD audit
EOF
exit 2
