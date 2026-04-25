---
id: 2026-04-24-research-first-time-and-cost-axes
title: "Research-first step 3 — time and cost axes with maintained pricing table"
kind: feature
date: 2026-04-24
status: open
phase: 09-research-first
state: planned
blast_radius: feature
review_cost: moderate
context_cost: 2 sessions
depends_on:
  - 2026-04-24-research-first-fixture-format-mvp
implementation_hints: |
  Add two new axes to the runner's per-fixture metrics:

    - time: wall-clock duration of the subprocess invocation, in seconds (monotonic clock).
            Measured per fixture, per version. High variance → needs tolerance tuning more than
            the mechanical tokens axis.

    - cost: derived metric. cost_usd = f(input_tokens, output_tokens, cached_input_tokens, model_id).
            Pricing table lives at `plugin-kiln/lib/pricing.json`:

              { "claude-opus-4-7":        { "input_per_mtok": 15.00, "output_per_mtok": 75.00, "cached_input_per_mtok": 1.50 },
                "claude-sonnet-4-6":      { "input_per_mtok": 3.00,  "output_per_mtok": 15.00, "cached_input_per_mtok": 0.30 },
                "claude-haiku-4-5-20251001": { "input_per_mtok": 0.80, "output_per_mtok": 4.00, "cached_input_per_mtok": 0.08 } }

  Note: these are example numbers — confirm with current Anthropic pricing during implementation.
  The pricing table is manually maintained; an auditor subcheck should flag it as stale if the
  file's mtime is >180 days old. Model IDs come from the fixture's kiln-test stream-json output.

  Cost axis is a pure derivation of token axes — no new measurement. Time is a genuinely new
  measurement and may require multi-run averaging to be stable (deferred to a later item if
  noise proves unmanageable).

  The axes are opt-in per PRD (the research block declares which metrics gate). Most changes
  will only declare 1-2 axes (per 2026-04-24 conversation); don't default-declare all four.
---

# Research-first step 3 — time and cost axes with maintained pricing table

## What

Add two new axes — wall-clock `time` and dollar `cost` — to the research runner. Cost is derived from tokens via a maintained pricing table at `plugin-kiln/lib/pricing.json`; time is a direct wall-clock measurement.

## Why now

Tokens are a useful proxy for "is this cheaper?" but they flatten the distinction between cached and uncached input, and between model tiers (Haiku is ~18x cheaper than Opus per token). A change that moves work from Opus to Haiku should register as a win even if token count rises. Cost axis captures that; tokens axis can't. Time matters for skills invoked inline in interviews (kiln-distill, kiln-roadmap) where wall-clock latency is a real UX signal.

## Assumptions

- Pricing table staleness is a soft concern — being off by 10-20% on rates doesn't invalidate the gate decision (relative comparison is what matters). Being off by 2x would. A 180-day staleness alarm is enough.
- Time measurement is reliable within blast_radius tolerance for single-run comparison at the corpus level. If cross-run variance exceeds tolerance, defer to multi-run averaging (not in scope for this step).

## Hardest part

Keeping the pricing table accurate without making it a burden. Anthropic pricing changes occasionally; neither an over-aggressive staleness alarm nor a "ship it and forget" approach is right. An auditor subcheck with the 180-day threshold plus a release-note reminder is a reasonable middle ground.

## Cheaper version

Skip the time axis entirely for this step; ship cost-only. Time is the noisier axis and could be added later if maintainers actually request it. Saves implementation complexity (multi-run averaging scope) but leaves an obvious gap for latency-sensitive changes.

## Dependencies

Depends on: step 1 (fixture-format-mvp). Independent of step 2.
