# Feature Specification: Wheel Create Workflow

**Feature Branch**: `build/wheel-create-workflow-20260406`  
**Created**: 2026-04-06  
**Status**: Draft  
**Input**: User description: "A /wheel-create skill that generates valid wheel workflow JSON files. Two modes: natural language description, and file-based reverse engineering (from: prefix)."

## User Scenarios & Testing

### User Story 1 - Natural Language to Workflow (Priority: P1)

A user wants to automate a multi-step process. They describe the automation in plain English, and the skill produces a valid workflow JSON file that can be run immediately via `/wheel-run`.

**Why this priority**: This is the primary use case. Most users will describe what they want in natural language rather than pointing at existing files. It delivers immediate value by eliminating manual JSON authoring.

**Independent Test**: Can be fully tested by running `/wheel-create "gather git stats, analyze repo structure, write a health report"` and verifying the output file loads and runs via `/wheel-run`.

**Acceptance Scenarios**:

1. **Given** a user provides a natural language description like "gather git stats, analyze the repo structure, then write a health report", **When** they run `/wheel-create` with that description, **Then** a valid workflow JSON file is created at `workflows/<derived-name>.json` with correctly typed steps, dependencies, and output paths.
2. **Given** a description with implicit data dependencies (e.g., "count files then summarize the count"), **When** the skill generates the workflow, **Then** the later step's `context_from` array references the earlier step's ID.
3. **Given** a description that maps to different step types (commands for shell work, agents for reasoning/writing), **When** the skill generates the workflow, **Then** each step has the correct `type` field matching its nature.
4. **Given** a generated workflow JSON file, **When** it is loaded via `workflow_load`, **Then** validation passes on first try with no errors.

---

### User Story 2 - File-Based Reverse Engineering (Priority: P2)

A user has an existing skill file (SKILL.md) or shell script that they want to convert into a repeatable wheel workflow. They point the skill at the file using the `from:` prefix, and it reverse-engineers the file into a workflow JSON.

**Why this priority**: Converting existing skills to workflows is valuable but secondary to creating new workflows from scratch. Users with existing automation will use this to migrate.

**Independent Test**: Can be tested by running `/wheel-create from:plugin-wheel/skills/wheel-status/SKILL.md` and verifying the output replicates the skill's behavior as a workflow.

**Acceptance Scenarios**:

1. **Given** a user provides `from:path/to/SKILL.md`, **When** the skill runs, **Then** it reads the file, identifies discrete steps, and produces a workflow JSON that preserves the intent and ordering of the source.
2. **Given** a SKILL.md with code blocks and prose instructions, **When** the skill reverse-engineers it, **Then** shell commands become `command` steps and reasoning/writing sections become `agent` steps.
3. **Given** a shell script with sequential commands, **When** the skill reverse-engineers it, **Then** each command maps to a `command` step in order.
4. **Given** a file path that does not exist, **When** the user runs `/wheel-create from:nonexistent.md`, **Then** the skill reports an error and stops without creating any file.

---

### User Story 3 - Agent Self-Service Creation (Priority: P3)

An agent mid-conversation wants to dynamically create a workflow for a task it has identified. It calls `/wheel-create` with a description and gets a runnable workflow without human JSON authoring.

**Why this priority**: Enables autonomous agent workflows but is an advanced use case that builds on top of the natural language mode.

**Independent Test**: Can be tested by having an agent invoke `/wheel-create "check test coverage, fix failing tests, re-run tests"` and verifying the generated workflow is valid and runnable.

**Acceptance Scenarios**:

1. **Given** an agent calls `/wheel-create` with a task description, **When** the skill generates the workflow, **Then** the output is a valid JSON file that can be run via `/wheel-run` without manual edits.
2. **Given** the agent creates a workflow with the same name as an existing one, **When** the skill runs, **Then** it appends a numeric suffix to the filename (e.g., `check-coverage-2.json`) and never overwrites the existing file.

---

### User Story 4 - No Arguments Provided (Priority: P2)

A user runs `/wheel-create` without any arguments. The skill prompts them to provide either a description or a file path.

**Why this priority**: Good UX requires handling the empty-input case gracefully.

**Independent Test**: Can be tested by running `/wheel-create` with no arguments and verifying the skill prompts for input.

**Acceptance Scenarios**:

1. **Given** the user runs `/wheel-create` with no arguments, **When** the skill executes, **Then** it prompts the user to either describe a workflow or provide a file path with the `from:` prefix.

---

### Edge Cases

- What happens when the description is too vague to decompose into steps (e.g., "do something")?
  - The skill asks a clarifying question before proceeding.
- What happens when a SKILL.md has deeply nested conditional logic that doesn't map to the 4 step types?
  - Complex sections are wrapped as `agent` steps with the original intent noted in the instruction field.
- What happens when the generated workflow would exceed 20 steps?
  - The skill caps at 20 steps and consolidates remaining logic into broader steps.
