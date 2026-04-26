---
derived_from:
  - .kiln/roadmap/items/2026-04-24-research-first-fixture-synthesizer.md
  - .kiln/roadmap/items/2026-04-24-research-first-output-quality-judge.md
distilled_date: 2026-04-25
theme: research-first-plan-time-agents
---
# Feature PRD: Research-first plan-time agents — fixture-synthesizer + output-quality judge

**Date**: 2026-04-25
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)

## Background

The `09-research-first` phase introduces a feasibility gate that runs comparative A/B measurements (baseline plugin-dir vs candidate worktree) against a fixture corpus before merging changes that declare `needs_research: true`. Steps 1–3 of the phase have shipped: the fixture corpus format + baseline-vs-candidate runner MVP (`research-first-fixture-format-mvp`), the per-axis direction gate with blast-radius-dynamic rigor (`research-first-per-axis-gate-and-rigor`), and the time + cost axes with a maintained pricing table (`research-first-time-and-cost-axes`). All three are committed under `docs/features/2026-04-25-research-first-foundation/` and `docs/features/2026-04-25-research-first-axis-enrichment/`. What remains before the gate becomes useful in practice is the two `/plan`-time agents that supply the corpus and evaluate the qualitative axis.

Recently the roadmap surfaced these items in the **09-research-first** phase: `2026-04-24-research-first-fixture-synthesizer` (feature), `2026-04-24-research-first-output-quality-judge` (feature). Both are net-new agents spawned by `/plan` when the PRD's research block declares them. They are independent of each other — synthesizer reads the PRD's empirical-quality declarations and a per-skill schema to propose fixtures; judge reads baseline + candidate output pairs and a verbatim PRD-author rubric to emit per-fixture verdicts. Bundling them in one PRD keeps the plan-time agent surface coherent and lets a single `/kiln:kiln-build-prd` run wire both into the existing `/plan` step.

The two items have orthogonal failure modes. The synthesizer fails by producing trivial, non-representative fixtures — a corpus where every entry resembles "the first README example" lets the gate pass with misleading confidence. The judge fails by drifting — a 70%-correct judge turns the gate into a coin-flip with extra steps. The PRD must address both failure modes head-on with concrete anti-drift / anti-triviality measures rather than treating them as future work.

### Source Issues

| # | Source Entry | Source | Type | GitHub Issue | Severity / Area |
|---|--------------|--------|------|--------------|------------------|
| 1 | [Research-first step 4 — fixture-synthesizer agent at plan-time with human review gate](../../../.kiln/roadmap/items/2026-04-24-research-first-fixture-synthesizer.md) | .kiln/roadmap/ | item | — | feature / phase:09-research-first |
| 2 | [Research-first step 5 — output-quality judge-agent with PRD-derived rubric (riskiest axis)](../../../.kiln/roadmap/items/2026-04-24-research-first-output-quality-judge.md) | .kiln/roadmap/ | item | — | feature / phase:09-research-first |

## Implementation Hints

A new agent type (`fixture-synthesizer`) spawned during `/plan` when the PRD declares
`fixture_corpus: synthesized` (or `fixture_corpus: promoted` and the existing promoted pool
has fewer fixtures than the blast_radius minimum). Takes as input:

  - The skill being A/B'd (from PRD)
  - The PRD's `empirical_quality[]` declarations (to bias toward fixtures that exercise
    the axes being gated)
  - A schema describing the skill's expected input shape (lives alongside the skill at
    `plugin-<name>/skills/<skill>/fixture-schema.md`, human-written)
  - The minimum fixture count for the PRD's blast_radius

Output: N proposed fixtures written to `.kiln/research/<prd-slug>/corpus/proposed/` (NOT the
committed corpus path). `/plan` then surfaces them to the human:

  - "Synthesized N fixtures. Here's a 3-line summary of each. Accept each one, reject, or
    edit before committing. Type `accept-all` to skip review."

Only after human review do fixtures move to `plugin-<name>/fixtures/<skill>/corpus/`.

