# Retrospective — pipeline-input-completeness

**Branch**: `build/pipeline-input-completeness-20260423`
**Date**: 2026-04-23
**Role**: Task #4 — retrospective
**PR**: https://github.com/yoshisada/ai-repo-template/pull/146

## Summary

Clean 3-agent pipeline (specifier → implementer → auditor). Two surgical bug fixes across one mostly-SKILL.md surface (`kiln-build-prd` Step 4b) and one wheel-workflow surface (`shelf-write-issue-note`), with a new portable helper script (`plugin-shelf/scripts/parse-shelf-config.sh`). 11 tasks, 5 phases (A/B/C/E/F; D dropped by specifier per Decision 2). PRD→Spec 8/8, Spec→Code 8/8. One contract-drift blessed inline by the auditor (CRLF-strip ordering in the `.shelf-config` parser) — **the second consecutive pipeline to exercise the R-1 "bless inline" precedent**.

The PRD was unusually implementation-ready: all 8 FRs had matching SCs, source issues cited concrete file paths + PR numbers, and the "Risks & Open Questions" section pre-enumerated the three decisions plan needed to lock. Specifier answered them in the plan; implementer followed the plan without drift; auditor confirmed end-to-end. No implementer needed to be split — the scope was right-sized for one.

## What worked well (with evidence)

### W-1 — Specifier pre-scoped the shelf-skill sweep to zero, and it held
Decision 2 in plan.md capped FR-008's sweep at zero additional shelf skills. `git diff main -- plugin-shelf/skills/` returned empty at audit time (commit `f9adda7`). The specifier did the legwork upfront (`_read_key` usage audit across all shelf skills); the implementer skipped Phase D entirely without scope-creep risk. **Pattern**: when a sweep FR is suspected to have zero additional surface area, specifier should enumerate + cap upfront rather than letting implementer discover the envelope mid-implementation.

### W-2 — Diagnostic-output-as-structural-prevention paid off during iteration
FR-003 + FR-005's six-field diagnostic line (`scanned_issues/scanned_feedback/matched/archived/skipped/prd_path`) isn't just ceremonial — the implementer's §5.2 fixture run caught a would-have-been-silent `./` leading-dot normalization case that the `.kiln/issues/`-only pre-fix would have skipped (implementer.md §1, commit `8b8b093`). The pre-emptive six-field width (not just `matched=N`) means future leaks are self-diagnosing: `scanned_issues=0` says "glob is broken," `skipped=N>0` says "frontmatter malformed," `archived≠matched` says "mv failed." **Pattern**: when adding a diagnostic line as a structural prevention, width it for the failure modes you're closing, not just the happy path.

### W-3 — "Same-failure-shape" bundling worked for the PRD narrative
Two unrelated bugs (Step 4b feedback scan + `shelf-write-issue-note` config read) shared the failure shape "skill ignores available input." The PRD held them in a single narrative without strain — one spec, one plan, 11 tasks split cleanly into A/B (bug 1) + C (bug 2) + E/F (smoke + verify). **Pattern**: distill can theme by failure shape, not just by affected surface. Two bugs with the same diagnostic lineage ("we wrote this input, and the consumer dropped it") are more cohesive than two bugs on the same surface with different failure modes.

### W-4 — Contract-drift-bless-inline pattern is stable (2× observed)
Second consecutive pipeline where the auditor used the R-1 "strict behavioral superset" blessing: kiln-structural-hygiene blessed a BSD-portable `find` refactor (P-1); this pipeline blessed a CRLF-strip ordering hoist. Both shared the same shape — implementer caught a contract edge-case during smoke, refined the pipeline, auditor recognized the refinement as a superset and blessed inline with documented precedent. **Pattern**: R-1 "strict behavioral superset" blessings are becoming a stable mechanism for absorbing small implementer refinements without triggering a contract amendment round-trip. Auditor brief should explicitly list it.

### W-5 — Single-implementer sizing was right
11 tasks / 5 phases / ~6 commits of implementation. The auditor had nothing blocked, no file overlaps, no re-work. For a 2-bug PRD where both bugs touch different surfaces but share a theme, 1 implementer is the right split. Splitting into 2 would have been pure coordination overhead.

## What was painful

### F-1 — PRD called `shelf-write-issue-note` a "skill"; it's a workflow JSON
The PRD body and the source issue both referred to "the `shelf:shelf-write-issue-note` skill." No such skill exists — it's a wheel workflow at `plugin-shelf/workflows/shelf-write-issue-note.json`. Specifier had to grep to find the actual file; ~1 min of confusion but the signal is real: the "skill" vs "workflow" vs "script" distinction is semantic (different directories, different mutation patterns, different audit grep targets). See prompt-rewrite PR-1 below.

