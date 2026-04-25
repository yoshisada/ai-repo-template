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

## Run log 2026-04-24 (second run — with token usage via --output-format=json)

Machine: Darwin 24.5.0 (macOS arm64), Claude Code 2.1.119, OAuth session (not
--bare), harness default model, default plugin set loaded.

Raw samples (`results-2026-04-24-with-tokens.tsv` for full data):

| # | Arm | Wall (s) | API (ms) | Turns | Out tok | Cache read | Cost $ |
|---|---|---:|---:|---:|---:|---:|---:|
| 1 | before | 10.80 | 6925 | 3 | 400 | 80394 | 0.1418 |
| 1 | after  |  7.73 | 3753 | 2 | 176 | 48476 | 0.1186 |
| 2 | before | 10.95 | 7206 | 3 | 395 | 80388 | 0.1417 |
| 2 | after  | 14.00 | 10331 | 2 | 180 | 48476 | 0.1187 |
| 3 | before | 10.47 | 6596 | 3 | 393 | 80136 | 0.1431 |
| 3 | after  |  8.41 | 4382 | 2 | 176 | 48476 | 0.1186 |
| 4 | before | 15.28 | 7132 | 3 | 393 | 79853 | 0.1397 |
| 4 | after  | 10.93 | 7158 | 2 | 176 | 48476 | 0.1186 |
| 5 | before | 10.58 | 6336 | 3 | 399 | 80391 | 0.1418 |
| 5 | after  |  7.87 | 3816 | 2 | 176 | 48476 | 0.1186 |

Summary (median):

| Metric | Before | After | Delta | Delta % |
|---|---:|---:|---:|---:|
| Wall-clock (s)           | 10.80  |  8.40  | +2.39  | -22% |
| duration_api_ms          |  6925  |  4382  | +2543  | -37% |
| **num_turns**            |    3   |    2   |  **+1**| **-33%** |
| **output_tokens**        |   395  |   176  | **+219** | -55% |
| **cache_read_input_tokens** | 80388 | 48476 | **+31912** | -40% |
| cache_creation_input_tokens |  14657 |  14392 |   +265 |  -2% |
| input_tokens                |      8 |      7 |     +1 |  n/a |
| **total_cost_usd**       | 0.1418 | 0.1186 | **+0.0232** | **-16%** |

## Run log 2026-04-24 (first run — wall-clock only)

Earlier run using `--output-format=text` (no token data captured). Retained for
reproducibility in `results-2026-04-24.tsv`.

|  | N | median | mean | stdev | min | max |
|---|---:|---:|---:|---:|---:|---:|
| Before (2 Bash tool calls) | 5 | 11.59 | 13.52 | 5.29 | 9.89 | 22.88 |
| After  (1 Bash tool call)  | 5 |  8.24 |  8.30 | 0.56 | 7.75 |  8.91 |

Delta (before - after): **median +3.35s, mean +5.21s**. Two independent runs;
wall-clock delta reproduced at +2.39s and +3.35s respectively.

## Interpretation

- **One fewer turn, deterministically.** Every run shows `num_turns` going
  3→2. The wrapper structurally eliminates one tool-call round-trip every
  time — not a stochastic win.
- **~2.4 seconds wall-clock saved** per bg sub-agent invocation on this
  hardware + session (median). Duration_api_ms delta matches (~2.5s), so
  subprocess startup is a non-factor in the comparison.
- **~219 fewer output tokens and ~31,900 fewer cache-read tokens** per
  invocation — the cost of the eliminated tool-use turn (reasoning +
  tool call + structure) and its associated conversation-context re-read.
- **~$0.023 saved per invocation** (~16% cost reduction on the bg
  sub-agent). At 10 invocations/day, ~$0.23/day; annualized per heavy
  user, ~$85.
- T092's switchover is validated at the LLM layer. SC-004 ("measurable
  wall-clock speedup from FR-018's step-batching prototype") is
  satisfied with real numbers.
- **This is background work; the user does not wait for it.** The wall-clock
  delta does not show up as foreground response-time speedup. It shows
  up as: (1) bg sub-agent finishes ~2.4s sooner every
  `/kiln:kiln-report-issue` invocation, (2) one fewer tool-use round-trip
  worth of model tokens per invocation, (3) ~$0.023 less API cost per
  invocation, (4) reduced tail latency if the user fires
  `/kiln:kiln-report-issue` again in quick succession.

## Limitations

- N=5 is small. The stdev estimates are wide.
- Same-session runs share server-side caches; cross-session runs could differ.
- This does NOT test the cross-plugin `${WORKFLOW_PLUGIN_DIR}` resolution
  gap documented in `.kiln/issues/2026-04-24-kiln-report-issue-workflow-plugin-dir-cross-plugin-gap.md`.
  The fixture copies scripts into the scratch dir by path, not through the
  workflow-dispatch path. The resolution-gap concern is orthogonal to the
  perf concern.
