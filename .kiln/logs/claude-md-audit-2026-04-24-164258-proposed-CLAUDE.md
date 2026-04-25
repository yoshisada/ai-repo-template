# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

This is the **kiln** Claude Code plugin (`@yoshisada/kiln`) — part of a five-plugin suite (`kiln` spec-first pipeline · `clay` idea → repo · `shelf` Obsidian mirror · `trim` design ↔ code sync · `wheel` workflow engine) that together form a mostly-autonomous build system for a solo builder. You feed it ideas, feedback, issues, and roadmap items; it researches, specs, plans, implements, QAs, audits, and ships — escalating only when accumulated precedent doesn't already tell it what you'd want.

**The loop is the product.** Captures (`/kiln:kiln-roadmap`, `/kiln:kiln-feedback`, `/kiln:kiln-mistake`, `/kiln:kiln-report-issue`) become PRDs via `/kiln:kiln-distill`; PRDs ship via `/kiln:kiln-build-prd`; retros and captured AI mistakes feed the next round and route through shelf as manifest-improvement proposals. Full thesis: `.kiln/vision.md`.

**Two load-bearing invariants:**
- **Propose-don't-apply is universal** — every self-improvement (manifest edits, template changes, mistake corrections) routes through a human apply step. The system never auto-merges its own proposals.
- **The bar is senior-engineer-merge, not audit-floor** — simple code, FR-traced tests, sparse load-bearing comments, useful PR descriptions, retros with actual insight. Hooks are the floor; the bar is higher.

**This is the plugin source repo, not a consumer project.** The `src/` and `tests/` directories don't exist here — they're scaffolded in consumer projects by `plugin-kiln/bin/init.mjs`.

## Quick Start

New session? Run `/kiln:kiln-next` to auto-detect where you left off and get your next steps.

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

**Tests.** `plugin-kiln/tests/` holds skill-test fixtures run via `/kiln:kiln-test [plugin] [test]` (auto-detects plugin from CWD; verdict reports at `.kiln/logs/kiln-test-<uuid>.md`). `plugin-wheel/tests/` holds shell unit tests under `unit/`, `model-dispatch/`, and feature-specific directories; run individual files directly (`bash plugin-wheel/tests/unit/<name>.sh`). End-to-end validation of the build-prd pipeline still happens by running it on consumer projects.

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

## How the Loop Works

The five-plugin suite exists to close one loop. Anything you'd want the system to act on goes through it.

1. **Capture** — file the thing in the surface that matches its shape:
   - `/kiln:kiln-report-issue` — bugs / friction with something that already exists.
   - `/kiln:kiln-feedback` — strategic notes about mission, scope, or direction.
   - `/kiln:kiln-roadmap` — typed product-direction items (feature / goal / research / constraint / non-goal / milestone / critique). Adversarial interview pushes back on thin ideas.
   - `/kiln:kiln-mistake` — AI failures (wrong assumption, bad tool call, missed context). Routed through shelf as a manifest-improvement proposal.
2. **Distill** — `/kiln:kiln-distill` bundles open captures into a feature PRD. Feedback + current-phase roadmap items shape the narrative; issues form the FR layer; raw un-promoted sources are refused at Step 0.5 (they must promote to a roadmap item first).
3. **Ship** — `/kiln:kiln-build-prd` runs the agent-team pipeline (specify → plan → tasks → implement → audit → PR) end-to-end. `/kiln:kiln-fix` is the spec-less escape hatch for bugs in already-specced features. Hooks gate every `src/` edit on spec presence + at least one `[X]` task. The QA team runs alongside implementers; the debugger spawns on demand when agents stall.
4. **Improve** — retros become next-cycle captures; AI mistakes become `@inbox/open/` proposals via `shelf-sync`; the maintainer reviews and applies → templates and skills evolve from evidence, not redesign cycles.

`/kiln:kiln-next` reads where you are in the loop and tells you the next step. Run it at session start.

### Context-informed autonomy

The system deliberates over accumulated precedent (prior feedback, approved manifest proposals, declined non-goals, captured mistakes) before deciding whether to act or escalate. Precedent present → it acts; precedent absent or ambiguous → it asks. The success signal is high-signal escalations, not friction — see vision §"How we'll know we're winning" (b).

### Governance lives in the constitution

