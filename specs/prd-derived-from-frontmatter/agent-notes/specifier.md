# Specifier Friction Notes — prd-derived-from-frontmatter

**Agent**: specifier
**Task**: #1 — Specify + plan + tasks for prd-derived-from-frontmatter
**Date**: 2026-04-24

## PRD interpretation calls

### Call A — Migration entry point (PRD OQ1 / plan.md Decision D1)

**PRD ambiguity**: PRD §Risks OQ1 offered two options — standalone `/kiln:kiln-prd-backfill` skill OR subcommand of `/kiln:kiln-hygiene`. The team lead kickoff message explicitly recommended the hygiene subcommand; the PRD's own User Story 3 names `/kiln:kiln-prd-backfill` with a parenthetical "(or equivalent)" escape hatch.

**Decision recorded**: plan.md Decision D1 — hygiene subcommand (`/kiln:kiln-hygiene backfill`). Rationale: consolidates propose-don't-apply audits under one entry point, shares the bundle-writer helper already present in hygiene's preview renderer, survives the one-shot lifecycle naturally as a perpetually-available subcommand rather than a vestigial top-level skill.

**Implication captured**: tasks.md T04-1 / T04-2 / T04-3 edit `plugin-kiln/skills/kiln-hygiene/SKILL.md` + `plugin-kiln/rubrics/structural-hygiene.md` + `CLAUDE.md`. NO new top-level skill file under `plugin-kiln/skills/` — this is explicit in plan.md and tasks.md so the implementer doesn't accidentally create a new skill directory.

### Call B — `distilled_date:` format (PRD OQ2 / plan.md Decision D2)

**PRD ambiguity**: UTC vs local; time-included vs date-only.

**Decision recorded**: plan.md Decision D2 — UTC ISO-8601 date (YYYY-MM-DD), matching `/kiln:kiln-feedback`'s `date:` convention and hygiene's `merged_date` shape. Inline `date -u +%Y-%m-%d` — no helper script.

### Call C — Hand-authored PRD policy (PRD OQ3 / plan.md Decision D3)

**PRD ambiguity**: hand-authored PRDs might carry `derived_from: []`, OR omit the block entirely, OR be the product-level `docs/PRD.md` that's already out-of-scope.

**Decision recorded**: plan.md Decision D3 — both cases (empty list OR no block) fall through Step 4b's scan-fallback path. NO special-case logic. The `matched == len(derived_from)` invariant naturally accepts `len == 0 → matched == 0`. The migration's idempotence predicate (contracts §4.2) treats both empty-list and non-empty-list frontmatter as "already migrated" to avoid re-backfilling.

### Call D — Diagnostic field-append discipline (NFR-005)

**PRD ambiguity**: The PRD says "additive — existing grep-anchored test patterns MUST continue to match" but does not pin WHERE the new fields go. I interpreted this as "append at the end, never insert in the middle."

**Decision recorded**: contracts §2.6 pins the exact field order — `scanned_issues`, `scanned_feedback`, `matched`, `archived`, `skipped`, `prd_path`, `derived_from_source`, `missing_entries`. Field 6 (`prd_path`) keeps its position at the end of the PR-#146 6-field block; the two new fields follow. PR-#146's SMOKE.md §5.3 regex is un-anchored at end-of-line (`[^[:space:]]+` for `prd_path=` with no trailing `$`), so the appended fields don't break existing matches. SC-007's verification log is where this invariant actually gets tested end-to-end.

### Call E — `missing_entries` when scan-fallback fires

**PRD ambiguity**: The PRD defines `missing_entries:` on the frontmatter path only (FR-006). The scan-fallback path has no `derived_from:` list — what value should the field carry?

**Decision recorded**: contracts §2.4 / §2.5 — `MISSING_ENTRIES=()` is initialized empty before the scan-fallback loop runs; the scan-fallback path NEVER populates it. `missing_entries=[]` always appears on the scan-fallback line. This keeps the diagnostic's arity invariant (same 8 fields on every run) — grep patterns and field-count assertions don't need to special-case the path.

## Things I had to look up

