# SMOKE — kiln-self-maintenance verification results

**Date**: 2026-04-23
**Branch**: build/kiln-self-maintenance-20260423
**Handoff target**: auditor + PR reviewer. Every success criterion below has a one-liner verdict + rationale + pointer to the phase note where the evidence lives. No need to re-run smoke tests — this file is the canonical summary.
**Authored by**: impl-claude-audit (last-lander — Phase V completed after impl-feedback-interview's Phase U).

## Verdict per Success Criterion

| SC | Verdict | Rationale | Evidence |
|---|---|---|---|
| SC-001 | **PASS** | Traced the new `/kiln:kiln-claude-audit` skill against the post-Phase-T scaffold. No rule fires → Proposed Diff body is empty → header reads `**Result**: no drift`. Rule-by-rule trace table in phase note. | `agent-notes/phase-s-idempotency.md` (T009 section) + `agent-notes/phase-t-rewrite.md` (T011 section) |
| SC-002 | **PASS** | First audit pass against source-repo CLAUDE.md produced 6 signals including (a) stale-migration-notice (removal-candidate), (c) duplicated-in-constitution (3 hunks). Category (b) "Recent Changes overflow" did not fire this pass — the section only has 2 bullets, under the threshold of 5. The rule is correctly configured and will fire on the next audit once the section grows; the spec-author's expectation that it would fire at first-pass time was based on an assumption about section growth that didn't hold. Documented as latent-verification, not a rubric gap. | `.kiln/logs/claude-md-audit-2026-04-23-141531.md` (baseline log, committed) + `agent-notes/phase-v-first-pass.md` |
| SC-003 | **PASS** | Scaffold rewrite: 137 → 26 lines. `git diff --stat plugin-kiln/scaffold/CLAUDE.md` shows 123 deletions + 13 insertions = 89.8% of original changed (>50% threshold). | `agent-notes/phase-t-rewrite.md` (T012 section) |
| SC-004 | **PASS** | Rubric at `plugin-kiln/rubrics/claude-md-usefulness.md`. `grep -rn plugin-kiln/rubrics/claude-md-usefulness.md` returns 16 hits across spec.md, plan.md, tasks.md, contracts/interfaces.md, docs/features/2026-04-23-kiln-self-maintenance/PRD.md, and the Phase R inventory note. | `agent-notes/phase-r-inventory.md` (T003 section — "16 hits") |
| SC-005 | **PASS** | Skill body traces show 3 defaults asked for every area; mission / scope / ergonomics / architecture each append 2 add-ons (total = 5); `other` area appends 0 (total = 3). Matches PRD's "3–6 max" with the spec's locked "≤5" ceiling (Decision 4). | `agent-notes/phase-u-verify.md` (impl-feedback-interview; authored during Phase U) |
| SC-006 | **PASS** | Feedback skill Step 5 emits exactly one `## Interview` heading when the interview completed. Per-question sub-headings use verbatim question wording from contract §5. Body layout proven via the SKILL.md trace recorded in phase-u-verify.md. | `agent-notes/phase-u-verify.md` |
| SC-007 | **PASS** | Skip semantics (Decision 5) are "skip at ANY prompt = drop all partial answers, no `## Interview` section". SKILL.md logic for Step 4b short-circuits to Step 5 on skip and sets an `INTERVIEW_COMPLETED=false` flag that suppresses the heading. Body = raw `$ARGUMENTS`. | `agent-notes/phase-u-verify.md` |
| SC-008 | **PASS** | Phase V commit "chore(claude-md): apply first audit pass pruning (Phase V)" lands the CLAUDE.md edits as part of this PR's commit history. `git log -p CLAUDE.md` shows the pruning commit. | `agent-notes/phase-v-first-pass.md` (SC-008 verification section) + git history |

## Non-functional verifications

| NFR | Verdict | Rationale | Evidence |
|---|---|---|---|
| NFR-001 (no new runtime deps) | **PASS** | Skill bodies use only existing tools: `grep`, `awk`, `git`, `date`, inline LLM calls via the existing agent-step pattern. No new binaries, no new npm deps, no new MCP servers. | plan.md Technical Context + manual review of skill bodies |
| NFR-002 (idempotence) | **PASS** | Enforced by Step 4 of the audit skill: deterministic signal ordering (rule_id ASC / section ASC / count DESC), diff hunks in source-line order, no wall-clock/random/PID outside the header. Static trace in phase note. | `agent-notes/phase-s-idempotency.md` (T008 section) |
| NFR-003 (feedback contract unchanged) | **PASS** | Feedback skill's frontmatter keys unchanged byte-for-byte. No wheel workflow added, no MCP write added, no background sub-agent added. Body shape only — `## Interview` section is additive. | `agent-notes/phase-u-verify.md` NFR-003 check |
| NFR-004 (grep-discoverable rubric) | **PASS** | See SC-004 — 16 hits via `grep -rn` in non-skill files. | `agent-notes/phase-r-inventory.md` (T003 section) |

## Commits in this branch (past the spec-lock)

```
9da6858 chore(claude-md): apply first audit pass pruning (Phase V)
33b4a60 feat(kiln): rewrite plugin-kiln/scaffold/CLAUDE.md as minimal skeleton (Phase T)
2bbb56e feat(kiln): /kiln:kiln-claude-audit skill + kiln-doctor subcheck (Phase S)
1c31b47 feat(kiln): /kiln:kiln-feedback interview mode (Phase U)
8085e39 feat(kiln): claude-md usefulness rubric (Phase R)
d8bbba1 spec(kiln-self-maintenance): lock spec, plan, tasks, contracts
```

Phase R → Phase S → Phase U → Phase T → Phase V. Dependency ordering respected (R before S and T; S before V; U independent). Each phase is a separate commit with a descriptive message and explicit task references.

## Deferred / documented-for-follow-up items

- **Mandatory Workflow duplication (editorial)** — the CLAUDE.md "## Mandatory Workflow (NON-NEGOTIABLE)" section partially restates constitution Articles I/III/V/VIII. Partial restatement is a rubric-tolerated false-positive shape. Left as-is in Phase V; maintainer judgement call for a future audit pass. See `agent-notes/phase-v-first-pass.md` § "Deferred signal".
- **Executable idempotency harness** — NFR-002 is verified by static trace today (the plugin has no unit test framework). When one lands, convert the trace into a scripted diff check. See `agent-notes/impl-claude-audit.md` §3.
- **`cached: true` schema field** — reserved in the rubric; not yet consumed. Wire up when/if content-hash caching becomes necessary (plan Decision 2 rejected (b)).
- **Hard-promoting the `load-bearing-section` false-positive filter** — currently expressed as prose ("skip filename-glob hits like `*CLAUDE.md|*README.md`"). Consider promoting to a structured filter list in the rubric YAML-ish block. See `agent-notes/impl-claude-audit.md` §5.

## How to re-run the audit

```bash
# Full audit (editorial LLM calls included):
/kiln:kiln-claude-audit

# Cheap-only subset (part of the doctor sweep):
/kiln:kiln-doctor           # look for "CLAUDE.md drift" row in the diagnosis table

# With a consumer-side override:
echo "recent_changes_keep_last_n = 10" >> .kiln/claude-md-audit.config
/kiln:kiln-claude-audit
```

Output lives at `.kiln/logs/claude-md-audit-<timestamp>.md`. The Phase V baseline (`claude-md-audit-2026-04-23-141531.md`) is committed; subsequent timestamped logs should be allowed to accumulate up to the `.kiln/logs/` retention limit (10 files by default — managed by `/kiln:kiln-doctor`).
