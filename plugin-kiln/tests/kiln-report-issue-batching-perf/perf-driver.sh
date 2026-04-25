#!/usr/bin/env bash
# Alternating N=5 before/after samples for T092 LLM-RTT comparison.
set -eu
SCRATCH="$1"
RESULTS=/tmp/perf-results.tsv
echo -e "sample\tarm\telapsed_sec" > "$RESULTS"

for i in 1 2 3 4 5; do
  for ARM in before after; do
    OUT=$(/tmp/perf-$ARM.sh "$SCRATCH" 2>&1)
    ELAPSED=$(echo "$OUT" | grep -oE "${ARM}_elapsed_sec=[0-9.]+" | cut -d= -f2)
    LOG_OK=$(echo "$OUT" | grep -c 'log_line_count=1' || true)
    echo -e "${i}\t${ARM}\t${ELAPSED}\t(log_ok=${LOG_OK})"
    echo -e "${i}\t${ARM}\t${ELAPSED}" >> "$RESULTS"
  done
done

echo ""
echo "=== SUMMARY ==="
python3 <<'PY'
import csv, statistics
rows = list(csv.DictReader(open('/tmp/perf-results.tsv'), delimiter='\t'))
before = [float(r['elapsed_sec']) for r in rows if r['arm'] == 'before']
after = [float(r['elapsed_sec']) for r in rows if r['arm'] == 'after']
print(f"BEFORE (3-call chain, N={len(before)}): "
      f"median={statistics.median(before):.2f}s  "
      f"mean={statistics.mean(before):.2f}s  "
      f"stdev={statistics.stdev(before):.2f}s  "
      f"min={min(before):.2f}s  max={max(before):.2f}s")
print(f"AFTER  (1-call wrapper, N={len(after)}): "
      f"median={statistics.median(after):.2f}s  "
      f"mean={statistics.mean(after):.2f}s  "
      f"stdev={statistics.stdev(after):.2f}s  "
      f"min={min(after):.2f}s  max={max(after):.2f}s")
delta_median = statistics.median(before) - statistics.median(after)
delta_mean = statistics.mean(before) - statistics.mean(after)
print(f"DELTA (before - after): median={delta_median:+.2f}s  mean={delta_mean:+.2f}s")
print(f"  Positive = wrapper is faster (fewer LLM round-trips)")
print(f"  Noise floor estimate (combined stdev): ~{(statistics.stdev(before)+statistics.stdev(after))/2:.2f}s")
PY
