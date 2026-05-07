#!/usr/bin/env bash
# parse-test-yaml-env.mjs coverage. The parser drives the TAP harness's
# 3rd-party-model fixture support — its contract is what
# wheel-test-runner.sh relies on to (a) extract per-test env vars,
# (b) substitute ${VAR} from caller env, and (c) report unset
# require-env vars so the runner can SKIP cleanly. Each assertion
# below pins one spoke of that contract; a regression here flips
# 3rd-party fixtures from clean SKIP to either silent run-on-default
# or hard FAIL.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PARSER="${REPO_ROOT}/plugin-wheel/scripts/harness/parse-test-yaml-env.mjs"

if [[ ! -f "$PARSER" ]]; then
  echo "FAIL: parser missing at $PARSER" >&2
  exit 1
fi

STAGE="$(mktemp -d -t parse-env-XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

PASS=0
FAIL=0

run_case() {
  local label="$1" yaml="$2" env_setup="$3" expected_jq="$4" expected_value="$5"
  local f="$STAGE/$label.yaml"
  printf '%s\n' "$yaml" > "$f"
  local out
  out=$(eval "$env_setup node \"$PARSER\" \"$f\"" 2>&1) || {
    echo "  [FAIL] $label: parser exited non-zero — $out" >&2
    FAIL=$((FAIL + 1))
    return
  }
  local actual
  actual=$(printf '%s' "$out" | jq -r "$expected_jq" 2>/dev/null) || {
    echo "  [FAIL] $label: jq query failed against output: $out" >&2
    FAIL=$((FAIL + 1))
    return
  }
  if [[ "$actual" == "$expected_value" ]]; then
    echo "  [OK] $label"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] $label: expected '$expected_value', got '$actual'" >&2
    echo "    full output: $out" >&2
    FAIL=$((FAIL + 1))
  fi
}

# 1. No env block → empty env + no missing
run_case "no-env-block" \
  $'harness-type: plugin-skill\ndescription: "no env"' \
  "" \
  '.env | length' \
  "0"

# 2. Plain env values (no substitution) survive verbatim
run_case "plain-values" \
  $'env:\n  ANTHROPIC_MODEL: "haiku"\n  ANTHROPIC_BASE_URL: https://api.example.com' \
  "" \
  '.env.ANTHROPIC_MODEL' \
  "haiku"

# 3. ${VAR} substitution from caller env
run_case "var-substitution" \
  $'env:\n  TOKEN: "${MY_TEST_TOKEN}"' \
  "MY_TEST_TOKEN=abc123" \
  '.env.TOKEN' \
  "abc123"

# 4. Unset ${VAR} reported in missingRequiredEnvs (gate fires)
run_case "unset-var-listed" \
  $'env:\n  TOKEN: "${WHEEL_NEVER_SET_VAR}"' \
  "" \
  '.missingRequiredEnvs[0]' \
  "WHEEL_NEVER_SET_VAR"

# 5. require-env explicit list — unset names propagate
run_case "require-env-unset" \
  $'require-env:\n  - WHEEL_DEMO_REQ_A\n  - WHEEL_DEMO_REQ_B' \
  "" \
  '.missingRequiredEnvs | length' \
  "2"

# 6. require-env satisfied by caller env
run_case "require-env-set" \
  $'require-env:\n  - WHEEL_DEMO_OK_A' \
  "WHEEL_DEMO_OK_A=1" \
  '.missingRequiredEnvs | length' \
  "0"

# 7. Mixed: env value substitution AND require-env, both satisfied
run_case "mixed-satisfied" \
  $'env:\n  TOKEN: "${WHEEL_DEMO_TOKEN}"\nrequire-env:\n  - WHEEL_DEMO_TOKEN' \
  "WHEEL_DEMO_TOKEN=xyz" \
  '.env.TOKEN' \
  "xyz"

echo
if (( FAIL == 0 )); then
  echo "PASS: parse-test-yaml-env ($PASS/7 assertions)"
  exit 0
else
  echo "FAIL: parse-test-yaml-env ($FAIL/7 assertions failed)"
  exit 1
fi
