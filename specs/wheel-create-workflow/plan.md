# Implementation Plan: Wheel Create Workflow

**Branch**: `build/wheel-create-workflow-20260406` | **Date**: 2026-04-06 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/wheel-create-workflow/spec.md`

## Summary

A `/wheel-create` skill that generates valid wheel workflow JSON files from two input modes: natural language description and file-based reverse engineering (from: prefix). The skill is implemented as a Markdown SKILL.md with embedded bash, following the same pattern as existing wheel skills (`wheel-run`, `wheel-status`, `wheel-stop`).

## Technical Context

**Language/Version**: Bash 5.x (shell commands in SKILL.md), Markdown (skill definition)
**Primary Dependencies**: `jq` (JSON generation/validation), existing wheel engine libs (`plugin-wheel/lib/workflow.sh`)
**Storage**: Filesystem — `workflows/<name>.json` at repo root
**Testing**: Manual validation via `workflow_load` and `/wheel-run`
**Target Platform**: Any system running Claude Code with the wheel plugin
**Project Type**: Claude Code plugin skill (Markdown + Bash)
**Performance Goals**: Generate workflow in under 30 seconds
**Constraints**: Max 20 steps per workflow, no new dependencies
**Scale/Scope**: Single skill file, single output JSON file per invocation

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-First | PASS | spec.md exists with FRs and acceptance scenarios |
| II. 80% Coverage | N/A | Plugin skill — no test suite (testing is manual via workflow_load) |
| III. PRD as Source | PASS | PRD at docs/features/2026-04-06-wheel-create-workflow/PRD.md |
| IV. Hooks Enforce | PASS | Existing hooks remain, no changes needed |
| V. E2E Testing | N/A | Plugin skill — validated by generating and running a workflow |
| VI. Small Changes | PASS | Single SKILL.md file under 500 lines |
| VII. Interface Contracts | PASS | contracts/interfaces.md defines the skill's structure |
| VIII. Incremental Tasks | PASS | Tasks will be marked [X] incrementally |

No violations.

## Project Structure

### Documentation (this feature)

```text
specs/wheel-create-workflow/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Workflow JSON schema reference
├── contracts/           # Interface contracts
│   └── interfaces.md    # Skill structure and validation contract
└── tasks.md             # Task breakdown (created by /tasks)
```

### Source Code (repository root)

```text
plugin-wheel/
└── skills/
    └── wheel-create/
        └── SKILL.md     # The new skill (single file)
```

**Structure Decision**: Single SKILL.md file in the existing wheel plugin skills directory. Follows the identical pattern of `wheel-run`, `wheel-status`, `wheel-stop`. No new directories, libraries, or dependencies.

## Phase 0: Research

### Decision 1: Workflow JSON Generation Approach

**Decision**: Use `jq` for JSON construction and validation within the SKILL.md bash blocks. The skill uses Claude's LLM reasoning (via the skill execution context) to decompose descriptions into steps, then emits the JSON using `jq` for structural correctness.

**Rationale**: `jq` is already a dependency of the wheel engine (used in all lib/*.sh files). It guarantees valid JSON output and allows validation against the same checks as `workflow_load`.

**Alternatives considered**:
- Heredoc with manual escaping — fragile, prone to JSON syntax errors
- Node.js script — adds a dependency; overkill for JSON generation

### Decision 2: Step Type Inference Strategy

**Decision**: The SKILL.md instructs the LLM (executing the skill) to classify each identified step based on these heuristics:
- Shell commands, file checks, data gathering → `command`
- Tasks requiring LLM reasoning, writing, analysis → `agent`
- Conditional logic ("if X then Y else Z") → `branch`
- Repeated execution ("repeat until", "for each") → `loop`

**Rationale**: The LLM executing the skill has full context to make these classifications. Encoding rigid regex patterns in bash would be brittle. The skill's markdown instructions guide the LLM's decomposition.

### Decision 3: File Mode Parsing Strategy

**Decision**: The SKILL.md instructs the LLM to read the source file and decompose it structurally:
- SKILL.md: headings = step boundaries, code blocks = command steps, prose = agent steps
- Shell scripts: command sequences = command steps, complex logic = agent steps
- Other files: best-effort heuristic

**Rationale**: The LLM is better at understanding document structure and intent than bash pattern matching. The skill provides guidelines, the LLM applies judgment.

### Decision 4: Name Derivation

**Decision**: The LLM generates a kebab-case slug from the input. For descriptions, extract 2-4 key action/noun words. For files, use the parent directory name or filename stem.

**Rationale**: Simple, deterministic enough for practical use. Collision handling (append `-2`, `-3`) is done via bash loop checking file existence.

## Phase 1: Design & Contracts

See [contracts/interfaces.md](./contracts/interfaces.md) for the skill structure contract.
See [data-model.md](./data-model.md) for the workflow JSON schema.

## Notes

- The skill is a Markdown file that guides LLM behavior — there are no exported functions in the traditional sense
- The "interface contract" defines the skill's structure, sections, and the JSON schema it must produce
- Validation reuses `workflow_load` from `plugin-wheel/lib/workflow.sh`
