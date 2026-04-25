---
id: 2026-04-24-research-first-per-axis-gate-and-rigor
title: "Research-first step 2 — per-axis direction gate + blast-radius-dynamic rigor"
kind: feature
date: 2026-04-24
status: open
phase: 09-research-first
state: planned
blast_radius: feature
review_cost: careful
context_cost: 2 sessions
depends_on:
  - 2026-04-24-research-first-fixture-format-mvp
implementation_hints: |
  Replace step 1's hardcoded strict gate with per-axis `direction:` enforcement:

    - Each PRD declares `empirical_quality: [{metric, direction, priority}, ...]`.
    - Gate rule: for every declared axis, every fixture's candidate value must satisfy `direction:`
      relative to baseline. direction=lower → candidate <= baseline. direction=equal_or_better →
      candidate >= baseline (or equal within tolerance). Accuracy is always implicit primary
      with direction=equal_or_better.
    - No axis needs to improve — they just must not regress past their declared direction.
      (Per 2026-04-24 conversation: "if it improves time but not tokens as long as tokens didn't increase then its fine.")

  Rigor scaling by blast_radius (config lives at `plugin-kiln/lib/research-rigor.json`):

    { "isolated":      { "min_fixtures": 3,  "tolerance_pct": 5 },
      "feature":       { "min_fixtures": 10, "tolerance_pct": 2 },
      "cross-cutting": { "min_fixtures": 20, "tolerance_pct": 1 },
      "infra":         { "min_fixtures": 20, "tolerance_pct": 0 } }

  Tolerance is a per-axis-per-fixture wobble budget for measurement noise (same input, different
  run, slightly different token count due to non-determinism). Set to 0 for infra changes where
  any regression is suspect.

  Excluded-fixtures escape hatch: PRD may declare `excluded_fixtures: [{path, reason}]` to skip
  specific known-noisy fixtures. Auditor flags if excluded-fixture count is >30% of corpus.
---

# Research-first step 2 — per-axis direction gate + blast-radius-dynamic rigor

## What

Replace step 1's hardcoded strict gate with a configurable per-axis direction-enforcement gate. Rigor (minimum fixture count, per-axis tolerance) scales automatically from the PRD's `blast_radius:`. Ships an escape hatch (`excluded_fixtures:`) for known-noisy cases with auditor oversight.

## Why now

Step 1's hardcoded gate is fine for a proof of concept but unusable in practice — you can't empirically measure tokens without accepting some measurement noise, and one-size-fits-all rigor means trivial isolated changes pay the same testing cost as core-infra changes. This step makes the gate calibration-aware.

## Assumptions

- Per-axis tolerances (wobble budgets) are stable across skill runs at similar token sizes — i.e., the same fixture run twice in a row with the same plugin-dir produces tokens within the declared tolerance percentage. If that assumption fails (non-determinism > tolerance), the gate becomes noisy and the policy needs a different statistical approach (multi-run averaging).
- `blast_radius:` values are trustworthy as entered. Coached capture already surfaces them so maintainer judgment is encoded — no automatic inference.

## Hardest part

Tuning the default `research-rigor.json` numbers so the gate is meaningful without being obnoxious. Too-strict → legit improvements get blocked on noise; too-loose → real regressions sneak through. Ship with conservative defaults and revise based on real usage.

## Cheaper version

Ship `tolerance_pct: 0` for every blast_radius. Maintainer explicitly overrides per-PRD when noise is a problem. Simpler default but creates friction on every first run. Revise to the tiered defaults once we've seen 3-5 real research gates.

## Dependencies

Depends on: step 1 (fixture-format-mvp).
