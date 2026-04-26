# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

This repo is a **mostly-autonomous build system for a solo builder** built as five Claude Code plugins — `kiln` (spec-first pipeline), `clay` (idea → repo), `shelf` (Obsidian mirror), `trim` (design↔code sync), `wheel` (workflow engine). The thesis: **the loop is the product** — captured ideas, feedback, AI mistakes, and roadmap items become PRDs via `/kiln:kiln-distill`, become code via `/kiln:kiln-build-prd`, become precedent for the next loop. The unfair shortcut is **context-informed autonomy** — the system deliberates over accumulated precedent (prior feedback, approved manifest proposals, captured mistakes) to decide when to act vs when to escalate.

Two load-bearing invariants:
- **Propose-don't-apply** — kiln never auto-merges its own self-improvements; every change routes through a human apply step. Hooks block untraced `src/` edits and `.env` commits.
- **Senior-engineer-merge bar** — simple code, FR-traced tests, sparse load-bearing comments, useful PR descriptions, retros with actual insight. Hooks are the floor; this bar is the target.

**This is the plugin source repo, not a consumer project.** The `src/` and `tests/` directories don't exist here — they're scaffolded in consumer projects by `plugin-kiln/bin/init.mjs`.

## Quick Start

This is a capture → distill → ship → improve loop:

1. **Capture** — `/kiln:kiln-report-issue` (bugs/friction), `/kiln:kiln-feedback` (strategic notes), `/kiln:kiln-roadmap` (typed product-direction items: feature / goal / research / constraint / non-goal / milestone / critique), `/kiln:kiln-mistake` (AI failures).
2. **Distill** — `/kiln:kiln-distill` bundles open captures into a feature PRD under `docs/features/<date>-<slug>/PRD.md`.
3. **Ship** — `/kiln:kiln-build-prd <slug>` runs specify → plan → tasks → implement → audit → PR end-to-end via an agent team. Hooks block any `src/` edit until spec + plan + tasks + ≥1 `[X]` task exist.
4. **Improve** — retros emit `insight_score`-rated PI proposals; `/kiln:kiln-pi-apply` surfaces actionable diffs from accumulated retros; manifest-improvement proposals route through shelf for human apply; AI mistakes captured via `/kiln:kiln-mistake` feed shelf's manifest-improvement proposals.

New session? Run `/kiln:kiln-next` to auto-detect where you left off and get prioritized next steps.

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

This repo houses **five plugins** that cooperate via the wheel runtime + shelf MCP mirror:

| Plugin | Role | Entry skill |
|--------|------|-------------|
| `kiln` | Spec-first pipeline (specify → plan → tasks → implement → audit) + capture surfaces (issues / feedback / roadmap / mistakes / fixes) + audit / hygiene / PI tooling | `/kiln:kiln-build-prd`, `/kiln:kiln-next` |
| `clay` | Idea-to-repo flow (research → naming → PRD → repo scaffold) | `/clay:clay-idea` |
| `shelf` | Obsidian mirror (issues / PRDs / progress sync via MCP); manifest-improvement proposals | `/shelf:shelf-sync` |
| `trim` | Penpot ↔ code design sync | `/trim:trim-pull` |
| `wheel` | Workflow engine (hooks, state machines, agent resolver, per-step model selection) | `/wheel:wheel-run` |

Wheel is **plugin-agnostic infrastructure** (vision constraint): it must NOT hold any registry, manifest, or hardcoded path that requires knowledge of another plugin's contents. New agents, skills, hooks, or workflows ship inside their owning plugin without requiring a wheel release. Plugin-prefixed names (`<plugin>:<role>`) plus filesystem-backed harness discovery are the canonical way agents are found — bare names that depend on a central registry are a coupling violation.

Inside `plugin-kiln/`:

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

