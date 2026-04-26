#!/usr/bin/env bash
# evaluate-output-quality.sh — Orchestrator for the kiln:output-quality-judge.
# Wraps judge-config.yaml resolution, pinned-model probing, FR-015 blind
# assignment, FR-016 identical-input control insertion, judge spawn (or mock
# injection per CLAUDE.md Rule 5), envelope de-anonymization, drift halt, and
# stdout pass/regression emission.
#
# Satisfies: FR-013, FR-014, FR-015, FR-016 + plan.md Decision 6 + 7.
# Contract:  specs/research-first-plan-time-agents/contracts/interfaces.md §4.
# Sibling:   plugin-wheel/scripts/harness/evaluate-direction.sh (same stdout
#            contract: pass | regression — consumed by the per-axis gate from
#            specs/research-first-axis-enrichment/contracts/interfaces.md §4).
#
# CLI:
#   evaluate-output-quality.sh \
#     --prd-slug <slug> \
#     --rubric-verbatim <string-or-@file> \
#     --baseline-outputs <abs-dir> \
#     --candidate-outputs <abs-dir> \
#     --fixture-list <abs-path-to-fixture-list-json> \
#     --judge-config <abs-path>
#
# Stdout: a single token — `pass` or `regression`.
# Stderr: bail-out diagnostics per contracts §4 table.
# Exit codes:
#   0 — verdict emitted on stdout
#   2 — Bail out! raised (drift, pinned-model unavailable, malformed config,
#       missing output file, rubric-hash mismatch)
#   3 — composer / resolver propagation failure
#
# Mock-injection (CLAUDE.md Rule 5 — newly-shipped agents not live-spawnable
# in same session):
#   When KILN_TEST_MOCK_JUDGE_DIR is set to a directory, the helper reads
#   <KILN_TEST_MOCK_JUDGE_DIR>/<fixture_id>.json instead of live-spawning the
#   judge. The mock file is the raw blinded envelope as the judge would relay
#   it (axis_id, blinded_verdict, fixture_id, model_used, rationale).

set -euo pipefail
LC_ALL=C
export LC_ALL

bail() {
  printf 'Bail out! %s\n' "$1" >&2
  exit 2
}

prd_slug= rubric= baseline= candidate= fixture_list= judge_config=
while (( $# > 0 )); do
  case $1 in
    --prd-slug) prd_slug=${2:-}; shift 2 ;;
    --rubric-verbatim) rubric=${2:-}; shift 2 ;;
    --baseline-outputs) baseline=${2:-}; shift 2 ;;
    --candidate-outputs) candidate=${2:-}; shift 2 ;;
    --fixture-list) fixture_list=${2:-}; shift 2 ;;
    --judge-config) judge_config=${2:-}; shift 2 ;;
    --help|-h)
      sed -n '1,40p' "$0" >&2
      exit 0
      ;;
    *) bail "evaluate-output-quality: unknown flag: $1" ;;
  esac
done

[[ -n $prd_slug ]] || bail "evaluate-output-quality: missing --prd-slug"
[[ -n $rubric ]] || bail "evaluate-output-quality: missing --rubric-verbatim"
[[ -n $baseline && -d $baseline ]] || bail "evaluate-output-quality: --baseline-outputs missing or not a dir: $baseline"
[[ -n $candidate && -d $candidate ]] || bail "evaluate-output-quality: --candidate-outputs missing or not a dir: $candidate"
[[ -n $fixture_list && -f $fixture_list ]] || bail "evaluate-output-quality: --fixture-list missing or not a file: $fixture_list"
[[ -n $judge_config && -f $judge_config ]] || bail "evaluate-output-quality: --judge-config missing or not a file: $judge_config"

