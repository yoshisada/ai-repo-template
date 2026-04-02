#!/bin/bash
# Non-compiled feature validation gate (FR-001)
# Validates frontmatter structure, bash syntax, file path references, and scaffold output
# for plugin repos where there is no src/ directory to run coverage against.
#
# Usage:
#   bash scripts/validate-non-compiled.sh [--files <file1> <file2> ...] [--all]
#   (no args) — detect modified files via git diff --name-only HEAD~1

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$PROJECT_DIR"

# --- Argument parsing ---
MODE="auto"
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --files)
      MODE="files"
      shift
      while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
        FILES+=("$1")
        shift
      done
      ;;
    --all)
      MODE="all"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# --- File collection ---
if [[ "$MODE" == "all" ]]; then
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(find plugin/ -type f \( -name "*.md" -o -name "*.sh" \) 2>/dev/null)
elif [[ "$MODE" == "auto" ]]; then
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(git diff --name-only HEAD~1 2>/dev/null || git diff --name-only HEAD 2>/dev/null || true)
fi

# --- Counters ---
FM_TESTED=0; FM_PASS=0; FM_FAIL=0; FM_DETAILS=()
BASH_TESTED=0; BASH_PASS=0; BASH_FAIL=0; BASH_DETAILS=()
REF_TESTED=0; REF_PASS=0; REF_FAIL=0; REF_DETAILS=()
SCAFFOLD_TESTED=0; SCAFFOLD_PASS=0; SCAFFOLD_FAIL=0; SCAFFOLD_DETAIL=""

# --- Check 1: Frontmatter structure in SKILL.md files ---
for f in "${FILES[@]}"; do
  [[ "$f" == */SKILL.md ]] || continue
  [[ -f "$f" ]] || continue
  FM_TESTED=$((FM_TESTED + 1))

  # Check for --- delimiters and basic YAML structure
  FIRST_LINE=$(head -1 "$f")
  if [[ "$FIRST_LINE" != "---" ]]; then
    FM_FAIL=$((FM_FAIL + 1))
    FM_DETAILS+=("$f: missing opening --- delimiter")
    continue
  fi

  # Find closing ---
  CLOSING_LINE=$(awk 'NR>1 && /^---$/{print NR; exit}' "$f")
  if [[ -z "$CLOSING_LINE" ]]; then
    FM_FAIL=$((FM_FAIL + 1))
    FM_DETAILS+=("$f: missing closing --- delimiter")
    continue
  fi

  # Check for name: field in frontmatter
  FRONTMATTER=$(sed -n "2,$((CLOSING_LINE - 1))p" "$f")
  if ! echo "$FRONTMATTER" | grep -q "^name:"; then
    FM_FAIL=$((FM_FAIL + 1))
    FM_DETAILS+=("$f: frontmatter missing 'name:' field")
    continue
  fi

  # Check for description: field in frontmatter
  if ! echo "$FRONTMATTER" | grep -q "^description:"; then
    FM_FAIL=$((FM_FAIL + 1))
    FM_DETAILS+=("$f: frontmatter missing 'description:' field")
    continue
  fi

  FM_PASS=$((FM_PASS + 1))
done

