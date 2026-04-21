# fix-skill Step 7 cannot spawn two teams in parallel — runtime blocks leading two teams

**Source**: observed during `/kiln:fix` Step 7 execution (first real end-to-end run, 2026-04-21)
**Priority**: medium
**Suggested command**: `/fix fix-skill Step 7 FR-003 parallel-spawn — runtime rejects second TeamCreate with "A leader can only manage one team at a time"`
**Tags**: [auto:continuance]

## Description

`plugin-kiln/skills/fix/SKILL.md` Step 7.6 says: "Spawn both teams in parallel (FR-003 — same tool-call batch)". The first real `/kiln:fix` run hit a hard runtime error on the second `TeamCreate`:

> `Already leading team "fix-record-1776734901". A leader can only manage one team at a time. Use TeamDelete to end the current team before creating a new one.`

Consequence: the skill currently runs fix-record → shutdown → TeamDelete → fix-reflect sequentially, doubling wall-clock time and producing extra idle-notification traffic (two shutdown nudges, two TeamDelete polls).

Candidate fixes:
1. Rewrite Step 7 to spawn the reflector as a plain background `Agent` (no team wrapper). Single-agent "teams" don't need team ceremony; drop the team for reflect, keep the team only for record.
2. Keep both teams but document the sequential pattern as the official flow and remove the "parallel" language from the skill + FR-003.
3. Petition the runtime to allow leading multiple teams concurrently (upstream change, unlikely short-term).

Option 1 is probably the right call — reflector is a singleton by spec, so the team wrapper buys nothing but overhead.
