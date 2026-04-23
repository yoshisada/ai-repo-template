# Phase U — Interview Mode Verification

**Owner**: impl-feedback-interview
**File under test**: `plugin-kiln/skills/kiln-feedback/SKILL.md`
**Date**: 2026-04-23

Verification is a manual walkthrough of the skill body. There is no unit test harness; the skill is executed by Claude reading the Markdown and running the steps. These paths simulate that execution against the current skill text.

## SC-005 — Interview runs by default (5-question path, non-`other` area)

**Input**: `/kiln:kiln-feedback "We should evaluate splitting kiln into separate PRD-authoring and implementation plugins."`

**Expected walk**:
1. Step 1: `$ARGUMENTS` non-empty → continue.
2. Step 2: slug = `we-should-evaluate-splitting-kiln-into` (truncated to ~6 words).
3. Step 3: `REPO_URL` from `gh repo view`.
4. Step 3b: no file paths in description → `files:` omitted.
5. Step 4: classify `severity = medium`, `area = architecture` (structural boundary — plugin shape). Unambiguous → no classification prompt.
6. Step 4a: interview offer — skip option presented as last option.
7. Step 4b: asks Q1, Q2, Q3 verbatim from §5 defaults.
8. Step 4b: `area = architecture` → dispatcher asks Qa = `What structural boundary or plugin shape does this change?` and Qb = `What does the rollout look like — one PR, staged, or a migration?`.
9. Question count: 3 defaults + 2 add-ons = **5**. Matches Decision 4 cap.
10. Step 5: writes frontmatter + `$ARGUMENTS` + `## Interview` heading + 5 `### <question>` sub-headings with answers.

**Assertion**:
- `grep -c '^## Interview$' <file>` = **1** (SC-006 invariant).
- `grep -c '^### ' <file>` = **5** (one per question).

**Result**: **PASS** (walk-through matches skill body Steps 4a, 4b, 5).

## SC-006 — `## Interview` heading appears exactly once when present

Covered by the SC-005 walk (§Step 5). Body-shape rule explicitly states "The `## Interview` heading appears EXACTLY ONCE when present (SC-006 invariant)".

**Result**: **PASS**.

## SC-007 — Skip produces file with no `## Interview` section

**Input**: `/kiln:kiln-feedback "Idle thought: maybe we should rename .kiln/feedback/ to .kiln/strategic/."`

**Expected walk**:
1. Steps 1–4: same as above. Classify `severity = low`, `area = ergonomics` (workflow naming feel).
2. Step 4a: interview offer — skip option presented as last option.
3. Step 4b / Q1 prompt: user picks `skip interview — just capture the one-liner` → skill immediately ends the interview, discards any partial answers, proceeds to Step 5 with empty answer list.
4. Step 5: body-shape rule "If the interview was SKIPPED (at any prompt), the body equals `$ARGUMENTS` verbatim with NO `## Interview` section."

**Assertion**:
- `grep -c '^## Interview$' <file>` = **0**.
- File body equals `$ARGUMENTS` verbatim (shape identical to today's skill output).

**Result**: **PASS**.

## Edge case — Classification ambiguity gate still fires BEFORE interview

**Input**: `/kiln:kiln-feedback "Something feels off about how we approach things."`

**Expected walk**:
1. Step 4: `severity` and `area` both ambiguous → skill asks the user to disambiguate (existing Contract 1 gate — NOT removed).
2. Once resolved, Steps 4a/4b run as normal.

**Result**: **PASS** (Step 4's "If either classification is ambiguous, ASK" rule is preserved; interview layers on top at Step 4a).

## Edge case — `area == other` → 3 questions total

**Input**: `/kiln:kiln-feedback "General philosophical note about AI agent coordination."`

**Expected walk**:
1. Step 4: `area = other` (no fit).
2. Step 4b: asks Q1, Q2, Q3 only. Area map entry `other` is `(no add-on)` for both Qa and Qb.
3. Body: 3 `### <question>` sub-headings, no Qa/Qb.

**Result**: **PASS** (skill body: "For `area == other`, the interview is exactly 3 questions total.").

## Edge case — Blank answer handling

**Walk**:
- User hits Enter on Q1 → skill re-prompts Q1 once.
- User hits Enter again → skill records `(no answer)` as the Q1 answer and proceeds to Q2.
- Blank is NOT the same as skip — only the explicit last-option choice terminates the interview.

**Result**: **PASS** (skill body §"Blank answer handling" explicit).

## NFR-003 contracts preserved

| Contract | Pre-change | Post-change | Status |
|---|---|---|---|
| No wheel workflow invocation | ✓ | ✓ (interview runs inline in main chat — no `wheel-run`, no `shelf-sync`, no `/kiln:kiln-report-issue` pattern) | **PASS** |
| No MCP writes | ✓ | ✓ (no `mcp__claude_ai_obsidian-*` calls anywhere) | **PASS** |
| No background sync | ✓ | ✓ (no dispatch-background-sync sub-agent; no counter) | **PASS** |
| Frontmatter byte-identical | ✓ | ✓ (Step 5 frontmatter block unchanged; interview changes body only) | **PASS** |

## Summary

| SC | Status | Note |
|---|---|---|
| SC-005 | PASS | 5-question path walks cleanly; question count matches Decision 4 cap. |
| SC-006 | PASS | `## Interview` heading appears exactly once when present; invariant baked into Step 5. |
| SC-007 | PASS | Skip → body equals `$ARGUMENTS` verbatim; zero `## Interview` occurrences. |

All Phase U success criteria satisfied by the current skill body. No deferred items.
