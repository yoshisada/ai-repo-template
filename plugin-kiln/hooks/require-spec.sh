#!/bin/bash
# Block Edit/Write on implementation files unless the full kiln workflow is complete:
# Gate 1: spec.md exists for current feature
# Gate 2: plan.md exists for current feature
# Gate 3: tasks.md exists for current feature
# Gate 3.5: contracts/interfaces.md exists for current feature
# Gate 4: tasks.md has at least one [X] mark OR implementing.lock is active
# Allows edits to docs, specs, config, scripts, tests, and non-implementation files always.
# FR-001: Feature-scoped gate checks (not glob-based)
# FR-002: Implementing lock bypass for Gate 4
# FR-003: Blocklist approach for implementation directories
# FR-004: Contracts gate enforcement

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

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"

# --- FR-001: Derive current feature name from git branch or fallback ---
get_current_feature() {
  local branch
  branch=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  # Pattern 1: build/<name>-<date> (e.g., build/pipeline-reliability-20260401)
  if [[ "$branch" =~ ^build/(.+)-[0-9]{8}$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi

  # Pattern 2: <number>-<name> (e.g., 42-my-feature)
  if [[ "$branch" =~ ^[0-9]+-(.+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi

  # Fallback: .kiln/current-feature marker file
  if [[ -f "$PROJECT_DIR/.kiln/current-feature" ]]; then
    cat "$PROJECT_DIR/.kiln/current-feature"
    return
  fi

  # All fail: empty string triggers glob fallback
  echo ""
}

# --- FR-003: Check if path is in an implementation directory ---
is_implementation_path() {
  local filepath="$1"

  # Always-allowed paths — exit 1 (not an implementation path)
  case "$filepath" in
    */docs/*|*/specs/*|*/scripts/*|*/.claude/*|*/.specify/*|*/tests/*|\
    */plugin/*|*/node_modules/*)
      return 1
      ;;
  esac

  # Always-allowed config files by extension
  case "$filepath" in
    *CLAUDE.md|*README.md|*.yml|*.yaml|*.toml|*.gitignore|*/.env*|*.json|*.md)
      return 1
      ;;
  esac

  # Implementation directories that require gate checks
  case "$filepath" in
    */src/*|*/cli/*|*/lib/*|*/modules/*|*/app/*|*/components/*|*/templates/*)
      return 0
      ;;
  esac

  # Anything not matching an implementation directory is allowed
  return 1
}

# --- FR-002: Check if /implement is currently active via lock file ---
check_implementing_lock() {
  local lock_file="$PROJECT_DIR/.kiln/implementing.lock"

  if [[ ! -f "$lock_file" ]]; then
    return 1
  fi

  # Parse timestamp from JSON lock file
  local lock_timestamp
  lock_timestamp=$(jq -r '.timestamp // empty' "$lock_file" 2>/dev/null)

  if [[ -z "$lock_timestamp" ]]; then
    return 1
  fi

  # Check if lock is less than 30 minutes old
  local lock_epoch now_epoch age_minutes
  lock_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${lock_timestamp%%.*}" "+%s" 2>/dev/null || \
               date -d "${lock_timestamp}" "+%s" 2>/dev/null || echo "0")
  now_epoch=$(date "+%s")

  if [[ "$lock_epoch" == "0" ]]; then
    return 1
  fi

  age_minutes=$(( (now_epoch - lock_epoch) / 60 ))

  if [[ "$age_minutes" -lt 30 ]]; then
    return 0
  fi

  # Lock is stale (>= 30 minutes old)
  return 1
}

# Check if this is an implementation path that needs gate enforcement
if ! is_implementation_path "$FILE_PATH"; then
  exit 0
fi

# Derive current feature
CURRENT_FEATURE=$(get_current_feature)
MISSING=""

if [[ -n "$CURRENT_FEATURE" ]]; then
  # Feature-scoped checks (FR-001)
  SPEC_DIR="$PROJECT_DIR/specs/$CURRENT_FEATURE"

  # Gate 1: spec.md exists
  if [[ ! -f "$SPEC_DIR/spec.md" ]]; then
    MISSING="$MISSING\n  - spec.md (run /specify)"
  fi

  # Gate 2: plan.md exists
  if [[ ! -f "$SPEC_DIR/plan.md" ]]; then
    MISSING="$MISSING\n  - plan.md (run /plan)"
  fi

  # Gate 3: tasks.md exists
  if [[ ! -f "$SPEC_DIR/tasks.md" ]]; then
    MISSING="$MISSING\n  - tasks.md (run /tasks)"
  fi

  # Gate 3.5: contracts/interfaces.md exists (FR-004)
  if [[ ! -f "$SPEC_DIR/contracts/interfaces.md" ]]; then
    MISSING="$MISSING\n  - contracts/interfaces.md (run /plan to generate contracts)"
  fi

  # Gate 4: tasks.md has [X] mark OR implementing lock is active (FR-002)
  if [[ -f "$SPEC_DIR/tasks.md" ]]; then
    if ! grep -q '\[[xX]\]' "$SPEC_DIR/tasks.md" 2>/dev/null; then
      if ! check_implementing_lock; then
        MISSING="$MISSING\n  - No tasks marked complete (run /implement, or /implement is not active)"
      fi
    fi
  fi
else
  # Glob fallback for backwards compatibility (no feature detected)
  # Gate 1: spec.md exists
  if ! ls "$PROJECT_DIR"/specs/*/spec.md >/dev/null 2>&1; then
    MISSING="$MISSING\n  - spec.md (run /specify)"
  fi

  # Gate 2: plan.md exists
  if ! ls "$PROJECT_DIR"/specs/*/plan.md >/dev/null 2>&1; then
    MISSING="$MISSING\n  - plan.md (run /plan)"
  fi

  # Gate 3: tasks.md exists
  if ! ls "$PROJECT_DIR"/specs/*/tasks.md >/dev/null 2>&1; then
    MISSING="$MISSING\n  - tasks.md (run /tasks)"
  fi

  # Gate 3.5: contracts/interfaces.md exists (FR-004)
  if ! ls "$PROJECT_DIR"/specs/*/contracts/interfaces.md >/dev/null 2>&1; then
    MISSING="$MISSING\n  - contracts/interfaces.md (run /plan to generate contracts)"
  fi

  # Gate 4: tasks.md has at least one checked task [X]
  if ls "$PROJECT_DIR"/specs/*/tasks.md >/dev/null 2>&1; then
    TASKS_FILE=$(ls "$PROJECT_DIR"/specs/*/tasks.md 2>/dev/null | head -1)
    if ! grep -q '\[[xX]\]' "$TASKS_FILE" 2>/dev/null; then
      if ! check_implementing_lock; then
        MISSING="$MISSING\n  - No tasks marked complete (run /implement, or /implement is not active)"
      fi
    fi
  fi
fi

# If nothing missing, allow
if [[ -z "$MISSING" ]]; then
  exit 0
fi

# Block with specific guidance
cat >&2 <<EOF
BLOCKED: Kiln workflow incomplete for feature "${CURRENT_FEATURE:-unknown}". Missing:
$(echo -e "$MISSING")

Required workflow before editing implementation files:
1. /specify   → creates spec.md
2. /plan      → creates plan.md + contracts/interfaces.md
3. /tasks     → creates tasks.md
4. /implement → executes tasks, marks [X], runs PRD audit
EOF
exit 2