- What happens when loop `condition` semantics can't be reliably inferred from natural language?
  - A reasonable default condition is generated and marked for user review in the output summary.
- What happens when `workflows/` directory doesn't exist?
  - The skill creates the `workflows/` directory before writing the file.

## Requirements

### Functional Requirements

- **FR-001**: The skill MUST accept a single argument string. If the string starts with `from:`, treat everything after the prefix as a file path (File Mode). Otherwise, treat the entire string as a natural language description (Description Mode).
- **FR-002**: If no arguments are provided, the skill MUST prompt the user to describe a workflow or provide a file path.
- **FR-003**: In File Mode, the skill MUST validate that the referenced file exists and is readable. If not, report an error and stop.
- **FR-004**: The skill MUST derive a workflow name as a short kebab-case slug. In Description Mode, from the description keywords. In File Mode, from the source filename.
- **FR-005**: If `workflows/<name>.json` already exists, the skill MUST append a numeric suffix (e.g., `name-2`). It MUST never overwrite an existing workflow file.
- **FR-006**: In Description Mode, the skill MUST parse the description to identify discrete steps, their types, dependencies, and outputs.
- **FR-007**: The skill MUST map each step to one of: `command` (shell commands), `agent` (LLM reasoning/writing), `branch` (conditional on exit code), or `loop` (repeated execution with condition).
- **FR-008**: The skill MUST generate `context_from` arrays based on data dependencies between steps.
- **FR-009**: The skill MUST generate output paths following wheel conventions: `.wheel/outputs/<step-id>.txt` for command steps, `reports/<name>.md` for agent steps producing reports.
- **FR-010**: The skill MUST mark the last step (or final convergence point) as `terminal: true`.
- **FR-011**: The skill MUST set `name` to the resolved workflow name and `version` to `"1.0.0"`.
- **FR-012**: In File Mode, the skill MUST read the source file and analyze its structure to identify discrete steps.
- **FR-013**: For SKILL.md files, the skill MUST parse headings, code blocks, and prose instructions, mapping each to a workflow step.
- **FR-014**: For shell scripts, the skill MUST parse command sequences and map to command steps, wrapping complex logic as agent steps.
- **FR-015**: For other structured files (JSON, YAML, Markdown), the skill MUST use best-effort heuristic parsing.
- **FR-016**: The skill MUST preserve the intent and ordering of the source file. It MUST NOT reorder or combine steps unless necessary for workflow validity.
- **FR-017**: Before writing the file, the skill MUST validate the generated JSON against the same checks as `workflow_load`: valid JSON, `name` string, non-empty `steps` array, every step has `id` and `type`, unique step IDs, valid branch targets, valid `context_from` references, valid `next` references.
- **FR-018**: If validation fails, the skill MUST attempt self-correction (fix references, deduplicate IDs). If self-correction fails, report errors and do not write the file.
- **FR-019**: The skill MUST write the validated workflow JSON to `workflows/<name>.json` with 2-space indentation.
- **FR-020**: After writing, the skill MUST report: file path, workflow name, step count, a brief summary of each step (id, type, one-line description), and the command to run it (`/wheel-run <name>`).
- **FR-021**: Command steps MUST have: `id`, `type: "command"`, `command`, `output`. Optional: `context_from`, `next`.
- **FR-022**: Agent steps MUST have: `id`, `type: "agent"`, `instruction`, `output`. Optional: `context_from`, `terminal`, `next`.
- **FR-023**: Branch steps MUST have: `id`, `type: "branch"`, `condition`, `if_zero`, `if_nonzero`. Optional: `context_from`.
- **FR-024**: Loop steps MUST have: `id`, `type: "loop"`, `command`, `condition`, `max_iterations`. Optional: `output`, `context_from`.
- **FR-025**: The skill MUST cap generated workflows at a maximum of 20 steps.

### Key Entities

- **Workflow**: A named automation pipeline with a version and an ordered array of steps. Stored as `workflows/<name>.json`.
- **Step**: A discrete unit of work within a workflow. Has an `id`, `type`, and type-specific fields. Types: command, agent, branch, loop.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Generated workflows pass `workflow_load` validation on first try 100% of the time.
- **SC-002**: Any existing SKILL.md in the plugin can be reverse-engineered into a runnable workflow.
- **SC-003**: Generated workflows run successfully via `/wheel-run` without manual JSON edits.
- **SC-004**: Users can create a workflow from a natural language description in under 30 seconds.
- **SC-005**: The skill handles name collisions by appending numeric suffixes without user intervention.

## Assumptions

- The 4 step types (command, agent, branch, loop) are sufficient for v1. Approval and parallel can be added later.
- The `workflow_load` validation function in `plugin-wheel/lib/workflow.sh` is the canonical validator.
- Workflow files live in `workflows/` at the repo root.
- The `--dry-run` flag is deferred to a future iteration (not in v1 scope).
- Maximum step count is capped at 20 to prevent runaway generation.
- The skill is implemented as a Markdown SKILL.md file with embedded bash, following the same pattern as other wheel skills.
