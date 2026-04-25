# {{PROJECT_NAME}} — Claude Code Instructions

## What kiln Is For

Kiln turns captured ideas, feedback, bug reports, and roadmap items into shipped code via a spec-first pipeline. The loop:

1. **Capture** — file the thing in the surface that matches its shape: `/kiln:kiln-report-issue` (bugs / friction), `/kiln:kiln-feedback` (strategic notes), `/kiln:kiln-roadmap` (typed product-direction items), `/kiln:kiln-mistake` (AI failures).
2. **Distill** — `/kiln:kiln-distill` bundles open captures into a feature PRD.
3. **Ship** — `/kiln:kiln-build-prd` runs specify → plan → tasks → implement → audit → PR end-to-end. Hooks block any `src/` edit until a spec, plan, tasks file, and at least one `[X]` task exist.
4. **Improve** — retros and captured AI mistakes feed the next round; manifest-improvement proposals route through shelf for human apply.

You don't need to memorize commands — `/kiln:kiln-next` at session start tells you the next step.

**Two load-bearing invariants:**
- **Propose-don't-apply** — kiln never auto-merges its own self-improvements; every change routes through a human apply step.
- **Senior-engineer-merge bar** — kiln targets simple code, FR-traced tests, useful PR descriptions, retros with real insight. Hooks are the floor; the bar is higher.

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

## Testing

- Run `npm test` (or `vitest run`) before every commit.
- New / changed code must clear the constitution's coverage gate (≥80%) — verify via `/kiln:kiln-coverage`.
- E2E and visual checks: `/kiln:kiln-qa-final` (quick green/red) and `/kiln:kiln-qa-pass` (full 4-agent team).

## Security

- Never commit `.env`, credentials, or API keys — hooks block this.
- Validate input at system boundaries.
