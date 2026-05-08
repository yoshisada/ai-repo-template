#!/usr/bin/env bash
# watcher-runner.sh — Polls a running test session, classifies state, terminates
#                     on `stalled`, writes verdict JSON + human-readable report.
#
# Satisfies: FR-006 (classification), FR-007 (verdict report), FR-008 (no
#            hard caps — termination only on classifier verdict)
# Contract:  contracts/interfaces.md §7.9 (v1.1 — `<transcript-path>` arg
#            replaces `<stdin-fifo>`) + §3 (verdict JSON schema +
#            classification rules) + the test-watcher.md agent spec
#
# V1 implementation note (per agent spec): the classification rules are pure
# bookkeeping (timestamps + file counts), so this runner implements them
# directly in bash without spawning the test-watcher LLM agent. The agent
# spec exists as the authoritative documentation + extension point.
#
# Usage:
#   watcher-runner.sh <scratch-dir> <subprocess-pid> <transcript-path> \
#                     <test-yaml> <output-verdict-json> <output-verdict-md>
#
# Args:
#   <scratch-dir>           absolute path to /tmp/kiln-test-<uuid>/
#   <subprocess-pid>        PID of the substrate's process (the immediate child
#                           backgrounded by kiln-test.sh; we SIGTERM its
#                           process group on stall)
#   <transcript-path>       absolute path to the NDJSON transcript file
#   <test-yaml>             absolute path to the test's test.yaml (used for
#                           timeout-override + expected-exit lookup)
#   <output-verdict-json>   absolute path to write verdict JSON on terminal
#                           classification (only — healthy is silent)
#   <output-verdict-md>     absolute path to write the human-readable report
#
# Env (from kiln-test.sh):
#   KILN_TEST_STALL_WINDOW    seconds; defaults to 300
#   KILN_TEST_POLL_INTERVAL   seconds; defaults to 30
#   KILN_TEST_REPO_ROOT       absolute path
#
# Exit:
#   0 — verdict written + termination delivered (if needed); session is done
#   2 — arg error
set -euo pipefail

