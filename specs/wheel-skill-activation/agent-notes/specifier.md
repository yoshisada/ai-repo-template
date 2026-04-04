# Specifier Friction Notes: wheel-skill-activation

**Agent**: specifier  
**Date**: 2026-04-04

## What went well

- Both PRDs (wheel parent + skill-activation) were clear and complementary. The parent PRD explained the engine architecture; the child PRD focused narrowly on the activation gate.
- The existing hook code follows a consistent pattern (auto-discovery block is nearly identical across all 6 hooks), making the guard clause replacement straightforward to specify.
- `lib/workflow.sh` already has `workflow_load()` with validation — the only gap was unique-step-ID checking, so FR-006 maps to a single new function.

## Friction points

- **state.json schema extension**: The PRD doesn't mention storing `workflow_file` in state.json, but hooks need to know which workflow file to load after state.json gates them in. Had to make a design decision (store path in state.json vs re-discover) and document it in the plan. This is the kind of detail PRDs should specify when the data flow changes.
- **Skill format uncertainty**: PRD risk #1 asks whether skills auto-register from `plugin-wheel/skills/`. I assumed yes based on kiln's pattern, but this isn't confirmed. If skills need explicit registration in plugin.json, T009-T011 will need adjustment.
- **engine_init creates state.json**: The current `engine_init()` creates state.json if it doesn't exist (line 41-46 of engine.sh). After this feature, `/wheel-run` owns state creation and `engine_init()` should NOT create it. The implementer needs to handle this — either `engine_init()` is changed to skip creation, or the hooks are structured so engine_init is only called when state.json already exists (which the guard ensures).

## Suggestions for next time

- PRD should specify data flow changes explicitly (e.g., "state.json gains a `workflow_file` field").
- Confirming skill auto-discovery behavior before speccing would have avoided the assumption.