# Read the rubric value: support `@<path>` to read from file (preserves whitespace).
if [[ "$rubric" == @* ]]; then
  rubric_path=${rubric#@}
  [[ -f $rubric_path ]] || bail "evaluate-output-quality: --rubric-verbatim @file not found: $rubric_path"
  rubric=$(cat "$rubric_path")
fi
[[ -n $rubric ]] || bail "evaluate-output-quality: rubric is empty"

# Repo root for log + verdict paths.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RESEARCH_DIR="$REPO_ROOT/.kiln/research/$prd_slug"
VERDICT_DIR="$RESEARCH_DIR/judge-verdicts"
DRIFT_REPORT="$RESEARCH_DIR/judge-drift-report.md"
POSITION_MAP="$RESEARCH_DIR/position-mapping.json"
mkdir -p "$VERDICT_DIR"

# Cross-platform sha256 of stdin → 64 hex chars.
sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

# --- judge-config.yaml parse (§5 schema) ---
# Parse minimal YAML: pinned_model + pinned_model_fallbacks list. Hand-rolled
# to avoid PyYAML dependency (matches parse-prd-frontmatter.sh precedent).
judge_cfg_json=$(python3 - "$judge_config" <<'PY' 2>&1
import json
import re
import sys

cfg_path = sys.argv[1]
try:
    with open(cfg_path, "r", encoding="utf-8") as f:
        text = f.read()
except Exception as ex:
    sys.stderr.write(f"Bail out! judge-config-malformed: {cfg_path} ({ex})\n")
    sys.exit(2)

# pinned_model: <value>
m = re.search(r"^pinned_model:\s*(\S+)\s*$", text, re.MULTILINE)
if not m:
    sys.stderr.write(f"Bail out! judge-config-malformed: {cfg_path} (missing pinned_model)\n")
    sys.exit(2)
pinned = m.group(1).strip().strip('"').strip("'")
if not pinned:
    sys.stderr.write(f"Bail out! judge-config-malformed: {cfg_path} (empty pinned_model)\n")
    sys.exit(2)

# pinned_model_fallbacks: optional list (block-style `- value` or inline `[a, b]`)
fallbacks = []
mf = re.search(r"^pinned_model_fallbacks:\s*(.*)$", text, re.MULTILINE)
if mf:
    rest = mf.group(1).rstrip()
    if rest.startswith("["):
        # Inline flow.
        inline = rest.strip("[]")
        fallbacks = [s.strip().strip('"').strip("'") for s in inline.split(",") if s.strip()]
    else:
        # Block-style: subsequent lines starting with `- `.
        idx = text.find(mf.group(0))
        tail = text[idx + len(mf.group(0)):]
        for line in tail.splitlines():
            stripped = line.strip()
            if not stripped:
                continue
            if stripped.startswith("- "):
                fallbacks.append(stripped[2:].strip().strip('"').strip("'"))
            else:
                break

print(json.dumps({"pinned_model": pinned, "pinned_model_fallbacks": fallbacks}))
PY
) || { printf '%s' "$judge_cfg_json" >&2; exit 2; }

pinned_model=$(jq -r .pinned_model <<<"$judge_cfg_json")
mapfile -t fallback_models < <(jq -r '.pinned_model_fallbacks[]?' <<<"$judge_cfg_json")

# --- Pinned-model probe (FR-014) ---
# When KILN_TEST_MOCK_JUDGE_DIR is set we skip the live probe (mock judges
# don't care which model id we believe is available). Otherwise probe the
# pinned model first, then walk the fallback list. First available wins.
resolve_model() {
  if [[ -n "${KILN_TEST_MOCK_JUDGE_DIR:-}" ]]; then
    # Mock mode: assume pinned model is "available."
    printf '%s' "$pinned_model"
    return 0
  fi
  local candidates=("$pinned_model" "${fallback_models[@]}")
  local m
  for m in "${candidates[@]}"; do
    [[ -n "$m" ]] || continue
    if claude --model "$m" --print 'health-check' >/dev/null 2>&1; then
      printf '%s' "$m"
      return 0
    fi
  done
  bail "pinned-model-unavailable: ${candidates[*]}"
}
model_used=$(resolve_model)

# --- Read fixture list ---
# Shape: {"fixtures": [{"id": "001-noop", "path": "..."}, ...]}
mapfile -t fixture_ids < <(jq -r '.fixtures[].id' "$fixture_list")
corpus_size=${#fixture_ids[@]}
[[ $corpus_size -gt 0 ]] || bail "evaluate-output-quality: fixture-list is empty"

# --- FR-016 control fixture selection (deterministic via sha256) ---
control_idx=$(python3 -c '
import hashlib, sys
print(int(hashlib.sha256(sys.argv[1].encode()).hexdigest(), 16) % int(sys.argv[2]))
' "$prd_slug:control" "$corpus_size")
control_fixture_id=${fixture_ids[$control_idx]}

# --- FR-015 position assignment per fixture (deterministic via sha256) ---
declare -A position_a position_b
for fid in "${fixture_ids[@]}"; do
  if [[ "$fid" == "$control_fixture_id" ]]; then
    # Identical-input control: both positions are baseline.
    position_a[$fid]="baseline"
    position_b[$fid]="baseline"
  else
    bit=$(python3 -c '
import hashlib, sys
print(int(hashlib.sha256(sys.argv[1].encode()).hexdigest(), 16) % 2)
' "$prd_slug:$fid")
    if [[ "$bit" == "0" ]]; then
      position_a[$fid]="baseline"
      position_b[$fid]="candidate"
    else
      position_a[$fid]="candidate"
      position_b[$fid]="baseline"
    fi
  fi
done

# --- Read paired output for a fixture ---
# Resolves <dir>/<fixture_id>.* — first matching extension wins. Bails if
# none found.
read_output() {
  local dir="$1" fid="$2"
  local matches=( "$dir/$fid".* "$dir/$fid" )
  local f
  for f in "${matches[@]}"; do
    if [[ -f "$f" ]]; then
      cat "$f"
      return 0
    fi
  done
  bail "missing-output-file: $fid in $dir"
}

# --- Compute rubric_verbatim_hash (orchestrator-side; FR-012) ---
rubric_hash=$(printf '%s' "$rubric" | sha256_hex)

# --- Spawn (or mock-load) judge per fixture, build envelopes ---
overall_verdict="pass"
position_assignments_json='{}'

for fid in "${fixture_ids[@]}"; do
  is_control="false"
  [[ "$fid" == "$control_fixture_id" ]] && is_control="true"

  # Construct output_a / output_b per the fixed assignment.
  if [[ "$is_control" == "true" ]]; then
    # Control: both = baseline output of the fixture.
    base_out=$(read_output "$baseline" "$fid")
    output_a="$base_out"
    output_b="$base_out"
  else
    base_out=$(read_output "$baseline" "$fid")
    cand_out=$(read_output "$candidate" "$fid")
    if [[ "${position_a[$fid]}" == "baseline" ]]; then
      output_a="$base_out"
      output_b="$cand_out"
    else
      output_a="$cand_out"
      output_b="$base_out"
    fi
  fi

  # Spawn judge OR load mock envelope.
  if [[ -n "${KILN_TEST_MOCK_JUDGE_DIR:-}" ]]; then
    mock_path="$KILN_TEST_MOCK_JUDGE_DIR/$fid.json"
    [[ -f "$mock_path" ]] || bail "evaluate-output-quality: mock judge envelope missing: $mock_path"
    judge_envelope_raw=$(cat "$mock_path")
  else
    # Live spawn would invoke the composer recipe + Agent tool here. Per
    # CLAUDE.md Rule 5 newly-shipped agents are NOT live-spawnable in the
    # same session — live invocation queues to the next session per the
    # auditor's first follow-on activity (specs/.../agent-notes/specifier.md
    # "Live-spawn validation is OUT OF SCOPE").
    bail "evaluate-output-quality: live judge spawn not yet supported in this session — set KILN_TEST_MOCK_JUDGE_DIR or wait for next-session validation per CLAUDE.md Rule 5"
  fi

  # Validate raw envelope shape — must contain blinded_verdict at minimum.
  blinded_verdict=$(jq -r '.blinded_verdict // empty' <<<"$judge_envelope_raw")
  case "$blinded_verdict" in
    A_better|equal|B_better) ;;
    *) bail "evaluate-output-quality: invalid blinded_verdict for $fid: '$blinded_verdict'" ;;
  esac

  # rubric_verbatim_hash assertion: when the mock envelope carries a
  # rubric_verbatim_hash, it must match orchestrator-side hash. Mocks may
  # omit it (test fixtures can be lighter) — only assert when present.
  mock_hash=$(jq -r '.rubric_verbatim_hash // empty' <<<"$judge_envelope_raw")
  if [[ -n "$mock_hash" && "$mock_hash" != "$rubric_hash" ]]; then
    bail "rubric-verbatim-hash-mismatch: expected=$rubric_hash actual=$mock_hash"
  fi

  rationale=$(jq -r '.rationale // ""' <<<"$judge_envelope_raw")
  reported_model=$(jq -r '.model_used // empty' <<<"$judge_envelope_raw")
  effective_model=${reported_model:-$model_used}

  pa=${position_a[$fid]}
  pb=${position_b[$fid]}

  # FR-016 drift halt — control MUST be `equal`. Halt BEFORE writing the
  # envelope to disk per contracts §1.
  if [[ "$is_control" == "true" && "$blinded_verdict" != "equal" ]]; then
    {
      printf '# Judge drift report — %s\n\n' "$prd_slug"
      printf 'Control fixture: `%s`\n' "$fid"
      printf 'Blinded verdict: `%s` (expected: `equal`)\n\n' "$blinded_verdict"
      printf '## Inputs\n\n'
      printf '### output_a\n```\n%s\n```\n\n' "$output_a"
      printf '### output_b\n```\n%s\n```\n\n' "$output_b"
      printf '## Rubric verbatim\n```\n%s\n```\n\n' "$rubric"
      printf '## Verdict envelope (raw, blinded)\n```json\n%s\n```\n' "$judge_envelope_raw"
    } > "$DRIFT_REPORT"
    bail "judge-drift-detected: blinded_verdict=$blinded_verdict"
  fi

  # De-anonymize.
  case "$blinded_verdict" in
    equal) deanon="equal" ;;
    A_better) deanon="${pa}_better" ;;
    B_better) deanon="${pb}_better" ;;
  esac

  # Write canonical envelope (sorted keys, jq -c -S).
  envelope=$(jq -c -S -n \
    --arg axis_id "output_quality" \
    --arg blinded_verdict "$blinded_verdict" \
    --arg pa "$pa" \
    --arg pb "$pb" \
    --arg deanon "$deanon" \
    --arg fid "$fid" \
    --argjson is_control "$is_control" \
    --arg model_used "$effective_model" \
    --arg rationale "$rationale" \
    --arg rubric_hash "$rubric_hash" \
    '{
      axis_id: $axis_id,
      blinded_verdict: $blinded_verdict,
      blinded_position_mapping: {A: $pa, B: $pb},
      deanonymized_verdict: $deanon,
      fixture_id: $fid,
      is_control: $is_control,
      model_used: $model_used,
      rationale: $rationale,
      rubric_verbatim_hash: $rubric_hash
    }')
  printf '%s\n' "$envelope" > "$VERDICT_DIR/fixture-$fid.json"

  # Track position assignment for the position-mapping.json file.
  position_assignments_json=$(jq -c \
    --arg fid "$fid" --arg pa "$pa" --arg pb "$pb" \
    '. + {($fid): {A: $pa, B: $pb}}' <<<"$position_assignments_json")

  # Per-axis gate: regression iff any non-control fixture has deanon == baseline_better.
  if [[ "$is_control" == "false" && "$deanon" == "baseline_better" ]]; then
    overall_verdict="regression"
  fi
done

# Write position-mapping.json (§2 shape).
mapping_json=$(jq -c -S -n \
  --arg control_fixture_id "$control_fixture_id" \
  --argjson assignments "$position_assignments_json" \
  --arg prd_slug "$prd_slug" \
  --arg seed_algorithm "sha256(prd_slug + ':' + fixture_id) mod 2" \
  '{
    control_fixture_id: $control_fixture_id,
    fixture_assignments: $assignments,
    prd_slug: $prd_slug,
    schema_version: 1,
    seed_algorithm: $seed_algorithm
  }')
printf '%s\n' "$mapping_json" > "$POSITION_MAP"

printf '%s\n' "$overall_verdict"
