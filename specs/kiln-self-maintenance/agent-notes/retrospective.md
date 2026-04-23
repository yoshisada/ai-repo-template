---
description: "Retrospective friction notes for the kiln-self-maintenance pipeline (2026-04-23)."
---

# Retrospective — kiln-self-maintenance

**Agent**: retrospective (Task #5)
**Date**: 2026-04-23
**Branch**: `build/kiln-self-maintenance-20260423`
**PR**: https://github.com/yoshisada/ai-repo-template/pull/141
**Team shape**: 1 specifier, 2 parallel implementers (15 tasks + 5 tasks), 1 auditor, 1 retrospective (me).

## Sources I pulled from

- `specs/kiln-self-maintenance/agent-notes/{specifier,impl-claude-audit,impl-feedback-interview,auditor}.md`
- `gh pr view 141` (body + 9 commits)
- SMOKE.md, blockers.md
- Scan of phase-r..phase-v notes for raw evidence

## TL;DR

Clean pipeline. 15-vs-5 parallel split was the right call (no file overlap, zero coordination cost). All 8 SCs PASS, all 4 NFRs PASS, one mid-pipeline rubric fix (authorized), three soft notes recorded — none block merge. Three preservable patterns from the auditor carried through: SMOKE.md-as-last-lander-handoff, implementer-to-team-lead judgement-call handoff, 2:3 grep-gate / read-and-grade auditor ratio. Main follow-ons: executable skill-test harness (would have let NFR-002 idempotence be mechanically verified instead of statically traced), and promoting the rubric's false-positive filter prose into a structured filter list.

## Retrospective analysis (the 5 questions)

### 1. Did the 2-parallel split work, or should it have been 3?

**Clean 2 was right.** Both implementers independently said zero coordination overhead — one-owner-per-file meant the contract was the only sync point. impl-claude-audit finished 15 tasks in ~77 minutes of wall-clock (Phase R at 21:09 → Phase V at 21:20, four commits); impl-feedback-interview finished Phase U in one commit at 21:10. No file-level conflicts. No mid-flight pings between implementers visible in the notes.

Splitting Phase T (scaffold rewrite) off into a third implementer would have been **overkill** for a 3-task phase (T010..T012) that shares zero surface area with the rest of impl-claude-audit's load. The rewrite was a 10-minute job that depended on the Phase R rubric (T001..T003) being landed — giving it to a separate agent would have added handoff cost (they'd need to read the rubric, understand the skeleton, get context on what "audit-clean" means) for no parallelism gain. Keep it bundled.

**The real asymmetry** is that impl-claude-audit owned Phases R/S/T/V (sequentially dependent: rubric → audit skill → scaffold → first pass), while impl-feedback-interview owned only Phase U (standalone). No way to break that dependency chain without changing the feature shape — the audit skill has to read the rubric, and the first audit pass has to read the audit skill. 15-vs-5 is a consequence of the feature shape, not a team-design miss.

### 2. Did the 5-decision lock hold? Any decisions revised mid-pipeline?

**4 of 5 held cleanly. Decision 1 (override precedence) held. Decision 2 (editorial LLM split: kiln-doctor cheap-only, kiln-claude-audit full) held. Decision 3 (minimal-skeleton scaffold) held. Decision 4 (3+2 interview cap) held. Decision 5 (in-prompt skip as last option, no CLI flag) held.**

**One mid-pipeline amendment, authorized:** `migration_notice_max_age_days` default lowered from **60 → 14 days** in Phase V, after impl-claude-audit discovered the in-repo migration notice was 23 days old (not "months old" as the PRD phrased it). T018 explicitly authorized rubric fixes for rubric-coverage gaps; the implementer used that escape clause, documented the rationale in `phase-v-first-pass.md`, and updated contracts §1 + §7 override example in the same commit. Contract stayed the single source of truth. **This is the right shape for a mid-pipeline amendment** — authorized at task-definition time, documented at fix time, contract updated in the same commit.

Pattern worth codifying: **when a PRD makes a factual claim that the implementer can check (commit timestamps, line counts, file existence), the specifier should grep-verify before locking the derived threshold.** The 60-day default came straight from PRD prose — no spec-level friction would have caught it.