**`WORKFLOW_PLUGIN_DIR` availability in foreground AND background sub-agents** (FR-D1/D2/D3, specs/wheel-as-runtime): wheel exports `WORKFLOW_PLUGIN_DIR` directly into the shell env for `"type": "command"` steps. For `"type": "agent"` steps — including sub-agents spawned with `run_in_background: true` — wheel cannot export env vars into the harness-spawned process (the hook process dies before the harness spawns the sub-agent), so it instead **templates the absolute `WORKFLOW_PLUGIN_DIR` value into the agent step's instruction text** via `plugin-wheel/lib/context.sh`'s `context_build`. Agent-step authors must read the "Runtime Environment" block wheel prepends and propagate the value into their Bash tool calls / nested sub-agent prompts explicitly (e.g. `export WORKFLOW_PLUGIN_DIR='<abs-path-from-instruction>'` at the top of a Bash call, or a verbatim line at the top of a spawned sub-agent prompt). This is the shipped Option B per specs/wheel-as-runtime/research.md R-001 after Option A (pure env inheritance) was found infeasible for harness-spawned sub-agents. The consumer-install smoke test at `plugin-wheel/tests/workflow-plugin-dir-bg/run.sh` — wired to `/wheel:wheel-test` + CI per NFR-4 — guards this invariant.

The symptom when this is violated: a consumer runs the plugin workflow, command steps fail silently with `No such file or directory`, and downstream agent/apply steps continue with empty input — producing plausible-looking but wrong output. The regression fingerprint string `WORKFLOW_PLUGIN_DIR was unset` appearing in `.kiln/logs/report-issue-bg-*.md` is the SC-007 canary — `git grep -F` returning zero matches is the live assertion.

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

Run `/kiln:kiln-next` at session start — it surfaces the right command for current state. The full skill catalog is delivered to Claude via runtime context; for a human-readable list, see each plugin's README.

### Plugin behavior conventions

These are non-obvious behaviors that aren't derivable from the skill list itself.

#### `.shelf-config` keys (shelf plugin)

Two counter-gating keys control how often `/kiln:kiln-report-issue`'s background sub-agent runs a full reconciliation. Defaults appended to `.shelf-config` on first read via `plugin-shelf/scripts/shelf-counter.sh ensure-defaults`.

| Key | Default | Effect |
|-----|---------|--------|
| `shelf_full_sync_counter` | `0` | Current counter. Incremented by 1 on every `/kiln:kiln-report-issue` invocation (by the background sub-agent, under `flock` where available). Reset to `0` when it reaches the threshold. |
| `shelf_full_sync_threshold` | `10` | Full-sync cadence. When the counter hits this value, the bg sub-agent runs `/shelf:shelf-sync` + `/shelf:shelf-propose-manifest-improvement` to completion. |

A transient sibling lockfile at `.shelf-config.lock` (gitignored) serializes the counter RMW. On systems without `flock` (macOS default), the helper runs unlocked and accepts ±1 drift per FR-006 of `specs/report-issue-speedup/spec.md`.

Per-day background logs are written to `.kiln/logs/report-issue-bg-<YYYY-MM-DD>.md` with pipe-delimited lines: `<ISO-8601> | counter_before=N | counter_after=N | threshold=N | action=increment|full-sync|error | notes=<string>`.

#### `shelf-sync` no longer nests reflection

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

## Architectural Rules — Agent Spawning + Prompt Composition

These six rules are load-bearing for every team-mode agent spawn in this codebase. Reviewers MUST flag any production code path that violates them.

