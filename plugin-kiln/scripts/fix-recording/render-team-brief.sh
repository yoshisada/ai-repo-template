#!/usr/bin/env bash
# render-team-brief.sh
# FR-025, FR-027, FR-028
#
# Reads a team-brief template on stdin, substitutes a fixed set of
# placeholders with values passed via flags, emits the rendered brief on
# stdout. Exits non-zero if any placeholder remains unsubstituted (catches
# authoring mistakes in the brief templates at skill-edit time).
#
# Invocation:
#   bash render-team-brief.sh \
#     --envelope-path "<abs-path>" \
#     --scripts-dir  "<abs-path>" \
#     --slug         "<slug>" \
#     --date         "<YYYY-MM-DD>" \
#     --project-name "<slug-or-empty>" \
#     --team-kind    "fix-record"|"fix-reflect"
#
# stdin: team-brief template text.
# stdout: rendered brief.
# stderr: silent on success; error lines on failure.
# exit:
#   0 — rendered.
#   1 — missing flag, unreadable template (stdin empty), or unresolved placeholder.

set -u
LC_ALL=C
export LC_ALL

envelope_path=""
scripts_dir=""
slug=""
date_val=""
project_name=""
team_kind=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --envelope-path) envelope_path="${2:-}"; shift 2 ;;
    --scripts-dir)   scripts_dir="${2:-}"; shift 2 ;;
    --slug)          slug="${2:-}"; shift 2 ;;
    --date)          date_val="${2:-}"; shift 2 ;;
    --project-name)  project_name="${2:-}"; shift 2 ;;
    --team-kind)     team_kind="${2:-}"; shift 2 ;;
    *) printf 'render-team-brief: unknown flag %s\n' "$1" >&2; exit 1 ;;
  esac
done

# project_name is the only placeholder allowed to be empty (FR-013 case 3).
for pair in \
  "envelope-path:$envelope_path" \
  "scripts-dir:$scripts_dir" \
  "slug:$slug" \
  "date:$date_val" \
  "team-kind:$team_kind"
do
  name=${pair%%:*}
  val=${pair#*:}
  if [ -z "$val" ]; then
    printf 'render-team-brief: --%s required\n' "$name" >&2
    exit 1
  fi
done

case "$team_kind" in
  fix-record|fix-reflect) : ;;
  *) printf 'render-team-brief: --team-kind must be fix-record or fix-reflect\n' >&2; exit 1 ;;
esac

template=$(cat)
if [ -z "$template" ]; then
  printf 'render-team-brief: empty template on stdin\n' >&2
  exit 1
fi

# Substitute placeholders. Using awk to do literal string replacement so
# neither sed metacharacters nor slashes in values cause grief.
substitute() {
  local text="$1" needle="$2" value="$3"
  awk -v n="$needle" -v v="$value" '
    {
      out = ""
      line = $0
      while (1) {
        i = index(line, n)
        if (i == 0) { out = out line; break }
        out = out substr(line, 1, i - 1) v
        line = substr(line, i + length(n))
      }
      print out
    }
  ' <<< "$text"
}

rendered="$template"
rendered=$(substitute "$rendered" '{{ENVELOPE_PATH}}' "$envelope_path")
rendered=$(substitute "$rendered" '{{SCRIPTS_DIR}}'   "$scripts_dir")
rendered=$(substitute "$rendered" '{{SLUG}}'          "$slug")
rendered=$(substitute "$rendered" '{{DATE}}'          "$date_val")
rendered=$(substitute "$rendered" '{{PROJECT_NAME}}'  "$project_name")
rendered=$(substitute "$rendered" '{{TEAM_KIND}}'     "$team_kind")

# Check for unsubstituted placeholders — any {{WORD}} remaining is a bug.
if printf '%s' "$rendered" | grep -E -q '\{\{[A-Z_]+\}\}'; then
  leftover=$(printf '%s' "$rendered" | grep -oE '\{\{[A-Z_]+\}\}' | sort -u | head -3)
  printf 'render-team-brief: unsubstituted placeholder(s): %s\n' "$(printf '%s' "$leftover" | tr '\n' ' ')" >&2
  exit 1
fi

printf '%s\n' "$rendered"
exit 0
