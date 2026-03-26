#!/bin/bash
# FR-003, FR-004: Block Edit/Write on src/ files when no spec exists in specs/
# Allows edits to docs, specs, config, scripts, and non-src files always.

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Only check Edit and Write tools
if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

# If no file path, allow (e.g. creating new files via Write)
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# FR-004: Always allow edits to non-src files
# Allow: docs/, specs/, scripts/, .claude/, .specify/, config files, tests/, package.json, etc.
case "$FILE_PATH" in
  */docs/*|*/specs/*|*/scripts/*|*/.claude/*|*/.specify/*|*/tests/*|\
  *CLAUDE.md|*README.md|*.json|*.yml|*.yaml|*.toml|*.md|*.gitignore|\
  */.env*|*/node_modules/*)
    exit 0
    ;;
esac

# FR-003: Check if any spec exists in specs/
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
if ls "$PROJECT_DIR"/specs/*/spec.md >/dev/null 2>&1; then
  exit 0  # Spec found, allow edit
fi

# No spec found — block the edit
cat >&2 <<EOF
BLOCKED: No spec found in specs/.

Before writing code, you must:
1. Create a feature spec: specs/<feature-name>/spec.md
2. Include user stories, FRs, and success criteria
3. Commit the spec to git

Run /speckit.specify to create one, or manually create specs/<name>/spec.md.
EOF
exit 2
