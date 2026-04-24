#!/usr/bin/env bash
# Test: project-context-reader-determinism
#
# Validates: NFR-002 (byte-identical output on unchanged state),
#            FR-003 (deterministic JSON emission),
#            SC-006 (reader completes on fixture repo).
#
# Acceptance scenario this validates:
#   "Re-run reader twice on unchanged fixture → byte-identical stdout."
#
# Approach: invoke read-project-context.sh against the populated fixture
# TWICE, diff the two outputs. Also structurally sanity-check the JSON
# shape matches contracts/interfaces.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/fixture"
READER="$SCRIPT_DIR/../../scripts/context/read-project-context.sh"

if [[ ! -f "$READER" ]]; then
  echo "FAIL: reader script missing at $READER" >&2
  exit 1
fi

if [[ ! -d "$FIXTURE" ]]; then
  echo "FAIL: fixture missing at $FIXTURE" >&2
  exit 1
fi

OUT1="$(mktemp)"
OUT2="$(mktemp)"
trap 'rm -f "$OUT1" "$OUT2"' EXIT

bash "$READER" --repo-root "$FIXTURE" > "$OUT1"
bash "$READER" --repo-root "$FIXTURE" > "$OUT2"

if ! diff -q "$OUT1" "$OUT2" >/dev/null; then
  echo "FAIL: two invocations produced different output (NFR-002 broken)" >&2
  diff "$OUT1" "$OUT2" | head -40 >&2
  exit 1
fi

# Structural sanity — fields documented in contracts/interfaces.md.
for field in schema_version prds roadmap_items roadmap_phases vision claude_md readme plugins; do
  if ! jq -e "has(\"$field\")" "$OUT1" >/dev/null; then
    echo "FAIL: output missing required field '$field'" >&2
    exit 1
  fi
done

# schema_version must be "1".
SV="$(jq -r '.schema_version' "$OUT1")"
if [[ "$SV" != "1" ]]; then
  echo "FAIL: schema_version expected '1', got '$SV'" >&2
  exit 1
fi

# prds[] count and sort ASC by path.
PRDS_COUNT="$(jq '.prds | length' "$OUT1")"
if [[ "$PRDS_COUNT" -ne 3 ]]; then
  echo "FAIL: expected 3 PRDs, got $PRDS_COUNT" >&2
  exit 1
fi
PRDS_SORTED="$(jq -r '.prds | map(.path) | . == (. | sort)' "$OUT1")"
if [[ "$PRDS_SORTED" != "true" ]]; then
  echo "FAIL: prds[] not sorted ASC by path" >&2
  exit 1
fi

# roadmap_items[] count = 5, sorted ASC by path.
ITEMS_COUNT="$(jq '.roadmap_items | length' "$OUT1")"
if [[ "$ITEMS_COUNT" -ne 5 ]]; then
  echo "FAIL: expected 5 roadmap items, got $ITEMS_COUNT" >&2
  exit 1
fi
ITEMS_SORTED="$(jq -r '.roadmap_items | map(.path) | . == (. | sort)' "$OUT1")"
if [[ "$ITEMS_SORTED" != "true" ]]; then
  echo "FAIL: roadmap_items[] not sorted ASC by path" >&2
  exit 1
fi

# roadmap_phases[] — 2 phases, sorted by name.
PHASES_COUNT="$(jq '.roadmap_phases | length' "$OUT1")"
if [[ "$PHASES_COUNT" -ne 2 ]]; then
  echo "FAIL: expected 2 phases, got $PHASES_COUNT" >&2
  exit 1
fi

# At least one phase has status in-progress.
IN_PROGRESS="$(jq -r '.roadmap_phases | map(select(.status=="in-progress")) | length' "$OUT1")"
if [[ "$IN_PROGRESS" -ne 1 ]]; then
  echo "FAIL: expected 1 in-progress phase, got $IN_PROGRESS" >&2
  exit 1
fi

# vision, claude_md, readme should be objects (not null).
for field in vision claude_md readme; do
  KIND="$(jq -r ".${field} | type" "$OUT1")"
  if [[ "$KIND" != "object" ]]; then
    echo "FAIL: expected .$field to be object (fixture has the file); got $KIND" >&2
    exit 1
  fi
done

# plugins[] — 2 stubs, sorted by name.
PLUGINS_COUNT="$(jq '.plugins | length' "$OUT1")"
if [[ "$PLUGINS_COUNT" -ne 2 ]]; then
  echo "FAIL: expected 2 plugins, got $PLUGINS_COUNT" >&2
  exit 1
fi
PLUGINS_SORTED="$(jq -r '.plugins | map(.name) | . == (. | sort)' "$OUT1")"
if [[ "$PLUGINS_SORTED" != "true" ]]; then
  echo "FAIL: plugins[] not sorted ASC by name" >&2
  exit 1
fi

# Unsorted item's phase is null.
UNSORTED_PHASE="$(jq -r '.roadmap_items | map(select(.state=="unsorted")) | .[0].phase' "$OUT1")"
if [[ "$UNSORTED_PHASE" != "null" ]]; then
  echo "FAIL: unsorted item should have phase:null, got '$UNSORTED_PHASE'" >&2
  exit 1
fi

echo "PASS: project-context reader is deterministic + schema-correct on populated fixture"
