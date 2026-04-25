#!/usr/bin/env bash
# Alternating N=5 before/after samples for T092 LLM-RTT + token comparison.
set -eu
SCRATCH="$1"
RESULTS=/tmp/perf-results.tsv
echo -e "sample\tarm\telapsed_sec\tduration_ms\tapi_ms\tnum_turns\tin_tok\tout_tok\tcache_read\tcache_create\tcost_usd\tstop" > "$RESULTS"

parse_field() {
  echo "$1" | grep -oE "^$2=.*" | head -1 | cut -d= -f2-
}

for i in 1 2 3 4 5; do
  for ARM in before after; do
    OUT=$(/tmp/perf-$ARM.sh "$SCRATCH" 2>&1)
    ELAPSED=$(parse_field "$OUT" "${ARM}_elapsed_sec")
    DURATION=$(parse_field "$OUT" "duration_ms")
    API=$(parse_field "$OUT" "duration_api_ms")
    TURNS=$(parse_field "$OUT" "num_turns")
    IN=$(parse_field "$OUT" "input_tokens")
    OUT_TOK=$(parse_field "$OUT" "output_tokens")
    CR=$(parse_field "$OUT" "cache_read_input_tokens")
    CC=$(parse_field "$OUT" "cache_creation_input_tokens")
    COST=$(parse_field "$OUT" "total_cost_usd")
    STOP=$(parse_field "$OUT" "stop_reason")
    LOG_OK=$(echo "$OUT" | grep -c 'log_line_count=1' || true)
    echo -e "${i}\t${ARM}\tel=${ELAPSED}s\tdur=${DURATION}ms\tapi=${API}ms\tturns=${TURNS}\tin=${IN}\tout=${OUT_TOK}\tcr=${CR}\tcc=${CC}\tcost=\$${COST}\tstop=${STOP}\tlog_ok=${LOG_OK}"
    echo -e "${i}\t${ARM}\t${ELAPSED}\t${DURATION}\t${API}\t${TURNS}\t${IN}\t${OUT_TOK}\t${CR}\t${CC}\t${COST}\t${STOP}" >> "$RESULTS"
  done
done

echo ""
echo "=== SUMMARY ==="
python3 <<'PY'
import csv, statistics
rows = list(csv.DictReader(open('/tmp/perf-results.tsv'), delimiter='\t'))

def stats(arm, key, unit=''):
    vals = []
    for r in rows:
        if r['arm'] != arm: continue
        v = r[key]
        try: vals.append(float(v))
        except: pass
    if not vals: return None
    return {
        'n': len(vals),
        'median': statistics.median(vals),
        'mean': statistics.mean(vals),
        'stdev': statistics.stdev(vals) if len(vals) > 1 else 0,
        'min': min(vals), 'max': max(vals),
    }

def row(label, key, unit='', fmt='.2f'):
    b = stats('before', key)
    a = stats('after', key)
    delta_med = b['median'] - a['median']
    delta_mean = b['mean'] - a['mean']
    print(f"{label:30s}  before={b['median']:{fmt}}{unit}  after={a['median']:{fmt}}{unit}  delta_median={delta_med:+{fmt}}{unit}  delta_mean={delta_mean:+{fmt}}{unit}")

row('Wall-clock (sec)', 'elapsed_sec', 's')
row('duration_ms (harness)', 'duration_ms', 'ms', '.0f')
row('duration_api_ms', 'api_ms', 'ms', '.0f')
row('num_turns', 'num_turns', '', '.1f')
row('input_tokens', 'in_tok', '', '.0f')
row('output_tokens', 'out_tok', '', '.0f')
row('cache_read_input_tokens', 'cache_read', '', '.0f')
row('cache_creation_input_tokens', 'cache_create', '', '.0f')
row('total_cost_usd', 'cost_usd', '', '.4f')
PY
