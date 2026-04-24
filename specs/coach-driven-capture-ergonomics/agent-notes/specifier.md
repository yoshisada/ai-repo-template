# Specifier Friction Note — `kiln-coach-driven-capture`

**Agent**: specifier
**Pipeline**: `kiln-coach-driven-capture`
**Branch**: `build/coach-driven-capture-ergonomics-20260424`
**Date**: 2026-04-24

## What was confusing in my prompt

- **Single-uninterrupted-pass instruction vs. kiln slash-command mechanics**: I was told to "run `/specify` → `/plan` → `/tasks` in one pass." In practice, `/specify` is a skill body whose opening step creates a new git branch and spec directory (`001-something`). The repo already had the correct branch (`build/coach-driven-capture-ergonomics-20260424`) and the team-lead dictated the spec directory name (`specs/coach-driven-capture-ergonomics/`) with NO numeric prefix. Running the skill as-written would have created a `specs/001-...` sibling directory and defeated FR-005. I resolved this by authoring the three artifacts directly against the templates the skill consumes, without running `.specify/scripts/bash/create-new-feature.sh`. This is effectively "execute the intent of each skill" rather than "invoke the Skill tool." Flag for pipeline design: consider a `--existing-branch --spec-dir <name>` flag on `/specify` so the same skill body can be safely invoked inside a pipeline.
- **"Task ID 1" ambiguity**: TaskList exposed `#1 [pending] Specify + plan + research + tasks`. It wasn't obvious whether the "research" in that title meant the optional `research.md` artifact or a separate `/research` step. I assumed the former (research.md companion to plan.md) — PRD didn't reference a research subcommand. If the pipeline has a `/research` skill I missed, that's a gap.

## Where I got stuck

- Nowhere blocking. The PRD was unusually well-scoped — 17 FRs, clear source-entry attribution, explicit numbered open-questions resolved one-per-Clarification in the spec. The main friction was ergonomic (tool mechanics, not thinking).
- Minor stall on: which directory name format should `disambiguate-slug.sh` output when a pre-existing committed PRD already occupies `<date>-<slug>`? Resolved conservatively: the algorithm treats committed-PRD directories as "collisions" and suffixes the fresh emission. Documented in research.md §4.

## PRD ambiguities I had to resolve

Five clarifications, all documented in `spec.md § Clarifications` with rationales:

1. **Multi-theme slug collision** (PRD open question 2) → numeric suffix, first-occurrence un-suffixed. Alternative (slug rewriting at grouping time) rejected as less reversible.
2. **Vision diff grouping verbosity** (PRD open question 4) → per-section accept-all nested inside global accept-all. Alternative (flat line-by-line) rejected as too noisy on active repos.
3. **External best-practices cache staleness** (PRD open question 3) → 30-day threshold, flagged but non-blocking. PRD hinted at this cadence ("fetched: date … >30 days"); I made it concrete.
4. **Partial-snapshot vision fallback** (PRD open question 6) → partial-evidence draft with per-section annotations; only the fully-empty case triggers the banner. Preserves the "draft, don't ask" philosophy as far as evidence allows.
5. **Tone validation** (PRD open question 5) → explicitly manual-review-only at PRD audit time. No automated heuristic. PRD already warned about this; I crystallized the validation path.

## What could be improved in the next pipeline run

1. **Teach `/specify` about existing branches and custom spec-dir names.** The repeated friction point in pipelines is that `/specify` assumes it's creating a fresh numbered feature. A `--reuse-branch --spec-dir <path>` flag (or auto-detection when the branch name already matches a canonical pattern) would remove the "execute the skill's intent by hand" workaround I used here.
2. **Clarify the `research.md` expectation in task titles.** "Specify + plan + research + tasks" suggests 4 artifacts. I delivered all 4, but a newcomer could reasonably think "research" means a separate `/research` skill that doesn't exist.
3. **Surface PRD `derived_from:` → item-state hooks for the specifier too.** The `/specify` skill body has a block for flipping roadmap items `distilled → specced`. I did NOT run that flip because this PRD's `derived_from:` entries are `.kiln/feedback/` and `.kiln/issues/` files — not `.kiln/roadmap/items/`. The skill body handles that case correctly (no-op), but the spec-pipeline prompt could explicitly call out which derived-from classes trigger which hooks, to reduce specifier anxiety about skipping the hook.
4. **Pipeline-internal skills should not prompt for interactive input.** `/specify`'s Step 6 has an interactive "Answer Q1: A, Q2: Custom …" path. In a team-lead-orchestrated pipeline that path would stall. I pre-emptively resolved all 5 clarifications without markers so there was nothing to prompt on — but a pipeline-safe `/specify` should short-circuit to "resolve conservatively and document" behavior when invoked from inside a wheel or team context.
5. **Fixture catalog discovery.** The `plugin-kiln/tests/` substrate was only discoverable via the `/kiln:kiln-test` skill description. Adding a one-paragraph "test fixtures: shape + conventions" block to `plugin-kiln/README.md` (or equivalent) would let a specifier write more specific test task descriptions in tasks.md without spelunking into `plugin-kiln/scripts/harness/`.

## Artifacts delivered

- `specs/coach-driven-capture-ergonomics/spec.md` — 21 FRs (1–21), 6 NFRs, 4 user stories with Given/When/Then scenarios, 5 clarifications documented, 7 measurable SCs, 8 edge cases.
- `specs/coach-driven-capture-ergonomics/plan.md` — 3 implementation tracks mapped to pipeline owners, constitution gates checked, risk table, fully-scoped to `plugin-kiln/`.
- `specs/coach-driven-capture-ergonomics/contracts/interfaces.md` — script signatures, JSON schema for ProjectContextSnapshot, per-consumer call-site contracts, signature-change protocol.
- `specs/coach-driven-capture-ergonomics/research.md` — 9 short notes on implementation decisions (fixture approach, jq strategy, cache strategy, slug algorithm, per-section diff UX, tone scope, dependency confirmations).
- `specs/coach-driven-capture-ergonomics/tasks.md` — 57 tasks across 6 phases, owner-tagged, FR-traceable, with explicit test-before-implementation ordering.
- `specs/coach-driven-capture-ergonomics/checklists/requirements.md` — validation checklist, all items passing.

## Open questions for downstream

- None blocking. The contract in `contracts/interfaces.md` is the single source of truth; if implementers discover a signature drift, the Signature Change Protocol at the bottom of that file is the escape hatch.
