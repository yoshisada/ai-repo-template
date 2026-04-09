# Agent Friction Notes: Specifier

## What Went Well
- The PRD was thorough with all 31 FRs clearly defined, making spec writing straightforward.
- Existing wheel engine code is well-structured — reading dispatch.sh, state.sh, engine.sh, and context.sh gave a clear picture of the handler pattern to follow.
- The existing `dispatch_parallel()` handler served as a useful reference for fan-out patterns.

## Friction Points
1. **Skill chaining overhead**: Running /specify, /plan, /tasks as three separate skill invocations adds significant prompt overhead. Each skill re-reads constitution, checks prerequisites, and runs validation. For a pipeline agent, a combined `/specify-plan-tasks` command would save tokens and time.
2. **Plan template mismatch**: The plan template assumes a standard src/tests project structure. For a plugin that modifies existing Bash scripts, the template's "Option 1/2/3" structure choices are not applicable. Had to manually rewrite the structure section.
3. **Tasks template test assumption**: The tasks template heavily suggests TDD with test-first phases. This plugin has no test suite — testing is done by running workflows on consumer projects. The template's test scaffolding had to be stripped out entirely.
4. **Contract format for Bash**: The contracts/interfaces.md template is designed for typed languages with function signatures. Bash functions have positional params and no type annotations, so the contract format needed adaptation to use comment-based param documentation.
5. **Agent context update**: The `update-agent-context.sh` script worked but added technologies to CLAUDE.md that are already listed there from previous features. The dedup logic could be improved.

## Suggestions for Future Runs
- Consider a "plugin mode" for kiln that adjusts templates for Bash/shell plugin development (no src/tests directories, no TDD phases, Bash function signatures in contracts).
- The spec quality checklist could auto-skip items that don't apply (e.g., "no implementation details" is hard to satisfy when the feature IS about implementation details of an engine).
