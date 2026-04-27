---
id: 2026-04-27-build-prd-model-cost-calibration
title: "build-prd model cost calibration — pin cost-effective models per pipeline step"
kind: feature
date: 2026-04-27
status: open
phase: 10-self-optimization
state: planned
blast_radius: feature
review_cost: moderate
context_cost: 2-3 sessions
depends_on:
  - 2026-04-24-wheel-per-step-model-selection
  - 2026-04-24-research-first-time-and-cost-axes
implementation_hints: |
  Calibration pass that pins the cheapest model meeting the quality bar
  for each agent in the build-prd pipeline. Reuses the already-shipped
  research-first cost infrastructure (PR #178 — pricing.json,
  per-fixture cost axes); this item is the *application* of that infra
  to build-prd specifically, not new measurement infra.

  ## Pipeline agents to calibrate

  Build-prd team (per CLAUDE.md): specifier → [researcher] → implementer(s)
  → [qa-engineer] → auditor(s) → retrospective. Plus the on-demand
  debugger and smoke-tester. Each gets a calibration row.

  ## Quality bar per agent (load-bearing)

    - specifier        — spec passes validate-spec + audit gates
    - planner          — plan produces interfaces.md matching spec FRs
    - tasks            — task graph passes /kiln:kiln-analyze (no
                         gaps/duplicates)
    - implementer      — code passes lint + tests + audit; FR comments
                         present
    - qa-engineer      — catches at least one real bug on a seeded
                         regression fixture
    - auditor          — flags real gaps, not noise; false-positive
                         rate < 20%
    - retrospective    — produced PI's insight_score ≥ threshold (per
                         retro-quality-auditor item, already shipped)
    - smoke-tester     — detects a real runtime failure on a known-broken
                         fixture
    - debugger         — produces fix that passes audit on first
                         attempt for ≥80% of seeded bugs

  Without measurable quality bars, downgrading to Haiku silently
  degrades pipelines. The bar IS the calibration's load-bearing input.

  ## Calibration approach (cheaper 80% version — recommended for v1)

  Manual one-shot audit:
    1. Pick one representative spec fixture (suggested:
       specs/structured-roadmap or a recently-completed PRD with known
       audit pass).
    2. Run each agent at Haiku / Sonnet / Opus against that fixture.
    3. Capture cost + quality-bar pass/fail per (agent, model) cell.
    4. Pick the cheapest model that hits ≥80% audit pass for that
       agent.
    5. Commit results as `model:` frontmatter on the agent.md files
       under plugin-kiln/agents/.

  This skips research-first-runner integration. v2 candidate: wire each
  agent into the research-first fixture format so calibration becomes
  reproducible / re-runnable on schema changes.

  ## Per-step granularity (v2 — gated on wheel-per-step-model-selection)

  Some agents do multiple kinds of work in one role (e.g., the
  implementer may need Opus for hardest-task planning but Haiku for
  bash-heavy file generation). Per-step `model:` in workflow JSON
  unlocks that finer grain. Until 2026-04-24-wheel-per-step-model-selection
  lands, calibration lives at the agent-role level only. That's the
  v1 ceiling.

  ## Dependency rationale

    - 2026-04-24-research-first-time-and-cost-axes — HARD: provides
      pricing.json + per-fixture cost computation. Already shipped
      (PR #178), so no blocker. Without it, we'd need to build cost
      measurement from scratch.

    - 2026-04-24-wheel-per-step-model-selection — SOFT: enables
      per-step model overrides in workflow JSON. Without it, calibration
      lands at agent.md frontmatter level only. Workaround: ship v1
      with agent-role granularity; revisit per-step when the wheel
      feature lands.

  ## Anti-patterns to avoid

    - Calibrating against a single fixture and assuming results
      generalize. Use ≥2 fixtures per agent if cost permits.
    - Picking the model based on cost alone without confirming the
      quality bar. Cheap-but-wrong is the failure mode this prevents.
    - Forgetting cached-input pricing when computing real costs —
      pricing.json's `cached_input_per_mtok` field is load-bearing
      for repeated-prompt agents (specifier, planner).

  ## Acceptance signal

    - Each agent.md under plugin-kiln/agents/ carries a `model:`
      frontmatter line citing the calibration result.
    - .kiln/logs/build-prd-model-calibration-<date>.md exists with
      the cost/quality matrix and per-agent decision rationale.
    - A delta-cost estimate of "savings per build-prd run" surfaces
      in the calibration log (e.g., "moving auditor from Opus to
      Sonnet saves $X per pipeline").
---

# build-prd model cost calibration — pin cost-effective models per pipeline step

## What

A calibration pass over each agent in the build-prd pipeline (specifier, planner, tasks, implementer, qa-engineer, auditor, retrospective, debugger, smoke-tester) that picks the cheapest Claude model meeting a per-agent quality bar. Reuses the time/cost axes shipped in PR #178 (research-first runner) and `plugin-kiln/lib/pricing.json`. Output: `model:` frontmatter committed on each agent.md, plus a calibration log under `.kiln/logs/`.

## Why now

Build-prd is the longest-lived multi-agent pipeline in the system. Every run spawns ~7 agents end-to-end; if each defaults to Opus when Sonnet or Haiku would meet the quality bar, costs compound. The infrastructure to measure cost per agent already exists (research-first PR #178 shipped pricing.json + per-fixture cost axes); this item turns that infra on for the pipeline that uses the most tokens.

## Hardest part

Defining the quality bar per agent. Without a measurable correctness signal per role — spec passes validator, smoke-tester catches a real bug, auditor's false-positive rate is < 20%, retrospective's PI insight_score clears the threshold — downgrading to Haiku silently degrades pipelines. The bar IS the load-bearing input; without it, calibration is unfounded.

## Key assumptions

- The research-first cost infrastructure (pricing.json, per-fixture cost computation) generalizes to build-prd agents — already shipped, just needs to be applied.
- Each build-prd agent has a measurable success signal (audit pass, smoke pass, retro insight_score) usable as a quality gate.
- Cost deltas justify the calibration work — Opus is roughly 5× Sonnet and Sonnet is roughly 3× Haiku per the existing pricing table.

## Depends on

- `2026-04-24-research-first-time-and-cost-axes` — **HARD** (already shipped, PR #178). Pricing table + cost measurement is the load-bearing dep; nothing to wait on.
- `2026-04-24-wheel-per-step-model-selection` — **SOFT** (currently `phase: unsorted`). Without it, calibration lands at agent.md frontmatter level only; per-workflow-step overrides aren't possible. v1 ceiling, not blocker.

## Cheaper 80% version

Manual one-shot audit: run each build-prd agent at Haiku / Sonnet / Opus against one representative spec fixture. Compare audit-pass rate + cost per agent. Pick the cheapest model hitting ≥80% audit pass. Commit results as `model:` frontmatter on each agent.md. Skip research-first-runner integration in v1; the calibration log + agent.md edits are the deliverable. v2 wires agents into the research-first fixture format so calibration becomes reproducible.

## Breaks if deps slip

- **`wheel-per-step-model-selection` not ready** → calibration lives at agent.md level only. Acceptable for v1 since each agent has a stable role; per-step granularity is a v2 add.
- **Quality signal weak for an agent** → fall back to manual review of 3 sample outputs per model + commit a confidence note in the calibration log. Don't pin a model without ground truth.

## Acceptance signal

Every agent.md under `plugin-kiln/agents/` carries an explicit `model:` frontmatter citing its calibration result. A calibration log at `.kiln/logs/build-prd-model-calibration-<date>.md` documents the cost/quality matrix and savings-per-pipeline-run estimate. The next build-prd run pulls the pinned models and the cost is measurably lower.
