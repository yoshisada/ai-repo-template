# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

This is the **kiln** Claude Code plugin (`@yoshisada/kiln`). It provides a spec-first development workflow with 4-gate enforcement, PRD-driven pipelines, integrated QA/debugging agents, and UI/UX evaluation — all as a Claude Code plugin that gets installed into consumer projects.

> **Migration Notice**: This plugin was renamed from `speckit-harness` to `kiln`.
> Old skill names (`/speckit-harness:speckit-*`) are no longer available.
> Use the new names: `/specify`, `/plan`, `/tasks`, `/implement`, `/audit`, etc.

**This is the plugin source repo, not a consumer project.** The `src/` and `tests/` directories don't exist here — they're scaffolded in consumer projects by `plugin-kiln/bin/init.mjs`.

## Quick Start

New session? Run `/resume` to auto-detect where you left off and get your next steps.

First time? Run `/init` to set up kiln in an existing repo, or `/create-repo` for a brand new repo.

## Build & Development

```bash
# No build step — skills/agents/hooks are markdown and shell scripts
# Plugin is published as an npm package:
npm publish --access public    # from plugin-kiln/ directory

# Run the scaffold locally (simulates what consumers do):
node plugin-kiln/bin/init.mjs init          # scaffold a project
node plugin-kiln/bin/init.mjs update        # re-sync templates

# Version management:
./scripts/version-bump.sh release      # bump release segment
./scripts/version-bump.sh feature      # bump feature segment
./scripts/version-bump.sh pr           # bump pr segment
cat VERSION                            # check current version
```

There is no test suite for the plugin itself. Testing is done by running the pipeline on consumer projects via `/build-prd`.

## Architecture

```
plugin-kiln/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest (name, version, description)
│   └── marketplace.json     # Distribution config for Claude Code marketplace
├── skills/                  # 28 skills — auto-discovered as /skill-name commands
│   ├── build-prd/           # Master pipeline orchestrator (agent teams)
│   ├── specify/,plan/,...   # Specify → Plan → Tasks → Implement → Audit workflow
│   ├── debug*/              # Bug fix loop (diagnose → fix → verify)
│   ├── qa-*/                # QA testing (setup, checkpoint, final, live pass)
│   ├── ux-evaluate/         # UI/UX design review
│   ├── init/                # Add kiln to existing repo
│   ├── resume/              # Session pickup — detect in-progress work
│   └── create-repo/         # New GitHub repo with kiln pre-configured
├── agents/                  # 7 agents — spawned as team members
│   ├── qa-engineer.md       # Visual QA with Playwright + /chrome (3 modes)
│   ├── ux-evaluator.md      # Design review (heuristics, a11y, visual, interaction)
│   ├── debugger.md          # Diagnose→fix→verify loop with 21 techniques
│   ├── prd-auditor.md       # PRD→Spec→Code→Test compliance
│   ├── smoke-tester.md      # Runtime verification (starts app, hits endpoints)
│   ├── spec-enforcer.md     # FR comment + test traceability
│   └── test-runner.md       # Run tests, report results
├── hooks/                   # 4 PreToolUse hooks — enforce workflow gates
│   ├── require-spec.sh      # 4-gate: blocks src/ edits without spec+plan+tasks+[X]
│   ├── version-increment.sh # Auto-increment VERSION 4th segment on code edits
│   ├── block-env-commit.sh  # Prevent .env files from being committed
│   └── require-feature-branch.sh  # Enforce branch naming conventions
├── templates/               # Spec, plan, tasks, interfaces, constitution templates
├── scaffold/                # Files copied into consumer projects by init.mjs
├── bin/init.mjs             # npm entrypoint — scaffolds consumer project structure
└── package.json             # npm package: @yoshisada/kiln
```

### How the pieces connect

**Skills** are user-invocable commands (`/skill-name`). They contain the logic and instructions.

**Agents** are spawned by skills (especially `/build-prd`) as team members. Each agent has a specific role and model assignment (sonnet for complex work, haiku for simple validation).

**Hooks** are shell scripts that run before every Edit/Write/Bash tool use. They enforce the workflow — you can't skip steps because the hooks block you.

**Templates** are copied into consumer projects and used by kiln skills to generate standardized spec/plan/tasks artifacts.

### Key pipeline flow (build-prd)

```
/build-prd
  → Reads PRD, designs agent team
  → Spawns: specifier → [researcher] → implementer(s) → [qa-engineer] → auditor(s) → retrospective
  → QA engineer runs alongside implementers (checkpoint feedback loop)
  → Debugger spawned on-demand in background when agents get stuck
  → Retrospective analyzes prompt/communication effectiveness
  → Creates PR with build-prd label
```

## Mandatory Workflow (NON-NEGOTIABLE)

