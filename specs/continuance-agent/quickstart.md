# Quickstart: Continuance Agent (/next)

## What This Feature Does

The continuance agent analyzes your full project state and tells you exactly what to do next. It replaces `/resume` with a more capable `/next` command.

## Two Ways It Runs

1. **After `/build-prd`**: Automatically runs as the final pipeline step, surfacing all open items from the build.
2. **At session start**: Run `/next` manually to pick up where you left off.

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `plugin/agents/continuance.md` | CREATE | Agent definition — analysis methodology and role |
| `plugin/skills/next/SKILL.md` | CREATE | Skill definition — user-invocable `/next` command |
| `plugin/skills/resume/SKILL.md` | MODIFY | Deprecate — redirect to `/next` with notice |
| `plugin/skills/build-prd/skill.md` | MODIFY | Add continuance as final pipeline step |

## Implementation Order

1. Create `plugin/agents/continuance.md` — the agent definition
2. Create `plugin/skills/next/SKILL.md` — the skill with full analysis logic
3. Modify `plugin/skills/resume/SKILL.md` — deprecation alias
4. Modify `plugin/skills/build-prd/skill.md` — pipeline integration

## How to Test

1. Run `/next` in a project with open tasks, blockers, and QA results — verify all items appear prioritized
2. Run `/next --brief` — verify only top 5 shown, no report file saved
3. Run `/resume` — verify deprecation notice + full `/next` output
4. Run `/build-prd` — verify continuance runs after retrospective and output appears in summary
