# Feature Specification: Research-First Completion — schema + distill + build-prd routing + classifier + E2E gate

**Feature Branch**: `build/research-first-completion-20260425`
**Created**: 2026-04-25
**Status**: Draft
**Input**: `docs/features/2026-04-26-research-first-completion/PRD.md`
**Parent items** (all phase `09-research-first`):
  - `.kiln/roadmap/items/2026-04-24-research-first-build-prd-wiring.md` (kind: feature, step 6)
  - `.kiln/roadmap/items/2026-04-24-research-first-classifier-inference.md` (kind: feature, step 7)
  - `.kiln/roadmap/items/2026-04-24-research-first-phase-complete-criterion.md` (kind: goal — phase-complete-criterion)
**Builds on**:
  - `specs/research-first-foundation/{spec.md,plan.md,contracts/interfaces.md}` (PR #176, runner at `plugin-wheel/scripts/harness/research-runner.sh`).
  - `specs/research-first-axis-enrichment/{spec.md,plan.md,contracts/interfaces.md}` (PR #178, per-axis gate + frontmatter parser at `parse-prd-frontmatter.sh`).
  - `specs/research-first-plan-time-agents/{spec.md,plan.md,contracts/interfaces.md}` (PR #182, fixture-synthesizer + output-quality-judge agents).
  - `plugin-kiln/scripts/roadmap/validate-item-frontmatter.sh` (existing item validator).
  - `plugin-kiln/scripts/roadmap/classify-description.sh` (existing kind/surface classifier — extended additively).
**Baseline checkpoint**: SKIPPED — see §"Baseline rationale". The PRD's NFR-002 / NFR-003 / NFR-005 are byte-identity assertions, not numeric perf budgets. The reference baseline IS the current pre-PR distill output by construction; no measurement needed.

## Overview

Five surfaces ship in ONE PR — the integration layer that closes phase `09-research-first`:

1. **Schema extensions** across four intake surfaces (item / issue / feedback / PRD frontmatter): six new optional research-block fields (`needs_research`, `empirical_quality`, `fixture_corpus`, `fixture_corpus_path`, `promote_synthesized`, `excluded_fixtures`). All default-off — absence preserves byte-identical pre-PR behavior.
2. **`/kiln:kiln-distill` propagation**: when ANY selected source declares `needs_research: true`, the generated PRD inherits the research block. Multi-source axis merging is union semantics; conflicting `direction` on the same `metric` triggers a confirm-never-silent ambiguity prompt naming both source paths and both directions.
3. **`/kiln:kiln-build-prd` auto-routing**: reads PRD frontmatter on entry. On `needs_research: true`, dispatches the research-first variant pipeline (baseline → implement-in-worktree → measure-candidate → per-axis gate → audit → PR). Otherwise dispatches the existing pipeline byte-identically.
4. **Classifier inference** (capture-time ergonomics): `plugin-kiln/scripts/roadmap/classify-description.sh` and sibling capture surfaces detect comparative-improvement signal words (`faster`, `cheaper`, `regression`, etc.) and propose the research block via the existing coached-capture accept/tweak/reject affordance. False-positive recovery is rejection → no research-block frontmatter (NFR-006).
5. **E2E phase-complete fixture** at `plugin-kiln/tests/research-first-e2e/`: scaffolds a temp-dir test repo with mocked `kiln-init`, declares a research-needing roadmap item, runs distill → build-prd, and exercises BOTH happy and regression paths (gate catches a deliberately-regressing candidate). Without both, the phase has only proven the happy path.

The four themes are tightly coupled — schema feeds distill propagation; distill propagation feeds build-prd routing; classifier proposes the schema at capture time; the E2E fixture asserts all three end-to-end. Bundled in one PR per the PRD body's "integration coherence" rationale: schema, propagation, routing, classifier, and the E2E proof land together or not at all.

## Resolution of PRD Open Questions

The PRD `## Risks & Open Questions` left four open questions. Resolved as follows; rationale anchors specific FRs/NFRs.

- **OQ-1 (Distill conflict prompt — should it cap at N sources?)**: RESOLVED — **NO cap in v1**. The FR-006 contract names "two or more" sources without bound; v1 renders conflicts grouped by `metric`, one block per metric, all conflicting `(source, direction)` pairs visible. If real-use produces a soup, follow-on adds an "accept-all-as-equal_or_better" escape hatch. Encoded in **FR-006** + **NFR-004**.
- **OQ-2 (Classifier high-signal-only config flag)**: RESOLVED — **NOT in v1**. The PRD's `.kiln/classifier-config.yaml::research_inference: high-signal-only` config flag is deferred. V1 ships the broad signal set (FR-013 word list); revisit after first 10 real captures per the PRD's Risks block. NFR-006 (false-positive recovery) covers the only currently-blocking concern. **Rationale**: shipping a config flag whose only job is "narrow this list" before evidence of false-positive friction is YAGNI; the maintainer can already reject any proposed block.
- **OQ-3 (Classifier learns from rejected proposals)**: DEFERRED to post-phase work. Signal-word matching is stateless by design (PRD §"Open question"). No FR.
- **OQ-4 (`fixture_corpus_path` absolute vs repo-relative)**: RESOLVED — **repo-relative only** in v1 (PRD body's default). The validator MUST reject absolute paths in `fixture_corpus_path:`. Encoded in **FR-003** explicitly.
- **OQ-5 (Auto-emit GitHub issue on gate-fail)**: DEFERRED to post-phase work. V1: per-axis report on stdout + halted PR creation is sufficient. No FR.

## Baseline rationale (§1.5 Baseline Checkpoint — SKIPPED)

The team-lead's launch prompt directed the specifier to skip the baseline-checkpoint substep. Verified against the PRD body:

- **NFR-001 (Backward compat)**: byte-identity assertion ("validate and propagate cleanly"). No numeric perf budget.
- **NFR-002 (Routing default-safety)**: byte-identity assertion ("byte-identically to pre-research-first PRD"). No numeric perf budget. Reference is the current pre-PR pipeline structure on a no-research-block PRD.
- **NFR-003 (Distill determinism)**: byte-identity assertion ("byte-identical research-block content" on re-run with unchanged inputs). No numeric perf budget.
- **NFR-005 (Pre-research-first byte-compat)**: byte-identity assertion ("byte-identical to pre-research-first distill output" on no-research-block backlog). The FR-008 fallback IS the determinism hook.
- **NFR-006 (Classifier false-positive recovery)**: structural assertion ("the field doesn't exist" not "the field exists but is null"). No numeric perf budget.

No PRD requirement implies a latency target. Baseline measurement is therefore unnecessary; the existing pre-PR distill output (and existing pre-PR build-prd pipeline structure) serve as the byte-identity reference by construction. A `git diff` of the post-merge against pre-merge artifacts on a no-research-block PRD IS the verification surface.

**Documented per team-lead instruction**: "baseline-checkpoint skipped: byte-identity NFRs do not require numeric baseline; reference is current pre-PR distill output."

## Clarifications

### Session 2026-04-25
- Q: Should the distill conflict prompt cap at N sources in v1? → A: No cap. Render conflicts grouped by `metric`, one block per metric, all `(source, direction)` pairs visible. (OQ-1 / FR-006 / NFR-004)
- Q: Should the classifier ship with a `research_inference: high-signal-only` config flag? → A: NO in v1. Ship the broad signal set; revisit after first 10 real captures. (OQ-2)
- Q: Where exactly does build-prd READ `needs_research` — at the workflow JSON dispatch level or inside the SKILL.md instruction? → A: SKILL.md instruction. The skill calls `parse-prd-frontmatter.sh` (already shipped — projects `empirical_quality`, extended in this PR with `needs_research` field), branches on the projected `needs_research` value, and dispatches the research-first variant inline. NO new wheel workflow JSON is shipped. (FR-009 / Decision 1)
- Q: When propagating the research block from sources, does distill EMIT the block or COPY it? → A: COPY verbatim — keys appear in the PRD frontmatter character-for-character matching the source declarations (post union-merge for `empirical_quality[]` and post-conflict-resolution for `direction` ambiguities). (FR-005 / FR-007 / NFR-003)
- Q: How does build-prd "auto-route" — does it spawn a different pipeline or branch within the existing one? → A: branches within the existing pipeline. After `/tasks`, the SKILL.md inserts a new "Phase 2.5: research-first variant" stanza that runs ONLY when the projected `needs_research: true`. The skip path (no research block) is structurally a no-op (NFR-002 byte-identity). (FR-009 / FR-010 / Decision 2)
- Q: Where does the classifier inject the research-block proposal into the coached-capture interview? → A: as ONE additional question rendered alongside the existing coached-capture template (`coach-driven-capture-ergonomics` FR-004 §5.0). The proposed answer is the inferred block; the rationale cites the matched signal word verbatim. The §5.0a response parser handles `accept | tweak | reject | skip | accept-all`. (FR-015)
- Q: For the E2E fixture, is the regression scenario a separate fixture file or a flag flipped within one fixture? → A: separate sub-paths within ONE fixture (`run.sh` invokes both `--scenario=happy` and `--scenario=regression`). Each sub-path has its own assertion. Bundled to keep the test cohesive. (FR-018 / FR-019)
- Q: Should the schema validator reject UNKNOWN research-block fields, or pass them through? → A: warn-but-pass — unknown fields under the research block are surfaced as a non-blocking warning on stderr (`Warning: unknown research-block field: <key>`) but do not fail validation. Known-but-malformed values DO fail loudly per NFR-007 from the plan-time-agents PR. (FR-001 / NFR-001)
- Q: Does the build-prd auto-routing apply to `--quick` mode or is it bypassed? → A: applies to all modes. `--quick` does NOT skip research-first routing. Maintainer who wants to bypass research-first explicitly removes `needs_research: true` from PRD frontmatter — there is no flag-level bypass per PRD §Non-Goals "Routing on flags". (FR-009)

## User Scenarios & Testing

### User Story 1 — Capture an idea with classifier inference (Priority: P1)

**As a maintainer capturing a comparative-improvement idea**, I run `/kiln:kiln-roadmap "make claude-md-audit cheaper"`. The classifier detects "cheaper", proposes `needs_research: true, empirical_quality: [{metric: tokens, direction: lower, priority: primary}, {metric: cost, direction: lower, priority: primary}]`, cites "matched signal word: cheaper". I accept. The roadmap item lands at `.kiln/roadmap/items/<date>-claude-md-audit-cheaper.md` with the research block in frontmatter. The validator passes.

**Acceptance Scenarios**:
1. **Given** a description containing the literal word `cheaper`, **When** `classify-description.sh --infer-research` runs, **Then** stdout JSON includes `{ "research_inference": { "needs_research": true, "matched_signals": ["cheaper"], "proposed_axes": [{"metric": "cost", "direction": "lower", "priority": "primary"}, {"metric": "tokens", "direction": "lower", "priority": "primary"}] } }` (FR-013, FR-014)
2. **Given** the coached-capture interview with a "cheaper" description, **When** the interview reaches the research-block question, **Then** the rendered question matches the §5.0 template — Q line, Proposed line, Why line citing the matched signal word verbatim, accept/tweak/reject/skip/accept-all menu — and the `tweak` path lets the maintainer edit any field (axes, direction, priority) before commit. (FR-015)
3. **Given** the maintainer accepts the proposal, **When** the item file is written, **Then** the frontmatter contains `needs_research: true` plus the proposed `empirical_quality:` block, AND the item validator at `validate-item-frontmatter.sh` exits ok. (FR-001, FR-014, FR-015)
4. **Given** the maintainer rejects the proposal, **When** the item file is written, **Then** the frontmatter contains NO research-block keys at all (not `needs_research: false`, not an empty `empirical_quality: []`). False-positive recovery is "the field doesn't exist." (FR-015, NFR-006)
5. **Given** a description containing `clearer error messages`, **When** the classifier runs, **Then** the proposed block includes `metric: output_quality, direction: equal_or_better` AND the rationale line includes the verbatim warning: "(`output_quality` enables the judge-agent — see `2026-04-24-research-first-output-quality-judge.md` for drift-risk caveats)". (FR-014, FR-016)

### User Story 2 — Distill propagation with multi-source axes (Priority: P1)

**As a maintainer running `/kiln:kiln-distill`**, I bundle two roadmap items + one issue into a PRD. Item A declares `needs_research: true` with `metric: tokens, direction: lower`. Item B declares `needs_research: true` with `metric: time, direction: lower`. The issue does not declare research. Distill propagates the union (`tokens` + `time`, both `lower`) into PRD frontmatter sorted alphabetically by metric.

**Acceptance Scenarios**:
1. **Given** two items declaring distinct axes (`tokens` + `time`) with same direction-semantics, **When** distill runs, **Then** the generated PRD frontmatter contains `needs_research: true` AND `empirical_quality:` is the union of both items' axes (deduplicated by `metric`), sorted ASC by `metric` then `direction` (FR-005, FR-008, NFR-003).
2. **Given** two items declaring the SAME `metric` with DIFFERENT `direction` (item A: `metric: tokens, direction: lower`; item B: `metric: tokens, direction: equal_or_better`), **When** distill runs, **Then** distill HALTS BEFORE writing the PRD with stdout containing both source paths AND both `(metric, direction)` pairs verbatim AND a prompt asking the user to pick one direction or specify a third. The output MUST match the NFR-004 "good shape": `<source-path-A> declares <metric>:<direction-A> but <source-path-B> declares <metric>:<direction-B>. Pick one direction or specify a third.` (FR-006, NFR-004)
3. **Given** NO selected source declares `needs_research: true`, **When** distill runs, **Then** the generated PRD frontmatter is BYTE-IDENTICAL to pre-PR distill output (three keys only: `derived_from`, `distilled_date`, `theme`). FR-008 + NFR-005 byte-identity verified by checksum diff against an unchanged-input baseline. (FR-008, NFR-005)
4. **Given** ONE source declares `fixture_corpus: declared` + `fixture_corpus_path: plugin-kiln/tests/.../fixtures/`, **When** distill runs, **Then** both keys propagate into PRD frontmatter VERBATIM (no synthesis, no normalization). Same for `promote_synthesized:` and `excluded_fixtures[]`. (FR-007)
5. **Given** the same source set as scenario 1, **When** distill runs twice with no input changes between runs, **Then** the second run's PRD frontmatter is BYTE-IDENTICAL to the first run's (NFR-003 determinism hook on axis ordering). (NFR-003)

### User Story 3 — Build-prd auto-routing on PRD frontmatter (Priority: P1)

**As a maintainer running `/kiln:kiln-build-prd`**, I run it against a PRD declaring `needs_research: true`. The skill auto-routes to the research-first variant — establishes a baseline against the corpus, implements the candidate in a worktree, measures the candidate, applies the per-axis gate, and (only if every axis passes) proceeds to audit + PR with the research report attached.

**Acceptance Scenarios**:
1. **Given** a PRD with `needs_research: true` + a declared corpus, **When** `/kiln:kiln-build-prd` runs, **Then** the SKILL.md execution path includes a NEW "Phase 2.5: research-first variant" stanza between `/tasks` and `/implement` that runs `establish-baseline → implement-in-worktree → measure-candidate → gate` per FR-010. (FR-009, FR-010)
2. **Given** a PRD WITHOUT `needs_research: true`, **When** `/kiln:kiln-build-prd` runs, **Then** the Phase 2.5 stanza is structurally a no-op (single jq lookup on already-parsed frontmatter JSON, returns immediately) AND the rest of the pipeline runs byte-identically to pre-PR behavior. (FR-009, NFR-002)
3. **Given** the gate detects a regression on at least one fixture × axis pair, **When** the variant phase completes, **Then** the pipeline HALTS BEFORE PR creation, surfaces the per-axis report verbatim (fixture-by-fixture, axis-by-axis), and the PR is NOT created. The exit path matches `evaluate-direction.sh` and `evaluate-output-quality.sh` `regression` stdout contracts from the foundation + plan-time-agents PRs. (FR-011)
4. **Given** the gate passes on all fixtures × axes, **When** the auditor runs, **Then** the auditor's PR body includes a `## Research Results` heading with a per-axis pass-status table beneath it AND a link to `.kiln/logs/research-<uuid>.md`. (FR-012)

### User Story 4 — End-to-end phase-complete fixture (Priority: P1)

**As a maintainer closing phase 09-research-first**, I run the E2E fixture at `plugin-kiln/tests/research-first-e2e/run.sh`. The fixture scaffolds a temp-dir test repo, exercises the full happy path (research-needing roadmap item → distill → build-prd → gate-pass → PR-creation), then resets the temp dir and exercises the regression path (same setup but with a deliberately-regressing candidate → gate-fail → no PR). Both sub-paths exit 0; their PASS lines appear in the test log.

**Acceptance Scenarios**:
1. **Given** an empty temp dir, **When** `bash plugin-kiln/tests/research-first-e2e/run.sh` is invoked, **Then** the fixture scaffolds a mocked `kiln-init` test repo, creates a roadmap item declaring `needs_research: true`, runs `/kiln:kiln-distill`, and asserts the generated PRD frontmatter inherits the research block with `needs_research: true`. (FR-017)
2. **Given** the same fixture continuing past distill, **When** the happy-path candidate runs, **Then** `/kiln:kiln-build-prd` invokes the research-first variant, the gate evaluates every axis, no axis regresses, and the pipeline proceeds to PR creation with the research report attached. (FR-018 happy path)
3. **Given** the regression sub-path runs (same setup, different candidate), **When** the deliberately-regressing candidate is measured, **Then** the gate detects the regression on at least one axis × fixture, the pipeline HALTS BEFORE PR creation, and the gate-fail report is surfaced naming the regressing axis + fixture. (FR-018 regression path — load-bearing)
4. **Given** both sub-paths complete, **When** the fixture's last line is read, **Then** it includes the literal token `PASS` AND the exit code is 0. The regression sub-path's intermediate output MUST contain the literal token `gate fail` to confirm the negative-case assertion fired. (FR-019, SC-005)
5. **Given** the E2E fixture ships in this PR, **When** `/kiln:kiln-test plugin-kiln research-first-e2e` is invoked from any consumer repo (per the substrate-hierarchy rule from issue #181 PI-2), **Then** the fixture runs to completion and exits 0. PASS-cite fallback: if the harness can't run the fixture in-substrate, `bash plugin-kiln/tests/research-first-e2e/run.sh` is the canonical evidence path. (FR-019)

### Edge Cases

- **Conflicting `direction` across 4+ sources** — distill MUST render all conflicting `(source, direction)` pairs grouped by `metric`, one block per metric. NO truncation, NO "and 3 more". Maintainer scrolls. (NFR-004 — confirmed via OQ-1 resolution.)
- **Schema field on a kind=goal item that doesn't make sense (e.g., `fixture_corpus`)** — validator passes (warn-but-pass per OQ); first-real-use evidence drives any future tightening. The research-block fields are scoped at the artifact level, not the kind level. (FR-001, NFR-001)
- **Maintainer types `tweak` in classifier interview but provides invalid axis (e.g., `metric: foo`)** — the §5.0a response parser surfaces an error per the existing coached-capture contract; the interview re-prompts. NOT a research-first specific path; inherited from coach-driven-capture. (FR-015)
- **PRD frontmatter has `needs_research: true` but ZERO declared axes (`empirical_quality: []`)** — the build-prd routing still triggers (per FR-009 — `needs_research: true` is the gate, not axis presence), but the gate has nothing to evaluate. The variant pipeline MUST surface a clear error: `Bail out! research-first-routed-but-no-axes: <prd-path>`. Validator at FR-001 SHOULD warn at write-time too. (FR-009, FR-001 warn-but-pass)
- **Distill propagates a `fixture_corpus_path:` that doesn't exist on disk** — distill propagates verbatim per FR-007; validation of path existence is build-prd's responsibility (corpus-load step in `establish-baseline`). Distill MUST NOT silently substitute `fixture_corpus: synthesized`. (FR-007 verbatim)
- **Classifier matches "cheaper" in a non-comparative sentence (e.g., "this should be cheaper to ship")** — false-positive; maintainer rejects; recovery is "no research-block frontmatter" per NFR-006. ACCEPTABLE per the PRD's "low-stakes inference" rationale.
- **Build-prd run on a PRD that has `needs_research: true` but no `fixture_corpus:` declared at all** — variant pipeline MUST bail at the corpus-load step with `Bail out! research-first-routed-but-no-corpus: <prd-path>`. The corpus declaration is required when routing is active. (FR-009, FR-010 corpus-load step)
- **E2E fixture run on a system without the `claude` CLI** — the fixture MOCKS the LLM-spawning steps (per CLAUDE.md Rule 5 — newly-shipped agents not live-spawnable in same session). The orchestrator-side determinism is what's tested, not live LLM behaviour. (FR-019)
- **PRD `derived_from:` includes a raw `.kiln/issues/` path that hasn't been promoted** — the un-promoted gate from `workflow-governance` already catches this in distill (Step 0.5). This PR does NOT alter the un-promoted gate. (Out of scope; mentioned for clarity.)

## Requirements

### Functional Requirements

#### Theme: schema extensions + distill propagation (FR-001 — FR-008)

**FR-001 (from PRD FR-001 / `.kiln/roadmap/items/2026-04-24-research-first-build-prd-wiring.md`)**: Extend `plugin-kiln/scripts/roadmap/validate-item-frontmatter.sh` to accept (additively) the optional research-block fields: `needs_research: bool`, `empirical_quality: [{metric, direction, priority}]`, `fixture_corpus: enum(synthesized|declared|promoted)`, `fixture_corpus_path: string`, `promote_synthesized: bool`, `excluded_fixtures: [{path, reason}]`. All fields default-off — absence preserves existing behavior. Unknown research-block keys are warn-but-pass (`Warning: unknown research-block field: <key>` to stderr) per the OQ resolution. Known-but-malformed values fail loudly per NFR-007 of plan-time-agents (carried forward — e.g., `metric: foo` exits non-zero with a clear bail message).

**FR-002 (from PRD FR-002)**: Extend (or create) the issue-frontmatter validator at `plugin-kiln/scripts/roadmap/validate-item-frontmatter.sh`-style sibling for `.kiln/issues/*.md`, AND the feedback-frontmatter validator for `.kiln/feedback/*.md`. If neither sibling currently exists, create one new validator script that handles both surfaces (`plugin-kiln/scripts/issues-feedback/validate-frontmatter.sh`) — same additive shape as FR-001. The plan.md MUST document which path the implementer chose; spec.md does NOT mandate one over the other. Wire the new validator into the existing `/kiln:kiln-report-issue` and `/kiln:kiln-feedback` skill flows so write-time validation fires. If — on inspection — the existing surfaces have NO write-time validator at all, the implementer MAY document this as a known gap in `specs/research-first-completion/blockers.md` rather than create a brand-new validator (the plan.md must still document the choice and the rationale).

**FR-003 (from PRD FR-003)**: Validation rules for the research block (uniform across all four schemas):
  - `empirical_quality[]` requires `metric ∈ {accuracy, tokens, time, cost, output_quality}` per entry; `direction ∈ {lower, higher, equal_or_better}` per entry; `priority` defaults to `secondary` if omitted.
  - `metric: output_quality` requires non-empty `rubric: <string>` per the FR-010 carried-forward rule from `specs/research-first-plan-time-agents/spec.md` (already shipped in `parse-prd-frontmatter.sh`).
  - `fixture_corpus_path:` is REQUIRED when `fixture_corpus: declared` OR `fixture_corpus: promoted`; FORBIDDEN when `fixture_corpus: synthesized`; absent otherwise.
  - `fixture_corpus_path:` MUST be repo-relative; absolute paths fail validation with `Bail out! fixture-corpus-path-must-be-relative: <path>` (OQ-4 resolution).
  - `excluded_fixtures[]` requires `path: <string>` AND `reason: <string>` per entry.
  - `needs_research: false` is permitted but discouraged (the validator emits `Warning: needs_research:false is the default — omit the key` to stderr).

**FR-004 (from PRD FR-004)**: Extend the PRD frontmatter contract (`prd-derived-from-frontmatter` spec) to permit the same set of optional research-block keys AFTER the existing three keys. Authoritative key order in PRD frontmatter:
```
derived_from
distilled_date
theme
needs_research
empirical_quality
fixture_corpus
fixture_corpus_path
promote_synthesized
excluded_fixtures
```
PRDs without the research block still parse cleanly. The existing `prd-derived-from-frontmatter` validator is extended additively to recognize the new keys (no shape change to its existing exit codes for pre-research-first PRDs).

**FR-005 (from PRD FR-005)**: `/kiln:kiln-distill` propagation — when ANY selected source (feedback / item / issue) declares `needs_research: true`, the generated PRD inherits `needs_research: true`. The PRD's `empirical_quality[]` is the SET-UNION of axes declared across all selected sources, deduplicated by `metric`. Order is canonical: ASC by `metric`, ties break on `direction` ASC (NFR-003 determinism hook). When deduplicating two entries with the same `metric` AND same `direction` but different `priority` (e.g., one `primary`, one `secondary`), the merged entry takes the highest-priority value (`primary > secondary`).

**FR-006 (from PRD FR-006 / NFR-004)**: Conflict resolution — if two or more selected sources declare the SAME `metric` with DIFFERENT `direction` values, distill MUST surface a confirm-never-silent ambiguity prompt. Output shape (NFR-004 verbatim contract):
```
Conflict on metric: <metric>
  <source-path-A> declares direction: <direction-A>
  <source-path-B> declares direction: <direction-B>
  [<source-path-C> declares direction: <direction-C>]
  ...
Pick one direction or specify a third.
> _
```
Distill MUST NOT silently merge or pick a winner. The user picks one of the listed `direction` values OR types a fresh value (validated against the `ALLOWED_DIR` enum). Multiple conflicting metrics produce one block per metric. NO cap on N (OQ-1). Distill exits non-zero (exit 2) without writing the PRD if the user types `abandon` or sends EOF; otherwise distill resumes with the resolved direction(s).

**FR-007 (from PRD FR-007)**: `/kiln:kiln-distill` propagates `fixture_corpus`, `fixture_corpus_path`, `promote_synthesized`, and `excluded_fixtures[]` from the union of source artifacts into the PRD frontmatter VERBATIM (no synthesis, no inference, no normalization). When two or more sources declare DIFFERENT values for the same scalar key (e.g., source A says `fixture_corpus: synthesized`, source B says `fixture_corpus: declared`), distill MUST surface a confirm-never-silent ambiguity prompt of the same shape as FR-006. List-keyed values (`excluded_fixtures[]`) are union-merged on `path`; deduplicated entries with same `path` but different `reason` trigger the same ambiguity prompt.

**FR-008 (from PRD FR-008)**: When NO selected source declares `needs_research: true`, distill emits the PRD frontmatter unchanged from current behavior (three keys: `derived_from`, `distilled_date`, `theme`). BYTE-IDENTICAL to pre-research-first distill output (NFR-005). The fallback path is exercised by an existing-PR distill re-run that produces zero diff against the committed PRD frontmatter on `main`.

#### Theme: build-prd routing (FR-009 — FR-012)

**FR-009 (from PRD FR-009)**: `/kiln:kiln-build-prd` SKILL.md MUST read PRD frontmatter on entry — by invoking `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh` (extended in this PR additively to project the new `needs_research:`, `fixture_corpus:`, `fixture_corpus_path:`, `promote_synthesized:` fields alongside the existing `empirical_quality[]`, `blast_radius`, `excluded_fixtures[]` projections). On `needs_research: true`, route to the research-first variant. Otherwise, route to the existing standard pipeline. Routing is unconditional on PRD frontmatter — no flag-level bypass (per PRD §Non-Goals).

**FR-010 (from PRD FR-010)**: The research-first variant pipeline executes these steps in order between `/tasks` and `/implement` (inserted as Phase 2.5 in `/kiln:kiln-build-prd` SKILL.md):
  - **establish-baseline** — runs the baseline plugin-dir against the declared corpus (`fixture_corpus: declared|promoted`) OR the synthesizer's accepted output (`fixture_corpus: synthesized`); captures metrics via the foundation runner at `plugin-wheel/scripts/harness/research-runner.sh`.
  - **implement-in-worktree** — runs `/implement` in an isolated worktree (Decision 4 in plan.md will document the worktree-isolation mechanism).
  - **measure-candidate** — runs the candidate plugin-dir against the SAME corpus.
  - **gate** — applies the per-axis direction enforcement from `specs/research-first-axis-enrichment/contracts/interfaces.md §4` (`evaluate-direction.sh`) AND for `output_quality` axis the orchestrator at `specs/research-first-plan-time-agents/contracts/interfaces.md §4` (`evaluate-output-quality.sh`).
  - **continue to audit → PR** — only if every axis passes on every non-control fixture.

**FR-011 (from PRD FR-011)**: On gate fail, the research-first variant HALTS the pipeline. Surface (stdout, verbatim from gate output): the per-axis report — fixture-by-fixture, axis-by-axis. The PR is NOT created. The maintainer sees what regressed and can revise the candidate. Specifically: the variant SKILL.md prose MUST explicitly forbid spawning the auditor + PR-creator agents on the gate-fail path; the SKILL emits a clear `Bail out! research-first-gate-failed: <prd-slug>` banner plus the verbatim per-axis report.

**FR-012 (from PRD FR-012)**: On gate pass, the auditor's PR body MUST include the research report path (`.kiln/logs/research-<uuid>.md` per foundation precedent) AND a `## Research Results` heading with a per-axis pass-status table. Table shape (markdown):
```
| metric | direction | priority | verdict |
|--------|-----------|----------|---------|
| tokens | lower | primary | pass (-22% mean across 12 fixtures) |
| time | lower | secondary | pass (no regression) |
| output_quality | equal_or_better | primary | pass (5/5 candidate_better) |
```
The auditor reads the per-axis verdict file emitted by the gate at `.kiln/research/<prd-slug>/per-axis-verdicts.json` (already shipped per foundation; this PR does not modify its shape).

#### Theme: classifier inference (FR-013 — FR-016)

**FR-013 (from PRD FR-013)**: Extend `plugin-kiln/scripts/roadmap/classify-description.sh` with a sibling subcommand or stdout key `--infer-research` (or equivalent) that returns a research-block proposal when comparative-improvement signal words match the description. Word list (case-insensitive whole-word match):
```
faster, slower, cheaper, more expensive, reduce, increase,
optimize, efficient, compare to, versus, vs , better than,
regression, improve, degradation
```
Match semantics: case-insensitive; whole-word boundaries; spaces in `compare to` / `more expensive` / `better than` / `vs ` are matched literally with surrounding whitespace.

**FR-014 (from PRD FR-014)**: When a signal word matches, the classifier emits a research-block proposal with axes inferred from the signal:
  - `faster | slower | latency` → `metric: time, direction: lower`
  - `cheaper | tokens | cost | "more expensive" | expensive` → BOTH `metric: cost, direction: lower` AND `metric: tokens, direction: lower`
  - `smaller | concise | verbose` → `metric: tokens, direction: lower`
  - `accurate | wrong | regression` → `metric: accuracy, direction: equal_or_better`
  - `clearer | better-structured | "more actionable"` → `metric: output_quality, direction: equal_or_better` (with judge-drift warning per FR-016)
  - `compare to | versus | "vs " | "better than" | improve | optimize | efficient | degradation | reduce | increase` → no axis-inference; emit `needs_research: true` only with rationale "matched signal word: <word>"; the maintainer is expected to declare axes via `tweak`.

The classifier output JSON shape (extends the existing `classify-description.sh` JSON):
```json
{
  "surface": "roadmap",
  "kind": "feature",
  "confidence": "high",
  "alternatives": [],
  "research_inference": {
    "needs_research": true,
    "matched_signals": ["cheaper"],
    "proposed_axes": [
      {"metric": "cost", "direction": "lower", "priority": "primary"},
      {"metric": "tokens", "direction": "lower", "priority": "primary"}
    ],
    "rationale": "matched signal word: cheaper"
  }
}
```
When NO signal word matches, the `research_inference` key is OMITTED entirely (NOT `null`, NOT an empty object — false-negative recovery is structural, matching NFR-006's structural-absence pattern for false-positives).

**FR-015 (from PRD FR-015)**: The coached-capture interview (e.g., `/kiln:kiln-roadmap`, `/kiln:kiln-report-issue`, `/kiln:kiln-feedback`) renders the inferred research block as a SINGLE accept/tweak/reject question following the existing coached-capture template (`coach-driven-capture-ergonomics` FR-004 §5.0). The proposed answer is the inferred block; the rationale cites the matched signal word verbatim. User input is parsed per the existing §5.0a response parser (`accept | tweak <value> | reject | skip | accept-all`). On `tweak`, the maintainer can edit any field (axes, direction, priority, fixture_corpus, etc.); on `reject`, NO research-block frontmatter is written (NFR-006). On `accept-all`, the proposal is committed unchanged AND every subsequent question in the interview is auto-accepted with its proposed default — matching the existing accept-all semantics.

**FR-016 (from PRD FR-016)**: When the inferred axis set includes `output_quality`, the rationale line in the FR-015 question MUST include this verbatim warning on its own line:
```
(`output_quality` enables the judge-agent — see `2026-04-24-research-first-output-quality-judge.md` for drift-risk caveats)
```
Maintainer can still accept; the warning is informational. The literal warning string is asserted by a CI lint check `plugin-kiln/scripts/research/lint-classifier-output-quality-warning.sh` that greps the classifier output for the verbatim string when `output_quality` is in the proposed axes.

#### Theme: phase-complete E2E test (FR-017 — FR-020)

**FR-017 (from PRD FR-017)**: A faked-test fixture under `plugin-kiln/tests/research-first-e2e/` MUST exercise the full research-first workflow end-to-end. The fixture:
  - (a) scaffolds a temp-dir test repo with mocked `kiln-init` (copies a minimal `.kiln/`, `plugin-kiln/`, `plugin-wheel/` subset into a `mktemp -d` directory).
  - (b) creates a roadmap item declaring `needs_research: true` with at least one `empirical_quality[]` axis (`metric: tokens, direction: lower` is the minimal viable axis).
  - (c) runs `/kiln:kiln-distill` (via direct script invocation OR a mocked SKILL.md execution path — implementer's choice, document in `run.sh`) and asserts the generated PRD frontmatter contains the propagated research block.
  - (d) runs `/kiln:kiln-build-prd` (via direct script invocation OR mocked SKILL.md) and asserts the research-first variant is invoked (greppable on stdout for "research-first variant" or equivalent verbatim banner).

**FR-018 (from PRD FR-018)**: The E2E fixture MUST exercise BOTH paths in a single `run.sh` invocation:
  - **Happy path** (`run.sh --scenario=happy` OR runs first by default): a candidate that holds-the-line on every declared axis. Assertion: pipeline proceeds past the gate, audit step is invoked, PR-creation step is invoked (mocked — no real GitHub PR). Research report path is asserted to exist at `.kiln/logs/research-<uuid>.md` within the temp-dir test repo.
  - **Regression path** (`run.sh --scenario=regression` OR runs second): a candidate deliberately worse on at least one axis. Assertion: pipeline HALTS BEFORE PR creation, gate-fail report appears on stdout naming the regressing axis + fixture, the literal token `gate fail` is greppable in the test log.

Without both, the phase has only proven the happy path. The regression case is the load-bearing assertion. Both sub-paths run within ONE `run.sh` invocation (per Clarification answer); each sub-path resets the temp dir between runs to ensure isolation.

**FR-019 (from PRD FR-019)**: The E2E fixture MUST be wired into the `/kiln:kiln-test` harness AND runnable directly:
  - `/kiln:kiln-test plugin-kiln research-first-e2e` exits 0 with PASS.
  - `bash plugin-kiln/tests/research-first-e2e/run.sh` exits 0 with the literal token `PASS` on its last line.

The PASS-cite fallback (per the substrate-hierarchy rule from issue #181 PI-2) means the direct-invocation path is the canonical evidence for SC-005 even if the harness wiring is imperfect. The test fixture MUST be self-contained (no external network, no real GitHub API calls); all spawning is mocked per CLAUDE.md Rule 5.

**FR-020 (from PRD FR-020)**: Phase-complete declaration — only after BOTH paths in the E2E fixture pass AND a follow-up commit flips the phase 09-research-first item-statuses from `state: in-phase` (or current) to `status: shipped` (per the auto-flip-on-merge gap captured in `.kiln/issues/2026-04-25-build-prd-no-auto-flip-item-state-on-merge.md`), the maintainer MAY run `/kiln:kiln-roadmap --phase complete 09-research-first`. This PR does NOT auto-flip the item statuses (that work belongs to the open auto-flip issue); it ONLY ships the E2E fixture + the FR-017..FR-019 evidence. The plan.md MUST document this hand-off explicitly.

### Non-Functional Requirements

**NFR-001 (Backward compatibility — schema)**: Every existing artifact (item, issue, feedback, PRD) without the new research-block fields MUST continue to validate cleanly. Validators are additive; missing-field tolerance is the default. NO existing PRD under `docs/features/` requires editing for this PRD to ship. Verified by re-running the existing validators against every committed artifact in the repo and asserting zero new failures.

**NFR-002 (Routing default-safety — byte-identity)**: PRDs without `needs_research: true` route through the existing `/kiln:kiln-build-prd` pipeline byte-identically. The Phase 2.5 stanza is structurally a no-op on the skip path: a single jq lookup on already-parsed frontmatter JSON. Smoke-test fixture: pre-research-first PRD shipped before this PR (e.g., `docs/features/2026-04-25-research-first-foundation/PRD.md`) + post-merge re-run produces the same pipeline structure (asserted via diff of the SKILL.md execution log against a captured pre-PR baseline log).

**NFR-003 (Distill determinism)**: When ANY source declares `needs_research: true`, the propagated PRD frontmatter is deterministic — re-running distill on unchanged inputs produces byte-identical research-block content. Axis ordering is stable: `metric` ASC alphabetical (using `LC_ALL=C sort`), ties break on `direction` ASC. List-keyed values (`excluded_fixtures[]`) are sorted ASC by `path`.

**NFR-004 (Conflict-prompt clarity)**: The FR-006 conflict prompt MUST name both source paths AND the conflicting `(metric, direction)` pairs. Bad shape: "axes conflict, please resolve." Good shape: "feedback `2026-04-15-foo.md` declares `metric: tokens, direction: lower` but item `2026-04-20-bar.md` declares `metric: tokens, direction: equal_or_better`. Pick one direction or specify a third." See FR-006 verbatim contract.

**NFR-005 (Pre-research-first byte-compat — distill)**: Distill of a backlog where NO source declares `needs_research: true` produces frontmatter byte-identical to pre-research-first distill output. The FR-008 fallback IS the determinism hook. Verified by checksum diff of regenerated PRD frontmatter against a pre-PR snapshot for at least one already-shipped PRD with no research block.

**NFR-006 (Classifier false-positive recovery)**: A maintainer rejecting the inferred research-block proposal MUST result in the captured artifact having NO research-block frontmatter (not "research block with all fields empty"). False-positive recovery is "the field doesn't exist," not "the field exists but is null." Tested via `plugin-kiln/tests/classifier-research-rejection-recovery/`.

**NFR-007 (Loud-failure validators)**: Every validator extension is loud-failure on malformed values per the carried-forward NFR-007 from `specs/research-first-plan-time-agents/spec.md`. NEVER silently fall back to a hardcoded default. Unknown-but-research-block-shaped keys are warn-but-pass per the OQ resolution; known-but-malformed values exit non-zero with `Bail out! <reason>` to stderr.

**NFR-008 (E2E fixture self-containment)**: The `research-first-e2e` fixture MUST be self-contained — no external network, no real GitHub API calls, no real `claude` CLI invocations against live LLMs. All spawning is mocked per CLAUDE.md Rule 5. The fixture's runtime budget is ≤ 30s on a developer macOS machine (no numeric perf gate beyond this informational ceiling).

**NFR-009 (Foundation invariants preserved)**: This PR does NOT modify any of the foundation-untouchable files listed in `specs/research-first-foundation/plan.md` and `specs/research-first-axis-enrichment/plan.md`. Specifically:
  - `plugin-wheel/scripts/harness/research-runner.sh` — UNTOUCHED.
  - `plugin-wheel/scripts/harness/parse-token-usage.sh` — UNTOUCHED.
  - `plugin-wheel/scripts/harness/render-research-report.sh` — UNTOUCHED (no new columns).
  - `plugin-wheel/scripts/harness/evaluate-direction.sh` — UNTOUCHED.
  - `plugin-wheel/scripts/harness/evaluate-output-quality.sh` — UNTOUCHED (already shipped per plan-time-agents PR).
  - `plugin-wheel/scripts/harness/compute-cost-usd.sh` — UNTOUCHED.
  - `plugin-wheel/scripts/harness/resolve-monotonic-clock.sh` — UNTOUCHED.
  - `plugin-kiln/lib/research-rigor.json` — UNTOUCHED.
  - `plugin-kiln/lib/pricing.json` — UNTOUCHED.
  - `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh` — extended ADDITIVELY ONLY (new field projections; existing field projections + exit codes UNCHANGED). The extension is the same kind of additive change the plan-time-agents PR shipped (adding `rubric:` validator).

## Assumptions

- **A-001 (composer + resolver shipped)**: `plugin-wheel/scripts/agents/compose-context.sh` + `resolve.sh` shipped per `build/agent-prompt-composition-20260425`. Used unchanged for any agent spawns from build-prd's research-first variant. (The variant reuses the existing implementer-spawn pattern; no new agent is registered in this PR.)
- **A-002 (axis-enrichment frontmatter parser shipped)**: `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh` shipped per PR #178 + extended per PR #182. This PR adds three more field projections (`needs_research`, `fixture_corpus`, `fixture_corpus_path`, `promote_synthesized`) but does NOT change existing field projections or exit codes.
- **A-003 (foundation runner shipped)**: `plugin-wheel/scripts/harness/research-runner.sh` and the per-axis gate (`evaluate-direction.sh`, `evaluate-output-quality.sh`) shipped per PRs #176 + #178 + #182. This PR consumes them via the build-prd variant pipeline; they are NOT modified.
- **A-004 (auto-flip-on-merge is post-PR work)**: The `state: shipped` flip on phase-09 items belongs to the `2026-04-25-build-prd-no-auto-flip-item-state-on-merge` issue. This PR ships the E2E fixture + the FR-017..FR-019 gate; the maintainer manually flips item statuses per FR-020.
- **A-005 (un-promoted gate is shipped)**: `/kiln:kiln-distill` Step 0.5 un-promoted gate from `workflow-governance` is shipped. This PR does NOT alter it; PRDs with un-promoted raw `derived_from:` are refused per existing behavior (orthogonal to research-first changes).
- **A-006 (existing capture surfaces have a coached-capture interview)**: `/kiln:kiln-roadmap`, `/kiln:kiln-report-issue`, `/kiln:kiln-feedback` each have a coached-capture interview that follows the §5.0 template from `coach-driven-capture-ergonomics`. The classifier inference attaches to that interview as ONE additional question, NOT a separate flow.
- **A-007 (worktree mechanism is plan.md's choice)**: The `implement-in-worktree` step in FR-010 has multiple plausible implementations (git worktree, isolated tempdir copy, etc.). The plan.md is responsible for picking one; the spec does NOT mandate a mechanism. Implementer must respect Article VI (small focused changes).

## Success Criteria

- **SC-001**: A backlog item or issue captured via `/kiln:kiln-roadmap` or `/kiln:kiln-report-issue` containing the word "cheaper" or "faster" produces a coached-capture proposal with `needs_research: true` and at least one matching axis. Verified by `plugin-kiln/tests/classifier-research-inference/`.

- **SC-002**: `/kiln:kiln-distill` against a backlog where one item declares `needs_research: true` produces a PRD whose frontmatter contains the propagated research block (matches the union semantics of FR-005 + FR-007). Verified by `plugin-kiln/tests/distill-research-block-propagation/`.

- **SC-003**: `/kiln:kiln-build-prd` on a PRD with `needs_research: true` invokes the research-first variant pipeline. Verified by `plugin-kiln/tests/build-prd-research-routing/` asserting the variant banner appears on stdout when the SKILL.md is executed against a fixture PRD.

- **SC-004**: `/kiln:kiln-build-prd` on a PRD without `needs_research: true` invokes the standard pipeline byte-identically to pre-research-first behavior (NFR-002). Verified by `plugin-kiln/tests/build-prd-standard-routing-bytecompat/` diffing the SKILL.md execution log against a captured pre-PR baseline.

- **SC-005 (load-bearing — phase-complete gate)**: The E2E fixture at `plugin-kiln/tests/research-first-e2e/` exercises both happy and regression paths in ONE `run.sh` invocation and exits 0. Direct evidence: `bash plugin-kiln/tests/research-first-e2e/run.sh` last line includes `PASS` and exit 0; the regression sub-path produces the literal token `gate fail` in the test log. This success criterion is the load-bearing assertion for closing phase 09-research-first.

- **SC-006 (FR-006 enforcement)**: The conflict prompt MUST fire when two sources declare conflicting `direction` for the same `metric`. Verified by `plugin-kiln/tests/distill-axis-conflict-prompt/` asserting the prompt text contains both source paths AND both `direction` values, AND that distill exits non-zero without writing the PRD on `abandon` input.

- **SC-007 (NFR-003 determinism)**: Re-distill against the same conflict-free backlog produces byte-identical PRD frontmatter. Verified by `plugin-kiln/tests/distill-research-block-determinism/` running distill twice and asserting `cmp` returns 0 between the two outputs.

- **SC-008 (NFR-006 false-positive recovery)**: A `reject` response in the coached-capture research-block question results in NO research-block frontmatter being written (structural absence, not empty values). Verified by `plugin-kiln/tests/classifier-research-rejection-recovery/`.

- **SC-009 (FR-001/FR-002/FR-003 schema validators)**: Validator fixtures exercise: (a) every new field on a clean item passes, (b) `metric: foo` fails loudly, (c) absolute `fixture_corpus_path:` fails loudly, (d) unknown research-block field warns-but-passes. Verified by `plugin-kiln/tests/research-block-schema-validation/`.

- **SC-010 (FR-014 axis-inference correctness)**: Each signal-word → axis mapping in the FR-014 table is exercised by at least one fixture; the test asserts the JSON `proposed_axes[]` matches the FR-014 spec exactly. Verified by `plugin-kiln/tests/classifier-axis-inference-mapping/`.

- **SC-011 (FR-016 output_quality warning)**: When the proposed axes include `output_quality`, the rationale string contains the verbatim warning from FR-016. Verified by `plugin-kiln/tests/classifier-output-quality-warning/` AND the lint script `plugin-kiln/scripts/research/lint-classifier-output-quality-warning.sh`.

## Risks & Open Questions

Carried forward from PRD body, refined by clarification session:

- **R-001 — Distill conflict prompt usability** (PRD): mitigated per OQ-1 resolution (no cap, grouped by metric). First-real-use will surface whether the soup is unmanageable; follow-on adds an "accept-all-as-equal_or_better" escape hatch if so.
- **R-002 — Classifier false positives** (PRD): mitigated per NFR-006 (structural-absence recovery on reject). The OQ-2 config flag is deferred; if first 10 captures show > 30% false-positive rate, file follow-on item.
- **R-003 — E2E fixture brittleness** (PRD): the fixture mocks `kiln-init` and scripts the full pipeline. Mitigation: PASS criterion is functional (pipeline halts on regression candidate), not structural ("output exactly matches X"). Rebuild the mock if structure shifts; the assertion stays stable.
- **R-004 — Schema drift across the four intake surfaces**: items / issues / feedback / PRD frontmatter all carry the SAME six fields, but their existing validators are independent scripts. Risk: one diverges from the others on a future PR. **Mitigation**: the implementer SHOULD factor the research-block validation logic into a shared helper (e.g., `plugin-kiln/scripts/research/validate-research-block.sh`) that all four validators call, avoiding duplication. The plan.md MUST commit to one of: (a) shared helper, (b) per-validator inline implementation with a CI lint asserting they all match a canonical reference snippet, (c) document the divergence risk as an accepted ongoing maintenance cost.
- **R-005 — Build-prd routing on a PRD with `needs_research: true` but a missing/invalid `fixture_corpus`**: the variant pipeline MUST bail at the corpus-load step with a clear error (per Edge Cases). The validator at FR-001 SHOULD warn at write-time if `needs_research: true` is declared without `fixture_corpus:`. **Mitigation**: validator stanza in FR-003 emits `Warning: needs_research:true without fixture_corpus — variant pipeline will bail at corpus-load` to stderr.

**Open questions deferred to first-real-use** (not blocking implementation):

- **OQ-1 (resolved in v1)** — distill conflict prompt cap at N. Confirmed NO cap.
- **OQ-2 (resolved in v1)** — classifier high-signal-only config flag. Confirmed deferred.
- **OQ-3 (deferred)** — classifier learns from rejected proposals. Stateless by design in v1.
- **OQ-4 (resolved in v1)** — `fixture_corpus_path:` repo-relative only.
- **OQ-5 (deferred)** — auto-emit GitHub issue on gate-fail. Not in v1.
- **OQ-6 (NEW, deferred)** — should the research-first variant emit a "research-first-skipped: <reason>" log line on the skip path, or remain truly silent (NFR-002 byte-identity)? Defer; v1 is silent on skip per byte-identity invariant. Re-open if maintainers want to audit how often the variant is skipped vs invoked.
- **OQ-7 (NEW, deferred)** — does the classifier propose research for `kiln-fix` invocations (which take a description)? V1: NO — the classifier extension only fires for capture-surface descriptions (`/kiln:kiln-roadmap`, `/kiln:kiln-report-issue`, `/kiln:kiln-feedback`). `/kiln:kiln-fix` is a debug-loop entrypoint, not an idea-capture surface; routing it would conflate concerns. Re-open if first-real-use shows research-needing fixes.

## Dependencies & Inputs

- `specs/research-first-foundation/contracts/interfaces.md` — runner shape (foundation §N).
- `specs/research-first-axis-enrichment/contracts/interfaces.md §3` — `parse-prd-frontmatter.sh` shape (this PRD extends additively with three more field projections).
- `specs/research-first-axis-enrichment/contracts/interfaces.md §4` — `evaluate-direction.sh` contract (consumed unchanged).
- `specs/research-first-plan-time-agents/contracts/interfaces.md §4` — `evaluate-output-quality.sh` contract (consumed unchanged).
- `plugin-kiln/scripts/roadmap/validate-item-frontmatter.sh` — extended additively per FR-001.
- `plugin-kiln/scripts/roadmap/classify-description.sh` — extended additively per FR-013/FR-014.
- `plugin-kiln/skills/kiln-distill/SKILL.md` — extended for FR-005..FR-008 propagation.
- `plugin-kiln/skills/kiln-build-prd/SKILL.md` — extended for FR-009..FR-012 routing (Phase 2.5 stanza).
- `plugin-kiln/skills/kiln-roadmap/SKILL.md` + `kiln-report-issue/SKILL.md` + `kiln-feedback/SKILL.md` — coached-capture interview hooks for FR-015.
- `coach-driven-capture-ergonomics` FR-004 §5.0 + §5.0a — coached-capture template + response parser (consumed unchanged).
- `.specify/memory/constitution.md` — Articles I, VII, VIII (read first; checked in plan.md gate).
