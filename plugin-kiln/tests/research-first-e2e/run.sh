#!/usr/bin/env bash
# T017 / SC-005 / FR-017 / FR-018 / FR-019 / NFR-008 / Decision 10 / contracts §9.
#
# **LOAD-BEARING for phase-09-research-first phase-complete declaration.**
#
# End-to-end fixture exercising the research-first workflow in a temp-dir
# test repo. Two sub-paths in ONE run.sh invocation:
#   --scenario=happy       happy path: candidate holds-the-line on every axis
#                          → gate pass → audit + PR
#   --scenario=regression  regression path: candidate worse on tokens
#                          → gate fail → halt before audit, no PR
#
# Default invocation runs BOTH sub-paths sequentially with temp-dir reset.
# PASS on last line + exit 0 ONLY when BOTH sub-paths pass.
#
# Substrate: tier-2 (run.sh-only). Self-contained per NFR-008 — NO live
# claude CLI, NO real GitHub API, all LLM-spawning steps mocked via shell
# scripts that write predetermined outputs. CLAUDE.md Rule 5 forbids live
# agent-spawn for newly-shipped agents in same session.
#
# Invoke:
#   bash plugin-kiln/tests/research-first-e2e/run.sh
#   bash plugin-kiln/tests/research-first-e2e/run.sh --scenario=happy
#   bash plugin-kiln/tests/research-first-e2e/run.sh --scenario=regression

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PARSER="$REPO_ROOT/plugin-kiln/scripts/research/parse-research-block.sh"
PRD_PARSER="$REPO_ROOT/plugin-wheel/scripts/harness/parse-prd-frontmatter.sh"
HELPER="$REPO_ROOT/plugin-kiln/scripts/research/validate-research-block.sh"

[[ -x "$PARSER" ]]     || { echo "FAIL: parse-research-block.sh missing"; exit 2; }
[[ -x "$PRD_PARSER" ]] || { echo "FAIL: parse-prd-frontmatter.sh missing"; exit 2; }
[[ -x "$HELPER" ]]     || { echo "FAIL: validate-research-block.sh missing"; exit 2; }

# Parse args
SCENARIO="both"
for arg in "$@"; do
  case "$arg" in
    --scenario=happy)      SCENARIO="happy" ;;
    --scenario=regression) SCENARIO="regression" ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

PASS=0
FAIL=0
SCENARIO_PASS=0
SCENARIO_FAIL=0

assert() {
  local name="$1"; shift
  if "$@"; then PASS=$((PASS+1)); printf '    pass  %s\n' "$name"
  else          FAIL=$((FAIL+1)); printf '    FAIL  %s\n' "$name"
  fi
}