- **PR #146 artifacts** — I read `specs/pipeline-input-completeness/{spec.md,plan.md,tasks.md,contracts/interfaces.md,SMOKE.md}` to understand the Step 4b diagnostic contract this spec extends. The extended diagnostic builds on §2 of PR #146's contracts; the PR-#146 regex in §2.6.2 is copied directly from PR #146's SC-002 verification regex.
- **Distill SKILL body** — `plugin-kiln/skills/kiln-distill/SKILL.md` (228 lines). Step 4 is the PRD-rendering block; Step 5 already handles the source-side `prd:` update (the reverse edge). The frontmatter write inserts between source-selection (Step 3) and body-rendering (Step 4) conceptually, but physically it's a new emit step at the top of Step 4's body template.
- **Hygiene SKILL body + rubric** — `plugin-kiln/skills/kiln-hygiene/SKILL.md` Step 5c (lines 174–253) for the existing merged-prd-not-archived logic; `plugin-kiln/rubrics/structural-hygiene.md` for the rule YAML block shape and the bundled-accept preview convention. The rubric's cost/signal_type/match_rule/action taxonomy informs the new `derived_from-backfill` rule entry.
- **CLAUDE.md plugin-portability invariant** — trivially satisfied here because NO workflow command-step scripts are introduced. All changes live in SKILL.md bodies or rubric markdown. Documented in NFR-002 for future refactors.
- **Existing PRD shapes** — I spot-checked `docs/features/2026-04-23-pipeline-input-completeness/PRD.md` and `docs/features/2026-04-24-prd-derived-from-frontmatter/PRD.md` to confirm the `### Source Issues` table uses the `| # | [title](.kiln/<type>/<file>.md) | ...` shape. The migration's awk parser in contracts §4.2 anchors on `/\]\(([^)]+)\)/` — the parenthesized path in the markdown link.

## Team-lead prompts — clarity notes

- **Chaining requirement** — crystal clear (3-step uninterrupted pass, no idle time). Followed by producing all four artifacts back-to-back.
- **Spec directory naming (FR-005)** — "no numeric prefix, no date — matches feature portion of branch name" — unambiguous. Directory: `specs/prd-derived-from-frontmatter/`.
- **Friction notes requirement** — unambiguous. This file satisfies it.
- **Suggested phase shape** — I followed the team lead's suggested Phase A–F structure nearly verbatim; `contracts/interfaces.md` maps each phase to FRs + SCs in §6. Total task count: 13 (within the 12–15 guideline).

### One mild friction

The team lead referenced **"FR-005"** in two different senses:

1. "SPEC DIRECTORY NAMING (FR-005)" — directory name convention.
2. This spec's internal FR-005 — Step 4b scan-fallback trigger.

I resolved the collision by keeping the spec FR numbering as-shipped (FR-001..FR-011 matching the PRD), and used "spec directory MUST be `specs/prd-derived-from-frontmatter/`" prose in the spec's metadata header rather than a numbered FR. Not a blocker; noting for the retrospective.

## Suggestions for the next pipeline

1. **A shared `read_derived_from()` helper** — this spec's Phase B (build-prd) and Phase C (hygiene) both want the same awk extractor. Plan.md punts on where it lives ("sourceable location, implementer's choice under `plugin-kiln/`"). A follow-on PRD could factor it into a real shared utility under `plugin-kiln/scripts/` AND update CLAUDE.md's plugin-portability section to note that `plugin-kiln/scripts/` is the home for cross-skill shared shell helpers. For now, duplicating the helper in each SKILL.md is the safest choice (no new file, no portability question).
2. **Diagnostic-line tooling** — the PR-#146 regex replay check (SC-007) is a verification step, not an automated guard. A small assertion library under `plugin-kiln/scripts/assert-step4b-diag.sh` that takes the raw line + both regexes and returns OK/FAIL would make it easier for every future diagnostic-extending PRD to prove NFR-005 holds. Defer until a third diagnostic-extending PRD ships.
3. **Migration preview schema** — the `prd-derived-from-backfill-<timestamp>.md` file is markdown, not JSON. Hygiene's existing preview is also markdown. If more audit-style subcommands ship, a shared preview schema (even if rendered as markdown) would help downstream tooling. Defer until the third propose-don't-apply audit ships.
4. **FR-012 awareness in the hygiene rubric** — the PRD references FR-012 (distill's feedback-first ordering) as a cross-spec dependency. The rubric text in contracts §3.3 mentions it only implicitly ("one signal per listed entry"). Explicit cross-reference in the rubric would help future maintainers who read the rubric cold.
5. **Backwards-compat test automation** — SC-007's verification is a manual `/kiln:kiln-build-prd` re-run. If the project moves to a real E2E test harness for kiln itself (today none exists — constitution says this is acceptable), this would be the first check to script.

## No-blockers status

All contracts resolved. No [NEEDS CLARIFICATION] markers remain. All 11 FRs traceable to PRD FRs; all 8 SCs traceable to spec FRs; all 3 PRD open questions locked as plan.md Decisions. Ready for implementer.
