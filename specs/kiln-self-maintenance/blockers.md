---
description: "PRD-audit blockers file for kiln-self-maintenance — none hard, three soft notes."
---

# Blockers — Kiln Self-Maintenance

**Audit date**: 2026-04-23
**Auditor**: auditor (Task #4)
**Result**: **No hard blockers**. PRD→Spec→Code→Test alignment is clean; all 11 FRs and all 8 SCs map through. Three soft notes are recorded below for maintainer judgement — none of them block merge.

## PRD → Spec → Code → Test compliance

| PRD | Spec | Code | Evidence |
|---|---|---|---|
| FR-001 | FR-001 | `plugin-kiln/skills/kiln-claude-audit/SKILL.md` + `plugin-kiln/skills/kiln-doctor/SKILL.md` Step 3g (line 160+) | SMOKE SC-001 PASS; doctor subcheck present with <2s budget wording |
| FR-002 | FR-002 | `plugin-kiln/rubrics/claude-md-usefulness.md` | File exists; audit skill resolves it at invocation (Step 1) |
| FR-003 | FR-003 | Rubric rules: `load-bearing-section`, `stale-migration-notice`, `recent-changes-overflow`, `active-technologies-overflow`, `duplicated-in-prd`, `duplicated-in-constitution`, `stale-section` | All three signal types covered (load-bearing, editorial, freshness) |
| FR-004 | FR-004 | `kiln-claude-audit/SKILL.md` "Rules" section line 234 | Grep gate PASS — zero direct-edit instructions on CLAUDE.md inside the audit skill; single line is explicit negative rule |
| FR-005 | FR-005 | `kiln-claude-audit/SKILL.md` Step 1 AUDIT_PATHS (lines 33-42) | Both source-repo CLAUDE.md and scaffold audited when run in plugin repo |
| FR-006 | FR-006 | Commit `33b4a60` | 136→13 lines, 99.3% of touched lines changed; substantive rewrite not just deletion |
| FR-007 | FR-007 | `kiln-feedback/SKILL.md` Step 4a + 4b | Inline interview; no wheel, no MCP, no background sync |
| FR-008 | FR-008 | `kiln-feedback/SKILL.md` Step 4b Q1-Q3 + area-map table | Exact wording matches contracts §5 |
| FR-009 | FR-009 | `kiln-feedback/SKILL.md` Step 5 body shape | Single `## Interview` heading, verbatim per-question sub-headings |
| FR-010 | FR-010 | `kiln-feedback/SKILL.md` Step 4a skip option | Grep gate PASS — zero `--no-interview` occurrences; only in-prompt opt-out |
| FR-011 | FR-011 | Phase V commit `9da6858` + `.kiln/logs/claude-md-audit-2026-04-23-141531.md` | Baseline audit log committed; pruning commit present |
| NFR-001 | NFR-001 | Skills use grep/awk/git/date + existing agent-step LLM pattern | No new npm deps, no new binaries, no new MCP servers |
| NFR-002 | NFR-002 | `kiln-claude-audit/SKILL.md` Step 4 + idempotence block (lines 213-220) | Deterministic sort: rule_id ASC, section ASC, count DESC; hunks in source-line order; no wall-clock/random/PID outside header |
| NFR-003 | NFR-003 | `kiln-feedback/SKILL.md` frontmatter unchanged | Body-only addition; no wheel/MCP/background-sync additions |
| NFR-004 | NFR-004 | 16 grep hits for rubric path across spec.md, plan.md, tasks.md, contracts/, PRD.md, CLAUDE.md | Discoverable from non-skill locations |

## Soft notes (not blockers)

### 1. SC-002 category (b) `recent-changes-overflow` — latent-not-missing

**What**: The first audit pass's SC-002 category (b) ("Recent Changes entries beyond threshold") did NOT fire, because the `## Recent Changes` section currently has only 2 bullets — under the threshold of 5. The SC language assumed the section would have grown past the threshold by audit time.

**Why not a blocker**: The rule is correctly configured (threshold 5, fires at count > 5). It has nothing to fire on this pass because the section is naturally groomed. SC-002 asks "does the audit catch real bloat when it exists?" — for the two present categories (a) and (c), yes. Category (b) is latent: the rule is live and will fire the first time the section grows.

**Classification**: Latent-verification, not rubric-coverage gap. Consistent with the implementer's `phase-v-first-pass.md §"SC-002 verification"` rationale. Auditor concurs.

### 2. Mid-Phase-V rubric fix (threshold 60 → 14 days for `migration_notice_max_age_days`)

**What**: During Phase V (T018), impl-claude-audit discovered the rubric's initial default of 60 days would not have fired on the in-repo Migration Notice (only 23 days old). T018 explicitly authorized "fix the rubric if a SC-002 category is missed" — so the threshold was lowered to 14 days. Rubric body, `contracts/interfaces.md` §1 and §7, and the phase note all updated consistently.

**Why not a blocker**: T018's escape clause explicitly permits this, and the PRD's "the rename is months old" was factually wrong — the cutover blockquote was actually only 23 days old, which is within the tail of a typical plugin rename window. 14 days is a defensible default that can be overridden upward (`.kiln/claude-md-audit.config`: `migration_notice_max_age_days = 90`) for genuinely long-tailed migrations.

**Classification**: Authorized rubric evolution. Auditor concurs.

### 3. Deferred `duplicated-in-constitution` signal on "Mandatory Workflow"

**What**: The "Mandatory Workflow (NON-NEGOTIABLE)" section in `CLAUDE.md` partially restates constitution Articles I/III/V/VIII. The editorial LLM flagged it; Phase V deferred the edit under the rubric's "condensed cheat-sheet" false-positive shape tolerance.

**Why not a blocker**: Partial restatement at a summary level is exactly what the rubric's `duplicated-in-constitution` false-positive note excludes — the section acts as a cheat-sheet for onboarding readers, not a mirror of the constitution. Removing it entirely would strip useful at-a-glance context. Full handling deferred to maintainer judgement in a follow-up pass. `agent-notes/phase-v-first-pass.md §"Deferred signal"` documents the three maintainer options.

**Classification**: Known rubric false-positive shape, correctly deferred. Auditor concurs.

## Verdict

**Pass.** No hard blockers. PR may proceed to the 5 deferred-gate pre-merge checklist (see PR body `## Pre-merge gates`).
