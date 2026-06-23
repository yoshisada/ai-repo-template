#!/usr/bin/env bash
# minimax-matrix-runner.sh — sequential model × fixture sweep for the
# Bifrost-routed MiniMax test fixtures.
#
# Why this exists: the bifrost-minimax-* fixtures are env-driven — each reads
# ${BIFROST_MODEL_ID} from the environment (see each fixture's test.yaml `env:`
# block). To test more than one MiniMax model (e.g. M2.7 AND M3) without
# duplicating 7 fixture directories per model, this runner re-exports
# BIFROST_MODEL_ID once per model id and re-runs the same fixtures.
#
# STRICTLY SEQUENTIAL by design (the whole point): exactly one live gateway
# call is in flight at any moment, and a configurable pause separates every
# fixture and every model sweep, so a self-hosted Bifrost/MiniMax deployment is
# never rate-limited. It delegates each fixture to the existing
# wheel-test-runner.sh single-test path — no new test/assertion logic here.
#
# Config (resolved from the environment, or from plugin-wheel/.env.test which is
# auto-loaded if present — override the path with WHEEL_ENV_FILE):
#   BIFROST_ENDPOINT        (required) Anthropic-compatible gateway URL
#   BIFROST_API_KEY         (required) gateway key
#   BIFROST_MODEL_IDS       comma-separated model ids to sweep
#                           (falls back to single BIFROST_MODEL_ID)
#   BIFROST_PACING_SECONDS  pause between fixtures + model sweeps (default 5)
#   BIFROST_FORCE=1         skip the endpoint-reachability pre-check
#
# CLI:
#   minimax-matrix-runner.sh [--models a,b] [--pacing N] [--force]
#
# Exit: 0 — all model×fixture runs passed, OR cleanly skipped (creds unset /
#           endpoint unreachable). 1 — at least one model×fixture run failed.
#
# SKIP semantics mirror the fixtures' own `require-env:` gate: when creds are
# absent the run is a clean no-op (exit 0), so CI and offline machines stay
# green without special-casing. The endpoint-reachability probe extends that to
# "creds present but gateway down" (the common case when the gateway is a LAN
# box you're not currently on), which would otherwise surface as a confusing
# cascade of connection-failed fixture FAILs.
set -euo pipefail

harness_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )
repo_root=$( cd -- "$harness_dir/../../.." && pwd )
runner="$harness_dir/wheel-test-runner.sh"

# The 7 Bifrost-routed MiniMax fixtures (directory names under plugin-wheel/tests/).
FIXTURES=(
  bifrost-minimax-smoke
  bifrost-minimax-team-static
  bifrost-minimax-team-single-haiku
  bifrost-minimax-team-haiku-fanout
  bifrost-minimax-team-dynamic
  bifrost-minimax-team-mixed-model
  bifrost-minimax-team-partial-failure
)

# --- CLI overrides -----------------------------------------------------------
cli_models=""
cli_pacing=""
force="${BIFROST_FORCE:-0}"
while (( $# > 0 )); do
  case $1 in
    --models)  cli_models=${2:-}; shift 2 ;;
    --models=*) cli_models=${1#--models=}; shift ;;
    --pacing)  cli_pacing=${2:-}; shift 2 ;;
    --pacing=*) cli_pacing=${1#--pacing=}; shift ;;
    --force)   force=1; shift ;;
    -h|--help) sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- Load .env.test (non-fatal if absent) ------------------------------------
env_file="${WHEEL_ENV_FILE:-$repo_root/plugin-wheel/.env.test}"
if [[ -f "$env_file" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
fi

# --- Resolve config ----------------------------------------------------------
models_raw="${cli_models:-${BIFROST_MODEL_IDS:-${BIFROST_MODEL_ID:-}}}"
pacing="${cli_pacing:-${BIFROST_PACING_SECONDS:-5}}"

skip() { echo "SKIP: minimax-matrix — $1"; exit 0; }

[[ -n "${BIFROST_ENDPOINT:-}" ]] || skip "BIFROST_ENDPOINT unset (set it in $env_file or the environment)"
[[ -n "${BIFROST_API_KEY:-}"  ]] || skip "BIFROST_API_KEY unset"
[[ -n "$models_raw"           ]] || skip "no model ids (set BIFROST_MODEL_IDS or BIFROST_MODEL_ID)"

# Split comma-separated model list into an array, trimming whitespace.
IFS=',' read -r -a MODELS <<< "$models_raw"
trimmed=()
for m in "${MODELS[@]}"; do
  m="${m#"${m%%[![:space:]]*}"}"; m="${m%"${m##*[![:space:]]}"}"
  [[ -n "$m" ]] && trimmed+=("$m")
done
MODELS=("${trimmed[@]}")
(( ${#MODELS[@]} > 0 )) || skip "model list resolved to empty"

# --- Endpoint reachability pre-check (clean SKIP when the gateway is down) ----
if [[ "$force" != "1" ]]; then
  probe_url="${BIFROST_ENDPOINT%/anthropic}"
  if ! curl -sS -m 5 -o /dev/null "$probe_url" 2>/dev/null \
     && ! curl -sS -m 5 -o /dev/null "$BIFROST_ENDPOINT" 2>/dev/null; then
    skip "endpoint $BIFROST_ENDPOINT unreachable (pass --force to run anyway)"
  fi
fi

# --- Sweep: model × fixture, strictly sequential -----------------------------
export BIFROST_ENDPOINT BIFROST_API_KEY
export KILN_TEST_REPO_ROOT="$repo_root"

echo "=== minimax matrix: ${#MODELS[@]} model(s) × ${#FIXTURES[@]} fixtures, pacing=${pacing}s ==="
printf '  models:   %s\n' "${MODELS[*]}"
printf '  endpoint: %s\n\n' "$BIFROST_ENDPOINT"

any_fail=0
first=1
declare -a summary=()
for model in "${MODELS[@]}"; do
  export BIFROST_MODEL_ID="$model"
  echo "----- model: $model -----"
  for fx in "${FIXTURES[@]}"; do
    # Pacing between every run (skip the pause before the very first run).
    if [[ "$first" == "1" ]]; then first=0; else sleep "$pacing"; fi

    set +e
    bash "$runner" wheel "$fx" >/tmp/minimax-matrix-$$.out 2>&1
    rc=$?
    set -e

    case "$rc" in
      0) verdict="PASS" ;;
      2) verdict="skip" ;;
      *) verdict="FAIL"; any_fail=1 ;;
    esac
    printf '  [%-4s] %s :: %s\n' "$verdict" "$model" "$fx"
    if [[ "$verdict" == "FAIL" ]]; then
      sed 's/^/      /' /tmp/minimax-matrix-$$.out | tail -12
    fi
    summary+=("$verdict|$model|$fx")
  done
  echo
done
rm -f /tmp/minimax-matrix-$$.out

# --- Summary -----------------------------------------------------------------
echo "=== summary ==="
pass=0; failc=0; skipc=0
for row in "${summary[@]}"; do
  case "${row%%|*}" in
    PASS) pass=$((pass+1)) ;;
    FAIL) failc=$((failc+1)) ;;
    skip) skipc=$((skipc+1)) ;;
  esac
done
echo "  pass=$pass fail=$failc skip=$skipc (of ${#summary[@]} runs)"

if (( any_fail )); then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
exit 0
