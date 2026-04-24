#!/usr/bin/env bash
# claude-invoke.sh — Spawn a `claude` subprocess for one test, queue scripted
#                    stream-json user envelopes on stdin, propagate exit code.
#
# Satisfies: FR-009 (subprocess invocation), FR-010 (scripted answers via
#            up-front user envelopes per plan.md D6), FR-011 (KILN_HARNESS=1
#            env), NFR-001 (portability — absolute path callable from anywhere)
# Contract:  contracts/interfaces.md §7.2 (v1.1 — stream-json pivot resolving
#            BLOCKER-001)
#
# Usage:
#   claude-invoke.sh <plugin-dir> <scratch-dir> <initial-message-file> [<answers-file>]
#
# Args:
#   <plugin-dir>               absolute path to the plugin source tree
#                              (passed to `claude --plugin-dir`)
#   <scratch-dir>              absolute path; becomes CWD of the subprocess
#   <initial-message-file>     absolute path to a file whose contents become
#                              the FIRST stream-json user envelope
#   <answers-file>             OPTIONAL. absolute path to inputs/answers.txt;
#                              each non-comment line → one subsequent user
#                              envelope (FIFO / file order)
#
# Current CLI flag contract (Claude Code v2.1.119, verified 2026-04-23):
#   claude --print --verbose                                     \
#          --input-format=stream-json --output-format=stream-json \
#          --dangerously-skip-permissions                        \
#          --plugin-dir <plugin-dir>
#
#   --print    : non-interactive (the old PRD `--headless` does not exist)
#   --verbose  : MANDATORY when --output-format=stream-json; CLI hard-errors
#                without it.
#
# Stream-json envelope shapes (empirically verified on 2026-04-23):
#   IN  (stdin, one NDJSON envelope per line):
#     {"type":"user","message":{"role":"user","content":"<text>"}}
#   OUT (stdout):
#     {"type":"system","subtype":"init", ...}           (once, first)
#     {"type":"assistant","message":{...}, ...}         (one per assistant turn)
#     {"type":"result","subtype":"success","is_error":<bool>, ...}  (once, last)
#
# Env: KILN_HARNESS=1 is exported into the subprocess per FR-011.
#
# Stdout: subprocess stdout (NDJSON transcript) — callers typically redirect
#         to the transcript file that the watcher tails.
# Stderr: subprocess stderr is passed through unchanged; this helper also
#         emits its own diagnostics to stderr.
# Exit:   propagates subprocess exit code; 2 on arg error or CLI-drift detection
set -euo pipefail

# Answer-file comment-escape convention per contracts §6.
# A leading `#` (first non-whitespace char) = skip the line entirely.
# A literal `\#` at line start is un-escaped to `#` and used as the answer.
answers_to_envelopes() {
  local path=$1
  [[ -f $path ]] || return 0
  while IFS= read -r raw || [[ -n $raw ]]; do
    # Strip trailing \r.
    raw=${raw%$'\r'}
    # Trim leading whitespace for comment detection; keep original for content.
    stripped=${raw#"${raw%%[![:space:]]*}"}
    # Pure blank lines ARE meaningful per contracts §6 (count as one "enter").
    # But blank-line-then-skip is ambiguous — treat blank as one answer (enter).
    if [[ ${stripped:0:1} == '#' ]]; then
      continue
    fi
    # Un-escape `\#...` to `#...`.
    if [[ ${raw:0:2} == '\#' ]]; then
      raw="#${raw:2}"
    fi
    # Emit stream-json user envelope. jq-free JSON-encode: escape " and \ and
    # control chars. Use awk for portability.
    local escaped
    escaped=$(printf '%s' "$raw" | awk '
      BEGIN { RS=""; ORS="" }
      {
        gsub(/\\/, "\\\\");
        gsub(/"/, "\\\"");
        gsub(/\n/, "\\n");
        gsub(/\r/, "\\r");
        gsub(/\t/, "\\t");
        print
      }
    ')
    printf '{"type":"user","message":{"role":"user","content":"%s"}}\n' "$escaped"
  done < "$path"
}

# JSON-encode a whole file's contents as one envelope content string.
file_to_envelope() {
  local path=$1
  # Read file, escape, emit single envelope with full content.
  local content
  # Use perl if available for robust control-char escaping; else awk fallback.
  if command -v perl >/dev/null 2>&1; then
    content=$(perl -0777 -MJSON::PP -e 'local $/; my $s = <STDIN>; print JSON::PP->new->ascii(0)->allow_nonref->encode($s)' < "$path")
  else
    # awk fallback — handles \ " \n \r \t; doesn't cover all control chars but
    # is sufficient for typical initial-message text.
    content=$(awk 'BEGIN { printf "\"" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\r$/, ""); printf "%s\\n", $0 } END { printf "\"" }' "$path")
  fi
  # `content` is already surrounded by `"..."`. Embed directly.
  printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$content"
}

# -----------------------------------------------------------------------------
# Args
# -----------------------------------------------------------------------------
if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "claude-invoke.sh: expected 3 or 4 args (plugin-dir scratch-dir initial-message-file [answers-file]), got $#" >&2
  exit 2
fi

plugin_dir=$1
scratch_dir=$2
initial_msg_file=$3
answers_file=${4:-}

for p in "$plugin_dir" "$scratch_dir" "$initial_msg_file"; do
  if [[ ! -e $p ]]; then
    echo "claude-invoke.sh: path does not exist: $p" >&2
    exit 2
  fi
done
if [[ -n $answers_file && ! -f $answers_file ]]; then
  echo "claude-invoke.sh: answers file does not exist: $answers_file" >&2
  exit 2
fi

# -----------------------------------------------------------------------------
# CLI-drift self-check per contracts §7.2 last paragraph. If the required
# flag set has changed, fail fast with a clear diagnostic — this is what
# catches the next PRD Risk 4 event.
# -----------------------------------------------------------------------------
if ! command -v claude >/dev/null 2>&1; then
  echo "claude-invoke.sh: 'claude' not on PATH" >&2
  exit 2
fi

claude_help=$(claude --help 2>&1 || true)
for flag in -- --plugin-dir --print --input-format --output-format --dangerously-skip-permissions --verbose; do
  if ! printf '%s' "$claude_help" | grep -q -F -- "$flag"; then
    echo "claude-invoke.sh: required CLI flag '$flag' not present in \`claude --help\` — CLI drift; update contracts/interfaces.md §7.2" >&2
    exit 2
  fi
done

# -----------------------------------------------------------------------------
# Spawn the subprocess. We pipe our envelope stream into its stdin.
# -----------------------------------------------------------------------------
export KILN_HARNESS=1

# Build envelope stream in a tmp file so we can inspect on failure.
env_stream=$(mktemp "/tmp/kiln-claude-invoke-envelopes.XXXXXX")
{
  file_to_envelope "$initial_msg_file"
  if [[ -n $answers_file ]]; then
    answers_to_envelopes "$answers_file"
  fi
} > "$env_stream"

# Trap cleanup of envelope-stream file on exit.
trap 'rm -f "$env_stream"' EXIT

# Subprocess is invoked with CWD = scratch dir (contracts §5 invariant).
# NB: we do NOT attach a TTY; --print is inherently non-TTY.
(
  cd "$scratch_dir"
  exec claude \
    --print --verbose \
    --input-format=stream-json --output-format=stream-json \
    --dangerously-skip-permissions \
    --plugin-dir "$plugin_dir" \
    < "$env_stream"
)
