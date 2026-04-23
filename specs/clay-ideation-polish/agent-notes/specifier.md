# Specifier Friction Notes — clay-ideation-polish

**Agent**: specifier
**Date**: 2026-04-22
**Task**: #1 (specify + plan + tasks for clay-ideation-polish)

## What went smoothly

- The PRD was well-structured with FR/NFR/SC IDs already in place — straight 1:1 trace into spec.md.
- The team-lead brief pre-flagged the three plan-phase decisions and gave recommendations, which made plan.md's "Locked Decisions" section a confirmation exercise rather than an exploration. Saved a lot of cycles.
- All five affected skills are pure Markdown — no code, no imports, no test runners. Made it trivial to scope edits per FR.

## Friction / risks for downstream agents

- **Contracts file is "shape only", not executable.** The bash predicates (`is_parent_product`, `list_sub_ideas`, `read_frontmatter_field`) live as snippets in `contracts/interfaces.md` and are inlined per skill. There is no shared helper file and no test that all five copies stay in sync. If contracts change post-Phase-A, the implementer must update each skill that already inlined the old version. Keep the helpers small (they are) and consider a grep gate in audit if drift becomes a real problem.

- **Backwards-compat for missing `intent:` (Decision 2) is silent.** Skills treat missing `intent:` as `marketable`. There is no log line, no warning. The only way a user notices the rule is if their existing flat product flows through `/clay:clay-idea-research` and they wonder why it didn't get demand-validation framing. Acceptable for now per NFR-002, but a future "intent backfill" prompt is the documented escape valve.

- **Phase D (shared-repo) is the riskiest phase.** It changes `clay-create-repo`'s defaults for sub-ideas (default flips from "new repo" to "shared repo"), modifies `clay.config` semantics (one repo entry covers multiple sub-slugs), and introduces `.repo-url` markers for sub-ideas pointing at a shared URL. The implementer should read all three D tasks together before starting and probably do D1+D2+D3 as one continuous edit rather than piecemeal — they touch overlapping sections of the same file.

- **No test suite for this plugin** (per CLAUDE.md) means SC verification is fully manual via the Phase E fixtures. The auditor (task #3) will need to run the SMOKE.md commands by hand against the fixtures and capture output.

## Decisions I made beyond the brief

- **Sub-idea frontmatter** — I added `status:` to the sub-idea schema (already present in flat products' implicit conventions in `clay-list`'s status-derivation logic). The brief named only `title, slug, date, status, parent, intent`, so this matches.

- **Parent-detection predicate location** — I documented the predicate in `contracts/interfaces.md` and instructed inlining per skill rather than creating a shared `lib/`. Clay's existing skill style is self-contained Markdown with embedded bash; matches Decision rationale in plan.md.

- **`status: pending` for tasks** — I used `[ ]` checkbox style per CLAUDE.md "incremental task completion (NON-NEGOTIABLE)" rule. The implementer marks each `[X]` immediately after the edit, not in a batch.

## Recommendations for implementer

1. Do Phase A first end-to-end (A1→A6 with commit). It's the foundation — Phases B/C/D all read or write `intent:` or `parent:` and rely on the helpers documented in contracts §5.
2. When inlining the bash helpers, copy verbatim from `contracts/interfaces.md` — do not paraphrase. The audit step will look for exact matches.
3. Phase D's prompt text for incompatible-tech-stack warning (PRD risk #3) is open-ended; I left guidance in plan.md but no exact wording. Use your judgment and keep it to one sentence.
4. Do NOT touch `clay-project-naming/SKILL.md` — the PRD scopes intent to research depth and PRD shape, not naming. Naming runs the same regardless of intent (and is skipped entirely for `internal` per FR-003).

## Recommendations for auditor

- Verify FR-001..FR-012 against grep matches in the 5 SKILL.md files.
- Verify FR-007 predicate appears verbatim from contracts in each skill that uses it (clay-idea, clay-list, clay-create-repo).
- Run the 6 SMOKE.md commands against the Phase E fixtures and capture output to `.kiln/qa/clay-ideation-polish-smoke.md`.
- Confirm SC-006 (backwards compat) by spot-checking one existing flat product in `products/` (if any exist in this repo at audit time) — running `/clay:clay-list` should produce identical output for that row pre and post merge.

## Time taken

~30 minutes end-to-end (read PRD + 5 skills + constitution → write spec + plan + contracts + tasks + this note). No clarifying questions needed — the team-lead brief pre-resolved the three decision points.
