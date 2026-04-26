# Implementation Plan: Research-First Plan-Time Agents — fixture-synthesizer + output-quality-judge

**Branch**: `build/research-first-plan-time-agents-20260425` | **Date**: 2026-04-25 | **Spec**: [spec.md](./spec.md)
**Input**: `specs/research-first-plan-time-agents/spec.md`
**PRD**: `docs/features/2026-04-25-research-first-plan-time-agents/PRD.md`
**Foundation dependencies**:
  - `specs/research-first-foundation/{spec.md,plan.md,contracts/interfaces.md}` (PR #176, in main).
  - `specs/research-first-axis-enrichment/{spec.md,plan.md,contracts/interfaces.md}` (PR #178, in main).
  - `plugin-kiln/agents/fixture-synthesizer.md` + `plugin-kiln/agents/output-quality-judge.md` (stubs, in main).
  - `plugin-wheel/scripts/agents/compose-context.sh` + `resolve.sh` (composer, in main).
**Baseline research**: `specs/research-first-plan-time-agents/research.md` (RECONCILED 2026-04-25 — NFR-006 reframed to `≤ baseline + 50 ms` with `no probe, no spawn` structural invariant preserved).

## Summary

Ship two `/plan`-time agents (`kiln:fixture-synthesizer`, `kiln:output-quality-judge`) by extending **5 surfaces** in ONE PR:

1. **Agent role-specific operating prose** — extend the existing stubs at `plugin-kiln/agents/fixture-synthesizer.md` and `plugin-kiln/agents/output-quality-judge.md` with the input/output contract, anti-drift invariants (judge), diversity-prompt invariant (synthesizer), and the SendMessage-relay coordination protocol per CLAUDE.md Rule 6. Tools allowlists are NOT changed (already conformant — synthesizer `Read, Write, SendMessage, TaskUpdate`; judge `Read, SendMessage, TaskUpdate`).
2. **Frontmatter validator extension** — extend `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh` (from axis-enrichment) with the additive rule "`rubric:` is required-and-non-empty when `metric: output_quality`". No shape change to existing axes.
3. **Spawn-from-/plan wiring** — extend `plugin-kiln/skills/plan/SKILL.md` with a Phase 1.5 stanza that (a) probes the parsed frontmatter for `fixture_corpus: synthesized` OR `metric: output_quality`, (b) on hit, invokes the runtime composer (per CLAUDE.md "Composer integration recipe") to spawn each agent with role-instance vars, (c) on miss, takes a structural no-op skip-path (NFR-006a). Single edit point — see "Single-implementer rationale" in `agent-notes/specifier.md`.
4. **Orchestrator-side anti-drift plumbing** — ship a new helper at `plugin-wheel/scripts/harness/evaluate-output-quality.sh` that wraps:
    - `judge-config.yaml` resolution (per FR-014 — local override + committed example fallback).
    - Position-blinding seeded RNG (per FR-015 + NFR-008).
    - Identical-input control insertion (per FR-016).
    - Per-fixture judge spawn batching via composer.
    - Verdict envelope parsing + de-anonymization.
    - Drift detection halt (`Bail out! judge-drift-detected: ...`).
    - Stdout contract matches `evaluate-direction.sh` (`pass | regression`) so the existing per-axis gate from `specs/research-first-axis-enrichment/contracts/interfaces.md §4` consumes it without modification.
5. **Lint scripts + per-skill schema convention + judge config** —
    - `plugin-kiln/scripts/research/lint-judge-prompt.sh` (asserts `{{rubric_verbatim}}` token + no-summarization).
    - `plugin-kiln/scripts/research/lint-synthesizer-prompt.sh` (asserts diversity-prompt verbatim string).
    - `plugin-kiln/scripts/research/lint-agent-allowlists.sh` (asserts the 4 / 3 tool allowlist strings haven't drifted).
    - `plugin-kiln/lib/judge-config.yaml.example` (committed default pinned model + fallback list).
    - `plugin-kiln/skills/<example>/fixture-schema.md` template — NO commit-time per-skill schema is in scope for this PRD; the convention is documented in `plan.md` Decision 5 and asserted by SC-001 (synthesized-corpus PRD MUST commit a schema for the skill it targets).

The two themes are bundled in ONE PR per the PRD body's "coherent plan-time agent surface" rationale, but they are **independently testable** — synthesizer can ship and pass its 5 acceptance scenarios with the judge surface dormant, and vice versa. There is no atomic-pairing invariant in this PRD (unlike axis-enrichment, where the gate refactor + axes had to ship together). The single-PR bundling is for review-coherence, not structural correctness.

Implementation is an **extension** to two already-shipped substrates (foundation runner + axis-enrichment frontmatter parser) plus an extension to the existing `/plan` SKILL.md. Foundation-listed-untouchable files (`research-runner.sh`, `parse-token-usage.sh`, `render-research-report.sh`, `evaluate-direction.sh`, `compute-cost-usd.sh`, `resolve-monotonic-clock.sh`) remain byte-untouched. The composer (`compose-context.sh` + `resolve.sh`) is consumed but not modified (per A-004 in spec.md).

## Technical Context

**Language/Version**: Bash 5.x (orchestrator + helpers + lint scripts); Markdown (agent.md prose + SKILL.md prose); YAML (judge-config + frontmatter); JSON (verdict envelopes + position mapping + composer outputs).
**Primary Dependencies**:
- `plugin-wheel/scripts/agents/compose-context.sh` (composer — consumed only).
- `plugin-wheel/scripts/agents/resolve.sh` (resolver — consumed only).
- `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh` (axis-enrichment — extended additively for FR-010).
- `plugin-wheel/scripts/harness/evaluate-direction.sh` (axis-enrichment — consumed only; sibling helper for `output_quality` ships in this PRD).
- `claude` CLI v2.1.119+ (inherited from foundation).
- `jq` for JSON parsing (already a kiln dependency).
- `python3` for YAML frontmatter helpers AND for `sha256` seeded RNG in FR-015 (stdlib `hashlib` + `re`/`json`; no PyYAML dependency — same hand-rolled approach as `compose-context.sh`).
- `shasum -a 256` (macOS) / `sha256sum` (Linux) for `rubric_verbatim_hash` in FR-012 (already established cross-platform pattern in `plugin-kiln/scripts/roadmap/promote-source.sh`).
**Storage**: filesystem only — `judge-config.yaml.example` committed at `plugin-kiln/lib/`, per-developer `judge-config.yaml` at `.kiln/research/` (gitignored, foundation precedent), per-PRD scratch at `.kiln/research/<prd-slug>/{corpus/,judge-verdicts/,position-mapping.json,synthesis-report.md,judge-drift-report.md}` (all gitignored).
**Testing**: shell-test fixtures under `plugin-kiln/tests/<test-name>/` matching the existing precedent (each fixture is a `run.sh` + `fixtures/` directory). Live agent spawn is OUT-OF-SCOPE for tests — all tests mock the spawn output (write a synthetic verdict envelope, write synthetic synthesizer output) and assert the orchestrator's deterministic logic. Live-spawn validation queues to the next session per CLAUDE.md Rule 5.
**Target Platform**: macOS + Linux developer machines + GitHub Actions (matches foundation + axis-enrichment).
**Project Type**: developer-tooling extension to an existing plugin (no service layer, no UI, no DB, no net-new runtime dependency).
**Performance Goals**: NFR-006a structural invariant (no-probe-no-spawn skip path); NFR-006b measurement invariant (`t_skip - t_baseline ≤ 50 ms` over 5 runs median).
**Constraints**:
- Zero modifications to foundation-untouchable files (NFR-AE-009 from axis-enrichment carries forward — see "Foundation invariants preserved" below).
- Backward compat: PRDs without `fixture_corpus: synthesized` AND without `output_quality` axis MUST behave byte-identically to pre-PRD `/plan` (NFR-001 + NFR-006a).
- Loud-failure on every config malformation (NFR-007); never silent fallback.
- Tool allowlists frozen at the committed values (NFR-005); CI lint blocks drift.
- The composer + resolver are consumed via the canonical recipe in CLAUDE.md; no in-repo bypass is permitted (Architectural Rule 1 — never `general-purpose`).
**Scale/Scope**:
- `plugin-kiln/agents/fixture-synthesizer.md`: ~12 LoC stub → ~80 LoC with role-specific prose (mostly the diversity-prompt invariant + I/O contract + relay protocol).
- `plugin-kiln/agents/output-quality-judge.md`: ~12 LoC stub → ~80 LoC with role-specific prose (verbatim-rubric invariant + envelope shape + relay protocol).
- `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh`: extended ~80 → ~100 LoC (one new validator stanza for `rubric:` requirement).
- New helper `plugin-wheel/scripts/harness/evaluate-output-quality.sh`: ~140 LoC (config-resolve + RNG-seed + control-insertion + spawn-batch + de-anon + drift-halt + stdout-emit).
- `plugin-kiln/skills/plan/SKILL.md`: ~165 LoC current → ~210 LoC with the new Phase 1.5 stanza (probe + spawn-or-skip + per-fixture review prompt for synthesizer + identical-input-control insertion delegation for judge).
- New lint scripts: `lint-judge-prompt.sh` (~30 LoC), `lint-synthesizer-prompt.sh` (~20 LoC), `lint-agent-allowlists.sh` (~30 LoC).
- New config example: `plugin-kiln/lib/judge-config.yaml.example` (~10 LoC).
- New test fixtures: 9 (per SC-003..SC-010 + skip-perf), each ~30–60 LoC of shell + fixtures.
- Total net-new + extended: ~750 LoC across artifacts (under the 800-LoC budget noted in axis-enrichment plan).

## Resolution of Spec Open Questions (carried into plan)

The spec left three first-real-use OQs (OQ-1 deferred from PRD, OQ-3 + OQ-4 new). These are **not blocking** — they're surfaced in the spec's Risks section and will be resolved post-merge against first-real-use evidence.

## Foundation invariants preserved

Per the axis-enrichment plan + the foundation plan, the following files are untouchable in this PR:
- `plugin-wheel/scripts/harness/research-runner.sh` (axis-enrichment — extended in PR #178; no further extension in this PRD).
- `plugin-wheel/scripts/harness/parse-token-usage.sh`.
- `plugin-wheel/scripts/harness/render-research-report.sh` (no new columns from this PRD; the per-axis verdict column from axis-enrichment already accommodates `output_quality`).
- `plugin-wheel/scripts/harness/evaluate-direction.sh`.
- `plugin-wheel/scripts/harness/compute-cost-usd.sh`.
- `plugin-wheel/scripts/harness/resolve-monotonic-clock.sh`.
- `plugin-kiln/lib/research-rigor.json`.
- `plugin-kiln/lib/pricing.json`.
- All foundation `wheel-test-runner.sh` + 12 sibling helpers.

The single shared file we DO modify additively is `parse-prd-frontmatter.sh` — and only one validator stanza is added (FR-010). Its existing stdout JSON projection shape is unchanged; its existing exit codes are unchanged; the new validator surfaces a new exit-2 path with the exact `Bail out! output_quality-axis-missing-rubric: <prd-path>` message (per NFR-007 loud-failure).

## Phase 0: Outline & Research

**Status**: COMPLETE — see `research.md`. NFR-006 reconciliation directive accepted; OQ-1 + OQ-2 resolved in spec; composer-integration sanity verified; pinned-judge-model availability confirmed; orchestrator-side anti-drift ownership clarified.

## Phase 1: Design & Contracts

### Decision 1 — Spawn from `/plan` SKILL.md, not from a separate hook

**Decision**: The spawn wiring lives in `plugin-kiln/skills/plan/SKILL.md` (a new "Phase 1.5: research-first plan-time agents" stanza between current Phase 1 and the existing "Stop and report"). NOT a separate hook script.

**Rationale**: `/plan` is the natural home for plan-time agent orchestration (it's where Phase 0 / Phase 1 already live). A separate hook script would split the spawn logic across two surfaces and force the implementer to coordinate state across them. SKILL.md's prose-as-instruction model is already the invocation surface for the existing Phase 0 / Phase 1 work; the new stanza follows the same pattern.

**Alternatives considered**:
- A new wheel workflow that runs alongside `/plan` and spawns the agents — rejected: this PRD is one-PR, the wheel workflow surface adds complexity without value, and the spawn-or-skip decision needs the SAME parsed frontmatter `/plan` already loads.
- A new top-level `/research-synth` skill — rejected: bifurcates the user's mental model. `/plan` already produces research artifacts (research.md); adding the synthesis at the same step keeps the surface coherent.

### Decision 2 — Single edit point in `/plan` SKILL.md

**Decision**: Both agents are spawned from the SAME stanza in `/plan` SKILL.md. The stanza branches on `has_synthesized_corpus` and `has_output_quality_axis` (booleans derived from one frontmatter probe).

**Rationale**: Single-implementer rationale per `agent-notes/specifier.md` — splitting the SKILL.md edit risks file conflicts. The two themes are orthogonal in failure modes but co-located in the spawn-decision logic.

### Decision 3 — Composer-integration recipe is the canonical spawn pattern

**Decision**: Both agents are spawned via the recipe in CLAUDE.md "Composer integration recipe" — not via a bare `Agent({...})` call.

**Rationale**: CLAUDE.md Rule 1 (plugin-prefixed `subagent_type`), Rule 3 (prompt-layer injection), and the explicit recipe stanza require this. The existing implementer pattern in `/kiln:kiln-fix` (per A-005) demonstrates the resolver-spawn alternative; this PRD follows the same pattern.

**Concrete spawn shape** (illustrative — implementer reproduces in SKILL.md):

```bash
# 1. Resolve agent identity.
SPEC_JSON=$(bash "$WORKFLOW_PLUGIN_DIR/scripts/agents/resolve.sh" kiln:fixture-synthesizer)
SUBAGENT_TYPE=$(jq -r .subagent_type <<<"$SPEC_JSON")

# 2. Compose runtime context block per CLAUDE.md recipe.
PREFIX=$(bash "$WORKFLOW_PLUGIN_DIR/scripts/agents/compose-context.sh" \
  --agent-name fixture-synthesizer \
  --plugin-id kiln \
  --task-spec /tmp/fixture-synth-spec.json \
  --prd-path "$PRD_PATH" | jq -r .prompt_prefix)

# 3. Spawn — calling skill prepends PREFIX.
# Agent({
#   subagent_type: SUBAGENT_TYPE,    # "kiln:fixture-synthesizer"
#   prompt: PREFIX + "\n---\n" + per_call_task,
#   team_name: "<existing-team>",
#   name: "synth-fixture-001"        # role-instance label per Rule 2 — distinguishes parallel spawns
# })
```

For the judge, the recipe is the same with `kiln:output-quality-judge` and a per-call task built by `evaluate-output-quality.sh`.

### Decision 4 — `judge-config.yaml` lives at TWO paths (override + example)

**Decision**: Per FR-014, the orchestrator reads `<repo-root>/.kiln/research/judge-config.yaml` first (per-developer override; gitignored), falling back to `<repo-root>/plugin-kiln/lib/judge-config.yaml.example` (committed default).

**Rationale**: The PRD initially specified only `.kiln/research/judge-config.yaml`. That path is gitignored per foundation precedent, which means the pinned-model config is per-developer and there's no committed source of truth — every developer's first run would crash (no config). The two-path resolution (override + example fallback) makes the default work everywhere AND lets developers pin a different model locally.

**Alternative considered**: commit the canonical config at `.kiln/research/judge-config.yaml` and remove `.kiln/research/` from gitignore for that one file. Rejected: `.kiln/research/` is gitignored for a good reason (per-developer scratch), and special-casing one file inside a gitignored directory is a maintenance hazard.

### Decision 5 — Per-skill `fixture-schema.md` convention is documented but no example committed

**Decision**: This PRD documents the convention (`plugin-<name>/skills/<skill>/fixture-schema.md`) and asserts loud-failure if missing (FR-003). It does NOT commit an example schema for any specific skill — the first synthesized-corpus PRD (per SC-001) is responsible for committing the schema for its target skill.

**Rationale**: We don't yet know what schema shape works best — committing a speculative example would lock in a shape before first-real-use evidence. Loud-failure on missing schema means the first-real-use PRD is forced to commit one, which seeds the convention.

**Alternatives considered**:
- Commit an example schema at `plugin-kiln/skills/_template/fixture-schema.md` — rejected: speculative, may bake in wrong shape.
- Make the schema optional (synthesizer infers shape) — rejected per OQ-2 (silent-correctness failure mode).

### Decision 6 — Identical-input control fixture is inserted by the orchestrator, not the synthesizer

**Decision**: The identical-input control (FR-016) is constructed by `evaluate-output-quality.sh` post-synthesis. It is NOT a synthesizer-emitted fixture (the control is a copy of an existing fixture's BASELINE output, not a net-new fixture).

**Rationale**: The control's purpose is to detect judge drift on outputs the judge has actually seen. A synthesizer-emitted control would be a net-new input the judge has never seen; that doesn't test drift, it tests baseline judge behavior on a new input. By copying the baseline output of an existing fixture, the control IS a known-equal pair (output_a = output_b = baseline), which is the exact drift test FR-016 specifies.

### Decision 7 — Verdict envelope JSON shape includes BOTH blinded and de-anonymized verdicts

**Decision**: Per FR-012, the verdict envelope written at `.kiln/research/<prd-slug>/judge-verdicts/fixture-<id>.json` includes both `blinded_verdict` (the judge's raw `A_better | equal | B_better` output) AND `deanonymized_verdict` (the orchestrator's `candidate_better | equal | baseline_better` translation). The mapping is also recorded in `position-mapping.json`.

**Rationale**: Storing both makes the audit trail self-contained. A reviewer can verify the de-anonymization is correct without cross-referencing two files. Storing only the blinded verdict requires the position mapping for any human read; storing only the de-anonymized verdict loses the original judge output for debugging judge drift.

### Decision 8 — Agent role-specific operating prose uses the `<!-- @include _shared/coordination-protocol.md -->` directive (per build/agent-prompt-composition-20260425)

**Decision**: Both extended agent.md files use the `_shared/coordination-protocol.md` include directive (per CLAUDE.md "Theme B directive syntax (compile-time agent-prompt includes — FR-B-8)") for the SendMessage relay coordination prose. The include is resolved at compile time by `plugin-kiln/scripts/agent-includes/build-all.sh` and CI gate `check-compiled.sh` asserts compiled == build(sources).

**Rationale**: The shared boilerplate (SendMessage relay protocol per Rule 6) is identical across both agents. Inlining it duplicates ~30 lines per agent. The directive is the canonical de-dup pattern shipped in PR #179.

**Operational note**: Implementer authors source files at `plugin-kiln/agents/_src/fixture-synthesizer.md` + `plugin-kiln/agents/_src/output-quality-judge.md` (since the role uses includes), then runs `bash plugin-kiln/scripts/agent-includes/build-all.sh` to compile to `plugin-kiln/agents/<role>.md`. Both compiled outputs are committed.

## Phase 1 outputs

- `contracts/interfaces.md` — see [`./contracts/interfaces.md`](./contracts/interfaces.md). SINGLE SOURCE OF TRUTH for every signature in net-new helpers + the additive validator extension + the verdict envelope shape.
- `quickstart.md` — DEFERRED to first-real-use synthesized-corpus PRD (per SC-001 dependency). The quickstart is bundled with the first PRD that exercises the synthesizer end-to-end.
- `data-model.md` — DEFERRED. The "data model" here is two JSON shapes (verdict envelope, position mapping) + one YAML shape (judge-config) — all defined in contracts/interfaces.md.

## Constitution Check

*GATE: Must pass before Phase 1 design. Re-check after Phase 1.*

- **Article I (Spec-First)**: PASS — spec.md committed before any implementation; FR comments will be added in implementation per Article I.
- **Article II (80% coverage)**: PASS — every net-new helper has a corresponding test fixture under `plugin-kiln/tests/`. Mock-spawn pattern keeps tests fast + deterministic.
- **Article III (PRD as source of truth)**: PASS — spec divergences from PRD are documented in spec §"Reconciliation" + §"Resolution of PRD Open Questions" with rationale. Single divergence is NFR-006 reframe (specifier-level reconciliation per team-lead Step 1.5).
- **Article IV (Hooks enforce rules)**: PASS — hooks unmodified; spec + plan + tasks + first `[X]` task gates apply to implementer.
- **Article V (E2E testing)**: PASS — every test fixture is a `run.sh` invoking the actual helper (not a unit-test mock of the helper internals). Live agent-spawn is mocked (per CLAUDE.md Rule 5 — newly-shipped agents not live-spawnable in same session); implementer documents in tasks.md.
- **Article VI (Small focused changes)**: PASS — total artifacts ≤ 800 LoC; no file exceeds 500 LoC; net-new helpers each ≤ 150 LoC.
- **Article VII (Interface Contracts Before Implementation)**: PASS — `contracts/interfaces.md` ships in this PR with every net-new + extended signature.
- **Article VIII (Incremental Task Completion)**: PASS — tasks.md uses 4 phases (A: lint + config, B: agents + frontmatter validator, C: orchestrator helper + SKILL wiring, D: tests). Implementer marks `[X]` per-task and commits per-phase.

**Verdict**: ALL articles pass; no documented exceptions required.

## Phase 2: Tasks (deferred to /tasks)

Tasks live in [`./tasks.md`](./tasks.md) — generated next.

## Wheel-workflow guidance (FR-B3)

This PRD does NOT emit a new wheel workflow JSON. The spawn happens inline in `/plan` SKILL.md per Decision 1. No `model:` tier selection applies at the workflow level.

For agent-step model selection: synthesizer + judge each have a `model_default` exposed by the composer (per `compose-context.sh` contract). This PRD does NOT override the default — the default flows through. Per CLAUDE.md model-selection rule of thumb: synthesizer is "synthesis / drafting" → `sonnet`; judge is "classification / scoring → narrative justification" → could be `sonnet` (default) or `opus` (when the rubric is hard-reasoning-heavy). Per FR-014, the judge is invoked with the PINNED model from `judge-config.yaml`, which OVERRIDES the composer's `model_default`. Implementer surfaces this override in `evaluate-output-quality.sh`.

## Key rules

- Use absolute paths.
- ERROR on gate failures, unresolved clarifications, missing fixture-schema, missing rubric, missing pinned-model.
- NEVER silently fall back to a hardcoded default rigor / pricing / model / rubric / schema.
- NEVER summarize the rubric en route to the judge — `{{rubric_verbatim}}` interpolation token is enforced by lint.
- NEVER pass `{baseline, candidate}` to the judge — always blinded `{output_a, output_b}` (FR-015).
- ALWAYS insert exactly one identical-input control per output_quality run (FR-016).
- ALWAYS record both blinded + de-anonymized verdicts in envelope (Decision 7).
