#!/usr/bin/env bash
# evaluate-direction.sh — Apply per-axis direction enforcement with
# tolerance_pct wobble for a single fixture.
#
# Satisfies: FR-AE-002 (per-axis direction independence),
#            FR-AE-005 (tolerance_pct semantics).
# Contract:  specs/research-first-axis-enrichment/contracts/interfaces.md §4.
#
# Synopsis:
#   evaluate-direction.sh --axis <axis> --direction <dir> \
#                         --tolerance-pct <int> \
#                         --baseline <num> --candidate <num>
#
# Stdout: a single token — `pass` or `regression`.
# Stderr: diagnostics only.
# Exit:   0 verdict emitted (regardless of pass/regression);
#         2 invalid input (missing flag, unknown axis/direction, non-numeric).
#
# Decision logic (FR-AE-002 + FR-AE-005 + SC-AE-003 axis-aware reading):
#   direction=lower             → regression iff (c-b)/max(b,1) > t/100
#   direction=higher            → regression iff c <= b (strict — tolerance does NOT lift)
#   direction=equal_or_better   → AXIS-AWARE polarity:
#     • accuracy (higher-is-better)         → regression iff (b-c)/max(b,1) > t/100
#     • tokens / time / cost (lower-is-better) → regression iff (c-b)/max(b,1) > t/100
#     SC-AE-003 anchors this — `tokens, eob, tol=0` must regress on +1 token; the
#     literal spec formula `c ≥ b - t` would pass that (axis-blind), so eob is
#     interpreted as "no degradation in the axis's preferred direction."
#   axis=accuracy               → pass=1.0, fail=0.0; only equal_or_better is meaningful.
#                                 Caller passes baseline/candidate as 0/1.
#
# Determinism: same inputs → byte-identical stdout (NFR-AE-002).
set -euo pipefail
LC_ALL=C
export LC_ALL

bail() {
  printf 'Bail out! %s\n' "$1" >&2
  exit 2
}

axis= direction= tol= b= c=
while (( $# > 0 )); do
  case $1 in
    --axis) axis=${2:-}; shift 2 ;;
    --direction) direction=${2:-}; shift 2 ;;
    --tolerance-pct) tol=${2:-}; shift 2 ;;
    --baseline) b=${2:-}; shift 2 ;;
    --candidate) c=${2:-}; shift 2 ;;
    *) bail "unknown flag: $1" ;;
  esac
done

[[ -n $axis ]] || bail "missing --axis"
[[ -n $direction ]] || bail "missing --direction"
[[ -n $tol ]] || bail "missing --tolerance-pct"
[[ -n $b ]] || bail "missing --baseline"
[[ -n $c ]] || bail "missing --candidate"

case $axis in
  accuracy|tokens|time|cost) ;;
  *) bail "unknown axis: $axis (allowed: accuracy|tokens|time|cost)" ;;
esac
case $direction in
  lower|higher|equal_or_better) ;;
  *) bail "unknown direction: $direction (allowed: lower|higher|equal_or_better)" ;;
esac
[[ $tol =~ ^[0-9]+$ ]] || bail "tolerance-pct must be a non-negative int: $tol"
[[ $b =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || bail "baseline must be numeric: $b"
[[ $c =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || bail "candidate must be numeric: $c"

# Floating-point comparison via awk for portability.
# eob polarity mapping: accuracy is higher-is-better; tokens/time/cost are lower-is-better.
verdict=$(awk -v axis="$axis" -v dir="$direction" -v t="$tol" -v b="$b" -v c="$c" '
  BEGIN {
    bb = (b < 1) ? 1 : b;
    if (dir == "lower") {
      delta = (c - b) / bb * 100.0;
      print (delta > t) ? "regression" : "pass";
    } else if (dir == "equal_or_better") {
      if (axis == "accuracy") {
        # higher-is-better polarity
        delta = (b - c) / bb * 100.0;
      } else {
        # tokens / time / cost — lower-is-better polarity
        delta = (c - b) / bb * 100.0;
      }
      print (delta > t) ? "regression" : "pass";
    } else if (dir == "higher") {
      print (c <= b) ? "regression" : "pass";
    } else {
      exit 1;
    }
  }
')

[[ -n $verdict ]] || bail "internal: awk produced no verdict"
printf '%s\n' "$verdict"
