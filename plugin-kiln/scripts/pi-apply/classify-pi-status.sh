#!/usr/bin/env bash
# FR-012: Classify a PI block as already-applied, stale, or actionable.
# Contract: specs/workflow-governance/contracts/interfaces.md Module 3 §classify-pi-status.sh
#
# Classification rules:
#   target file absent                          → stale
#   target file present, anchor not found       → stale
#   anchor found, proposed text present verbatim → already-applied
#   anchor found, proposed text not present     → actionable
#
# The "anchored section" extends from the anchor line down to the next same-or-higher-level
# markdown heading (or EOF). Proposed text must appear verbatim inside that window.

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: classify-pi-status.sh --target-file <path> --target-anchor <anchor> --proposed <text>
USAGE
  exit 2
}

TARGET_FILE=""
TARGET_ANCHOR=""
PROPOSED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-file)   TARGET_FILE="${2:-}"; shift 2 ;;
    --target-anchor) TARGET_ANCHOR="${2:-}"; shift 2 ;;
    --proposed)      PROPOSED="${2:-}"; shift 2 ;;
    -h|--help)       usage ;;
    *)               echo "classify-pi-status.sh: unknown flag: $1" >&2; usage ;;
  esac
done

[[ -z "$TARGET_FILE" || -z "$TARGET_ANCHOR" ]] && usage

# Rule 1 — target file absent.
if [[ ! -f "$TARGET_FILE" ]]; then
  printf 'stale\n'
  exit 0
fi

# Extract the anchor line number. Use grep -F for literal match (anchors may contain
# regex-special chars like "## R-1 [special]").
ANCHOR_LINE=$(grep -nF -- "$TARGET_ANCHOR" "$TARGET_FILE" 2>/dev/null | head -1 | cut -d: -f1 || true)

# Rule 2 — anchor not found.
if [[ -z "$ANCHOR_LINE" ]]; then
  printf 'stale\n'
  exit 0
fi

# Determine the anchor's heading depth (count leading '#'). Non-heading anchors
# (e.g. "## R-1" literal inside body) treat the whole rest-of-file as the section.
ANCHOR_TEXT=$(sed -n "${ANCHOR_LINE}p" "$TARGET_FILE")
LEADING_HASHES=$(printf '%s' "$ANCHOR_TEXT" | awk '{match($0, /^#+/); print RLENGTH}')
if [[ -z "$LEADING_HASHES" || "$LEADING_HASHES" == "-1" || "$LEADING_HASHES" == "0" ]]; then
  # Anchor isn't a markdown heading — treat the whole rest-of-file as the window.
  SECTION_END=$(wc -l < "$TARGET_FILE" | tr -d ' ')
else
  # Find the next line that is a heading of the same or higher level.
  SECTION_END=""
  TOTAL_LINES=$(wc -l < "$TARGET_FILE" | tr -d ' ')
  if [[ $((ANCHOR_LINE + 1)) -le "$TOTAL_LINES" ]]; then
    # Build a regex for 1..LEADING_HASHES leading hashes followed by a space.
    # awk over the tail slice and emit the first match offset.
    REGEX="^#{1,${LEADING_HASHES}} "
    NEXT=$(awk -v start=$((ANCHOR_LINE + 1)) -v rx="$REGEX" 'NR >= start && $0 ~ rx { print NR; exit }' "$TARGET_FILE" || true)
    if [[ -n "$NEXT" ]]; then
      SECTION_END=$((NEXT - 1))
    fi
  fi
  [[ -z "$SECTION_END" ]] && SECTION_END="$TOTAL_LINES"
fi

# Extract the anchored window into a temp file so we can do a verbatim multi-line
# substring check without shell/awk mangling newlines.
WINDOW_TMP=$(mktemp)
PATTERN_TMP=$(mktemp)
trap 'rm -f "$WINDOW_TMP" "$PATTERN_TMP"' EXIT

sed -n "${ANCHOR_LINE},${SECTION_END}p" "$TARGET_FILE" > "$WINDOW_TMP"
printf '%s' "$PROPOSED" > "$PATTERN_TMP"

# Rule 3 — proposed text already present verbatim in the anchored window.
# Empty PROPOSED means "no proposed change" — treat as actionable (no-op handled
# upstream). Otherwise substring-match window against PROPOSED bytes. Python
# handles multi-line strings cleanly where awk/grep are unreliable.
if [[ -s "$PATTERN_TMP" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    if python3 -c "
import sys
with open(sys.argv[1], 'rb') as f: w = f.read()
with open(sys.argv[2], 'rb') as f: p = f.read()
sys.exit(0 if p in w else 1)
" "$WINDOW_TMP" "$PATTERN_TMP"; then
      printf 'already-applied\n'
      exit 0
    fi
  elif command -v perl >/dev/null 2>&1; then
    if perl -e '
      local $/;
      open my $wf, "<", $ARGV[0] or die; my $w = <$wf>; close $wf;
      open my $pf, "<", $ARGV[1] or die; my $p = <$pf>; close $pf;
      exit (index($w, $p) >= 0 ? 0 : 1);
    ' "$WINDOW_TMP" "$PATTERN_TMP"; then
      printf 'already-applied\n'
      exit 0
    fi
  else
    echo "classify-pi-status.sh: neither python3 nor perl available for verbatim match" >&2
    exit 2
  fi
fi

printf 'actionable\n'
