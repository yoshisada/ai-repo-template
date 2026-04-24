#!/usr/bin/env bash
# parse-roadmap-input.sh — locate the roadmap source file the calling skill
# just wrote (or updated), parse its YAML frontmatter + body, and derive the
# Obsidian-side subpath so the downstream agent can compose its write target.
#
# FR-030 / PRD FR-030: all roadmap create/update writes dispatch via the
# shelf:shelf-write-roadmap-note workflow; this script is the workflow's
# Step 2 input-normaliser (contract §2.11 of structured-roadmap).
# FR-035 / PRD FR-035: workflow shape mirrors shelf-write-issue-note — this
# script plays the same role as parse-create-issue-output.sh.
# FR-037 / PRD FR-037: output is deterministic on identical inputs.
#
# Input (priority order):
#   1. $ROADMAP_INPUT_FILE env var — exact repo-relative path to a .kiln/
#      vision / phase / item file.
#   2. $ROADMAP_INPUT_BLOCK env var — structured text block containing a
#      `source_file = <path>` line (or just the path on its own line).
#   3. .wheel/outputs/roadmap-input.txt — first `.kiln/...` path mentioned.
#   4. stdin — first `.kiln/...` path mentioned (if -c piped / heredoc).
#
# Output (stdout, single-line JSON):
#   {
#     "source_file": ".kiln/.../foo.md",
#     "basename":    "foo.md",
#     "frontmatter": { ... YAML → JSON object ... },
#     "body":        "<everything below the closing --- line>",
#     "obsidian_subpath": "vision.md" | "roadmap/phases/<basename>" | "roadmap/items/<basename>"
#   }
#
# Exit 0 on success; 1 on "no .kiln/... source file could be resolved" — hard
# error, the workflow's finalize-result step will translate this into a JSON
# error payload.

set -u

INPUT_FILE_ENV="${ROADMAP_INPUT_FILE:-}"
INPUT_BLOCK_ENV="${ROADMAP_INPUT_BLOCK:-}"
FALLBACK_FILE="${ROADMAP_INPUT_FALLBACK:-.wheel/outputs/roadmap-input.txt}"

# --- source-file resolution ---------------------------------------------------

# Given any text blob, emit the FIRST `.kiln/...` path on its own (anchored
# either by a leading `source_file =` assignment, bullet list, plain path, or
# unquoted inside prose). The regex is conservative so we don't pick up stray
# punctuation.
extract_kiln_path() {
  grep -oE '\.kiln/[A-Za-z0-9._/-]+\.md' 2>/dev/null | head -1 || true
}

resolve_source_file() {
  # 1) Explicit env var path wins.
  if [ -n "$INPUT_FILE_ENV" ] && [ -f "$INPUT_FILE_ENV" ]; then
    printf '%s\n' "$INPUT_FILE_ENV"
    return 0
  fi

  # 2) Env-var block.
  if [ -n "$INPUT_BLOCK_ENV" ]; then
    local p
    p=$(printf '%s\n' "$INPUT_BLOCK_ENV" | extract_kiln_path)
    if [ -n "${p:-}" ] && [ -f "$p" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  fi

  # 3) Fallback file.
  if [ -f "$FALLBACK_FILE" ]; then
    local p
    p=$(extract_kiln_path < "$FALLBACK_FILE")
    if [ -n "${p:-}" ] && [ -f "$p" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  fi

  # 4) stdin — only if we have something on it (non-interactive).
  if [ ! -t 0 ]; then
    local stdin_buf p
    stdin_buf=$(cat || true)
    p=$(printf '%s\n' "$stdin_buf" | extract_kiln_path)
    if [ -n "${p:-}" ] && [ -f "$p" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  fi

  return 1
}

# --- frontmatter → JSON (awk, identical to parse-create-issue-output.sh shape) -

extract_frontmatter_json() {
  local file="$1"
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
      if ($0 ~ /^[A-Za-z_][A-Za-z0-9_]*:/) {
        colon = index($0, ":")
        k = substr($0, 1, colon - 1)
        v = substr($0, colon + 1)
        sub(/^[[:space:]]+/, "", v)
        sub(/[[:space:]]+$/, "", v)
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
  # Print everything after the second `---` line; if no frontmatter at all,
  # print the whole file (vision.md may be frontmatterless per §1.1).
  awk '
    BEGIN { seen = 0; started = 0; any = 0 }
    {
      any = 1
      if (!started) {
        if ($0 == "---") { seen++; if (seen == 2) { started = 1 }; next }
        if (seen == 0) {
          # No leading --- → whole file is the body.
          buf[length(buf)+1] = $0
          next
        }
        next
      }
      print
    }
    END {
      if (seen == 0 && any == 1) {
        for (i = 1; i <= length(buf); i++) print buf[i]
      }
    }
  ' "$file"
}

# --- obsidian_subpath derivation (contract §2.11) -----------------------------

derive_obsidian_subpath() {
  local path="$1"
  local base
  base=$(basename "$path")
  case "$path" in
    .kiln/vision.md)
      printf 'vision.md\n'
      ;;
    .kiln/roadmap/phases/*.md)
      printf 'roadmap/phases/%s\n' "$base"
      ;;
    .kiln/roadmap/items/*.md)
      printf 'roadmap/items/%s\n' "$base"
      ;;
    *)
      printf 'parse-roadmap-input: unrecognized source path (expected .kiln/vision.md or .kiln/roadmap/{phases,items}/*.md): %s\n' "$path" >&2
      return 2
      ;;
  esac
}

# --- main --------------------------------------------------------------------

main() {
  local source_file basename frontmatter body body_esc subpath
  if ! source_file=$(resolve_source_file); then
    printf 'parse-roadmap-input: no resolvable .kiln/ source file (set $ROADMAP_INPUT_FILE, write %s, or pipe via stdin)\n' "$FALLBACK_FILE" >&2
    exit 1
  fi
  if ! subpath=$(derive_obsidian_subpath "$source_file"); then
    exit 1
  fi

  basename=$(basename "$source_file")
  frontmatter=$(extract_frontmatter_json "$source_file")
  # Empty frontmatter → emit `{}` (vision.md may have no frontmatter).
  [ -n "${frontmatter:-}" ] || frontmatter="{}"

  body=$(extract_body "$source_file")
  body_esc=$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null \
             || node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>console.log(JSON.stringify(d)))' <<<"$body" 2>/dev/null \
             || printf '"<body-escape-failed>"')

  printf '{"source_file":"%s","basename":"%s","frontmatter":%s,"body":%s,"obsidian_subpath":"%s"}\n' \
    "$source_file" "$basename" "$frontmatter" "$body_esc" "$subpath"
}

main "$@"