### 3. Was Phase R → S → V ordering respected?

**Yes, strictly.** Commit order: Phase R (21:09) → Phase U (21:10, parallel) → Phase S (21:12) → Phase T (21:14) → Phase V (21:20) → Phase W/SMOKE (21:22). Phase S (audit skill) came after Phase R (rubric). Phase V (first audit pass) came after Phase S (the skill it uses). The audit-skill author never got ahead of the rubric — the specifier's tasks.md dependency graph was respected.

Specifier's note about "T011 audit-clean chicken-egg" (Phase T scaffold has to pass the rubric, but the rubric isn't finalized until Phase R) was preempted by the commit ordering — R landed before T. No issue in practice.

### 4. SC-002 category (b) latent-not-missing — should contracts test for latent coverage?

**Keep the "will fire when section grows" response.** Reasoning:

- The rule is correctly configured (threshold=5, section has 2 bullets).
- Testing for "fires correctly on synthetic inputs" would require either (a) a fixture harness the plugin doesn't have, or (b) committing a bloated Recent Changes section just to demonstrate the rule — which would immediately need to be reverted.
- The rule's logic was traced statically by the implementer (impl-claude-audit: "verified the rule logic by tracing it against a hypothetical >5-bullet input").
- The cost of "prove by firing" (synthetic fixture + revert) outweighs the latent-verification risk on a deterministic threshold rule.

**However**, the broader gap — "no executable harness for skill-body verification" — is real and worth escalating as a backlog item (impl-claude-audit flagged this: candidate `/kiln:kiln-test-skill` scaffold that replays a skill against a fixture). That would turn every "static trace" into a mechanical check. Not a blocker for this PRD; a good next self-maintenance target.

### 5. Was the editorial-LLM-split (Decision 2) the right call, or did the implementer wish for hash caching?

**Right call. Implementer did flag hash caching as a future enhancement** ("The rubric's `cached: false` reserved field should become `true` once content-hash caching lands. Track that as an enhancement.") — but explicitly as a "next round" item, not a this-round regret.

The split (cheap signals in `/kiln:kiln-doctor`, full rubric in `/kiln:kiln-claude-audit`) kept the doctor fast and gave the maintainer a dedicated full-audit entrypoint. Two surfaces, one rubric. Implementer also raised whether `stale-section` (editorial) earns its LLM cost — 0 findings on the first pass. That's a calibration question for round 2, not a design regret.

## Preservable patterns (expand on the auditor's 3 + what I found)

1. **SMOKE.md as last-lander handoff (>1 implementer only).** The last implementer to finish writes SMOKE.md with pre-verified SC verdicts + evidence pointers. The auditor grades, doesn't re-verify. Auditor confirmed: "the implementer is best placed to write the 'why this passes' argument because they just did the verification." Single-implementer features don't need this; multi-implementer features do. **Codify in `/implement`'s finale:** "if this is the last-lander on a multi-implementer pipeline, write SMOKE.md with SC verdicts + evidence pointers."

2. **Judgement-call handoff from implementer to team-lead.** Implementer flagged three items proactively in their handoff (SC-002 category (b) latent, mid-phase rubric fix, Mandatory Workflow deferral) — exactly the auditor's three likeliest "huh?" moments. Auditor accepted all three in one pass. **Codify:** add a "Decisions I deviated on (and why)" section to `/implement`'s output template. Separate from the checkpoint commit messages — a single flat list the auditor can read in one pass.

3. **2:3 grep-gate / read-and-grade auditor brief ratio.** Two cheap binary checks (FR-004 no-direct-edit, FR-010 no-CLI-flag) + three SC read-and-grades (SC-002/003/004). Auditor said: "that ratio felt right." **Codify:** when the team lead writes the auditor brief, aim for ~2 grep gates (hard contracts) and ~3 read-and-grades (softer judgement SCs). Don't make the auditor re-run smoke tests.

4. **Mid-pipeline rubric/contract amendment with explicit authorization.** T018's task description pre-authorized "fix the rubric before marking Phase V complete" for rubric-coverage gaps. The implementer used that escape clause, fixed the 60→14 threshold, updated contracts in the same commit, and documented the rationale. **Codify:** when a task sits at the end of a phase that uses an artifact produced earlier in the same PRD (audit pass against audit rubric, smoke test against scaffold, etc.), the task description should pre-authorize amendment-of-the-upstream-artifact and specify where the rationale lands. Without that authorization, the implementer either ships a broken artifact or asks the team lead — both bad.