Promoted vs one-off: the PRD can declare `promote_synthesized: true` to keep accepted fixtures
in the persistent corpus after the PRD ships (growing the long-term suite). Default is `false`
— fixtures are one-off for this PRD only, kept in `.kiln/research/<prd-slug>/corpus/` and not
promoted to the shared location. This respects "no persistent hand-curated corpus" as the
default stance, while letting maintainers opt-in to growing one.

Hardest calibration: making synthesized fixtures representative rather than trivial. A dumb
synthesizer produces "all fixtures look like the skill's first example in the README" — zero
diversity, no edge cases, passing the gate means nothing. Counter this with:
  - Explicit diversity prompt ("generate fixtures that exercise edge cases: empty inputs,
    maximum-size inputs, typical inputs, adversarial inputs")
  - Reject-then-regenerate loop during human review (reject one, ask for a replacement that
    exercises a different axis)

*(from: `2026-04-24-research-first-fixture-synthesizer`)*

The `output_quality` axis is the fuzzy one — mechanical axes (accuracy / tokens / time / cost)
can be tested by diffing numbers; output quality needs a judge.

Design:

  - PRD declares `empirical_quality: [..., {metric: output_quality, direction: equal_or_better,
    rubric: "..."}, ...]`. The `rubric:` field is a free-text string written by the PRD author
    describing the intended improvement axis ("more concise without losing accuracy",
    "clearer step-ordering", "more actionable error messages").
  - Judge-agent receives per fixture: the baseline output, the candidate output, and the VERBATIM
    rubric string (NEVER summarize the rubric — per `2026-04-24-skill-ab-harness-wheel-workflow`
    "The rubric has to be derived from the PR intent (commit message, user-supplied `--intent`)
    and passed to the judge verbatim, not summarized"). Emits: candidate_better | equal | baseline_better
    + one-sentence rationale.
  - Gate: for every fixture, judge verdict MUST NOT be `baseline_better` (direction: equal_or_better).

Anti-drift measures (the hardest-part problem):
  - Pinned judge model: use a specific model ID (not "whatever is newest") so judge behavior
    is reproducible across the research run. Document the pinned model in the PRD blockers
    if it diverges from the primary model.
  - Blind-to-version: judge does NOT know which output came from baseline vs candidate (randomize
    the A/B label per fixture; record mapping in the report). This is the single most important
    anti-drift measure.
  - Pairwise sanity check: occasionally run judge with baseline=candidate=same-output. Expected
    verdict: `equal` (within noise). If judge says `candidate_better` when inputs are identical,
    the judge is drifting — fail the research run with a clear error.

Defer default-on: this axis ships opt-in per PRD. Most PRDs will use accuracy/tokens/cost/time
only. Only opt into `output_quality` when the improvement is genuinely qualitative and can't
be captured mechanically.

*(from: `2026-04-24-research-first-output-quality-judge`)*

## Problem Statement

The shipped research-first runner can measure a candidate against a corpus and gate on numeric direction per axis, but two pieces of the workflow are missing before a maintainer can actually use it on a real PRD:

1. **No corpus exists for most skills.** The runner accepts a declared fixture path, but maintainers without an existing corpus have to hand-curate one before the gate can run — a per-PRD upfront cost large enough to kill adoption. Burnout on fixture authoring is the predictable failure mode of this whole initiative.
2. **No qualitative axis.** The shipped axes (`accuracy`, `tokens`, `time`, `cost`) are all mechanical. A non-trivial fraction of comparative changes maintainers want to make ("clearer error messages", "more concise PRDs", "more actionable suggestions") are qualitative — they need a judge. Without one, those changes can't be gated and the research-first pipeline only helps for the easy cases.

The two missing pieces are independent agents wired into `/plan`. Building them together in one PRD lets us land a coherent plan-time agent surface (both attach at the same workflow step, both write to `.kiln/research/<prd-slug>/`, both share the same human-review affordance pattern) while keeping their orthogonal failure modes explicit.

## Goals

- Ship a `fixture-synthesizer` agent that generates a representative N-fixture corpus at `/plan` time when the PRD declares `fixture_corpus: synthesized`, with mandatory human review before fixtures land in the committed path.
- Ship an `output-quality` judge-agent that evaluates baseline vs candidate output pairs against a verbatim PRD-author rubric, with three concrete anti-drift measures (pinned model, blind-to-version ordering, identical-input sanity check).
- Both agents are opt-in per PRD via the existing research block — they cost zero tokens for PRDs that don't declare them.
- Establish the convention that `/plan`-time agents write to `.kiln/research/<prd-slug>/` and surface for human accept/reject before any committed-path write.

## Non-Goals

- Wiring the agents into `/kiln:kiln-build-prd` — that's step 6 (`research-first-build-prd-wiring`), a separate PRD. This PRD only ships the agents and their `/plan`-time spawn convention.
- Classifier inference of `needs_research: true` from capture descriptions — that's step 7 (`research-first-classifier-inference`), a separate PRD.
- A persistent shared fixture corpus that grows across PRDs as the default. The synthesizer's default is one-off per-PRD fixtures; promotion to the shared corpus is opt-in via `promote_synthesized: true`.
- A judge-reliability test corpus or formal validation that judges are >N% correct. The anti-drift measures (pinned model, blind ordering, identical-input check) ship in this PRD; quantitative reliability measurement is follow-on work flagged in Risks.
- Replacing the mechanical axes with the judge. Most PRDs will use `accuracy`/`tokens`/`time`/`cost` only; `output_quality` is opt-in per PRD.

## Requirements

### Functional Requirements

#### Theme: fixture-synthesizer (FR-001 — FR-008)

**FR-001 (from: `.kiln/roadmap/items/2026-04-24-research-first-fixture-synthesizer.md`)**: Define a new agent role `fixture-synthesizer` under `plugin-kiln/agents/fixture-synthesizer.md` (or `plugin-wheel/agents/` per current registry conventions) registered as `kiln:fixture-synthesizer` (per CLAUDE.md Architectural Rule 1 — never `general-purpose`). The agent's tool allowlist MUST be limited to `Read`, `Write`, `Bash` (for jq invocations); no `Agent`, no `Edit`, no network tools.

**FR-002 (from: `.kiln/roadmap/items/2026-04-24-research-first-fixture-synthesizer.md`)**: `/plan` MUST spawn `fixture-synthesizer` exactly when the PRD frontmatter declares `fixture_corpus: synthesized` OR (`fixture_corpus: promoted` AND the existing promoted pool has fewer fixtures than the blast-radius minimum from `2026-04-24-research-first-per-axis-gate-and-rigor`).

**FR-003 (from: `.kiln/roadmap/items/2026-04-24-research-first-fixture-synthesizer.md`)**: Agent inputs MUST include: (a) the skill identifier being A/B'd; (b) the PRD's `empirical_quality[]` declarations; (c) a per-skill fixture schema at `plugin-<name>/skills/<skill>/fixture-schema.md` (human-authored, prerequisite); (d) the minimum fixture count derived from `blast_radius`. Inputs flow via the runtime context-injection composer (CLAUDE.md "Composer integration recipe").

**FR-004 (from: `.kiln/roadmap/items/2026-04-24-research-first-fixture-synthesizer.md`)**: Synthesizer output MUST be written to `.kiln/research/<prd-slug>/corpus/proposed/` and never to the committed corpus path. Each proposed fixture is a separate file with deterministic naming (`fixture-001.md`, `fixture-002.md`, …) and a 3-line summary header (used by the human-review prompt).

**FR-005 (from: `.kiln/roadmap/items/2026-04-24-research-first-fixture-synthesizer.md`)**: After synthesis, `/plan` MUST surface a per-fixture confirm-never-silent prompt: each proposed fixture rendered with its 3-line summary; user replies `accept`, `reject`, `edit`, or `accept-all`. No fixture moves to the committed path without an explicit accept (per-fixture or via accept-all).

**FR-006 (from: `.kiln/roadmap/items/2026-04-24-research-first-fixture-synthesizer.md`)**: `/plan` MUST support a reject-then-regenerate loop: when the user rejects a fixture, the synthesizer is re-spawned with the rejected fixture's axis-summary in the prompt and asked to generate a replacement that exercises a different axis. Loop bounded by a configurable max-regenerations (default 3 per fixture) to prevent runaway token spend.

**FR-007 (from: `.kiln/roadmap/items/2026-04-24-research-first-fixture-synthesizer.md`)**: Accepted fixtures MUST move to `plugin-<name>/fixtures/<skill>/corpus/` (committed path) when `promote_synthesized: true` is declared in PRD frontmatter, OR remain at `.kiln/research/<prd-slug>/corpus/` (one-off path) when `promote_synthesized: false` (default). `/plan` MUST log which path each fixture landed in for the research report.

**FR-008 (from: `.kiln/roadmap/items/2026-04-24-research-first-fixture-synthesizer.md`)**: Synthesizer prompt MUST explicitly request diversity: "generate fixtures that exercise edge cases: empty inputs, maximum-size inputs, typical inputs, adversarial inputs". The diversity prompt is part of the system prompt template, not the per-call context.

#### Theme: output-quality judge (FR-009 — FR-016)

**FR-009 (from: `.kiln/roadmap/items/2026-04-24-research-first-output-quality-judge.md`)**: Define a new agent role `output-quality-judge` registered as `kiln:output-quality-judge`. Tool allowlist limited to `Read` only (no Bash, no Write, no Edit) — judge reads paired output files and emits a verdict; it never writes to disk and never executes code. (CLAUDE.md Rule 1 — plugin-prefixed.)

**FR-010 (from: `.kiln/roadmap/items/2026-04-24-research-first-output-quality-judge.md`)**: Extend the `empirical_quality[]` schema (defined in `2026-04-24-research-first-build-prd-wiring`'s implementation_hints, prerequisite for build-prd integration but defined here for the judge axis) to accept `{metric: output_quality, direction: equal_or_better, rubric: <free-text-string>}`. The `rubric:` field is required when `metric: output_quality`; validator MUST reject the axis if `rubric:` is missing or empty.

**FR-011 (from: `.kiln/roadmap/items/2026-04-24-research-first-output-quality-judge.md`)**: Judge agent inputs per fixture MUST include: (a) the baseline output content; (b) the candidate output content; (c) the VERBATIM rubric string from the PRD frontmatter — the judge prompt template MUST NOT summarize, paraphrase, or truncate the rubric. Verbatim-rubric invariant is enforced by a lint check that asserts the prompt template includes the literal `{{rubric}}` interpolation token unmodified.

**FR-012 (from: `.kiln/roadmap/items/2026-04-24-research-first-output-quality-judge.md`)**: Judge output MUST be a structured verdict: one of `candidate_better | equal | baseline_better` plus a one-sentence rationale. The verdict format is a JSON envelope `{"verdict": "...", "rationale": "..."}` written to `.kiln/research/<prd-slug>/judge-verdicts/fixture-<id>.json`.

**FR-013 (from: `.kiln/roadmap/items/2026-04-24-research-first-output-quality-judge.md`)**: Per-axis gate evaluation for `output_quality` MUST fail the research run if ANY fixture's verdict is `baseline_better` (direction: `equal_or_better`). This wires into the existing per-axis gate from `2026-04-24-research-first-per-axis-gate-and-rigor`.

**FR-014 (Anti-drift: pinned model — from: `.kiln/roadmap/items/2026-04-24-research-first-output-quality-judge.md`)**: Judge agent MUST be invoked with a pinned model ID (not "whatever is newest"). The pinned model is configured at `.kiln/research/judge-config.yaml` with key `pinned_model: <model-id>`. Default value SHOULD match the current Anthropic model recommendation (e.g., `claude-opus-4-7`) but a maintainer override is supported. If the pinned model is unavailable at runtime, the research run halts with a clear error.

**FR-015 (Anti-drift: blind-to-version — from: `.kiln/roadmap/items/2026-04-24-research-first-output-quality-judge.md`)**: Per fixture, the orchestrator MUST randomly assign baseline output to position A or B (50/50), pass `{"output_a": ..., "output_b": ...}` to the judge (NOT `{"baseline": ..., "candidate": ...}`), and record the mapping `{fixture_id: position_assignment}` in the research report. The judge's verdict (`A_better | equal | B_better`) is then de-anonymized into `candidate_better | equal | baseline_better` by the orchestrator using the recorded mapping.

**FR-016 (Anti-drift: identical-input sanity check — from: `.kiln/roadmap/items/2026-04-24-research-first-output-quality-judge.md`)**: For every research run that includes the `output_quality` axis, the orchestrator MUST insert at least one identical-input control (baseline_output == candidate_output, both copied from the actual baseline). Expected verdict: `equal`. If the judge returns `A_better` or `B_better` on the control fixture, the research run halts with a "judge drift detected" error and the verdict is attached to `.kiln/research/<prd-slug>/judge-drift-report.md`.

### Non-Functional Requirements

**NFR-001 (Opt-in cost)**: PRDs that do NOT declare `fixture_corpus: synthesized` and do NOT declare an `output_quality` axis MUST incur zero token cost from these agents — `/plan` skips both spawn paths entirely, with no probe or spawn-then-no-op behavior.

**NFR-002 (Determinism for synthesizer review)**: Proposed fixture filenames are deterministic (`fixture-001.md` … `fixture-NNN.md`) so that re-running synthesis on identical inputs produces a comparable proposal set. Fixture content itself is non-deterministic (LLM output) and is not asserted byte-identical.

**NFR-003 (Determinism for judge verdicts)**: Per-fixture verdict files include a stable filename (`fixture-<id>.json`) and a stable JSON envelope structure. Verdict text is non-deterministic (LLM output) and is not asserted byte-identical, but the envelope shape is stable for downstream parsing.

**NFR-004 (Backward compatibility)**: PRDs in `09-research-first` that have already shipped (`research-first-fixture-format-mvp`, `research-first-per-axis-gate-and-rigor`, `research-first-time-and-cost-axes`) MUST continue to work unchanged. The synthesizer + judge are additive — declared-corpus and mechanical-axis-only flows are unaffected.

**NFR-005 (Tool-allowlist conformance)**: Both new agents MUST conform to the CLAUDE.md "Architectural Rules" (Rule 1: plugin-prefixed `subagent_type`, never `general-purpose`; Rule 4: no nested spawns; Rule 6: SendMessage relay for any team-mode coordination). Synthesizer's allowlist: `Read`, `Write`, `Bash`. Judge's allowlist: `Read` only.

## User Stories

- **As a maintainer with no existing fixture corpus**, I declare `fixture_corpus: synthesized` in my source artifact's research block. `/plan` synthesizes 10 diverse fixtures and shows me 3-line summaries; I accept 7, reject 2 (re-synthesize replacements), and edit 1. The corpus lands at `.kiln/research/<my-prd-slug>/corpus/` (one-off; not promoted) and the rest of the research-first pipeline runs as if I'd hand-curated it.
- **As a maintainer making a qualitative improvement** (clearer error messages, say), I declare `empirical_quality: [{metric: output_quality, direction: equal_or_better, rubric: "Error messages should name the specific failure mode and suggest one concrete next action"}]`. The judge evaluates baseline vs candidate per fixture against my verbatim rubric. I see one verdict per fixture in the research report attached to the PR.
- **As a maintainer auditing judge reliability**, I check the research report and confirm: (a) the run used the pinned model `claude-opus-4-7`; (b) the A/B position mapping is recorded; (c) the identical-input control returned `equal`. If any of those three are missing or wrong, the research run halted before merge.

## Success Criteria

- **SC-001**: At least one synthesized-corpus PRD has shipped (merged PR) end-to-end through `/kiln:kiln-build-prd` (which requires `research-first-build-prd-wiring` to also ship — joint dependency tracked in the routing PRD's success criteria).
- **SC-002**: At least one `output_quality`-axis PRD has shipped end-to-end with the three anti-drift controls active and the identical-input control passing.
- **SC-003**: A lint check (`scripts/research/lint-judge-prompt.sh` or equivalent) verifies that the judge agent's prompt template contains the literal `{{rubric}}` interpolation token and no rubric-summarization/paraphrasing language. CI gate.
- **SC-004**: Re-running synthesis on the same PRD inputs produces an N-fixture proposal set with stable filenames `fixture-001.md` … `fixture-NNN.md`, even though fixture content varies (LLM non-determinism). Test fixture under `plugin-kiln/tests/fixture-synthesizer-stable-naming/`.
- **SC-005**: Re-running the judge on the same baseline/candidate pair produces a verdict envelope with the stable JSON shape `{"verdict": "...", "rationale": "..."}` regardless of verdict content. Test fixture under `plugin-kiln/tests/judge-verdict-envelope/`.
- **SC-006**: Performance — `/plan` skip-path for PRDs that declare neither synthesized corpus nor `output_quality` axis adds < 50 ms (no probe, no spawn). Measured via timing harness in `plugin-kiln/tests/plan-time-agents-skip-perf/`.

## Tech Stack

Inherited from the parent project:

- **Bash 5.x + jq + python3** — agent registration, runtime context composer, validators
- **Claude Code agent runtime** — for `kiln:fixture-synthesizer` and `kiln:output-quality-judge` agent spawns; spawn from `/plan` SKILL via the runtime composer (CLAUDE.md "Composer integration recipe")
- **YAML frontmatter** — `empirical_quality[]` axis declarations, `fixture_corpus:` directives, `promote_synthesized:` flag
- **Anthropic API** — pinned model for judge (default `claude-opus-4-7`, maintainer override at `.kiln/research/judge-config.yaml`)

No new runtime dependencies.

## Risks & Open Questions

- **Synthesizer triviality** — the explicit diversity prompt + reject-then-regenerate loop are mitigations, not guarantees. If the first 3 real-use PRDs produce trivial corpora despite both, escalate to a richer schema-input format or a second-stage diversification pass. **Mitigation**: include the diversity-prompt assertion in the research report so reviewers can see what was asked of the synthesizer.
- **Judge reliability is unmeasured** — the three anti-drift controls catch the worst failure modes but do not establish a quantitative reliability number. A judge that is consistently 70% correct passes all three controls and still produces a useless gate. **Mitigation**: ship with a loud warning banner on every research run that includes `output_quality` for the first N PRDs; require a human reviewer to sign off on the verdict before merge for those first N runs. Graduate to "trusted gate" only after a follow-on PRD measures judge reliability against a known-outcome corpus.
- **Pinned model availability** — if the pinned model is deprecated mid-phase, every PRD using `output_quality` halts. **Mitigation**: judge-config.yaml supports a fallback model list; runtime walks the list and uses the first available, recording which model was used in the verdict envelope.
- **Promote-synthesized growth** — if maintainers default-on `promote_synthesized: true` for convenience, the shared corpus grows uncontrolled and stops representing what each individual PRD actually needed. **Mitigation**: keep the default `false`; add a periodic `kiln-coverage`-style audit that flags shared corpora exceeding a threshold size.
- **Open question** — should the judge be allowed to abstain (return `unsure`) rather than forcing a three-way verdict? Forcing a verdict matches the gate semantics; allowing abstention introduces a fourth case the orchestrator must handle. Defer decision until the first real-use PRD encounters a genuinely-tied case.
- **Open question** — should `fixture-schema.md` be required for synthesis, or can the synthesizer infer schema from the skill's existing fixtures (when any exist)? Required-schema is safer (no silent inference); inferred-schema is more ergonomic. Defer until first real-use PRD; ship required-schema first.
