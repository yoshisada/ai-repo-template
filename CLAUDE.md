# AI Repo Template — Claude Code Instructions

## Mandatory Workflow (NON-NEGOTIABLE)

Every code change MUST follow this order. No exceptions.

### 1. Read Constitution
Before ANY code change, read `.specify/memory/constitution.md`.

### 2. Specify (/speckit.specify)
Create `specs/<feature>/spec.md` with user stories, FRs, and success criteria.

### 3. Plan (/speckit.plan)
Create `specs/<feature>/plan.md` with technical approach, phases, and file list.

### 4. Tasks (/speckit.tasks)
Create `specs/<feature>/tasks.md` with ordered, dependency-aware task breakdown.

### 5. Commit All Artifacts Before Code
spec.md, plan.md, and tasks.md MUST exist before any `src/` edits. Hooks enforce this.

### 6. Implement via /speckit.implement ONLY
**Do NOT write implementation code directly.** Run `/speckit.implement` which:
- Reads tasks.md and executes tasks phase-by-phase
- Marks each completed task as `[X]` in tasks.md
- Hooks verify tasks are being checked off — raw edits to src/ are BLOCKED until at least one task is marked `[X]`
- Every function MUST reference its spec FR in a comment
- Every test MUST reference the acceptance scenario it validates
- **After all tasks complete, runs PRD audit automatically** (see step 7)

### 7. PRD Audit (runs inside /speckit.implement)
After implementation completes, `/speckit.implement` runs `/speckit.audit` which:
- Checks every PRD requirement has a spec FR, implementation, and test
- **Attempts to fix** gaps (missing comments, missing tests, missing implementation)
- **If a gap cannot be fixed**: documents the reason in `specs/<feature>/blockers.md`
- **If blockers exist**: STOPS and asks for user confirmation before proceeding
- Reports overall compliance percentage

### 8. Test with Coverage Gate
- Run tests after every code change
- New/changed code MUST achieve >=80% test coverage
- Run `npm test` or `vitest run` to verify

### 9. Verify Before Done
- Tests pass
- Build succeeds
- Coverage >=80%
- PRD audit passed (or blockers acknowledged)
- No lint errors

## File Organization

- `src/` — source code (BLOCKED by hooks without spec + implement)
- `tests/` — test files
- `specs/` — feature specifications
- `docs/` — documentation and PRD
- `scripts/` — setup and utility scripts
- `.specify/` — speckit configuration
- `.claude/` — Claude Code hooks, skills, agents

## Hooks Enforcement (4 Gates)

This repo has PreToolUse hooks that:
- **Gate 1**: Block edits to `src/` unless `specs/*/spec.md` exists
- **Gate 2**: Block edits to `src/` unless `specs/*/plan.md` exists
- **Gate 3**: Block edits to `src/` unless `specs/*/tasks.md` exists
- **Gate 4**: Block edits to `src/` unless tasks.md has at least one `[X]` mark (forces `/speckit.implement`)
- **Always block** commits that include .env files
- **Always allow** edits to docs, specs, config, scripts, and tests

If a hook blocks you, complete the full speckit workflow: specify → plan → tasks → implement.

## Available Commands

### Speckit Workflow (run in this order)
1. `/speckit.specify` — Create a feature spec
2. `/speckit.plan` — Create implementation plan
3. `/speckit.tasks` — Generate task breakdown
4. `/speckit.implement` — Execute tasks + PRD audit
5. `/speckit.audit` — PRD compliance audit (also runs inside implement)

### Other
- `/speckit.constitution` — View/update project principles
- `/speckit.analyze` — Cross-artifact consistency check
- `/speckit.coverage` — Check test coverage gate

## Security

- NEVER commit .env, credentials, or API keys
- Validate input at system boundaries
- Hooks will block .env commits automatically
