# Research Run Report

**Run UUID**: aad8c2de-eeb9-437e-b637-1d4a050f4202
**Baseline plugin-dir**: /Users/ryansuematsu/Documents/github/personal/ai-repo-template/plugin-kiln
**Candidate plugin-dir**: /tmp/kiln-smoke-regress-RDpDex/plugin-kiln-regressing
**Corpus**: /Users/ryansuematsu/Documents/github/personal/ai-repo-template/plugin-kiln/fixtures/research-first-seed/corpus
**Started**: 2026-04-25T21:25:51Z
**Completed**: 2026-04-25T21:27:01Z
**Wall-clock**: 70s

## Per-Fixture Results

| Fixture | Baseline Acc | Candidate Acc | Baseline Tokens | Candidate Tokens | Δ Tokens | Verdict |
|---|---|---|---|---|---|---|
| 001-noop-passthrough | pass | pass | 97122 | 98162 | 1040 | regression (tokens) |
| 002-token-floor | pass | pass | 128804 | 98178 | -30626 | pass |
| 003-assertion-anchor | pass | pass | 129473 | 64890 | -64583 | pass |

## Aggregate

- **Total fixtures**: 3
- **Regressions**: 1
- **Overall**: FAIL
- **Report UUID**: aad8c2de-eeb9-437e-b637-1d4a050f4202
- **Runtime**: 70s

## Diagnostics

- **001-noop-passthrough** — verdict `regression (tokens)`
  - Baseline transcript: `/Users/ryansuematsu/Documents/github/personal/ai-repo-template/.kiln/logs/kiln-test-cdf0b594-61bb-4567-a5b1-886fa47a8106-transcript.ndjson`
  - Candidate transcript: `/Users/ryansuematsu/Documents/github/personal/ai-repo-template/.kiln/logs/kiln-test-961b003c-ee73-4af3-b85d-41f3e1139b28-transcript.ndjson`
  - Baseline scratch (retained on fail): `/tmp/kiln-test-cdf0b594-61bb-4567-a5b1-886fa47a8106/`
  - Candidate scratch (retained on fail): `/tmp/kiln-test-961b003c-ee73-4af3-b85d-41f3e1139b28/`
