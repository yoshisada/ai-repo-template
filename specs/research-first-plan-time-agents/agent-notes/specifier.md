# Specifier friction notes — research-first-plan-time-agents

**Author**: specifier (kiln-research-first-plan-time-agents pipeline)
**Date**: 2026-04-25
**Branch**: `build/research-first-plan-time-agents-20260425`

## Decisions on ambiguous PRD points

The PRD body left two open questions in §"Risks & Open Questions". Resolved during spec authoring:

1. **OQ-1 (judge abstention `unsure`)** — RESOLVED NO in v1. Encoded as **FR-012** (three-way verdict only). Rationale: forcing a verdict matches `direction: equal_or_better` semantics; abstention introduces a fourth case the orchestrator must handle with no clear gate-mapping. Re-open if first-real-use produces a genuinely-tied case (carried to spec.md OQ-1 → blockers.md item 2).
2. **OQ-2 (`fixture-schema.md` required vs inferred)** — RESOLVED REQUIRED in v1. Encoded as **FR-003** + **A-002**. Rationale: inferred schema introduces a silent-correctness failure mode (synthesizer guesses input shape from existing fixtures, produces a corpus that subtly diverges from the skill's actual contract). Loud-failure on missing schema; bare prereq check before spawn.

Five additional clarifications resolved during spec authoring (recorded in spec §"Clarifications / Session 2026-04-25"):

3. **`judge-config.yaml` location** — BOTH (per-developer `.kiln/research/judge-config.yaml` override + committed `plugin-kiln/lib/judge-config.yaml.example` fallback). Rationale: the PRD initially specified only the gitignored override path, which would crash on first run for every developer with no committed source-of-truth. Two-path resolution makes the default work everywhere AND lets developers pin different models locally. Encoded as **FR-014** + **plan.md Decision 4**.
4. **Diversity prompt location** — agent.md system prompt (not per-call composer-injected). Rationale: stable, role-defining instruction. Per-call context is the skill identifier + axes + count. Encoded as **FR-008**.
5. **FR-015 position-A-vs-B blinding seed** — deterministic via `sha256("<prd-slug>:<fixture-id>")` mod 2. Rationale: re-runs on the same PRD produce the same mapping → reproducible reports → testable. Encoded as **FR-015** + **NFR-008**.
6. **FR-006 regeneration budget** — bounded per-fixture only; total budget = `corpus_size × max_regenerations`. Surfaced in research-report header for auditability. Encoded as **FR-006** + **NFR-009**.
7. **Identical-input control construction** — orchestrator constructs (NOT synthesizer-emitted). Rationale: control's purpose is to detect drift on outputs the judge has actually seen — synthesizer-emitted control would test baseline judge behavior on a new input, not drift. Encoded as **plan.md Decision 6**.
8. **Verdict envelope contains BOTH blinded + de-anonymized verdicts** — per **plan.md Decision 7**. Rationale: self-contained audit trail; reviewer can verify de-anonymization without cross-referencing two files.

## NFR-006 baseline reconciliation

**PRD threshold**: `< 50 ms` for the `/plan` skip-path (PRDs declaring neither feature).

**Baseline measurement** (research.md §baseline, captured 2026-04-25 on macOS):
- In-process scan (already-running python3): **0.12 ms** median
- Shell `grep -E` single-pass: **~5 ms**
- python3 cold-start fork (no work): **~10 ms** (irreducible macOS floor — PR #168 NFR-H-5 pattern)
- jq cold-start fork (no work): **~5 ms**

**Verdict**: the threshold is reachable IF the skip-path detector re-uses the frontmatter parse `/plan` already does (sub-millisecond) OR a single `grep -E` (~5 ms). It is NOT reachable if the implementer adds a fresh python3 cold-fork solely for the probe (would burn 20% of the 50ms budget on a no-op decision).

**Reconciliation directive (accepted)**: rewrite NFR-006 / SC-006 as **`t_skip - t_baseline ≤ 50 ms`** with the structural invariant "no probe, no spawn" preserved as **NFR-006a** (no net-new agent spawn, no net-new subprocess EXCEPT the strictly-required spawn-or-skip decision probe). The measurement invariant is **NFR-006b** (`t_skip - t_baseline ≤ 50 ms` over 5 runs median, measured by `plugin-kiln/tests/plan-time-agents-skip-perf/`).

**Implementer constraint** (carried into tasks.md T012 + T015): the probe SHOULD be a single jq lookup on already-parsed JSON (sub-ms) OR a single `grep -E` (~5 ms). MUST NOT add a fresh python3 / jq cold-fork solely for the probe.

**Thresholds reconciled against `research.md §baseline`** ✅.

## Why single implementer (over split)

Both themes (synthesizer + judge) share `plugin-kiln/skills/plan/SKILL.md` as their spawn surface. The probe + spawn-or-skip decision logic is a SINGLE stanza that branches on `has_synthesized_corpus` and `has_output_quality_axis`. Splitting the SKILL.md edit across two implementers would:

1. **Risk file conflicts** — both implementers editing the same file region (Phase 1.5 stanza between current Phase 1 and "Stop and report").
2. **Bifurcate the skip-path probe** — if both implementers write their own conditional check, the skip path takes 2 probes instead of 1, doubling the budget consumed.
3. **Bifurcate the composer-recipe boilerplate** — both spawn paths use the same CLAUDE.md "Composer integration recipe"; duplicating it across files creates drift surface.

Single implementer with serial Phase B → Phase C work avoids all three. The themes are orthogonal in failure modes (synthesizer fails by triviality, judge fails by drift) but co-located in the wiring surface. Phase D tests are parallel-friendly across both themes.

## Handoff notes for implementer

### Existing-stub heads-up

Both agent files ALREADY EXIST as stubs at `plugin-kiln/agents/{fixture-synthesizer,output-quality-judge}.md` (committed in PR #178 build/agent-prompt-composition-20260425). Your job is to EXTEND them with role-specific operating prose, NOT to create them from scratch. Tools allowlists are already conformant — DO NOT change them (lint asserts).

### Composer + resolver heads-up

`plugin-wheel/scripts/agents/{compose-context.sh,resolve.sh}` are ALREADY SHIPPED (per A-004 in spec.md). Consume them via the canonical CLAUDE.md "Composer integration recipe" — do NOT bypass with bare `Agent({...})` calls. Plugin-prefixed `subagent_type` only (`kiln:fixture-synthesizer`, `kiln:output-quality-judge`); NEVER `general-purpose` (Architectural Rule 1).

### parse-prd-frontmatter.sh extension is ADDITIVE

`plugin-wheel/scripts/harness/parse-prd-frontmatter.sh` is from axis-enrichment (PR #178). Your extension (T005) is ONE NEW VALIDATOR STANZA — the existing JSON projection shape is UNCHANGED. The `rubric` field MUST be preserved character-for-character (no normalization, no whitespace trimming). This is critical for the rubric-hash invariant in §1 — if the validator normalizes whitespace, the orchestrator's `sha256(rubric)` won't match what the judge actually saw.

### Live-spawn validation is OUT OF SCOPE

Per CLAUDE.md Rule 5, agents shipped in this PR will not be live-spawn-validated in this session. All tests mock the spawn output. Live-spawn validation is the auditor's first follow-on activity in Task #3. The auditor will (a) start a fresh session, (b) spawn `kiln:fixture-synthesizer` + `kiln:output-quality-judge` against a synthetic PRD, (c) verify the relay envelopes match the contracts §6 + §7 shape.

### Foundation invariants

These files MUST remain BYTE-UNTOUCHED in this PR (carried from axis-enrichment NFR-AE-009 + foundation NFR-S-002):
- `plugin-wheel/scripts/harness/research-runner.sh`
- `plugin-wheel/scripts/harness/parse-token-usage.sh`
- `plugin-wheel/scripts/harness/render-research-report.sh`
- `plugin-wheel/scripts/harness/evaluate-direction.sh`
- `plugin-wheel/scripts/harness/compute-cost-usd.sh`
- `plugin-wheel/scripts/harness/resolve-monotonic-clock.sh`
- `plugin-kiln/lib/research-rigor.json`
- `plugin-kiln/lib/pricing.json`
- All foundation `wheel-test-runner.sh` + 12 sibling helpers.

Only ONE shared file is modified additively: `parse-prd-frontmatter.sh` (T005). Everything else is new (`evaluate-output-quality.sh`, lint scripts, judge-config example, agent prose, SKILL.md Phase 1.5 stanza).

### Test-fixture pattern reminder

Phase D mock-spawn tests follow the `plugin-kiln/tests/<test-name>/run.sh + fixtures/` precedent from foundation + axis-enrichment. The mock-spawn injection mechanism (T014, T016, T017, T019) is implementer's choice — document it in each test's `run.sh`. A reasonable approach: env var override `KILN_TEST_MOCK_AGENT_SPAWN=<path-to-mock-output-json>` checked by `evaluate-output-quality.sh` and the `/plan` SKILL Phase 1.5 stanza; when set, skip the live composer-spawn and read the mock envelope from disk.

### Commit cadence

Per Article VIII, commit per-phase: A → B → C → D → E. Mark each task `[X]` in tasks.md IMMEDIATELY after completion (not batched). Hooks will block raw `src/` edits if no `[X]` exists.

## Pipeline-level friction observations

(For the retrospective agent, Task #4.)

- **PRD → spec compression worked well** — the PRD body's "## Implementation Hints" sections quoted from the source items map cleanly to FR-001..FR-016. No PRD-spec divergence required beyond the OQ-resolution + NFR-006 reframe.
- **PRD threshold realism check (NFR-006) was the right friction-catching gate** — without baseline measurement, the implementer would have hit the 50ms wall and either (a) gold-plated the probe, or (b) silently violated the threshold. Step 1.5 baseline checkpoint is well-designed.
- **PRD-stub-already-exists realization** — the team-lead's prompt described the agents as "two NEW plan-time agents" but `plugin-kiln/agents/{fixture-synthesizer,output-quality-judge}.md` ALREADY EXIST as stubs from PR #178. Specifier surfaced this in research.md §"Composer-integration sanity" and re-scoped Phase B from "create" to "extend". Recommend the team-lead check `ls plugin-kiln/agents/` before describing future agents as "new".
- **Single-implementer guidance from team-lead was on-point** — bifurcating SKILL.md across two implementers would have created file-conflict and bifurcated-probe risks.
- **Two-path config resolution (Decision 4) emerged from spec-authoring, not from PRD body** — the PRD specified only `.kiln/research/judge-config.yaml` (gitignored); the example fallback at `plugin-kiln/lib/judge-config.yaml.example` was added during spec authoring after realizing the gitignored-only path would crash on first run for every developer. Suggests a future PRD-author checklist item: "if you specify a config-file path, verify it's not in a gitignored directory".
