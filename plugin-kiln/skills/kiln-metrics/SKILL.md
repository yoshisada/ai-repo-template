---
name: "kiln-metrics"
description: "Win-condition scorecard against this repo's eight six-month vision signals (a)–(h). Emits an 8-row table with status (on-track / at-risk / unmeasurable) + evidence cite, written to BOTH stdout and a timestamped log under .kiln/logs/metrics-<UTC-timestamp>.md."
---

# /kiln:kiln-metrics

Run the eight per-signal extractors against this repo's `.kiln/vision.md`
"How we'll know we're winning" section and emit a tabular scorecard.

This skill is a thin wrapper around `plugin-kiln/scripts/metrics/orchestrator.sh`.
The orchestrator handles writing both stdout and the timestamped log; the SKILL
exists so the surface is `/kiln:kiln-metrics` (FR-015 / FR-019).

## Usage

```bash
/kiln:kiln-metrics
```

No flags in V1.

## What it does

- Walks each `plugin-kiln/scripts/metrics/extract-signal-<a..h>.sh`.
- Aggregates one row per signal into a pipe-delimited table.
- Writes the report to BOTH stdout AND `.kiln/logs/metrics-<UTC-timestamp>.md`.
- Never overwrites an existing log file (suffix `-<N>` on collision).

## Column shape (FR-016)

```
| signal | current_value | target | status | evidence |
```

`status` is exactly one of:
- `on-track` — measured value meets the target.
- `at-risk` — measured value falls short.
- `unmeasurable` — extractor cannot return a value (data source missing or
  outside shell-readable surface).

## Eight signals (V1 — this repo only, NFR-002)

| Signal | Source script | Evidence source |
|---|---|---|
| `(a)` | `extract-signal-a.sh` | `git log --merges` for `build-prd` PRs in last 90 days |
| `(b)` | `extract-signal-b.sh` | `.wheel/history/*.jsonl` `escalation` count, last 90 days |
| `(c)` | `extract-signal-c.sh` | `docs/features/*/PRD.md` with `derived_from:` |
| `(d)` | `extract-signal-d.sh` | `.kiln/mistakes/` ↔ Obsidian `@inbox/closed/` (closed leg unreadable from shell → unmeasurable) |
| `(e)` | `extract-signal-e.sh` | `.kiln/logs/hook-*.log` block / refus / .env grep, last 30 days |
| `(f)` | `extract-signal-f.sh` | `.shelf-config` + `.trim/` presence (drift count requires shelf MCP → unmeasurable) |
| `(g)` | `extract-signal-g.sh` | `.kiln/logs/kiln-test-*.md` count, last 30 days |
| `(h)` | `extract-signal-h.sh` | `.kiln/roadmap/items/declined/` cross-referenced with `.kiln/feedback/` |

## Graceful degrade (FR-017 / SC-008)

If any extractor fails, returns malformed output, or has its data source
missing, that row carries `status: unmeasurable` with a reason in the
`evidence` column. The skill ALWAYS exits 0 — extractor failures NEVER
propagate as overall failure.

## Determinism

Theme D extractors are deterministic shell readers (no LLM). The orchestrator's
output is byte-identical for a frozen repo state modulo the run timestamp;
`KILN_METRICS_NOW=<timestamp>` overrides the timestamp for fixtures and CI.

## Run

```bash
bash plugin-kiln/scripts/metrics/orchestrator.sh
```
