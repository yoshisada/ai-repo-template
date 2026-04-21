---
type: issue
date: 2026-04-21
status: open
priority: medium
repo: https://github.com/yoshisada/ai-repo-template
tags: [kiln-fix, architecture, simplification]
files:
  - plugin-kiln/skills/fix/SKILL.md
  - plugin-kiln/skills/fix/team-briefs/fix-record.md
  - plugin-kiln/skills/fix/team-briefs/fix-reflect.md
  - plugin-kiln/scripts/fix-recording/
---

# `/kiln:fix` should not use the wheel plugin for the fix-recording step

## Description

`/kiln:fix` Step 7 "Record the Fix" currently uses the wheel plugin indirectly — it spawns two short-lived Claude agent **teams** (`fix-record` and `fix-reflect`) and relies on `TeamCreate` / `TaskCreate` / `TeamDelete` primitives plus MCP to write one Obsidian note and (optionally) file one manifest-improvement proposal. It does not directly invoke a wheel workflow for recording, but the design leans on the same "dispatch work to a child runtime and wait for completion" model that wheel uses — and it inherits the failure modes.

Observed failures today (2026-04-21):

1. **Recorder teammate stalled on final `TaskUpdate`** (filed as separate issue: `2026-04-21-kiln-fix-step7-recorder-stall-teams.md`). The haiku recorder successfully wrote the Obsidian fix note, then never called `TaskUpdate` to mark the task completed. `TeamDelete` blocked. Main chat had to intervene manually.

2. **Grandchild stranding during `/kiln:report-issue` follow-up** — when I tried to file an issue about #1, `/kiln:report-issue` invoked `shelf:sync`, which invoked `shelf:propose-manifest-improvement` as a grandchild. The grandchild's `reflect (1/3)` step never advanced because the wheel resolver in the installed plugin cache (v `000.001.000.167`) couldn't pick the grandchild as the leaf. This is the resolver bug fixed in commit `6fc9ee0` but not yet republished. Workflow had to be force-stopped via `/wheel:stop --all`, and the issue file had to be written inline via direct MCP calls (which worked perfectly in one call).

Both failures are symptoms of the same root cause: **fix-recording is mechanical work (one MCP write with a templated body) that does not benefit from dispatch/polling machinery, and adding that machinery creates failure surface where none is needed.**

## Proposal

Refactor `/kiln:fix` Step 7 to perform the Obsidian write (and the optional manifest-improvement reflect) **inline in main chat**, without `TeamCreate` / wheel involvement.

Concretely, replace the current Step 7.5–7.9 flow with:

1. **Envelope** — unchanged; `compose-envelope.sh` still runs inline.
2. **Local record** — unchanged.
3. **Obsidian write** — main chat calls `mcp__claude_ai_obsidian-projects__create_file` (or `-manifest__create_file` for manifest paths) directly with the templated note body. No teams. No wheel.
4. **Manifest reflect** — main chat reads the envelope, decides if any `@manifest/types/*.md` or `@manifest/templates/*.md` has a concrete gap, and either calls `mcp__claude_ai_obsidian-manifest__create_file` into `@inbox/open/` or skips. No teams. No wheel.
5. **Report** — unchanged.

Remove `plugin-kiln/skills/fix/team-briefs/` and `plugin-kiln/scripts/fix-recording/render-team-brief.sh`. Keep `compose-envelope.sh`, `write-local-record.sh`, and the two gate scripts (`validate-reflect-output.sh`, `check-manifest-target-exists.sh`, `derive-proposal-slug.sh`) — those are still useful as pure helpers.

## Why this is better

- **Zero failure modes around teammate lifecycle** — no `TaskUpdate` to forget, no `TeamDelete` ordering, no "one team at a time" constraint.
- **Zero dependency on wheel's grandchild resolver** — `shelf:sync` is not involved, and `shelf:propose-manifest-improvement` is not dispatched. The resolver bug (even after it's fixed) doesn't surface here.
- **Cheaper** — one MCP call per write vs. envelope → brief render → TeamCreate → TaskCreate → poll → TaskUpdate → TeamDelete.
- **Main-chat context cost is negligible** — the envelope is already in main chat; composing the note body from it and calling `create_file` once adds maybe 2k tokens, far less than the team-spawn dance.
- **Matches how simple inline MCP writes actually behave** — demonstrated in this very session: the inline issue-file write succeeded in one call with zero stalls.

## Acceptance

- `/kiln:fix` Step 7 no longer calls `TeamCreate` or any wheel workflow.
- The Obsidian fix note is written via one direct MCP call from main chat.
- The manifest-improvement reflect is either performed inline by main chat or dropped entirely (if the main-chat judgment step is too expensive, a deterministic "skip unless envelope mentions manifest/" gate is acceptable).
- The fix-recording section of `/kiln:fix` completes end-to-end in a single pass with no polling, no teardown, and no opportunity for teammate-lifecycle stalls.

## Related

- `2026-04-21-kiln-fix-step7-recorder-stall-teams.md` — the recorder-stall incident that motivated this refactor.
- Commit `6fc9ee0` — wheel grandchild resolver fix (fixes the resolver bug but does not eliminate the class of failures that team-spawn introduces).

## Source

Observed across two `/kiln:fix`-related runs on 2026-04-21: the original fix run (recorder stall) and the follow-up `/kiln:report-issue` run (grandchild stranding). Both recovered only via direct main-chat intervention.
