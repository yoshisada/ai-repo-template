# Feature PRD: Wheel Create Workflow

**Status**: Draft
**Date**: 2026-04-06

## Parent Product

[Kiln Plugin](../../PRD.md) — spec-first development workflow plugin for Claude Code. This feature extends the **wheel** subsystem, which provides a hook-driven workflow engine for automating multi-step pipelines.

## Feature Overview

A `/wheel-create` skill that generates valid wheel workflow JSON files from two input modes:

1. **Natural language** — User or agent describes what they want to automate; the skill produces a `workflows/<name>.json` file with the correct step types, dependencies, and output paths.
2. **File-based** — User or agent points at an existing skill file (e.g., a `SKILL.md`) or any structured file; the skill reverse-engineers it into a repeatable workflow.

The generated workflow is immediately runnable via `/wheel-run` with no manual edits required.

## Problem / Motivation

Creating wheel workflows today requires hand-writing JSON with exact field names, step type semantics, `context_from` references, output paths, and branch/loop configuration. This is error-prone and slow — especially for agents that want to create automation loops at runtime without human JSON authoring.

Users who already have working skills or scripts shouldn't need to manually translate them into workflow JSON. The structure is mechanical enough to automate.

## Goals

- Let users describe a multi-step automation in plain English and get a valid workflow JSON file
- Let users/agents point at an existing file and get a workflow that replicates its behavior
- Let agents create their own pipelines at runtime (self-improvement loops, dynamic automation)
- Generated workflows must pass `workflow_load` validation on first try

## Non-Goals

- Visual/interactive workflow editor (drag-and-drop UI)
- Workflow versioning or migration (updating existing workflows in place)
- Workflow marketplace or sharing between repos
- Auto-execution after creation (user must explicitly `/wheel-run`)
- Approval or parallel step types in v1 (limit to command, agent, branch, loop)

## Target Users

- **Plugin developers** who want to quickly prototype workflows without writing JSON by hand
- **Agents** (sub-agents, teammates) that need to create automation pipelines at runtime
- **Users** who have existing skills/scripts they want to convert into repeatable workflows

## Core User Stories

### US-1: Natural Language to Workflow
As a user, I want to describe a multi-step automation in plain language so that the skill generates a valid workflow JSON I can run immediately.

**Example**: `/wheel-create "gather git stats, analyze the repo structure, then write a health report"`

### US-2: File-Based Reverse Engineering
As a user, I want to point at an existing skill file or script so that the skill reverse-engineers it into a workflow JSON that replicates the same behavior.

**Example**: `/wheel-create from:plugin-shelf/skills/shelf-sync/SKILL.md`

### US-3: Agent Self-Service
As an agent mid-conversation, I want to call `/wheel-create` to dynamically generate a workflow for a task I've identified, so I can automate a repeatable process without human JSON authoring.

## Functional Requirements

### Input Parsing

- **FR-001**: The skill accepts a single argument string. If the string starts with `from:`, treat everything after the prefix as a file path (File Mode). Otherwise, treat the entire string as a natural language description (Description Mode).
- **FR-002**: If no arguments are provided, prompt the user to either describe a workflow or provide a file path.
- **FR-003**: In File Mode, validate that the referenced file exists and is readable. If not, report an error and stop.

### Workflow Name Resolution

- **FR-004**: Derive the workflow name from the input. In Description Mode, generate a short kebab-case slug from the description (e.g., "gather git stats and report" -> `gather-git-stats`). In File Mode, derive from the source filename (e.g., `shelf-sync/SKILL.md` -> `shelf-sync`).
- **FR-005**: If `workflows/<name>.json` already exists, append a numeric suffix (e.g., `gather-git-stats-2`). Never overwrite an existing workflow file.

### Description Mode (Natural Language)

- **FR-006**: Parse the natural language description to identify discrete steps, their types, dependencies, and outputs.
- **FR-007**: Map each identified step to one of the supported step types:
  - **command** — Shell commands, file checks, data gathering
  - **agent** — Tasks requiring LLM reasoning, writing, or analysis
  - **branch** — Conditional logic based on a command exit code
  - **loop** — Repeated execution with a condition check
- **FR-008**: Generate `context_from` arrays based on data dependencies between steps (which steps produce outputs that later steps need).
- **FR-009**: Generate output paths following wheel conventions:
  - Command steps: `.wheel/outputs/<step-id>.txt`
  - Agent steps: output path derived from the step's purpose (e.g., `reports/<name>.md`)
