# AI Repo Template — Claude Code Instructions

## Mandatory Workflow (NON-NEGOTIABLE)

Every code change MUST follow this order. No exceptions.

### 1. Read Constitution
Before ANY code change, read `.specify/memory/constitution.md`.

### 2. Find or Create Spec
Every feature needs a spec in `specs/<feature>/spec.md` with:
- User stories with Given/When/Then acceptance scenarios
- Functional requirements with unique IDs (FR-001, FR-002, ...)
- Measurable success criteria

### 3. Commit Spec Before Code
The spec MUST be committed to git before any implementation begins.

### 4. Implement with Traceability
- Every function MUST reference its spec FR in a comment
- Every test MUST reference the acceptance scenario it validates

### 5. Test with Coverage Gate
- Run tests after every code change
- New/changed code MUST achieve >=80% test coverage
- Run `npm test` or `vitest run` to verify

### 6. Verify Before Done
- Tests pass
- Build succeeds
- Coverage >=80%
- No lint errors

## File Organization

- `src/` — source code (BLOCKED by hooks without a spec)
- `tests/` — test files
- `specs/` — feature specifications
- `docs/` — documentation and PRD
- `scripts/` — setup and utility scripts
- `.specify/` — speckit configuration
- `.claude/` — Claude Code hooks, skills, agents

## Hooks Enforcement

This repo has PreToolUse hooks that:
- **Block** edits to `src/` when no spec exists in `specs/`
- **Block** commits that include .env files
- **Allow** edits to docs, specs, config, and scripts always

If a hook blocks you, write the spec first. That's the point.

## Available Commands

### Speckit Workflow
- `/speckit.constitution` — View/update project principles
- `/speckit.specify` — Create a feature spec
- `/speckit.plan` — Create implementation plan
- `/speckit.tasks` — Generate task breakdown
- `/speckit.implement` — Execute tasks
- `/speckit.analyze` — Cross-artifact consistency check
- `/speckit.audit` — PRD compliance audit (custom)
- `/speckit.coverage` — Check test coverage gate (custom)

### Ruflo/Claude-Flow
- `/claude-flow-swarm` — Multi-agent swarm coordination
- `/claude-flow-memory` — Persistent memory across sessions

## Security

- NEVER commit .env, credentials, or API keys
- Validate input at system boundaries
- Hooks will block .env commits automatically
