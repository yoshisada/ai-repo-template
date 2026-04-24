#!/usr/bin/env bash
# validate-phase-frontmatter.sh — schema validator for .kiln/roadmap/phases/*.md
#
# FR-005 / PRD FR-005: Phase frontmatter required keys
# FR-038 / spec FR-038: exposed for use by other skills
# Contract: specs/structured-roadmap/contracts/interfaces.md §2.3 + §1.2
#
# Usage:   validate-phase-frontmatter.sh <path-to-phase.md>
# Output:  stdout = JSON {"ok": true|false, "errors": [<string>...]}
# Exit:    0 always

set -u

PHASE_PATH="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

emit_result() {
  local ok="$1"
  shift
  local errors_json="[]"
  if [ "$#" -gt 0 ]; then
    errors_json="["
    local first=1
    for err in "$@"; do
      local esc="${err//\\/\\\\}"
      esc="${esc//\"/\\\"}"
      if [ "$first" -eq 1 ]; then first=0; else errors_json+=","; fi
      errors_json+="\"$esc\""
    done
    errors_json+="]"
  fi
  printf '{"ok":%s,"errors":%s}\n' "$ok" "$errors_json"
}

if [ -z "$PHASE_PATH" ]; then
  emit_result false "missing path argument"
  exit 0
fi
if [ ! -f "$PHASE_PATH" ]; then
  emit_result false "file not found: $PHASE_PATH"
  exit 0
fi

FM_JSON="$(bash "$SCRIPT_DIR/parse-item-frontmatter.sh" "$PHASE_PATH" 2>/dev/null)"
if [ -z "$FM_JSON" ]; then
  emit_result false "failed to parse frontmatter"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  emit_result false "jq not available"
  exit 0
fi

BASENAME="$(basename "$PHASE_PATH" .md)"

VALIDATION_JSON="$(jq --arg basename "$BASENAME" -c '
  def allowed_status: ["planned","in-progress","complete"];
  . as $fm
  | [
      ( ["name","status","order"][] as $k
        | if ($fm[$k] // null) == null or ($fm[$k] | tostring | length) == 0
          then "missing required key: \($k)"
          else empty end
      ),
      # name must match basename
      ( if ($fm["name"] // "") != $basename and ($fm["name"] // "") != ""
        then "name (\($fm["name"])) must match filename sans .md (\($basename))"
        else empty end
      ),
      # status ∈ allowed
      ( if ($fm["status"] // "") as $s | (allowed_status | index($s)) == null
        then "invalid status: \($fm["status"] // "<missing>") (allowed: \(allowed_status | join(", ")))"
        else empty end
      ),
      # order must be integer
      ( if ($fm["order"] // "") | tostring | test("^-?[0-9]+$") | not
        then "order must be integer: \($fm["order"] // "<missing>")"
        else empty end
      ),
      # started / completed ISO date if present
      ( if ($fm | has("started")) and (($fm["started"] // "") | length) > 0
          and (($fm["started"]) | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") | not)
        then "started must be YYYY-MM-DD: \($fm["started"])"
        else empty end
      ),
      ( if ($fm | has("completed")) and (($fm["completed"] // "") | length) > 0
          and (($fm["completed"]) | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$") | not)
        then "completed must be YYYY-MM-DD: \($fm["completed"])"
        else empty end
      )
    ]
  | { ok: (length == 0), errors: . }
' <<<"$FM_JSON" 2>/dev/null)"

if [ -z "$VALIDATION_JSON" ]; then
  emit_result false "jq validation failed unexpectedly"
  exit 0
fi

printf '%s\n' "$VALIDATION_JSON"
