#!/usr/bin/env bash
# substrate-plugin-skill.sh — v1 substrate driver for the plugin-skill harness
#                            type. Spawns a real `claude --print ... --plugin-
#                            dir <root>` subprocess, feeds scripted stream-json
#                            user envelopes on stdin, redirects subprocess
#                            stdout (NDJSON transcript) to a file the watcher
#                            tails.
#
# Satisfies: FR-009 (claude subprocess spawn) + FR-010 (scripted answers
#            queued up-front per plan.md D6) + FR-012 (scratch snapshot)
# Contract:  contracts/interfaces.md §5 + §7.2 (v1.1)
#
# Usage:
#   substrate-plugin-skill.sh <scratch-dir> <test-dir> <plugin-root>
#
# Required test-dir contents (contracts §5 substrate-script contract):
#   inputs/initial-message.txt   — required; first stream-json user envelope
#   inputs/answers.txt           — optional; subsequent envelopes (FIFO)
#
# Env set for the subprocess (exported by claude-invoke.sh):
#   KILN_HARNESS=1
#
# Transcript / snapshot locations (created by this script):
#   <scratch-dir>/../kiln-test-<basename(scratch-dir)>-transcript.ndjson
#     Wait — per contracts §9, the transcript lives in .kiln/logs/, not in
#     scratch. The harness orchestrator (kiln-test.sh) passes the transcript
#     path via env KILN_TEST_TRANSCRIPT. This script uses that if set,
#     otherwise falls back to a path next to the scratch dir.
#
# Exit: propagates the `claude` subprocess exit code.
set -euo pipefail

harness_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [[ $# -ne 3 ]]; then
  echo "substrate-plugin-skill.sh: expected 3 args (scratch-dir test-dir plugin-root), got $#" >&2
  exit 2
fi

scratch_dir=$1
test_dir=$2
plugin_root=$3

# Validate paths.
for p in "$scratch_dir" "$test_dir" "$plugin_root"; do
  if [[ ! -d $p ]]; then
    echo "substrate-plugin-skill.sh: path does not exist: $p" >&2
    exit 2
  fi
done

initial_msg_file="$test_dir/inputs/initial-message.txt"
if [[ ! -f $initial_msg_file ]]; then
  echo "substrate-plugin-skill.sh: required inputs/initial-message.txt missing in $test_dir" >&2
  exit 2
fi

answers_file="$test_dir/inputs/answers.txt"
[[ -f $answers_file ]] || answers_file=""

# Transcript path: prefer orchestrator-supplied (KILN_TEST_TRANSCRIPT), else
# derive one next to the scratch dir (the orchestrator will provide it in
# production; this fallback is for direct invocation during dev/testing).
transcript_path=${KILN_TEST_TRANSCRIPT:-}
if [[ -z $transcript_path ]]; then
  scratch_base=${scratch_dir##*/}
  transcript_path="/tmp/${scratch_base}-transcript.ndjson"
fi

# Invoke. Redirect subprocess stdout to the transcript; stderr passes through
# to our own stderr so the caller's stderr stream gets runtime diagnostics.
# We do NOT `tee` the transcript to our stdout — the orchestrator does not
# want NDJSON in the TAP stream.
#
# NB: claude-invoke.sh propagates the subprocess exit code. We preserve that.
if [[ -n $answers_file ]]; then
  "$harness_dir/claude-invoke.sh" "$plugin_root" "$scratch_dir" "$initial_msg_file" "$answers_file" \
    > "$transcript_path"
else
  "$harness_dir/claude-invoke.sh" "$plugin_root" "$scratch_dir" "$initial_msg_file" \
    > "$transcript_path"
fi
claude_exit=$?

# Snapshot scratch-dir final state per FR-012.
snapshot_path=${KILN_TEST_SCRATCH_SNAPSHOT:-}
if [[ -n $snapshot_path ]]; then
  "$harness_dir/scratch-snapshot.sh" "$scratch_dir" "$snapshot_path" || true
fi

exit "$claude_exit"