harness_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [[ $# -ne 6 ]]; then
  echo "watcher-runner.sh: expected 6 args (scratch-dir subprocess-pid transcript-path test-yaml output-verdict-json output-verdict-md), got $#" >&2
  exit 2
fi

scratch_dir=$1
subprocess_pid=$2
transcript_path=$3
test_yaml=$4
verdict_json=$5
verdict_md=$6

stall_window=${KILN_TEST_STALL_WINDOW:-300}
poll_interval=${KILN_TEST_POLL_INTERVAL:-30}

# Per-test timeout-override from test.yaml (overrides stall_window).
if [[ -f $test_yaml ]]; then
  override=$(awk '/^timeout-override:[[:space:]]*[0-9]+/ { print $2; exit }' "$test_yaml")
  if [[ -n ${override:-} ]] && (( override >= 60 )) && (( override <= 3600 )); then
    stall_window=$override
  fi
fi

expected_exit=0
if [[ -f $test_yaml ]]; then
  ee=$(awk '/^expected-exit:[[:space:]]*[0-9]+/ { print $2; exit }' "$test_yaml")
  [[ -n ${ee:-} ]] && expected_exit=$ee
fi

# Helpers.
iso_now() { date -u +"%Y-%m-%dT%H:%M:%SZ" ; }
session_started_iso=$(iso_now)
last_scratch_write_iso=$session_started_iso
last_transcript_advance_iso=$session_started_iso

prev_scratch_mtime=0
prev_transcript_lines=0
last_advance_epoch=$(date -u +%s)

# Final classification + payload accumulator.
final_classification=""
final_result_envelope=null

# JSON-string-escape a multi-line text via perl (preferred) or awk (fallback).
json_escape_string() {
  if command -v perl >/dev/null 2>&1; then
    perl -0777 -e 'local $/; my $s = <STDIN>; $s =~ s/\\/\\\\/g; $s =~ s/"/\\"/g; $s =~ s/\n/\\n/g; $s =~ s/\r/\\r/g; $s =~ s/\t/\\t/g; print $s'
  else
    awk 'BEGIN { ORS="" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\r$/, ""); printf "%s\\n", $0 }'
  fi
}

# Write verdict JSON + verdict MD report.
write_verdict() {
  local classification=$1

  # Collect last 50 NDJSON envelopes from transcript.
  local last50_array="[]"
  if [[ -f $transcript_path ]]; then
    last50_array=$(
      tail -n 50 "$transcript_path" \
        | awk 'BEGIN { print "["; first=1 }
               NF { if (!first) printf ",\n"; first=0;
                    gsub(/\\/, "\\\\"); gsub(/"/, "\\\"");
                    gsub(/\r$/, "");
                    printf "    \"%s\"", $0 }
               END { print "\n  ]" }'
    )
    # Empty file → keep []
    [[ -z $last50_array ]] && last50_array="[]"
  fi

  # Scratch files list as JSON array.
  local files_array="[]"
  if [[ -d $scratch_dir ]]; then
    files_array=$(
      (cd "$scratch_dir" && find . -type f) \
        | sort \
        | sed 's|^\./||' \
        | awk 'BEGIN { print "["; first=1 }
               NF { if (!first) printf ",\n"; first=0; gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); printf "    \"%s\"", $0 }
               END { print "\n  ]" }'
    )
    [[ -z $files_array ]] && files_array="[]"
  fi

  # Result envelope: last `{"type":"result",...}` line in transcript verbatim
  # (JSON-string-escaped so it can be embedded as a quoted string).
  local result_env_field="null"
  if [[ -f $transcript_path ]]; then
    local last_result
    last_result=$(grep '^{"type":"result"' "$transcript_path" 2>/dev/null | tail -1 || true)
    if [[ -n $last_result ]]; then
      local escaped
      escaped=$(printf '%s' "$last_result" | json_escape_string)
      result_env_field="\"$escaped\""
    fi
  fi

  local scratch_uuid=${scratch_dir##*/kiln-test-}
  local verdict_emitted_iso
  verdict_emitted_iso=$(iso_now)

  cat > "$verdict_json" <<EOF
{
  "classification": "$classification",
  "timestamps": {
    "session_started_iso": "$session_started_iso",
    "last_scratch_write_iso": "$last_scratch_write_iso",
    "last_transcript_advance_iso": "$last_transcript_advance_iso",
    "verdict_emitted_iso": "$verdict_emitted_iso"
  },
  "last_50_lines": $last50_array,
  "scratch_uuid": "$scratch_uuid",
  "scratch_files": $files_array,
  "result_envelope": $result_env_field
}
EOF

  # Human-readable report.
  cat > "$verdict_md" <<EOF
# kiln-test verdict — $scratch_uuid

- **Classification**: \`$classification\`
- **Scratch UUID**: \`$scratch_uuid\`
- **Scratch dir** (retained on failure): \`$scratch_dir/\`
- **Session started**: $session_started_iso
- **Last scratch write**: $last_scratch_write_iso
- **Last transcript advance**: $last_transcript_advance_iso
- **Verdict emitted**: $verdict_emitted_iso
- **Stall window used**: ${stall_window}s
- **Poll interval**: ${poll_interval}s

## Scratch files

$(if [[ -d $scratch_dir ]]; then (cd "$scratch_dir" && find . -type f | sort | sed 's|^|- \`|;s|$|\`|'); fi)

## Last 50 transcript envelopes

\`\`\`ndjson
$(if [[ -f $transcript_path ]]; then tail -n 50 "$transcript_path"; fi)
\`\`\`

## Final result envelope (if any)

\`\`\`json
$(if [[ -f $transcript_path ]]; then grep '^{"type":"result"' "$transcript_path" 2>/dev/null | tail -1; fi)
\`\`\`
EOF
}

# Send SIGTERM to the subprocess + its children. macOS doesn't have `pkill -P`
# on every install but does have `pgrep`. Use a portable two-step kill.
terminate_subprocess() {
  local pid=$1
  # Try gentle TERM first.
  kill -TERM "$pid" 2>/dev/null || return 0
  # Send TERM to direct children too if pkill is available.
  if command -v pkill >/dev/null 2>&1; then
    pkill -TERM -P "$pid" 2>/dev/null || true
  fi
  # Wait up to 10s for natural exit.
  for _ in $(seq 1 10); do
    if ! kill -0 "$pid" 2>/dev/null; then return 0; fi
    sleep 1
  done
  # Hard kill.
  kill -KILL "$pid" 2>/dev/null || true
  if command -v pkill >/dev/null 2>&1; then
    pkill -KILL -P "$pid" 2>/dev/null || true
  fi
}

# Poll loop.
while :; do
  snapshot=$("$harness_dir/watcher-poll.sh" "$scratch_dir" "$subprocess_pid" "$transcript_path")

  # Parse snapshot via awk (jq-free).
  alive=$(printf '%s' "$snapshot" | awk -F'"alive":' 'NR==1 { sub(/,.*/, "", $2); print $2 }')
  scratch_mtime=$(printf '%s' "$snapshot" | awk -F'"scratch_mtime":' 'NR==1 { sub(/,.*/, "", $2); print $2 }')
  transcript_lines=$(printf '%s' "$snapshot" | awk -F'"transcript_lines":' 'NR==1 { sub(/[^0-9].*/, "", $2); print $2 }')

  now_epoch=$(date -u +%s)

  # Detect advance.
  advanced=0
  if [[ ${scratch_mtime:-0} -gt $prev_scratch_mtime ]]; then
    last_scratch_write_iso=$(iso_now)
    prev_scratch_mtime=$scratch_mtime
    advanced=1
  fi
  if [[ ${transcript_lines:-0} -gt $prev_transcript_lines ]]; then
    last_transcript_advance_iso=$(iso_now)
    prev_transcript_lines=$transcript_lines
    advanced=1
  fi
  if [[ $advanced -eq 1 ]]; then
    last_advance_epoch=$now_epoch
  fi

  # Subprocess exited?
  if [[ $alive == "false" ]]; then
    # Inspect transcript for a result envelope.
    if [[ -f $transcript_path ]] && grep -q '^{"type":"result".*"is_error":true' "$transcript_path" 2>/dev/null; then
      final_classification="failed"
      write_verdict "failed"
    fi
    # Otherwise the substrate path will compare exit codes — no verdict needed
    # from the watcher. Still write a healthy-exit informational verdict so
    # operators can see what happened.
    if [[ -z $final_classification ]]; then
      write_verdict "exited"
    fi
    exit 0
  fi

  # Workflow-archived early-terminate check.
  #
  # Symptom this addresses: orchestrator's claude --print keeps running
  # in a gateway-retry storm (api_retry envelopes flood the transcript)
  # AFTER the wheel has already archived the workflow to history/. The
  # watcher's stall heuristic doesn't fire because the transcript is
  # still advancing on retry events. But the workflow IS done — its
  # state file is gone and a success/failure archive exists.
  #
  # Detect that condition: when scratch_dir/.wheel/ has zero live
  # state_*.json files AND at least one history/<bucket>/*.json
  # archive exists, treat as terminated. Classify as "exited" so the
  # downstream substrate runs assertions against the archived state.
  if [[ -d "$scratch_dir/.wheel" ]]; then
    live_states=$(find "$scratch_dir/.wheel" -maxdepth 1 -name 'state_*.json' 2>/dev/null | head -1)
    if [[ -z "$live_states" ]]; then
      archive_exists=$(find "$scratch_dir/.wheel/history" -maxdepth 2 -name '*.json' 2>/dev/null | head -1)
      if [[ -n "$archive_exists" ]]; then
        final_classification="exited"
        write_verdict "exited"
        terminate_subprocess "$subprocess_pid"
        exit 0
      fi
    fi
  fi

  # Stall check.
  idle_secs=$((now_epoch - last_advance_epoch))
  if (( idle_secs >= stall_window )); then
    final_classification="stalled"
    write_verdict "stalled"
    terminate_subprocess "$subprocess_pid"
    exit 0
  fi

  sleep "$poll_interval"
done
