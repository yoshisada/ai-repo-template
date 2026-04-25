# researcher-baseline friction note

**Agent**: researcher-baseline (TaskList #2)
**Branch**: build/wheel-test-runner-extraction-20260425
**Date**: 2026-04-25

## What was confusing in my prompt

### 1. The three "representative fixtures" don't all share a verdict-report pipeline

The prompt says: *"For each, run the appropriate invocation today (via current `kiln-test.sh` path) and save the verdict report verbatim."*

But the three fixtures listed are **NOT all driven by `kiln-test.sh`**:

| Fixture | Invocation path | Produces `.kiln/logs/kiln-test-<uuid>.md` verdict? |
|---|---|---|
| `plugin-kiln/tests/perf-kiln-report-issue/` | `bash run.sh` (standalone) — its `test.yaml` declares `harness-type: static`, which **`dispatch-substrate.sh` does not implement** (only `plugin-skill` is in the case statement). It exits 2 with "Substrate 'static' not implemented in v1." | ❌ No — emits its own PASS/FAIL stdout + writes `/tmp/perf-results.tsv` and `/tmp/perf-medians.json`. |
| `plugin-wheel/tests/preprocess-substitution.bats` | `bats <path>` — pure bats suite, no `kiln-test.sh` involvement at all. | ❌ No — emits TAP v14 to stdout. |
| `plugin-kiln/tests/kiln-distill-basic/` | `/kiln:kiln-test plugin-kiln kiln-distill-basic` (or `bash plugin-kiln/scripts/harness/kiln-test.sh plugin-kiln kiln-distill-basic`) — `harness-type: plugin-skill`. | ✅ Yes — the watcher writes `.kiln/logs/kiln-test-<uuid>.md`. |

So SC-R-1's snapshot-diff invariant is heterogeneous — what gets diffed differs per fixture:
- For `perf-kiln-report-issue`: the `run.sh` stdout shape + the TSV columns + the `b81aa25-after.json` baseline schema.
- For `preprocess-substitution.bats`: the TAP v14 stream emitted by `bats`.
- For `kiln-distill-basic`: the `.kiln/logs/kiln-test-<uuid>.md` watcher-emitted verdict report.

The auditor will need to run three different invocations to produce the post-PRD comparator. I documented all three explicitly in `research.md §baseline-snapshot` so the auditor isn't left guessing.

### 2. §1.5 Baseline Checkpoint guidance vs. what I had to invent

§1.5 (per the PRD's Pipeline guidance) tells the specifier to reconcile thresholds against observed reality. It does NOT prescribe:

- **Baseline-capture conventions**: file naming (`<fixture-name>-pre-prd.md` is what I picked), location under `specs/<feature>/research/baseline-snapshot/`, what counts as the "pre-PRD" stable artifact when a fixture's normal output is `.kiln/logs/kiln-test-<uuid>.md` (path varies per run).
- **What to do when "verdict report" is the wrong noun for the fixture's output**: the prompt assumes a single verdict-report shape, but two of three fixtures use other shapes (TSV, bats TAP).
- **What to capture when a fixture cannot run quickly**: I documented the constraint and snapshotted a representative existing verdict report from `.kiln/logs/` (latest `kiln:kiln-distill` run, 2026-04-24, `kiln-test-19d37581-...md`). The auditor must NOT use this as a byte-for-byte oracle (LLM stochasticity) — only as a verdict-report **shape** baseline. Real byte-identity for `kiln-distill-basic` requires re-running both pre-PRD and post-PRD with identical scratch fixtures + a deterministic LLM seed (which we don't have).

### 3. SC-R-1's "byte-identical (modulo timestamps + UUIDs)" goal is harder than the PRD admits

For `kiln-distill-basic`, the verdict report contains:
- Timestamps (Session started, Last scratch write, Last transcript advance, Verdict emitted) — modulo-able.
- Scratch UUID — modulo-able.
- Scratch dir absolute path — modulo-able.
- **Transcript envelopes** including LLM-generated text (assistant messages, tool inputs, signatures) — **NOT modulo-able**. LLM output is non-deterministic across runs even with identical inputs.

R-R-3 in the PRD flags this risk but mitigation says "spec phase pins the exact exclusion regex". For LLM-driven fixtures the exclusion list isn't a regex — it's "skip the entire transcript envelopes section, only diff the framing/structure". This needs explicit treatment in the spec.

### 4. The perf baseline already exists at `b81aa25-after.json`

The PRD asks for a "full N=5 live run" producing medians for `num_turns / wall_clock_sec / duration_api_ms / output_tokens / cost_usd`. But `plugin-kiln/tests/perf-kiln-report-issue/baselines/b81aa25-after.json` already encodes these exact medians at commit b81aa25 (PR #168 baseline). I re-ran live to get the current-tip pre-extraction medians for an apples-to-apples comparison, but the auditor should also know `b81aa25-after.json` exists and can be referenced directly as the back-stop baseline.

## Where I got stuck

- **Resolver overhead gate (NFR-F-6) failed during my baseline run**: median 387ms > 200ms threshold. This is unrelated to wheel-test-runner-extraction (it's a prior PRD's gate) but it's failing on current main. Documented in `research.md §observation`. Auditor should not interpret this as a regression caused by this PRD.
- The `harness-type: static` declaration in `perf-kiln-report-issue/test.yaml` is dead metadata — `dispatch-substrate.sh` doesn't implement that substrate. The fixture is invoked via its own `run.sh` directly. This reinforces that `wheel-test-runner.sh` only needs to handle `plugin-skill` substrate to maintain backward compat (NFR-R-3) — the harness-type extension is roadmap item #2.

## Suggestions

1. **`kiln-build-prd` SKILL.md §1.5**: add a sentence directing the researcher to "if the pipeline asks for byte-identical baselines on LLM-driven fixtures, EXPLICITLY note that 'byte-identical' applies only to the framing/structure, not the embedded LLM output — and pin the exclusion list at the section level (skip `## Last 50 transcript envelopes` body) rather than at the regex level."
2. **`kiln-build-prd` SKILL.md researcher prompt template**: add a checklist row "for each named fixture, identify the actual invocation path and what artifact gets compared — verdict report, TSV, bats TAP, etc. Do not assume kiln-test.sh produces every test artifact in the repo."
3. **PRD authoring discipline**: when SC says "snapshot diff of three fixtures", the spec phase should resolve the heterogeneity (different invocations, different artifacts) into an explicit per-fixture comparator — not delegate that work to the auditor at gate time.
4. **`b81aa25-after.json` reuse**: the perf baseline JSON pattern (PR #168) is reusable. We should encode the wheel-test-runner-extraction perf baseline into `plugin-kiln/tests/perf-kiln-report-issue/baselines/<sha>-after.json` post-merge so the next PRD inherits it the same way.

## Cross-reference: did §1.5 give me enough guidance?

**Partially.** §1.5 told me TO capture baselines and TO have the specifier reconcile thresholds. It didn't give me the file-naming convention, the directory structure, the comparator format per fixture-type, or the LLM-stochasticity caveat. I invented all of those and documented them in `research.md` so the convention is now repo-precedent.

The pattern I'd want for the next pipeline: §1.5 should reference a "baseline-capture template" under `plugin-kiln/templates/` that the researcher fills in. Right now §1.5 is prose-only.
