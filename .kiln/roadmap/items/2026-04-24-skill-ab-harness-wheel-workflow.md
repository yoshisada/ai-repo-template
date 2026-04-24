---
id: 2026-04-24-skill-ab-harness-wheel-workflow
title: "Skill A/B harness as wheel workflow"
kind: feature
date: 2026-04-24
status: open
phase: unsorted
state: planned
blast_radius: feature
review_cost: careful
context_cost: 3 sessions
implementation_hints: |
  Wheel workflow that takes two plugin-dir paths (old version, new version) and runs both
  against the same kiln-test fixture, then compares results along three axes in priority order:

    1. Accuracy (PRIMARY gate) — did the new version still produce the assertion-passing output?
       If accuracy regresses, the A/B test FAILS. No token-savings argument overrides this.
       Reuse kiln-test's existing pass/fail verdict as the accuracy signal.

    2. Token usage — diff input/output/cached tokens between the two runs. Report savings or regressions.
       A pure efficiency win (accuracy held, tokens down) is the happy path.

    3. Output quality judgment (SECONDARY) — LLM-judged comparison of the two outputs on the dimensions
       the skill was *intended* to improve. If the new version performs worse on the axis the update
       was supposed to strengthen, the test FAILS even if accuracy held. Requires a judge-agent with
       a rubric derived from the PR / commit message / user-supplied intent.

  The kiln-test headless substrate (`claude --print --verbose --input-format=stream-json ... --plugin-dir`)
  is the execution primitive. The harness may need to extend kiln-test's runner to accept two plugin-dirs
  and diff their outputs — "make the setup more dynamic" per the interview.

  Verdict output: `.kiln/logs/skill-ab-<uuid>.md` with:
    - accuracy verdict per version (pass/fail from kiln-test)
    - token usage table (in/out/cached, diff, % change)
    - quality judgment on intended dimension (pass/fail + rationale)
    - overall A/B verdict (fail on ANY regression; pass only when accuracy held + intended-axis judgment held)

  Usage: `/wheel:wheel-run skill-ab <plugin>:<skill> --baseline <old-version-ref> --candidate <new-version-ref> --intent "<what the update was supposed to improve>"`.
---

# Skill A/B harness as wheel workflow

## What

A wheel workflow that runs two versions of the same skill (baseline and candidate) against the same kiln-test fixture and reports on three axes: accuracy, token usage, and intended-improvement quality. Failure on *any* axis fails the A/B test — a cheaper but worse-performing update is not a win.

## Why now

The `kiln-test` substrate landed in v0.1.9 — we now know how to run headless Claude against a fixture and classify the verdict. That's the hard primitive solved. The gap is tooling that uses it to answer "did this skill edit make things better or worse?" Without it, skill updates are shipped on vibes.

## Assumptions

- `/kiln:kiln-test` fixture format is stable enough to run as a shared input for two skill versions.
- The headless substrate can be pointed at two different `--plugin-dir` paths in one workflow run — may require extending the runner to take "baseline" and "candidate" paths.
- LLM-as-judge on a narrowly-defined intent axis produces a stable enough signal to gate on (this is the riskiest assumption — see Hardest part).

## Hardest part

Designing the quality judge so it actually catches "worse on the intended dimension" rather than rubber-stamping the candidate. Token usage is mechanical; accuracy reuses kiln-test's existing verdict. But "the update was supposed to make the skill more concise / more thorough / more structured — did it?" is a fuzzy rubric, and a naive judge will drift. The rubric has to be derived from the PR intent (commit message, user-supplied `--intent`) and passed to the judge verbatim, not summarized.

## Cheaper version

Skip the quality-judge axis for v1 — ship the workflow with accuracy + token usage only. Catches most "this edit is a pure regression" cases. Quality-judge is the v2 upgrade. BUT: user's preference per interview is to start with the expensive (full) mode for accuracy's sake. Document the cheaper variant as a fallback only if the judge-agent proves too noisy in practice.

## Dependencies

- Depends on: `/kiln:kiln-test` substrate (already shipped in v0.1.9).
- Depends on: wheel command-step + agent-step primitives (already ship).
- Depends on: Claude Code's `--plugin-dir` flag accepting arbitrary paths (already works).
