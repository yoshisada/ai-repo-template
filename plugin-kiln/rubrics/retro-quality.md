# Retrospective Quality Rubric

**Purpose**: Define the minimum substance bar for `/kiln:kiln-build-prd` retrospective issues. Used by the retrospective agent's self-rating prompt (FR-024 of `claude-audit-quality`).

## What counts as a high-substance retro

A high-substance retro contains at least ONE of the following:

1. **Non-obvious cause-and-effect claim** — names a specific failure mode in this run AND attributes it to a specific root cause that wasn't already documented in the spec / plan. "Tests failed because the fixture path was wrong" is obvious; "tests failed because the agent assumed `WORKFLOW_PLUGIN_DIR` was env-inherited but harness-spawned sub-agents don't inherit env" is non-obvious and process-relevant.
2. **Calibration update with reasoning** — observes that a prior estimate (timing, complexity, blast radius, review cost) was wrong, AND offers a one-sentence reason the model now believes a different estimate would be correct next time.
3. **Process-change proposal** — proposes a concrete change to a skill / agent / hook / workflow / template (the "PI proposals" pattern), with the file named, the current behavior described, and the proposed behavior described. Bold-inline format preferred.

## Rating scale

| Score | Meaning |
|---|---|
| 1 | None of the three criteria met. The retro is a status report. |
| 2 | One criterion partially met (e.g. names a failure but no root cause). |
| 3 | One criterion fully met. (Default threshold for "passes" — below this fires the team-lead warning.) |
| 4 | Two criteria fully met. |
| 5 | All three criteria fully met, with non-obvious content. |

## How the agent self-rates

The retrospective agent applies this rubric verbatim to the retro body it just drafted. It MUST emit:

```yaml
insight_score: <integer 1-5>
insight_score_justification: <one-line; cites the criterion(a) driving the score>
```

The justification names the criterion(a) that drove the score — e.g. "process-change proposal: bold-inline PI for require-feature-branch.sh". Honest self-rating is the contract; if the retro is a status report, the agent emits `1`, not `3` to game the threshold.
