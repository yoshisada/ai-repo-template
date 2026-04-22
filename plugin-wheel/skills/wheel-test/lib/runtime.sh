#!/usr/bin/env bash
# wheel test runtime library — all wt_* functions per
# specs/wheel-test-skill/contracts/interfaces.md
#
# Sourced by plugin-wheel/skills/wheel-test/SKILL.md.
# All functions are synchronous, return 0 on success, non-zero on failure.
# Functions print results to stdout; state is passed via args or read-only WT_* globals.
# No function writes to .wheel/state_*.json or advances cursors — that's activate.sh + hooks (FR-016).

set -uo pipefail

# ---------------------------------------------------------------------------
# Globals (read-only after wt_init_run_clock)
# ---------------------------------------------------------------------------
: "${WT_REPO_ROOT:=$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
WT_TESTS_DIR="${WT_REPO_ROOT}/workflows/tests"
WT_WHEEL_DIR="${WT_REPO_ROOT}/.wheel"
WT_STATE_GLOB="${WT_WHEEL_DIR}/state_*.json"
WT_HISTORY_SUCCESS="${WT_WHEEL_DIR}/history/success"
WT_HISTORY_FAILURE="${WT_WHEEL_DIR}/history/failure"
WT_HISTORY_STOPPED="${WT_WHEEL_DIR}/history/stopped"
WT_LOG_FILE="${WT_WHEEL_DIR}/logs/wheel.log"
WT_REPORT_DIR="${WT_WHEEL_DIR}/logs"
WT_ACTIVATE_SH="${WT_REPO_ROOT}/plugin-wheel/bin/activate.sh"
WT_RUN_TIMESTAMP="${WT_RUN_TIMESTAMP:-}"
WT_LOG_BASELINE="${WT_LOG_BASELINE:-0}"
WT_START_EPOCH="${WT_START_EPOCH:-}"
export WT_REPO_ROOT WT_TESTS_DIR WT_WHEEL_DIR WT_STATE_GLOB \
       WT_HISTORY_SUCCESS WT_HISTORY_FAILURE WT_HISTORY_STOPPED \
       WT_LOG_FILE WT_REPORT_DIR WT_ACTIVATE_SH \
       WT_RUN_TIMESTAMP WT_LOG_BASELINE WT_START_EPOCH

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

# Sets WT_RUN_TIMESTAMP (UTC ISO-8601) and WT_START_EPOCH. No output.
wt_init_run_clock() {
  WT_RUN_TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
  WT_START_EPOCH="$(date +%s)"
  export WT_RUN_TIMESTAMP WT_START_EPOCH
}

