# Session Prompt

Copy everything below this line and paste it as your first message in a new Claude Code session.

---

## Setup

This repo uses spec-first development enforced by Claude Code hooks. No code can be written without completing the speckit workflow first.

## Before you start

1. Read `CLAUDE.md` — it has the full 9-step mandatory workflow
2. Read `.specify/memory/constitution.md` — governing principles
3. Read `docs/PRD.md` — what you're building
4. Check `specs/` — any existing feature specs

## Workflow

The hooks will **block all edits to `src/`** until these gates pass:

| Gate | Artifact | How to create |
|------|----------|---------------|
| 1 | `specs/<feature>/spec.md` | Run `/speckit.specify` |
| 2 | `specs/<feature>/plan.md` + `contracts/interfaces.md` | Run `/speckit.plan` |
| 3 | `specs/<feature>/tasks.md` | Run `/speckit.tasks` |
| 4 | At least one `[X]` in tasks.md | Run `/speckit.implement` |

Commit all artifacts (spec, plan, contracts, tasks) before writing any implementation code.

## Rules

- **Never skip workflow steps.** The hooks enforce this mechanically.
- **Interface contracts are mandatory.** `/speckit.plan` must produce `contracts/interfaces.md` with exact function signatures. All implementation must match.
- **Mark tasks incrementally.** Mark each task `[X]` immediately after completing it. Commit after each phase.
- **Every function must reference its spec FR** in a comment (e.g., `// FR-001: ...`)
- **Every test must reference its acceptance scenario** (e.g., `// Story 1, Scenario 2`)
- **80% test coverage** on new code — constitutional requirement.
- **PRD audit runs automatically** at the end of `/speckit.implement`. Fix gaps or document blockers.
- **Don't ask unnecessary questions.** If the PRD and spec say to do it, do it.

## After implementation

The PRD audit runs as the final task in `/speckit.implement`. If it finds gaps:
1. It tries to fix them (add missing FR comments, write missing tests)
2. If unfixable, it documents blockers in `specs/<feature>/blockers.md`
3. It asks you to confirm before proceeding

## Start

Begin by reading the PRD and running the speckit workflow. Do not write any implementation code until spec, plan, contracts, and tasks are all committed.
