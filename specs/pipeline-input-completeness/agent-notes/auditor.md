# Auditor notes — pipeline-input-completeness

**Branch**: `build/pipeline-input-completeness-20260423`
**Date**: 2026-04-23
**Role**: Task #3 — Audit + PR

## Audit result

**PRD → Spec coverage**: 8 / 8 (100%). PRD FR-001 through FR-008 all have a matching spec FR of the same number.

**Spec → Code coverage**: 8 / 8 (100%).

| FR | Surface | Evidence |
|---|---|---|
| FR-001 | `plugin-kiln/skills/kiln-build-prd/SKILL.md` Step 4b | line 625 heading + line 634 `for f in .kiln/issues/*.md .kiln/feedback/*.md` |
| FR-002 | same file | line 662 archive loop + line 665 `orig_dir="$(dirname "$f")"` + line 667 `dest_dir="${orig_dir}/completed"` |
| FR-003 | same file | line 696 `DIAG_LINE="step4b: scanned_issues=... scanned_feedback=... matched=... archived=... skipped=... prd_path=..."` |
| FR-004 | same file | `normalize_path` helper at lines 603–620, applied at 622 (`PRD_PATH_NORM`) and 649 (`prd_norm`) |
| FR-005 | same file | line 599 `LOG_FILE=".kiln/logs/build-prd-step4b-${TODAY}.md"` + line 698 append + line 704 commit (always) |
| FR-006 | `plugin-shelf/workflows/shelf-write-issue-note.json` + `plugin-shelf/scripts/parse-shelf-config.sh` | `parse-shelf-config.sh` reads `.shelf-config` via the `_read_key`-pattern defensive parser; workflow invokes it via `${WORKFLOW_PLUGIN_DIR}/scripts/parse-shelf-config.sh` in the `read-shelf-config` step; `obsidian-write` agent composes `${base_path}/${slug}/issues/${basename}` directly |
| FR-007 | same workflow | the decision rule in `obsidian-write` §2 writes exactly `".shelf-config (base_path + slug)"` on the fast path and `"discovery (shelf-config incomplete)"` on the fallback; `finalize-result` defaults `path_source: "unknown"` when the agent fails |
| FR-008 | trivially satisfied (plan Decision 2) | `git diff main -- plugin-shelf/skills/` returns no changes — sweep confirmed zero additional skills in scope |

**SC coverage via SMOKE.md**: SC-001 (§5.1), SC-002 (§5.3), SC-003 (§5.2), SC-004 (§5.4), SC-005 (§5.5), SC-006 (§5.6), SC-007 (Phase F row + DG-5 pre-merge gate), SC-008 (the existence of SMOKE.md itself).

## Issues raised by implementer — dispositions

### 1. T03-1 task description updated to reflect extracted-script path
**Status**: in-scope. Contracts §3 lines 218–220 explicitly permit (and encourage) extracting the parser into `${WORKFLOW_PLUGIN_DIR}/scripts/parse-shelf-config.sh`. The task description update matches the code. No action.

### 2. CRLF-handling drift between contracts §3 pseudocode and `parse-shelf-config.sh`
**Contract**: `tr -d ' \t\r'` as the FINAL pipeline stage (line 175 of `contracts/interfaces.md`).
**Implementation**: `tr -d '\r'` hoisted EARLIER (before the sed quote-strip passes), with a final `tr -d ' \t'` for whitespace.

**Auditor decision**: bless the hoist inline. Precedent: `kiln-structural-hygiene` R-1 (auditor may bless implementation that is a strict behavioral superset of the contract). Rationale:

- The contract's final-stage `tr -d '\r'` is incorrect for inputs where CRLF sits between the closing quote and EOL: the sed pattern `s/^"(.*)"$/\1/` cannot match `"value"\r` because `$` anchors after the `\r`, not before the closing `"`. The implementer's hoist strips `\r` first, ensuring both CRLF-present and CRLF-absent inputs are handled.
- Behavioral supersets: every input the contract handles correctly is also handled by the hoist; some inputs the contract mishandles (CRLF-with-quotes) are correctly handled by the hoist. No regressions.
- The contract pseudocode remains the documentation of intent; the implementation's inline comment (script lines 38–45) explains the hoist rationale. No further action required on this branch. If the precedent crystallizes into a pattern, a follow-on cleanup PRD could realign contracts §3's pseudocode with the more-correct hoist form.

**Not a blocker.**

### 3. Decision 2 (zero additional shelf skills) proved accurate
**Auditor confirmation**: `git diff main --stat -- plugin-shelf/` shows modifications to `plugin-shelf/.claude-plugin/plugin.json`, `plugin-shelf/package.json`, `plugin-shelf/scripts/parse-shelf-config.sh` (new), and `plugin-shelf/workflows/shelf-write-issue-note.json` — and nothing under `plugin-shelf/skills/`. Scope matched plan. Preservable pattern: specifier's plan-phase sweep produced an accurate scope envelope, which let the implementer skip Phase D entirely without drift risk.

## Grep-gate results (literal)

```
$ grep -n '\.kiln/issues' plugin-kiln/skills/kiln-build-prd/SKILL.md
625,634,637,665,707,792  ✅

$ grep -n '\.kiln/feedback' plugin-kiln/skills/kiln-build-prd/SKILL.md
625,634,638,665,707  ✅

$ grep -nE 'scanned_issues|scanned_feedback|matched|archived|skipped|prd_path' plugin-kiln/skills/kiln-build-prd/SKILL.md
662,696,701,703  — all 6 field names appear in the Step 4b section. ✅

$ (in workflow JSON, not a SKILL.md — the shelf-write-issue-note asset is workflow-only)
$ grep -n '\.shelf-config\|base_path\|slug\|path_source\|shelf-config incomplete' plugin-shelf/workflows/shelf-write-issue-note.json
→ all patterns present. ✅

$ git diff main -- plugin-shelf/skills/
(empty) ✅  — Decision 2 scope-preserved
```

Note: the team-lead brief pointed FR-006/FR-007 greps at `plugin-shelf/skills/shelf-write-issue-note/SKILL.md`, but that path does not exist — `shelf-write-issue-note` is workflow-only (no SKILL.md). Tasks.md T03-1/T03-2/T03-3 correctly validate against the workflow JSON, and the implementation follows tasks.md. The grep gate is satisfied at the workflow-JSON layer.

## Friction notes for retrospective

- **Brief-vs-reality path mismatch**: team-lead's audit checklist referenced a `plugin-shelf/skills/shelf-write-issue-note/SKILL.md` that doesn't exist. Not a blocker — the tasks.md validation commands were correct — but worth capturing so future auditors know to cross-check against `tasks.md` when a grep path doesn't resolve.
- **Contract pseudocode vs implementer-refined pipeline order**: when the contract spec-writes bash pipelines stage-by-stage, the `tr`/`sed` order is semantically load-bearing. Contracts §3 specified the wrong pipeline order for CRLF-with-quotes inputs; the implementer correctly caught and hoisted. The precedent (R-1 blessing) worked, but a small tweak would prevent drift: future contract authors should test their pseudocode against the CRLF+quoted case before freezing it.
- **Specifier pre-scope discipline**: Decision 2 capping the sweep at zero additional skills saved the implementer a Phase D and saved the auditor a scope-creep check. Good pattern — worth preserving.

## Verdict

**PASS**. All 8 FRs covered end-to-end. SC coverage documented via SMOKE.md. No blockers. No open gaps. Proceeding to version bump + PR.
