#!/bin/bash
# PreToolUse(Bash) — merge bar gate.
# Fires when `gh pr create` is called. Enforces the senior-engineer merge bar:
# 1. Audit compliance >= 80% (.wheel/outputs/audit-verdict.json)
# 2. All tasks [X] in specs/*/tasks.md (no remaining [ ])
# 3. No severity:blocking entries in specs/*/blockers.md
# Fail open if files are absent (manual / pre-spec runs are allowed through).
# FR-MERGE-BAR-001

INPUT=$(cat 2>/dev/null || true)

# If no input or jq unavailable, allow
if [[ -z "$INPUT" ]] || ! command -v jq &>/dev/null; then
  exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

# Only act on Bash tool
if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

# Only act when command contains `gh pr create`
if ! echo "$COMMAND" | grep -q "gh pr create" 2>/dev/null; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
FAILURES=""

# --- Check 1: Audit compliance >= 80% ---
AUDIT_VERDICT="$PROJECT_DIR/.wheel/outputs/audit-verdict.json"
if [[ -f "$AUDIT_VERDICT" ]]; then
  COMPLIANCE=$(jq -r '.compliance_pct // empty' "$AUDIT_VERDICT" 2>/dev/null || true)
  if [[ -n "$COMPLIANCE" ]] && echo "$COMPLIANCE" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
    THRESHOLD=80
    BELOW=0
    if command -v bc &>/dev/null; then
      if (( $(echo "$COMPLIANCE < $THRESHOLD" | bc -l) )); then
        BELOW=1
      fi
    else
      # Integer fallback
      COV_INT=${COMPLIANCE%.*}
      if (( COV_INT < THRESHOLD )); then
        BELOW=1
      fi
    fi
    if [[ "$BELOW" == "1" ]]; then
      FAILURES="${FAILURES}\n  - Audit compliance ${COMPLIANCE}% < 80% required (see .wheel/outputs/audit-verdict.json)"
    fi
  fi
  # If compliance_pct absent → fail open for this check
fi
# If audit-verdict.json absent → fail open (may be a manual/pre-audit PR)

# --- Check 2: All tasks marked [X] in specs/*/tasks.md ---
TASKS_FILES=$(ls "$PROJECT_DIR"/specs/*/tasks.md 2>/dev/null || true)
if [[ -n "$TASKS_FILES" ]]; then
  while IFS= read -r TASKS_FILE; do
    [[ -f "$TASKS_FILE" ]] || continue
    # Look for unchecked tasks: [ ] (space inside brackets)
    UNCHECKED=$(grep -cE '^\s*[-*]\s+\[ \]' "$TASKS_FILE" 2>/dev/null || true)
    if [[ -n "$UNCHECKED" && "$UNCHECKED" -gt 0 ]]; then
      FEATURE_DIR=$(dirname "$TASKS_FILE")
      FEATURE=$(basename "$FEATURE_DIR")
      FAILURES="${FAILURES}\n  - ${UNCHECKED} unchecked task(s) remaining in specs/${FEATURE}/tasks.md"
    fi
  done <<< "$TASKS_FILES"
fi
# If no tasks.md files found → fail open

# --- Check 3: No severity:blocking entries in specs/*/blockers.md ---
BLOCKER_FILES=$(ls "$PROJECT_DIR"/specs/*/blockers.md 2>/dev/null || true)
if [[ -n "$BLOCKER_FILES" ]]; then
  while IFS= read -r BLOCKER_FILE; do
    [[ -f "$BLOCKER_FILE" ]] || continue
    # Match lines containing "severity: blocking" (case-insensitive)
    BLOCKING_COUNT=$(grep -ciE 'severity:\s*blocking' "$BLOCKER_FILE" 2>/dev/null || true)
    if [[ -n "$BLOCKING_COUNT" && "$BLOCKING_COUNT" -gt 0 ]]; then
      FEATURE_DIR=$(dirname "$BLOCKER_FILE")
      FEATURE=$(basename "$FEATURE_DIR")
      FAILURES="${FAILURES}\n  - ${BLOCKING_COUNT} blocking blocker(s) in specs/${FEATURE}/blockers.md — resolve or downgrade severity"
    fi
  done <<< "$BLOCKER_FILES"
fi
# If no blockers.md files found → fail open

# If nothing failed, allow
if [[ -z "$FAILURES" ]]; then
  exit 0
fi

cat >&2 <<EOF
BLOCKED: Merge bar not met — PR creation denied.

Failing checks:
$(echo -e "$FAILURES")

All checks must pass before opening a PR:
  1. Audit compliance >= 80%  (.wheel/outputs/audit-verdict.json)
  2. All tasks marked [X]     (specs/<feature>/tasks.md)
  3. No blocking blockers     (specs/<feature>/blockers.md)

Run /kiln:kiln-build-prd or address the issues above, then retry.
EOF
exit 2
