#!/usr/bin/env bash
# validate-item-frontmatter.sh — schema validator for .kiln/roadmap/items/*.md
#
# FR-008 / PRD FR-008: AI-native sizing only — forbid human-time / T-shirt fields
# FR-011 / PRD FR-011: kind:critique requires non-empty proof_path
# FR-038 / spec FR-038: exposed for use by other skills (distill, next, specify)
# Contract: specs/structured-roadmap/contracts/interfaces.md §2.2 + §1.3–§1.5
#
# Usage:   validate-item-frontmatter.sh <path-to-item.md>
# Output:  stdout = JSON {"ok": true|false, "errors": [<string>...]}
# Exit:    0 always (validation result is in JSON, not exit code)

set -u

ITEM_PATH="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

emit_result() {
  local ok="$1"
  shift
  local errors_json="[]"
  if [ "$#" -gt 0 ]; then
    errors_json="["
    local first=1
    for err in "$@"; do
      # JSON-escape: \ and "
      local esc="${err//\\/\\\\}"
      esc="${esc//\"/\\\"}"
      if [ "$first" -eq 1 ]; then
        first=0
      else
        errors_json+=","
      fi
      errors_json+="\"$esc\""
    done
    errors_json+="]"
  fi
  printf '{"ok":%s,"errors":%s}\n' "$ok" "$errors_json"
}

if [ -z "$ITEM_PATH" ]; then
  emit_result false "missing path argument"
  exit 0
fi
if [ ! -f "$ITEM_PATH" ]; then
  emit_result false "file not found: $ITEM_PATH"
  exit 0
fi

# Parse frontmatter to JSON via the parser helper
FM_JSON="$(bash "$SCRIPT_DIR/parse-item-frontmatter.sh" "$ITEM_PATH" 2>/dev/null)"
if [ -z "$FM_JSON" ]; then
  emit_result false "failed to parse frontmatter"
  exit 0
fi

# jq-based validation. Validation rules (§2.2):
#   - All required keys present per §1.3.
#   - kind ∈ allowed set.
#   - status ∈ kind-specific set (§1.4).
#   - state ∈ FR-021 set.
#   - Sizing fields present and ∈ allowed sets.
#   - id matches `^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+$` AND equals basename sans .md.
#   - kind: critique → proof_path present and non-empty.
#   - ZERO forbidden keys (§1.5).
BASENAME="$(basename "$ITEM_PATH" .md)"

# Use jq to drive validation and emit an array of error strings. Fallback to
# bash parsing would be cheaper but jq is already a hard dependency of kiln.
if ! command -v jq >/dev/null 2>&1; then
  emit_result false "jq not available — validator requires jq"
  exit 0
fi

