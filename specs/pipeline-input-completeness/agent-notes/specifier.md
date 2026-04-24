# Specifier — Friction Notes

**Agent**: specifier
**Pipeline**: kiln-pipeline-input-completeness
**Branch**: `build/pipeline-input-completeness-20260423`
**Date**: 2026-04-23

## Summary

Produced spec.md, plan.md, tasks.md, contracts/interfaces.md for `pipeline-input-completeness` in a single pass. PRD was unusually well-scoped — both bugs are mechanical, the FRs were already enumerated, and the success criteria were measurable as written. Most of my time went into:
1. Understanding the actual current state of `shelf-write-issue-note` (it's a wheel workflow JSON, not a `SKILL.md`), and
2. Doing the FR-008 sweep (Decision 2) to confirm zero additional shelf skills needed work.

## What worked well

- **PRD was implementation-ready.** All 8 FRs had matching SCs, source-issue evidence was concrete (4 leaked items with file paths + PR numbers), and the "Risks & Open Questions" section explicitly asked plan to confirm 3 decisions. I just had to do the legwork and answer them.
- **Existing `shelf-counter.sh` `_read_key()` is reusable.** I lifted its defensive parse pattern (`grep -E '^key[[:space:]]*=' | tail -1 | sed strip | tr -d`) directly into `contracts/interfaces.md` §3. No need to invent a new parser.
- **Step 4b is small enough to inline a contract.** The §1 bash pseudocode is ~80 lines including comments — short enough to be the literal source of truth, eliminating any "implementer interpretation" risk.

## Friction encountered

### F-001 (medium) — PRD said "shelf:shelf-write-issue-note SKILL" but it's a workflow JSON

The PRD body and source issue both refer to "the `shelf:shelf-write-issue-note` skill." There is no skill at `plugin-shelf/skills/shelf-write-issue-note/SKILL.md` — it's a wheel workflow at `plugin-shelf/workflows/shelf-write-issue-note.json`. I had to grep to find the actual file.

**Impact**: ~1 minute of confusion. Not a blocker.

**Proposed fix**: When `/kiln:kiln-create-prd` (or distill) generates PRD copy that references a "shelf skill," it should verify whether the named target is a `skills/<name>/SKILL.md` or a `workflows/<name>.json` and use precise terminology. The retro for this PRD should propose adding a verification step or a glossary clarification to `/kiln:kiln-distill` so the distinction surfaces in the PRD body.

```
File: plugin-kiln/skills/kiln-distill/SKILL.md (or wherever distill renders source-issue paths)
Current: "shelf:shelf-write-issue-note skill"
Proposed: "shelf:shelf-write-issue-note workflow (plugin-shelf/workflows/shelf-write-issue-note.json)"
Why: The "skill" vs "workflow" distinction is meaningful — they live in different directories, have different mutation patterns (markdown vs JSON), and need different audit checks.
```

### F-002 (low) — Step 4b's existing pseudocode in SKILL.md doesn't have line-numbered anchors

The PRD's bug 1 fix is "rewrite Step 4b's scan loop." The team-lead context for Step 4b is one big bash block in markdown; if a future PRD wants to amend just step 3 of the bash block, it has nothing to anchor against besides "lines 596–610 of the existing body." Re-anchoring after every edit drifts.

**Impact**: Low for this PRD (the contract pins the entire replacement body). Medium long-term if more Step 4b changes pile on.

**Proposed fix**: For multi-step skill bodies, use stable headings (`#### Step 4b.1`, `#### Step 4b.2`, …) so future edits can target a specific sub-step. Out of scope for this PRD; flag for retro.

### F-003 (low) — `read-shelf-config` step's ambiguity is a contract gap, not a bug

The original `read-shelf-config` command was `if [ -f .shelf-config ]; then cat .shelf-config; ...` — perfectly correct mechanically. The bug is that its DOWNSTREAM consumer (`obsidian-write` agent) was instructed to "parse `slug = <value>` and `base_path = <value>` (space-padded `=`)" with no defensive treatment for quoted values, CRLF, or comments — and crucially no `path_source` field to expose which branch of the parse the agent took.

So the PRD framing of "the skill walks the vault and burns list_files calls" is partly aspirational — the real bug is **observability**: callers can't tell whether the fast path or the fallback fired, and the fallback is hard-coded into the agent prompt without surfacing.

I named this in the spec ("the bug surface is in step 1 ... and step 3") but the PRD itself overstates the discovery cost. Worth raising in retro: PRD wording should match the actual code state more precisely. (Not a blocker — the FRs are correct.)

### F-004 (none, just a note) — Decision 3 retention was uncontroversial

PRD recommended default `keep_last: 10`. The hygiene audit is a downstream safety net (PR #144) — even if logs roll, the merge state is recoverable. Confirmed in plan §Decision 3. No friction.

## Open questions for the implementer

- **PR_NUMBER plumbing**: The Step 4b body assumes `$PR_NUMBER` is in scope. The `kiln-build-prd` orchestrator already plumbs this from audit-pr's task output. If the implementer finds the variable isn't actually exported into the team-lead's bash session, that's a separate orchestration bug — file via `/kiln:kiln-fix`, don't expand this PRD.
- **Date in fixture file names**: §5 fixtures use `2026-04-23-fixture-*.md`. Adjust the date for whenever you actually run the smoke; the bash sets `TODAY` independently.
- **Should the parser be extracted to a `.sh` file?** §3 of contracts says "MAY (and is encouraged to)." Recommend YES if the implementer is comfortable adding a file under `plugin-shelf/scripts/parse-shelf-config.sh` — it keeps the workflow JSON readable and testable in isolation. If not, keep inline in the JSON command — both meet the contract.

## Recommendations for retrospective

1. PRDs that name source files should use precise paths (skill vs workflow vs script). Distill or PRD-create should enforce.
2. `/kiln:kiln-build-prd`'s Step 4b heading should anchor sub-steps so future PRDs have stable targets.
3. The pattern of "skill X reads config and calls Y" appears in at least 6 shelf skills. The defensive parser in `shelf-counter.sh` is the de-facto standard. Worth a retro thread on whether `_read_key()` should be extracted into `plugin-shelf/scripts/parse-shelf-config.sh` (with subcommand interface like `bash parse-shelf-config.sh slug`) for shared use across all consumers — would unify the discovery vs. config decision rule across the whole plugin.

## Time

Spec + plan + tasks + contracts: ~30 min wall-clock (one continuous pass, no stops).

## Sign-off

All four artifacts exist:
- `specs/pipeline-input-completeness/spec.md`
- `specs/pipeline-input-completeness/plan.md`
- `specs/pipeline-input-completeness/contracts/interfaces.md`
- `specs/pipeline-input-completeness/tasks.md`

Friction note (this file) written. Marking Task #1 `completed` and notifying implementer.
