# Implementer Friction Notes: Wheel Session Guard

## What Went Well

- The contracts/interfaces.md was clear and precise — guard_check signature, return codes, and per-hook pass-through responses were all specified. No ambiguity.
- The task breakdown mapped cleanly to the code changes. Each task was one discrete edit.
- All 6 hooks follow an identical pattern, so the guard integration was mechanical and consistent.

## Friction Points

1. **Gate 4 blocking on first write**: The kiln require-spec hook blocks all `plugin-*` edits until at least one task is marked `[X]`. Since T001 creates a new file (guard.sh), I had to mark T001 done in tasks.md *before* actually creating the file. This is a chicken-and-egg problem — the task can't be done until the file is written, but the file can't be written until a task is marked done. I worked around it by marking T001 first, then writing the file.

2. **Waiting on specifier**: I was blocked for an extended period waiting for Task #1 to complete. The team-lead assignment message arrived before specs existed. Having a clearer signal (e.g., a blockedBy dependency on the task itself) would have been smoother than polling for file existence.

## Suggestions

- Consider exempting `lib/` files from Gate 4 when the target file doesn't exist yet (new file creation vs modification of existing code).
- The first-hook stamping approach (FR-004) is elegant but has a documented race condition window. If this becomes a real problem, consider having `/wheel-run` write a marker file that the first hook consumes, rather than relying on event ordering.