# FR-014 — refuse to run if workflows/tests/ has no .json files.
wt_require_nonempty_tests_dir() {
  if [[ ! -d "$WT_TESTS_DIR" ]]; then
    echo "wheel test: workflows/tests/ directory not found at $WT_TESTS_DIR" >&2
    return 1
  fi
  shopt -s nullglob
  local files=("$WT_TESTS_DIR"/*.json)
  shopt -u nullglob
  if (( ${#files[@]} == 0 )); then
    echo "wheel test: no .json workflow files in $WT_TESTS_DIR" >&2
    return 1
  fi
  return 0
}

# FR-001 — print one absolute path per workflow JSON, newline-separated.
wt_discover_workflows() {
  shopt -s nullglob
  local files=("$WT_TESTS_DIR"/*.json)
  shopt -u nullglob
  if (( ${#files[@]} == 0 )); then
    return 1
  fi
  local f
  for f in "${files[@]}"; do
    printf '%s\n' "$f"
  done
}

# FR-007 — refuse to proceed if any .wheel/state_*.json files exist.
wt_require_clean_state() {
  shopt -s nullglob
  local orphans=("$WT_WHEEL_DIR"/state_*.json)
  shopt -u nullglob
  if (( ${#orphans[@]} > 0 )); then
    echo "wheel test: pre-existing state files detected — refuse to proceed:" >&2
    local o
    for o in "${orphans[@]}"; do
      echo "  $o" >&2
    done
    echo "wheel test: archive them (or run /wheel:wheel-stop) before re-running." >&2
    return 1
  fi
  return 0
}

# FR-009 — print the current line count of wheel.log (0 if missing).
wt_record_log_baseline() {
  if [[ -f "$WT_LOG_FILE" ]]; then
    wc -l <"$WT_LOG_FILE" | tr -d ' '
  else
    printf '0\n'
  fi
}

# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------

# FR-002 — print the sorted unique set of step types in a workflow JSON.
wt_step_types() {
  local wf="$1"
  jq -r '.steps[].type' "$wf" 2>/dev/null | sort -u
}

# FR-002 — classify into phase 1|2|3|4 based on step types. Precedence: team > workflow > agent > phase1.
wt_classify_workflow() {
  local wf="$1"
  local types
  types="$(wt_step_types "$wf")" || return 1
  # Check in precedence order. "teammate" and any "team*" type → Phase 4.
  if grep -Eq '^(teammate|team[_-].*|team)$' <<<"$types"; then
    printf '4\n'
    return 0
  fi
  if grep -q '^workflow$' <<<"$types"; then
    printf '3\n'
    return 0
  fi
  if grep -q '^agent$' <<<"$types"; then
    printf '2\n'
    return 0
  fi
  printf '1\n'
}

# FR-005 — expected outcome from basename. Prints "success" or "failure".
# Only workflows whose basename ends with "-fail" (or equals "fail") are
# expected-failure fixtures. Names like "team-partial-failure" describe
# workflows that HANDLE a failing child but are themselves expected to succeed,
# so they must not match.
wt_expected_outcome() {
  local wf="$1"
  local base
  base="$(basename "$wf" .json)"
  case "$base" in
    *-fail|fail) printf 'failure\n' ;;
    *)           printf 'success\n' ;;
  esac
}

# ---------------------------------------------------------------------------
# Execution
# ---------------------------------------------------------------------------

# FR-003/FR-004 — call activate.sh. Prints basename (without .json) to stdout.
# Returns non-zero if activate.sh itself fails.
wt_activate() {
  local wf="$1"
  local base
  base="$(basename "$wf" .json)"
  printf '%s\n' "$base"
  # activate.sh expects the workflow name (or absolute path for local workflows);
  # the existing wheel:wheel-run pattern passes the workflow file argument unchanged.
  "$WT_ACTIVATE_SH" "$wf" >&2
}

# FR-004/FR-010/FR-015 — poll for archive file matching {basename}-*-*.json.
# Args: $1 = workflow basename, $2 = timeout seconds.
# Prints absolute archive path on success; prints "TIMEOUT" and returns 2 on timeout;
# prints "MISSING" and returns 3 if the state file vanished without an archive.
# Portable file mtime as epoch seconds (macOS stat -f, Linux stat -c).
_wt_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# Pick the newest archive whose mtime is >= min_epoch. Prevents matching
# stale archives from earlier sessions that share the same workflow name.
_wt_newest_archive_since() {
  local base="$1"
  local min_epoch="$2"
  shopt -s nullglob
  local candidates=(
    "$WT_HISTORY_SUCCESS/${base}-"*-*.json
    "$WT_HISTORY_FAILURE/${base}-"*-*.json
    "$WT_HISTORY_STOPPED/${base}-"*-*.json
  )
  shopt -u nullglob
  (( ${#candidates[@]} == 0 )) && return 1
  local best="" best_mt=0 f mt
  for f in "${candidates[@]}"; do
    mt="$(_wt_mtime "$f")"
    [[ -z "$mt" ]] && continue
    (( mt < min_epoch )) && continue
    if (( mt > best_mt )); then
      best="$f"
      best_mt="$mt"
    fi
  done
  [[ -n "$best" ]] || return 1
  printf '%s\n' "$best"
  return 0
}

wt_wait_for_archive() {
  local base="$1"
  local timeout="$2"
  local min_epoch="${3:-$WT_START_EPOCH}"
  local deadline=$(( $(date +%s) + timeout ))
  local found=""
  while (( $(date +%s) < deadline )); do
    if found="$(_wt_newest_archive_since "$base" "$min_epoch")"; then
      printf '%s\n' "$found"
      return 0
    fi
    # If there is no in-flight state file AND no archive, mark MISSING.
    shopt -s nullglob
    local inflight=("$WT_WHEEL_DIR"/state_*.json)
    shopt -u nullglob
    if (( ${#inflight[@]} == 0 )); then
      # No state, no archive — give the hook one more grace second.
      sleep 1
      if found="$(_wt_newest_archive_since "$base" "$min_epoch")"; then
        printf '%s\n' "$found"
        return 0
      fi
      printf 'MISSING\n'
      return 3
    fi
    sleep 1
  done
  printf 'TIMEOUT\n'
  return 2
}

# FR-008 — list orphan .wheel/state_*.json files (newline-separated).
wt_detect_orphans() {
  shopt -s nullglob
  local orphans=("$WT_WHEEL_DIR"/state_*.json)
  shopt -u nullglob
  local o
  for o in "${orphans[@]}"; do
    printf '%s\n' "$o"
  done
  return 0
}

# Helper: derive phase from archive path.
_wt_archive_status() {
  local archive="$1"
  case "$archive" in
    "$WT_HISTORY_SUCCESS"/*) printf 'success\n' ;;
    "$WT_HISTORY_FAILURE"/*) printf 'failure\n' ;;
    "$WT_HISTORY_STOPPED"/*) printf 'stopped\n' ;;
    *)                       printf 'unknown\n' ;;
  esac
}

# ---------------------------------------------------------------------------
# Run-env bridging (cross-BashCall state)
# ---------------------------------------------------------------------------
#
# Each Bash tool call gets a fresh shell, so we persist the run identifiers
# (timestamp, baseline, start epoch) into an env snapshot file. wt_load_run_env
# reads the most recent snapshot and exports the globals so later Bash calls
# can re-join the run.

_wt_latest_env_file() {
  ls -1t "${WT_WHEEL_DIR}/logs/".wheel-test-phases-*.env 2>/dev/null | head -n1
}

wt_load_run_env() {
  local f
  f="$(_wt_latest_env_file)"
  if [[ -z "$f" || ! -f "$f" ]]; then
    echo "wt_load_run_env: no phases env snapshot found" >&2
    return 1
  fi
  # Only source KEY=VALUE lines; skip PHASEN <path> lines.
  local line key val
  while IFS= read -r line; do
    case "$line" in
      WT_RUN_TIMESTAMP=*|WT_LOG_BASELINE=*|WT_START_EPOCH=*)
        key="${line%%=*}"
        val="${line#*=}"
        printf -v "$key" '%s' "$val"
        export "$key"
        ;;
    esac
  done <"$f"
  return 0
}

# ---------------------------------------------------------------------------
# Phase 1 — bookkeeping + waiter
# ---------------------------------------------------------------------------

_wt_phase1_starts_tsv() {
  printf '%s\n' "${WT_WHEEL_DIR}/logs/.wheel-test-phase1-starts-${WT_RUN_TIMESTAMP}.tsv"
}

# Record the start epoch for a Phase 1 workflow.
wt_record_phase1_start() {
  local wf="$1"
  local base
  base="$(basename "$wf" .json)"
  printf '%s\t%s\n' "$base" "$(date +%s)" >>"$(_wt_phase1_starts_tsv)"
}

# FR-003/FR-008/FR-010/FR-015 — Phase 1 waiter.
# Reads PHASE1 entries from the env snapshot, waits on each with a 60s timeout,
# records results, sweeps for orphans. Assumes activation has already been
# performed by the invoker as separate Bash tool calls.
wt_phase1_wait_all() {
  local env_file
  env_file="$(_wt_latest_env_file)"
  [[ -n "$env_file" && -f "$env_file" ]] || { echo "wt_phase1_wait_all: missing env snapshot" >&2; return 1; }
  local starts_tsv
  starts_tsv="$(_wt_phase1_starts_tsv)"
  declare -A starts_map=()
  if [[ -f "$starts_tsv" ]]; then
    local b e
    while IFS=$'\t' read -r b e; do
      starts_map["$b"]="$e"
    done <"$starts_tsv"
  fi
  local tag wf base expected archive rc duration status notes arch_status start_epoch now
  while IFS=' ' read -r tag wf; do
    [[ "$tag" == "PHASE1" ]] || continue
    [[ -z "$wf" ]] && continue
    base="$(basename "$wf" .json)"
    expected="$(wt_expected_outcome "$wf")"
    start_epoch="${starts_map[$base]:-$WT_START_EPOCH}"
    archive="$(wt_wait_for_archive "$base" 60 "$start_epoch")"
    rc=$?
    now="$(date +%s)"
    duration=$(( now - start_epoch ))
    notes=""
    if (( rc == 0 )); then
      arch_status="$(_wt_archive_status "$archive")"
      case "$arch_status" in
        success) status="pass" ;;
        failure) status="fail" ;;
        stopped) status="stopped" ; notes="stopped unexpectedly" ;;
        *)       status="fail"    ; notes="unknown archive location" ;;
      esac
    elif (( rc == 2 )); then
      status="timeout" ; archive="" ; notes="phase 1 60s timeout"
    elif (( rc == 3 )); then
      status="missing-archive" ; archive="" ; notes="state vanished without archive"
    else
      status="fail" ; archive="" ; notes="wait_for_archive rc=$rc"
    fi
    wt_record_result "$base" "1" "$expected" "$status" "$duration" "$archive" "$notes"
  done <"$env_file"
  local orph
  while IFS= read -r orph; do
    [[ -z "$orph" ]] && continue
    wt_record_result "$(basename "$orph" .json)" "1" "n/a" "orphaned" "0" "" "orphan state after phase 1"
  done < <(wt_detect_orphans)
  return 0
}

# ---------------------------------------------------------------------------
# Phase 2/3/4 — single-workflow waiter
# ---------------------------------------------------------------------------

# FR-004/FR-008/FR-010/FR-015/FR-018 — Wait on one serial-phase workflow and
# record its result. Called ONCE per workflow, AFTER the invoker has issued
# the activate.sh call as its own separate Bash tool invocation.
wt_wait_and_record_serial() {
  local phase="$1"
  local wf="$2"
  local start_epoch="${3:-$(date +%s)}"
  local base expected archive rc duration status notes arch_status timeout
  timeout=60
  (( phase == 4 )) && timeout=120
  base="$(basename "$wf" .json)"
  expected="$(wt_expected_outcome "$wf")"
  archive="$(wt_wait_for_archive "$base" "$timeout" "$start_epoch")"
  rc=$?
  duration=$(( $(date +%s) - start_epoch ))
  notes=""
  if (( rc == 0 )); then
    arch_status="$(_wt_archive_status "$archive")"
    case "$arch_status" in
      success) status="pass" ;;
      failure) status="fail" ;;
      stopped) status="stopped" ; notes="stopped unexpectedly" ;;
      *)       status="fail"    ; notes="unknown archive location" ;;
    esac
  elif (( rc == 2 )); then
    status="timeout" ; archive="" ; notes="phase $phase ${timeout}s timeout"
  elif (( rc == 3 )); then
    status="missing-archive" ; archive="" ; notes="state vanished without archive"
  else
    status="fail" ; archive="" ; notes="wait_for_archive rc=$rc"
  fi
  wt_record_result "$base" "$phase" "$expected" "$status" "$duration" "$archive" "$notes"
  local orph
  while IFS= read -r orph; do
    [[ -z "$orph" ]] && continue
    wt_record_result "$(basename "$orph" .json)" "$phase" "n/a" "orphaned" "0" "" "orphan state after $base"
  done < <(wt_detect_orphans)
  return 0
}

# ---------------------------------------------------------------------------
# Results & reporting
# ---------------------------------------------------------------------------

_wt_results_tsv() {
  printf '%s\n' "${WT_WHEEL_DIR}/logs/.wheel-test-results-${WT_RUN_TIMESTAMP}.tsv"
}

# Append a TAB-separated result row. Replaces TABs in notes with spaces.
wt_record_result() {
  local workflow="$1"
  local phase="$2"
  local expected="$3"
  local status="$4"
  local duration="$5"
  local archive="$6"
  local notes="${7:-}"
  notes="${notes//	/ }"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$workflow" "$phase" "$expected" "$status" "$duration" "$archive" "$notes" \
    >> "$(_wt_results_tsv)"
}

# FR-009 — tail wheel.log from baseline+1 and grep for error markers.
wt_collect_hook_errors() {
  [[ -f "$WT_LOG_FILE" ]] || return 0
  local start=$(( WT_LOG_BASELINE + 1 ))
  tail -n +"$start" "$WT_LOG_FILE" 2>/dev/null | grep -E 'ERROR|FAIL|stalled' || true
}

# FR-005/FR-018 — reconcile actual status against expected outcome.
# Rewrites the TSV so expected-failure workflows that archived to failure/ become pass (with note),
# expected-success workflows archived to failure/ are fail, stopped maps to fail with "stopped unexpectedly".
wt_reconcile_expected_failures() {
  local tsv
  tsv="$(_wt_results_tsv)"
  [[ -f "$tsv" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  local workflow phase expected status duration archive notes new_status new_notes actual
  while IFS=$'\t' read -r workflow phase expected status duration archive notes; do
    new_status="$status"
    new_notes="$notes"
    # Only reconcile rows with a real archive path. Timeout / missing-archive /
    # orphan rows have no archive and should not be rewritten. Deriving the
    # rewrite from (expected, archive) rather than (expected, status) makes
    # this function idempotent — running it twice produces the same output.
    if [[ -n "$archive" ]]; then
      case "$archive" in
        */history/success/*) actual="success" ;;
        */history/failure/*) actual="failure" ;;
        */history/stopped/*) actual="stopped" ;;
        *)                   actual="unknown" ;;
      esac
      if [[ "$actual" == "stopped" ]]; then
        new_status="fail"
        new_notes="stopped unexpectedly"
      elif [[ "$actual" == "unknown" ]]; then
        new_status="fail"
        new_notes="unknown archive location"
      elif [[ "$actual" == "$expected" ]]; then
        new_status="pass"
        if [[ "$expected" == "failure" ]]; then
          new_notes="expected failure archived correctly"
        else
          new_notes=""
        fi
      else
        new_status="fail"
        if [[ "$expected" == "failure" ]]; then
          new_notes="expected failure but archived to success/"
        else
          new_notes="expected success but archived to failure/"
        fi
      fi
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$workflow" "$phase" "$expected" "$new_status" "$duration" "$archive" "$new_notes" >>"$tmp"
  done <"$tsv"
  mv "$tmp" "$tsv"
}

# FR-011 — build the markdown report body. Prints full markdown to stdout.
wt_build_report() {
  local tsv
  tsv="$(_wt_results_tsv)"
  local total_duration=$(( $(date +%s) - WT_START_EPOCH ))
  local passed=0 failed=0 orphaned=0 hook_errors=0
  local line workflow phase expected status duration archive notes
  if [[ -f "$tsv" ]]; then
    while IFS=$'\t' read -r workflow phase expected status duration archive notes; do
      case "$status" in
        pass)             passed=$(( passed + 1 )) ;;
        orphaned)         orphaned=$(( orphaned + 1 )) ;;
        fail|timeout|missing-archive|stopped) failed=$(( failed + 1 )) ;;
      esac
    done <"$tsv"
  fi

  local hook_error_lines
  hook_error_lines="$(wt_collect_hook_errors || true)"
  if [[ -n "$hook_error_lines" ]]; then
    hook_errors="$(printf '%s\n' "$hook_error_lines" | wc -l | tr -d ' ')"
  fi

  local verdict
  if (( failed == 0 && orphaned == 0 && hook_errors == 0 )); then
    verdict="PASS"
  else
    verdict="FAIL ($failed failed, $orphaned orphaned, $hook_errors hook errors)"
  fi

  printf '# Wheel Test Run — %s\n\n' "$WT_RUN_TIMESTAMP"
  printf '- **Timestamp (UTC)**: %s\n' "$WT_RUN_TIMESTAMP"
  printf '- **Total duration**: %ss\n' "$total_duration"
  printf '- **Overall verdict**: %s\n\n' "$verdict"

  printf '## Summary\n\n'
  printf '%d passed / %d failed / %d orphaned / %d hook errors\n\n' \
    "$passed" "$failed" "$orphaned" "$hook_errors"

  printf '## Per-Workflow Results\n\n'
  printf '| Workflow | Phase | Expected | Status | Duration | Archive | Notes |\n'
  printf '|---|---|---|---|---|---|---|\n'
  if [[ -f "$tsv" ]]; then
    while IFS=$'\t' read -r workflow phase expected status duration archive notes; do
      local arch_display="${archive##*/}"
      [[ -z "$arch_display" ]] && arch_display="-"
      printf '| %s | %s | %s | %s | %ss | %s | %s |\n' \
        "$workflow" "$phase" "$expected" "$status" "$duration" "$arch_display" "${notes:--}"
    done <"$tsv"
  fi
  printf '\n'

  # Orphan section — only if orphans exist.
  if (( orphaned > 0 )); then
    printf '## Orphan State Files\n\n'
    if [[ -f "$tsv" ]]; then
      while IFS=$'\t' read -r workflow phase expected status duration archive notes; do
        if [[ "$status" == "orphaned" ]]; then
          printf -- '- %s (%s)\n' "$workflow" "$notes"
        fi
      done <"$tsv"
    fi
    printf '\n'
  fi

  # Hook error section — only if matches exist.
  if [[ -n "$hook_error_lines" ]]; then
    printf '## Hook Error Excerpts\n\n'
    printf '```\n%s\n```\n\n' "$hook_error_lines"
  fi

  # Reproduction commands section — one activate.sh line per workflow.
  printf '## Reproduction Commands\n\n'
  printf '```bash\n'
  local wf
  while IFS= read -r wf; do
    [[ -z "$wf" ]] && continue
    printf './plugin-wheel/bin/activate.sh %s\n' "$wf"
  done < <(wt_discover_workflows)
  printf '```\n'
}

