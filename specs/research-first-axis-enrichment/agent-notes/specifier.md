# specifier — friction note (FR-009)

**Teammate**: specifier
**Task**: #1 — Specify + plan + tasks (chained pass)
**Date**: 2026-04-25

## Reconciliation

Thresholds reconciled against `specs/research-first-axis-enrichment/research.md §baseline` (committed by researcher-baseline 2026-04-25, 66 lines). All three reconciliation directives applied:

- **Directive 1 (pricing)** — PRD example numbers were wrong on opus + haiku rows. Reconciled to 2026-04-25 Anthropic-published rates: opus `$5/$25/$0.50` (was `$15/$75/$1.50` — PRD example tracked legacy Opus 4/4.1), sonnet `$3/$15/$0.30` (matches PRD), haiku `$1/$5/$0.10` (was `$0.80/$4.00/$0.08` — PRD example tracked Haiku 3.5). Encoded in spec.md FR-AE-010, contracts/interfaces.md §8, tasks.md T002.
- **Directive 2 (time-axis tolerance)** — PRD-table `tolerance_pct` values STAY (5/2/1/0). Researcher-baseline measured 13.41% wobble on 180ms harness fixture, but harness floor is the wrong baseline (real research-runs are dominated by API latency in the 5–60s range). Reconciliation: keep tolerances as-is + ADD a sub-second-fixture guard (median wall-clock < 1.0s → silently un-enforce time axis, surface warning). Encoded in spec.md NFR-AE-001, plan.md Decision 2, tasks.md T013.
- **Directive 3 (monotonic clock)** — `gdate` is NOT reliably available on macOS dev environments (researcher confirmed not installed on probe host). Reconciliation: probe ladder is now `python3 time.monotonic()` (preferred — already a kiln dependency, genuinely monotonic, portable) → `gdate +%s.%N` → `/bin/date +%s.%N` → abort with documented `Bail out!`. NEVER fall back to integer-second `date +%s`. Encoded in spec.md NFR-AE-006, contracts/interfaces.md §6, tasks.md T004.

## PI candidates (for retrospective)

- **PI candidate 1**: Researcher-baseline finished task #2 BEFORE specifier started — coordination worked smoothly because the orchestrator brief named `specs/research-first-axis-enrichment/research.md` as the canonical contract path AND the spec dir was pre-spelled-out (no numeric prefix per FR-005). This is a good pattern; suggest formalizing in the kiln-build-prd template that "specifier checks for research.md §baseline before finalizing tasks; messages researcher-baseline if missing" lives in the orchestrator brief.
- **PI candidate 2**: The PRD's example pricing values were wrong on 2/3 model rows. The PRD itself acknowledged this ("Note: these are example numbers — confirm with current Anthropic pricing during implementation") but the wording is soft. Suggest a stronger PRD convention: **any quantitative threshold that depends on external rates SHOULD include a `requires_reconciliation: true` annotation** that distill / build-prd surfaces to the researcher-baseline teammate as a TODO. Today the connection is implicit; explicit annotation would let the orchestrator validate "every quant threshold has either a reconciliation directive or a `requires_reconciliation: false` justification."
- **PI candidate 3**: `parse-token-usage.sh` and `render-research-report.sh` from the foundation are listed as "additively extendable" in NFR-AE-009, but the foundation contract §10 listed them as untouchable. Resolved by promoting the renderer to "additively extendable" in this PRD's §11 (with the audit-compliance teammate verifying foundation's 5 fixtures still pass), and keeping `parse-token-usage.sh` byte-untouched. Suggest formalizing a "foundation file lifecycle" convention so future spec writers don't have to re-derive whether a foundation file is touchable each time.
- **PI candidate 4**: The atomic-pairing invariant (NFR-AE-005) needs a CI-runnable check. Plan §Decision 8 + tasks T026 wire this via `git diff main...HEAD --name-only | grep -E 'plugin-kiln/lib/(research-rigor|pricing)\.json'`. Suggest formalizing as a generic kiln rubric: "any PRD that ships paired config files MUST declare its pairing keys in spec.md and the audit teammate auto-generates the grep check."

## Artifacts written

- `specs/research-first-axis-enrichment/spec.md` (~440 lines, RECONCILED)
- `specs/research-first-axis-enrichment/plan.md` (~260 lines)
- `specs/research-first-axis-enrichment/contracts/interfaces.md` (~430 lines)
- `specs/research-first-axis-enrichment/tasks.md` (~150 lines)
- `specs/research-first-axis-enrichment/checklists/requirements.md` (~40 lines)
- This friction note.

## Spec dir naming compliance

Spec directory is `specs/research-first-axis-enrichment/` (no numeric prefix), per orchestrator FR-005 brief. Verified.

## Atomic-pairing compliance (NFR-AE-005)

tasks.md Phase B+C is explicitly INTERLEAVED — gate refactor (T010, T011) and time/cost axes (T008, T009) are sequential tasks on the SAME runner-extension file. No carved-out "axes-only" or "gate-only" subset. Plan §Decision 8 + tasks T026 wire the CI-runnable atomic-pairing tripwire.

## Backward-compat compliance (NFR-AE-003)

Plan §Decision 7 splits gate-mode dispatch via an EXPLICIT fall-through codepath (not direction-evaluator emulation), so foundation strict-gate output is byte-identical modulo the §3 exclusion comparator. T022 (SC-AE-005) re-runs foundation's 5 existing fixtures + the new fallback fixture for verification.

## Open questions for downstream teammates

- T021 (renderer extension): the renderer's existing column layout fits 120 cols on a 30-char-slug fixture (foundation NFR-S-005). Plan §Decision 1 lays out the new 4-column layout assuming the same slug ceiling. If a real fixture slug exceeds 30 chars, implementer MAY need to adjust the slug-truncation rule. Surface in `agent-notes/impl-runner.md` if hit.
- T026 (atomic-pairing tripwire): if the implementer ships a hot-fix that touches only ONE of `research-rigor.json` / `pricing.json`, audit-compliance MUST reject. The grep-based check is in place; if a future PRD adds a third paired file, the rubric in PI candidate 4 should land.

## Done conditions

- spec.md, plan.md, contracts/interfaces.md, tasks.md, checklists/requirements.md, this friction note: ✅ all written.
- Reconciliation against research.md §baseline: ✅ all three directives applied.
- Atomic-pairing invariant (NFR-AE-005): ✅ encoded in tasks Phase B+C interleaving + T026 tripwire.
- PRD-drift guard: ✅ pricing values RECONCILED (NOT locked to PRD example numbers).
- TaskUpdate to completed: pending (this teammate's last action).
