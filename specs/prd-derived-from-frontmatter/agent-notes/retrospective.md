# Retrospective Agent Note — prd-derived-from-frontmatter

**Agent**: retrospective
**Task**: #4 — Retrospective for prd-derived-from-frontmatter pipeline
**Date**: 2026-04-24
**Branch**: `build/prd-derived-from-frontmatter-20260424`
**PR**: https://github.com/yoshisada/ai-repo-template/pull/148

## Scope of this note

This is the synthesis intended for FUTURE retrospectives to build on. Full evidence + prompt-rewrite proposals live in the GitHub retro issue. This note captures the accumulated pattern counters and the 1 new preservable pattern codified this run.

## Accumulated pattern counters (update on every run)

| Signal | Count now | First seen | Last seen | Status |
|---|---:|---|---|---|
| **O-1** executable skill-test harness gap | **4** | retro #142 | this retro | **ESCALATED** — filed `.kiln/feedback/2026-04-24-kiln-needs-an-executable-skill-test-harness.md`, severity `high`, area `architecture`. Next distill run will lead a PRD narrative with it. |
| **R-1** "strict behavioral superset" bless-inline | **3** | CRLF hoist (pipeline-input-completeness) | D-1 POSIX awk (this run) | Pattern is stable. Auditor briefing should explicitly enumerate POSIX-portability tightening as a permitted R-1 class. |
| **Same-failure-shape bundling** (single-implementer, multi-concern) | ≥2 | retro #147 | this retro (4 concerns, 13 tasks, 6 phases, 1 implementer) | Reinforced. Keep this shape for the next multi-phase refactor. |
| **Propose-don't-apply discipline** (skill never calls Edit/Write against target artifacts) | **4** | claude-audit | kiln-hygiene backfill (this run) | **Codified** as PP-6 below. |

## Preservable patterns codified

### PP-6 — Propose-don't-apply as a first-class skill shape

A skill that audits or proposes changes to repo-owned artifacts (PRDs, specs, frontmatter) MUST:

1. Write its output to `.kiln/logs/<skill-name>-<timestamp>.md` only.
2. Emit `git apply`-compatible hunks (or shell command blocks) for the maintainer to apply manually.
3. Document the invariant in prose at the top of the skill's body: **"The skill ONLY proposes a diff or a command block. It MUST NOT call the Edit/Write tools or run `perl -i` / `sed -i` / `git mv` / `git apply` against any audited file."**
4. Name the audited path classes explicitly (e.g. `docs/features/*/PRD.md`, `products/*/features/*/PRD.md`).
5. Be idempotent — running it twice produces zero new hunks for already-migrated artifacts.

**Current occurrences** (4): `/kiln:kiln-claude-audit`, `/kiln:kiln-hygiene` (default audit), `/kiln:kiln-fix` Step 7 (fix-record), `/kiln:kiln-hygiene backfill` (new this run).

**Grep gate for enforcement**: auditor greps `Edit|Write|perl -i|sed -i|git mv|git apply` against SKILL.md body and expects every hit to be prose-invariant or a write to `.kiln/logs/` or `/tmp`. This run's Grep Gate 1 validated the invariant cleanly (auditor.md lines 12–38).

## Signals that did NOT escalate this run

- **FR-005 terminology collision** (team-lead brief used "FR-005" to mean both spec-directory naming rule AND internal spec FR-005 — specifier.md lines 58–63). Resolved without blocker. Single instance — no counter yet. Track if it recurs.
- **Contracts-vs-plan POSIX tool claim drift** (plan §Architecture claims POSIX but contracts §4.2 / §5.1 used gawk-only 3-arg `match()`). Caught in Phase E via fixture run, fixed by R-1 deviation. Single instance — track if it recurs.

## What future retrospectives should watch for

1. **Does O-1 actually move after the feedback is filed?** The feedback file alone is not a fix — the signal is whether the next `/kiln:kiln-distill` run picks it up and bundles it into a PRD for `/kiln:kiln-build-prd`. If 5 retros pass without a skill-test harness PRD shipping, escalate to a direct team-lead decision.
2. **Does PP-6 hold as a 5th skill ships?** The pattern has only crystallized because 4 skills land in the same shape. Watch the 5th: if the next propose-don't-apply skill diverges (different log path, different prose, different grep gate), PP-6 needs a tightening PR.
3. **Does R-1 bless-inline show up at 4×?** If yes, rewrite the auditor brief to list POSIX-portability tightening as an explicit R-1 class rather than a precedent-by-analogy decision. Today the auditor is relying on their own memory of the prior 2 cases.
4. **Does the 3rd consumer of `read_derived_from()` emerge?** Both specifier (suggestion #1) and implementer (suggestion #2) flagged the duplication (build-prd + hygiene). A 3rd consumer (e.g. a kiln-distill validator checking `derived_from:` ↔ Source Issues drift) is the natural trigger to factor it into `plugin-kiln/scripts/lib/read_derived_from.sh`.

## Cross-references

- GitHub retro issue: filed on `yoshisada/ai-repo-template` with labels `retrospective` + `build-prd` (URL in Task #4 completion message).
- Strategic feedback filed: `.kiln/feedback/2026-04-24-kiln-needs-an-executable-skill-test-harness.md`.
- Prior retros referenced: #142, #145, #147 (exact issue numbers in the GitHub retro body — cited from team-lead brief).