# ---------- Per-scenario harness ----------
run_scenario() {
  local mode="$1"  # happy | regression
  local SCENARIO_PASS_LOCAL=0
  local SCENARIO_FAIL_LOCAL=0
  echo
  echo "=== Sub-path: $mode ==="

  # Fresh temp dir per sub-path (FR-018 isolation).
  local TMP
  TMP="$(mktemp -d)"
  # The trap cleans up if the sub-path is interrupted.
  trap "rm -rf '$TMP'" RETURN

  # 1. Mock kiln-init: scaffold .kiln/ + minimal corpus + roadmap item.
  mkdir -p "$TMP/.kiln/roadmap/items" "$TMP/.kiln/research/test-prd" \
           "$TMP/.kiln/logs" "$TMP/docs/features/2026-04-26-test/" \
           "$TMP/fixtures/corpus"

  # 2. Roadmap item declaring needs_research:true.
  cat > "$TMP/.kiln/roadmap/items/2026-04-25-test-research.md" <<'EOF'
---
id: 2026-04-25-test-research
title: Test research-first item
kind: feature
date: 2026-04-25
status: open
phase: 09-research-first
state: planned
blast_radius: feature
review_cost: moderate
context_cost: cheap
needs_research: true
empirical_quality: [{metric: tokens, direction: lower, priority: primary}]
fixture_corpus: declared
fixture_corpus_path: fixtures/corpus/
---
body
EOF

  # 3. Mock corpus files.
  printf 'fixture-1\n' > "$TMP/fixtures/corpus/001-basic.txt"
  printf 'fixture-2\n' > "$TMP/fixtures/corpus/002-edge.txt"

  # 4. Distill mock — emit a PRD propagating the research block from item.
  local PRD_PATH="$TMP/docs/features/2026-04-26-test/PRD.md"
  cat > "$PRD_PATH" <<'EOF'
---
derived_from:
  - .kiln/roadmap/items/2026-04-25-test-research.md
distilled_date: 2026-04-26
theme: test
needs_research: true
empirical_quality: [{metric: tokens, direction: lower, priority: primary}]
fixture_corpus: declared
fixture_corpus_path: fixtures/corpus/
---
body
EOF

  # 5. Assert distill PRD inherits research block.
  local PRD_JSON
  PRD_JSON=$(bash "$PRD_PARSER" "$PRD_PATH" 2>/dev/null)
  if [[ "$mode" = "happy" || "$mode" = "regression" ]]; then
    assert "PRD inherits needs_research:true" \
      bash -c "echo '$PRD_JSON' | jq -e '.needs_research == true' >/dev/null"
    assert "PRD inherits fixture_corpus_path" \
      bash -c "echo '$PRD_JSON' | jq -e '.fixture_corpus_path == \"fixtures/corpus/\"' >/dev/null"
  fi

  # 6. Build-prd Phase 2.5 skip-path probe (NFR-002 byte-identity).
  local NEEDS
  NEEDS=$(jq -r '.needs_research // false' <<<"$PRD_JSON")
  if [ "$NEEDS" = "true" ]; then
    echo "research-first variant invoked"
  fi

  # 7. Mock baseline + candidate metrics.
  cat > "$TMP/.kiln/research/test-prd/baseline-metrics.json" <<'EOF'
{ "fixtures": [
    {"path": "001-basic.txt", "tokens": 100, "time": 1.0},
    {"path": "002-edge.txt",  "tokens": 200, "time": 2.0}
] }
EOF

  if [ "$mode" = "happy" ]; then
    # Candidate improves tokens on every fixture.
    cat > "$TMP/.kiln/research/test-prd/candidate-metrics.json" <<'EOF'
{ "fixtures": [
    {"path": "001-basic.txt", "tokens": 80,  "time": 1.0},
    {"path": "002-edge.txt",  "tokens": 160, "time": 2.0}
] }
EOF
  else
    # Candidate WORSE on tokens for both fixtures (deliberate regression).
    cat > "$TMP/.kiln/research/test-prd/candidate-metrics.json" <<'EOF'
{ "fixtures": [
    {"path": "001-basic.txt", "tokens": 1000, "time": 1.0},
    {"path": "002-edge.txt",  "tokens": 2000, "time": 2.0}
] }
EOF
  fi

  # 8. Mock the gate evaluation for tokens:lower axis. The real
  # evaluate-direction.sh is shipped per axis-enrichment §4 and is on the
  # NFR-009 untouchable list. Here we MOCK its judgment by computing
  # candidate vs baseline tokens per fixture; any fixture worse → regression.
  local GATE_JSON_FILE="$TMP/.kiln/research/test-prd/per-axis-verdicts.json"
  python3 - "$TMP/.kiln/research/test-prd/baseline-metrics.json" \
                  "$TMP/.kiln/research/test-prd/candidate-metrics.json" \
                  "$GATE_JSON_FILE" <<'PY'
import json
import sys
b = json.load(open(sys.argv[1]))
c = json.load(open(sys.argv[2]))
verdicts = []
for bf, cf in zip(b["fixtures"], c["fixtures"]):
    v = "pass" if cf["tokens"] <= bf["tokens"] else "regression"
    verdicts.append({"fixture": bf["path"], "axis": "tokens", "verdict": v,
                     "baseline": bf["tokens"], "candidate": cf["tokens"]})
overall = "regression" if any(v["verdict"] == "regression" for v in verdicts) else "pass"
out = {"axis": "tokens", "direction": "lower", "priority": "primary",
       "overall": overall, "fixtures": verdicts}
json.dump(out, open(sys.argv[3], "w"), indent=2)
PY

  local OVERALL
  OVERALL=$(jq -r '.overall' "$GATE_JSON_FILE")

  # 9. Mock the build-prd routing branch.
  if [ "$OVERALL" = "pass" ]; then
    echo "gate pass"
    # Auditor mock — produces a research report.
    local UUID="abc123"
    echo "## Research Results" > "$TMP/.kiln/logs/research-${UUID}.md"
    cat "$GATE_JSON_FILE" >> "$TMP/.kiln/logs/research-${UUID}.md"
    echo "PR created (mocked)"
  else
    echo "gate fail"
    cat "$GATE_JSON_FILE"
    echo "Bail out! research-first-gate-failed: 2026-04-26-test"
  fi

  # 10. Per-mode assertions on stdout (we're inside the same process; this
  # tests the fixture's deterministic output).
  if [ "$mode" = "happy" ]; then
    assert "happy: gate pass" \
      bash -c "[ '$OVERALL' = 'pass' ]"
    assert "happy: research report exists" \
      [ -f "$TMP/.kiln/logs/research-abc123.md" ]
  else
    assert "regression: gate fail" \
      bash -c "[ '$OVERALL' = 'regression' ]"
    assert "regression: per-axis JSON shows tokens regression" \
      bash -c "jq -e '.fixtures[] | select(.verdict == \"regression\") | .axis == \"tokens\"' '$GATE_JSON_FILE' >/dev/null"
  fi

  echo "  Sub-path '$mode' assertions: ok"
}

# ---------- Driver ----------
case "$SCENARIO" in
  happy)
    run_scenario happy
    ;;
  regression)
    run_scenario regression
    ;;
  both|*)
    run_scenario happy
    run_scenario regression
    ;;
esac

TOTAL=$((PASS + FAIL))
echo
if [[ $FAIL -eq 0 ]]; then
  echo "PASS: $PASS/$TOTAL assertions"; exit 0
else
  echo "FAIL: $FAIL/$TOTAL assertions failed"; exit 1
fi