# --- Check 2: Bash syntax in SKILL.md code blocks ---
for f in "${FILES[@]}"; do
  [[ "$f" == *.md ]] || continue
  [[ -f "$f" ]] || continue

  # Extract bash/sh code blocks
  TMPSCRIPT=$(mktemp /tmp/bash-check-XXXXXX.sh)
  trap 'rm -f "$TMPSCRIPT"' EXIT

  IN_BLOCK=false
  BLOCK_NUM=0
  while IFS= read -r line; do
    if [[ "$IN_BLOCK" == true ]]; then
      if [[ "$line" =~ ^\`\`\` ]]; then
        IN_BLOCK=false
        BASH_TESTED=$((BASH_TESTED + 1))
        BLOCK_NUM=$((BLOCK_NUM + 1))
        if ! bash -n "$TMPSCRIPT" 2>/dev/null; then
          BASH_FAIL=$((BASH_FAIL + 1))
          BASH_DETAILS+=("$f: block #$BLOCK_NUM failed bash -n")
        else
          BASH_PASS=$((BASH_PASS + 1))
        fi
        : > "$TMPSCRIPT"
      else
        echo "$line" >> "$TMPSCRIPT"
      fi
    elif [[ "$line" =~ ^\`\`\`(bash|sh)$ ]]; then
      IN_BLOCK=true
      : > "$TMPSCRIPT"
    fi
  done < "$f"

  rm -f "$TMPSCRIPT"
done

# --- Check 3: File path references ---
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  # Look for path-like references: plugin/..., scripts/..., .kiln/..., .specify/...
  while IFS= read -r ref; do
    # Skip URLs, markdown links to anchors, template variables
    [[ "$ref" =~ ^https?:// ]] && continue
    [[ "$ref" =~ ^\$ ]] && continue
    [[ "$ref" =~ \{.*\} ]] && continue
    # Skip wildcard/glob patterns
    [[ "$ref" =~ \* ]] && continue
    # Skip paths that are clearly examples or placeholders
    [[ "$ref" =~ specs/\<feature ]] && continue
    [[ "$ref" =~ \<feature ]] && continue
    [[ "$ref" =~ nonexistent ]] && continue

    REF_TESTED=$((REF_TESTED + 1))
    if [[ -e "$ref" ]]; then
      REF_PASS=$((REF_PASS + 1))
    else
      REF_FAIL=$((REF_FAIL + 1))
      REF_DETAILS+=("$f -> $ref (not found)")
    fi
  done < <(grep -oE '(plugin|scripts|\.kiln|\.specify|\.claude)/[a-zA-Z0-9_./-]+' "$f" 2>/dev/null | sort -u)
done

# --- Check 4: Scaffold output verification ---
if [[ -f "plugin/bin/init.mjs" ]]; then
  SCAFFOLD_TESTED=1
  TMPDIR=$(mktemp -d /tmp/scaffold-test-XXXXXX)
  trap 'rm -rf "$TMPDIR"' EXIT

  # Initialize a minimal git repo and package.json in the temp dir
  (
    cd "$TMPDIR"
    git init -q
    echo '{"name":"test","version":"0.0.0"}' > package.json
    git add -A && git commit -q -m "init"
  ) 2>/dev/null

  if node "$PROJECT_DIR/plugin/bin/init.mjs" init "$TMPDIR" 2>/dev/null; then
    SCAFFOLD_PASS=1
    SCAFFOLD_DETAIL="pass"
  else
    SCAFFOLD_FAIL=1
    SCAFFOLD_DETAIL="fail"
  fi

  rm -rf "$TMPDIR"
else
  SCAFFOLD_DETAIL="skip (no init.mjs)"
fi

# --- Report ---
TOTAL_FAIL=$((FM_FAIL + BASH_FAIL + REF_FAIL + SCAFFOLD_FAIL))

echo ""
echo "## Non-Compiled Validation Report"
echo ""
echo "| Check | Files Tested | Pass | Fail | Details |"
echo "|-------|-------------|------|------|---------|"
echo "| Frontmatter | $FM_TESTED | $FM_PASS | $FM_FAIL | ${FM_DETAILS[*]:-none} |"
echo "| Bash syntax | $BASH_TESTED | $BASH_PASS | $BASH_FAIL | ${BASH_DETAILS[*]:-none} |"
echo "| File references | $REF_TESTED | $REF_PASS | $REF_FAIL | ${REF_DETAILS[*]:-none} |"
echo "| Scaffold output | $SCAFFOLD_TESTED | $SCAFFOLD_PASS | $SCAFFOLD_FAIL | $SCAFFOLD_DETAIL |"
echo ""

if [[ "$TOTAL_FAIL" -eq 0 ]]; then
  echo "Result: PASS"
  exit 0
else
  echo "Result: FAIL ($TOTAL_FAIL failures)"
  exit 1
fi
