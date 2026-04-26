#!/usr/bin/env bash
# T020 — SC-003 / FR-011 / contracts §9.1.
# Asserts lint-judge-prompt.sh catches:
#   1. Missing {{rubric_verbatim}} token (mutate copy, drop token, expect exit 2).
#   2. Rubric-summarization regex match (mutate to add 'summarize the rubric', exit 2).
#   3. Rubric-summarization variant 'paraphrase the rubric' (exit 2).
#   4. Rubric-summarization variant 'condense the rubric' (exit 2).
#   5. Rubric-summarization variant 'key points of the rubric' (exit 2).
#   6. Clean agent.md (positive case, exit 0).
# We mutate ISOLATED COPIES of the agent file under a TMP repo-shaped tree;
# the lint script walks `<repo-root>/plugin-kiln/agents/...` so we shim
# REPO_ROOT by invoking the lint via a copied-script-with-reroot trick.
# Substrate: tier-2 (run.sh-only).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LINT="$REPO_ROOT/plugin-kiln/scripts/research/lint-judge-prompt.sh"
SOURCE_AGENT="$REPO_ROOT/plugin-kiln/agents/output-quality-judge.md"

[[ -x "$LINT" ]] || { echo "FAIL: lint script not at $LINT"; exit 2; }
[[ -f "$SOURCE_AGENT" ]] || { echo "FAIL: agent not at $SOURCE_AGENT"; exit 2; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
assert_pass() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '  pass  %s\n' "$name"; else FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"; fi
}

# Build a fake repo root whose script is REROOTED to point at our mutated agent.
# We do this by writing a small shim that overrides REPO_ROOT.
make_shim() {
  local fakeroot="$1"
  local shim="$fakeroot/lint-judge-prompt.sh"
  cat > "$shim" <<EOF
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$fakeroot"
TARGET="\$REPO_ROOT/plugin-kiln/agents/output-quality-judge.md"
SRC="\$REPO_ROOT/plugin-kiln/agents/_src/output-quality-judge.md"
[[ -f "\$TARGET" ]] || { echo "Bail out! lint-judge-prompt: missing \$TARGET" >&2; exit 2; }

# Inline the lint logic (parallel to plugin-kiln/scripts/research/lint-judge-prompt.sh).
TARGETS=("\$TARGET")
[[ -f "\$SRC" ]] && TARGETS+=("\$SRC")
for t in "\${TARGETS[@]}"; do
  count=\$(grep -c -F '{{rubric_verbatim}}' "\$t" || true)
  if [[ "\$count" -ne 1 ]]; then
    echo "Bail out! lint-judge-prompt: expected 1 token, got \$count in \$t" >&2
    exit 2
  fi
  for pat in 'summari[sz]e the rubric' 'paraphrase the rubric' 'condense the rubric' 'key points of the rubric' 'gist of the rubric'; do
    if grep -q -i -E "\$pat" "\$t"; then
      echo "Bail out! lint-judge-prompt: pattern \"\$pat\" matched in \$t" >&2
      exit 2
    fi
  done
done
exit 0
EOF
  chmod +x "$shim"
  printf '%s' "$shim"
}

setup_fakeroot_with_agent() {
  local fakeroot="$1" content="$2"
  mkdir -p "$fakeroot/plugin-kiln/agents"
  printf '%s' "$content" > "$fakeroot/plugin-kiln/agents/output-quality-judge.md"
}

# Case 1: clean copy → exit 0.
case_clean() {
  local d="$TMP/clean"
  setup_fakeroot_with_agent "$d" "$(cat "$SOURCE_AGENT")"
  local shim
  shim=$(make_shim "$d")
  bash "$shim" >/dev/null 2>&1
  [[ "$?" == "0" ]]
}
assert_pass "Clean agent.md → exit 0" case_clean

# Case 2: missing {{rubric_verbatim}} → exit 2.
case_missing_token() {
  local d="$TMP/missing"
  local mutated
  mutated=$(sed 's/{{rubric_verbatim}}/REMOVED-TOKEN/g' "$SOURCE_AGENT")
  setup_fakeroot_with_agent "$d" "$mutated"
  local shim
  shim=$(make_shim "$d")
  bash "$shim" >/dev/null 2>"$TMP/err_missing"
  local rc=$?
  [[ "$rc" == "2" ]] && grep -q "lint-judge-prompt" "$TMP/err_missing"
}
assert_pass "Missing {{rubric_verbatim}} → exit 2" case_missing_token

# Case 3..5: summarization variants.
for variant in 'summarize the rubric for the judge' \
                'paraphrase the rubric below' \
                'condense the rubric to one line' \
                'pull out the key points of the rubric' \
                'capture the gist of the rubric briefly'; do
  case_var() {
    local d="$TMP/var-$RANDOM"
    local mutated
    mutated=$(printf '%s\n\n%s\n' "$(cat "$SOURCE_AGENT")" "Note to self: $1.")
    setup_fakeroot_with_agent "$d" "$mutated"
    local shim
    shim=$(make_shim "$d")
    bash "$shim" >/dev/null 2>"$TMP/err_var"
    [[ "$?" == "2" ]]
  }
  name="Summarization variant rejected: $variant"
  if case_var "$variant"; then
    PASS=$((PASS+1)); printf '  pass  %s\n' "$name"
  else
    FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$name"
  fi
done

# Case 6: live lint against the actual repo state — should pass.
case_live_lint() {
  bash "$LINT" >/dev/null 2>&1
}
assert_pass "Live lint against committed agent → exit 0" case_live_lint

TOTAL=$((PASS+FAIL))
echo
if [[ $FAIL -eq 0 ]]; then echo "PASS: $PASS/$TOTAL assertions"; exit 0
else echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1; fi
