# kiln-report-issue-batching-perf

**Purpose**: Measure the LLM-tool-call round-trip latency delta that T092's
wrapper-switchover actually delivers on `/kiln:kiln-report-issue`'s background
sub-agent path. Complements — and corrects — the bash-orchestration-layer
measurement in `.kiln/research/wheel-step-batching-audit-2026-04-24.md`, which
measured the wrong layer.

## What it does

Constructs two `claude --print` subprocess invocations that each direct an
agent to perform the same observable work (counter increment + log append) on
a scratch dir, but with different tool-call structures:

- **Before** (`perf-before.sh`): 2 Bash tool calls — `shelf-counter.sh
  increment-and-decide`, parse JSON, `append-bg-log.sh <args>`. Matches the
  pre-T092 bg sub-agent prompt shape.
- **After** (`perf-after.sh`): 1 Bash tool call — `step-dispatch-background-sync.sh`.
  Matches the post-T092 bg sub-agent prompt shape.

The driver (`perf-driver.sh`) runs N=5 alternating samples, writes raw numbers
to `results-<date>.tsv`, and prints a summary with median / mean / stdev.

## How to reproduce

```bash
# Scaffold a scratch dir
SCRATCH=$(mktemp -d -t kiln-test-t092-perf-XXXXXXXX)
mkdir -p "$SCRATCH/.kiln/issues/completed" "$SCRATCH/.kiln/logs" "$SCRATCH/.wheel/outputs"
printf 'shelf_full_sync_counter=0\nshelf_full_sync_threshold=10\n' > "$SCRATCH/.shelf-config"
cp plugin-shelf/scripts/shelf-counter.sh \
   plugin-shelf/scripts/append-bg-log.sh \
   plugin-shelf/scripts/step-dispatch-background-sync.sh "$SCRATCH/"

# Run
bash plugin-kiln/tests/kiln-report-issue-batching-perf/perf-driver.sh "$SCRATCH"
```

## Run log 2026-04-24

Machine: Darwin 24.5.0 (macOS arm64), Claude Code 2.1.119, OAuth session (not
--bare), haiku not forced (harness default model), default plugin set loaded.

Raw samples:

| # | Before (sec) | After (sec) |
|---|---:|---:|
| 1 | 22.879 (cold-start outlier) | 8.911 |
| 2 | 11.591 | 8.843 |
| 3 | 11.567 | 7.778 |
| 4 | 9.886 | 7.747 |
| 5 | 11.654 | 8.244 |

Summary:

|  | N | median | mean | stdev | min | max |
|---|---:|---:|---:|---:|---:|---:|
| Before (2 Bash tool calls) | 5 | 11.59 | 13.52 | 5.29 | 9.89 | 22.88 |
| After  (1 Bash tool call)  | 5 |  8.24 |  8.30 | 0.56 | 7.75 |  8.91 |

Delta (before - after): **median +3.35s, mean +5.21s**.

Excluding the sample-1 cold-start outlier, BEFORE stdev is 0.83s — the ~3s
delta is well clear of noise.

## Interpretation

- Each eliminated LLM tool-call round-trip is worth ~3 seconds on this
  hardware + session.
- The wrapper eliminates exactly one round-trip (2 → 1 Bash tool calls in
  the bg sub-agent prompt).
- T092's switchover is validated at the LLM layer. SC-004 ("measurable
  wall-clock speedup from FR-018's step-batching prototype") is now
  satisfied with real numbers.
- **This is background work; the user does not wait for it.** The delta
  does not show up as foreground response-time speedup for the user. It
  shows up as: (1) bg sub-agent finishes ~3s sooner on every
  `/kiln:kiln-report-issue` invocation, (2) ~1 fewer tool-use round-trip
  worth of model tokens per invocation, (3) reduced tail latency if the
  user fires `/kiln:kiln-report-issue` again in quick succession.

## Limitations

- N=5 is small. The stdev estimates are wide.
- Same-session runs share server-side caches; cross-session runs could differ.
- This does NOT test the cross-plugin `${WORKFLOW_PLUGIN_DIR}` resolution
  gap documented in `.kiln/issues/2026-04-24-kiln-report-issue-workflow-plugin-dir-cross-plugin-gap.md`.
  The fixture copies scripts into the scratch dir by path, not through the
  workflow-dispatch path. The resolution-gap concern is orthogonal to the
  perf concern.
