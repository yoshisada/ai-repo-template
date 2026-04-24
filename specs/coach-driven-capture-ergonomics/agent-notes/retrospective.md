---
agent: retrospective
feature: coach-driven-capture-ergonomics
recorded_at: 2026-04-24
---

# Retrospective Friction Notes

## Input quality

- **Friction-note corpus was complete and self-consistent.** All six upstream
  agents (specifier, impl-context-roadmap, impl-vision-audit, impl-distill-multi,
  audit-quality, audit-smoke-pr) left notes. No polling of upstream agents via
  SendMessage was required. The notes were structured, cited commits by hash,
  and flagged the same retro items across multiple perspectives (e.g.,
  concurrent-working-tree race mentioned in all three implementer notes +
  audit-smoke-pr). Cross-triangulation was trivial.
- **`audit-quality`'s compliance-report.md was the strongest artifact** and the
  single best input for building a ship-confidence picture: PRD↔Spec crosswalk,
  explicit tripwire vs behavioural test decisions, file-level coverage table.
  `audit-smoke-pr` used it as a to-do list; I used it the same way.
- **`impl-vision-audit`'s post-ship addendum resolved what would have been the
  hardest claim to verify from the brief** — the team-lead scope-violation
  nudge. The addendum reconstructed the git timeline with author-time, mapped
  each commit to its actual agent, and explained why git author metadata is
  useless as a discriminator. Without that addendum I would have had to
  re-derive the timeline from scratch.

## What was hard

- **Verifying the commit-mis-attribution claim required reading SIX notes +
  running `git log --author-date-order` + cross-referencing commit messages
  against phase labels.** Evidence was scattered — the team-lead claim was in
  my spawn prompt, the correction was in `impl-vision-audit.md` §"Post-ship
  clarification", the parallel-commit race was in `impl-context-roadmap.md`
  friction point #3 AND `impl-distill-multi.md` friction point #3 AND
  `audit-smoke-pr.md` friction bullet #2. Three agents independently reported
  the same git-add-scope failure on commit `216169c`. The triangulation was
  useful (strong signal) but also noisy — agents are duplicating retro work
  because there's no shared retro-capture surface during the run.
- **No standardised friction-note schema.** Each agent wrote its own shape —
  some used H2 sections, some used frontmatter, some used numbered lists,
  some used tables. I can still pattern-match across them but a minimal
  enforced schema (`what_worked`, `friction[]`, `handoff_signals`, `retro_flags`)
  would let me diff agents mechanically.
- **No direct way to cite a specific prompt line.** The brief asked for
  "PROPOSED REWRITE with Current / Proposed / Why", and I had to grep
  `plugin-kiln/skills/kiln-build-prd/SKILL.md` by hand to find the exact
  text. A convention like "quote the SKILL.md anchor line number" in agent
  notes would have let me lift Current text without greppage.

## Claims I could not fully verify

- **`KILN_TEST_FORCE_WEBFETCH_FAIL=1` env var as the fix for T031 race.** I can
  confirm the race is real (impl-vision-audit item 3) but I can't confirm the
  proposed env-var is the right fix without reading the kiln-test harness
  source. The issue lists it as a proposal, not a solution.
- **Whether the malformed-YAML stderr warning is a ≥1 % compliance gap or a
  <1 % nit.** audit-quality deducted 1 % for it; I took that at face value.

## Scope

- Did not write any code. Only wrote: this note, one GitHub issue, task
  status transitions. Per brief.

## Time in retro

~20 minutes across: gate check (1 min), read 6 friction notes + 2 audit
reports (6 min), verify 216169c claim via `git log` (2 min), pattern-match
retro items across notes (3 min), write GitHub issue (7 min), write this
note + close task (1 min).
