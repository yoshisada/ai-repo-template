# Research Run Report

**Run UUID**: 9fdc0fb0-948a-4aa9-bbbf-ffe065e4a298
**Baseline plugin-dir**: /Users/ryansuematsu/Documents/github/personal/ai-repo-template/plugin-kiln
**Candidate plugin-dir**: /Users/ryansuematsu/Documents/github/personal/ai-repo-template/plugin-kiln
**Corpus**: /var/folders/s1/lcdt1qs90b99z2zlpxk5b6j40000gn/T/tmp.05SMKBQkTo/corpus
**PRD**: /Users/ryansuematsu/Documents/github/personal/ai-repo-template/plugin-kiln/tests/research-runner-axis-excluded-fixtures/fixtures/excluded-prd.md
**Gate mode**: per_axis_direction
**Blast radius**: isolated
**Rigor row**: min_fixtures=3, tolerance_pct=5
**Declared axes**: tokens (equal_or_better)
**Started**: 2026-04-25T22:44:09Z
**Completed**: 2026-04-25T22:44:22Z
**Wall-clock**: 13s

## Per-Fixture Results

| Fixture | Acc B/C | Tokens B/C | Δ Tok | Time B/C | Δ Time | Cost B/C | Δ Cost | Per-Axis Verdict |
|---|---|---|---|---|---|---|---|---|
| 001-active | pass/pass | 0/0 | 0 | 2.4656/2.1266 | -0.3390 | —/— | — | accuracy:pass, tokens:pass |
| 003-active | pass/pass | 0/0 | 0 | 2.1738/1.9351 | -0.2387 | —/— | — | accuracy:pass, tokens:pass |
| 004-active | pass/pass | 0/0 | 0 | 2.1998/2.0857 | -0.1141 | —/— | — | accuracy:pass, tokens:pass |

## Aggregate

- **Total fixtures**: 3
- **Excluded fixtures**: 1
- **Regressions**: 0
- **Overall**: PASS
- **Report UUID**: 9fdc0fb0-948a-4aa9-bbbf-ffe065e4a298
- **Runtime**: 13s

## Excluded Fixtures

| Fixture | Reason |
|---|---|
| 002-flaky | intermittent stream-json shape drift |

## Warnings

- pricing-table-miss: <synthetic>
