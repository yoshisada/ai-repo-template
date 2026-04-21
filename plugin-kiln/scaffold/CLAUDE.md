# AI Repo Template — Claude Code Instructions

## Quick Start

New session? Read `docs/session-prompt.md` for the full onboarding prompt.

## Mandatory Workflow (NON-NEGOTIABLE)

Every code change MUST follow this order. No exceptions.

### 1. Read Constitution
Before ANY code change, read `.specify/memory/constitution.md`.

### 2. Specify (/specify)
Create `specs/<feature>/spec.md` with user stories, FRs, and success criteria.

### 3. Plan (/plan)
Create `specs/<feature>/plan.md` with technical approach, phases, and file list.

**Interface contracts are mandatory.** The plan MUST produce `specs/<feature>/contracts/interfaces.md` defining exact function signatures (name, params, return type, sync vs async) for every exported function. Use `.specify/templates/interfaces-template.md` as the format. These signatures are the single source of truth — all implementation tasks and parallel agents MUST match them exactly.

### 4. Tasks (/tasks)
Create `specs/<feature>/tasks.md` with ordered, dependency-aware task breakdown.

### 5. Commit All Artifacts Before Code
spec.md, plan.md, tasks.md, and contracts/ MUST exist before any `src/` edits. Hooks enforce this.

### 6. Implement via /implement ONLY
**Do NOT write implementation code directly.** Run `/implement` which:
- Reads tasks.md and executes tasks phase-by-phase
- **Marks each task `[X]` IMMEDIATELY after completing it** — not in a batch at the end
- **Commits after each phase** (not one giant commit at the end)
- Hooks verify tasks are being checked off — raw edits to src/ are BLOCKED until at least one task is marked `[X]`
- Every function MUST match its signature in `contracts/interfaces.md`
- Every function MUST reference its spec FR in a comment
- Every test MUST reference the acceptance scenario it validates
- **After all tasks complete, runs PRD audit automatically** (see step 7)

### 7. PRD Audit (runs inside /implement)
After implementation completes, `/implement` runs `/audit` which:
- Checks every PRD requirement has a spec FR, implementation, and test
- **Attempts to fix** gaps (missing comments, missing tests, missing implementation)
- **If a gap cannot be fixed**: documents the reason in `specs/<feature>/blockers.md`
- **If blockers exist**: STOPS and asks for user confirmation before proceeding
- Reports overall compliance percentage

### 8. Test with Coverage Gate
- Run tests after every code change
- New/changed code MUST achieve >=80% test coverage
- Run `npm test` or `vitest run` to verify

### 9. Smoke Test (runs inside /implement)
After tests pass, the `smoke-tester` agent runs a runtime verification:
- Detects project type (CLI, web app, mobile, API) from plan.md
- Scaffolds a fresh project in a temp directory
- Actually runs it (starts dev server, executes CLI commands, hits endpoints)
- For web: uses Playwright headless or curl to verify the server responds
- For CLI: runs the binary and checks output/exit codes
- For mobile: runs Maestro flow if available, otherwise verifies prebuild
- Reports PASS/FAIL with exact error output if something breaks

### 10. Verify Before Done
- Tests pass
- Build succeeds
- Coverage >=80%
- PRD audit passed (or blockers acknowledged)
- Smoke test passed
- No lint errors

## Implementation Rules

### Incremental Progress (NON-NEGOTIABLE)
- Mark each task `[X]` in tasks.md **immediately** after completing it
- Commit after each completed phase, not at the end
- This creates a reviewable audit trail in git history
- If a task fails, leave it `[ ]` and document why before moving on

### Interface Contract Compliance
- Every exported function signature MUST match `contracts/interfaces.md`
- If you need to change a signature, update `contracts/interfaces.md` FIRST
- Parallel agents receive the contracts file as their source of truth
- No `async` unless the contract says `async`. No renamed functions. No changed return types.

### Sub-Agent Coordination
When using parallel agents for implementation:
- Give every agent the `contracts/interfaces.md` file
- Each agent owns specific files — no two agents write to the same file
- Agent output is verified against the contracts before merging

## File Organization

- `src/` — source code (BLOCKED by hooks without spec + implement)
- `tests/` — test files
- `specs/` — feature specifications (spec, plan, tasks, contracts, blockers)
- `docs/` — documentation, PRD, and session prompt
- `scripts/` — setup and utility scripts
- `.specify/` — kiln configuration and templates
- `.claude/` — Claude Code hooks, skills, agents

## Hooks Enforcement (4 Gates)

This repo has PreToolUse hooks that:
- **Gate 1**: Block edits to `src/` unless `specs/*/spec.md` exists
- **Gate 2**: Block edits to `src/` unless `specs/*/plan.md` exists
- **Gate 3**: Block edits to `src/` unless `specs/*/tasks.md` exists
- **Gate 4**: Block edits to `src/` unless tasks.md has at least one `[X]` mark (forces `/implement`)
- **Always block** commits that include .env files
- **Always allow** edits to docs, specs, config, scripts, and tests

If a hook blocks you, complete the full kiln workflow: specify → plan → tasks → implement.

## Available Commands

### Kiln Workflow (run in this order)
1. `/specify` — Create a feature spec
2. `/plan` — Create implementation plan + interface contracts
3. `/tasks` — Generate task breakdown
4. `/implement` — Execute tasks incrementally + PRD audit
5. `/audit` — PRD compliance audit (also runs inside implement)

### Other
- `/kiln:kiln-constitution` — View/update project principles
- `/kiln:kiln-analyze` — Cross-artifact consistency check
- `/kiln:kiln-coverage` — Check test coverage gate

## Versioning

Format: `release.feature.pr.edit` — `000.000.000.000`

The 4th segment (edit) auto-increments on every file edit via a PreToolUse hook. Stored in `VERSION` file and synced to `package.json`. The `.version.lock` directory is a transient concurrency lock — do not commit it.

## Security

- NEVER commit .env, credentials, or API keys
- Validate input at system boundaries
- Hooks will block .env commits automatically