- **FR-010**: Mark the last step (or final convergence point in branched workflows) as `terminal: true`.
- **FR-011**: Set `name` to the resolved workflow name and `version` to `"1.0.0"`.

### File Mode (Reverse Engineering)

- **FR-012**: Read the source file and analyze its structure to identify discrete steps.
- **FR-013**: For SKILL.md files, parse the step-by-step structure (headings, code blocks, prose instructions) and map each to a workflow step.
- **FR-014**: For shell scripts, parse command sequences and map to command steps. Wrap complex logic sections as agent steps.
- **FR-015**: For other structured files (JSON, YAML, Markdown), use best-effort heuristic parsing to identify actionable steps.
- **FR-016**: Preserve the intent and ordering of the source file. Do not reorder or combine steps unless necessary for workflow validity.

### Validation

- **FR-017**: Before writing the file, validate the generated JSON by running the same checks as `workflow_load`:
  - Valid JSON
  - Has `name` (string) and `steps` (non-empty array)
  - Every step has `id` (string) and `type` (string)
  - All step IDs are unique
  - All branch targets (`if_zero`, `if_nonzero`) reference valid step IDs
  - All `context_from` entries reference valid step IDs
  - All `next` fields reference valid step IDs
- **FR-018**: If validation fails, attempt to self-correct (fix invalid references, deduplicate IDs). If self-correction fails, report the errors and do not write the file.

### Output

- **FR-019**: Write the validated workflow JSON to `workflows/<name>.json` with 2-space indentation.
- **FR-020**: After writing, report:
  - The file path
  - Workflow name and step count
  - A brief summary of each step (id, type, one-line description)
  - The command to run it: `/wheel-run <name>`

### Step Type Schema Reference

- **FR-021**: Command steps must have: `id`, `type: "command"`, `command` (string), `output` (string). Optional: `context_from`, `next`.
- **FR-022**: Agent steps must have: `id`, `type: "agent"`, `instruction` (string), `output` (string). Optional: `context_from`, `terminal`, `next`.
- **FR-023**: Branch steps must have: `id`, `type: "branch"`, `condition` (string — shell command), `if_zero` (step id), `if_nonzero` (step id). Optional: `context_from`.
- **FR-024**: Loop steps must have: `id`, `type: "loop"`, `command` (string), `condition` (string — shell command that exits 0 to continue), `max_iterations` (number). Optional: `output`, `context_from`.

## Absolute Musts

1. **Tech stack**: Markdown skill + Bash + JSON (no new dependencies)
2. Generated workflows must pass `workflow_load` validation without modification
3. Never overwrite existing workflow files
4. No auto-execution — output is a JSON file, not a running workflow

## Tech Stack

Inherited from wheel plugin — no additions needed:
- Markdown (skill definition)
- Bash (inline shell commands)
- JSON (workflow output format)
- Existing wheel engine libs for validation reference

## Impact on Existing Features

**Standalone** — this skill writes a JSON file to `workflows/`. No changes to the wheel engine, hooks, state management, or other skills. The existing `/wheel-run` and hook system handle execution.

## Success Metrics

1. Generated workflows pass `workflow_load` validation on first try (100% of the time)
2. Any existing SKILL.md in the plugin can be reverse-engineered into a runnable workflow
3. Generated workflows run successfully via `/wheel-run` without manual JSON edits

## Risks / Unknowns

- **Ambiguous natural language**: Vague descriptions may produce suboptimal step decomposition. Mitigation: the skill can ask a clarifying question if the description is too vague to decompose.
- **Complex skill files**: Some SKILL.md files have deeply nested conditional logic, MCP calls, or multi-tool interactions that don't map cleanly to the 4 supported step types. Mitigation: use agent steps as a catch-all for complex sections, noting the original intent in the instruction field.
- **Loop semantics**: Translating "repeat until done" from natural language into a concrete `condition` shell command requires inference. Mitigation: generate a reasonable default condition and note it for user review.

## Assumptions

- The 4 step types (command, agent, branch, loop) are sufficient for v1. Approval and parallel can be added later.
- The `workflow_load` validation function in `plugin-wheel/lib/workflow.sh` is the canonical validator and will not change incompatibly.
- Workflow files live in `workflows/` at the repo root.

## Open Questions

- Should the skill support a `--dry-run` flag that shows the generated JSON without writing it? (Leaning yes for agent use cases where they want to inspect before committing.)
- Should there be a maximum step count to prevent runaway generation? (Leaning yes — cap at 20 steps for v1.)