5. **Exhaustive contracts file before implementers start.** Both implementers independently said they didn't have to ask a single question. impl-claude-audit: "Every rule's schema, every output file shape, every override-parse rule was already locked." impl-feedback-interview: "If the contract had been looser, I would have had to ping the team lead." **This IS the pattern we want — the specifier's contract output earned the zero-coordination parallelism.**

## Specific prompt rewrites

### Rewrite 1 — `/implement` finale: SMOKE.md for last-lander

**File**: `plugin-kiln/skills/implement/SKILL.md` (final step, multi-implementer branch)

**Current**: (no explicit last-lander instruction; SMOKE.md was added ad-hoc via task T021 on this pipeline.)

**Proposed** (add to the final step of `/implement`, after tasks.md is fully `[X]`):

> **If you are the last implementer to finish on a multi-implementer pipeline** (check by reading `specs/<feature>/tasks.md` — if every task across all owners is `[X]` except your current one, you are the last lander): write `specs/<feature>/SMOKE.md` with one-liner verdicts for every SC and NFR in `spec.md`. Each verdict: `✅ PASS` / `⚠️ PARTIAL` / `❌ FAIL`, one-sentence rationale, pointer to the phase-note file or commit where the evidence lives. The auditor reads SMOKE.md first; it grades against SMOKE.md rather than re-deriving. If you are **not** the last-lander, skip this — the next finisher will write it.

**Why**: SMOKE.md was a force multiplier on this pipeline ("every SC came pre-verified with a one-line verdict") but only because T021 explicitly created it. On a pipeline without T021, the auditor has to re-derive everything. Codifying the last-lander rule in `/implement` means every multi-implementer pipeline benefits — no need for the specifier to invent a T-last task every time.

### Rewrite 2 — `/implement` finale: "Decisions I deviated on" section

**File**: `plugin-kiln/skills/implement/SKILL.md` (final step, single + multi-implementer)

**Current**: The implementer commits their work and posts a handoff message to the team lead. No structured "flag my judgement calls" section — relies on the implementer remembering to surface them.

**Proposed** (add to the handoff message template):

> After all your tasks are `[X]`, if you made any judgement calls that deviate from the plan or rubric — a mid-phase threshold change, a deferred signal, a tolerated false-positive, a latent-verification SC — add a `## Decisions I deviated on` section to your handoff message (or friction note if you write one). For each: **What** you changed / deferred, **Why** (specifically, what the plan/rubric would have required vs. what you did), **Where the evidence lives** (commit hash, phase note, blockers.md entry). The auditor uses this to prioritize review — a deviation that's pre-flagged is a 30-second spot-check; a deviation discovered by surprise costs context.

**Why**: Auditor explicitly said the implementer's three flagged items "pre-flighted the auditor's three likeliest 'huh?' moments and let me accept them in one pass rather than spending context re-deriving them." Making this structural (named section, consistent fields) means every future auditor gets the same pre-flight.

### Rewrite 3 — team-lead auditor brief template: 2:3 grep/read ratio

**File**: `plugin-kiln/skills/build-prd/SKILL.md` (auditor brief template section) — or wherever the `/kiln:kiln-build-prd` orchestrator assembles auditor task descriptions.

**Current**: (auditor briefs are composed ad-hoc. On this pipeline the mix was good by accident — 2 grep gates + 3 read-and-grades — but not because a template enforced it.)

