# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

This is the **kiln** Claude Code plugin (`@yoshisada/kiln`). It provides a spec-first development workflow with 4-gate enforcement, PRD-driven pipelines, integrated QA/debugging agents, and UI/UX evaluation — all as a Claude Code plugin that gets installed into consumer projects.

**This is the plugin source repo, not a consumer project.** The `src/` and `tests/` directories don't exist here — they're scaffolded in consumer projects by `plugin-kiln/bin/init.mjs`.

## Quick Start

New session? Run `/kiln:kiln-resume` to auto-detect where you left off and get your next steps.

First time? Run `/kiln:kiln-init` to set up kiln in an existing repo, or `/clay:clay-create-repo` for a brand new repo.

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

There is no test suite for the plugin itself. Testing is done by running the pipeline on consumer projects via `/kiln:kiln-build-prd`.

## Architecture

```
plugin-kiln/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest (name, version, description)
│   └── marketplace.json     # Distribution config for Claude Code marketplace
├── skills/                  # Skills — auto-discovered as /skill-name commands
│   ├── build-prd/           # Master pipeline orchestrator (agent teams)
│   ├── specify/,plan/,...   # Specify → Plan → Tasks → Implement → Audit workflow
│   ├── fix/                 # Bug fix loop (diagnose → fix → verify, inline)
│   ├── qa-*/                # QA testing (setup, checkpoint, final, live pass)
│   ├── ux-evaluate/         # UI/UX design review
│   ├── init/                # Add kiln to existing repo
│   └── next/                # Session pickup — detect in-progress work
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

**Agents** are spawned by skills (especially `/kiln:kiln-build-prd`) as team members. Each agent has a specific role and model assignment (sonnet for complex work, haiku for simple validation).

**Hooks** are shell scripts that run before every Edit/Write/Bash tool use. They enforce the workflow — you can't skip steps because the hooks block you.

**Templates** are copied into consumer projects and used by kiln skills to generate standardized spec/plan/tasks artifacts.

### Key pipeline flow (build-prd)

```
/kiln:kiln-build-prd
  → Reads PRD, designs agent team
  → Spawns: specifier → [researcher] → implementer(s) → [qa-engineer] → auditor(s) → retrospective
  → QA engineer runs alongside implementers (checkpoint feedback loop)
  → Debugger spawned on-demand in background when agents get stuck
  → Retrospective analyzes prompt/communication effectiveness
  → Creates PR with build-prd label
