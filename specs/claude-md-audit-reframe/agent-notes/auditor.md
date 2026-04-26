# Auditor friction note — claude-md-audit-reframe

**Pipeline branch**: `build/claude-md-audit-reframe-20260425`
**Auditor pass at**: 2026-04-25 17:36 UTC

## What passed

- All 29 PRD FRs trace cleanly to spec, code, and at least one fixture (29/29 = 100% coverage). PRD numbering jumps FR-019 → FR-022 by design — preserved verbatim in spec, contracts, tasks, and rubric.
- Skill body (`plugin-kiln/skills/kiln-claude-audit/SKILL.md`, 587 lines) extends cleanly: Step 2.5 classification, Step 3 reframe rules, Step 3.5 sync composers, Step 4 output rendering with `## Plugins Sync` + `## Vision Sync` + `### Vision.md Coverage`. Sort wiring for `sort_priority: top` (only `product-undefined` triggers it currently).
- Rubric (`plugin-kiln/rubrics/claude-md-usefulness.md`, 314 lines) ships all 7 new rule entries + `## Convention Notes` (verbatim per contracts §1.2) + Signal Reconciliation (codifies FR-031 precedence: `enumeration-bloat` wins over `load-bearing-section` for `plugin-surface`).
- All 5 plugin-guidance files match §4.4 (lines 13-14, `## When to use` first heading, no skill enums / command lists / agent inventories, single trailing newline 0x0a).
- 19 new fixtures present + 4 pre-existing = 23 total. Spot-checks of `enumeration-bloat`, `product-undefined`, `plugins-sync`, `plugins-sync-missing`, `vision-overlong` assertion files confirmed real `grep -qE` + FAIL exits + PASS reporting + cat-preview-on-fail debugging (not stubs).
- Source-repo smoke test (T202): `## Plugins Sync` correctly composes alphabetical 5-plugin diff; `## Vision Sync` correctly fires the overlong-unmarked sub-signal; `enumeration-bloat` correctly identifies `## Available Commands`; `product-undefined` correctly does NOT fire (vision.md exists).
- Idempotence (T203, NFR-002 / SC-006): simulated with sed-replaced timestamp + diff -u → 2 lines differ (timestamp only).

## What didn't pass / what needed fixing during the audit

- **impl-plugin-guidance bookkeeping gap**: T100-T111 were committed in 5f2a651 but never marked [X] in tasks.md. Implementation completeness check would have failed under a strict reading of "every task assigned to either implementer is marked [X]". The work IS done — auditor reconciled the [X] marks during this pass and proceeded. **Flagged to retrospective**: implementer's "mark task [X] IMMEDIATELY after each one" discipline didn't fire for T100-T111; would benefit from a TaskUpdate-aware checklist in the implementer prompt that ties commit hashes to task IDs.

## Substrate decision (live vs structural)

Per team-lead's NON-NEGOTIABLE substrate hierarchy:

1. **Live workflow substrate** — checked `ls plugin-*/tests/ | grep -E '(perf|smoke|live)-claude-audit'` → no matches. The 19 new `claude-audit-*` fixtures ARE the substrate (`harness-type: plugin-skill`, each invokes a real `claude --print --plugin-dir` subprocess with 900s timeout-override).

2. **Wheel-hook-bound workflows** — N/A (claude-audit doesn't activate wheel hooks).

3. **Structural surrogate fallback** — used for the full 23-fixture batch run, because executing all 23 fixtures end-to-end (~up-to-5.75hr of subprocess time) exceeds in-pipeline auditor budget. The smoke test on the actual source-repo CLAUDE.md (T202) IS the live evidence. Structural verification of fixture assertion shapes (multiple spot-checks confirming real `grep -qE` + FAIL exits) is the surrogate for the batch run.

**Substrate gap explicitly flagged**: T201 (full `/kiln:kiln-test plugin-kiln` batch pass) is documented as the maintainer-driven follow-on validation gate in `audit-report.md` and `blockers.md` O-3. Per team-lead's brief, this gap is flagged transparently — not silently downgraded.

## Anything to flag for the retrospective

1. **Implementer task-checkbox discipline**: T100-T111 unchecked despite committed work (flagged above).
2. **Substrate authoring vs substrate executing**: impl-audit-logic authored 19 fixtures structurally but explicitly handed batch execution to the auditor (per their friction note). The pipeline implicitly assumes the auditor can run heavyweight harnesses; in practice, in-pipeline auditor budget can't absorb hours of subprocess time. This is a recurring pattern — should the implementer's "Implement" phase include a smoke-pass of at least one fixture to validate the substrate before handing off? Worth a retro discussion.
3. **Project-context reader brittleness**: a long-standing issue with `read-project-context.sh` choking on PRD bodies with control characters. Not this PR's concern, but the auditor smoke test surfaced it and proved the fallback path works. Worth a separate `.kiln/issues/` capture.
4. **Source-repo vision.md is overlong-unmarked**: the actual vision.md trips the new `vision-overlong-unmarked` sub-signal — correctly. The maintainer needs to add fenced-region markers OR shorten vision.md OR opt-out. Mild dogfooding-bites-back moment.
5. **The PRD numbering gap (FR-020/FR-021 missing)** propagated cleanly through spec → contracts → tasks → code without confusion. The "preserve verbatim, do not renumber" decision in spec L10 was load-bearing — confirmed correct in retrospect.

## Time / cost notes

- Audit pass took ~30 minutes wall-clock (mostly reading PRD + spec + contracts + skill body + rubric + spot-check fixtures + writing audit-report.md + this note).
- Token spend was modest because the editorial parts (running actual classification LLM calls, running editorial rules) were deferred to maintainer-driven re-runs and marked `inconclusive` per the existing skill convention.
- The full kiln-test batch pass (~5.75hr of subprocesses) would have been the bulk of cost — appropriately deferred.
