# Blockers — Report-Issue Speedup

**Audit date**: 2026-04-22
**Auditor**: auditor teammate
**Branch**: `build/report-issue-speedup-20260422`

## Executive summary

Zero **hard** blockers against merge. Three **deferred** live-verification gates remain, all documented with exact procedures. Recommendation: merge is safe pending a short main-thread validation pass by the team lead (procedure below).

## Hard blockers

None.

## Deferred pre-merge validation

The following three checks require invoking slash commands through the main-thread Claude Code harness. They cannot be exercised from a teammate tool surface (neither the implementer nor the auditor can call `/kiln:kiln-report-issue` or `/shelf:shelf-sync` as skills — only Bash, file tools, and task/message tools are available). Each gate has a concrete procedure.

### DG-1 — `/shelf:shelf-sync` standalone direct invocation (SC-004 empirical)

**Status**: static `jq` evidence shows SC-004 passes (0 hits in `shelf-sync.json` for the removed workflow ref — already verified below). Live invocation would confirm no `propose-manifest-improvement` step fires at runtime.

**Procedure** (team lead, main thread):
1. `/shelf:shelf-sync`
2. Inspect `.wheel/state_*.json` for the run or the visible step trace.
3. Confirm no step with id `propose-manifest-improvement` or workflow `shelf:shelf-propose-manifest-improvement` fires.
4. Confirm dashboard + progress entries still update normally (existing shelf-sync behavior unaffected).

**Static evidence already gathered**:
```
$ jq '[.steps[] | select(.workflow == "shelf:shelf-propose-manifest-improvement")] | length' \
    plugin-shelf/workflows/shelf-sync.json
0
$ grep -n "propose-manifest-improvement" plugin-shelf/workflows/shelf-sync.json
(no output)
```

### DG-2 — Counter=9 → foreground fires full-sync in background (FR-003 + SC-003 empirical)

**Status**: counter cadence verified LIVE against this repo's real `.shelf-config` via direct script exercise (11 iterations — see audit session log). The static-analysis SC-001 estimate (≤25% of 64.5k) holds. What is NOT yet empirically validated is whether `run_in_background: true` in the wheel agent-step actually returns the foreground immediately.

**Procedure** (team lead, main thread):
1. Set `.shelf-config`: `shelf_full_sync_counter = 9` (one off from threshold 10).
2. Start a stopwatch.
3. Run `/kiln:kiln-report-issue "pre-merge DG-2 probe — foreground fire-and-forget"`.
4. When the foreground returns, stop the stopwatch. Record `T_fg`.
5. Read `.kiln/logs/report-issue-bg-2026-04-22.md`. Find the line with `action=full-sync`. Note its ISO-8601 timestamp `T_bg`.
6. **Pass condition**: `T_fg` is short (< ~15 s) AND `T_bg` > the wall-clock time at which the foreground returned (i.e., the bg log entry is AFTER foreground return).
7. If `T_fg > ~15 s` (foreground blocking on bg sub-agent): apply the **E-3 fallback** per `plan.md` §Unknown 1 — replace the `dispatch-background-sync` step from `type: agent` to `type: command` using `nohup ... &; disown`. The pattern is named inline in the step's existing instruction.

**Cleanup after DG-2**:
- `rm .kiln/issues/2026-04-22-pre-merge-dg-2-probe-*.md` (the test issue file)
- Verify `.shelf-config` has `shelf_full_sync_counter = 0` (reset after full-sync).

### DG-3 — Lean path fast-return validation (SC-001 empirical complement)

**Status**: static analysis of workflow step composition gives confident estimate ~5–10k tokens (≈8–16% of 64.5k baseline). A live run with counter=0 would provide the absolute token number.

**Procedure** (team lead, main thread, after DG-2 passes and counter reset to 0):
1. `/kiln:kiln-report-issue "pre-merge DG-3 probe — lean-path speed"`
2. Foreground should return fast (comparable or faster than DG-2).
3. Verify `.kiln/issues/2026-04-22-pre-merge-dg-3-probe-*.md` exists.
4. Verify corresponding Obsidian note exists at `@second-brain/projects/ai-repo-template/issues/<basename>`.
5. Verify foreground output shows the 3 lines from FR-010 (issue_file, obsidian_path, "background sync queued — full reconciliation next at invocation N/10").
6. Inspect `.shelf-config` — `shelf_full_sync_counter` incremented to 1.
7. Inspect `.kiln/logs/report-issue-bg-2026-04-22.md` — one new line with `action=increment`.

