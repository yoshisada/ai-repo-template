# Friction Note — Specifier (FR-009 of process-governance)

**Author**: specifier
**Date**: 2026-04-25
**Branch**: build/wheel-test-runner-extraction-20260425
**Pipeline phase**: Specify → Plan → Tasks (back-to-back, single uninterrupted pass)
**Cross-reference**: `agent-notes/researcher-baseline.md` (read first; reconciliation directives consumed inline in spec.md)

This note answers two questions explicitly per the specifier prompt: (1) did §1.5 work cleanly with researcher-baseline running first? and (2) did I actually need to recalibrate any thresholds, or were the PRD numbers already realistic?

---

## §1.5 Baseline Checkpoint — clean or friction-prone?

**Verdict: clean. The §1.5 sequencing was the right call.** Three concrete observations:

1. **Researcher-baseline produced exactly the artifacts the spec phase needed.** The `research.md §reconciliation directive` block named four discrete recalibrations with numerical evidence (raw spread ±9.5%, dead-metadata observation, pre-existing NFR-F-6 regression, section-level vs regex-level exclusion for kiln-distill-basic). Each one mapped 1:1 to a spec-phase decision I would have otherwise had to invent without evidence.
2. **The reconciliation directives saved a real architectural error.** The PRD's "byte-identical (modulo timestamps + UUIDs)" framing for SC-R-1 would have shipped a snapshot-diff comparator that fired false-positive on the LLM-stochastic transcript-envelopes section in `kiln-distill-basic`. Without baseline capture, this would have surfaced at audit time as a "false-positive on R-R-3," which is the exact failure mode R-R-3 names. §1.5 caught it before any code was written. Exactly the friction-loop §1.5 was designed to short-circuit.
3. **The directive #3 finding (`harness-type: static` is dead metadata) tightened spec scope correctly.** Without that observation, NFR-R-3 (backward compat strict) could have been read as "every declared `harness-type` value must continue to work post-extraction" — which would have over-scoped the implementer to also extract a `static` substrate that doesn't exist in the codebase. Surfacing the dead-metadata fact explicitly in spec.md prevents this misread.

**Suggestion for §1.5 prose**: the current §1.5 instruction in `kiln-build-prd` SKILL.md probably says something like "researcher captures baselines, specifier reconciles." Add a third sentence: "The specifier MUST acknowledge each reconciliation directive explicitly in spec.md (typically a §Reconciliation Against Researcher-Baseline section) — not just absorb the numbers. Acknowledgment is the audit trail; absorbing numbers silently leaves no record that the directive was considered."

---

## Did I actually recalibrate any thresholds?

**Yes, three thresholds were recalibrated. The PRD numbers were NOT realistic for two of them.**

### Recalibration 1: SC-R-2 ±10% → ±20% on wall_clock_sec / duration_api_ms

The PRD wrote SC-R-2 as "within ±10% of pre-merge medians." Researcher's N=5 live run showed raw `wall_clock_sec` spread of 7.401s–8.877s around a 7.751s median = ±9.5% in the SAMPLES THEMSELVES. ±10% on the median post-merge sits AT the noise floor — a pure-relocation PRD would routinely fail this gate due to LLM run-to-run variance, not because of a regression. ±20% is the comfortable band and matches the precedent NFR-F-4 from PR #168.

**Without baseline capture I would have shipped ±10%.** This is the canonical "PRD prose written without measurement" failure mode that §1.5 fixes.

### Recalibration 2: SC-R-1 byte-identity refined to per-fixture (section-level for kiln-distill-basic)

The PRD wrote SC-R-1 as "byte-identical (modulo timestamps + UUIDs)" — a single uniform exclusion for all three fixtures. Researcher's directive #2 surfaced that the three fixtures have HETEROGENEOUS artifact shapes:

- `preprocess-substitution.bats` is fully deterministic — true byte-identity post-modulo (none).
- `kiln-distill-basic` has an LLM-stochastic body (`## Last 50 transcript envelopes`) that no regex can normalize — must be excluded **section-level** (skip the entire body, NOT regex-match its content).
- `perf-kiln-report-issue` doesn't even route through `kiln-test.sh` — its TSV/medians-JSON shape is the back-compat invariant, NOT verdict-report contents (and so it's not actually a SC-R-1 fixture at all; it's the SC-R-2 substrate).

Spec.md now pins three modes (`bats`, `verdict-report`, `verdict-report-deterministic`) in `contracts/interfaces.md §3` with the exact section-split logic for `kiln-distill-basic`. Without this refinement, the auditor would have to invent an ad-hoc regex per fixture at audit time — exactly the R-R-3 false-positive risk.

### Recalibration 3 (negative — kept PRD value): NFR-R-6 ≤50ms façade overhead