### F-2 — Auditor brief referenced a non-existent path
Team-lead's audit checklist pointed grep gates at `plugin-shelf/skills/shelf-write-issue-note/SKILL.md` — the same phantom path from F-1. Auditor noted this and correctly cross-checked against `tasks.md` (which had the right workflow-JSON path). Minor but avoidable; downstream effect of F-1.

### F-3 — Contracts §3 pseudocode mis-ordered `\r`-strip against the CRLF+quoted-value case
The contract specified `tr -d ' \t\r'` as the final pipeline stage. Implementer caught during §5.2 smoke that trailing `\r` sat between the closing quote and EOL, so `sed -E 's/^"(.*)"$/\1/'` never matched (the `$` anchor missed). Hoist to `tr -d '\r'` first fixed it. Auditor blessed inline per R-1. **This is the second contract-drift-bless-inline in two pipelines** — stable enough to codify in the auditor brief (see PR-2), but also a signal that contract authors should test pseudocode against edge inputs (CRLF, blank lines, comment lines) before freezing. See PR-3.

### F-4 — SMOKE.md is documentary-only for the 4th pipeline in a row
kiln-self-maintenance, kiln-claude-audit, kiln-hygiene, kiln-structural-hygiene, and now pipeline-input-completeness all ship SMOKE-style fixture docs with copy-pasteable assertions but no executable harness. §5.4/§5.5 in this PRD could only be verified structurally (parser unit + agent-instruction grep); full end-to-end verification deferred to the next `/kiln:kiln-report-issue` post-merge. Retros #142 (kiln-self-maintenance) and #145 (kiln-structural-hygiene) both flagged "executable skill-test harness" as a follow-on. **No `.kiln/issues/` entry exists yet**. Signal has accumulated past "file a backlog entry" into "overdue PRD-worthy." See follow-on O-1.

### F-5 — Step 4b's markdown body doesn't have stable sub-step anchors
Step 4b is one ~100-line bash block inside a larger SKILL.md. If a future PRD wants to amend only step 3 of the block, it has nothing to anchor against besides line numbers, which drift on every edit. Specifier flagged F-002; no amendment attempted this pipeline. Low-priority but it will bite again. See PR-4.

## Specific prompt rewrites (proposals — not applied this pipeline)

### PR-1 — Distill + kiln-create-prd should label shelf/kiln references as skill vs workflow vs script

| Field | Value |
|---|---|
| **File** | `plugin-kiln/skills/kiln-distill/SKILL.md` (Step 4 "Generate the Feature PRD") and/or `plugin-kiln/skills/kiln-create-prd/SKILL.md` |
| **Current** | PRDs render source-issue references as free-form text ("the `shelf:shelf-write-issue-note` skill") without validating the type of the referenced artifact. |
| **Proposed** | Before finalizing PRD text, for each `shelf:<name>` / `kiln:<name>` reference in the body, verify whether the named target resolves to `plugin-<plugin>/skills/<name>/SKILL.md`, `plugin-<plugin>/workflows/<name>.json`, or `plugin-<plugin>/scripts/<name>.sh`. Replace the generic "skill" with the precise type in PRD copy: "the `shelf:shelf-write-issue-note` workflow (`plugin-shelf/workflows/shelf-write-issue-note.json`)". If none resolves, flag a clarification before proceeding. |
| **Why** | F-1: skill vs workflow vs script is semantically meaningful. Different directories, different mutation patterns, different audit grep targets. Specifier + auditor both hit the same phantom-path problem (F-1, F-2) because the PRD was imprecise. Precision here prevents both. |

### PR-2 — Auditor brief should explicitly list "strict behavioral superset" blessings as a permitted resolution

| Field | Value |
|---|---|
| **File** | `plugin-kiln/agents/prd-auditor.md` (or wherever auditor brief lives), and `plugin-kiln/skills/kiln-build-prd/SKILL.md` Step 5 (auditor task brief) |
| **Current** | Auditor brief describes gap-discovery + blocker filing but doesn't explicitly describe the "bless inline" mechanism for implementer refinements that are strict supersets of the contract. |
| **Proposed** | Add a numbered subsection: "If implementation diverges from a contract pseudocode and the implementer's version is a strict behavioral superset (handles every input the contract handles correctly + handles additional edge cases the contract mis-handles), you MAY bless inline with: (a) a one-paragraph note in the audit PR body citing this precedent, (b) an `agent-notes/auditor.md` entry explaining the superset relationship, (c) NO blocker filed. Recent precedents: kiln-structural-hygiene R-1 (BSD-portable `find`), pipeline-input-completeness R-1 (CRLF-strip hoist)." |
| **Why** | W-4: 2 pipelines have now exercised this pattern. Codifying it in the brief reduces uncertainty for future auditors (is this a blocker, or is it in-scope to bless?) and makes the precedent discoverable rather than oral tradition. Not risky — both instances caught real contract under-specification that a strict-equality check would have blocked unnecessarily. |

