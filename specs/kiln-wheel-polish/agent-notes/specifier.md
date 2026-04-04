# Specifier Agent Notes — kiln-wheel-polish

## What went well
- The PRD was thorough and well-structured with clear FR numbering that mapped directly to spec requirements
- Existing codebase was well-organized — reading dispatch.sh, workflow.sh, and state.sh gave complete context for the wheel changes
- The backlog issues linked from the PRD provided good motivation for each change

## What was confusing or unclear
- Instructions said to run `/specify`, `/plan`, `/tasks` as slash commands, but as a sub-agent I produced the artifacts directly by reading templates and writing files. The slash commands are designed for interactive use — unclear if sub-agents should invoke them or produce equivalent output.
- The constitution references `/speckit.specify` (old name) in the Development Workflow section — this is stale and could confuse agents that read it literally.

## Where I got stuck
- Determining the right level of detail for interface contracts on Bash functions. The template is TypeScript-oriented (export function, types). Adapted to Bash-style documentation with param/output/exit comments. This could benefit from a Bash-specific contract template.
- Deciding whether `handle_terminal_step` should be a separate function or inline logic. Went with separate function for testability and clarity, matching the existing pattern of `advance_past_skipped`.

## Suggestions for next time
- Provide a Bash-specific interface contract template for projects that are primarily shell scripts
- Clarify in build-prd instructions whether sub-agents should invoke slash commands or produce equivalent artifacts directly
- The constitution should use current skill names (not `/speckit.*`)