The PRD's 50ms façade-overhead budget is realistic. Bash subprocess startup is ~5-10ms; one extra script-invocation hop fits comfortably under 50ms. No baseline contradicts this. Kept verbatim.

---

## Other friction encountered

### Friction 1: Three fixtures named in PRD include one that doesn't actually flow through kiln-test.sh

The PRD's SC-R-1 lists `perf-kiln-report-issue` as one of three representative fixtures. Researcher correctly observed that this fixture invokes its own `bash run.sh` directly — never through `kiln-test.sh`. So it can't be a SC-R-1 fixture for "verdict-report byte-identity" purposes. Spec.md handles this by:

- Removing `perf-kiln-report-issue` from the SC-R-1 trio.
- Substituting "an implementer-chosen fast-deterministic plugin-skill fixture" as the third snapshot-diff target.
- Documenting `perf-kiln-report-issue` exclusively as the SC-R-2 substrate (live-smoke gate).

**Suggestion for future PRD authors**: when naming "representative fixtures" for a back-compat byte-identity gate, verify each one actually flows through the surface being moved. The PRD author named `perf-kiln-report-issue` as a representative kiln-test fixture probably because it's the highest-profile fixture in the repo — but it's actually the `harness-type: static` ghost (researcher's directive #3) that bypasses kiln-test entirely.

### Friction 2: OQ-R-1 had three candidates but only option (a) was actually viable

The PRD listed options (a), (b), (c) for the script-resolution pattern. Option (a) `${WORKFLOW_PLUGIN_DIR}/../plugin-wheel/...` is the obvious choice for two reasons:
- Zero new wheel infrastructure required.
- Validated by `workflow-plugin-dir-bg` smoke pattern (PR #168).

Options (b) and (c) introduce coupling — (b) requires every kiln-test consumer to source a wheel helper; (c) embeds find-in-cache fallbacks. Both add complexity for a problem that doesn't need solving.

**Suggestion for PRD-writing**: when a PRD lists 3 candidates for a blocking OQ but the problem space genuinely has only 1 reasonable answer, just write the answer with a one-sentence rationale. The 3-candidate framing implies a real architectural decision is open; here it wasn't.

### Friction 3: Spec/plan/tasks back-to-back ≠ uninterrupted in the agent's mental model

The team-lead prompt said "run /specify, /plan, /tasks back-to-back, no idle." In practice for a sub-agent, "back-to-back" doesn't have meaning the same way it does for a human-driven pipeline — there's no slash-command harness here, just author the artifacts directly. I authored spec.md, plan.md, contracts/interfaces.md, and tasks.md as one continuous block of writes. This works, but the prompt could be clearer about that being the expected interpretation.

**Suggestion for `kiln-build-prd` SKILL.md**: when team-lead spawns a specifier sub-agent, the prompt should say "Author spec.md / plan.md / contracts/interfaces.md / tasks.md as one continuous unit" rather than "Run /specify then /plan then /tasks." The slash-command framing is a leaky abstraction — those commands are interactive harness flows that don't map cleanly onto agent-context execution.

---

## Suggestions for §1.5 prose (consolidated)

1. **Make reconciliation acknowledgment mandatory** (not just absorbed numbers). A `§Reconciliation Against Researcher-Baseline` section in spec.md that names each directive and the spec-phase response is the audit trail.
2. **Verify representative-fixture claims in PRD against actual code paths** before using them as SC anchors. The PRD's SC-R-1 named a fixture that didn't actually flow through the surface being moved.
3. **For OQ resolution: when the problem space has one obvious answer, just write it.** The 3-candidate framing is theatre when the constraints are clear (consumer-install layout, no new wheel infra, existing precedent).
4. **Distinguish "spec phase" from "slash-command interactive flow" in sub-agent prompts.** The spec/plan/tasks artifacts are the deliverables; the slash-command names are scaffolding that doesn't apply in agent context.

---

## Files authored this phase

- `specs/wheel-test-runner-extraction/spec.md`
- `specs/wheel-test-runner-extraction/plan.md`
- `specs/wheel-test-runner-extraction/contracts/interfaces.md`
- `specs/wheel-test-runner-extraction/tasks.md`
- `specs/wheel-test-runner-extraction/agent-notes/specifier.md` (this file)

OQs resolved: OQ-R-1 (option a), OQ-R-2 (`wheel-test-runner.sh`), OQ-R-3 (acknowledged — fossil prefix preserved).
Reconciliation directives consumed: all 4 from researcher-baseline (relax SC-R-2 to ±20%, refine SC-R-1 per-fixture, dead-metadata observation, NFR-F-6 pre-existing).
Article VII compliance: every exported entrypoint has a pinned signature in contracts/interfaces.md.
