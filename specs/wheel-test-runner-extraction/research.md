# Research — wheel-test-runner-extraction

**Author**: researcher-baseline
**Date**: 2026-04-25
**Branch**: build/wheel-test-runner-extraction-20260425
**PRD**: [`docs/features/2026-04-25-wheel-test-runner-extraction/PRD.md`](../../docs/features/2026-04-25-wheel-test-runner-extraction/PRD.md)

This research artifact captures the **pre-PRD baselines** that the auditor will compare against for the headline gates SC-R-1 and SC-R-2. Per the new §1.5 Baseline Checkpoint rule from `kiln-build-prd` SKILL.md (issue #170 fix), the specifier MUST reconcile any quantitative thresholds in `spec.md` against these numbers BEFORE finalizing.

---

## §baseline-snapshot — SC-R-1 verdict-report shape baselines

### Summary table

| Fixture | Harness path | Artifact captured | Pre-PRD baseline file |
|---|---|---|---|
| `plugin-kiln/tests/perf-kiln-report-issue/` | `bash run.sh` (NOT kiln-test.sh; `harness-type: static` is dead metadata — see Observation 1) | `run.sh` stdout + `/tmp/perf-results.tsv` + `/tmp/perf-medians.json` | `perf-baseline-runlog.txt`, `perf-baseline.tsv`, `perf-baseline-medians.json` |
| `plugin-wheel/tests/preprocess-substitution.bats` | `bats <path>` | TAP v14 stdout (15 tests) | `baseline-snapshot/preprocess-substitution.bats-pre-prd.md` |
| `plugin-kiln/tests/kiln-distill-basic/` | `/kiln:kiln-test plugin-kiln kiln-distill-basic` (or `bash plugin-kiln/scripts/harness/kiln-test.sh plugin-kiln kiln-distill-basic`) | `.kiln/logs/kiln-test-<uuid>.md` (watcher-emitted verdict report) | `baseline-snapshot/kiln-distill-basic-pre-prd.md` + `baseline-snapshot/kiln-distill-basic-pre-prd-verdict.json` |

**Important**: The three named fixtures DO NOT all flow through `kiln-test.sh`. Only `kiln-distill-basic` produces a watcher verdict report. The auditor's snapshot-diff invariant is **heterogeneous per-fixture** — different invocations, different artifact shapes. See `agent-notes/researcher-baseline.md` for the full friction note.

### Reproducible methodology — fixture 1 (`perf-kiln-report-issue`)

```bash
# From repo root:
bash plugin-kiln/tests/perf-kiln-report-issue/run.sh > runlog.txt 2>&1
cp /tmp/perf-results.tsv .       # the perf TSV
cp /tmp/perf-medians.json .      # post-run computed medians (if gate (a) ran)
```

Pre-PRD baseline saved at:
- **Run log**: `/Users/ryansuematsu/Documents/github/personal/ai-repo-template/specs/wheel-test-runner-extraction/research/perf-baseline-runlog.txt`
- **TSV**: `/Users/ryansuematsu/Documents/github/personal/ai-repo-template/specs/wheel-test-runner-extraction/research/perf-baseline.tsv` (see §perf-baseline below)
- **Medians**: `/Users/ryansuematsu/Documents/github/personal/ai-repo-template/specs/wheel-test-runner-extraction/research/perf-baseline-medians.json`

What the auditor compares post-PRD: **(a)** stdout structure (PASS/FAIL line shape, "Resolver phase median (N=5):" header), **(b)** TSV column shape (`sample arm elapsed_sec duration_ms api_ms num_turns in_tok out_tok cache_read cache_create cost_usd stop`), **(c)** medians computed by the in-script python block. NOT byte-identical content for the LLM-driven gate (a) — that's stochastic.

### Reproducible methodology — fixture 2 (`preprocess-substitution.bats`)

```bash
# From repo root:
bats plugin-wheel/tests/preprocess-substitution.bats
```

Pre-PRD baseline saved at:
- `/Users/ryansuematsu/Documents/github/personal/ai-repo-template/specs/wheel-test-runner-extraction/research/baseline-snapshot/preprocess-substitution.bats-pre-prd.md`

Result: `1..15` plan, all 15 tests `ok`. Post-PRD MUST produce byte-identical output (this is pure-shell, no LLM, fully deterministic — true byte-identity is achievable here).

### Reproducible methodology — fixture 3 (`kiln-distill-basic`)

```bash
# From repo root (requires claude CLI on PATH; ~2-5 min, costs ~$0.10):
bash plugin-kiln/scripts/harness/kiln-test.sh plugin-kiln kiln-distill-basic
# Then locate the most recent verdict report:
ls -t .kiln/logs/kiln-test-*.md | head -1
```

Pre-PRD baseline saved at:
- `/Users/ryansuematsu/Documents/github/personal/ai-repo-template/specs/wheel-test-runner-extraction/research/baseline-snapshot/kiln-distill-basic-pre-prd.md`
- `/Users/ryansuematsu/Documents/github/personal/ai-repo-template/specs/wheel-test-runner-extraction/research/baseline-snapshot/kiln-distill-basic-pre-prd-verdict.json`

**Constraint** (per prompt's "If any fixture won't run quickly..."): The captured baseline is the most recent existing run from `.kiln/logs/kiln-test-19d37581-10ab-4cf1-b19b-78d132ed7229.md` (mtime 2026-04-24 00:09, skill: `kiln:kiln-distill`). I did NOT re-run kiln-distill-basic live for this baseline because (i) the perf-baseline run (Job 2) is already consuming my LLM budget, (ii) re-running once doesn't make this comparator any more byte-identical — the LLM output portion is stochastic regardless.

**Implication for SC-R-1 byte-identity**: For `kiln-distill-basic` the auditor MUST diff only the **framing** of the verdict report — the `# kiln-test verdict` header, the bullet list of fields (Classification, Scratch UUID, Stall window, Poll interval), the `## Scratch files` section structure (sorted file list), and the `## Last 50 transcript envelopes` SECTION HEADER (not its body — that's LLM output). The byte-identity PRD goal needs spec-phase refinement to articulate this exclusion list correctly. R-R-3 acknowledges this risk but underspecifies the mitigation; see `agent-notes/researcher-baseline.md` Suggestion 1.

### Observation 1: `harness-type: static` is dead metadata

`plugin-kiln/tests/perf-kiln-report-issue/test.yaml` declares `harness-type: static`, but `plugin-kiln/scripts/harness/dispatch-substrate.sh` only implements `plugin-skill` — `static` falls through to `Substrate '<X>' not implemented in v1` (exit 2). The fixture is invoked via its own `bash plugin-kiln/tests/perf-kiln-report-issue/run.sh` directly, NEVER through `kiln-test.sh`. This reinforces NFR-R-3 (backward compat strict): `wheel-test-runner.sh` need only handle the `plugin-skill` substrate to remain back-compat. The harness-type extension is the parent goal's roadmap item #2 (`shell-test-substrate`).

---

## §perf-baseline — SC-R-2 perf metrics baseline

### Methodology

```bash
# From repo root, no env overrides:
bash plugin-kiln/tests/perf-kiln-report-issue/run.sh
# Driver writes /tmp/perf-results.tsv (N=5 alternating before/after samples).
# Script computes medians and writes /tmp/perf-medians.json.
```

**Sample protocol** (per `perf-driver.sh`): N=5 alternating "before" / "after" samples invoking `/kiln:kiln-report-issue` against a synthetic scratch dir; `before` arm uses `perf-before.sh`, `after` arm uses `perf-after.sh`. Total wall-clock ~3 min for the LLM portion.

**Captured artifacts**:
- TSV: `/Users/ryansuematsu/Documents/github/personal/ai-repo-template/specs/wheel-test-runner-extraction/research/perf-baseline.tsv`
- Medians JSON: `/Users/ryansuematsu/Documents/github/personal/ai-repo-template/specs/wheel-test-runner-extraction/research/perf-baseline-medians.json`
- Run log: `/Users/ryansuematsu/Documents/github/personal/ai-repo-template/specs/wheel-test-runner-extraction/research/perf-baseline-runlog.txt`

### Median values — pre-PRD `after`-arm

Live N=5 alternating-arm run completed 2026-04-25 (this researcher session). Raw samples at `specs/wheel-test-runner-extraction/research/perf-baseline.tsv`. Final 1-passed-1-failed gate result: gate (a) PASS (NFR-F-4 within 120% of b81aa25), gate (b) FAIL (NFR-F-6 resolver overhead — pre-existing, see §observation).

| Metric | After-arm median (N=5) | b81aa25 reference | Δ vs. b81aa25 |
|---|---|---|---|
| `wall_clock_sec` | **7.751s** | 8.405s | -7.8% |
| `duration_api_ms` | **4364ms** | 4382ms | -0.4% |
| `num_turns` | **2** | 2 | exact |
| `output_tokens` | **180** | 176 | +2.3% |
| `cache_read_input_tokens` | **48621** | 48476 | +0.3% |
| `total_cost_usd` | **$0.11794** | $0.11862 | -0.6% |

**Before-arm median wall-clock**: 11.210s (informational; the perf-driver alternates before/after but only `after` is the path /kiln:kiln-report-issue uses today).

**Tolerance band visible in this sample**: `wall_clock_sec` ranges 7.401s–8.877s in the 5 `after` samples — that's a **±9.5%** spread around the median in raw samples. ±10% threshold (PRD's SC-R-2) is RIGHT AT this noise floor. ±20% (precedent NFR-F-4) is comfortable. Documented and recommended in the reconciliation directive below.

### Reference baseline (b81aa25 — PR #168)

For continuity, the prior PRD's frozen baseline at `plugin-kiln/tests/perf-kiln-report-issue/baselines/b81aa25-after.json`:

```json
{
  "samples": 5,
  "after_arm_medians": {
    "elapsed_sec": 8.405,
    "duration_api_ms": 4382,
    "num_turns": 2,
    "output_tokens": 176,
    "cache_read_input_tokens": 48476,
    "total_cost_usd": 0.118623
  },
  "thresholds": {
    "elapsed_sec_max": 10.086,
    "duration_api_ms_max": 5258
  }
}
```

The PRD's SC-R-2 says "within ±10% of pre-merge medians". The b81aa25 baseline's prior threshold band was 120% (NFR-F-4). The specifier must reconcile: is SC-R-2's ±10% intentionally tighter than the prior PRD's ±20%? If so, the ±10% threshold against THIS researcher's pre-PRD medians may not pass even on a no-op extraction (LLM run-to-run noise routinely exceeds 10%).

### Recommendation to specifier

**RECOMMENDED THRESHOLD ADJUSTMENT**: relax SC-R-2 from "±10%" to "±20%" (matching the precedent NFR-F-4 from PR #168). LLM perf samples have run-to-run noise that ±10% will not consistently absorb on a pure relocation. Document the tolerance band explicitly:

> SC-R-2 (revised proposal): post-merge `after`-arm medians within **±20%** of pre-PRD `after`-arm medians for `wall_clock_sec` AND `duration_api_ms`. `num_turns` MUST be exact (deterministic — protocol shape, not perf). `output_tokens` advisory band ±10% (token count is more stable than wall-clock). `cost_usd` derived from tokens — informational only.

If the specifier insists on ±10%, the implementer will need to budget for a re-run loop (capture N=10 instead of N=5; use trimmed mean, not median; document that single-run failures are not blockers).

---

## §observation — incidental findings during baseline capture

### NFR-F-6 (resolver overhead) is currently failing on main

During the perf-baseline run, gate (b) measured the resolver+preprocess phase median at **387ms** against the 200ms threshold. This is **NOT caused by this PRD** (we haven't touched the runtime libs yet), but it IS a pre-existing regression vs. PR #168's gate. Specifier should note this in `spec.md` to head off auditor confusion: "the wheel-test-runner-extraction PRD is NOT responsible for the NFR-F-6 regression visible on the pre-PRD baseline run; track separately."

Sample: `Resolver phase median (N=5): 387.08ms (samples: 282.21 810.31 475.67 349.49 387.08)`. Wide spread (282–810ms) suggests cold-start variance — possibly a `claude` plugin discovery cache miss on first invocation. Worth a follow-up issue but **out of scope** for this PRD.

---

## §reconciliation directive (for specifier)

Per the §1.5 Baseline Checkpoint rule, before finalizing `spec.md` you MUST:

1. **Reconcile SC-R-2's ±10% threshold** against the actual run-to-run noise visible in `perf-baseline.tsv`. Recommend ±20% per the precedent (see §perf-baseline above). Document the tolerance band explicitly in `spec.md` rather than referencing "the PRD's ±10%" verbatim.
2. **Refine SC-R-1's "byte-identical (modulo timestamps + UUIDs)"** for the LLM-driven `kiln-distill-basic` fixture. The transcript envelopes section IS NOT byte-stable across runs; the exclusion list must be section-level, not regex-level. Pin the exact comparator in `contracts/` (e.g., a snapshot-diff script that knows about the framing/transcript split).
3. **Note the `harness-type: static` dead-metadata observation** so NFR-R-3 (backward compat) is scoped correctly: only the `plugin-skill` substrate path matters for backward compat. `harness-type: static` is observable in test.yaml files but is not a runnable substrate today.
4. **Note the NFR-F-6 (resolver overhead) pre-existing regression** so the auditor doesn't blame this PRD for a number that's already off-budget on main.

Tolerances and exclusions documented in `spec.md` — not just the PRD — are the spec-phase obligation. Don't paper over the gap between PRD prose and observed reality.

---

## File index

```
specs/wheel-test-runner-extraction/research/
├── baseline-snapshot/
│   ├── preprocess-substitution.bats-pre-prd.md       # bats TAP output, 15/15 ok
│   ├── kiln-distill-basic-pre-prd.md                  # most recent .kiln/logs/ verdict report (kiln:kiln-distill, 2026-04-24)
│   └── kiln-distill-basic-pre-prd-verdict.json        # corresponding verdict.json
├── perf-baseline.tsv                                  # N=5 live perf run, raw TSV
├── perf-baseline-medians.json                         # computed after-arm medians
└── perf-baseline-runlog.txt                           # full run.sh stdout + stderr
```