### PR-3 — Contract pseudocode for shell pipelines should cite edge inputs it was tested against

| Field | Value |
|---|---|
| **File** | `plugin-kiln/skills/kiln-plan/SKILL.md` contracts section (or templates/contracts template if one exists) |
| **Current** | Contracts render bash pseudocode as illustrative, without enumerating inputs the author tested against. |
| **Proposed** | When a contract specifies a pseudo-shell pipeline (sed/tr/awk chains), require a trailing "Tested-against:" line enumerating the edge inputs validated: `# Tested-against: LF-only, CRLF, quoted-value, CRLF+quoted-value, comment-line, blank-line, key-only-no-value`. If the author hasn't tested CRLF+quoted-value (the F-3 case), they'd notice when writing the line. |
| **Why** | F-3: the CRLF+quoted-value case was exactly what contracts §3 mis-ordered. A lightweight "what did you test against?" discipline at contract-authoring time would have caught it before the implementer needed to hoist. Costs ~1 line per pseudocode block. |

### PR-4 — Multi-step skill bodies should use stable `#### Step N.M` sub-headings

| Field | Value |
|---|---|
| **File** | `plugin-kiln/skills/kiln-build-prd/SKILL.md` Step 4b + any other Step body longer than ~50 lines |
| **Current** | Step 4b is one monolithic bash block under a single `### Step 4b` heading. |
| **Proposed** | Split long bash bodies into sub-sections with `#### Step 4b.1 — Normalize PRD path`, `#### Step 4b.2 — Scan issues + feedback`, `#### Step 4b.3 — Archive matches`, `#### Step 4b.4 — Emit diagnostic + commit`. Future PRDs can anchor patches to a specific sub-step without line-number drift. |
| **Why** | F-5: specifier flagged this (F-002 in specifier.md) as "low for this PRD, medium long-term." Deferring again is cheap; doing it once as a cleanup PR is also cheap. Recommend a future cleanup PRD that touches multiple long Step bodies in one pass. |

## Preservable patterns (codified)

### PP-1 — Specifier's "enumerate-and-cap" for suspected-empty sweep FRs
When a PRD names a sweep-style FR (FR-008 this pipeline: "also fix any other shelf skill with the same issue"), specifier should grep/read every candidate surface upfront in the plan-phase and pin the decision (`Decision 2: zero additional surfaces in scope`). Implementer then skips the corresponding phase entirely. Alternative — "implementer discovers the envelope" — risks mid-pipeline scope creep. This pipeline's `git diff main -- plugin-shelf/skills/` confirms the cap held.

### PP-2 — Diagnostic-output-as-structural-prevention, widened for failure modes
A diagnostic line added as a structural prevention (FR-003 + FR-005) should expose EVERY failure mode you're closing, not just the happy path. Six fields (`scanned_issues/scanned_feedback/matched/archived/skipped/prd_path`) let the NEXT debugger auto-classify any future leak on first occurrence. Pattern: when a black-box hole has leaked N times, the fix isn't just the code — it's the diagnostic that makes the next occurrence self-classifying. FR-003 was implementer-vindicated (implementer.md §1).

### PP-3 — Same-failure-shape bundling as a distill theming heuristic (NEW)
Distill can bundle unrelated bugs that share a diagnostic lineage — "consumer drops available input," "write path isn't captured in output," "duplicate detection is eager/lossy" — into one PRD without strain. This pipeline bundled feedback-scan + config-read under "skill ignores available input." Narrative held; 11 tasks split cleanly. Worth adding to distill's Step 2 theming rubric as an alternative to surface-based grouping.

### PP-4 — Contract-drift-bless-inline via R-1 "strict behavioral superset" (2× observed, stable)
Second consecutive pipeline. The mechanism: (a) implementer catches a contract edge-case during smoke, (b) refines the pseudocode order or form, (c) auditor recognizes the refinement is a strict superset of the contract, (d) blesses inline with precedent citation, no blocker filed. This pipeline cites kiln-structural-hygiene R-1 as precedent; future pipelines can cite both. See PR-2 for codification.

