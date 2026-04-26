# Implementation Plan: Research-First Completion — schema + distill + build-prd routing + classifier + E2E gate

**Branch**: `build/research-first-completion-20260425` | **Date**: 2026-04-25 | **Spec**: [spec.md](./spec.md)
**Input**: `specs/research-first-completion/spec.md`
**PRD**: `docs/features/2026-04-26-research-first-completion/PRD.md`
**Foundation dependencies**:
  - `specs/research-first-foundation/{spec.md,plan.md,contracts/interfaces.md}` (PR #176, in main).
  - `specs/research-first-axis-enrichment/{spec.md,plan.md,contracts/interfaces.md}` (PR #178, in main).
  - `specs/research-first-plan-time-agents/{spec.md,plan.md,contracts/interfaces.md}` (PR #182, in main).
  - `plugin-kiln/scripts/roadmap/{validate-item-frontmatter.sh,classify-description.sh,parse-item-frontmatter.sh}` (existing).
  - `plugin-wheel/scripts/harness/{parse-prd-frontmatter.sh,evaluate-direction.sh,evaluate-output-quality.sh,research-runner.sh}` (existing).
**Baseline checkpoint**: SKIPPED — see spec.md §"Baseline rationale". The PRD's NFRs are byte-identity assertions, not numeric perf budgets. Reference baseline IS the current pre-PR distill output + pre-PR build-prd pipeline structure.

## Summary

Ship the integration layer that closes phase `09-research-first` by extending **9 surfaces** in ONE PR. Single implementer, four phases (A: schema validators, B: distill propagation + build-prd routing, C: classifier inference, D: E2E fixture). Phase A is foundation for B, C, D; phases B+C can interleave; phase D depends on A+B+C.

The 9 surfaces (per spec.md §"Dependencies & Inputs"):

1. **Item validator extension** — `plugin-kiln/scripts/roadmap/validate-item-frontmatter.sh` accepts the six new optional research-block fields with the FR-003 validation rules. Warn-but-pass for unknown research-block keys; loud-fail on malformed values.
2. **Issue + feedback validators** — extend (or create) write-time validators for `.kiln/issues/*.md` + `.kiln/feedback/*.md` with the same shape. Plan.md commits to ONE of three approaches per spec R-004 (see Decision 3 below).
3. **PRD frontmatter contract** — extend the `prd-derived-from-frontmatter` validator to accept the new keys after the existing three (`derived_from`, `distilled_date`, `theme`). Authoritative key order per spec FR-004.
4. **Distill propagation** — extend `plugin-kiln/skills/kiln-distill/SKILL.md` with research-block propagation logic: union-merge axes, conflict-prompt on direction conflicts, verbatim-propagate scalar + list keys, byte-identity fallback when no source declares.
5. **PRD parser projection extension** — `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh` projects three more frontmatter fields (`needs_research`, `fixture_corpus`, `fixture_corpus_path`, `promote_synthesized`). Existing field projections + exit codes UNCHANGED (additive only per NFR-009).
6. **Build-prd routing** — extend `plugin-kiln/skills/kiln-build-prd/SKILL.md` with a new "Phase 2.5: research-first variant" stanza inserted between `/tasks` and `/implement`. Single jq lookup on already-parsed JSON; structural no-op on skip path (NFR-002).
7. **Classifier inference** — extend `plugin-kiln/scripts/roadmap/classify-description.sh` with the FR-013 signal-word detector + FR-014 axis-inference table. Output JSON gains an optional `research_inference` key (omitted when no signal matches per FR-014 spec).
8. **Coached-capture interview hooks** — extend `/kiln:kiln-roadmap`, `/kiln:kiln-report-issue`, `/kiln:kiln-feedback` SKILL.md files with the FR-015 single-question rendering. The §5.0a response parser is consumed unchanged from `coach-driven-capture-ergonomics`.
9. **E2E fixture** — `plugin-kiln/tests/research-first-e2e/run.sh` + supporting fixtures. Both happy + regression sub-paths in one `run.sh` invocation. Self-contained per NFR-008.

Plus 8 supporting test fixtures + 1 lint script:

- `plugin-kiln/tests/classifier-research-inference/` (SC-001)
- `plugin-kiln/tests/distill-research-block-propagation/` (SC-002)
- `plugin-kiln/tests/build-prd-research-routing/` (SC-003)
- `plugin-kiln/tests/build-prd-standard-routing-bytecompat/` (SC-004)
- `plugin-kiln/tests/distill-axis-conflict-prompt/` (SC-006)
- `plugin-kiln/tests/distill-research-block-determinism/` (SC-007)
- `plugin-kiln/tests/classifier-research-rejection-recovery/` (SC-008)
- `plugin-kiln/tests/research-block-schema-validation/` (SC-009)
- `plugin-kiln/tests/classifier-axis-inference-mapping/` (SC-010)
- `plugin-kiln/tests/classifier-output-quality-warning/` (SC-011)
- `plugin-kiln/scripts/research/lint-classifier-output-quality-warning.sh` (SC-011 CI lint)

The four themes are **co-deployable** but **independently testable** — schema validators ship with their own SC fixtures; distill propagation ships with its own; build-prd routing ships with its own; classifier ships with its own; E2E ties them all together. There IS atomic-pairing on the E2E fixture (it requires all four prior themes), but each prior theme ships a green per-theme fixture independently.

This PR's net-new + extended footprint targets ~900 LoC across artifacts (under the implicit budget set by the plan-time-agents PR's ~750 LoC; the larger surface here reflects four themes vs two).

## Technical Context

**Language/Version**: Bash 5.x (validators, classifier extension, distill propagation logic, build-prd routing, E2E fixture); Markdown (SKILL.md prose); YAML (frontmatter); JSON (parser projections, classifier output, per-axis verdicts).

**Primary Dependencies**:
- `plugin-kiln/scripts/roadmap/validate-item-frontmatter.sh` (extended additively).
- `plugin-kiln/scripts/roadmap/parse-item-frontmatter.sh` (consumed unchanged).
- `plugin-kiln/scripts/roadmap/classify-description.sh` (extended additively).
- `plugin-wheel/scripts/harness/parse-prd-frontmatter.sh` (extended additively per A-002).
- `plugin-wheel/scripts/harness/evaluate-direction.sh` (consumed unchanged per NFR-009).
- `plugin-wheel/scripts/harness/evaluate-output-quality.sh` (consumed unchanged per NFR-009).
- `plugin-wheel/scripts/harness/research-runner.sh` (consumed unchanged per NFR-009).
- `coach-driven-capture-ergonomics` FR-004 §5.0 + §5.0a (consumed unchanged).
- `claude` CLI v2.1.119+ (inherited).
- `jq` for JSON parsing (already a kiln dependency).
- `python3` for YAML frontmatter helpers (already used by `parse-prd-frontmatter.sh`; same hand-rolled approach).
- `mktemp -d` for E2E temp-dir scaffolding.

**Storage**: filesystem only — no DB, no service. Item / issue / feedback frontmatter at existing paths; PRD frontmatter at existing paths; per-PRD research scratch at `.kiln/research/<prd-slug>/` (gitignored, foundation precedent).

**Testing**: shell-test fixtures under `plugin-kiln/tests/<test-name>/` matching the existing precedent. Live agent spawn is OUT-OF-SCOPE for tests (CLAUDE.md Rule 5); all build-prd / distill / classifier behavior is exercised via direct script invocation OR mocked SKILL.md execution paths.

**Target Platform**: macOS + Linux developer machines + GitHub Actions.

**Project Type**: developer-tooling extension to an existing plugin (no service, no UI, no DB, no net-new runtime dependency).

**Performance Goals**: NONE numeric. NFR-002 / NFR-003 / NFR-005 are byte-identity assertions; NFR-008 is an informational ≤ 30s ceiling for the E2E fixture (not a gate).

**Constraints**:
- Foundation-untouchable files preserved (NFR-009): research-runner, parse-token-usage, render-research-report, evaluate-direction, evaluate-output-quality, compute-cost-usd, resolve-monotonic-clock, research-rigor.json, pricing.json — all UNTOUCHED.
- Backward compat: artifacts without research-block fields unchanged (NFR-001); PRDs without `needs_research: true` route byte-identically (NFR-002).
- Loud-failure on malformed values (NFR-007); warn-but-pass on unknown research-block keys (FR-001 / OQ resolution).
- The composer + resolver are consumed via the canonical recipe in CLAUDE.md (no in-repo bypass).

**Scale/Scope** (per-surface LoC estimates):
- `validate-item-frontmatter.sh`: ~178 LoC current → ~250 LoC with research-block validation stanza (+72).
- Issue + feedback validators (Decision 3): per-decision LoC TBD (Decision 3 below).
- PRD frontmatter validator (per FR-004): scope determined by Decision 6.
- `classify-description.sh`: ~106 LoC current → ~200 LoC with FR-013/FR-014 inference (+94).
- `parse-prd-frontmatter.sh`: ~289 LoC current → ~330 LoC with three more field projections (+41 additive).
- `kiln-distill/SKILL.md`: TBD by Decision 5; estimate +150 LoC for propagation + conflict prompt.
- `kiln-build-prd/SKILL.md`: TBD by Decision 7; estimate +60 LoC for Phase 2.5 stanza.
- `kiln-roadmap/SKILL.md` + `kiln-report-issue/SKILL.md` + `kiln-feedback/SKILL.md`: ~30 LoC each for the FR-015 single-question hook (+90 across three).
- `lint-classifier-output-quality-warning.sh`: ~30 LoC.
- E2E fixture: `run.sh` + fixtures ~250 LoC.
- 10 supporting test fixtures: ~30–60 LoC each (~400 LoC total).

**Total net-new + extended**: ~1,150 LoC across artifacts. Above the plan-time-agents ~750 LoC budget but justified by the four-theme footprint. No single file exceeds 500 LoC (Article VI).

## Resolution of Spec Open Questions (carried into plan)

The spec left seven OQs (OQ-1, OQ-2, OQ-4 resolved in v1; OQ-3, OQ-5, OQ-6, OQ-7 deferred). All non-blocking — surfaced in spec §"Risks & Open Questions" and resolved post-merge against first-real-use evidence.

## Foundation invariants preserved

Per spec NFR-009, the following files are untouchable in this PR:

- `plugin-wheel/scripts/harness/research-runner.sh` (foundation).
- `plugin-wheel/scripts/harness/parse-token-usage.sh` (foundation).
- `plugin-wheel/scripts/harness/render-research-report.sh` (foundation; no new columns).
- `plugin-wheel/scripts/harness/evaluate-direction.sh` (axis-enrichment).
- `plugin-wheel/scripts/harness/evaluate-output-quality.sh` (plan-time-agents).
- `plugin-wheel/scripts/harness/compute-cost-usd.sh` (foundation).
- `plugin-wheel/scripts/harness/resolve-monotonic-clock.sh` (foundation).
- `plugin-kiln/lib/research-rigor.json` (foundation).
- `plugin-kiln/lib/pricing.json` (foundation).
- All foundation `wheel-test-runner.sh` + 12 sibling helpers.
- `plugin-kiln/agents/fixture-synthesizer.md` (plan-time-agents).
- `plugin-kiln/agents/output-quality-judge.md` (plan-time-agents).

The single shared file we DO modify additively in `plugin-wheel/` is `parse-prd-frontmatter.sh` — three more field projections, NO shape change to existing projections, NO new exit codes for pre-research-first PRDs. The implementer MUST verify the three pre-existing fixtures (`empirical_quality`, `blast_radius`, `excluded_fixtures`) project byte-identically post-extension on at least one already-shipped PRD with no research block.

## Phase 0: Outline & Research

**Status**: COMPLETE — see spec.md §"Resolution of PRD Open Questions" + §"Clarifications". No standalone `research.md` is required for this PR (no novel substrate work; all dependencies shipped). Baseline checkpoint SKIPPED per spec.md §"Baseline rationale" (byte-identity NFRs, no numeric perf budget).

## Phase 1: Design & Contracts

### Decision 1 — Single implementer, four phases (sequential within phase)

**Decision**: Task #2 has ONE implementer named `implementer`. Phases A → B/C → D execute sequentially, with B + C interleavable but each phase committed as a unit. Per team-lead launch prompt rationale: "Theme 1's schema is shared foundation; splitting risks file conflicts on validators and SKILL.md files."

**Rationale**: The four themes share several edit points:
- Schema validators (Theme 1) are used by Themes 2 (distill propagation), 3 (classifier), and 4 (E2E).
- The PRD parser extension is shared between Themes 2 (distill writes PRD frontmatter) and Theme 3 (build-prd reads PRD frontmatter).
- SKILL.md files (Themes 2, 3) live in the same plugin tree; concurrent edits risk merge conflicts.

Splitting into multiple implementers would force shared-edit-point coordination that single-implementer sequential execution avoids structurally.

### Decision 2 — Build-prd routing branches inline; no new wheel workflow JSON

**Decision**: The Phase 2.5 stanza in `/kiln:kiln-build-prd` SKILL.md branches inline on the projected `needs_research` value. NO new wheel workflow JSON is shipped; NO new top-level skill is added. The variant pipeline runs as additional steps within the existing build-prd skill, not as a separate orchestrator.

**Rationale**: Matches the plan-time-agents PR's Decision 1 (spawn from SKILL.md, not a separate hook). The skip-path is structurally a no-op (single jq lookup on already-parsed frontmatter JSON, returns immediately) per NFR-002. A new wheel workflow would split the skip-decision logic across two surfaces and force the implementer to coordinate state across them.

**Alternative considered**: a new `/kiln:kiln-build-prd-research-first` skill that the existing skill dispatches to on `needs_research: true`. Rejected: bifurcates the user's mental model; the existing skill is the maintainer's entrypoint regardless of whether routing is active.

### Decision 3 — Issue + feedback validator: shared helper approach

**Decision**: The implementer creates ONE shared helper at `plugin-kiln/scripts/research/validate-research-block.sh` that all four validation surfaces (item / issue / feedback / PRD frontmatter) call. The helper takes a frontmatter JSON projection (already produced by `parse-item-frontmatter.sh` for items, or by `parse-prd-frontmatter.sh` for PRDs, or by a new sibling parser for issues + feedback) and emits the same `{ "ok": bool, "errors": [...] }` JSON shape that the existing `validate-item-frontmatter.sh` emits.

**Rationale**: Avoids the "schema drift across four intake surfaces" risk (spec R-004). Per-validator inline copies would duplicate ~50 LoC of validation logic four times; one shared helper keeps the single source of truth.

**Alternative considered**: per-validator inline implementation with a CI lint asserting they all match a canonical reference snippet. Rejected: more complex than the shared helper, and the CI lint is itself a maintenance hazard.

**Implementer scope**: if `.kiln/issues/*.md` and `.kiln/feedback/*.md` have NO existing write-time validator, the implementer SHOULD use the shared helper to add one (write-time validation in `/kiln:kiln-report-issue` + `/kiln:kiln-feedback` SKILL flows). If creating brand-new validators is judged out-of-scope, the implementer documents this in `specs/research-first-completion/blockers.md` and ships the shared helper anyway (used by the item validator + PRD validator in this PR; the issue + feedback hooks are deferred to a follow-on PR). Prefer (a) — full coverage — unless time-budget forces (b).

### Decision 4 — Worktree mechanism: git worktree (preferred); fallback to tempdir copy if blocked

**Decision**: The `implement-in-worktree` step in the build-prd research-first variant uses `git worktree add <tempdir>` to create an isolated checkout. The variant `/implement` runs in the worktree; the worktree is cleaned up via `git worktree remove --force` after the gate runs.

**Rationale**: Git worktrees are the canonical isolation mechanism — no copy overhead, native to git's mental model, share the same `.git/` so refs/branches are visible. The Agent tool's `isolation: "worktree"` parameter (per the Agent schema in CLAUDE.md context) demonstrates this pattern is already standard in the harness.

**Alternative considered**: `cp -R <repo> <tempdir>` copy. Rejected: 5–10x slower on large repos, no shared `.git/`, requires manual ref management, no rollback affordance.

**Fallback**: if `git worktree add` fails (e.g., locked working tree, filesystem incompatible), the variant pipeline bails with `Bail out! research-first-worktree-failed: <error>` and instructs the maintainer to clean up before retry. NO silent fallback to copy-based isolation per NFR-007 loud-failure.

### Decision 5 — Distill propagation: extends existing SKILL.md inline, no new helper script

**Decision**: The FR-005..FR-008 propagation logic lives inline in `/kiln:kiln-distill` SKILL.md as a new step run before the existing PRD-emission step. Conflict resolution is implemented as a confirm-never-silent prompt in the SKILL.md prose (matching the existing Step 0.5 un-promoted gate pattern from `workflow-governance`).

**Rationale**: Distill is already a procedural orchestrator over multiple sources; adding propagation logic as a step matches the existing SKILL.md model. A separate helper script would split the logic across two surfaces and require duplicating the source-loading code that distill already does.

**Alternative considered**: a new helper at `plugin-kiln/scripts/distill/propagate-research-block.sh`. Rejected: the propagation needs the full set of selected sources (already loaded by distill), and the conflict prompt needs interactive user I/O which is awkward in a helper but natural in SKILL.md prose.

**Determinism hook (NFR-003)**: the propagation step computes `LC_ALL=C` sorted axes via `jq` (already a kiln dep). The exact `jq` expression is documented in `contracts/interfaces.md §3` as the single source of truth for axis ordering.

### Decision 6 — PRD frontmatter validator: extends existing validator OR uses the shared helper from Decision 3

**Decision**: The PRD frontmatter validator (per FR-004) is implemented by calling the shared helper from Decision 3, applied to the JSON projection from `parse-prd-frontmatter.sh` (extended in this PR with three more field projections per surface 5). NO new top-level PRD validator script is added. The validator hook lives wherever the existing `prd-derived-from-frontmatter` validation lives (implementer to discover; likely in `plugin-kiln/skills/kiln-distill/SKILL.md` or `plugin-kiln/skills/kiln-build-prd/SKILL.md` at PRD-load time).

**Rationale**: Reuses the shared validation helper (single source of truth from Decision 3) and avoids duplicating validation logic per artifact type.

**Alternative considered**: ship a brand-new `validate-prd-frontmatter.sh` script. Rejected: redundant with the shared helper.

### Decision 7 — Phase 2.5 stanza is structurally a no-op on skip path

**Decision**: The Phase 2.5 stanza in `/kiln:kiln-build-prd` SKILL.md probes the projected frontmatter JSON for `needs_research: true`. If FALSE or absent, the stanza emits NO output and returns immediately to the next phase. NO stdout banner, NO log line — true byte-identity per NFR-002.

**Rationale**: NFR-002 mandates byte-identity routing for non-research PRDs. A "research-first-skipped" log line would create a stdout diff against pre-PR behavior, violating the byte-identity invariant. OQ-6 (deferred) explicitly notes this: re-open if maintainers want skip-path observability.

**Operational note**: the implementer SHOULD add a comment in the SKILL.md prose explicitly stating "skip-path: structural no-op — single jq lookup on already-parsed JSON; NEVER emit stdout on skip path" for future maintainers.

### Decision 8 — Classifier inference: extends classify-description.sh in-place, no new script

**Decision**: The FR-013/FR-014 inference logic is added to `plugin-kiln/scripts/roadmap/classify-description.sh` as additive code. The existing JSON output shape gains an OPTIONAL `research_inference` key (omitted when no signal matches per FR-014 spec). Existing fields (`surface`, `kind`, `confidence`, `alternatives`) are unchanged.

**Rationale**: Per CLAUDE.md "Active Technologies": the cross-surface classifier is a single script that callers (kiln-roadmap, kiln-report-issue, kiln-feedback) consume. Forking it into a sibling `infer-research.sh` would require callers to invoke both scripts and merge the outputs. Additive extension keeps the single-call contract.

**Alternative considered**: ship a new `plugin-kiln/scripts/research/infer-research-block.sh` script invoked alongside `classify-description.sh`. Rejected: doubles the call sites for callers; harder to keep the two outputs in sync.

### Decision 9 — Coached-capture interview integration: SKILL.md prose, no new helper

**Decision**: The FR-015 single-question rendering lives in each capture-skill's SKILL.md (`/kiln:kiln-roadmap`, `/kiln:kiln-report-issue`, `/kiln:kiln-feedback`) as a new question stanza. The `coach-driven-capture-ergonomics` §5.0 template + §5.0a response parser are consumed verbatim — no new template, no new parser.

**Rationale**: The existing coached-capture pattern is well-established; adding a new question stanza to each capture skill matches the existing ergonomics. A new helper script for "render-research-block-question" would be premature abstraction (Article VI).

**Implementer scope**: ONE new question stanza per capture skill (3 stanzas total). The stanza is conditional on `research_inference != null` in the classifier output JSON; when absent, the question is silently skipped (NOT rendered with empty defaults — false-negative recovery is structural).

### Decision 10 — E2E fixture: ONE run.sh, two scenarios via flag

**Decision**: `plugin-kiln/tests/research-first-e2e/run.sh` accepts `--scenario=happy` and `--scenario=regression` flags. Default invocation (no flag) runs BOTH sub-paths sequentially with a temp-dir reset between them. Each sub-path has its own assertion; the run.sh's last-line `PASS` is emitted only if BOTH pass. Self-contained per NFR-008.

**Rationale**: The PRD's User Stories scenario 4 explicitly requires the regression case as load-bearing. Bundling both sub-paths in one `run.sh` keeps the test cohesive (one invocation = both proofs) and matches the SC-005 evidence path.

**Alternative considered**: separate `run-happy.sh` + `run-regression.sh`. Rejected: two run.sh files complicate the `/kiln:kiln-test` harness wiring (the harness expects one run.sh per test fixture); bundled is the harness convention.

**Mocking strategy**: every LLM-invoking step is replaced with a deterministic mock that writes a synthetic baseline/candidate output to a known path. The gate's evaluation is exercised against the mocked outputs. Live `claude` CLI invocations are forbidden in the fixture (NFR-008 self-containment + CLAUDE.md Rule 5).

## Phase 1 outputs

- `contracts/interfaces.md` — see [`./contracts/interfaces.md`](./contracts/interfaces.md). SINGLE SOURCE OF TRUTH for: shared validation helper signature, parse-prd-frontmatter additive projections, classify-description research_inference shape, distill propagation jq expression, build-prd Phase 2.5 stanza signature, E2E fixture run.sh CLI surface.
- `quickstart.md` — DEFERRED. The maintainer-facing "how to use research-first" quickstart is bundled with the first first-real-use research-first PRD (per spec SC-001 dependency joint with first synthesized-corpus PRD). This PRD is plumbing; the quickstart is post-merge.
- `data-model.md` — DEFERRED. The "data model" here is the six new YAML keys + their JSON projection — fully specified in spec.md FRs and contracts/interfaces.md §1.

## Constitution Check

*GATE: Must pass before Phase 1 design. Re-check after Phase 1.*

- **Article I (Spec-First)**: PASS — spec.md committed before any implementation; FR comments will be added in implementation per Article I. Every FR has a unique ID; every acceptance scenario is Given/When/Then.
- **Article II (80% coverage)**: PASS — every net-new helper has a corresponding test fixture under `plugin-kiln/tests/`. Mock-spawn pattern keeps tests fast + deterministic. The 10 SC fixtures + 1 E2E fixture cover all FRs and NFRs.
- **Article III (PRD as source of truth)**: PASS — spec divergences from PRD are documented in spec §"Resolution of PRD Open Questions" + §"Clarifications" with rationale. No FR contradicts the PRD; new FRs (e.g., FR-003's repo-relative-only path validation) are PRD-derived via OQ-4.
- **Article IV (Hooks enforce rules)**: PASS — hooks unmodified; spec + plan + tasks + first `[X]` task gates apply to implementer.
- **Article V (E2E testing)**: PASS — every test fixture is a `run.sh` invoking the actual scripts (not unit-test mocks). Live `claude` CLI invocation is mocked per CLAUDE.md Rule 5.
- **Article VI (Small focused changes)**: PASS — total artifacts ~1,150 LoC; no file exceeds 500 LoC (largest extension is `validate-item-frontmatter.sh` at ~250 LoC post-extension; classify-description at ~200 LoC). Net-new helpers each ≤ 150 LoC.
- **Article VII (Interface Contracts Before Implementation)**: PASS — `contracts/interfaces.md` ships in this PR with every net-new + extended signature.
- **Article VIII (Incremental Task Completion)**: PASS — tasks.md uses 4 phases (A: schema validators, B: distill propagation + build-prd routing, C: classifier inference, D: E2E fixture + lint + test fixtures). Implementer marks `[X]` per-task and commits per-phase. Phase A is the foundation phase; B + C interleave; D depends on A+B+C.

**Verdict**: ALL articles pass; no documented exceptions required.

## Phase 2: Tasks (deferred to /tasks)

Tasks live in [`./tasks.md`](./tasks.md) — generated next.

## Wheel-workflow guidance

This PR does NOT emit a new wheel workflow JSON (per Decision 2). The build-prd routing branches inline within the existing skill. No `model:` tier selection applies at the workflow level.

For agent-step model selection within the variant pipeline: the existing `establish-baseline`, `implement-in-worktree`, `measure-candidate`, `gate` steps are NOT agent steps in this PR — they are orchestrated inline by the SKILL.md prose. If a follow-on PR splits them into agent steps with `model: <tier>` selection, that work belongs to its own PRD.

## Key rules

- Use absolute paths.
- ERROR on gate failures, unresolved clarifications, missing fixture-corpus, missing rubric, missing pinned-model.
- NEVER silently fall back to a hardcoded default rigor / pricing / model / rubric / schema.
- NEVER summarize the rubric en route to the judge — `{{rubric_verbatim}}` interpolation token is enforced by lint (carried-forward from plan-time-agents).
- NEVER pass `{baseline, candidate}` to the judge — always blinded `{output_a, output_b}` (carried-forward from plan-time-agents FR-015).
- ALWAYS preserve byte-identity on the no-research-block path (NFR-002, NFR-005).
- ALWAYS use the shared validation helper (Decision 3) for the four schema surfaces — single source of truth.
- ALWAYS render the FR-006 conflict prompt with both source paths AND both `(metric, direction)` pairs verbatim (NFR-004).
- ALWAYS structurally absent `research_inference` from classifier output when no signal matches (FR-014, NFR-006 sibling).
- ALWAYS emit the verbatim FR-016 warning when `output_quality` is in the proposed axes — lint-enforced (SC-011).
- ALWAYS run BOTH happy + regression sub-paths in the E2E fixture; PASS only when both pass (FR-018, SC-005).
- NEVER emit stdout on the build-prd Phase 2.5 skip path (Decision 7, NFR-002 byte-identity).