1. **NEVER use `general-purpose` for specialized roles in production.** `subagent_type` must always be plugin-prefixed (`<plugin>:<role>`, e.g. `kiln:research-runner`) so the harness routes to the correct registered agent definition with its `tools:` allowlist. `general-purpose` is for one-off ad-hoc tasks only — using it for a specialized role discards the role's tool scoping and identity.
2. **One role per registered subagent_type, multiple spawns per run with different injected variables.** Do NOT create variant agent.md files (`research-runner-baseline.md`, `research-runner-candidate.md`); spawn the SAME `kiln:research-runner` multiple times with different injected `Variables` blocks via the runtime composer.
3. **Injection is prompt-layer, NOT system-prompt-layer.** Per-spawn variables (verb bindings, role-instance variables) MUST live in the `prompt` parameter of the `Agent` call, never in the agent.md file. The agent.md is a stable, cache-friendly system prompt; per-call context goes in the prompt prefix the composer emits.
4. **Top-level orchestration is correct, not nested.** Skills spawn agents at the top level via the team-lead. Agents do NOT spawn other agents (no `Agent` tool in their allowlists). Nested spawns blow context budgets and break the team-mode coordination model.
5. **Agent registration is session-bound.** A new agent.md file shipped in this PR will NOT be spawnable in the session that ships it — the harness scans the filesystem at session start. Live-spawn validation of newly-shipped agents is queued for the next session; in-session validation is structural-only (file shape, allowlist conformance).
6. **Plain-text output is invisible to team-lead — always relay via SendMessage.** A teammate's plain prose is never seen by the lead. The ONLY visible output channel is `SendMessage({to: "team-lead", message: ...})`. Every team-mode agent's coordination protocol enforces this.

### Theme B directive syntax (compile-time agent-prompt includes — FR-B-8)

Authors deduplicate shared boilerplate (e.g., the SendMessage relay coordination prose) across agent.md files via a directive on its own line:

```markdown
<!-- @include _shared/coordination-protocol.md -->
```

The directive is HTML-comment-shaped (markdown-rendering-safe). Path is relative to the agent file's directory; shared modules live under `plugin-kiln/agents/_shared/`. Resolution is hybrid: source files under `plugin-kiln/agents/_src/` (when a role uses includes) compile to committed `plugin-kiln/agents/<role>.md` outputs via `plugin-kiln/scripts/agent-includes/build-all.sh`; CI gate `check-compiled.sh` re-runs the build and asserts compiled == build(sources). Recursion is forbidden in v1; directives inside fenced code blocks are NEVER expanded.

### Composer integration recipe (R-3 mitigation)

A skill that spawns a team-mode agent SHOULD use the runtime composer like this:

```bash
# 1. Resolve agent identity (existing resolve.sh).
SPEC_JSON=$(bash "$WORKFLOW_PLUGIN_DIR/scripts/agents/resolve.sh" kiln:research-runner)
SUBAGENT_TYPE=$(jq -r .subagent_type <<<"$SPEC_JSON")

# 2. Compose runtime context block.
PREFIX=$(bash "$WORKFLOW_PLUGIN_DIR/scripts/agents/compose-context.sh" \
  --agent-name research-runner \
  --plugin-id kiln \
  --task-spec /tmp/task-spec.json \
  --prd-path docs/features/<prd>.md | jq -r .prompt_prefix)

# 3. Spawn — the calling skill prepends PREFIX to the actual task prompt.
# Agent({
#   subagent_type: SUBAGENT_TYPE,            # "kiln:research-runner" — plugin-prefixed (Rule 1)
#   prompt: PREFIX + "\n---\n" + actual_task,
#   team_name: "<team>",
#   name: "baseline-runner"                  # role-instance label distinguishes parallel spawns (Rule 2)
# })
```

The composer NEVER calls `Agent` itself — the calling skill is responsible for the spawn. The composer is a pure function: inputs → JSON. Determinism is guaranteed (NFR-6): identical inputs produce byte-identical output, so cache-friendly re-invocation in test fixtures works.

## Looking up recent changes

Recent changes are tracked authoritatively in three places:
- `git log` — commit-level granularity
- `.kiln/roadmap/phases/<active-phase>.md` — current phase's `## Items` list
- `ls docs/features/` — date-prefixed PRD directories (most recent first)

Run `/kiln:kiln-next` for a synthesis of recent activity + suggested next steps.
