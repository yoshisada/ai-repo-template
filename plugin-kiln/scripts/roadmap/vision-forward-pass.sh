#!/usr/bin/env bash
# vision-forward-pass.sh — generate ≤5 forward-looking suggestions.
#
# FR-010 / FR-011 / vision-tooling FR-010/FR-011: at the END of every coached
# /kiln:kiln-roadmap --vision interview, on opt-in `y`, this helper generates
# ≤5 suggestions tagged gap | opportunity | adjacency | non-goal-revisit. Each
# suggestion cites concrete evidence (file path, item path, phase path,
# CLAUDE.md path, or commit hash).
#
# Mock-injection (CLAUDE.md Rule 5): if KILN_TEST_MOCK_LLM_DIR is set, the
# script reads ${KILN_TEST_MOCK_LLM_DIR}/forward-pass.txt verbatim instead of
# calling claude --print.
#
# Contract: specs/vision-tooling/contracts/interfaces.md §"Theme C —
#           vision-forward-pass.sh"
#
# Usage:
#   vision-forward-pass.sh [--declined-set <path>]
#
# Stdout: zero to five suggestion blocks, separated by a single blank line.
#         Each block is exactly four lines:
#             title: <one-line title, no tabs>
#             tag: <gap|opportunity|adjacency|non-goal-revisit>
#             evidence: <file-path-or-commit-hash>:<optional-anchor>
#             body: <one-line body summary, ≤200 chars>
#
# Exit:   0 suggestions emitted (may be empty after dedup).
#         1 usage error.
#         4 LLM call failed; caller skips the forward pass.
set -u
LC_ALL=C
export LC_ALL

DECLINED_SET=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --declined-set) DECLINED_SET="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,32p' "$0"
      exit 0
      ;;
    *) echo "vision-forward-pass: unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ---- Source the raw suggestion blob (mock or live) ----
RAW=""
if [ -n "${KILN_TEST_MOCK_LLM_DIR:-}" ]; then
  fixture="${KILN_TEST_MOCK_LLM_DIR}/forward-pass.txt"
  if [ ! -f "$fixture" ]; then
    # Mock dir set but no fixture → no suggestions, exit 0.
    exit 0
  fi
  RAW=$(cat "$fixture")
else
  if ! command -v claude >/dev/null 2>&1; then
    echo "vision-forward-pass: claude CLI not available — set KILN_TEST_MOCK_LLM_DIR for tests" >&2
    exit 4
  fi

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CTX_READER="$SCRIPT_DIR/../context/read-project-context.sh"
  CTX_JSON=""
  if [ -f "$CTX_READER" ]; then
    CTX_JSON=$(bash "$CTX_READER" 2>/dev/null) || CTX_JSON=""
  fi

  PROMPT=$(cat <<EOF
You are proposing forward-looking roadmap suggestions for a project. Emit AT
MOST 5 suggestion blocks. Each block is EXACTLY four lines, in this order, no
extra prose, no headers, no numbering:

title: <one-line title, no tabs>
tag: <gap|opportunity|adjacency|non-goal-revisit>
evidence: <file-path-or-commit-hash>:<optional-anchor>
body: <one-line body summary, ≤200 chars>

Separate blocks with EXACTLY one blank line. Tag MUST be one of: gap,
opportunity, adjacency, non-goal-revisit. Evidence MUST cite a concrete
artifact in the repo.

PROJECT CONTEXT:
$CTX_JSON
EOF
)

  RAW=$(printf '%s' "$PROMPT" | claude --print 2>/dev/null) || {
    exit 4
  }
fi

# ---- Parse blocks (4-line; blank-line separator) ----
# Then enforce dedup against --declined-set (matched on `<title>\t<tag>`).
# Then enforce ≤5 cap.
TMP_BLOCKS=$(mktemp); trap 'rm -f "$TMP_BLOCKS"' EXIT

awk '
  BEGIN { lines = 0; sep_pending = 0 }
  /^[[:space:]]*$/ {
    if (lines == 4) {
      printf "%s\n", buf
      lines = 0
      buf = ""
    }
    next
  }
  {
    if (lines == 0) buf = $0
    else            buf = buf "\x1e" $0   # RS-like joiner; we re-split below
    lines++
    if (lines == 4) {
      printf "%s\n", buf
      lines = 0
      buf = ""
    }
  }
  END {
    if (lines == 4) printf "%s\n", buf
  }
' <<<"$RAW" > "$TMP_BLOCKS"

# Build dedup index: <title>\t<tag> → 1
TMP_DEDUP=$(mktemp); trap 'rm -f "$TMP_BLOCKS" "$TMP_DEDUP"' EXIT
if [ -n "$DECLINED_SET" ] && [ -f "$DECLINED_SET" ]; then
  cp "$DECLINED_SET" "$TMP_DEDUP"
fi

emitted=0
first_block=1
while IFS= read -r joined; do
  [ -z "$joined" ] && continue
  [ "$emitted" -ge 5 ] && break
  # Re-split the four fields on the joiner.
  IFS=$'\x1e' read -r l1 l2 l3 l4 <<<"$joined"
  # Validate field prefixes.
  case "$l1" in title:*) ;; *) continue ;; esac
  case "$l2" in tag:*)   ;; *) continue ;; esac
  case "$l3" in evidence:*) ;; *) continue ;; esac
  case "$l4" in body:*)  ;; *) continue ;; esac
  # Validate tag membership.
  tag_val=$(printf '%s' "$l2" | sed -E 's/^tag:[[:space:]]*//')
  case "$tag_val" in
    gap|opportunity|adjacency|non-goal-revisit) ;;
    *) continue ;;
  esac
  # Validate evidence non-empty.
  ev_val=$(printf '%s' "$l3" | sed -E 's/^evidence:[[:space:]]*//')
  [ -z "$ev_val" ] && continue
  title_val=$(printf '%s' "$l1" | sed -E 's/^title:[[:space:]]*//')
  [ -z "$title_val" ] && continue
  # Dedup against declined-set.
  if [ -s "$TMP_DEDUP" ]; then
    if grep -F -x -q "${title_val}	${tag_val}" "$TMP_DEDUP" 2>/dev/null; then
      continue
    fi
  fi
  # Emit block (with leading blank-line separator after the first).
  if [ "$first_block" -eq 1 ]; then
    first_block=0
  else
    printf '\n'
  fi
  printf '%s\n%s\n%s\n%s\n' "$l1" "$l2" "$l3" "$l4"
  emitted=$((emitted + 1))
done < "$TMP_BLOCKS"

exit 0
