---
id: 2026-04-24-research-first-fixture-format-mvp
title: "Research-first step 1 — fixture corpus format + baseline-vs-candidate runner MVP"
kind: feature
date: 2026-04-24
status: open
phase: 09-research-first
state: planned
blast_radius: feature
review_cost: careful
context_cost: 3 sessions
implementation_hints: |
  Extend kiln-test's headless substrate (`claude --print --verbose --input-format=stream-json ... --plugin-dir`)
  to accept TWO plugin-dir paths per run: baseline and candidate. Run the same fixture against both and
  capture per-run metrics (input tokens, output tokens, cached tokens, assertion pass/fail verdict).

  Fixture corpus directory convention:

    plugin-<name>/fixtures/<skill>/corpus/
      ├── 001-<slug>/
      │   ├── input.json        # stream-json input replayed to the subprocess
      │   ├── expected.json     # assertion config (accuracy verdict reuses kiln-test logic)
      │   └── metadata.yaml     # axes covered, notes on why this fixture exists
      ├── 002-<slug>/
      ...

  v1 ships TWO axes only: accuracy (reuse kiln-test's pass/fail verdict) and tokens
  (input + output + cached, per fixture). Hardcoded strict gate: ANY fixture regressing on
  accuracy OR tokens fails the run. No per-axis `direction:` logic yet (that's step 2).
  No time / cost / output_quality yet (steps 3 and 5). No synthesizer (step 4).
  Declared-corpus only — the PRD declares `fixture_corpus:` pointing at a directory.

  Output: `.kiln/logs/research-<uuid>.md` with:
    - per-fixture row: baseline accuracy, candidate accuracy, baseline tokens, candidate tokens, delta, verdict
    - aggregate summary: N fixtures, M regressions, overall verdict

  Inherits design notes from `.kiln/roadmap/items/2026-04-24-skill-ab-harness-wheel-workflow.md`
  — that item is the origin idea; this step is its concrete MVP.
---

# Research-first step 1 — fixture corpus format + baseline-vs-candidate runner MVP

## What

Define the fixture-corpus directory format and extend the kiln-test runner to execute one corpus against two plugin-dirs (baseline + candidate), collecting per-fixture metrics and emitting a verdict report.

## Why now

The entire research-first phase depends on being able to run the same skill twice (against two plugin-dirs) over a set of examples and compare the results. Without this primitive, every downstream step is speculative. The kiln-test headless substrate solved the "run a skill against a fixture" problem in v0.1.9; this step solves "run two versions of a skill against a corpus."

## Hardest part

Deciding what belongs in the fixture-corpus format vs what belongs in per-fixture metadata. Overly-rigid schema blocks legitimate fixtures; overly-loose schema means the runner can't mechanically compare fixtures that test different things. Err toward rigid-for-v1, relax when a real fixture demands it.

## Cheaper version

Ship with only one plugin-dir flag (candidate only — compare against the previous git sha of the same plugin). Simpler UX but breaks when baseline is not a git ancestor (branch comparison, external fork). Not cheap enough to justify — accept the dual-plugin-dir interface up front.

## Dependencies

None — this is the foundation step.