VALIDATION_JSON="$(jq --arg basename "$BASENAME" -c '
  def required_keys: [
    "id","title","kind","date","status","phase","state",
    "blast_radius","review_cost","context_cost"
  ];
  def allowed_kinds: [
    "feature","goal","research","constraint","non-goal","milestone","critique"
  ];
  def allowed_states: ["planned","in-phase","distilled","specced","shipped"];
  def allowed_blast: ["isolated","feature","cross-cutting","infra"];
  def allowed_review: ["trivial","moderate","careful","expert"];
  def forbidden_keys: [
    "human_time","human_days","effort_days","effort_hours",
    "t_shirt_size","tshirt","estimate_days","estimate_hours","pomodoros"
  ];
  def status_for_kind:
    { "feature":    ["open","in-progress","shipped","dropped"],
      "goal":       ["open","met","dropped"],
      "research":   ["open","in-progress","concluded","dropped"],
      "constraint": ["active","retired"],
      "non-goal":   ["active","retired"],
      "milestone":  ["pending","reached","missed"],
      "critique":   ["open","partially-disproved","disproved"] };

  . as $fm
  | [
      # Required keys present
      ( required_keys[] as $k
        | if ($fm[$k] // null) == null or ($fm[$k] | tostring | length) == 0
          then "missing required key: \($k)"
          else empty end
      ),
      # Forbidden keys absent
      ( forbidden_keys[] as $k
        | if ($fm | has($k))
          then "forbidden sizing key present: \($k) — AI-native sizing only (FR-008)"
          else empty end
      ),
      # size field with T-shirt value
      ( if ($fm | has("size")) and (($fm["size"] // "") | ascii_downcase | test("^(xs|s|m|l|xl|xxl)$"))
        then "forbidden sizing key present: size=\($fm["size"]) — AI-native sizing only (FR-008)"
        else empty end
      ),
      # id format and filename match
      ( if ($fm["id"] // "") | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+$") | not
        then "invalid id format (expected <YYYY-MM-DD>-<slug>): \($fm["id"] // "<missing>")"
        else empty end
      ),
      ( if ($fm["id"] // "") != $basename
        then "id (\($fm["id"] // "<missing>")) must equal basename sans .md (\($basename))"
        else empty end
      ),
      # kind allowed
      ( if ($fm["kind"] // "") as $k | (allowed_kinds | index($k)) == null
        then "invalid kind: \($fm["kind"] // "<missing>") (allowed: \(allowed_kinds | join(", ")))"
        else empty end
      ),
      # state allowed
      ( if ($fm["state"] // "") as $s | (allowed_states | index($s)) == null
        then "invalid state: \($fm["state"] // "<missing>") (allowed: \(allowed_states | join(", ")))"
        else empty end
      ),
      # status ∈ kind-specific set
      ( ($fm["kind"] // "") as $k
        | ($fm["status"] // "") as $s
        | (status_for_kind[$k] // null) as $allowed
        | if $allowed == null
          then empty  # already flagged by kind check
          elif ($allowed | index($s)) == null
          then "invalid status for kind=\($k): \($s) (allowed: \($allowed | join(", ")))"
          else empty end
      ),
      # blast_radius
      ( if ($fm["blast_radius"] // "") as $b | (allowed_blast | index($b)) == null
        then "invalid blast_radius: \($fm["blast_radius"] // "<missing>") (allowed: \(allowed_blast | join(", ")))"
        else empty end
      ),
      # review_cost
      ( if ($fm["review_cost"] // "") as $r | (allowed_review | index($r)) == null
        then "invalid review_cost: \($fm["review_cost"] // "<missing>") (allowed: \(allowed_review | join(", ")))"
        else empty end
      ),
      # context_cost non-empty free-text
      ( if (($fm["context_cost"] // "") | tostring | length) == 0
        then "context_cost must be non-empty free-text (AI-native sizing)"
        else empty end
      ),
      # critique requires proof_path
      ( if ($fm["kind"] // "") == "critique"
          and (($fm["proof_path"] // "") | tostring | length) == 0
        then "kind:critique requires non-empty proof_path (FR-011)"
        else empty end
      )
    ]
  | { ok: (length == 0), errors: . }
' <<<"$FM_JSON" 2>/dev/null)"

if [ -z "$VALIDATION_JSON" ]; then
  emit_result false "jq validation failed unexpectedly"
  exit 0
fi

# T002 / FR-001 / contracts §2 — additive research-block validation.
# Strategy: research-block fields use flow-style YAML that the existing
# parse-item-frontmatter.sh (line-oriented awk) cannot handle correctly. So
# we use the dedicated research-block extractor (python3-based, same shape
# as parse-prd-frontmatter.sh) to project research-block fields, then call
# the shared validation helper.
#
# Backward compat: items without research-block keys produce a projection
# with all-null values; the helper passes them as { ok: true, errors: [] }.
# The existing `{ ok, errors }` JSON shape is preserved — research warnings
# emit to stderr (NFR-001 backward compat — callers reading only stdout
# remain unaffected).
RESEARCH_PARSER="$SCRIPT_DIR/../research/parse-research-block.sh"
RESEARCH_HELPER="$SCRIPT_DIR/../research/validate-research-block.sh"
if [ -x "$RESEARCH_PARSER" ] && [ -x "$RESEARCH_HELPER" ]; then
  RB_STDERR="$(mktemp)"
  RB_JSON="$(bash "$RESEARCH_PARSER" "$ITEM_PATH" 2>"$RB_STDERR")"
  RB_RC=$?
  if [ "$RB_RC" -ne 0 ]; then
    # Parser bailed (loud-failure on malformed value per NFR-007). Surface
    # the bail message as a validation error so the item is rejected.
    PARSE_ERR="$(grep -oE 'parse error: .*' "$RB_STDERR" | head -1 | sed 's/^parse error: //')"
    [ -z "$PARSE_ERR" ] && PARSE_ERR="research-block parse failed (rc=$RB_RC)"
    VALIDATION_JSON="$(jq --arg e "$PARSE_ERR" -c '
      .errors += [$e]
      | .ok = false
    ' <<<"$VALIDATION_JSON" 2>/dev/null)"
  elif [ -n "$RB_JSON" ]; then
    RESEARCH_RESULT="$(bash "$RESEARCH_HELPER" "$RB_JSON" 2>/dev/null || true)"
    if [ -n "$RESEARCH_RESULT" ]; then
      VALIDATION_JSON="$(jq --argjson rb "$RESEARCH_RESULT" -c '
        .errors = (.errors + ($rb.errors // []))
        | .ok = (.ok and ($rb.ok // true))
      ' <<<"$VALIDATION_JSON" 2>/dev/null)"
      printf '%s' "$RESEARCH_RESULT" | jq -r '.warnings[]?' 2>/dev/null \
        | while IFS= read -r w; do
            [ -n "$w" ] && printf 'Warning: %s\n' "$w" >&2
          done
    fi
  fi
  rm -f "$RB_STDERR"
fi

printf '%s\n' "$VALIDATION_JSON"
