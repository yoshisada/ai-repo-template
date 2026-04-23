---
title: "Wheel workflows should activate via skill, not auto-fire on every session"
type: improvement
severity: high
category: workflow
source: manual
github_issue: null
status: completedcompleted_date: 2026-04-23
pr: merged-pre-tracking
prd: docs/features/2026-04-04-wheel-skill-activation/PRD.md
date: 2026-04-04
---

## Description

Wheel's hooks currently auto-discover workflow JSON files in `workflows/` and activate on every Claude Code session. This means any project with wheel installed and a workflow file will always run the workflow — there's no way to use Claude Code normally without the workflow engine intercepting Stop events.

Workflows should only activate when explicitly triggered via a skill command (e.g., `/wheel-run example`). The skill creates `.wheel/state.json` which activates the hooks. Without state.json, hooks pass through silently.

Three skills needed:
- `/wheel-run <name>` — Init state.json from workflow definition, output first step instruction, hooks take over
- `/wheel-stop` — Remove state.json, hooks go dormant
- `/wheel-status` — Print current step, progress, command log

## Impact

Without this fix, wheel is unusable in practice — it hijacks every Claude Code session in any project where it's installed. Users can't do normal work alongside wheel without the Stop hook blocking them.

## Suggested Fix

1. Create `plugin-wheel/skills/wheel-run/`, `wheel-stop/`, `wheel-status/` with SKILL.md files
2. Update every hook's guard clause: replace workflow file auto-discovery with a simple `[[ ! -f ".wheel/state.json" ]] && exit 0` check
3. The `/wheel-run` skill handles workflow validation, state initialization, and outputs the first step instruction
4. The `/wheel-stop` skill removes state.json and optionally archives the completed workflow log
