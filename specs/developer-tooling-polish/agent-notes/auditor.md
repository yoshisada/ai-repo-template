# Auditor Friction Notes: Developer Tooling Polish

**Agent**: auditor
**Date**: 2026-04-07

## What Went Well

- Both implementers delivered clean, complete SKILL.md files that match the interface contracts exactly
- FR coverage is 100% — every requirement has a corresponding implementation section with the correct FR reference
- The wheel-list smoke test worked first try (once run under bash instead of zsh)
- No file conflicts between the two parallel implementers — clean separation of concerns

## Friction Points

1. **Long wait for predecessors**: Tasks #1, #2, and #3 all had to complete before audit could start. The auditor was spawned early but sat idle for the entire specify + plan + tasks + implement cycle. Consider spawning the auditor only after implementation is confirmed complete, or giving the auditor preliminary work (e.g., reviewing spec/plan artifacts) while waiting.

2. **Phase 5 tasks unchecked**: T017 and T018 (edge case verification, quickstart validation) were left unchecked by both implementers. These are cross-cutting and don't belong to either agent's scope. The task breakdown should either assign cross-cutting polish tasks to a specific agent or to the auditor.

3. **zsh vs bash incompatibility in smoke test**: The wheel-list skill uses bash-specific syntax (`declare -A` for associative arrays) which fails in zsh. This is correct behavior since Claude Code runs bash blocks in bash, but it's a gotcha for manual smoke testing. Not a real issue for production use.

## Suggestions for Future Pipelines

- Assign Phase 5 polish tasks to the auditor, since the auditor is the one verifying completeness anyway
- Consider a "pre-audit" step where the auditor reviews spec/plan quality while waiting for implementation