**Cleanup after DG-3**:
- `rm .kiln/issues/2026-04-22-pre-merge-dg-3-probe-*.md`
- `.shelf-config` counter left at 1 (or reset to 0 if preferred — cosmetic).

## Live evidence gathered at audit time

The auditor re-ran the 11-iteration counter smoke against THIS repo's real `.shelf-config` (not a scratchdir). Results — exactly as SC-003 requires:

```
iter=01  before=0 after=1 action=increment
iter=02  before=1 after=2 action=increment
iter=03  before=2 after=3 action=increment
iter=04  before=3 after=4 action=increment
iter=05  before=4 after=5 action=increment
iter=06  before=5 after=6 action=increment
iter=07  before=6 after=7 action=increment
iter=08  before=7 after=8 action=increment
iter=09  before=8 after=9 action=increment
iter=10  before=9 after=0 action=full-sync   <-- cadence correct
iter=11  before=0 after=1 action=increment
```

- `.shelf-config` comment + existing keys preserved intact through the 11 atomic rewrites (verified by diff against pre-run backup).
- `.kiln/logs/report-issue-bg-2026-04-22.md` now exists and contains the FR-009-format lines plus earlier implementer-smoke lines — the log-append helper produced distinct newline-terminated lines for every call (the implementer's earlier newline bug does not regress).
- `.shelf-config` restored to `shelf_full_sync_counter = 0` after exercise so the tree is clean for team-lead's DG-2.

## Behavior-change audit (from DG-scope §6 of Task #3 brief)

Grep sweep: `grep -rn "shelf-sync" plugin-*/skills/ plugin-*/workflows/ | grep -v "plugin-shelf/workflows/shelf-sync.json"`

Callers and disposition:

| Caller | Line | Disposition |
|--------|------|-------------|
| `plugin-kiln/workflows/kiln-mistake.json:26` | terminal step `full-sync` of type workflow → `shelf:shelf-sync` | **NO regression**: kiln-mistake.json ALREADY calls `shelf:shelf-propose-manifest-improvement` explicitly as its own step BEFORE `shelf-sync` (step index 2, not nested). Removing shelf-sync's inline nested reflection does not change kiln-mistake's total behavior — reflection still fires, just from the explicit step. |
| `plugin-kiln/workflows/kiln-report-issue.json:27` | new `dispatch-background-sync` instruction text | Not a caller — this is the text of the new sub-agent prompt describing the (now asynchronous) shelf-sync/reflection invocation. Expected. |
| `plugin-shelf/skills/shelf-sync/SKILL.md` | documentation self-reference | N/A — it's the skill's own README. |
| `plugin-shelf/skills/shelf-propose-manifest-improvement/SKILL.md:3,40` | mentions shelf-sync in frontmatter + body text | Documentation only — describes caller list. Needs no code change. The wording is still broadly accurate (shelf-sync still exists; reflection just no longer auto-chains off of it). |
| `plugin-shelf/skills/shelf-feedback/SKILL.md:63` | suggestion table row — "run `/shelf:shelf-sync` to track as issue" | Cosmetic hint; does not depend on nested reflection. |
| `plugin-kiln/skills/kiln-fix/SKILL.md:377` | explicit FR: "Step 7 MUST NOT invoke `shelf:shelf-sync`" | Explicit non-dependency — kiln-fix goes OUT OF ITS WAY to avoid shelf-sync. Reinforces: removing shelf-sync's inline reflection is safe. |
| `plugin-kiln/skills/kiln-mistake/SKILL.md:8,67` | body text mentions `shelf:shelf-sync` as follow-up | Documentation of the same already-analyzed workflow relationship. |
| `plugin-kiln/skills/kiln-report-issue/SKILL.md:62` | documentation of new `.shelf-config` keys | Expected — this is the new docs. |

**Conclusion**: zero downstream callers break from FR-007's removal of nested reflection inside shelf-sync. The only consumer that previously got "free" reflection via nested shelf-sync (kiln-mistake) already calls reflection explicitly as a sibling step. Reflection's move from "nested inside shelf-sync" to "explicit step in every caller that needs it" is clean.

## Version bump status

Not yet applied (pending team lead approval to proceed — see auditor.md).
