# Implementer Friction Notes: shelf-skills-polish

## What went well

- The spec artifacts (contracts/interfaces.md especially) were well-defined with clear JSON schemas for each workflow, making implementation straightforward
- The task breakdown was clean — each task mapped to a single step or file, no ambiguity
- Reusing the `read-shelf-config` command from shelf-full-sync as a pattern kept things consistent across all three workflows
- The command-first/agent-second pattern is natural for these workflows — data gathering doesn't need MCP

## Friction points

1. **shelf-full-sync summary command is long**: The `generate-sync-summary` step's bash command is very long because it needs to grep multiple output files for counts. The output format of prior agent steps isn't standardized, so the grep patterns have to be flexible (case-insensitive, multiple patterns). A standardized output format from agent steps (e.g., `KEY: N` on dedicated lines) would make downstream command steps simpler.

2. **No test harness for workflow validation**: Validation of workflows is manual (jq checks, file existence). A `wheel-validate` command that checks JSON schema, context_from references, and output path conflicts would catch issues earlier.

3. **check-duplicate abort semantics**: As the specifier noted, there's no first-class "abort" mechanism in wheel workflows. The check-duplicate step writes "DUPLICATE" as a prefix, and the create-project step is instructed to check for that prefix and skip. This is a convention, not enforcement. If the agent ignores the instruction, it could still create a duplicate. A workflow-level `abort_if` condition on steps would be more reliable.

4. **Status label validation is instruction-only**: Skills reference `plugin-shelf/status-labels.md` via prose instructions. There's no hook or automated enforcement — it relies on the AI agent reading and following the instructions. A PreToolUse hook that validates status values before MCP writes would be stronger.

## Suggestions for future work

- Add a `wheel-validate` skill that checks workflow JSON structure
- Add a workflow-level `skip_if` or `abort_if` field for conditional step execution
- Standardize agent step output format with a header section for machine-readable counts