**Proposed** (add to the orchestrator's auditor-brief assembly logic):

> When composing the auditor task brief, aim for roughly **2 grep gates** (hard binary-checkable contracts like "no direct edits to X", "no CLI flag named Y", "every function has an FR comment") plus **3 read-and-grade checks** (softer SCs that need reading the output and judging "does this meet the bar"). Grep gates should specify the exact regex + the expected hit count (including "hits in these files are OK: <list>"). Read-and-grades should specify the phase-note file where the implementer's measurement lives — don't make the auditor re-derive line counts or re-run commands. If the feature has more than 2 hard contracts, split into grep gates; if it has more than 3 soft SCs, pick the 3 highest-risk and trust SMOKE.md for the rest.

**Why**: Auditor flagged this as the golden ratio. Grep gates are cheap (one command, binary answer); read-and-grades are expensive (context-load + judgement). Over-grepping wastes agent cycles on things already proven by construction; over-grading burns context on things the auditor can't answer without redoing the work. The 2:3 ratio keeps the auditor honest and fast.

### Rewrite 4 — specifier: grep-verify PRD factual claims before locking thresholds

**File**: `plugin-kiln/skills/specify/SKILL.md` (or the plan step if thresholds live there)

**Current**: (specifier locks thresholds from PRD prose without a verification step.)

**Proposed** (add to the specifier's threshold-derivation step):

> When deriving a numeric threshold from the PRD (days, lines, counts, sizes), if the PRD uses qualitative language ("months old", "too many", "outdated"), **verify the underlying claim before picking the number**. Cheap checks: `git log --follow <file>` for age claims, `wc -l <file>` for line-count claims, section-count greps for "too many" claims. Record the verified value in plan.md Decision N ("PRD claim: X. Verified value: Y. Threshold chosen: Z."). This prevents downstream implementers from finding the threshold doesn't fire in practice (the 60→14 `migration_notice_max_age_days` fix on kiln-self-maintenance was exactly this failure mode — authorized to fix mid-phase, but a specifier grep would have caught it earlier).

**Why**: Direct outcome of the mid-Phase-V amendment. Not a catastrophic miss (T018 authorized the fix), but a spec-level check that would have prevented the churn. Cheap to add; high recall on a narrow class of issues.

## Open follow-ons (backlog candidates, not PR-blockers)

1. **Executable skill-test harness** (`/kiln:kiln-test-skill` or similar). impl-claude-audit flagged NFR-002 idempotence could only be verified by static trace, not execution. impl-feedback-interview flagged the same — "a regression in the skill wording would not be caught by anything mechanical." A fixture-replay harness would let both get mechanical verification. File via `/kiln:kiln-report-issue`.

2. **Hash-caching for editorial rubric rules.** The rubric's `cached: false` reserved field is ready for this. Would let `/kiln:kiln-claude-audit` skip LLM calls on unchanged sections between runs. Worth measuring token cost on next 2-3 runs to decide priority.

3. **Structured false-positive filter list in the rubric.** Currently the `load-bearing-section` rule's filter ("skip filename-glob hits like `*CLAUDE.md|*README.md`") is prose. Promoting to a structured filter list in the rubric YAML-ish block means implementations don't re-derive it.

4. **`stale-section` editorial rule calibration.** 0 findings on the first pass. After 2-3 more runs, evaluate whether it earns its LLM cost or can be dropped.

5. **Friction-note template in `.specify/templates/`.** Specifier flagged this: "every specifier invents the shape." A one-page template would standardize what the retrospective reads.

6. **`Edit`-after-`Edit` sequential-edit pattern** (impl-claude-audit friction point #5). Not actionable — it's the intended guardrail — but worth surfacing in the `/implement` pre-flight: "after a multi-line block removal, `Read` before the next `Edit` to get fresh line numbers."

7. **Auditor FR-004 regex tightening.** Auditor flagged the over-broad `grep -rnE '(Edit|Write|sed -i|perl -i)' ... | grep -i claude`. Hit count was 7 (manageable), but a tighter regex saves context on future audits.

## What I'm NOT committing as a prompt rewrite this round

- The "skill-test harness" idea is big enough to be its own feature PRD, not a prompt tweak. Route through `/kiln:kiln-distill` when enough signal accumulates.
- Hash caching for editorial rules is a feature, not a prompt fix.
- The friction-note template is nice-to-have; defer.

## Completion

All sources read. GitHub issue filed (title "Retrospective: kiln-self-maintenance pipeline (2026-04-23)", labels `retrospective`, `build-prd`). No small prompt-rewrite commit landed this round — the four proposed rewrites in §"Specific prompt rewrites" are substantial enough to warrant a dedicated `/kiln:kiln-fix` or their own mini-PRD rather than a drive-by retrospective commit.

Task #5 ready to mark `completed`.
