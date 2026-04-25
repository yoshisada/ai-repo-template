---
name: kiln-research
description: "Run the baseline-vs-candidate research substrate against a declared fixture corpus. Emits a comparative markdown report at .kiln/logs/research-<uuid>.md with a strict-gate verdict (any regression on accuracy OR tokens fails). Three required args: <baseline-plugin-dir> <candidate-plugin-dir> <corpus-dir>."
---

# /kiln:kiln-research

**Purpose**: Drive the existing `kiln-test` substrate twice per fixture (baseline arm + candidate arm) and emit a comparative report. v1 declared-corpus only — no synthesizer, no per-axis direction, no judge.

**Non-negotiable**: this skill MUST delegate to wheel's `scripts/harness/research-runner.sh`, resolved via the dual-layout sibling traversal shown in "What to do" below. No repo-relative `plugin-kiln/scripts/...` or `plugin-wheel/scripts/...` path may appear in this file.

## Invocation forms (FR-S-007)

| Form | What it does |
|---|---|
| `/kiln:kiln-research --baseline <dir> --candidate <dir> --corpus <dir>` | Run the runner with explicit args. |
| `/kiln:kiln-research --baseline <dir> --candidate <dir> --corpus <dir> --report-path <p>` | Override report output location (used by tests for determinism). |

## What to do

Resolve the wheel install dir, then invoke the runner:

```bash
if [ -d "${WORKFLOW_PLUGIN_DIR}/../plugin-wheel" ]; then
  WHEEL_DIR="${WORKFLOW_PLUGIN_DIR}/../plugin-wheel"
else
  WHEEL_DIR=$(ls -d "${WORKFLOW_PLUGIN_DIR}/../../wheel"/*/ 2>/dev/null | sort -V | tail -1)
fi
bash "${WHEEL_DIR}/scripts/harness/research-runner.sh" $ARGUMENTS
```

That's the entire skill. The runner emits TAP v14 on stdout, writes the comparative report to `.kiln/logs/research-<uuid>.md`, and retains per-arm scratch dirs under `/tmp/kiln-test-<uuid>/` on failure for post-mortem.

## Exit codes

- **0** — all fixtures pass (`Overall: PASS`).
- **1** — at least one fixture regression (`Overall: FAIL`). See per-fixture verdict in the report.
- **2** — at least one fixture inconclusive (missing files, stalled, parse error, empty corpus, malformed args). See `Bail out!` line on stdout.

## Forward-compat: `fixture_corpus:` PRD frontmatter (FR-S-006)

A PRD that opts into research-first MAY declare `fixture_corpus: <path>` in its frontmatter. The v1 runner does NOT read this — `/kiln:kiln-build-prd` wiring lands in step 6 of the `09-research-first` phase. Documented here so step 6 can ship without a contract change.

## Full how-to

See `plugin-wheel/scripts/harness/README-research-runner.md` for the one-page how-to with worked example using the seed corpus at `plugin-kiln/fixtures/research-first-seed/corpus/`.
