# Feature Specification: Research-First Plan-Time Agents — fixture-synthesizer + output-quality-judge

**Feature Branch**: `build/research-first-plan-time-agents-20260425`
**Created**: 2026-04-25
**Status**: Draft
**Input**: `docs/features/2026-04-25-research-first-plan-time-agents/PRD.md`
**Parent goals**:
  - `.kiln/roadmap/items/2026-04-24-research-first-fixture-synthesizer.md` (phase `09-research-first`, step 4 of 7)
  - `.kiln/roadmap/items/2026-04-24-research-first-output-quality-judge.md` (phase `09-research-first`, step 5 of 7)
**Builds on**:
  - `specs/research-first-foundation/{spec.md,plan.md,contracts/interfaces.md}` (PR #176, runner at `plugin-wheel/scripts/harness/research-runner.sh`).
  - `specs/research-first-axis-enrichment/{spec.md,plan.md,contracts/interfaces.md}` (PR #178, per-axis gate + frontmatter parser at `parse-prd-frontmatter.sh`).
  - `plugin-kiln/agents/fixture-synthesizer.md` + `plugin-kiln/agents/output-quality-judge.md` (stubs from `build/agent-prompt-composition-20260425`).
**Baseline research**: `specs/research-first-plan-time-agents/research.md` (read first; thresholds in §Success Criteria are reconciled against it per §1.5 Baseline Checkpoint).

## Overview

The shipped research-first runner can measure mechanical axes (accuracy / tokens / time / cost) against a declared fixture corpus. Two pieces remain before a maintainer can use it on a real qualitative-improvement PRD:

1. **fixture-synthesizer** — a `/plan`-time agent that generates an N-fixture corpus when the PRD declares `fixture_corpus: synthesized`. Mandatory human review before fixtures land in the committed path. Default `promote_synthesized: false` (one-off per-PRD); opt-in to `true` for shared-corpus growth.
2. **output-quality-judge** — a per-axis evaluator that scores baseline vs candidate output pairs against a verbatim PRD-author rubric. Three anti-drift controls: pinned model (FR-014), blind-to-version ordering (FR-015), identical-input sanity check (FR-016).

Both agents are **opt-in per PRD** via the existing research block — they cost zero tokens (and structurally zero subprocess spawns) for PRDs that declare neither feature. Both are spawned via the runtime context-injection composer per CLAUDE.md "Composer integration recipe" — the agent.md stubs already exist at `plugin-kiln/agents/<role>.md` and ALREADY conform to Architectural Rules 1, 2, 3, 4, 6 (plugin-prefixed names, single role per registered subagent_type, prompt-layer injection, no nested spawns, SendMessage relay). This PRD adds the role-specific operating prose, the spawn-from-`/plan` wiring, the per-skill `fixture-schema.md` convention, the `judge-config.yaml` model-pin contract, the orchestrator-side anti-drift plumbing, and the per-fixture confirm-never-silent human-review prompt.

The two themes are independent (orthogonal failure modes — synthesizer fails by triviality, judge fails by drift) but bundled in one PRD per the PRD body's rationale: both attach at the same `/plan` step, both write to `.kiln/research/<prd-slug>/`, both share the same human-review affordance pattern, both are spawned via the same composer.

## Resolution of PRD Open Questions

The PRD `## Risks & Open Questions` left two items. Resolved as follows; rationale anchors specific FRs/NFRs.

- **OQ-1 (judge abstention — `unsure` verdict)**: RESOLVED — **NO** in v1. The judge MUST emit one of `candidate_better | equal | baseline_better`. Forcing a verdict matches the gate semantics (`direction: equal_or_better` requires a binary "is the candidate at least as good"); allowing abstention introduces a fourth case the orchestrator must handle without a clear gate-mapping. Encoded in **FR-012**. If the first real-use PRD encounters a genuinely-tied case, file a follow-on item — abstention is a v2 concern, not a v1 blocker.
- **OQ-2 (fixture-schema.md required vs inferred)**: RESOLVED — **REQUIRED** in v1. The synthesizer MUST be invoked with an explicit `plugin-<name>/skills/<skill>/fixture-schema.md` per PRD's FR-003. Inferred-schema is more ergonomic but introduces a silent-correctness failure mode (the synthesizer guesses the input shape from existing fixtures and produces a corpus that subtly diverges from the skill's actual contract). Loud-failure on missing schema; bare prerequisite check before spawn. Encoded in **FR-003** + **A-002**.

## Reconciliation Against Researcher-Baseline (§1.5 Baseline Checkpoint) — RECONCILED 2026-04-25

The specifier captured `specs/research-first-plan-time-agents/research.md §baseline` (this same PR) with one reconciliation directive. Accepted.

### Directive 1 — NFR-006 / SC-006 threshold reframe

**Live measurement** (research.md §baseline, captured 2026-04-25 on macOS):

| probe | what it measures | median (ms) |
|-------|------------------|-------------|
| in-process scan (already-running python3) | regex on a 7-line YAML file already in memory | **0.12 ms** |
| shell `grep -E` single-pass | one-shot grep against the file | **~5 ms** |
| python3 cold-start fork (no work) | `python3 -c 'pass'` | **~10 ms** (irreducible macOS floor; PR #168 NFR-H-5 pattern) |
| jq cold-start fork (no work) | `jq -n '0'` | **~5 ms** (irreducible macOS floor) |

**Reconciliation accepted**: PRD NFR-006's "< 50 ms" threshold is rewritten as **`≤ baseline + 50 ms`** with the structural invariant "no probe, no spawn" preserved as **NFR-006a** (no net-new agent spawn, no net-new subprocess EXCEPT the strictly-required spawn-or-skip decision probe). The measurement invariant is **NFR-006b** (`t_skip - t_baseline ≤ 50 ms` over 5 runs median, measured by `plugin-kiln/tests/plan-time-agents-skip-perf/`). SC-006 is rewritten to match. **Implementer constraint**: the skip-path detector SHOULD be a single `grep -E` (~5 ms) OR — preferred — a key lookup on the JSON already produced by `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh` from the axis-enrichment PR (sub-millisecond). Implementer MUST NOT add a fresh python3 / jq cold-start fork solely for the skip-path probe.

### Directive 2 — `output_quality` schema extension is additive over axis-enrichment

`specs/research-first-axis-enrichment/contracts/interfaces.md §3` already validates `metric ∈ {accuracy, tokens, time, cost, output_quality}` — `output_quality` is in the enum, deferred. This PRD ADDS the `rubric:` required-when-`metric: output_quality` validation rule. NO existing axis-enrichment helper is forked or rewritten; the validator is extended in place via additive code. Encoded in **FR-010** + **NFR-005**.

## Clarifications

### Session 2026-04-25
- Q: Should the judge be allowed to abstain (`unsure`)? → A: NO in v1 — three-way verdict only. Encoded in FR-012.
- Q: Should `fixture-schema.md` be required or inferable? → A: REQUIRED in v1. Loud-failure on missing schema. Encoded in FR-003 + A-002.
- Q: Where does `judge-config.yaml` live (gitignored `.kiln/research/` vs committed `plugin-kiln/lib/`)? → A: BOTH — the orchestrator reads `.kiln/research/judge-config.yaml` first (per-developer override), falls back to a committed `plugin-kiln/lib/judge-config.yaml.example` (default pinned model + fallback list). Encoded in FR-014.
- Q: Should the synthesizer's diversity prompt be in the agent.md (system prompt) or in the per-call prompt (composer-injected)? → A: agent.md (system prompt). The diversity prompt is a stable, role-defining instruction; per-call context is the skill identifier + axes + count. Encoded in FR-008.
- Q: How does the orchestrator pick the position-A vs position-B assignment for FR-015 blinding? → A: deterministic seeded RNG keyed off `<prd-slug>:<fixture-id>` so the assignment is reproducible across re-runs of the same research run. Encoded in FR-015 + NFR-008.
- Q: The PRD declares max-regenerations per fixture default 3 (FR-006). What is the bound on the total reject-then-regenerate budget? → A: bounded per-fixture only; total budget = `corpus_size × max_regenerations`. Surfaced in the per-PRD research-report header so token spend is auditable. Encoded in FR-006 + NFR-009.

## User Scenarios & Testing

### User Story 1 — Synthesized corpus from no existing corpus (Priority: P1)

**As a maintainer with no existing fixture corpus**, I declare `fixture_corpus: synthesized` in my source artifact's research block. `/plan` synthesizes 10 diverse fixtures and shows me 3-line summaries. I accept 7, reject 2 (re-synthesize replacements), and edit 1. The corpus lands at `.kiln/research/<my-prd-slug>/corpus/` (one-off, default `promote_synthesized: false`) and the rest of the research-first pipeline runs as if I'd hand-curated it.

**Acceptance Scenarios**:
1. **Given** a PRD declaring `fixture_corpus: synthesized` + `blast_radius: feature` (min_fixtures=10) + `empirical_quality: [{metric: tokens, direction: lower}]`, **When** `/plan` runs, **Then** `kiln:fixture-synthesizer` is spawned exactly once with the role-instance variables `{skill, axes, target_count: 10, schema_path}`, writes 10 files at `.kiln/research/<prd-slug>/corpus/proposed/fixture-001.md` … `fixture-010.md` (deterministic naming), and `/plan` surfaces a per-fixture confirm-never-silent prompt. (FR-001..FR-005, FR-008)
2. **Given** the human rejects fixture-003 with reason "all my fixtures are too short — give me one with maximum-size input", **When** `/plan` re-spawns the synthesizer for replacement, **Then** the replacement is written at `.kiln/research/<prd-slug>/corpus/proposed/fixture-003.md` (overwrites the rejected version), the synthesizer's per-call prompt includes the rejection reason and the axis-summary of the rejected fixture, and the regeneration counter for fixture-003 increments by 1. (FR-006)
3. **Given** the human types `accept-all`, **When** `/plan` finalizes, **Then** all proposed fixtures move from `proposed/` to `.kiln/research/<prd-slug>/corpus/` (one-off, since `promote_synthesized: false` is the default). (FR-007)
4. **Given** the same PRD additionally declares `promote_synthesized: true`, **When** the human accepts all fixtures, **Then** they move to `plugin-<skill-plugin>/fixtures/<skill>/corpus/` (the committed path) instead of the per-PRD scratch path. The research report records WHICH path each fixture landed at. (FR-007)

### User Story 2 — Qualitative improvement with output-quality judge (Priority: P1)

**As a maintainer making a qualitative improvement** (clearer error messages, say), I declare `empirical_quality: [{metric: output_quality, direction: equal_or_better, rubric: "Error messages should name the specific failure mode and suggest one concrete next action"}]` in my source artifact's research block. The judge evaluates baseline vs candidate per fixture against my verbatim rubric. I see one verdict per fixture in the research report attached to the PR.

**Acceptance Scenarios**:
1. **Given** a PRD with `output_quality` axis declared + a 5-fixture corpus + a candidate that produces strictly clearer error messages on every fixture, **When** the research run executes, **Then** the judge is invoked once per fixture (5 spawns) with `kiln:output-quality-judge` role + role-instance vars `{output_a, output_b, rubric_verbatim}` (NOT `baseline / candidate` — see FR-015), each verdict envelope is written at `.kiln/research/<prd-slug>/judge-verdicts/fixture-<id>.json`, and the per-axis verdict is `pass`. (FR-009..FR-013)
2. **Given** the same setup but with a candidate that on fixture-003 produces a strictly worse error message, **When** the research run executes, **Then** the de-anonymized verdict for fixture-003 is `baseline_better`, the per-axis gate for `output_quality` returns `regression`, and the overall research run fails with `Overall: FAIL` + `regression (output_quality)` per the existing axis-enrichment gate semantics. (FR-013)
3. **Given** a PRD with `output_quality` declared but `rubric:` field omitted or empty, **When** the frontmatter validator runs (`parse-prd-frontmatter.sh` extension), **Then** it exits non-zero with `Bail out! output_quality-axis-missing-rubric: <prd-path>` and the research run never starts. (FR-010)

### User Story 3 — Anti-drift audit (Priority: P1)

**As a maintainer auditing judge reliability**, I check the research report and confirm: (a) the run used the pinned model `claude-opus-4-7`; (b) the A/B position mapping is recorded; (c) the identical-input control returned `equal`. If any of those three are missing or wrong, the research run halted before merge.

**Acceptance Scenarios**:
1. **Given** an `output_quality` research run, **When** the judge is spawned, **Then** every spawn passes `model: <pinned-model>` from `judge-config.yaml` (default `claude-opus-4-7`), the model used is recorded in each verdict envelope, and the report header lists `Pinned judge model: claude-opus-4-7`. (FR-014)
2. **Given** the pinned model is unavailable at runtime (API returns `model_not_found`), **When** the orchestrator probes the model, **Then** if `pinned_model_fallbacks: [...]` is configured, it walks the fallback list and uses the first available + records WHICH model was used; if no fallback is available, it halts with `Bail out! pinned-model-unavailable: <model-id>`. (FR-014)
3. **Given** an `output_quality` run with N fixtures, **When** the orchestrator builds the judge spawn batch, **Then** for each fixture it deterministically (seeded by `<prd-slug>:<fixture-id>`) assigns baseline output to position A or B, passes `{output_a, output_b, rubric_verbatim}` to the judge (NEVER `{baseline, candidate}`), and records the position-mapping in `.kiln/research/<prd-slug>/position-mapping.json`. The judge's verdict (`A_better | equal | B_better`) is de-anonymized into `candidate_better | equal | baseline_better` by the orchestrator. (FR-015, NFR-008)
4. **Given** an `output_quality` run, **When** the orchestrator builds the spawn batch, **Then** it inserts at least one identical-input control fixture (`output_a = output_b = baseline_output`) at a deterministic position, runs it through the judge as a normal spawn, and asserts the verdict is `equal`. If the verdict is `A_better` or `B_better`, the orchestrator halts with `Bail out! judge-drift-detected: <verdict>` and writes `.kiln/research/<prd-slug>/judge-drift-report.md` capturing the control inputs + verdict + judge prompt. (FR-016)

### Edge Cases

- **fixture-schema.md missing** — synthesizer is spawned but the schema file at `plugin-<skill-plugin>/skills/<skill>/fixture-schema.md` doesn't exist. The synthesizer-spawn code in `/plan` MUST pre-check the file's existence and bail BEFORE spawn with `Bail out! fixture-schema-missing: <expected-path>`. (FR-003)
- **regeneration loop exhaustion** — a fixture is rejected `max_regenerations` times in a row. `/plan` halts the synthesis phase with a clear error: `Bail out! regeneration-exhausted: fixture-<id> rejected <N> times`. The maintainer can either accept the last attempt or abandon the synthesis run. (FR-006)
- **promote_synthesized: true + committed-path collision** — the target path `plugin-<skill-plugin>/fixtures/<skill>/corpus/fixture-NNN.md` already exists. The orchestrator MUST refuse to overwrite (no silent clobber); maintainer resolves by editing the conflicting fixture or by not promoting. Loud-failure with `Bail out! promotion-collision: <existing-path>`. (FR-007)
- **judge-config.yaml absent** — neither `.kiln/research/judge-config.yaml` nor `plugin-kiln/lib/judge-config.yaml.example` exists. Bail out with `Bail out! judge-config-missing` instructing maintainer to copy the example. (FR-014)
- **lint-judge-prompt.sh fails** — the judge-spawn prompt template at `plugin-kiln/agents/output-quality-judge.md` (or its compose-context-injected per-call prompt) does not contain the literal `{{rubric}}` interpolation token, OR contains rubric-summarization language. CI lint asserts NEVER-summarize. Loud-failure in CI. (SC-003 + FR-011)
- **/plan skip-path baseline regression** — `t_skip - t_baseline > 50 ms` in the perf harness. The harness fails the run and reports the regression delta + which probe took the longest. (NFR-006b + SC-006)

## Requirements

### Functional Requirements

#### Theme: fixture-synthesizer (FR-001 — FR-008)

**FR-001 (from PRD FR-001 / `.kiln/roadmap/items/2026-04-24-research-first-fixture-synthesizer.md`)**: Extend the existing stub agent at `plugin-kiln/agents/fixture-synthesizer.md` (registered as `kiln:fixture-synthesizer` per CLAUDE.md Rule 1) with role-specific operating prose: input format, output format, deterministic-naming invariant, diversity-prompt invariant, no-Agent / no-Edit / no-Bash-except-jq tool-allowlist conformance check stanza. Tools allowlist remains as currently committed: `Read, Write, SendMessage, TaskUpdate` — Bash is **not** added (the synthesizer writes files directly; jq derivations happen in the calling skill, not in the agent).

**FR-002 (from PRD FR-002)**: `/plan` SKILL.md MUST spawn `kiln:fixture-synthesizer` exactly when the PRD frontmatter declares `fixture_corpus: synthesized` OR (`fixture_corpus: promoted` AND the existing promoted pool has fewer fixtures than `min_fixtures` from the resolved rigor row of `plugin-kiln/lib/research-rigor.json`). Skip-path (neither condition) MUST take ZERO subprocess spawns beyond the spawn-or-skip decision probe (NFR-006a).

**FR-003 (from PRD FR-003)**: Synthesizer agent role-instance variables (composer-injected per CLAUDE.md "Composer integration recipe") MUST include: (a) the skill identifier being A/B'd (string `<plugin>:<skill>`); (b) the PRD's `empirical_quality[]` declarations (JSON array, verbatim from frontmatter); (c) the absolute path to `plugin-<skill-plugin>/skills/<skill>/fixture-schema.md` — REQUIRED, loud-failure if missing; (d) `target_count` (int, derived from `min_fixtures` of the resolved rigor row); (e) the absolute proposed-corpus output directory (`<repo-root>/.kiln/research/<prd-slug>/corpus/proposed/`).

**FR-004 (from PRD FR-004)**: Synthesizer output MUST be deterministically-named files at `.kiln/research/<prd-slug>/corpus/proposed/fixture-NNN.md` (zero-padded 3-digit index, `001` … `NNN`). Each fixture file MUST start with a 3-line summary header in YAML frontmatter — keys: `axis_focus` (which `empirical_quality` axis the fixture is biased to exercise), `shape` (one of `empty | minimal | typical | maximum-size | adversarial`), `summary` (one-sentence description). The body below the frontmatter is the actual fixture content matching the per-skill schema.

**FR-005 (from PRD FR-005)**: After synthesis, `/plan` MUST surface a per-fixture confirm-never-silent prompt: each proposed fixture rendered with its 3-line summary header; user replies one of `accept | reject [reason] | edit | accept-all | abandon`. No fixture moves to the committed path without an explicit accept (per-fixture or via `accept-all`). `abandon` aborts the synthesis phase; the proposed-corpus directory is preserved for inspection but no fixture lands.

**FR-006 (from PRD FR-006)**: `/plan` MUST support reject-then-regenerate: when the user rejects a fixture, the synthesizer is re-spawned with role-instance variables additionally including `rejection_reason` (string) + `rejected_fixture_summary` (the 3-line summary of the rejected fixture) + `existing_fixtures_summary` (a list of the 3-line summaries of all currently-accepted fixtures, so the regenerator can avoid duplicating them). Bounded by `max_regenerations` per fixture (default 3, configurable per-PRD via frontmatter `max_regenerations: <int>`). Exhaustion bails per the Edge Cases.

**FR-007 (from PRD FR-007)**: Accepted fixtures move to `plugin-<skill-plugin>/fixtures/<skill>/corpus/` when the PRD declares `promote_synthesized: true`, OR remain at `.kiln/research/<prd-slug>/corpus/` when `promote_synthesized: false` (default). `/plan` MUST log per-fixture which path was used in the research report at `.kiln/research/<prd-slug>/synthesis-report.md`. Promotion-target collisions MUST be detected pre-write and bail loud per the Edge Cases.

**FR-008 (from PRD FR-008)**: The diversity prompt MUST live in the agent.md system prompt (NOT the per-call composer-injected context). Verbatim string: "generate fixtures that exercise edge cases: empty inputs, maximum-size inputs, typical inputs, adversarial inputs". This is asserted by a CI lint check at `plugin-kiln/scripts/research/lint-synthesizer-prompt.sh` that greps the agent.md for the verbatim string.

#### Theme: output-quality judge (FR-009 — FR-016)

**FR-009 (from PRD FR-009)**: Extend the existing stub agent at `plugin-kiln/agents/output-quality-judge.md` (registered as `kiln:output-quality-judge` per CLAUDE.md Rule 1) with role-specific operating prose: verbatim-rubric invariant, three-way verdict envelope (`candidate_better | equal | baseline_better` per FR-012, OR — when invoked under blinding from FR-015 — `A_better | equal | B_better`), one-sentence rationale required, no retry / no abstain. Tools allowlist remains as currently committed: `Read, SendMessage, TaskUpdate` — judge is read-only by construction.

**FR-010 (from PRD FR-010)**: Extend the frontmatter validator from `specs/research-first-axis-enrichment/contracts/interfaces.md §3` (`parse-prd-frontmatter.sh`) to require `rubric: <non-empty-string>` on every `empirical_quality[]` entry where `metric: output_quality`. Validator MUST loud-fail with `Bail out! output_quality-axis-missing-rubric: <prd-path>` when missing or empty. Loud-failure on summarization-attempt is enforced by the per-call composer-injected prompt verbatim-interpolation token + the lint check (FR-011 / SC-003).

**FR-011 (from PRD FR-011)**: Judge per-call composer-injected variables MUST include: (a) `output_a` (string, full content of one paired output — assignment-blind per FR-015); (b) `output_b` (string, full content of the other paired output); (c) `rubric_verbatim` (the literal string from `empirical_quality[].rubric` — NOT summarized, NOT paraphrased, NOT truncated); (d) `axis_id` (always `output_quality`, scoping for downstream parsing). The composer prompt template MUST contain the literal `{{rubric_verbatim}}` interpolation token; CI lint at `plugin-kiln/scripts/research/lint-judge-prompt.sh` asserts the token is present and that no rubric-summarization language exists in the surrounding template prose.

**FR-012 (from PRD FR-012)**: Judge output MUST be a structured JSON envelope written via SendMessage relay (per CLAUDE.md Rule 6) AND parsed by the orchestrator into a per-fixture verdict file at `.kiln/research/<prd-slug>/judge-verdicts/fixture-<id>.json`. Envelope shape (canonical, sorted keys, `jq -c -S`):
```json
{
  "axis_id": "output_quality",
  "blinded_verdict": "A_better | equal | B_better",
  "blinded_position_mapping": {"A": "baseline | candidate", "B": "baseline | candidate"},
  "deanonymized_verdict": "candidate_better | equal | baseline_better",
  "fixture_id": "001-noop-passthrough",
  "model_used": "claude-opus-4-7",
  "rationale": "<one-sentence string, ≤200 chars>",
  "rubric_verbatim_hash": "<sha256 of the rubric string the judge actually saw>"
}
```
Three-way verdict only — abstention (`unsure`) is not permitted (OQ-1). The `rubric_verbatim_hash` is computed orchestrator-side post-spawn and asserted to match the hash of the rubric string in the PRD frontmatter — a hash mismatch indicates the judge's prompt template summarized or modified the rubric en route, which is a CI-blocking violation per FR-011.

**FR-013 (from PRD FR-013)**: Per-axis gate evaluation for `output_quality` MUST fail the research run if ANY fixture's `deanonymized_verdict` is `baseline_better` (direction: `equal_or_better`). Wires into the existing per-axis gate from `specs/research-first-axis-enrichment/contracts/interfaces.md §4` via a new sibling helper `plugin-wheel/scripts/harness/evaluate-output-quality.sh` that reads the verdict-envelope files + the position-mapping file + the identical-input control verdict, applies the FR-015 de-anonymization, runs the FR-016 drift assertion, and emits `pass | regression` to stdout matching the existing `evaluate-direction.sh` contract.

**FR-014 (Anti-drift: pinned model — from PRD FR-014)**: Judge agent MUST be invoked with a pinned model ID. Resolution order:
  1. `<repo-root>/.kiln/research/judge-config.yaml` (per-developer override; gitignored).
  2. `<repo-root>/plugin-kiln/lib/judge-config.yaml.example` (committed default).
Schema (both files):
```yaml
pinned_model: claude-opus-4-7         # required
pinned_model_fallbacks:                # optional ordered list
  - claude-sonnet-4-6
```
At spawn time the orchestrator probes the pinned model first; on `model_not_found` it walks the fallback list. The model actually used is recorded in each verdict envelope's `model_used` field. If no model in the resolution chain is available, the orchestrator halts with `Bail out! pinned-model-unavailable: <model-id-attempted-list>`.

**FR-015 (Anti-drift: blind-to-version — from PRD FR-015)**: Per fixture, the orchestrator MUST deterministically (seeded by `sha256("<prd-slug>:<fixture-id>")` mod 2) assign baseline output to position A or B, pass `{output_a, output_b}` to the judge (NEVER `{baseline, candidate}`), and record the mapping `{fixture_id: position_assignment}` at `.kiln/research/<prd-slug>/position-mapping.json`. The judge's verdict (`A_better | equal | B_better`) is de-anonymized into `candidate_better | equal | baseline_better` by the orchestrator using the recorded mapping. The mapping file is JSON, deterministic-keyed, `jq -c -S`-stable.

**FR-016 (Anti-drift: identical-input sanity check — from PRD FR-016)**: For every research run that includes the `output_quality` axis, the orchestrator MUST insert exactly one identical-input control fixture at a deterministic position (seeded by `sha256("<prd-slug>:control")` mod corpus_size). The control's `output_a = output_b = <baseline_output_of_chosen_fixture>`. The control fixture is run through the judge as a normal spawn (judge does NOT know it's a control). Expected verdict: `equal` (post-de-anonymization). If the judge returns `A_better` or `B_better`, the orchestrator halts with `Bail out! judge-drift-detected: blinded_verdict=<v>` and writes `.kiln/research/<prd-slug>/judge-drift-report.md` capturing the control inputs, the verdict envelope, and the verbatim judge prompt that was sent.

### Non-Functional Requirements

**NFR-001 (Opt-in spawn cost)**: PRDs that do NOT declare `fixture_corpus: synthesized` AND do NOT declare an `output_quality` axis MUST take ZERO net-new agent spawns from this PRD. Skip-path is structurally a no-op.

**NFR-002 (Determinism for synthesizer review)**: Proposed fixture filenames are deterministic (`fixture-001.md` … `fixture-NNN.md`); fixture content itself is non-deterministic (LLM output) and is not asserted byte-identical. Test fixture under `plugin-kiln/tests/fixture-synthesizer-stable-naming/` per SC-004 asserts the filename invariant.

**NFR-003 (Determinism for judge verdicts)**: Per-fixture verdict files have stable filenames (`fixture-<id>.json`) and a stable JSON envelope shape (per FR-012). Verdict text is non-deterministic; envelope shape is byte-stable for downstream parsing. Test fixture under `plugin-kiln/tests/judge-verdict-envelope/` per SC-005 asserts the envelope-shape invariant.

**NFR-004 (Backward compatibility)**: PRDs in `09-research-first` that have already shipped (`research-first-foundation`, `research-first-axis-enrichment`) MUST continue to work unchanged. The two new agents are additive — `parse-prd-frontmatter.sh` is extended only with the `rubric:` validation rule (no shape change to existing axis declarations); `evaluate-direction.sh` is unmodified (the `output_quality` axis goes through the new sibling `evaluate-output-quality.sh`).

**NFR-005 (Tool-allowlist conformance)**: Both new agents MUST conform to CLAUDE.md Architectural Rules 1, 2, 3, 4, 6. Synthesizer's allowlist stays as committed: `Read, Write, SendMessage, TaskUpdate`. Judge's allowlist stays as committed: `Read, SendMessage, TaskUpdate`. Neither has `Agent` (Rule 4) nor `Bash` (Rule 1 sibling — limit blast radius). CI lint at `plugin-kiln/scripts/research/lint-agent-allowlists.sh` asserts the literal allowlist strings haven't drifted.

**NFR-006a (Skip-path structural invariant)**: When `/plan` runs against a PRD that declares neither `fixture_corpus: synthesized` nor an `output_quality` axis, the SKILL MUST NOT spawn either agent and MUST NOT invoke any net-new subprocess that's not strictly required to make the spawn-or-skip decision.

**NFR-006b (Skip-path measurement invariant — RECONCILED 2026-04-25)**: The /plan skip-path latency overhead — measured as `t_skip - t_baseline` over 5 runs (median) where `t_baseline` is `/plan` against a pre-existing PRD declaring neither feature on the new SKILL.md surface and `t_skip` is `/plan` against a fresh fixture PRD declaring neither feature on the new SKILL.md surface — MUST be ≤ 50 ms. Measured by `plugin-kiln/tests/plan-time-agents-skip-perf/`.

**NFR-007 (Loud-failure config)**: Every config file (`judge-config.yaml`, `judge-config.yaml.example`, per-skill `fixture-schema.md`, `max_regenerations`, `pinned_model`, `pinned_model_fallbacks`, `rubric:`, `promote_synthesized:`) is loud-failure on malformation. NEVER silently fall back to a hardcoded default.

**NFR-008 (Deterministic position blinding)**: The position-A-vs-B assignment in FR-015 is seeded by `sha256("<prd-slug>:<fixture-id>")` so that re-running the research run on the same PRD produces the same position mapping. This makes the report reproducible across re-runs and makes test fixtures possible (the test asserts the verdict file's `blinded_position_mapping` matches the expected seeded value).

**NFR-009 (Regeneration budget visibility)**: The per-PRD research report header MUST display `Regeneration budget used: <N>/<corpus_size × max_regenerations>`. Token spend on regenerations is auditable.

## Assumptions

- **A-001 (regeneration token spend acceptable)**: Worst-case `corpus_size × max_regenerations` synthesizer spawns (e.g., 10 × 3 = 30 spawns at ~5k tokens each = ~150k tokens) is acceptable for a one-time per-PRD cost. If first-real-use shows otherwise, follow-on PRD scoping reduces `max_regenerations` default or adds a "summary mode" regenerator.
- **A-002 (per-skill fixture-schema.md is human-authored)**: The schema file is a PREREQUISITE for a skill to be a valid synthesis target — it describes the input shape the skill's fixtures must conform to. We do not infer schemas. First-real-use may demonstrate this needs a schema-template generator; flagged as follow-on in Risks.
- **A-003 (judge model pinning is single-model not ensemble)**: V1 ships single-model pinning. Multi-model judge ensembles (e.g., majority vote of opus + sonnet) is not in scope; flagged as follow-on in Risks.
- **A-004 (composer is already shipped)**: The runtime context-injection composer at `plugin-wheel/scripts/agents/compose-context.sh` is already shipped per `build/agent-prompt-composition-20260425` and emits `{subagent_type, prompt_prefix, model_default}` JSON. This PRD relies on it but does not modify it.
- **A-005 (axis-enrichment frontmatter parser is already shipped)**: `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh` from `build/research-first-axis-enrichment-20260425` (PR #178) is already shipped and exports the `empirical_quality[]` JSON projection. This PRD extends its validator with the `rubric:` rule but reuses its parser harness.

## Success Criteria

- **SC-001 (Synthesized-corpus PRD ships end-to-end)**: At least one synthesized-corpus PRD has shipped (merged PR) end-to-end through `/kiln:kiln-build-prd`. (Joint dependency on `research-first-build-prd-wiring` step 6; tracked there.)
- **SC-002 (Output-quality PRD ships end-to-end)**: At least one `output_quality`-axis PRD has shipped end-to-end with all three anti-drift controls active and the identical-input control passing.
- **SC-003 (Judge prompt lint)**: `plugin-kiln/scripts/research/lint-judge-prompt.sh` verifies the judge's per-call composer prompt template contains the literal `{{rubric_verbatim}}` interpolation token AND no rubric-summarization/paraphrasing language. CI gate. Test fixture at `plugin-kiln/tests/judge-prompt-lint/`.
- **SC-004 (Stable synthesizer naming)**: Re-running synthesis on the same PRD inputs produces an N-fixture proposal set with stable filenames `fixture-001.md` … `fixture-NNN.md`, even though fixture content varies (LLM non-determinism). Test fixture at `plugin-kiln/tests/fixture-synthesizer-stable-naming/` asserts the filename invariant via mocked synthesizer (the test does not call a live LLM; it mocks the agent spawn output and asserts the orchestrator's filename derivation is correct).
- **SC-005 (Stable judge envelope)**: Re-running the judge on the same baseline/candidate pair produces a verdict envelope with the stable JSON shape `{axis_id, blinded_verdict, blinded_position_mapping, deanonymized_verdict, fixture_id, model_used, rationale, rubric_verbatim_hash}` regardless of verdict content. Test fixture at `plugin-kiln/tests/judge-verdict-envelope/` (mocked judge spawn, asserts envelope shape).
- **SC-006 (Skip-path latency — RECONCILED 2026-04-25)**: `/plan` skip-path for PRDs declaring neither feature has `t_skip - t_baseline ≤ 50 ms` over 5 runs (median). Measured by `plugin-kiln/tests/plan-time-agents-skip-perf/`. Threshold reconciled against `research.md §baseline` per Directive 1 above.
- **SC-007 (Frontmatter rubric validation)**: `parse-prd-frontmatter.sh` extended-validator returns exit 2 with `Bail out! output_quality-axis-missing-rubric: <prd-path>` for every PRD declaring `output_quality` without a non-empty `rubric:` field. Test fixture at `plugin-kiln/tests/parse-prd-frontmatter-rubric-required/`.
- **SC-008 (Identical-input drift detection)**: A synthetic test that injects an identical-input control with a mocked judge response of `A_better` MUST cause the orchestrator to halt with `Bail out! judge-drift-detected: blinded_verdict=A_better` and produce `.kiln/research/<prd-slug>/judge-drift-report.md`. Test fixture at `plugin-kiln/tests/judge-identical-input-control-fail/`.
- **SC-009 (Position blinding determinism)**: For a fixed `<prd-slug>:<fixture-id>` pair, the position-mapping file's blinded assignment is byte-stable across re-runs. Test fixture at `plugin-kiln/tests/judge-position-blinding-deterministic/`.
- **SC-010 (Regeneration exhaustion bail)**: A synthesis run where every regenerate is rejected `max_regenerations + 1` times causes `/plan` to halt with `Bail out! regeneration-exhausted: fixture-<id> rejected <N> times`. Test fixture at `plugin-kiln/tests/synthesis-regeneration-exhausted/`.

## Risks & Open Questions

Carried forward from PRD body, refined by clarification session:

- **R-001 — Synthesizer triviality** (PRD): mitigated by FR-008 diversity prompt + FR-006 reject-then-regenerate loop. Surface check: research report includes the literal diversity-prompt verbatim so reviewers can see what was asked of the synthesizer.
- **R-002 — Judge reliability is unmeasured** (PRD): the three anti-drift controls catch worst-case failure modes but don't establish a quantitative reliability number. **Mitigation**: ship with a loud "FIRST-N-RUNS" warning banner on every research run that includes `output_quality` for the first N PRDs; require human reviewer sign-off on judge verdicts before merge for those first N runs. Graduate to "trusted gate" only after a follow-on PRD measures judge reliability against a known-outcome corpus. Carried into a follow-on roadmap item to be filed by the team-lead post-merge.
- **R-003 — Pinned model deprecation** (PRD): mitigated by `pinned_model_fallbacks: [...]` per FR-014. Verdict envelope records WHICH model was actually used so reviewers can spot fallback usage.
- **R-004 — Promote-synthesized growth** (PRD): mitigated by `promote_synthesized: false` default. Follow-on `kiln-coverage`-style audit flagging shared corpora exceeding threshold size is a separate roadmap item.
- **R-005 — `judge-config.yaml` per-developer drift**: each developer's `.kiln/research/judge-config.yaml` could drift from the committed `judge-config.yaml.example`, producing different research-run outcomes on different machines. **Mitigation**: research report header records `Pinned judge model: <model> (source: <local-config | example-fallback>)` so reviewers can see if the run used a non-default config.
- **R-006 — `corpus_size × max_regenerations` worst-case spend on a feature-blast PRD with a 10-fixture min**: 30 synthesizer spawns × ~5k tokens = ~150k tokens. **Mitigation**: NFR-009 surfaces actual usage in report header; if real usage is ever > 50% of worst-case on first-real-use PRDs, file follow-on item to lower default `max_regenerations`.

**Open questions deferred to first-real-use** (not blocking implementation):

- **OQ-1 (deferred from PRD; restated)**: Should the judge be allowed to abstain (`unsure`)? Resolved NO in v1 (FR-012). Re-open if first-real-use produces a genuinely-tied case.
- **OQ-3 (NEW)**: Should the synthesizer be rate-limited (e.g., max N regenerations per `/plan` invocation across ALL fixtures, not just per-fixture)? Defer to first-real-use; bound is currently per-fixture only via FR-006.
- **OQ-4 (NEW)**: Should the identical-input control verdict envelope be visually distinguished from regular fixtures in the research report? Defer; current decision is one combined "Judge verdicts" section listing the control row LAST with a `[control]` annotation.

## Dependencies & Inputs

- `specs/research-first-foundation/contracts/interfaces.md` — runner shape, transcript shape (referenced as "foundation §N").
- `specs/research-first-axis-enrichment/contracts/interfaces.md §3` — `parse-prd-frontmatter.sh` shape (this PRD extends with `rubric:` rule).
- `specs/research-first-axis-enrichment/contracts/interfaces.md §4` — `evaluate-direction.sh` contract (this PRD ships `evaluate-output-quality.sh` as a sibling matching the same stdout contract).
- `plugin-wheel/scripts/agents/compose-context.sh` — runtime composer (per A-004, NOT modified).
- `plugin-kiln/agents/fixture-synthesizer.md` — existing stub (this PRD extends with role-specific operating prose).
- `plugin-kiln/agents/output-quality-judge.md` — existing stub (this PRD extends with role-specific operating prose).
- `plugin-kiln/skills/plan/SKILL.md` — single edit point for the spawn wiring (per single-implementer rationale in agent-notes/specifier.md).
- `plugin-kiln/lib/research-rigor.json` — rigor row source for `min_fixtures` derivation in FR-002.
- `.specify/memory/constitution.md` — Articles I, VII, VIII (read first; checked in plan.md gate).
