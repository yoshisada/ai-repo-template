---
type: issue
date: 2026-04-21
status: completedcompleted_date: 2026-04-23
pr: #135
prd: docs/features/2026-04-22-kiln-capture-fix-polish/PRD.md
priority: medium
repo: https://github.com/yoshisada/ai-repo-template
tags: [kiln-fix, wheel-teams, reliability]
files:
  - plugin-kiln/skills/fix/SKILL.md
  - plugin-kiln/skills/fix/team-briefs/fix-record.md
  - plugin-kiln/skills/fix/team-briefs/fix-reflect.md
  - plugin-kiln/scripts/fix-recording/
---

# `/kiln:fix` Step 7 recorder teammate stalls on TaskUpdate; reconsider using wheel/teams for fix recording

## Description

During a `/kiln:fix` run on 2026-04-21 (resolver grandchild bug fix, commit `6fc9ee0`), Step 7 "Record the Fix" spawned a `fix-record` team with a haiku `recorder` teammate to write the Obsidian fix note. The recorder appears to have successfully created the Obsidian note — confirmed because a direct `mcp__claude_ai_obsidian-projects__create_file` from main chat on the same target path returned `"File already exists: @second-brain/projects/ai-repo-template/fixes/2026-04-21-wheel-grandchild-workflow-stranding-stale-local.md"`. However, the recorder never called `TaskUpdate` to mark task #1 completed.

Consequences:
- The team could not be torn down. `TeamDelete` returned `"Cannot cleanup team with 1 active member(s): recorder. Use requestShutdown to gracefully terminate teammates first."`
- Main chat had to intervene: mark task #1 completed manually via `TaskUpdate`, send a `shutdown_request` via `SendMessage`, wait, then retry `TeamDelete`.
- Scheduled wakeup / polling loops burned cache and tokens while the recorder sat idle.
- The `fix-reflect` team was never spawned because the leader runtime constraint ("one team at a time") required the first team to be torn down first.

## Two concerns to address

### 1. Recorder reliability

The team brief at `plugin-kiln/skills/fix/team-briefs/fix-record.md` lists under "Terminal states":

> 1. **Success** — `create_file` returned ok. Call `TaskUpdate` to mark completed. Do not `SendMessage` main chat; success is silent.

The haiku model completed the `create_file` but skipped the terminal `TaskUpdate`. A `SendMessage` nudge from main chat didn't unstick it either. Possible causes: the brief's "be silent" instruction may be over-indexed on by small models (interpreted as "do nothing after the write"); or the sequence "call tool X, then call tool Y, then stop" is fragile for haiku when the two calls are different primitives (MCP write vs task management).

### 2. Is team-spawn the right primitive for fix recording at all?

Step 7 adds two short-lived teams (`fix-record` + `fix-reflect`) purely to write one Obsidian file and optionally propose one manifest patch. The envelope → brief render → `TeamCreate` → `TaskCreate` → poll → `TeamDelete` pipeline costs several round-trips, then stalled at the final `TaskUpdate`. The same work could be done with much less failure surface:

- **Option A — Inline**: main chat writes the Obsidian note directly via `mcp__claude_ai_obsidian-projects__create_file` and performs the `@manifest/types/*.md` reflect inline. No teams, no poll loop, no teardown. Trade-off: burns main-chat context for a write that doesn't really need deliberation.
- **Option B — Wheel workflow without teammates**: use a `type: command` wheel step that invokes a single MCP write helper (if shelf can expose one), or a small bash wrapper around `mcp` CLI. Trade-off: adds a wheel dependency but eliminates the teammate-lifecycle class of bugs.
- **Option C — Keep teams but harden the brief**: make the terminal `TaskUpdate` the LAST and most-emphasized instruction, add a self-check loop ("if task is still `in_progress` after 30s, re-call TaskUpdate"), or switch the recorder from haiku to sonnet (at cost).

Recommendation: try Option A first — the recorder's job (one MCP write with a templated body from the envelope JSON) is mechanical enough that inline main-chat execution is strictly simpler. The `fix-reflect` team has more judgment in it (decide whether a gap exists, extract verbatim `current`, run the exact-patch gate) but even that is sequential work that could run inline without team ceremony.

## Acceptance

- `/kiln:fix` Step 7 no longer requires main-chat intervention to unstick a teammate.
- Either the recorder reliably completes `TaskUpdate`, or Step 7 is refactored to not depend on team-spawn at all.
- A `/kiln:fix` success path completes end-to-end (local record + Obsidian note + optional proposal + final report) without manual `TaskUpdate`, manual `shutdown_request`, or manual `TeamDelete` from main chat.

## Source

Observed during `/kiln:fix` on 2026-04-21 while fixing the wheel grandchild resolver bug (commit `6fc9ee0`). Local fix record: `.kiln/fixes/2026-04-21-wheel-grandchild-workflow-stranding-stale-local.md`.
