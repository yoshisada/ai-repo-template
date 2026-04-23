# Specifier friction notes — kiln-structural-hygiene

**Agent**: specifier | **Date**: 2026-04-23 | **Branch**: `build/kiln-structural-hygiene-20260423`

## What went smoothly

- Having the kiln-self-maintenance spec + kiln-claude-audit skill already in-tree gave me a concrete shape to mirror. The rubric schema in contracts §1 is a near-clone of the CLAUDE.md rubric schema, and the audit skill's 5-step flow maps 1:1. This saved roughly half the design work — I only had to decide where the hygiene-specific shapes differ (bundled preview block, gh bulk-lookup, two predicate sections).
- The PRD's "Risks & Open Questions" section pre-telegraphed the 5 locked decisions verbatim. The team-lead prompt then named them as `Decision 1..5` and listed the recommended answer. Both were correct; I only had to confirm and document rather than re-litigate.
- The 18-item leaked-issues file (`.kiln/issues/2026-04-23-stale-prd-created-issues-not-archived.md`) was an excellent tactical fixture — it gave me both a concrete frontmatter sample AND a built-in SC-008 smoke test.

## Friction / things I had to work around

- **Existing kiln-cleanup already has issue-archival logic (Step 2.5 + doctor 3f/4a).** This is a quiet surprise: the infrastructure for "scan `.kiln/issues/` for archivable items" exists today, but it deliberately matches `status: prd-created|completed` without the merged-PR check — so it either under-archives (doctor, which only matches `closed|done`) or over-archives (cleanup Step 2.5, which archives any `prd-created` regardless of whether the PRD actually merged). The PRD's Part A vs Part B split is real: the hygiene audit is a SAFETY NET, not a replacement. The spec and plan call this out, but the implementer should watch for the temptation to "just reuse cleanup Step 2.5" — that would conflate the tools. Phase E backwards-compat fixture (E2) is the gate that enforces the separation.
- **Doctor's existing subcheck lettering is NOT alphabetical** — the current order is 3a, 3b, 3c, 3d, 3g, 3f, 3e (not 3a..3h). I initially tried to insert 3h at the end, but 3e is the Report block that renders the table — it must remain terminal in the subcheck sequence. I locked placement as "after 3g, before 3f" to keep Report last. The implementer should not try to "fix" the out-of-alphabetical-order numbering in this PR — that's a separate cleanup.
- **`gh pr list` JSON key is `headRefName`, not `branch`.** Easy to get wrong from memory. Contract §5 spells out the exact jq expression and the TSV column layout to avoid a silent shape mismatch during implementation.
- **Feature-slug derivation is not obvious.** PRD paths can be either `docs/features/YYYY-MM-DD-<slug>/PRD.md` OR `products/<slug>/PRD.md`. Both shapes exist in-repo today. Contract §5 lists both derivation paths so the implementer doesn't have to guess.
- **Orphaned-folder predicate is the highest-false-positive-risk rule** in the MVP. The three-check AND in Decision 3 is intentionally conservative; I'd rather have the rule under-fire than blow up a consumer's custom top-level directory. If the rule stays silent in practice, Phase A's threshold (30 days) can relax to 14 in v2.

## Decisions I made that deserve scrutiny in review

1. **Contract §2 preview shape omits empty per-rule sections** (they're not rendered with zero rows). This keeps no-drift runs clean. Implementer might prefer always-render-for-idempotence — if so, adjust the contract.
2. **Bundled block is strict accept-all (Decision 4)**. I followed the PRD's recommendation. If QA finds this too rigid in practice, v2 can introduce `--except <file>`; that's called out in the plan's Decision 4 rejected-alternatives subsection.
3. **Single implementer, not parallel agents.** The phase dependencies are truly sequential (B depends on A; D depends on B; C can technically run parallel to B/D but the total task count is low enough that coordination overhead exceeds the savings). If the team-lead wants to parallelize, split C off as its own agent but keep A→B→D serial.
4. **SMOKE.md only codifies SC-008 (18-item leak repro).** The other 7 SCs have fixture tests under the skill's `tests/` directory. If the pipeline convention is "SMOKE.md covers everything", the implementer should consolidate — but I followed the prior kiln-self-maintenance SMOKE.md precedent which similarly only covered the keystone test.

## Time / token cost

- Spec + plan + tasks + contracts: roughly 1 focused pass, no re-work. Most of the authorship time went into contracts/interfaces.md §5 (the merged-PR predicate) and §1 (rubric schema). Everything else was pattern-copy from the kiln-self-maintenance spec.
- No agent escalations; no back-and-forth with the team-lead needed.

## Hand-off notes for the implementer

- Read the plan's Decision 5 carefully before touching `plugin-kiln/skills/kiln-doctor/SKILL.md`. The exact insertion point (between 3g and 3f) matters — other orderings will break 3e's Report-is-last invariant.
- The exact error-message strings in contracts §9 are grep-anchored in tests. Do not re-word; they're load-bearing.
- When writing the `merged-prd-not-archived` predicate, implement the gh-unavailable branch FIRST, run the gh-unavailable fixture, then add the gh-available path. This prevents accidentally hard-coupling the rule to a live `gh`.
- Phase A4 is the "verify ≥2 rubric references" gate. Don't mark it `[X]` until Phase E lands.
