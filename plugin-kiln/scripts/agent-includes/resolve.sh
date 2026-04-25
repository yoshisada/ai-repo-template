#!/usr/bin/env bash
# resolve.sh — single-pass include-directive resolver for plugin-kiln agent sources.
# Contract: specs/agent-prompt-composition/contracts/interfaces.md §1
# Owner: impl-include-preprocessor track (Theme B, FR-B-1..FR-B-4).
#
# Usage:
#   plugin-kiln/scripts/agent-includes/resolve.sh <input-path>
#   cat src.md | plugin-kiln/scripts/agent-includes/resolve.sh -
#
# Stdout: resolved markdown. Exit 0 on success, 1 on any error (NEVER silent).
#
# Behavior:
#   - Directive regex (POSIX ERE):
#       ^[[:space:]]*<!--[[:space:]]+@include[[:space:]]+([^[:space:]][^>]*[^[:space:]])[[:space:]]*-->[[:space:]]*$
#   - Lines inside fenced code blocks (toggled by /^[[:space:]]*```/) are NEVER expanded (R-2).
#   - Single-pass: directive inside a shared module is an error (FR-B-4).
#   - Path is relative to input file's directory; with `-`, relative to PWD.
#   - Missing target / malformed path / recursive include → exit 1 with diagnostic.

set -euo pipefail

DIRECTIVE_RE='^[[:space:]]*<!--[[:space:]]+@include[[:space:]]+([^[:space:]][^>]*[^[:space:]])[[:space:]]*-->[[:space:]]*$'
FENCE_RE='^[[:space:]]*```'

usage() {
  echo "resolve.sh: usage: resolve.sh <input-path|->" >&2
  exit 1
}

INPUT="${1:-}"
[[ -n "$INPUT" ]] || usage

if [[ "$INPUT" == "-" ]]; then
  BASE_DIR="$PWD"
  SOURCE="<stdin>"
  TMP_INPUT=$(mktemp)
  trap 'rm -f "$TMP_INPUT"' EXIT
  cat > "$TMP_INPUT"
  INPUT_FILE="$TMP_INPUT"
else
  if [[ ! -f "$INPUT" ]]; then
    echo "resolve.sh: input-not-found: $INPUT" >&2
    exit 1
  fi
  BASE_DIR="$(cd "$(dirname "$INPUT")" && pwd)"
  SOURCE="$INPUT"
  INPUT_FILE="$INPUT"
fi

# has_directive_outside_fences <file> — exit 0 if file contains a directive on a
# line by itself outside any fenced code block; exit 1 otherwise.
has_directive_outside_fences() {
  local f="$1"
  local in_cb=0
  local l
  while IFS= read -r l || [[ -n "$l" ]]; do
    if [[ "$l" =~ $FENCE_RE ]]; then
      in_cb=$((1 - in_cb))
      continue
    fi
    if [[ $in_cb -eq 1 ]]; then
      continue
    fi
    if [[ "$l" =~ $DIRECTIVE_RE ]]; then
      return 0
    fi
  done < "$f"
  return 1
}

# emit_include_body <file> — cat file contents to stdout, ensuring the emission
# ends with a newline so the next parent line starts on its own line. Empty
# files emit zero bytes (per contract). Uses od to inspect the last byte
# directly, since $(tail -c 1 ...) strips trailing newlines.
emit_include_body() {
  local f="$1"
  [[ -s "$f" ]] || return 0
  cat "$f"
  local last_hex
  last_hex=$(tail -c 1 "$f" | od -An -tx1 | tr -d ' \n')
  if [[ "$last_hex" != "0a" ]]; then
    printf '\n'
  fi
}

in_code_block=0
line_no=0

while IFS= read -r line || [[ -n "$line" ]]; do
  line_no=$((line_no + 1))

  if [[ "$line" =~ $FENCE_RE ]]; then
    in_code_block=$((1 - in_code_block))
    printf '%s\n' "$line"
    continue
  fi

  if [[ $in_code_block -eq 1 ]]; then
    printf '%s\n' "$line"
    continue
  fi

  if [[ "$line" =~ $DIRECTIVE_RE ]]; then
    inc_path="${BASH_REMATCH[1]}"
    if [[ -z "$inc_path" ]]; then
      echo "resolve.sh: malformed-directive: empty include path (file: $SOURCE, line: $line_no)" >&2
      exit 1
    fi
    target="$BASE_DIR/$inc_path"
    if [[ ! -f "$target" ]]; then
      echo "resolve.sh: include-target-not-found: $inc_path (file: $SOURCE, line: $line_no)" >&2
      exit 1
    fi
    if has_directive_outside_fences "$target"; then
      echo "resolve.sh: recursive-include-detected: $inc_path (file: $SOURCE, line: $line_no)" >&2
      exit 1
    fi
    emit_include_body "$target"
    continue
  fi

  printf '%s\n' "$line"
done < "$INPUT_FILE"
