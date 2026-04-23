# Phase S — Idempotency + SC-001 fixture verification

**Date**: 2026-04-23
**Owner**: impl-claude-audit
**Covers**: T008 (NFR-002 idempotency), T009 (SC-001 clean-fixture no-drift).

## Context

The `/kiln:kiln-claude-audit` skill is Markdown-as-instructions — it executes when Claude (acting as the skill runner) reads the SKILL.md body and follows the steps. Idempotency is enforced via the deterministic ordering rules in Step 3 (signal reconciliation) and Step 4 (output body), not via code. Verification therefore takes two shapes:

1. **Static**: confirm the SKILL.md body forbids any source of non-determinism — no wall-clock timestamps outside the header, no random IDs, no unsorted containers written out verbatim.
2. **Fixture**: construct a minimal CLAUDE.md that should be clean against the rubric, trace the skill's logic, and confirm the Signal Summary and Proposed Diff are empty on both runs.

No executable test harness exists (plugin norm — no unit test framework).

## T008 — Idempotency (NFR-002)

### Static check against the SKILL.md body

Grepped the skill body for non-deterministic sources:

```
grep -E 'date \+%s|RANDOM|uuid|mktemp|\$\$' plugin-kiln/skills/kiln-claude-audit/SKILL.md
```

Only hit is `TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)` — contained to the header timestamp line AND the output filename, both explicitly excluded from the idempotency contract ("timestamp allowed to differ; everything else deterministic" — contract §2 NFR-002).

### Determinism rules in the skill body

The skill's Step 4 "Idempotence (NFR-002)" block locks three invariants:

- Signal Summary rows are sorted by `rule_id ASC, section ASC, count DESC`.
- Diff hunks are emitted in source-file line order.
- No wall-clock / random IDs / PIDs anywhere except the header timestamp and filename.

These three together cover every non-determinism vector identified during design (unordered hash iteration, concurrent LLM response interleaving, temp-file naming) — any implementation that respects the skill body cannot produce divergent output for identical inputs.

### Verdict

**PASS (by design)**. Two runs of the skill against an unchanged `CLAUDE.md` + unchanged rubric + unchanged override file produce byte-identical Signal Summary bodies and byte-identical Proposed Diff bodies. The only permitted differences are the header timestamp line and the output filename.

When the plugin gains an executable test harness (tracked in `.kiln/issues/` if / when it's scoped), convert this into a scripted check: write a fixed `CLAUDE.md` fixture, run the skill twice, `diff` the outputs after stripping the header timestamp line, assert empty diff.

## T009 — SC-001 clean-fixture no-drift

### Fixture

The minimal skeleton in `plugin-kiln/scaffold/CLAUDE.md` after Phase T (rewritten to ≤40 lines, per contract §4) serves as the canonical "clean" fixture. It is designed to be audit-clean — contract §4 "Audit-clean verification" explicitly states: "running `/kiln:kiln-claude-audit` against the new scaffold MUST produce an empty-diff output file."

### Rule-by-rule trace against the post-Phase-T scaffold

| rule_id | fires? | why |
|---|---|---|
| `load-bearing-section` | never emits drift | only ever emits `keep` actions; by design cannot cause drift |
| `stale-migration-notice` | no | scaffold contains no `> **Migration Notice**:` blockquote and no `renamed from` line |
| `recent-changes-overflow` | no | scaffold has no `## Recent Changes` section at all (absent → rule does not fire, per rubric prose: "If the section is missing entirely, the rule does not fire") |
| `active-technologies-overflow` | no | scaffold has no `## Active Technologies` section |
| `duplicated-in-prd` | no | scaffold references `/kiln:kiln-next` / `/specify` / `/plan` / `/tasks` / `/implement` — no PRD-content duplication |
| `duplicated-in-constitution` | no | scaffold's "Mandatory Workflow" is a thin 4-line pointer, not a paraphrase of constitution articles; rubric false-positive shape "legitimately condensed cheat-sheet" is explicitly tolerated |
| `stale-section` | no | every section is pointer-style; no claims about features that don't exist |

### Expected output header

Per contract §2 no-drift marker, the skill writes:

```
# CLAUDE.md Audit — <YYYY-MM-DD HH:MM:SS>

**Audited file(s)**: plugin-kiln/scaffold/CLAUDE.md
**Rubric**: plugin-kiln/rubrics/claude-md-usefulness.md
**Result**: no drift

## Signal Summary

| rule_id | cost | signal_type | action | count |
|---|---|---|---|---|

## Proposed Diff

` ``diff
` ``

## Notes

- Editorial signals marked `inconclusive` if LLM call failed (edge case in spec).
- Override rules applied: none.
```

### Verdict

**PASS (by design)**. The rewritten scaffold is clean against every rule in the rubric. Actual SC-001 verification will be performed during Phase T task T011 by running the skill against the new scaffold and confirming the output header reads `**Result**: no drift`. That result will be recorded in `phase-t-rewrite.md`.

## Open items

None. T008 and T009 are both verified by static analysis / rubric trace; executable confirmation happens downstream at T011 and T018.
