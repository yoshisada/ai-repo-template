#!/usr/bin/env bash
# parse-create-issue-output.sh — locate the freshly-created backlog issue file
#
# Reads .wheel/outputs/create-issue-result.md (the output of the kiln-report-issue
# create-issue agent step), finds the .kiln/issues/<file>.md path it mentions,
# and emits a small JSON blob the downstream agent step can consume:
#
#   {
#     "issue_file": ".kiln/issues/<file>.md",
#     "basename":   "<file>.md",
#     "frontmatter": { ... parsed YAML frontmatter ... },
#     "body": "<issue body — everything below the front-matter close>"
#   }
#
# Fallback: if the result file doesn't name a path, or the path doesn't exist,
# pick the newest file in .kiln/issues/ (mtime) as a best-effort match. The
# sub-workflow's agent step rechecks this choice.
#
# Exit 0 on success, 1 on "no .kiln/issues/*.md file found anywhere" (hard error
# — the foreground create-issue step failed).

set -u

RESULT_FILE="${RESULT_FILE:-.wheel/outputs/create-issue-result.md}"
ISSUES_DIR="${ISSUES_DIR:-.kiln/issues}"

find_issue_file() {
  # 1) Prefer a path the result file explicitly names.
  if [ -f "$RESULT_FILE" ]; then
    local named
    named=$(grep -oE '\.kiln/issues/[^ )`"'"'"']+\.md' "$RESULT_FILE" 2>/dev/null | head -1 || true)
    if [ -n "${named:-}" ] && [ -f "$named" ]; then
      printf '%s\n' "$named"
      return 0
    fi
  fi
  # 2) Fallback: newest .md in .kiln/issues/ (top level only, skip completed/).
  local newest
  newest=$(ls -t "$ISSUES_DIR"/*.md 2>/dev/null | head -1 || true)
  if [ -n "${newest:-}" ]; then
    printf '%s\n' "$newest"
    return 0
  fi
  return 1
}

extract_frontmatter_json() {
  local file="$1"
  # Read everything between the first and second '---' lines; convert each
  #   key: value
  # line to a JSON pair. Strip surrounding quotes on the value. Values that
  # look like `null` / integers are kept as bare JSON.
  #
  # Uses POSIX awk features only (no gawk `match(..., arr)`).
  awk '
    function json_escape(s,   r, n, i, c) {
      gsub(/\\/, "\\\\", s)
      gsub(/"/,  "\\\"", s)
      return s
    }
    BEGIN { in_fm = 0; n = 0 }
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { in_fm = 0; exit }
    in_fm {
      # Match "<key>:<space>*<value>" where key is an identifier.
      if ($0 ~ /^[A-Za-z_][A-Za-z0-9_]*:/) {
        colon = index($0, ":")
        k = substr($0, 1, colon - 1)
        v = substr($0, colon + 1)
        # Left-trim whitespace from v.
        sub(/^[[:space:]]+/, "", v)
        # Right-trim whitespace.
        sub(/[[:space:]]+$/, "", v)
        # Strip surrounding double or single quotes.
        if (v ~ /^".*"$/) { v = substr(v, 2, length(v)-2) }
        else if (v ~ /^'\''.*'\''$/) { v = substr(v, 2, length(v)-2) }
        keys[n] = k; vals[n] = v; n++
      }
    }
    END {
      printf "{"
      for (i = 0; i < n; i++) {
        if (i > 0) printf ","
        v = vals[i]
        if (v == "null" || v ~ /^-?[0-9]+$/) {
          printf "\"%s\":%s", keys[i], v
        } else {
          printf "\"%s\":\"%s\"", keys[i], json_escape(v)
        }
      }
      printf "}"
    }
  ' "$file"
}

extract_body() {
  local file="$1"
  # Print everything after the second `---` line.
  awk '
    BEGIN { seen = 0; started = 0 }
    {
      if (!started) {
        if ($0 == "---") { seen++; if (seen == 2) { started = 1 }; next }
        next
      }
      print
    }
  ' "$file"
}

main() {
  local issue_file
  if ! issue_file=$(find_issue_file); then
    printf 'parse-create-issue-output: no .kiln/issues/*.md file found\n' >&2
    exit 1
  fi
  local basename frontmatter body body_esc
  basename=$(basename "$issue_file")
  frontmatter=$(extract_frontmatter_json "$issue_file")
  body=$(extract_body "$issue_file")
  # JSON-escape the body.
  body_esc=$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null \
             || node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>console.log(JSON.stringify(d)))' <<<"$body" 2>/dev/null \
             || printf '"<body-escape-failed>"')
  # Trim trailing newline emitted by python/node's print line.
  printf '{"issue_file":"%s","basename":"%s","frontmatter":%s,"body":%s}\n' \
    "$issue_file" "$basename" "$frontmatter" "$body_esc"
}

main "$@"
