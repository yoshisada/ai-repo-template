---
type: issue
date: 2026-04-21
status: open
priority: low
repo: https://github.com/yoshisada/ai-repo-template
tags: [test, kiln-fix, wheel-resolver, architecture]
files:
  - plugin-kiln/skills/fix/SKILL.md
  - plugin-kiln/skills/fix/team-briefs/fix-record.md
  - plugin-wheel/lib/guard.sh
---

# Test issue — verify wheel 3-level nesting; reiterate `/kiln:fix` drop-wheel recommendation

## Description

This is a test issue filed intentionally to exercise the full 3-level `/kiln:report-issue` → `shelf:sync` → `shelf:propose-manifest-improvement` workflow chain now that the wheel grandchild resolver fix (`6fc9ee0`, shipped in wheel plugin cache version `000.001.000.173`) is installed. Prior to the fix, this chain stranded at the grandchild `reflect` step because the old `guard.sh` resolver couldn't pick the leaf state file reliably among 3+ matching candidates. If this workflow completes end-to-end (the grandchild advances past `reflect`, and the parent `report-issue` workflow eventually archives), the chain-walk leaf resolver is confirmed working.

## Secondary content — reiterate the `/kiln:fix` recommendation

Even with the resolver fix, the underlying architectural argument from `2026-04-21-kiln-fix-drop-wheel-plugin-from-recording.md` still stands:

- The resolver fix eliminates the **grandchild stranding** failure mode.
- It does NOT eliminate the **teammate-lifecycle** failure mode (recorder successfully writes the Obsidian note, then fails to call `TaskUpdate`, blocking `TeamDelete`). That was observed earlier today during the wheel grandchild fix run.
- `/kiln:fix` Step 7 touches both failure surfaces when it uses `TeamCreate` with haiku teammates. Inline MCP writes avoid both.

Recommendation unchanged: refactor `/kiln:fix` Step 7 to write the Obsidian fix note directly from main chat via one `mcp__claude_ai_obsidian-projects__create_file` call.

## Acceptance

Primary (test goal):
- This `/kiln:report-issue` invocation completes without being force-stopped via `/wheel:stop`.
- `shelf:propose-manifest-improvement` grandchild `reflect` step advances past `pending`.
- Final state: all three workflow state files archived to `.wheel/history/success/`.

Secondary (recommendation, tracked in the related issue):
- `/kiln:fix` Step 7 no longer spawns a `fix-record` team.

## Related

- `2026-04-21-kiln-fix-step7-recorder-stall-teams.md` — recorder stall observation.
- `2026-04-21-kiln-fix-drop-wheel-plugin-from-recording.md` — architectural recommendation.
- `2026-04-21-wheel-grandchild-workflow-stranding-stale-local.md` (fix record) — the resolver fix this test is validating.
- Commit `6fc9ee0` — wheel resolver fix.

## Source

Filed 2026-04-21 as an intentional test of the wheel `000.001.000.173` plugin cache update, immediately after confirming the fix landed in `~/.claude/plugins/cache/yoshisada-speckit/wheel/000.001.000.173/lib/guard.sh`.