### PP-5 — Skill-vs-workflow-vs-script precision (NEW)
Plugin artifacts have three distinct shapes: skills (`skills/<name>/SKILL.md`, markdown prompt surfaces), workflows (`workflows/<name>.json`, wheel orchestration), scripts (`scripts/<name>.sh`, shared shell helpers). When PRD copy, tasks.md validation greps, and auditor briefs all agree on the precise type, specifier + implementer + auditor all save time. When they don't (F-1, F-2), everyone grepts their own way back. Distill and kiln-create-prd should enforce precision at authoring time (PR-1).

## Open follow-ons

### O-1 — Executable skill-test harness (4th signal, now overdue)
**Biggest open follow-on.** Four consecutive pipelines have shipped documentary-only SMOKE fixtures: kiln-self-maintenance, kiln-claude-audit, kiln-hygiene, kiln-structural-hygiene, pipeline-input-completeness. Retros #142 and #145 already flagged it. **No `.kiln/issues/` backlog item exists yet.** File one NOW via `/kiln:kiln-report-issue` or `/kiln:kiln-feedback` (this is arguably strategic feedback, not a tactical bug — "our smoke-test paradigm is slipping"). Candidate PRD scope:

- A `skill-smoke.md` per-skill convention or `.wheel/smoke/` fixture that the Claude Code runtime can replay against a skill body.
- A new `/kiln:kiln-test-skill <skill-name>` that invokes the skill against the fixture and asserts outputs.
- Retrofit to kiln-hygiene + kiln-claude-audit as the first consumers.

### O-2 — Contracts template should require "Tested-against:" for bash pseudocode
See PR-3. Small prompt tweak to plan/contracts rendering. Cost: ~1 line per block. Catches class of bugs illustrated by F-3.

### O-3 — Stable sub-step headings for long Step bodies
See PR-4. Batch as a cleanup PRD over Step 4b + any other ≥50-line Step body in `kiln-build-prd/SKILL.md`. Cheap, unblocks future surgical amendments.

### O-4 — Distill's theming rubric should include "same-failure-shape" as a grouping option
See PP-3, PR proposal implicit. Add to distill Step 2 prose: "bugs that share a diagnostic lineage (same failure-shape across different surfaces) can be theme'd together — don't require same-surface grouping."

## Pipeline-level observations

- **PRD-as-implementation-ready is possible and reproducible.** The specifier's section "What worked well" bullet 1 nails it: "Implementation-ready PRDs have enumerated FRs with matching SCs + concrete source evidence + risks-section with pre-enumerated decisions for plan to lock." Worth capturing as a PRD authoring checklist (distill + kiln-create-prd could consult).
- **Single-implementer + single-auditor is a viable small-pipeline shape.** 11 tasks and 5 phases is below the "need to parallelize" threshold. Coordinator overhead of a 2-implementer split would have eaten the savings.
- **R-1 blessings are now predictable.** 2/2 instances matched the pattern (strict superset, documented precedent, no blocker). Third instance should be no-surprise.
- **The diagnostic-as-prevention discipline is starting to look like a skill.** Three pipelines (shelf-config-artifact, kiln-hygiene, pipeline-input-completeness) have now shipped structural diagnostics that did useful work during or post-implementation. Worth a short writeup in the constitution or CLAUDE.md about when to add them.

## Verdict

**PASS**. Pipeline clean. Preservable patterns well-documented. Follow-ons filed to retrospective issue + friction note. No code changes applied this retro pass (prompt rewrites remain proposals per prior retro convention).

## Cross-pipeline signals tracked

| Signal | 1st pipeline | 2nd | 3rd | 4th | Status |
|---|---|---|---|---|---|
| Documentary-only SMOKE | kiln-self-maintenance | kiln-claude-audit | kiln-hygiene | kiln-structural-hygiene + pipeline-input-completeness | **OVERDUE** — file backlog item (O-1) |
| Contract-drift-bless-inline (R-1) | kiln-structural-hygiene (BSD find) | pipeline-input-completeness (CRLF hoist) | — | — | **Stable pattern** — codify in auditor brief (PR-2) |
| Skill-vs-workflow phantom path | pipeline-input-completeness | — | — | — | **First occurrence** — fix upstream in distill (PR-1) |

---

*File written by the retrospective prior to marking Task #4 completed, per `tasks.md` friction-note protocol.*
