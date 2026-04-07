# Implementer Friction Notes: wheel-list

## What went well
- Existing wheel skills (wheel-status, wheel-create) provided clear patterns for SKILL.md structure
- The contracts/interfaces.md output format spec was precise enough to implement directly
- E2E validation against 9 real workflow files confirmed all FRs working on first pass

## Friction points
- **Waiting for specs**: Had to poll for ~2 minutes waiting for spec artifacts to appear. The task assignment arrived before specs were committed, causing idle time.
- **Bash in zsh shell**: E2E validation required explicit `bash -c` wrapper since the dev machine uses zsh and associative arrays (`declare -A`) are bash-specific. The skill itself will run correctly in Claude Code's bash execution context, but local testing needed the wrapper.

## Decisions made
- Used inline validation rather than importing `plugin-wheel/lib/workflow.sh` — the skill is read-only and self-contained, keeping it simple
- Validated branch targets, context_from refs, and unique step IDs (comprehensive validation beyond just JSON parsing)
- Used `find` with `-type f` for robustness with nested directories

## Time estimate vs actual
- Estimated: ~10 minutes of active implementation
- Actual: ~5 minutes implementation + ~2 minutes waiting for specs + ~3 minutes validation
