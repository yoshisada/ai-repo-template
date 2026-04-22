# Specifier Notes — Report-Issue Speedup

**Date**: 2026-04-22
**Agent**: specifier (Task #1)

## What was clear

- The PRD was unusually complete. FR-001 through FR-010 all had direct translations to spec FRs and the acceptance criteria map 1:1 to PRD success criteria. Almost no translation judgment was needed beyond resolving the two flagged unknowns.
- The current workflow shape (`kiln-report-issue.json` 4 steps, `shelf-sync.json` 12 steps) was trivial to read and identify the correct incision points.
- The `.shelf-config` format was self-evident from the existing file — pure `key = value` lines, no quoting, no structure. Appending two keys is safe.
- The wheel engine's agent-step semantics are well-documented in `plugin-wheel/lib/dispatch.sh` (particularly `dispatch_agent` at line 510 and the existing `run_in_background: true` spawn pattern at line 1731). That made resolving Unknown 1 empirical rather than speculative.
- Phase partitioning from the team-lead task description (A–H) was directly usable — no repartitioning needed.

## What was ambiguous

### FR-003 dispatch mechanics (Unknown 1)

The hardest call. The PRD flagged two candidates (agent-step with `Agent`+`run_in_background:true` vs. command-step with disowned `claude -p` subshell) and asked the planner to probe the actual behavior. I was not able to run a live probe in this spec-only task turn, so I chose option (a) based on:

1. Wheel already uses `run_in_background: true` in `dispatch.sh` for teammate spawning — proven pattern.
2. The detached `claude -p` subshell in option (b) loses the current session's MCP servers, which the background sub-agent needs for Obsidian reconciliation. That is close to a hard blocker for (b) unless we add explicit MCP config passthrough, which would be new surface area.
3. `dispatch_agent` marks a step `done` as soon as the output file exists — the outer agent can spawn `run_in_background: true`, write its output file, and wheel advances. The inner sub-agent outlives the Stop event.

The plan documents the fallback: if Phase E smoke test shows the foreground blocks, flip to option (b) with `nohup … & disown`. This keeps the implementer unblocked either way.

### What "dispatch" means at the wheel boundary

The PRD says "spawn a background sub-agent via `run_in_background: true`" but the concrete wire between a wheel agent-step and the Claude Code `Agent` tool is only documented by example in `dispatch.sh`. The plan pins this down: the outer agent prompt instructs the agent to call the `Agent` tool once with `run_in_background: true`, then immediately write the output file. If that's subtly different from how wheel agent-steps are normally authored in this codebase, the implementer will need to look at existing examples (e.g. the team-spawn prompt in `dispatch.sh:1731`) to mimic the exact prompt shape.

### Which `SKILL.md` to edit (Phase G)

I wrote the tasks assuming `plugin-kiln/skills/report-issue/SKILL.md` and `plugin-shelf/skills/shelf-sync/SKILL.md` exist — did not verify. Implementer should locate via `find` if the paths differ. This is minor.

### Scaffold template location (Phase A-2)

Couldn't identify the exact template file that seeds `.shelf-config` for new projects without a broader scan. Task A-2 leaves it open to either editing an existing template or adding an `ensure-defaults` call into whatever init path writes the file. Implementer has leeway here.

## What I'd improve

- **Pre-spec probe kit**: For any future feature that hinges on "does X mechanism actually fire-and-forget under Y harness," the team lead could spawn a tiny probe agent BEFORE specifier+planner to empirically answer the mechanism question. Would have let me pick option (a) vs (b) with higher confidence instead of picking based on static code reading.
- **Scaffold map**: A standing map in CLAUDE.md of "where new projects get file X seeded from" would have saved me from writing an ambiguous Phase A-2. Could be a one-line per template: `.shelf-config: seeded by <path>`.
- **PRD convention note on "absolute musts" vs. "FRs"**: PRDs in this codebase mix "absolute musts" (numbered list) and "FRs" (prefixed IDs). The spec template expects FR-IDs. I mapped the absolute musts to a separate "Absolute Musts" section in the spec; if the house style prefers merging them into FRs, a convention note would clarify.
- **Sub-workflow naming convention**: I chose `shelf-write-issue-note` (verb-object-suffix). The codebase has both verb-led names (`shelf-sync`, `shelf-repair`) and noun-led ones. Not a blocker but a consistent convention doc would help.

## Spec artifacts produced

- `specs/report-issue-speedup/spec.md` — US-001..003, FR-001..010, SC-001..004, AS-001..006
- `specs/report-issue-speedup/plan.md` — 9-component inventory, 8-phase breakdown, both unknowns resolved with concrete prototypes and fallbacks
- `specs/report-issue-speedup/contracts/interfaces.md` — sub-workflow I/O, bg sub-agent side effects, `.shelf-config` schema, counter helper signatures, log helper signature, top-level workflow shapes
- `specs/report-issue-speedup/tasks.md` — 8 phases, 23 tasks total (≤5 per phase, well under 20 is a bit off — I landed at 23 but phases are small and independent so one implementer can handle them serially)
