#!/bin/bash
# FR-005: Block git commit when .env files are staged.
# Must never crash — always exit 0 unless actively blocking a commit with staged .env files.

INPUT=$(cat 2>/dev/null || true)

# If no input or jq not available, allow
if [[ -z "$INPUT" ]] || ! command -v jq &>/dev/null; then
  exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

# Only check Bash tool
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

# Only check git commit commands
if ! echo "$COMMAND" | grep -q "git commit" 2>/dev/null; then
  exit 0
fi

# Check if .env files are staged. The repo-root .gitignore allows
# `.env.example` through (it's the canonical schema-template
# convention used by Node/Python/Ruby ecosystems and by this repo's
# own plugin-wheel/.env.example). Mirror that exception here so the
# hook agrees with gitignore — otherwise legitimate template commits
# get blocked while the corresponding `.env.test` file with secrets
# can never be staged in the first place (gitignored).
STAGED_ENV=$(git diff --cached --name-only 2>/dev/null \
  | grep -E '\.env(\..*)?$' \
  | grep -vE '(^|/)\.env\.example$' || true)
if [[ -n "$STAGED_ENV" ]]; then
  cat >&2 <<EOF
BLOCKED: .env file(s) are staged for commit:

$STAGED_ENV

Unstage with: git reset HEAD <file>
Never commit secrets to the repository.
EOF
  exit 2
fi

exit 0
