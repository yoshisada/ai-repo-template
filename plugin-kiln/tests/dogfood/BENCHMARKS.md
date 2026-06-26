# kiln-build-prd — unattended run benchmarks

Measured by driving `kiln-build-prd` end-to-end in an interactive tmux `claude` session
(`run-buildprd-e2e.sh`) with **no nudging**, instrumented by a PID+cursor probe sampling every
12s. Feature under test: the `slugify` PRD (3 FRs, 1 pure function — a deliberately small,
stable fixture so timings are comparable across runs).

## Headline

| Configuration | Outcome | Wall-clock |
|---|---|---|
| Teams (implement + audit as agent-teams) — **babysat** | full archive, required manual nudges | **68.5 min** |
| Teams — **unattended** | ❌ never archives (driving process dies at the team teardown) | — |
| **Delegates (implement + audit as `delegate`) — unattended** | ✅ **full SUCCESS archive, zero nudges** | **17.6 min** |

The team→delegate conversion is what made an unattended full run possible at all (see
`project_capstone_full_e2e` memory for the root-cause probe). It is also ~**3.9× faster** than the
babysat team run, because it removes team coordination/churn — the implement step alone went from
~6–8 min (team) to ~2 min (delegate).

## Per-step timings — team-free unattended run (run #15, 2026-06-26)

| Step | Type | Model | Duration |
|---|---|---|---|
| query-precedent | delegate | haiku | 85s |
| specify | delegate | sonnet | 48s |
| plan | delegate | sonnet | 85s |
| tasks | delegate | sonnet | 73s |
| **implement** | delegate | sonnet | **121s** |
| smoke-review | agent | sonnet | 24s |
| checkpoint-post-implement | branch | — | 13s |
| audit-prd-auditor | delegate | sonnet | 72s |
| **audit-spec-enforcer** | delegate | sonnet | **170s** ← slowest |
| audit-quality-judge | delegate | sonnet | 121s |
| audit-synthesize | agent | haiku | 24s |
| fix-blocking | agent | sonnet | 12s |
| checkpoint-pre-pr | branch | — | 12s |
| collect-retro | agent | sonnet | 37s |
| classify-proposals | agent | haiku | 24s |
| build-summary | agent | haiku | 49s |
| **TOTAL** | | | **1054s (17.6 min)** |

## Lines-of-code / minute

- Implementation output for `slugify`: **~47 LOC** (`src/slugify.ts` + test; measured in prior runs —
  the implement subagent writes via Bash heredocs so it isn't always captured in the lead transcript).
- **Implement-phase rate:** ~47 LOC / 121s ≈ **23 LOC/min** (the rate while actually coding).
- **End-to-end rate:** ~47 LOC / 17.6 min ≈ **2.7 LOC/min** (whole pipeline — spec→plan→tasks→
  implement→smoke→3-role audit→synth→retro→summary, i.e. LOC is a small fraction of the work).

LOC/min is most meaningful as the *implement-phase* number; the end-to-end number is dominated by
spec/plan/audit reasoning, not typing, so it scales sub-linearly with feature size.

## Efficiency levers (applied / candidate)

- ✅ **applied + MEASURED — `audit-spec-enforcer` → haiku.** It was the single slowest step (170s on
  sonnet) and its own instruction calls it "haiku-simple, mechanical" (FR-comment + test-traceability
  checks). Run #16 (haiku) measured it at **72s — a 58% drop (170s→72s)** while still archiving to
  success (the haiku verdict was accepted by audit-synthesize). `prd-auditor` and `quality-judge` stay
  on sonnet (judgement). Two consecutive unattended full archives (run #15 sonnet, run #16 haiku)
  confirm the team-free pipeline is reproducible, not a fluke.
- candidate: the 3 audit roles run **sequentially** (~6.5 min combined) because parallel = teams =
  process death. If agent-teams stabilize in this environment, parallelizing audit reclaims ~4 min.
- candidate: `query-precedent`/`plan`/`tasks` are ~73–85s each; tightening their delegate prompts
  (less re-reading) could shave the front half.

## How to reproduce

```
bash plugin-kiln/tests/dogfood/run-buildprd-e2e.sh      # drives unattended, polls to archive
# probe per-step timing + PID liveness: see the inline probe in the session that produced this file
```
