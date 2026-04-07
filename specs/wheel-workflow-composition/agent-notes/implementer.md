# Implementer Friction Notes: Wheel Workflow Composition

## What Went Well

- **Spec artifacts were thorough.** The contracts/interfaces.md had exact function signatures and the research.md explained key design decisions (fan-in in handle_terminal_step, not the hook). This saved significant time — I didn't have to reverse-engineer the design intent.
- **Phase ordering was correct.** Validation first (Phase 2) → core composition (Phase 3) → stop cascade (Phase 6) → e2e (Phase 7) was a clean dependency chain.
- **Existing patterns were consistent.** Adding a new step type to dispatch_step() was straightforward because all existing step types (agent, command, parallel, approval, branch, loop) follow the same pattern.

## What Was Confusing

- **`engine.sh` sourcing in tests**: The engine.sh file uses `BASH_SOURCE` to resolve its sibling libs, which doesn't work when sourced from a different working directory. Had to manually set `WHEEL_LIB_DIR` and source individual files. This is a general testing friction point for the wheel engine, not specific to this feature.
- **`local` keyword in hook script**: The `post-tool-use.sh` hook script uses `local` in its deactivate.sh else-branch (lines 91-92) — but `local` is only valid inside bash functions. This is a pre-existing bug outside the scope of this feature. Didn't fix it to stay in scope.
- **Edit tool uniqueness constraints**: Several files had repeated `return 0\n}` patterns that made exact-match edits fail. Had to include more surrounding context each time to get unique matches.

## Where I Got Stuck

- **Circular reference error message format**: The initial implementation produced `A,A` instead of the spec's `A -> B -> A` format. The visited set was comma-separated internally, and the error message just printed the raw visited string. Fixed by building a proper chain string with ` -> ` separators before printing.

## What Could Be Improved

- **E2E testing is manual and fragile.** Creating/validating/cleaning up test workflow files by hand is error-prone. A simple test harness (even just a bash script that runs assertions) would make e2e validation more reliable and repeatable.
- **No integration test for the full hook lifecycle.** The fan-in logic in `handle_terminal_step()` and the `dispatch_workflow()` child activation were tested individually, but testing the full PostToolUse hook → engine → dispatch → fan-in → parent advance flow requires a running Claude Code session. This is the hardest thing to validate outside of a real execution.
- **The spec could note that `workflow_validate_workflow_refs` needs to be called from `workflow_load` AFTER content is already read into a variable.** The integration point (where to insert the call in workflow_load) was clear from the contracts, but the exact insertion point required reading the function body.