Every code change in a consumer project MUST follow this order. No exceptions.

### 1. Read Constitution
Before ANY code change, read `.specify/memory/constitution.md`.

### 2. Specify (/specify)
Create `specs/<feature>/spec.md` with user stories, FRs, and success criteria.

### 3. Plan (/plan)
Create `specs/<feature>/plan.md` with technical approach, phases, and file list.

**Interface contracts are mandatory.** The plan MUST produce `specs/<feature>/contracts/interfaces.md` defining exact function signatures (name, params, return type, sync vs async) for every exported function. These signatures are the single source of truth — all implementation tasks and parallel agents MUST match them exactly.

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
Checks every PRD requirement has a spec FR, implementation, and test. Attempts to fix gaps. Documents unfixable gaps in `specs/<feature>/blockers.md`. Reports compliance percentage.

### 8. Test with Coverage Gate
New/changed code MUST achieve >=80% test coverage. Run `npm test` or `vitest run`.

### 9. Smoke Test (runs inside /implement)
The `smoke-tester` agent scaffolds a fresh project, starts it, and verifies it actually works at runtime.

### 10. Verify Before Done
Tests pass, build succeeds, coverage >=80%, PRD audit passed (or blockers acknowledged), smoke test passed, no lint errors.

## Implementation Rules

### Incremental Progress (NON-NEGOTIABLE)
- Mark each task `[X]` in tasks.md **immediately** after completing it
- Commit after each completed phase, not at the end
- If a task fails, leave it `[ ]` and document why before moving on

### Interface Contract Compliance
- Every exported function signature MUST match `contracts/interfaces.md`
- If you need to change a signature, update `contracts/interfaces.md` FIRST
- No `async` unless the contract says `async`. No renamed functions. No changed return types.

### Sub-Agent Coordination
- Give every agent the `contracts/interfaces.md` file
- Each agent owns specific files — no two agents write to the same file
- Agent output is verified against the contracts before merging

## Hooks Enforcement (4 Gates)

PreToolUse hooks that run on every Edit/Write:
- **Gate 1**: Block edits to `src/` unless `specs/*/spec.md` exists
- **Gate 2**: Block edits to `src/` unless `specs/*/plan.md` exists
- **Gate 3**: Block edits to `src/` unless `specs/*/tasks.md` exists
- **Gate 4**: Block edits to `src/` unless tasks.md has at least one `[X]` mark
- **Always block** commits that include .env files
- **Auto-increment** VERSION 4th segment on code file edits
- **Always allow** edits to docs, specs, config, scripts, and tests

If a hook blocks you, either:
- Complete the full kiln workflow: specify → plan → tasks → implement (for new features)
- Run `/fix` to fix a bug in an already-specced feature (existing specs satisfy the gates)

## Available Commands

### Project Setup
- `/init` — Add kiln to an existing repo
- `/resume` — Pick up where you left off (run at start of every session)
- `/create-repo` — Create a brand new GitHub repo with kiln

### Kiln Workflow (run in this order)
1. `/specify` — Create a feature spec
2. `/plan` — Create implementation plan + interface contracts
3. `/tasks` — Generate task breakdown
4. `/implement` — Execute tasks incrementally + PRD audit
5. `/audit` — PRD compliance audit (also runs inside implement)

### Debugging (no spec required)
- `/fix [issue]` — Fix a bug without creating a new PRD or spec. Describe the issue or pass a GitHub issue number.
- `/debug-diagnose` — Classify an issue and collect diagnostics (used by `/fix`)
- `/debug-fix` — Apply a fix and verify it (used by `/fix`)

### QA (two workflows — same 4-agent team, different reporter mode)
- `/qa-pass` — **Standalone**. 4-agent team (e2e + chrome + ux + reporter). Findings filed as GitHub issues. Use outside the pipeline.
- `/qa-pipeline` — **Pipeline**. Same 4 agents but reporter routes findings to implementers, waits for fixes, re-tests, then files remaining issues. Used by `/build-prd`.
- `/qa-final` — Quick E2E gate. Just runs `npx playwright test` — green/red, no evaluation.
- `/qa-setup` — Install Playwright and scaffold QA test infrastructure
- `/qa-checkpoint` — Quick targeted QA on recently completed flows (feedback loop during implementation)
- `/ux-evaluate` — Standalone UI/UX design review using /chrome

### Other
- `/constitution` — View/update project principles
- `/analyze` — Cross-artifact consistency check
- `/coverage` — Check test coverage gate
- `/build-prd` — Full pipeline via agent teams (specify → plan → tasks → implement → audit → PR)
- `/analyze-issues` — Triage open GitHub issues: categorize, label, flag actionable, suggest closures, create backlog items
- `/issue [#N]` — Analyze a GitHub issue and propose improvements
- `/report-issue` — Quick capture bugs/friction to `.kiln/issues/`