```

### Plugin workflow portability (NON-NEGOTIABLE)

Wheel workflows shipped inside a plugin (`plugin-<name>/workflows/*.json`) must be runnable from any consumer repo — not just from the plugin's source repo. That means command-step scripts **must not** be referenced via repo-relative paths like `plugin-shelf/scripts/foo.sh`, because that directory only exists inside this source repo. When a consumer installs the plugin, the scripts live under the plugin's install path (e.g. `~/.claude/plugins/cache/<org>-<mp>/<plugin>/<version>/scripts/`).

Rules for authoring plugin workflows:
- **Do not** hardcode `plugin-<name>/scripts/...` in workflow command steps. It silently works in the source repo and silently breaks everywhere else (the command emits "No such file or directory" and the workflow advances with empty step outputs).
- Workflow scripts invoked from command steps must be resolvable via a plugin-dir-aware variable (e.g. `${WORKFLOW_PLUGIN_DIR}/scripts/foo.sh`) that wheel exports before dispatching commands. If that variable isn't yet available from wheel, treat this as a pre-req gap and fix wheel first — don't paper over it with a repo-relative path.
- If you see `plugin-<name>/scripts/...` in an existing workflow JSON, that is a portability bug regardless of whether it currently "works" in this repo.

The symptom when this is violated: a consumer runs the plugin workflow, command steps fail silently with `No such file or directory`, and downstream agent/apply steps continue with empty input — producing plausible-looking but wrong output.

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

See `.specify/memory/constitution.md` Articles VII (Interface Contracts) and VIII (Incremental Task Completion).

## Hooks Enforcement (4 Gates)

Hooks block `src/` edits until spec + plan + tasks + at least one `[X]` task exist, and always block `.env` commits. See constitution Article IV.

If a hook blocks you, either:
- Complete the full kiln workflow: specify → plan → tasks → implement (for new features)
- Run `/kiln:kiln-fix` to fix a bug in an already-specced feature (existing specs satisfy the gates)

## Available Commands

### Project Setup
- `/kiln:kiln-init` — Add kiln to an existing repo
- `/kiln:kiln-next` — Pick up where you left off (run at start of every session)
- `/clay:clay-create-repo` — Create a brand new GitHub repo with kiln

### Kiln Workflow (run in this order)
1. `/specify` — Create a feature spec (pipeline-internal — stays bare)
2. `/plan` — Create implementation plan + interface contracts (pipeline-internal — stays bare)
3. `/tasks` — Generate task breakdown (pipeline-internal — stays bare)
4. `/implement` — Execute tasks incrementally + PRD audit (pipeline-internal — stays bare)
5. `/audit` — PRD compliance audit (pipeline-internal — stays bare; also runs inside implement)

### Debugging (no spec required)
- `/kiln:kiln-fix [issue]` — Fix a bug without creating a new PRD or spec. Describe the issue or pass a GitHub issue number. Diagnose and fix logic are now inline in `/kiln:kiln-fix`.

### QA (two workflows — same 4-agent team, different reporter mode)
- `/kiln:kiln-qa-pass` — **Standalone**. 4-agent team (e2e + chrome + ux + reporter). Findings filed as GitHub issues. Use outside the pipeline.
- `/kiln:kiln-qa-pipeline` — **Pipeline**. Same 4 agents but reporter routes findings to implementers, waits for fixes, re-tests, then files remaining issues. Used by `/kiln:kiln-build-prd`.
- `/kiln:kiln-qa-final` — Quick E2E gate. Just runs `npx playwright test` — green/red, no evaluation.
- `/kiln:kiln-qa-setup` — Install Playwright and scaffold QA test infrastructure
- `/kiln:kiln-qa-checkpoint` — Quick targeted QA on recently completed flows (feedback loop during implementation)
- `/kiln:kiln-ux-evaluate` — Standalone UI/UX design review using /chrome

### Other
- `/kiln:kiln-constitution` — View/update project principles
- `/kiln:kiln-analyze` — Cross-artifact consistency check
- `/kiln:kiln-coverage` — Check test coverage gate
- `/kiln:kiln-build-prd` — Full pipeline via agent teams (specify → plan → tasks → implement → audit → PR)
- `/kiln:kiln-analyze-issues` — Triage open GitHub issues: categorize, label, flag actionable, suggest closures, create backlog items
- `/issue [#N]` — Analyze a GitHub issue and propose improvements
- `/kiln:kiln-report-issue` — Quick capture bugs/friction to `.kiln/issues/`. The foreground path is now lean (4 steps, Apr 2026): `check-existing-issues` → `create-issue` → `write-issue-note` (single Obsidian note via `shelf:shelf-write-issue-note`) → `dispatch-background-sync` (fire-and-forget bg sub-agent). Heavy reconciliation (`shelf-sync` + `shelf-propose-manifest-improvement`) runs only once every `shelf_full_sync_threshold` invocations on the background path.
- `/kiln:kiln-feedback` — Log strategic product feedback (mission, scope, ergonomics, architecture, direction) to `.kiln/feedback/`. Distinct from `/kiln:kiln-report-issue` (tactical bugs/friction). No wheel workflow, no Obsidian write — just writes the local file and exits. `/kiln:kiln-distill` picks it up on the next run and leads PRD narratives with it.
- `/kiln:kiln-distill` — Bundle open items from `.kiln/feedback/` AND `.kiln/issues/` into a feature PRD. Feedback shapes the narrative (Background, Problem, Goals); issues form the tactical FR layer. Use as `/kiln:kiln-distill` or `/kiln:kiln-distill <category>` to filter.
- `/kiln:kiln-mistake` — Capture an AI mistake (wrong assumption, bad tool call, missed context) to `.kiln/mistakes/`. Shelf files a review proposal in `@inbox/open/` on the next sync.
- `/kiln:kiln-claude-audit` — Audit CLAUDE.md against `plugin-kiln/rubrics/claude-md-usefulness.md` and propose a git-diff-shaped drift report at `.kiln/logs/claude-md-audit-<timestamp>.md`. Never applies edits; human reviews and applies manually. Complements the cheap subcheck in `/kiln:kiln-doctor`.

### `.shelf-config` keys (shelf plugin)

Two counter-gating keys control how often `/kiln:kiln-report-issue`'s background sub-agent runs a full reconciliation. Defaults appended to `.shelf-config` on first read via `plugin-shelf/scripts/shelf-counter.sh ensure-defaults`.

| Key | Default | Effect |
|-----|---------|--------|
| `shelf_full_sync_counter` | `0` | Current counter. Incremented by 1 on every `/kiln:kiln-report-issue` invocation (by the background sub-agent, under `flock` where available). Reset to `0` when it reaches the threshold. |
| `shelf_full_sync_threshold` | `10` | Full-sync cadence. When the counter hits this value, the bg sub-agent runs `/shelf:shelf-sync` + `/shelf:shelf-propose-manifest-improvement` to completion. |

A transient sibling lockfile at `.shelf-config.lock` (gitignored) serializes the counter RMW. On systems without `flock` (macOS default), the helper runs unlocked and accepts ±1 drift per FR-006 of `specs/report-issue-speedup/spec.md`.

Per-day background logs are written to `.kiln/logs/report-issue-bg-<YYYY-MM-DD>.md` with pipe-delimited lines: `<ISO-8601> | counter_before=N | counter_after=N | threshold=N | action=increment|full-sync|error | notes=<string>`.

### `shelf-sync` no longer nests reflection

`shelf:shelf-sync` previously invoked `shelf:shelf-propose-manifest-improvement` as an inline workflow step. That step has been removed (Apr 2026). Reflection is now a separate concern: it's invoked by the `/kiln:kiln-report-issue` background sub-agent when the counter rolls over, or manually via `/shelf:shelf-propose-manifest-improvement`. Direct invocations of `/shelf:shelf-sync` no longer automatically propose manifest improvements.

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

Trimmed to the 5 most recent feature branches per `plugin-kiln/rubrics/claude-md-usefulness.md` (`active_technologies_keep_last_n`, default 5). Older entries remain in git history via `git log CLAUDE.md`.

- Node.js 18+ (init.mjs), Bash 5.x (hooks, workflows), Markdown (skills/agents) + jq, gh CLI (optional), Penpot MCP tools (for trim), wheel engine (build/plugin-polish-and-skill-ux-20260409)
- File-based (JSON workflows, markdown skills/templates, `.wheel/` state) (build/plugin-polish-and-skill-ux-20260409)
- Bash 5.x + jq (JSON parsing), Claude Code agent teams API (TeamCreate, TaskCreate, TaskList, TaskUpdate, TeamDelete, Agent, SendMessage) (build/wheel-team-primitives-20260409)
- File-based JSON state (`.wheel/state_*.json`) (build/wheel-team-primitives-20260409)
- Bash 5.x (command step scripts); Markdown + JSON (workflow + skill definitions). + wheel engine (`plugin-wheel/`), Obsidian MCP (`mcp__claude_ai_obsidian-manifest__*` for `@inbox/`), `jq` for JSON parsing, standard POSIX utilities (`grep -F` for verbatim match, `date` for ISO dates, `sed`/`tr` for slug derivation). (build/manifest-improvement-subroutine-20260416)

## Recent Changes
- build/fix-skill-with-recording-teams-20260420: `/kiln:kiln-fix` gained Step 7 "Record the Fix" — writes a local fix record to `.kiln/fixes/<date>-<slug>.md` and spawns two short-lived teams (`fix-record` for the Obsidian note, `fix-reflect` for an optional manifest-improvement proposal). Debug loop (Steps 2b–5) stays in main chat. New helpers under `plugin-kiln/scripts/fix-recording/`; new manifest type `@manifest/types/fix.md` (staged at `specs/.../assets/manifest-types/fix.md`).
- build/continuance-agent-20260331: Added Markdown (skill/agent definitions) + Bash (shell commands within skills) + None new — uses existing kiln plugin infrastructure, GitHub CLI (`gh`)
