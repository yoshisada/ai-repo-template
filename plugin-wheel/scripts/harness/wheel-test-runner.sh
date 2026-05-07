#!/usr/bin/env bash
# kiln-test.sh — Top-level harness orchestrator.
#
# Satisfies: FR-001 (three invocation forms), FR-005 (exit-code aggregation),
#            FR-004 (TAP stream), NFR-003 (deterministic stdout)
# Contract:  contracts/interfaces.md §7.11 + §2 (TAP stream shape) + §5 (dispatch)
#
# Usage:
#   kiln-test.sh                             # auto-detect plugin
#   kiln-test.sh <plugin-name>               # run all tests for plugin
#   kiln-test.sh <plugin-name> <test-name>   # run single test
#
# Plugin auto-detect scans CWD for sibling dirs matching `plugin-<name>/`. If
# exactly one match, use it. If multiple, exit 2 with a plugin-list diagnostic.
#
# PHASE STATUS: Phase B wires the substrate (spawns `claude --print ...` +
# runs assertions.sh). Phase C will layer the watcher on top (classification-
# driven termination). For Phase B, subprocess termination relies on `claude`
# exiting on its own (either by consuming all queued envelopes then emitting
# a `{"type":"result",...}` envelope, or by hitting an error). FR-008 no-hard-
# caps still holds — we never wrap the subprocess in `timeout` or kill it.
#
# Stdout: TAP v14 stream (header + one line per test + optional YAML diagnostic)
# Stderr: diagnostics / warnings
# Exit:   0 — all pass, 1 — at least one fail, 2 — at least one skip (no fails)
set -euo pipefail

# Resolve this script's directory so we can dispatch to sibling helpers by
# absolute path. `${BASH_SOURCE[0]}` is portable to bash 3.2+ (macOS default).
harness_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# -----------------------------------------------------------------------------
# Helper: emit a TAP bail-out on stdout and exit. MUST NOT be called from
# inside a command substitution — the `Bail out!` line is part of the TAP
# stream and must reach the caller's stdout. Helper functions that *might*
# bail should instead return a non-zero exit code + write a diagnostic to
# stderr, and the top-level caller converts that into the Bail out! line.
# -----------------------------------------------------------------------------
bail_out() {
  local msg=$1
  # TAP v14: `Bail out! <msg>` is the standard fatal line.
  printf 'Bail out! %s\n' "$msg"
  exit 2
}