## Versioning

Format: `release.feature.pr.edit` — `000.000.000.000`

| Segment | Trigger | Reset |
|---------|---------|-------|
| **release** (1st) | `./scripts/version-bump.sh release` | Resets feature, pr, edit to 0 |
| **feature** (2nd) | `./scripts/version-bump.sh feature` | Resets pr, edit to 0 |
| **pr** (3rd) | `./scripts/version-bump.sh pr` | Resets edit to 0 |
| **edit** (4th) | Auto — increments on every file edit (Edit/Write hook) | — |

Stored in `VERSION` file (project root) and synced to `plugin-kiln/package.json`. The `.version.lock` directory is a transient concurrency lock — do not commit it.

## Security

- NEVER commit .env, credentials, or API keys
- Validate input at system boundaries
- Hooks will block .env commits automatically
- QA credentials go in `.kiln/qa/.env.test` (gitignored)

## Active Technologies
- Markdown (skill/agent definitions) + Bash (shell commands within skills) + None new — uses existing kiln plugin infrastructure, GitHub CLI (`gh`) (build/continuance-agent-20260331)
- Filesystem — `.kiln/logs/` for reports, `.kiln/issues/` for backlog items (build/continuance-agent-20260331)
- Markdown (skill/agent definitions), Bash (shell commands within skills), Node.js (init.mjs scaffold) + None — uses existing kiln plugin infrastructure (001-kiln-polish)
- Filesystem — `.kiln/qa/` for QA artifacts (001-kiln-polish)
- Markdown (skill definition) + Bash (shell commands within skill via `gh` CLI) + `gh` CLI (GitHub CLI), existing `/report-issue` skill (build/analyze-issues-20260401)
- N/A (labels applied to GitHub issues, backlog items written to `.kiln/issues/`) (build/analyze-issues-20260401)
- Bash 5.x (hook scripts), Markdown (skill/agent definitions) + git CLI, jq (JSON parsing in hooks), Docker CLI (for container-aware projects) (build/pipeline-reliability-20260401)
- N/A — file-based lock and marker files only (build/pipeline-reliability-20260401)
- Markdown (skill/agent definitions), Bash 5.x (hook scripts), Node.js 18+ (init.mjs), JSON (configs) + Claude Code plugin system, GitHub CLI (`gh`), Playwright (QA config changes) (build/qa-tooling-templates-20260401)
- Filesystem — `.kiln/` directory tree, `specs/` artifacts (build/qa-tooling-templates-20260401)
- Markdown (skill definitions), Bash 5.x (hooks), Node.js 18+ (init.mjs scaffold) + `jq` (JSON parsing in hooks), `bash -n` (syntax checking), `gh` CLI (GitHub operations) (build/pipeline-workflow-polish-20260401)
- Filesystem — `.kiln/` directory tree for issues, logs, roadmap, QA artifacts (build/pipeline-workflow-polish-20260401)
- Markdown (skill definitions) + Bash (inline shell commands in skills) + None — shelf plugin skills are Markdown files with embedded shell/MCP instructions (build/shelf-config-artifact-20260403)
- `.shelf-config` plain-text key-value file at repo roo (build/shelf-config-artifact-20260403)
- Bash 5.x + `jq` (JSON parsing), existing wheel engine libs (state.sh, workflow.sh, dispatch.sh, engine.sh, context.sh, lock.sh) (build/wheel-session-guard-20260405)
- `.wheel/state.json` (file-based JSON state) (build/wheel-session-guard-20260405)
- Bash 5.x (shell commands in SKILL.md), Markdown (skill definition) + `jq` (JSON generation/validation), existing wheel engine libs (`plugin-wheel/lib/workflow.sh`) (build/wheel-create-workflow-20260406)
- Filesystem — `workflows/<name>.json` at repo roo (build/wheel-create-workflow-20260406)
- Bash 5.x + jq (JSON parsing), existing wheel engine libs (state.sh, workflow.sh, dispatch.sh, engine.sh, context.sh, lock.sh, guard.sh) (build/wheel-workflow-composition-20260407)
- File-based JSON state in `.wheel/state_*.json` (build/wheel-workflow-composition-20260407)
- Bash 5.x, Markdown (skill definitions) + jq (JSON parsing), existing wheel engine libs (`plugin-wheel/lib/workflow.sh`) (build/developer-tooling-polish-20260407)
- Filesystem — reads `workflows/*.json`, writes `.kiln/qa/test-audit-report.md` (build/developer-tooling-polish-20260407)

## Recent Changes
- build/continuance-agent-20260331: Added Markdown (skill/agent definitions) + Bash (shell commands within skills) + None new — uses existing kiln plugin infrastructure, GitHub CLI (`gh`)
