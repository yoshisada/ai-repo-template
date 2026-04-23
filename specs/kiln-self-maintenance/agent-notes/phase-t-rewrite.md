# Phase T — Scaffold rewrite verification

**Date**: 2026-04-23
**Owner**: impl-claude-audit
**Covers**: T010 (rewrite), T011 (audit-clean against new rubric), T012 (SC-003 >50% changed).

## T010 — Rewrite matches contract §4

The new `plugin-kiln/scaffold/CLAUDE.md` follows the exact skeleton locked in `contracts/interfaces.md` §4:

- H1 with `{{PROJECT_NAME}}` placeholder — present at line 1.
- `## Quick Start` — two bullets (kiln-next pointer, kiln-init pointer). No session-prompt reference (the broken one was explicitly called out in plan Decision 3).
- `## Mandatory Workflow` — four numbered steps (specify / plan / tasks / implement), one-line 4-gate hook mention.
- `## Available Commands` — one-line pointer to `/kiln:kiln-next`, no enumeration.
- `## Security` — two bullets (.env + input validation).

Explicitly EXCLUDED sections (per contract §4), all removed from the previous 137-line version:
- "Implementation Rules"
- "File Organization"
- "Hooks Enforcement (4 Gates)" detail block
- "Versioning"
- Enumerated "Available Commands" list
- "PRD Audit" / "Test with Coverage Gate" / "Smoke Test" detail sections

## T011 — Audit-clean verification

Traced the new scaffold against every rule in `plugin-kiln/rubrics/claude-md-usefulness.md`. No rule fires.

| rule_id | cost | fires? | why |
|---|---|---|---|
| `load-bearing-section` | cheap | n/a | only ever emits `keep`, never drift |
| `stale-migration-notice` | cheap | no | no `> **Migration Notice**:` or `renamed from` content |
| `recent-changes-overflow` | cheap | no | section absent — rule does not fire on missing section |
| `active-technologies-overflow` | cheap | no | section absent |
| `duplicated-in-prd` | editorial | no | scaffold is pointer-style, no PRD-content duplication |
| `duplicated-in-constitution` | editorial | no | `## Mandatory Workflow` is a 4-line pointer, not a constitution paraphrase |
| `stale-section` | editorial | no | no claims about features that don't exist; all pointers resolve to skills that exist today |

Expected skill output when run against the new scaffold:

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

The `**Result**: no drift` header line matches contract §2's no-drift marker. **Audit-clean verification passes.**

## T012 — SC-003 measurement

```
$ git diff --stat plugin-kiln/scaffold/CLAUDE.md
 plugin-kiln/scaffold/CLAUDE.md | 136 ++++-------------------------------------
 1 file changed, 13 insertions(+), 123 deletions(-)

$ wc -l plugin-kiln/scaffold/CLAUDE.md
26 plugin-kiln/scaffold/CLAUDE.md
```

- Original: 137 lines.
- New: 26 lines (well within the ≤40 target).
- Changed lines: 123 deletions + 13 insertions = 136 touched lines out of 137 original.
- **Percent changed: 123/137 = 89.8%** (by deletion; 99.3% by touched-line count).

**SC-003 (>50% of original lines changed) passes with margin.**

## Notes

- The `{{PROJECT_NAME}}` placeholder is already handled by `plugin-kiln/bin/init.mjs` (confirmed in kiln-init/SKILL.md). No new scaffolding code needed.
- No session-prompt reference included (the old scaffold's `docs/session-prompt.md` reference was broken — the file doesn't exist in the scaffold and was confusing for consumers).