# -----------------------------------------------------------------------------
# Auto-detect plugin directory. On success prints the matched plugin-<name>/
# path (absolute) to stdout. On failure, writes diagnostic to stderr and
# returns 1 (ambiguous multi-match) or 2 (no plugin found). Caller is
# responsible for emitting the Bail out! line — this function is safe to
# call inside `$(...)`.
# -----------------------------------------------------------------------------
auto_detect_plugin() {
  local cwd=$1
  local -a candidates=()
  for d in "$cwd"/plugin-*/; do
    [[ -d $d ]] || continue
    if [[ -d "$d.claude-plugin" || -d "${d}skills" ]]; then
      candidates+=("${d%/}")
    fi
  done
  if (( ${#candidates[@]} == 0 )); then
    echo "no plugin-<name>/ dir found in $cwd; pass plugin name explicitly (e.g., /kiln:kiln-test kiln)" >&2
    return 2
  fi
  if (( ${#candidates[@]} > 1 )); then
    local list
    list=$(printf '%s\n' "${candidates[@]}" | sed 's|^.*/||' | tr '\n' ' ')
    echo "multiple plugin-<name>/ dirs found: ${list}— pass plugin name explicitly" >&2
    return 1
  fi
  printf '%s\n' "${candidates[0]}"
  return 0
}

# -----------------------------------------------------------------------------
# Check `claude` is on PATH (edge case per spec.md §Edge Cases).
# -----------------------------------------------------------------------------
check_claude_on_path() {
  if ! command -v claude >/dev/null 2>&1; then
    bail_out "claude CLI not on PATH; install Claude Code (https://docs.claude.com/en/docs/claude-code)"
  fi
}

# -----------------------------------------------------------------------------
# Argument parsing (FR-001).
# -----------------------------------------------------------------------------
repo_root=${KILN_TEST_REPO_ROOT:-$(pwd)}

if [[ $# -gt 2 ]]; then
  bail_out "too many arguments: expected 0, 1, or 2 (got $#)"
fi

plugin_name=${1:-}
test_name=${2:-}

# Resolve plugin root.
if [[ -z $plugin_name ]]; then
  # Capture stderr separately so we can embed the diagnostic in Bail out!
  ad_err=$(mktemp)
  if ! plugin_root=$(auto_detect_plugin "$repo_root" 2>"$ad_err"); then
    msg=$(awk 'NF { print; exit }' "$ad_err")
    rm -f "$ad_err"
    bail_out "$msg"
  fi
  rm -f "$ad_err"
  plugin_name=${plugin_root##*/plugin-}
else
  plugin_root="$repo_root/plugin-$plugin_name"
  if [[ ! -d $plugin_root ]]; then
    bail_out "plugin dir does not exist: $plugin_root"
  fi
fi

# Check claude CLI present (only needed once per invocation).
check_claude_on_path

# Load config (defaults + any .kiln/test.config overrides).
config_output=$("$harness_dir/config-load.sh" "$repo_root") || bail_out "config-load.sh failed"
eval "$config_output"

# Expand the `<name>` placeholder in discovery_path if present.
# Default `plugin-<name>/tests` → `plugin-kiln/tests`.
discovery_rel=${discovery_path/<name>/$plugin_name}

# -----------------------------------------------------------------------------
# Discover tests. Each test = a directory containing test.yaml.
# -----------------------------------------------------------------------------
tests_root="$repo_root/$discovery_rel"
# If discovery_path is absolute, don't prepend repo_root.
if [[ $discovery_rel == /* ]]; then
  tests_root=$discovery_rel
fi

declare -a discovered_tests=()
if [[ -d $tests_root ]]; then
  # Stable discovery order: sorted by directory basename (determinism per NFR-003).
  # Only directories that contain test.yaml count as tests.
  while IFS= read -r -d '' dir; do
    if [[ -f "$dir/test.yaml" ]]; then
      discovered_tests+=("$dir")
    fi
  done < <(find "$tests_root" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
fi

# If form (c) `<plugin> <test>`, filter to that one test.
if [[ -n $test_name ]]; then
  filtered=()
  for d in "${discovered_tests[@]}"; do
    if [[ ${d##*/} == "$test_name" ]]; then
      filtered+=("$d")
      break
    fi
  done
  if (( ${#filtered[@]} == 0 )); then
    bail_out "test '$test_name' not found under $tests_root"
  fi
  discovered_tests=("${filtered[@]}")
fi

n=${#discovered_tests[@]}

# Ensure .kiln/logs/ exists for verdict reports + transcripts + snapshots.
logs_dir="$repo_root/.kiln/logs"
mkdir -p "$logs_dir"

# -----------------------------------------------------------------------------
# Emit TAP header (contracts §2 stream shape).
# -----------------------------------------------------------------------------
printf 'TAP version 14\n'
printf '1..%s\n' "$n"

# -----------------------------------------------------------------------------
# Helper: extract a scalar value from test.yaml (mirrors test-yaml-validate
# extraction). We trust validation has already passed when this runs.
# -----------------------------------------------------------------------------
extract_yaml_scalar() {
  local key=$1 file=$2
  awk -v k="^${key}:[[:space:]]*" '
    $0 ~ k {
      sub(k, "");
      if (substr($0,1,1) == "\"" && substr($0,length($0),1) == "\"") {
        print substr($0, 2, length($0)-2)
      } else if (substr($0,1,1) == "\x27" && substr($0,length($0),1) == "\x27") {
        print substr($0, 2, length($0)-2)
      } else {
        print $0
      }
      exit
    }
  ' "$file"
}

# -----------------------------------------------------------------------------
# Run loop (Phase B: real substrate + assertions.sh).
# -----------------------------------------------------------------------------
any_fail=0
any_skip=0
i=0
for test_dir in "${discovered_tests[@]}"; do
  i=$((i + 1))
  basename=${test_dir##*/}

  # --- 1. Validate test.yaml --------------------------------------------------
  yaml_err_file="/tmp/kiln-test-yaml-err.$$-$i"
  if ! "$harness_dir/test-yaml-validate.sh" "$test_dir/test.yaml" 2>"$yaml_err_file" ; then
    diag=$(mktemp)
    awk 'NF { print; exit }' "$yaml_err_file" > "$diag"
    "$harness_dir/tap-emit.sh" "$i" "$basename" skip "$diag"
    rm -f "$yaml_err_file" "$diag"
    any_skip=1
    continue
  fi
  rm -f "$yaml_err_file"

  # --- 2. Read test.yaml metadata --------------------------------------------
  harness_type=$(extract_yaml_scalar "harness-type" "$test_dir/test.yaml")
  expected_exit=$(extract_yaml_scalar "expected-exit" "$test_dir/test.yaml")
  : "${expected_exit:=0}"

  # --- 2b. Resolve test.yaml `env:` + `require-env:` blocks ------------------
  # Parses optional schema fields that let a fixture inject custom env vars
  # into the claude --print subprocess (e.g. Bedrock / Vertex / OpenRouter
  # configs). Per-test scope: each iteration of this loop reads its own
  # fixture's env block and applies it ONLY to its own substrate subshell
  # (step 7 below), so different fixtures in the same run can target
  # different providers without env leaking between them.
  if env_parse_out=$(node "$harness_dir/parse-test-yaml-env.mjs" "$test_dir/test.yaml" 2>/dev/null); then
    test_yaml_env_json="$env_parse_out"
  else
    test_yaml_env_json='{"env":{},"missingRequiredEnvs":[]}'
  fi
  # Extract missing-required list (one var per line). Skip the test if any
  # caller-env requirement is unset — gives clean CI behavior on machines
  # without 3rd-party provider creds.
  missing_required_envs=$(printf '%s' "$test_yaml_env_json" | jq -r '.missingRequiredEnvs[]?' 2>/dev/null || true)
  if [[ -n "$missing_required_envs" ]]; then
    diag=$(mktemp)
    {
      echo "skipped: test.yaml require-env vars unset in caller environment:"
      printf '%s' "$missing_required_envs" | sed 's/^/  - /'
    } > "$diag"
    "$harness_dir/tap-emit.sh" "$i" "$basename" skip "$diag"
    rm -f "$diag"
    any_skip=1
    continue
  fi

  # --- 3. Check required inputs ----------------------------------------------
  if [[ ! -f "$test_dir/inputs/initial-message.txt" ]]; then
    diag=$(mktemp); echo "missing required inputs/initial-message.txt" > "$diag"
    "$harness_dir/tap-emit.sh" "$i" "$basename" skip "$diag"
    rm -f "$diag"; any_skip=1; continue
  fi
  if [[ ! -f "$test_dir/assertions.sh" ]]; then
    diag=$(mktemp); echo "missing required assertions.sh" > "$diag"
    "$harness_dir/tap-emit.sh" "$i" "$basename" skip "$diag"
    rm -f "$diag"; any_skip=1; continue
  fi

  # --- 4. Create scratch dir -------------------------------------------------
  if ! scratch_dir=$("$harness_dir/scratch-create.sh" 2>/tmp/kiln-scratch-err.$$) ; then
    diag=$(mktemp); awk 'NF { print; exit }' /tmp/kiln-scratch-err.$$ > "$diag"
    "$harness_dir/tap-emit.sh" "$i" "$basename" skip "$diag"
    rm -f "$diag" /tmp/kiln-scratch-err.$$; any_skip=1; continue
  fi
  rm -f /tmp/kiln-scratch-err.$$
  scratch_uuid=${scratch_dir##*/kiln-test-}

  # --- 5. Seed fixtures ------------------------------------------------------
  if ! "$harness_dir/fixture-seeder.sh" "$test_dir" "$scratch_dir" ; then
    diag=$(mktemp); echo "fixture-seeder.sh failed for $test_dir" > "$diag"
    "$harness_dir/tap-emit.sh" "$i" "$basename" skip "$diag"
    rm -f "$diag"; any_skip=1
    # Retain scratch for diagnosis.
    continue
  fi

  # --- 6. Set up per-test env + log paths ------------------------------------
  transcript_path="$logs_dir/kiln-test-${scratch_uuid}-transcript.ndjson"
  snapshot_path="$logs_dir/kiln-test-${scratch_uuid}-scratch.txt"
  verdict_md_path="$logs_dir/kiln-test-${scratch_uuid}.md"
  verdict_json_path="$logs_dir/kiln-test-${scratch_uuid}-verdict.json"
  # Touch transcript up-front so the watcher doesn't trip on a missing file.
  : > "$transcript_path"

  export KILN_TEST_SCRATCH_DIR="$scratch_dir"
  export KILN_TEST_NAME="$basename"
  export KILN_TEST_TRANSCRIPT="$transcript_path"
  export KILN_TEST_SCRATCH_SNAPSHOT="$snapshot_path"
  export KILN_TEST_STALL_WINDOW="$watcher_stall_window_seconds"
  export KILN_TEST_POLL_INTERVAL="$watcher_poll_interval_seconds"

  # --- 7. Background the substrate; foreground the watcher ------------------
  # Substrate runs in background so watcher can monitor. Watcher exits when
  # subprocess exits naturally OR when it SIGTERMs on stall.
  #
  # Per-test env scoping (FR — third-party model support): the substrate
  # is invoked from a SUBSHELL that exports any test.yaml `env:` vars
  # locally. Subshell exit cleans up the env additions, so test N+1's
  # substrate starts from the parent shell's env unaltered. This is what
  # lets a single test run mix Anthropic-default fixtures and 3rd-party-
  # provider fixtures without one polluting the other.
  set +e
  (
    while IFS= read -r kv; do
      [[ -z "$kv" ]] && continue
      # `kv` is a single line of the form "KEY=value". Use eval to make
      # it a real export — but only after splitting safely.
      key="${kv%%=*}"
      val="${kv#*=}"
      export "$key=$val"
    done < <(printf '%s' "$test_yaml_env_json" | jq -r '.env | to_entries[]? | "\(.key)=\(.value)"' 2>/dev/null || true)
    "$harness_dir/dispatch-substrate.sh" "$harness_type" "$scratch_dir" "$test_dir" "$plugin_root"
  ) &
  substrate_pid=$!

  "$harness_dir/watcher-runner.sh" "$scratch_dir" "$substrate_pid" "$transcript_path" \
    "$test_dir/test.yaml" "$verdict_json_path" "$verdict_md_path"

  wait "$substrate_pid"
  subprocess_exit=$?
  set -e

  # --- 8. Check verdict: stalled trumps exit-code check ----------------------
  if [[ -f $verdict_json_path ]] && grep -q '"classification": "stalled"' "$verdict_json_path"; then
    diag=$(mktemp)
    {
      echo "classification: \"stalled\""
      echo "scratch-uuid: \"$scratch_uuid\""
      echo "scratch-retained: \"$scratch_dir/\""
      echo "verdict-report: \"$verdict_md_path\""
      echo "transcript: \"$transcript_path\""
      echo "stall-window-seconds: $watcher_stall_window_seconds"
    } > "$diag"
    "$harness_dir/tap-emit.sh" "$i" "$basename" fail "$diag"
    rm -f "$diag"
    any_fail=1
    continue
  fi

  # --- 9. Check subprocess exit matches expected-exit ------------------------
  if [[ $subprocess_exit -ne $expected_exit ]]; then
    diag=$(mktemp)
    {
      echo "classification: \"failed\""
      echo "scratch-uuid: \"$scratch_uuid\""
      echo "scratch-retained: \"$scratch_dir/\""
      echo "verdict-report: \"$verdict_md_path\""
      echo "transcript: \"$transcript_path\""
      echo "expected-exit: $expected_exit"
      echo "actual-exit: $subprocess_exit"
    } > "$diag"
    "$harness_dir/tap-emit.sh" "$i" "$basename" fail "$diag"
    rm -f "$diag"
    any_fail=1
    # Scratch retained on fail per contracts §4.
    continue
  fi

  # --- 9. Run assertions.sh --------------------------------------------------
  assertion_stdout=$(mktemp)
  assertion_stderr=$(mktemp)
  set +e
  (
    cd "$scratch_dir"
    bash "$test_dir/assertions.sh"
  ) > "$assertion_stdout" 2> "$assertion_stderr"
  assertion_exit=$?
  set -e

  if [[ $assertion_exit -ne 0 ]]; then
    diag=$(mktemp)
    {
      echo "classification: \"assertion-failed\""
      echo "scratch-uuid: \"$scratch_uuid\""
      echo "scratch-retained: \"$scratch_dir/\""
      echo "verdict-report: \"$verdict_md_path\""
      echo "transcript: \"$transcript_path\""
      echo "assertion-exit: $assertion_exit"
      echo "assertion-stdout: |"
      sed 's/^/  /' "$assertion_stdout"
      echo "assertion-stderr: |"
      sed 's/^/  /' "$assertion_stderr"
    } > "$diag"
    "$harness_dir/tap-emit.sh" "$i" "$basename" fail "$diag"
    rm -f "$diag" "$assertion_stdout" "$assertion_stderr"
    any_fail=1
    # Scratch retained on fail.
    continue
  fi

  # --- 10. Pass path: cleanup scratch, emit `ok` -----------------------------
  rm -f "$assertion_stdout" "$assertion_stderr"
  rm -rf "$scratch_dir"
  "$harness_dir/tap-emit.sh" "$i" "$basename" pass
done

# -----------------------------------------------------------------------------
# Aggregate exit code per contracts §2.
# -----------------------------------------------------------------------------
if (( any_fail > 0 )); then
  exit 1
fi
if (( any_skip > 0 )); then
  exit 2
fi
exit 0
