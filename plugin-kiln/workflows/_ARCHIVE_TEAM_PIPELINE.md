# Archived: team-based build-prd pipeline

**This branch (`archive/team-build-prd`) preserves the agent-teams version of
`kiln-build-prd.json`.** On the main line it was replaced by an all-`delegate`
pipeline (2026-07-01).

## Why it was retired
Head-to-head on the same PRD (a TTL+LRU cache), delegate vs team:

| | delegate | team |
|---|---|---|
| completion reliability | ~100% | **~40%/attempt** (multi-point spawn/coordination flakiness) |
| main-session context | 67% | 56% (confounded — team did less; see below) |
| code + tests | 23 tests, 100% cov | 16 tests, 100%/96% cov |
| **audit gate** | complete (3/3 lenses, 100% compliance) | **degraded — 2/3 lenses silently missing** |

The decisive problem: teams don't just hang — when they *do* archive, teammate
flakiness can **silently degrade the output** (e.g. 2 of 3 audit lenses never
deliver, so `compliance` comes back `null` on a "green" build). Root cause is
architectural: a team is N autonomous agent sessions coordinating over an async
file/hook channel, so reliability compounds multiplicatively (~p^N). Delegates
collapse each team into one synchronous, framework-guaranteed blocking `Agent`
call (~p^1). See memory `project_capstone_full_e2e` for the full investigation.

## What's here
- `kiln-build-prd.json` on this branch = the **team** pipeline (team-create /
  teammate / team-wait / team-delete for implement + a 3-role audit panel).
- The team sub-workflows `kiln-implement-worker.json` / `kiln-audit-worker.json`
  are present on both lines.
- This branch is forked AFTER all the wheel reliability fixes (per-session
  sentinels, verdict-file + worktree-safe done-file completion, launch-verify +
  precise re-spawn, post-2.1.178 team-create/delete), so it's the *best* version
  of the team pipeline — revive from here if/when agent-teams matures upstream.

## To revive
`git checkout archive/team-build-prd` — its `kiln-build-prd.json` is the team
pipeline. (Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` and human-in-the-loop
supervision for acceptable reliability.)
