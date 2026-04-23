# {{PROJECT_NAME}} — Claude Code Instructions

## Quick Start

- Start every session with `/kiln:kiln-next` — it inspects current state and tells you the next step.
- First time setting up kiln? Run `/kiln:kiln-init`.

## Mandatory Workflow

Every code change follows this order. Hooks enforce it.

1. `/specify` — write the spec (user stories + FRs + success criteria).
2. `/plan` — write the technical plan + `contracts/interfaces.md`.
3. `/tasks` — break the plan into tasks.
4. `/implement` — execute tasks incrementally. Runs the PRD audit on completion.

Hooks block edits to `src/` until a spec, plan, tasks file, and at least one `[X]` task exist.

## Available Commands

Run `/kiln:kiln-next` at session start — it surfaces the right command for your current state. For the full catalog, see each plugin's README.

## Security

- Never commit `.env`, credentials, or API keys — hooks block this.
- Validate input at system boundaries.
