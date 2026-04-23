# Retrospective friction notes — kiln-structural-hygiene

**Agent**: retrospective (Task #4) | **Date**: 2026-04-23 | **PR**: #144

## Scope

Synthesis across specifier.md / implementer.md / auditor.md + PR #144 body + 9 commits. No code changes in this pass — one GitHub issue filed with the full retrospective.

## Cross-cutting themes

### 1. The 5-decision lock held; only contract-shell drift was amended

D1 (new sibling skill) / D2 (single bulk `gh pr list`) / D3 (3-AND orphan predicate) / D4 (strict bundle-accept) / D5 (doctor 3h placement) all survived implementation untouched. The only mid-pipeline amendment was contract §6's `find -printf '%f\n'` → `find ... | sed 's:^\./::'` — an impl-level BSD/macOS portability catch, not a revision of a locked decision. This is the right resilience profile: decisions stayed load-bearing; shell incantations flexed.

### 2. Single-implementer was right-sized for 17 tasks / 5 phases

All phase commits are linear and clean (`8bd89ae` → `715ce75` → `9872f97` → `c4c3195`). No parallelization opportunity materialized — Phase C (doctor 3h) technically could have split off, but it depends on Phase A's rubric and the total task count was low enough that coordination overhead would have exceeded savings. Specifier called this correctly in specifier.md §Decisions point 3.

### 3. Rubric-first discipline paid off cleanly

Phase A (rubric) → Phase B (cheap rules) → Phase C (doctor) → Phase D (editorial merged-PRD rule) → Phase E (SMOKE + discoverability) mirrored the `/kiln:kiln-claude-audit` precedent 1:1. The implementer's lead observation ("contracts-first discipline paid off — SKILL.md was essentially transcription work once the rubric landed") is the proof. Rubric-first is now established convention for audit-shaped skills.

### 4. gh bulk-lookup strategy (D2) not exercised live

SC-002 / SC-003 / SC-008 all defer to post-merge reviewer shell. The theoretical shape is right (one `gh pr list --state merged --limit 500 …` per audit; in-memory match against frontmatter), but live behavior — `--limit 500` truncation warnings, `gh auth status` degradation, per-slug match collisions — has not been stress-tested. **Residual risk**: if a consumer repo has >500 merged PRs, the truncation notice fires but no one has seen it render in practice. Follow-on: post-merge DG validation should be considered a hard gate, not an optional check.

### 5. Bundled-accept UX (D4) not yet exercised

The strict bundle-accept prose ships but was never rendered against a real ≥2-item candidate list during implementation (SC-008's 18-item dance is deferred). No implementer friction on v1 rigidity — but also no datapoint on whether reviewers will want `--except <file>` per v2.

### 6. Propose-don't-apply is now 3 skills deep → codification candidate

Three skills now enforce "write preview, human reviews, human applies":
- `/kiln:kiln-claude-audit` (PR #141)
- `/kiln:kiln-hygiene` (this PR)
- `/kiln:kiln-fix` Step 7 reflect gate (build/fix-skill-with-recording-teams-20260420)

All three use grep gates against the same forbidden-op vocabulary (`sed -i`, `mv .kiln/...`, `git mv .kiln/...`, raw Edit/Write on `.kiln/issues|feedback`). This is enough signal to promote the pattern from "per-skill choice" to "build-prd convention for audit-shaped features." Concrete proposal: add a `propose-don't-apply.md` template under `plugin-kiln/templates/` that new audit skills reference, with a shared grep-gate stanza for spec.md SC tables.

## Preservable patterns

### P-1 — Implementer-caught contract drift resolved inline by auditor (NEW)

The BSD `find` incident is the canonical shape. Chain of events:

1. Implementer hits `find -printf` drift on macOS during Phase C.
2. Fixes it in both shipped files (SKILL.md + doctor 3h).
3. Flags it in implementer.md as "spec-contract drift: §6 still references `-printf`."
4. Auditor R-1-resolves it inline: updates contract §6 to the BSD-portable form with "semantically identical" justification, logs in `blockers.md` §Resolved.

**Why this is the right pattern**: the alternative would be a mini-amendment loop (implementer → team-lead → specifier → contract patch → implementer re-verify), which costs ~15 minutes for a zero-risk forward-fix. The auditor has full context to evaluate semantic equivalence. Constitution Article VII ("interface contracts are single source of truth") does NOT forbid auditor-driven contract edits when scoped to semantic-preserving drift.

**Codify as**: auditor agent brief should include a "resolve-or-escalate" decision rule: if contract/impl drift is semantically equivalent (verifiable by artifact grep), resolve inline and log as R-N; if it changes contract semantics or FR coverage, escalate.

### P-2 — Rubric-first sequencing for audit skills

Phase A (rubric) must ship before any rule-evaluation logic. The rubric is simultaneously (a) the spec for the predicates, (b) the versioned artifact consumers reference, and (c) the discoverability anchor (CLAUDE.md must link it — SC-001 floor). Any future audit skill should follow: rubric → skill → doctor tripwire → SMOKE → discoverability. Mirror precedent from kiln-claude-audit.

### P-3 — Doctor tripwire tier for expensive audits

Pattern: heavy audit skill (`/kiln:kiln-hygiene`, `/kiln:kiln-claude-audit`) is the 5-minute full pass; doctor subcheck (3g, 3h) is the <2s cheap-signals tripwire that tells users when to run the full thing. This keeps `/kiln:kiln-doctor` fast while preserving the deeper audit as opt-in. Budget ratio held nicely here: 0.31s measured vs 2s budget = 5.3× headroom.

## Painful spots (impl → audit → retro)

### F-1 — No lint catches contract-body / skill-body shell-snippet drift

Auditor F-1: "without implementer flagging, the `-printf` → `| sed` drift would have been invisible at artifact-grep layer." Proposed v2: cheap doctor subcheck or `/kiln:kiln-contract-lint` that greps canonical shell snippets from `contracts/interfaces.md` and asserts each one appears verbatim in the referenced skill body.

### F-2 — Grep-anchored gates are fragile against prose / error strings

Auditor F-2: `grep -c 'gh pr list' SKILL.md` = 3, not the "exactly 1" the brief predicted. Two hits were noise (quoted error string + prose guidance). The brief's gate should anchor on shell invocation shape, e.g. `grep -cE '^\s*(if !|! |)\s*gh pr list --state merged' SKILL.md` or require implementers to hide bulk `gh` calls behind a grep-anchorable function name (`fetch_merged_prs()`). Generalizes beyond this PR — every future audit brief has the same hazard.

### F-3 — Version-bump files accumulate pre-audit

Auditor F-3: 11 files staged (VERSION + 5×2 plugin manifests) arrived with the tree when audit started. These belong in the audit commit, not a chore — but the look-and-feel of "contamination" at hand-off burns a minute of auditor confidence. Cheap fix: per-phase commit hook sweeps pending auto-increments so the tree is always clean at phase boundaries.

### F-4 — Doctor subcheck lettering is non-alphabetical (3a,3b,3c,3d,3g,3h,3f,3e)

Specifier explicitly punted this to a dedicated cleanup pass. 3e being terminal (the Report block) makes this not-quite-a-mistake — but the gap between `3d` and `3g` (where did 3e go in alphabetical order?) tells you the lettering grew organically rather than being designed. Worth a dedicated cleanup pass someday; NOT worth fixing inline in any feature PR.

### F-5 — Fixtures remain documentary-not-executable (precedent-preserving)

Two consecutive audit skills (kiln-claude-audit + kiln-hygiene) now ship with README-style fixtures that have shell-runnable assertion snippets but no `harness.sh` that drives them end-to-end. Implementer notes: "the skill is invoked via `/kiln:kiln-hygiene` in the Claude Code runtime, not a standalone shell script, so a pure-bash harness would have been a poor fit." True — but the accumulating signal (3 skills deep if we count kiln-fix Step 7 reflect) suggests the executable-test-harness follow-on from retro #142 is now priority-worthy. **Recommendation**: file or bump an existing roadmap item for a Claude-Code-runtime-compatible test harness convention (e.g. a `skill-smoke.md` per-skill file that can be driven by a future `/kiln:kiln-skill-test`).

### F-6 — SC-005 self-grep trap

Implementer friction point 4: the first-pass "Rules" section literally listed forbidden patterns (`sed -i`, `mv .kiln/issues/`, …), causing SC-005's grep to match its own prohibition sentence. Rephrased to describe patterns without writing them literally. Worth capturing as a pattern-writing tip in any future propose-don't-apply template: **describe the prohibition; don't transcribe the forbidden tokens.**

## Specific prompt rewrites

### PR-1 — Auditor brief: grep gates must anchor on shell invocation shape

| Field | Value |
|---|---|
| **File** | `plugin-kiln/skills/kiln-build-prd/SKILL.md` (auditor brief section) — or wherever bulk-call grep assertions are named |
| **Current** | "Assert exactly 1 `gh pr list` invocation in skill body" (pseudo-example) |
| **Proposed** | "Assert exactly 1 shell invocation of `gh pr list --state merged`; use `grep -cE '^\s*(if !|! |)\s*gh pr list --state merged' <file>` or require the call to live behind a named shell function (`fetch_merged_prs()`) that the grep can anchor on." |
| **Why** | Auditor F-2: bare-substring grep matched 3× (1 real call + 1 error string + 1 prose note), costing ~3 minutes to read each match. Shell-shape anchoring makes the gate deterministic. |

### PR-2 — Specifier / contracts guidance: BSD-portability by default

| Field | Value |
|---|---|
| **File** | `plugin-kiln/templates/plan-template.md` or `plugin-kiln/templates/contracts/interfaces-template.md` (wherever shell snippets are authored) |
| **Current** | No explicit portability convention; GNU-ism `-printf` slipped through contract §6. |
| **Proposed** | Add a "Shell portability" stanza: "All shell snippets in this contract must run unmodified on BSD find / BSD sed / macOS-default tools. GNU-only idioms (`find -printf`, `sed -i ''` quirks, `grep -P`) must be flagged and rewritten to POSIX-portable form. If a GNU idiom is unavoidable, explicitly document the hard dependency and gate on `command -v gfind` or similar." |
| **Why** | Implementer caught this during Phase C; auditor resolved inline as R-1. Preventing the drift at contract-authoring time is cheaper than catching it at implementation time. |

### PR-3 — Auditor brief: resolve-or-escalate decision rule for contract drift

| Field | Value |
|---|---|
| **File** | `plugin-kiln/skills/kiln-build-prd/SKILL.md` (auditor phase instructions) |
| **Current** | No explicit rule for what the auditor should do when implementer flags contract/impl drift. Ambiguity invites either over-escalation (mini-amendment loops) or under-action (silent drift). |
| **Proposed** | "When implementer flags contract/impl drift (or audit grep detects it): if the change is semantically preserving (verifiable by artifact grep — same output shape, same exit codes, same FR coverage), resolve inline. Log as `R-N` entry in `blockers.md`. If the change alters contract semantics, FR coverage, or interface signatures, escalate to specifier as a mini-amendment." |
| **Why** | P-1 above. Codifies the successful R-1 pattern this pipeline produced. |

### PR-4 — Propose-don't-apply template

| Field | Value |
|---|---|
| **File** | New: `plugin-kiln/templates/propose-dont-apply.md` |
| **Current** | Each audit skill re-derives the pattern from prior precedent (kiln-claude-audit → kiln-hygiene copy-paste). |
| **Proposed** | Single shared template defining: (a) the propose-don't-apply prose to include in the skill body, (b) the SC-005-style grep gate stanza `grep -nE '(Edit\|Write\|sed -i\|perl -i\|git mv\|^mv)\s.*\.kiln/(issues\|feedback)'`, (c) the anti-pattern warning ("describe the prohibition; don't transcribe the forbidden tokens"), (d) the "write preview to `.kiln/logs/<skill>-<ts>.md`" output convention. |
| **Why** | Pattern is now 3 skills deep (claude-audit, hygiene, fix Step 7). Shared template prevents drift and makes the 4th skill cheaper to author. |

## Open follow-ons

1. **Post-merge DG validation as hard gate** — DG-1/2/3/4 in PR #144 body are currently optional checkboxes. Given that D2 (`gh` bulk-lookup) has never been exercised live, these should be a hard merge gate, not an optional polish pass. (Not a blocker for #144 merge — but something the build-prd convention should call out for future audit-shaped PRs that defer SC smoke to live env.)
2. **Executable skill-test harness** (F-5 / reto #142 follow-on) — signal now strong enough to prioritize; file as `.kiln/issues/` entry.
3. **Doctor subcheck lettering cleanup** (F-4) — dedicated PR someday, not tied to any feature work.
4. **`/kiln:kiln-contract-lint` or doctor subcheck** (F-1) — greps canonical shell snippets from `contracts/interfaces.md` and asserts verbatim presence in referenced skill bodies.
5. **Per-phase commit hook version-bump sweep** (F-3) — cheap rubric polish.
6. **Grep-gate anchoring convention** (PR-1) — implementers should hide bulk external-API calls behind named functions to make the audit grep deterministic.

## Compliance summary

- Task #1/2/3 completed, TaskList verified.
- All 3 agent-notes read; PR #144 body + 9 commits read; blockers.md read.
- Themes cross-checked against team-lead's 4 pre-surfaced friction signals. All 4 preserved in this note (BSD find → P-1, fixtures documentary → F-5, doctor ordering → F-4, propose-don't-apply 3-deep → PR-4).
- No code commits applied from this retro pass. Prompt rewrites PR-1..4 are proposals only; implementing them is a separate follow-on.

## Links

- PR: https://github.com/yoshisada/ai-repo-template/pull/144
- PRD: `docs/features/2026-04-23-kiln-structural-hygiene/PRD.md` (if present) or `.kiln/feedback/…` source
- Spec: `specs/kiln-structural-hygiene/`
- Blockers (auditor-resolved R-1): `specs/kiln-structural-hygiene/blockers.md`