The spec-first ordering, the `[X]`-task rule, the >=80% coverage gate, the interface-contracts requirement, and the "no `src/` edits without artifacts" hooks are all enforced by `.specify/memory/constitution.md` (Articles IV, VII, VIII) and the four PreToolUse hooks. Don't operate the pipeline by hand — `/kiln:kiln-build-prd` (or `/kiln:kiln-fix`) runs it for you.

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
- `/kiln:kiln-report-issue` — Quick capture of bugs / friction to `.kiln/issues/`. Background sub-agent runs full Obsidian reconciliation every `shelf_full_sync_threshold` invocations. See `plugin-kiln/skills/kiln-report-issue/SKILL.md`.
- `/kiln:kiln-feedback` — Log strategic product feedback (mission, scope, direction) to `.kiln/feedback/`. Distinct from `kiln-report-issue` (tactical). `/kiln:kiln-distill` picks it up on the next run.
- `/kiln:kiln-roadmap [description]` — Capture a typed roadmap item via adversarial interview. Kinds: feature / goal / research / constraint / non-goal / milestone / critique. AI-native sizing only (no human-time / T-shirt fields). Flags: `--quick`, `--vision`, `--phase`, `--check`, `--reclassify`, `--promote`. See `plugin-kiln/skills/kiln-roadmap/SKILL.md`.
- `/kiln:kiln-distill [category]` — Bundle open feedback + current-phase roadmap items + issues into a feature PRD. Step 0.5 gate refuses un-promoted raw sources. Flags: `--phase`, `--addresses`, `--kind`. See `plugin-kiln/skills/kiln-distill/SKILL.md`.
- `/kiln:kiln-mistake` — Capture an AI mistake (wrong assumption, bad tool call, missed context) to `.kiln/mistakes/`. Shelf files a review proposal in `@inbox/open/` on the next sync.
- `/kiln:kiln-claude-audit` — Audit CLAUDE.md against `plugin-kiln/rubrics/claude-md-usefulness.md` and propose a git-diff-shaped drift report at `.kiln/logs/claude-md-audit-<timestamp>.md`. Never applies edits; human reviews and applies manually. Complements the cheap subcheck in `/kiln:kiln-doctor`.
- `/kiln:kiln-hygiene` — Full structural-hygiene audit against `plugin-kiln/rubrics/structural-hygiene.md`. Walks the repo for merged-PRD-not-archived items, orphaned top-level folders, and unreferenced `.kiln/` artifacts, then writes a review preview at `.kiln/logs/structural-hygiene-<timestamp>.md`. Never applies edits. `/kiln:kiln-doctor` subcheck `3h` is the cheap-signals tripwire that points at this skill.
- `/kiln:kiln-hygiene backfill` — One-shot propose-don't-apply backfill of PRD `derived_from:` frontmatter. Writes preview at `.kiln/logs/prd-derived-from-backfill-<timestamp>.md`. Idempotent — safe to re-run.
- `/kiln:kiln-test [plugin] [test]` — Skill-test harness: invokes real `claude --print` subprocesses against `/tmp/kiln-test-<uuid>/` fixtures via a classifier agent. V1 plugin-skill substrate only. See `plugin-kiln/skills/kiln-test/SKILL.md`.

Shelf-plugin reference (`.shelf-config` keys, counter-gating, removed inline reflection step) lives in `plugin-shelf/README.md`.

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

- Bash 5.x + jq (JSON parsing), Claude Code agent teams API (TeamCreate, TaskCreate, TaskList, TaskUpdate, TeamDelete, Agent, SendMessage) (build/wheel-team-primitives-20260409)
- File-based JSON state (`.wheel/state_*.json`) (build/wheel-team-primitives-20260409)
- Bash 5.x (command step scripts); Markdown + JSON (workflow + skill definitions). + wheel engine (`plugin-wheel/`), Obsidian MCP (`mcp__claude_ai_obsidian-manifest__*` for `@inbox/`), `jq` for JSON parsing, standard POSIX utilities (`grep -F` for verbatim match, `date` for ISO dates, `sed`/`tr` for slug derivation). (build/manifest-improvement-subroutine-20260416)
- Shared project-context reader under `plugin-kiln/scripts/context/` (`read-project-context.sh` + `read-prds.sh` + `read-plugins.sh`) — Bash 5.x + `jq` + POSIX awk; emits deterministic JSON (`LC_ALL=C` + path/name sort) consumed by `/kiln:kiln-roadmap`, `/kiln:kiln-claude-audit`, and `/kiln:kiln-distill`. Multi-theme distill helpers under `plugin-kiln/scripts/distill/` (`select-themes.sh`, `disambiguate-slug.sh`, `emit-run-plan.sh`). No new runtime dependency. (build/coach-driven-capture-ergonomics-20260424)
- Bash 5.x + `jq` + `awk` + `shasum -a 256` (macOS) / `sha256sum` (Linux) — distill gate helpers (`plugin-kiln/scripts/distill/detect-un-promoted.sh`, `invoke-promote-handoff.sh`) classify raw `.kiln/issues/` and `.kiln/feedback/` candidates via frontmatter reciprocal-link checks; `plugin-kiln/scripts/roadmap/promote-source.sh` writes a new roadmap item with `promoted_from:` back-reference and flips the source to `status: promoted` with SHA-256-validated body byte-preservation (NFR-003). `require-feature-branch-build-prefix` fixture invokes the hook in a disposable `mktemp -d` git repo (no new runtime deps). (build/workflow-governance-20260424)

## Looking up recent changes

This file does not carry a changelog tail — git and `.kiln/roadmap/` are the source of truth. For what landed, run `git log --oneline --since="30 days ago"` (feature branches follow `build/<slug>-<YYYYMMDD>`). For active work, read `.kiln/roadmap/phases/08-in-flight.md`. For shipped / specced PRDs, `ls docs/features/`. For the recommended next step, `/kiln:kiln-next`.