# FR-012 — persist the report to .wheel/logs/test-run-<ts>.md AND echo it.
# Prints the absolute report path on the final line.
wt_emit_report() {
  local body="$1"
  local path="${WT_REPORT_DIR}/test-run-${WT_RUN_TIMESTAMP}.md"
  mkdir -p "$WT_REPORT_DIR"
  printf '%s' "$body" >"$path"
  printf '%s\n' "$body"
  printf '%s\n' "$path"
}

# FR-013 — final verdict. Returns 0 if PASS, 1 if FAIL.
wt_final_verdict() {
  local tsv
  tsv="$(_wt_results_tsv)"
  local failed=0 orphaned=0 hook_errors=0
  local workflow phase expected status duration archive notes
  if [[ -f "$tsv" ]]; then
    while IFS=$'\t' read -r workflow phase expected status duration archive notes; do
      case "$status" in
        orphaned)                                 orphaned=$(( orphaned + 1 )) ;;
        fail|timeout|missing-archive|stopped)     failed=$(( failed + 1 )) ;;
      esac
    done <"$tsv"
  fi
  local hook_error_lines
  hook_error_lines="$(wt_collect_hook_errors || true)"
  if [[ -n "$hook_error_lines" ]]; then
    hook_errors="$(printf '%s\n' "$hook_error_lines" | wc -l | tr -d ' ')"
  fi
  if (( failed == 0 && orphaned == 0 && hook_errors == 0 )); then
    printf 'PASS\n'
    return 0
  fi
  printf 'FAIL (%d failed, %d orphaned, %d hook errors)\n' \
    "$failed" "$orphaned" "$hook_errors"
  return 1
}
