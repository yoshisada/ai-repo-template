# Regression-detect fixtures

Engineered transcripts for SC-S-002:
- `transcript-baseline.ndjson` — usage totals: input=10, output=50, cc=100, cr=200, total=360.
- `transcript-candidate-token-regression.ndjson` — same except output=80, total=390. Δ=+30 tokens, comfortably above the NFR-S-001 ±10 tolerance band.

`run.sh` synthesizes per-fixture NDJSON results from these transcripts, drives `render-research-report.sh` directly, and asserts the rendered report names the regressing fixture by slug + flips Overall: FAIL.

This avoids spawning a real `claude` subprocess per the test substrate hierarchy: pure-shell unit fixture invokable via `bash run.sh`.
