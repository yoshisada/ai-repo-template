# Kiln Autonomous Re-architecture — Master Plan

> Source of truth: `docs/features/2026-06-22-kiln-autonomous-rearchitecture/ARCHITECTURE.html`  
> Branch: `build/wheel-viewer-definition-quality-20260509`  
> Date: 2026-06-23

---

## Executive Summary

The kiln build system ships today as a skill-invoked, human-paced pipeline. This plan upgrades it to a **context-informed autonomous loop**: every build reads its own accumulated precedent, follows per-project coding standards, and decides how much to self-advance based on declared review preferences. The loop closes because mistakes flow into Obsidian, Obsidian is searchable before the next build, and self-improvement proposals land as either auto-applied L1 patches or human-reviewed chips.

**Six build phases, fully ordered by dependency:**

| Phase | Theme | Gate to next |
|---|---|---|
| 0 | Config foundation | Standards + config files scaffold cleanly |
| 1 | Ledger + precedent | `search_vault` MCP tool live; ledger written |
| 2 | Build pipeline as workflow | `kiln-build-prd.json` wheel workflow passes smoke test |
| 3 | Self-improvement loop | `kiln-self-improve.json` closes write→classify→apply |
| 4 | Hooks + gates | Coverage + traceability hooks green in CI |
| 5 | Observability + vision layer | Cockpit streams; vision-verify gates UI projects |

---

## Design Philosophy — Agent-First, Rightsized Model

**Core principle:** Every step in a wheel workflow that involves any reasoning, judgment, or synthesis MUST be an agent step. Command steps are reserved for pure mechanical operations: file reads, git commands, JSON slicing, process management. When in doubt, make it an agent.

The corollary: the model tier must match the task. Running sonnet on a classification task that haiku can do wastes latency and cost. Running haiku on a complex design task produces shallow output.

### Journal as Orchestrator State Source of Truth

The run journal (`.kiln/runs/<id>/journal.md`) is the canonical state for the orchestrator session — not conversation history. After each step completes, a structured line is appended:

```
[step: specify] [verdict: pass] [output: specs/auth/spec.md] [cost: $0.03]
```

**Why this matters for session management:** Claude Code's auto-compact can summarize and compress conversation history at any time. This is safe because the orchestrator session is intentionally thin — it dispatches wheel steps and reads outputs from disk. All decision-relevant state (step verdicts, output paths, costs, errors) lives in the journal and `.wheel/outputs/`, not in session context. On `--resume`, the orchestrator reads the journal to reconstruct exactly where the run is, making compact irrelevant to correctness.

**Implication:** the orchestrator should never make a decision based on "what the previous agent said in the conversation." It reads `.wheel/outputs/<step>-verdict.json`. The conversation is a display surface, not a state store.

### Model Tier Table

| Tier | Model | When to use |
|---|---|---|
| **`validator`** | `haiku` | Validation, classification, format-checking, spec quality checklist, risk voting, traceability scanning, audit-synthesize, build-summary, coverage gate reasoning |
| **`researcher`** / **`implementer`** / **`auditor`** | `sonnet` | Research, design, implementation, contract generation, complex analysis, retro synthesis, precedent formatting, self-improvement, smoke review, PRD audit |
| **`oracle`** | `sonnet` (reserved) | Future judge panels — run sonnet N× with distinct lenses (correctness / security / feasibility), synthesize. Use when a single verdict is too high-stakes. |

Tier names map to config keys in `.kiln/config.json`'s `models` block — wheel resolves the tier name to an actual model ID before dispatching each step. Changing a tier's model affects all steps that declare it without touching workflow JSON.

### Agent-First Step Upgrade Table

Applied to `kiln-build-prd.json`:

| Step | Type | Model | Rationale |
|---|---|---|---|
| `read-config` | command | — | Pure file read, no reasoning |
| `read-prd` | command | — | Pure file read |
| `read-standards` | command | — | Pure file read |
| `init-run-manifest` | command | — | Pure file write |
| `query-precedent` | command (sub-wf call) | — | Sub-workflow dispatch; `on_failure: skip` — Obsidian MCP unavailability never blocks a build |
| `specify` | agent | sonnet | Complex synthesis of PRD → spec |
| `checkpoint-post-spec` | command | — | Pause if in `review_checkpoints[]` or upstream `severity: blocking` |
| `plan` | agent | sonnet | Complex design + contract generation |
| `tasks` | agent | sonnet | Task breakdown requires reasoning |
| `check-hooks-gate` | command | — | File existence check, no reasoning |
| `dispatch-implement` | command | — | Groups tasks by story; writes dispatch manifest |
| `implement` | **team** | sonnet (implementers) + haiku (spec-enforcer) | Wheel dispatches parallel agents per story; spec-enforcer + qa-engineer as singletons |
| `run-tests` | command | — | Shell execution |
| `smoke-review` | agent | sonnet | Requires vision + judgment |
| `checkpoint-post-implement` | command | — | Pause if in `review_checkpoints[]` or `implement-verdict` has blockers |
| `audit` | **team** | sonnet + haiku × 2 | Wheel dispatches parallel panel: prd-auditor + spec-enforcer + quality-judge |
| `audit-synthesize` | agent | haiku | Merges three panel verdicts into one `compliance_pct` + `severity` |
| `fix-blocking` | agent | sonnet | Inline fix for blocking findings; routes to debugger on failure |
| `checkpoint-pre-pr` | command | — | Pause if in `review_checkpoints[]` or `audit-verdict.severity == blocking` |
| `create-pr` | command | — | `gh pr create` shell call |
| `checkpoint-pre-merge` | command | — | Pause if in `review_checkpoints[]` — merges always get at least one human gate |
| `collect-retro` | agent | sonnet | Synthesis of friction → structured ledger entries |
| `classify-proposals` | agent | **haiku** | Classification is mechanical, not creative — haiku suffices |
| `apply-low-risk` | **agent** | **sonnet** | Requires reading + editing config files intelligently |
| `update-run-manifest` | command | — | Pure JSON write |
| `build-summary` | **agent** | **haiku** | Reads all verdicts + PR URL + git diff; emits structured markdown summary tables for the human |

Bold = changed from original design.

### Implement as a Parallel Team

The `implement` step is the most expensive in the pipeline. It MUST be a team, not a single agent:

```
team: implement
  ├── implementer-foundational  (sonnet) — Phase 2 tasks: shared infrastructure
  │     ↓ emits: SendMessage(to:"team-lead", "foundational done: T001-T009 ✓")
  ├── spec-enforcer             (haiku)  — watches all edits for spec/contract drift
  │     ↓ emits: SendMessage(to:"team-lead", findings[])
  ├── implementer-us1           (sonnet) — Phase 3 (P1 story tasks), starts after foundational
  ├── implementer-us2           (sonnet) — Phase 4 (P2 story tasks), parallel with us1
  └── qa-engineer               (sonnet) — checkpoint feedback after each phase completes
```

The team-lead coordinates phase sequencing: foundational must complete before us1/us2 spawn. QA engineer fires after each phase, not just at smoke. Spec-enforcer runs throughout.

**Worktree isolation:** each parallel implementer (`us1`, `us2`, ...) runs with `isolation: "worktree"` — a fresh git checkout of the current branch. Implementers work freely without file locking or upfront partitioning.

**Merge + conflict recovery:**
```
merge-worktrees (agent, researcher tier) — runs after all implementers complete
  → merges each worktree into main branch sequentially
  → on conflict:
      send conflict diff back to the implementer that owns those FRs
      → implementer resolves using its own context + the other side's diff
      → retry merge
  → if implementer fails after 2 attempts → route to kiln:debugger
  → emits: {merged: N, conflicts_resolved: N, blockers: []}
```

A merge conflict is not a bug — it means two implementers touched the same surface. The implementer that owns those FRs is the right resolver: it knows its intent, and the other side's diff is sufficient context. The debugger is last resort only.

### Audit as a Parallel Panel

The `audit` step MUST be a parallel panel, not a single agent:

```
team: audit
  ├── prd-auditor      (sonnet) — FR compliance, coverage %, drift check
  ├── spec-enforcer    (haiku)  — test traceability, FR comment presence in src/
  └── quality-judge    (haiku)  — naming rule compliance, function size, comment ratio
        ↓
  audit-synthesizer    (haiku)  — merges three verdicts into one compliance_pct + findings[]
```

Each panel member emits a structured verdict JSON. The synthesizer aggregates them. A feature passes audit when: compliance ≥ 80% AND no findings with `severity: blocking`.

### Checkpoint Pause Logic

Checkpoints are `type: "command"` steps — no AI reasoning. Pause decision has two triggers:

1. **Config-determined (roadmap):** the checkpoint name appears in `review_checkpoints[]` in `.kiln/config.json`. This is set during `kiln-init` and reflects the user's pre-declared review cadence for the project.
2. **Critical-event override:** an upstream step wrote `severity: blocking` in its verdict JSON. A blocking finding always pauses regardless of config — the human must see it.

If neither condition is met, the checkpoint skips automatically. No agent reasoning mid-run.

```bash
# checkpoint-pre-pr example:
CHECKPOINTS=$(jq -r '.review_checkpoints // [] | join(",")' .wheel/outputs/kiln-config.json)
BLOCKING=$(jq -r '.severity // "pass"' .wheel/outputs/audit-verdict.json)
if echo "$CHECKPOINTS" | grep -q 'pre-pr' || [ "$BLOCKING" = "blocking" ]; then
  echo '{"checkpoint":"pre-pr","action":"pause","reason":"in review_checkpoints or blocking finding"}'
else
  echo '{"checkpoint":"pre-pr","action":"skip"}'
fi
```

### Failure Recovery — Debugger Loop + Notification

When a workflow step fails, the system does NOT retry blindly. The recovery sequence is:

```
step fails
  → spawn kiln:debugger with failed step context + error output
  → debugger diagnoses, applies targeted fix, signals retry
  → step retried with updated context
  → if still failing after max_debug_attempts (default: 2):
      → debugger writes .kiln/runs/<id>/failure-report.md
      → workflow halts, manifest written with cursor at failed step
      → post hook fires (on: always) → notify.sh dispatches notification
      → kiln-next surfaces the failure with debugger's diagnosis on next session start
```

**Step schema — `on_failure`:**
```json
{
  "id": "implement",
  "type": "team",
  "on_failure": {
    "route": "kiln:debugger",
    "max_debug_attempts": 2
  }
}
```

Command steps with transient failure modes (network calls, `gh` CLI) additionally get `"retry": 2` before the debugger is invoked. Agent/team steps go straight to the debugger — retrying the same prompt with the same context will produce the same failure.

The `build-summary` and post hook steps always run (`"on": "always"`) regardless of pipeline status, so the human always gets a summary and always gets notified.

**Notification config (in `config.json`):**

| Event | Fires when |
|---|---|
| `failure` | Debugger exhausted, workflow halted |
| `complete` | Pipeline finished successfully |
| `checkpoint` | Human pause requested — "ping me when you need me" |

| Channel | Config key | Notes |
|---|---|---|
| macOS system alert | `macos: true` | `osascript` — zero config, on by default |
| Email | `email: "you@example.com"` | Requires mail relay or sendmail |
| Slack | `slack_webhook: "<url>"` | Standard Slack incoming webhook |
| Generic webhook | `webhook: "<url>"` | POST with JSON body — works for Discord, Teams, custom |

`plugin-kiln/scripts/notify.sh` reads `config.json` and dispatches to all configured channels. Called by the workflow's post hook — no new infrastructure required. Notification body is the debugger's `failure-report.md` content for failures, the `summary.md` tables for completions.

### External MCP Graceful Degradation

Any workflow step that depends on an external MCP (Obsidian, Notion, etc.) MUST have `on_failure: "skip"`. External MCPs can be unavailable at any time — Obsidian closed, plugin crashed, network issue — and a build should never block on them.

The skip pattern: the command falls back to writing an empty or stub output with a warning message, so downstream steps that `context_from` it receive something rather than nothing. The warning surfaces in the build summary's Findings section as `info` severity.

```json
{ "on_failure": "skip" }
```

Applied to: `query-precedent` (Obsidian MCP), any future shelf-sync steps embedded in workflows, any Notion/external service calls.

### `kiln-next` — Human Orientation Command

`kiln-next` is **human-only** — never auto-invoked by any pipeline or workflow. It runs at session start to tell the human what needs their attention and what to do next. It reads all project state and evaluates a fixed priority stack, short-circuiting at the first match:

| Priority | Condition | Output |
|---|---|---|
| **1 — Pending human review** | Workflow checkpoint pauses · open PRs awaiting review · L2 improvement proposals awaiting apply decision · debugger escalations that couldn't auto-fix | "These need you before anything can move" — listed first, always |
| **2 — Interrupted run** | `.kiln/runs/*/manifest.json` with `phase ≠ "done"` and not a checkpoint pause | Show which step halted + exact resume command: `/kiln:kiln-build-prd <slug> --resume` |
| **3 — Failing tests** | `npm test` exit ≠ 0 on current branch | Show failing tests + suggest `kiln-fix` |
| **4 — Issues: large batch** | `.kiln/issues/` count ≥ `issue_batch_threshold` | "N issues open — significant enough to spec → `/kiln:kiln-build-prd`" (issues treated as a feature/fix body of work) |
| **5 — Issues: small batch** | `.kiln/issues/` count > 0 and < `issue_batch_threshold` | "N issue(s) open → `/kiln:kiln-fix <id>`" per issue — targeted fix loop, no spec overhead |
| **6 — Captures ready to distill** | Feedback + roadmap items combined ≥ `distill_threshold` | "N feedback/roadmap items → `/kiln:kiln-distill`" — strategic captures bundle into feature PRD |
| **7 — PRD ready to build** | `docs/features/*/PRD.md` exists, no `specs/` dir yet | Suggest `kiln-build-prd <slug>` |
| **8 — All clear** | Nothing above matches | Project health snapshot: coverage %, last build date, open issue count, active roadmap phase |

Each level short-circuits — shows the highest-priority thing and stops. Output uses the structured summary table format. Always ends with one clear recommended action, not a list of everything.

**Two-track model:** issues are always fix-priority — the track is determined by count vs `issue_batch_threshold`. Small batch → `kiln-fix` per issue (targeted, no spec overhead). Large batch → `kiln-build-prd` (enough work to warrant full spec → plan → implement). Feedback + roadmap items are strategic, not urgent — they accumulate and `kiln-distill` bundles them into feature PRDs. These two tracks never mix: issues don't get distilled, feedback doesn't get fixed.

`kiln-distill` only processes feedback + roadmap items. Issues go to kiln-fix or kiln-build-prd.

### Structured Human Output

**Every pipeline run that changes code, creates artifacts, or makes decisions MUST emit a structured markdown summary as its final step.** This is the human handoff document — everything needed to review, verify, and close out the work without digging through logs.

**Required at end of:** `kiln-build-prd`, `kiln-fix`, `kiln-create-prd`, `kiln-distill`

**Implementation:** a `build-summary` agent step (model_tier: `validator`) is added as the final step of every qualifying workflow. It reads all verdict outputs accumulated during the run and generates the tables below. Output is written to `.kiln/runs/<run-id>/summary.md` AND printed to terminal (agent output is always visible to the human in the session). For non-workflow skills (`kiln-fix`, `kiln-create-prd`, `kiln-distill`): the skill file includes a "generate summary" section at the end with the same format, scoped to what's relevant.

**Canonical summary format:**

```markdown
## Build Summary: <feature-name>

### Overview
| Field | Value |
|---|---|
| Feature | [<feature>](docs/features/<slug>/PRD.md) |
| Branch | `feature/<slug>` |
| PR | [#<n> — <title>](<github-url>) |
| Run ID | `<id>` |
| Spec compliance | 95% |
| Test coverage | 87% |
| Smoke test | Passed |

### What Changed
| File | Change |
|---|---|
| src/components/Foo.tsx | New |
| src/api/bar.ts | Modified |
| src/utils/legacy.ts | Deleted |

### What to Test
| User Story | How to verify | Expected result |
|---|---|---|
| US-1: User can log in | Visit /login, submit valid credentials | Redirect to /dashboard |
| US-2: Invalid credentials show error | Submit wrong password on /login | Red error message, no redirect |

### Findings (if any)
| Severity | Finding |
|---|---|
| warning | FR-5 branch coverage 71% — below 80% gate |
| info | 2 low-risk improvement proposals queued in ledger |

### Links
| Resource | Path |
|---|---|
| PR | <github-url> |
| Spec | `specs/<slug>/spec.md` |
| Contracts | `specs/<slug>/contracts/interfaces.md` |
| Smoke report | `specs/<slug>/smoke-report.md` |
| Retro | `.kiln/runs/<id>/retro.md` |
| Agent notes | `.kiln/runs/<id>/agent-notes/<story-id>.md` |
| Journal | `.kiln/runs/<id>/journal.md` |
```

**Per-command scope:**

| Command | Overview | What Changed | What to Test | Findings | Links |
|---|---|---|---|---|---|
| `kiln-build-prd` | full | git diff --stat | user stories + test scenarios | audit + coverage | PR, spec, smoke, retro |
| `kiln-fix` | abbreviated | files touched | what broke + how to re-verify | none / ✓ green | PR or branch |
| `kiln-create-prd` | PRD metadata | PRD file created | open decisions / gaps | none | PRD path, roadmap item |
| `kiln-distill` | capture bundle | N captures → PRD | gaps the PRD should answer | none | PRD path |

### Cost + Token Tracking

Every workflow run records token usage and estimated cost to `.kiln/runs/<id>/manifest.json`, broken down by model. The `build-summary` step reads this and includes it in the overview table.

**Manifest schema addition:**
```json
"cost": {
  "total_usd": 2.40,
  "input_tokens": 84000,
  "output_tokens": 12000,
  "by_model": {
    "claude-haiku-4-5-20251001": { "input_tokens": 12000, "output_tokens": 3000, "usd": 0.25 },
    "claude-sonnet-4-6":         { "input_tokens": 72000, "output_tokens": 9000, "usd": 2.15 }
  }
}
```

**Build summary overview rows added:**
```
| Tokens | 84k in · 12k out |
| Cost   | ~$2.40  (haiku: $0.25 · sonnet: $2.15) |
```

Wheel records token counts from agent output metadata after each step. The `build-summary` agent aggregates and formats. No budget gate — visibility only. Applies to both `kiln-build-prd` and `kiln-fix` runs.

### `kiln-init` Onboarding Flow

**`kiln-init` is idempotent.** It checks whether `.kiln/config.json` already exists and reads its `config_version` field:
- **First run (no config exists):** runs the full 6-step wizard.
- **Subsequent runs (config exists):** compares `config_version` against the current package's `config-schema.json`, identifies keys introduced since the project's version, and asks only about those. If nothing is new, confirms "config is up to date" and exits.

No separate `update` subcommand — `kiln-init` is the single entry point for both cases.

**Version detection schema** (`plugin-kiln/scaffold/config-schema.json`):
```json
{
  "1.0.0": ["review_mode", "review_checkpoints", "notifications", "models", "standards", "auto_build", "branching"],
  "1.1.0": ["pi_apply_threshold"]
}
```
`.kiln/config.json` carries a `"config_version": "1.0.0"` field. On re-run, `kiln-init` finds all keys in versions > `config_version`, asks only about those, then bumps `config_version` on save.

**Interview sequence (full wizard — first run):**

| Step | Question | Config written |
|---|---|---|
| 1 | "How often should kiln pause for your review?" → thorough / **standard** / express / autonomous | `config.json` → `review_mode`, `review_checkpoints` |
| 2 | "How should kiln notify you on finish or failure?" → **macOS alert** / Slack / email / webhook / none | `config.json` → `notifications.channels` |
| 3 | "Do you follow a coding style guide?" → Clean Code / Google / Airbnb / custom / **none (skip)** | `.kiln/standards.md` bootstrapped from template |
| 3b | Vision interview (skipped if `.kiln/vision.md` already exists): "What is this project?" / "What is it NOT?" / "What does winning look like?" / "What are the hard constraints?" → **skip (defer)** / answer now | `.kiln/vision.md` written from `vision-template.md` |
| 4 | "What command runs your tests? What's your coverage target?" → **npm test** / vitest run / jest / custom + **80%** default | `.kiln/test-strategy.json` |
| 5 | "Priority: quality or cost?" → quality (oracle → opus) / **balanced** (all sonnet) / cost-optimized (implementer → haiku) | `config.json` → `models` block |
| 5b | "Do you design in Penpot before building features?" → **no** / yes (design-first mode) | `config.json` → `design_first` |
| 5c | "What branching style?" → **github-flow** (feature → main) / gitflow (feature → integration → main) / trunk (commit direct to main) | `config.json` → `branching.style`; if gitflow, follow-up: "Integration branch name?" → **dev** |
| 6 | **Summary** — shows all chosen settings as a table, prompts for confirmation before writing files | All config files written atomically |

**Gate:** no config files are written until the user confirms the step-6 summary table. Each step has an explicit "accept default" path — the full wizard completes in under 30 seconds for users who want no customization.

### Distill → Build: Closing the Loop

`kiln-distill` (captures → PRD) and `kiln-build-prd` (PRD → code) are the two halves of the loop. By default they are separate commands — the user decides when to build. When `auto_build: true` is set in `config.json`, `kiln-distill` automatically enqueues `kiln-build-prd` after the PRD is written, completing the loop without a manual hand-off step.

**Config key (in `config.json`):**
```json
"auto_build": false
```

**`kiln-distill` end-of-flow behavior:**
```
if auto_build == true:
  → emit: "PRD created. Starting build pipeline for <slug>..."
  → invoke: kiln-build-prd <slug>  (same session, sequential)
else:
  → emit: "PRD ready. Run /kiln:kiln-build-prd <slug> to build."
```

`auto_build` is surfaced as a yes/no question in the `kiln-init` onboarding wizard. Default is `false` — users start manual and opt in when they trust the loop.

### Two-Tier Data Sync

**All kiln capture surfaces write locally first. Obsidian is an optional cross-project sync layer — never a hard dependency.**

| Capture surface | Local write | Obsidian sync |
|---|---|---|
| `kiln-report-issue` | `.kiln/issues/<id>.md` | shelf-sync on counter rollover |
| `kiln-feedback` | `.kiln/feedback/<id>.md` | shelf-sync call, `on_failure: "skip"` |
| `kiln-roadmap` | `.kiln/roadmap/items/<id>.md` | shelf-sync call, `on_failure: "skip"` |
| `kiln-mistake` | `.kiln/mistakes/<id>.md` | shelf-sync call, `on_failure: "skip"` |
| Ledger entries (build/self-improve) | `.kiln/ledger/<id>.json` | `sync-to-obsidian` step, `on_failure: "skip"` |

When Obsidian is unavailable, all captures land safely in local files. The next time `shelf-sync` runs (manually or on counter rollover) it picks up any unsynced entries — eventual consistency without blocking any build.

**Why this matters for cross-project learning:** `precedent-reader` queries Obsidian. A mistake captured in project A is invisible to project B's build until it syncs. The catch-up path (`shelf-sync` as a reconcile pass) ensures nothing is permanently lost — just delayed.

---

## Current Inventory

### Skills (existing, 67 total)

**kiln (42):** audit, implement, kiln-analyze, kiln-analyze-issues, kiln-build-prd, kiln-checklist, kiln-clarify, kiln-claude-audit, kiln-cleanup, kiln-constitution, kiln-coverage, kiln-create-prd, kiln-distill, kiln-doctor, kiln-escalation-audit, kiln-feedback, kiln-fix, kiln-hygiene, kiln-init, kiln-merge-pr, kiln-mistake, kiln-next, kiln-pi-apply, kiln-qa-audit, kiln-qa-checkpoint, kiln-qa-final, kiln-qa-pass, kiln-qa-pipeline, kiln-qa-setup, kiln-report-issue, kiln-research, kiln-reset-prd, kiln-resume, kiln-roadmap, kiln-taskstoissues, kiln-test, kiln-todo, kiln-ux-evaluate, kiln-version, plan, specify, tasks

**clay (6):** clay-create-repo, clay-idea, clay-idea-research, clay-list, clay-new-product, clay-project-naming

**shelf (8):** shelf-create, shelf-feedback, shelf-propose-manifest-improvement, shelf-release, shelf-repair, shelf-status, shelf-sync, shelf-update

**trim (10):** trim-design, trim-diff, trim-edit, trim-flows, trim-init, trim-library, trim-pull, trim-push, trim-redesign, trim-verify

**wheel (9):** wheel-create, wheel-init, wheel-list, wheel-run, wheel-skip, wheel-status, wheel-stop, wheel-test, wheel-view

### Agents (existing, 13 in plugin-kiln)

continuance, debugger, fixture-synthesizer, output-quality-judge, prd-auditor, qa-engineer, qa-reporter, research-runner, smoke-tester, spec-enforcer, test-runner, test-watcher, ux-evaluator

### Workflows (existing, 18 production)

clay: sync.json  
kiln: kiln-mistake.json, kiln-report-issue.json  
shelf: shelf-create.json, shelf-propose-manifest-improvement.json, shelf-repair.json, shelf-sync.json, shelf-write-issue-note.json, shelf-write-roadmap-note.json  
trim: library-sync.json, trim-design.json, trim-diff.json, trim-edit.json, trim-pull.json, trim-push.json, trim-redesign.json, trim-verify.json  
wheel: example.json, noni.json

---

## Phase 0 — Config Foundation

**Goal:** Every new and existing project can declare its coding standards and review preferences. `kiln-init` and `clay-create-repo` scaffold both files.

### New Config Files

#### `.kiln/standards.md` (scaffold template)
```markdown
## Coding Standards

### Naming
- names are pronounceable and searchable — no abbreviations, no encodings
- one word per concept (fetch not retrieve/get/pull mixed across the codebase)
- functions named as verbs, booleans as predicates (isActive, hasPermission)
- classes/modules named as nouns describing what they ARE, not what they DO

### Functions
- do one thing at one level of abstraction
- <= 20 lines, <= 2 parameters — extract an object or split if more are needed
- no flag arguments — split into two named functions instead
- no side effects — a function that says it reads should only read

### Comments
- do not comment WHAT the code does — rename or restructure instead
- only write a comment to explain WHY: a hidden constraint, a non-obvious invariant,
  a workaround for a specific bug

### Error handling
- throw exceptions, never return null or error codes from internal functions
- never pass null — guard at system boundaries, trust contracts internally
- fail loudly at boundaries (user input, external APIs), fail silently nowhere

### Structure
- single responsibility — one reason to change per module
- small and cohesive — if you're listing unrelated methods, split it
- tell don't ask — don't reach into an object's state to make decisions for it
- no circular dependencies across layers

### Tests
- one concept per test, assertion names describe the failure
- every test references its spec FR in a comment
- no stubs on integration paths
```

#### `.kiln/config.json` (scaffold template)
```json
{
  "review_mode": "standard",
  "review_checkpoints": ["post-spec", "pre-pr"],
  "auto_build": false,
  "design_first": false,
  "branching": {
    "style": "github-flow",
    "integration_branch": "dev",
    "per_feature": true
  },
  "auto_pr":    false,
  "auto_merge": false,
  "pi_apply_threshold": "none",
  "standards": ".kiln/standards.md",
  "models": {
    "validator":   "claude-haiku-4-5-20251001",
    "researcher":  "claude-sonnet-4-6",
    "implementer": "claude-sonnet-4-6",
    "auditor":     "claude-sonnet-4-6",
    "oracle":      "claude-sonnet-4-6"
  },
  "notifications": {
    "on": ["failure", "complete", "checkpoint"],
    "channels": {
      "email": null,
      "slack_webhook": null,
      "webhook": null,
      "macos": true
    }
  }
}
```

`review_mode` presets:

| Mode | Checkpoints |
|---|---|
| `thorough` | post-spec · post-plan · post-implement · pre-pr · pre-merge |
| `standard` | post-spec · pre-pr |
| `express` | pre-merge only |
| `autonomous` | none |

`branching.style` options:

| Style | Flow | When to use |
|---|---|---|
| `github-flow` | feature branch → PR → `main` | Solo or small team; simple, main always deployable |
| `gitflow` | feature branch → PR → `integration_branch` → PR → `main` | Long-lived sessions; keep `main` clean until milestone-ready; `integration_branch` defaults to `dev` |
| `trunk` | commit directly to `main` | Experienced team with strong CI; no branches, fastest loop |

**How kiln uses `branching`:**
- `require-feature-branch.sh` reads `branching.per_feature` — if `false`, skips the feature-branch gate
- `create-pr` step in `kiln-build-prd.json` reads `branching.style` to determine PR target: `main` for `github-flow`/`trunk`, `integration_branch` value for `gitflow`
- `kiln-init` creates the integration branch if it doesn't exist when `style: gitflow`

#### Model Tier Configuration

Workflow agent steps reference a `model_tier` name instead of a hardcoded model ID. Wheel resolves the tier against `config.json`'s `models` block before dispatching each step. This lets you change every validator-class agent from haiku to sonnet (or swap in a MiniMax or Gemini model via Bifrost) by editing one line in config — no workflow JSON edits needed.

| Tier | Default model | Used for |
|---|---|---|
| `validator` | haiku | Spec gate checks, classification, audit-synthesize, build-summary, task counting |
| `researcher` | sonnet | Precedent queries, Phase 0 codebase research, plan research sub-phase |
| `implementer` | sonnet | Code generation, specifier, planner, task implementers |
| `auditor` | sonnet | PRD audit, spec-enforcer, quality-judge, smoke-review |
| `oracle` | sonnet | Audit synthesizer, retro analysis, highest-stakes synthesis (upgrade to opus when budget allows) |

**Resolution priority** (wheel evaluates in order):
1. Step-level `"model"` field — explicit per-step override (escape hatch, use sparingly)
2. Step-level `"model_tier"` → looked up in `config.json`'s `models` block
3. Default: `claude-sonnet-4-6`

**Example step with tier:**
```json
{
  "id": "spec-gate",
  "type": "agent",
  "model_tier": "validator",
  "instruction": "Check spec gates: does spec.md exist, does it have ≥3 FRs..."
}
```

**Power-user patterns:**
```json
// Run entire pipeline on haiku for a cheap smoke-test pass
"models": { "validator": "claude-haiku-4-5-20251001", "researcher": "claude-haiku-4-5-20251001", "implementer": "claude-haiku-4-5-20251001", "auditor": "claude-haiku-4-5-20251001", "oracle": "claude-haiku-4-5-20251001" }

// Upgrade oracle to opus for maximum synthesis quality
"models": { ..., "oracle": "claude-opus-4-8" }

// Use MiniMax for implementer tier via Bifrost gateway
"models": { ..., "implementer": "minimax/MiniMax-Text-01" }
```

### Modified Skills

**`kiln-init`** — add scaffolding of `.kiln/standards.md`, `.kiln/config.json`, `.kiln/test-strategy.json` on first init.

**`clay-create-repo`** — after scaffolding the repo and running the initial git commit, runs a short vision interview to write `.kiln/vision.md` (what this project is, what it is NOT, winning condition, constraints). This is clay's primary contribution to the kiln loop — vision is best captured at creation time when the idea is freshest. After vision is written, asks: "Would you like to set up kiln now? (recommended)". If yes → delegates to `kiln-init` directly (which skips the vision step since it already exists). If no → prints: "Run /kiln:kiln-init any time to set up kiln." No other wizard logic lives in clay — it is a hand-off, not a duplication.

**`kiln-init` vision step** — wizard step 3b: checks if `.kiln/vision.md` already exists. If yes → skips with "Vision already defined — edit with `/kiln:kiln-roadmap --vision`." If no → runs the same short vision interview (what / what NOT / winning / constraints), writes from `vision-template.md`. Skippable — user can press enter to defer and define vision later.

**`kiln-next`** — read `.kiln/config.json` on session entry; surface `review_mode` and pending checkpoint state in session summary.

**`kiln-doctor`** — upgraded to read `plugin-kiln/scaffold/doctor-manifest.json` for the current package version. Merges all entries from `1.0.0` through the current version, runs each check, and emits a structured diagnostic table. New system components added in future versions ship as new entries in `doctor-manifest.json` — no code changes to `kiln-doctor` needed.

**`plugin-kiln/scaffold/doctor-manifest.json`** (new scaffold file — not copied to consumer projects, read from plugin install path):
```json
{
  "1.0.0": {
    "required": [
      { "path": ".kiln/config.json",        "check": "valid-json",   "fix": "/kiln:kiln-init" },
      { "path": ".kiln/test-strategy.json", "check": "valid-json",   "fix": "/kiln:kiln-init" },
      { "path": ".kiln/standards.md",       "check": "exists",       "fix": "/kiln:kiln-init", "if_config_key": "standards" }
    ],
    "optional": [
      { "check": "obsidian-reachable", "severity": "warning", "fix": "Open Obsidian + enable MCP plugin" },
      { "check": "stale-worktrees",    "severity": "warning", "fix": "kiln-doctor --clean-worktrees" }
    ],
    "version_checks": [
      { "path": ".kiln/config.json", "field": "config_version", "fix": "/kiln:kiln-init" }
    ]
  },
  "1.1.0": {
    "required": [
      { "path": ".kiln/ledger/", "check": "dir-exists", "fix": "created automatically on next build" }
    ]
  }
}
```

Checks run in order: required → version → optional. Required failures are errors (doctor exits non-zero). Optional failures are warnings (doctor exits 0). All results render as a table: `| Check | Status | Fix |`.

### compose-context.sh changes

Add a `--standards` flag that reads `.kiln/standards.md` and prepends it as a `## Coding Standards` block in the agent prompt prefix. Called with this flag for `plan` and `implement` spawns in `kiln-build-prd`.

---

## Phase 1 — Ledger + Precedent System

**Goal:** Past mistakes from all projects are queryable before any new build. The ledger consolidates mistakes, fixes, and retros into a single searchable store.

### New Config Files / Runtime Artifacts

#### `.kiln/ledger/<id>.json` schema
```json
{
  "id": "YYYY-MM-DD-<slug>",
  "kind": "mistake | fix | retro | friction",
  "summary": "one-line description",
  "detail": "full prose",
  "blast_radius": "local | cross-plugin | cross-project",
  "tags": ["mistake/assumption", "topic/hooks", "language/typescript"],
  "source_path": ".kiln/mistakes/YYYY-MM-DD-<slug>.md",
  "ts": "ISO-8601"
}
```

#### `.kiln/ledger/proposals/<id>.json` schema
```json
{
  "id": "YYYY-MM-DD-<slug>",
  "target": "plugin-kiln/skills/plan/SKILL.md",
  "patch": "unified diff or instruction string",
  "risk": "low | high",
  "blast_radius": "local | cross-plugin",
  "rationale": "why this change",
  "ledger_refs": ["YYYY-MM-DD-<slug>"]
}
```

#### `.kiln/runs/<id>/manifest.json` schema
```json
{
  "run_id": "uuid",
  "prd": "docs/features/<slug>/PRD.md",
  "phase": "specify | plan | tasks | implement | audit | pr | done",
  "branch": "build/<slug>-YYYYMMDD",
  "pr": null,
  "decisions": [],
  "escalations": [],
  "cursor": "last-completed-step-id"
}
```

### New Agents

#### `precedent-reader.md`
**Role:** Before each build run, search Obsidian for past mistakes relevant to the current PRD's topic and stack tags. Injects them as a `## Precedent` warning block so specifiers and implementers see real failure history before writing a line.

**Model tier:** `validator` (haiku — fast lookup, no reasoning required)  
**Tools:** `Bash` (Obsidian MCP calls), `Write`  
**`on_failure: "skip"`** — if Obsidian is unavailable, writes an empty precedent block and continues

```markdown
---
name: precedent-reader
role: validator
model_tier: validator
on_failure: skip
tools: [Bash, Write]
---

You are the precedent reader. Your job is to surface past mistakes before the build starts.

## Inputs
- .wheel/outputs/prd-context.json — {topics: [], stack: []} extracted from PRD frontmatter

## Steps
1. Build an Obsidian tag query from topics + stack.
   Example: topics=["hooks","wheel"], stack=["language/typescript"]
   → query: "(tag:topic/hooks OR tag:topic/wheel) AND tag:language/typescript path:mistakes/"
2. Call mcp__obsidian-projects__search_vault with that query, limit=10.
3. If no results, retry with only the first topic tag (broader search).
4. For each result extract: title, assumption, correction, severity, project (frontmatter).
5. Format as:

## Precedent — past mistakes relevant to this feature

> Real mistakes from prior builds. Read before specifying or implementing.

- **[severity]** `[mistake_class]` — [assumption]
  ✓ Correction: [correction]
  _(source: [project], [date])_

6. If Obsidian unavailable or no results: write "## Precedent\n\n_No relevant past mistakes found._"
7. Write to .wheel/outputs/precedent-block.md
8. Emit JSON: {"count": N, "queries_used": [...], "path": ".wheel/outputs/precedent-block.md"}
```

#### `risk-classifier.md`
**Role:** Classifies improvement proposals from retros and friction logs as `low` or `high` risk so the self-improvement loop knows which to auto-apply vs surface to the human.

**Model tier:** `researcher` (sonnet — needs judgment about blast radius)  
**Tools:** `Read`, `Write`

```markdown
---
name: risk-classifier
role: researcher
model_tier: researcher
tools: [Read, Write]
---

You are the risk classifier. Assess each improvement proposal and assign a risk level.

## Inputs
- .wheel/outputs/friction-consolidated.json — {proposals: [{id, target, instruction, tags}]}
- .kiln/ledger/proposals/<id>.json — existing proposals for context

## Classification rules
LOW risk (safe to auto-apply):
- Target is a single .kiln/*.json or .kiln/*.md config file
- Target is a SKILL.md with local blast_radius only
- No hook, gate, workflow, or cross-plugin contract is modified
- Change is a prompt clarification, default value adjustment, or wording improvement

HIGH risk (surface to human):
- Target is any hook/*.sh or hooks.json
- Target involves a gate or enforcement rule
- Change affects cross-plugin contracts or shared interfaces
- blast_radius is "cross-plugin" or "cross-project"
- Uncertain — when in doubt, classify HIGH

## Output
For each proposal, update .kiln/ledger/proposals/<id>.json with {"risk": "low"|"high"}.
Emit JSON: {"low": [{id, target, instruction}], "high": [{id, target, instruction}]}
```

### New MCP Tool (Obsidian MCP)

**`search_vault(query: string, limit?: number)`**

Exposes Obsidian's native search syntax. Returns `[{ path, title, frontmatter, excerpt }]`.

Example queries from `precedent-reader`:
- `tag:mistake/assumption AND tag:topic/hooks path:mistakes/`
- `tag:language/typescript AND tag:topic/wheel path:mistakes/`

**Future upgrade:** `semantic_search(text: string, k: number)` backed by Turso sqlite-vec — add when mistakes corpus exceeds ~50 entries and tag search returns noisy results.

### New Skills

**`kiln-ledger`** — CLI surface for the precedent ledger. Lists all ledger entries, filters by tag/kind/date. No writes — read-only history view.

```
/kiln:kiln-ledger [--kind mistake|fix|retro] [--tag topic/hooks] [--last 10]
```

### New Wheel Workflow

#### `plugin-kiln/workflows/kiln-precedent.json`
```json
{
  "name": "kiln-precedent",
  "version": "1.0.0",
  "description": "Query Obsidian for relevant past mistakes and emit a Precedent block for injection into build prompts",
  "steps": [
    {
      "id": "read-prd-context",
      "type": "command",
      "command": "PRD_CONTENT='.wheel/outputs/prd-content.md'; if [ ! -f \"$PRD_CONTENT\" ]; then echo '{\"topics\":[],\"stack\":[]}'; exit 0; fi; TOPICS=$(grep -oE 'topic/[a-z_-]+' \"$PRD_CONTENT\" | sort -u | jq -R . | jq -s .); STACK=$(grep -oE '(language|framework|lib)/[a-z_-]+' \"$PRD_CONTENT\" | sort -u | jq -R . | jq -s .); echo \"{\\\"topics\\\":$TOPICS,\\\"stack\\\":$STACK}\"",
      "output": ".wheel/outputs/prd-context.json"
    },
    {
      "id": "search-mistakes",
      "type": "agent",
      "instruction": "You are the precedent reader. Your job is to find past mistakes relevant to the current build context and format them as a concise warning block.\n\n1. Read the PRD context from .wheel/outputs/prd-context.json — it contains topics[] and stack[] arrays.\n2. Build an Obsidian search query from these tags. Example: if topics=[\"hooks\",\"wheel\"] and stack=[\"language/typescript\"], query = \"(tag:topic/hooks OR tag:topic/wheel) AND tag:language/typescript path:mistakes/\".\n3. Call mcp__obsidian-projects__search_vault with that query, limit=10.\n4. If the search returns no results, also try a broader query with just the first topic tag.\n5. For each result, extract: title, assumption, correction, severity, project (from frontmatter).\n6. Format as a Markdown block:\n\n## Precedent — past mistakes relevant to this feature\n\n> These are real mistakes made in prior builds. Read before specifying or implementing.\n\n- **[severity]** `[mistake_class]` — [assumption]\n  ✓ Correction: [correction]\n  _(source: [project], [date])_\n\n7. Write the formatted block to .wheel/outputs/precedent-block.md.\n8. If no relevant mistakes found, write: `## Precedent\\n\\n_No relevant past mistakes found for this feature._`\n9. Emit JSON to your output: {\"count\": N, \"queries_used\": [...], \"path\": \".wheel/outputs/precedent-block.md\"}",
      "context_from": ["read-prd-context"],
      "output": ".wheel/outputs/precedent-search-result.json"
    }
  ]
}
```

#### `plugin-kiln/workflows/kiln-mistake-record.json`

Reusable 3-step sub-workflow called by any surface that produces a mistake entry: `collect-retro` (one call per mistake found), `kiln-report-issue` (AI-class issues), `kiln-feedback` (AI-failure entries). Keeps mistake writing and Obsidian sync logic in one place.

**Input contract** — caller writes `.wheel/inputs/mistake-data.json` before invoking:
```json
{ "summary": "...", "assumption": "...", "correction": "...", "source": "retro|report-issue|feedback" }
```
The workflow generates the ID and tags internally. Callers do not need to know the ID scheme or tag taxonomy.

```json
{
  "name": "kiln-mistake-record",
  "version": "1.0.0",
  "description": "Write a mistake entry to local ledger + .kiln/mistakes/, then mirror to Obsidian",
  "steps": [
    {
      "id": "write-mistake",
      "type": "agent",
      "model_tier": "validator",
      "instruction": "You are the mistake recorder. Persist a mistake entry from the caller's input.\n\n1. Read .wheel/inputs/mistake-data.json: {summary, assumption, correction, source}\n2. Generate a unique ID: mistake-<YYYYMMDD>-<slug-of-summary> (slug = first 4 words, kebab-cased)\n3. Derive tags from summary + assumption content (e.g. #hallucination, #wrong-assumption, #scope-drift, #shell, #test)\n4. Write .kiln/mistakes/<id>.md with frontmatter (id, source, tags) + body sections: Summary / Wrong assumption / Correction\n5. Write .kiln/ledger/<id>.json: {id, kind:\"mistake\", summary, assumption, correction, tags[], source, source_path, ts}\n6. Emit: {id, path:\".kiln/mistakes/<id>.md\", tags[]}",
      "output": ".wheel/outputs/mistake-written.json"
    },
    {
      "id": "sync-to-obsidian",
      "type": "agent",
      "instruction": "Mirror the newly written mistake file to Obsidian.\n\n1. Read .wheel/outputs/mistake-written.json for the id.\n2. Read .kiln/mistakes/<id>.md\n3. Call mcp__obsidian-projects__create_note or update_note to write it to the mistakes vault path.\n4. Emit: {synced: true, path: '.kiln/mistakes/<id>.md'}\n\nIf MCP unavailable: emit {synced: false, note: 'Obsidian unavailable — entry remains local'} and exit cleanly.",
      "on_failure": "skip",
      "context_from": ["write-mistake"],
      "output": ".wheel/outputs/mistake-synced.json"
    },
    {
      "id": "emit-summary",
      "type": "command",
      "command": "ID=$(jq -r '.id' .wheel/outputs/mistake-written.json); SYNCED=$(jq -r '.synced' .wheel/outputs/mistake-synced.json 2>/dev/null || echo false); echo \"{\\\"id\\\":\\\"${ID}\\\",\\\"path\\\":\\\".kiln/mistakes/${ID}.md\\\",\\\"synced\\\":${SYNCED}}\"",
      "output": ".wheel/outputs/mistake-record-summary.json"
    }
  ]
}
```

**`collect-retro` step update:** after writing ledger entries, for each entry where `kind == "mistake"`, the retrospective agent writes `.wheel/inputs/mistake-data.json` with `{summary, assumption, correction, source: "retro"}` and calls `wheel-run kiln:kiln-mistake-record` once per mistake. Same pattern for `kiln-report-issue` (source: "report-issue") and `kiln-feedback` (source: "feedback"). The workflow handles ID generation and tagging — callers only supply the four fields.

---

## Phase 2 — Build Pipeline as Wheel Workflow

**Goal:** `kiln-build-prd` becomes a resumable wheel workflow. Standards and precedent inject automatically. Review checkpoints gate on `config.json`. Structured verdicts replace prose relay.

### New Wheel Workflows

#### `plugin-kiln/workflows/kiln-distill.json`

Promotes `kiln-distill` from a SKILL.md to a resumable wheel workflow. Captures the vision-filter and auto_build behaviors as reliable, traceable steps. The skill becomes a thin wrapper calling `wheel-run kiln:kiln-distill`.

```json
{
  "name": "kiln-distill",
  "version": "1.0.0",
  "description": "Bundle open captures into a PRD, filter against vision, optionally trigger build",
  "steps": [
    {
      "id": "read-captures",
      "type": "command",
      "command": "ISSUES=$(find .kiln/issues -name '*.md' 2>/dev/null | wc -l | tr -d ' '); FEEDBACK=$(find .kiln/feedback -name '*.md' 2>/dev/null | wc -l | tr -d ' '); ROADMAP=$(find .kiln/roadmap/items -name '*.md' 2>/dev/null | wc -l | tr -d ' '); echo \"{\\\"issues\\\":$ISSUES,\\\"feedback\\\":$FEEDBACK,\\\"roadmap\\\":$ROADMAP,\\\"total\\\":$((ISSUES+FEEDBACK+ROADMAP))}\" > .wheel/outputs/captures-count.json; cat .kiln/issues/*.md .kiln/feedback/*.md .kiln/roadmap/items/*.md 2>/dev/null > .wheel/outputs/captures-combined.md; cat .wheel/outputs/captures-count.json",
      "output": ".wheel/outputs/captures-count.json"
    },
    {
      "id": "sync-designs",
      "type": "command",
      "command": "DESIGN_FIRST=$(jq -r '.design_first // false' .kiln/config.json 2>/dev/null); if [ \"$DESIGN_FIRST\" = 'true' ]; then echo 'design_first mode: pulling latest Penpot designs before distill...'; claude --print --model haiku 'Run /trim:trim-pull to pull latest design tokens and component specs from Penpot. Report: {synced: true|false, files_updated: N, error?: string}'; echo '{\"design_sync\": true}'; else echo '{\"design_sync\": false, \"reason\": \"design_first disabled\"}'; fi",
      "on_failure": "skip",
      "output": ".wheel/outputs/design-sync-result.json"
    },
    {
      "id": "vision-filter",
      "type": "agent",
      "instruction": "You are the vision filter. Remove captures that conflict with the project vision before distillation.\n\n1. Read .kiln/vision.md (if it exists — skip this step if absent).\n2. Read .wheel/outputs/captures-combined.md\n3. For each capture, check: does it contradict a 'what this is NOT' or constraint in vision.md?\n4. Write .wheel/outputs/captures-filtered.md with only the kept captures.\n5. Emit JSON: {kept: N, filtered: N, reasons: [{id, reason}]}",
      "on_failure": "skip",
      "output": ".wheel/outputs/vision-filter-result.json"
    },
    {
      "id": "group-and-draft",
      "type": "agent",
      "model_tier": "implementer",
      "instruction": "You are the PRD drafter. Group the filtered captures by theme and write a PRD.\n\n1. Read .wheel/outputs/captures-filtered.md (or captures-combined.md if vision-filter was skipped).\n2. Group by common theme, user need, or feature area.\n3. Pick a slug: <date>-<theme-slug> (e.g. 2026-06-24-auth-improvements).\n4. Write docs/features/<slug>/PRD.md following the project PRD template.\n5. Write .wheel/outputs/prd-path.txt with the PRD file path.\n6. Emit JSON: {slug, prd_path, capture_count: N, themes: [...]}",
      "context_from": ["vision-filter"],
      "output": ".wheel/outputs/distill-verdict.json"
    },
    {
      "id": "mark-processed",
      "type": "command",
      "command": "PRD=$(cat .wheel/outputs/prd-path.txt 2>/dev/null); SLUG=$(basename $(dirname $PRD) 2>/dev/null); find .kiln/issues .kiln/feedback .kiln/roadmap/items -name '*.md' 2>/dev/null | while read f; do echo \"processed: $SLUG\" >> \"$f\"; done; echo \"{\\\"marked_processed\\\":true,\\\"prd\\\":\\\"$PRD\\\"}\"",
      "output": ".wheel/outputs/mark-processed.json"
    },
    {
      "id": "trigger-build",
      "type": "command",
      "command": "AUTO=$(jq -r '.auto_build // false' .kiln/config.json 2>/dev/null); SLUG=$(cat .wheel/outputs/prd-path.txt 2>/dev/null | xargs dirname | xargs basename); if [ \"$AUTO\" = 'true' ]; then echo \"PRD created. Starting build pipeline for $SLUG...\"; echo \"{\\\"auto_build\\\":true,\\\"slug\\\":\\\"$SLUG\\\"}\"; else echo \"PRD ready at docs/features/$SLUG/PRD.md. Run /kiln:kiln-build-prd $SLUG to build.\"; echo \"{\\\"auto_build\\\":false,\\\"slug\\\":\\\"$SLUG\\\"}\"; fi",
      "output": ".wheel/outputs/trigger-result.json"
    },
    {
      "id": "invoke-build",
      "type": "command",
      "command": "AUTO=$(jq -r '.auto_build // false' .wheel/outputs/trigger-result.json 2>/dev/null); SLUG=$(jq -r '.slug // \"\"' .wheel/outputs/trigger-result.json 2>/dev/null); if [ \"$AUTO\" = 'true' ] && [ -n \"$SLUG\" ]; then echo \"$SLUG\" > .wheel/inputs/prd-slug.txt; wheel-run kiln:kiln-build-prd; else echo 'SKIP: auto_build=false — build not triggered'; fi",
      "on_failure": "skip"
    }
  ]
}
```

#### `plugin-kiln/workflows/kiln-fix.json`

Promotes `kiln-fix` from a skill to a resumable wheel workflow. The skill becomes a thin wrapper calling `wheel-run kiln:kiln-fix`.

**Auto-invoked from two places:**
- **`kiln-build-prd` post-audit (A):** if `audit-synthesize` returns `severity: blocking`, the `fix-blocking` implementer step runs inline — reads each blocking finding, fixes the implementation, verifies tests. Any finding the implementer cannot resolve is marked `escalate` and surfaces as priority 1 in kiln-next. No separate kiln-fix sub-workflow is spawned.
- **`kiln-next` with `auto_build: true` (B):** if `kiln-next` detects failing tests on an already-implemented feature (spec exists, code exists, tests failing), it auto-invokes `kiln-fix` rather than just recommending it.

```json
{
  "name": "kiln-fix",
  "version": "1.0.0",
  "description": "Diagnose → fix → verify loop for targeted bug fixes. Auto-invoked by kiln-build-prd post-audit and kiln-next (auto_build mode).",
  "hooks": {
    "post": {
      "command": "bash \"${WORKFLOW_PLUGIN_DIR}/../plugin-kiln/scripts/notify.sh\" \"$WHEEL_RUN_ID\" \"$WHEEL_STATUS\"",
      "on": "always",
      "env_required": []
    }
  },
  "steps": [
    {
      "id": "read-context",
      "type": "command",
      "command": "ISSUE=$(cat .wheel/inputs/issue.txt 2>/dev/null || echo ''); TESTS=$(npm test 2>&1 | tail -40 || echo 'no test output'); echo \"{\\\"issue\\\":\\\"$ISSUE\\\",\\\"test_output\\\":\\\"$TESTS\\\"}\"",
      "output": ".wheel/outputs/fix-context.json"
    },
    {
      "id": "diagnose",
      "type": "agent",
      "model_tier": "researcher",
      "context_from": ["read-context"],
      "instruction": "You are the fix diagnostician. Read fix-context.json (issue description + test output).\n\nRead the relevant source files and failing tests.\n\nWrite .wheel/outputs/diagnosis.json:\n{\n  \"summary\": \"one-line description of the bug\",\n  \"root_cause\": \"...\",\n  \"implicated_files\": [\"src/...\"],\n  \"implicated_frs\": [\"FR-3\"],\n  \"fix_strategy\": \"...\",\n  \"risk\": \"low|medium|high\"\n}\n\nEmit the JSON only.",
      "output": ".wheel/outputs/diagnosis.json"
    },
    {
      "id": "fix",
      "type": "agent",
      "model_tier": "implementer",
      "context_from": ["diagnose"],
      "instruction": "You are the fix implementer. Read .wheel/outputs/diagnosis.json.\n\nApply the fix strategy to the implicated files. Every change must match the existing contract in specs/<feature>/contracts/interfaces.md if one exists.\n\nCommit with message: fix(<area>): <summary>\n\nWrite .wheel/outputs/fix-result.json: {\"files_changed\": [], \"commit\": \"<sha>\"}",
      "on_failure": { "route": "kiln:debugger", "max_debug_attempts": 2 },
      "output": ".wheel/outputs/fix-result.json"
    },
    {
      "id": "verify",
      "type": "command",
      "command": "COVERAGE_GATE=$(jq -r '.coverage_gate // 80' .kiln/test-strategy.json 2>/dev/null); TEST_CMD=$(jq -r '.test // \"npm test\"' .kiln/test-strategy.json 2>/dev/null); $TEST_CMD 2>&1; echo \"{\\\"exit\\\":$?,\\\"gate\\\":$COVERAGE_GATE}\"",
      "on_failure": { "route": "kiln:debugger", "max_debug_attempts": 2 },
      "output": ".wheel/outputs/verify-result.json"
    },
    {
      "id": "write-ledger",
      "type": "agent",
      "model_tier": "validator",
      "context_from": ["diagnose", "fix", "verify"],
      "instruction": "Write a ledger entry to .kiln/ledger/<run-id>-fix.json:\n{id, kind:\"fix\", summary, detail, blast_radius, tags:[\"topic/<area>\"], source_path, ts}\n\nEmit the path written.",
      "output": ".wheel/outputs/ledger-entry.json"
    },
    {
      "id": "build-summary",
      "type": "agent",
      "model_tier": "validator",
      "on": "always",
      "context_from": ["diagnose", "fix", "verify"],
      "instruction": "Generate a fix summary in markdown tables:\n\n### Fix Summary\n| Field | Value |\n|---|---|\n| Issue | <summary> |\n| Root cause | <root_cause> |\n| Files changed | <list> |\n| Tests | Pass / Fail |\n\n### What to Verify\n| Step | Expected |\n|---|---|\n(derive from failing tests that should now pass)\n\nRead run-id from .wheel/outputs/run-id.txt.\nPrint to output AND write to .kiln/runs/<run-id>/summary.md",
      "output": ".wheel/outputs/fix-summary.json"
    }
  ]
}
```

#### `plugin-kiln/workflows/kiln-build-prd.json`
```json
{
  "name": "kiln-build-prd",
  "version": "1.0.0",
  "description": "Full spec-first build pipeline (26 steps): config → precedent → specify → checkpoint → plan → tasks → gate → dispatch → implement → test → smoke → checkpoint → audit → synthesize → fix-blocking → checkpoint → PR → checkpoint → retro → classify → apply → manifest → summary",
  "steps": [
    {
      "id": "read-config",
      "type": "command",
      "command": "cat .kiln/config.json 2>/dev/null || echo '{\"review_mode\":\"standard\",\"review_checkpoints\":[\"post-spec\",\"pre-pr\"],\"auto_build\":false,\"auto_pr\":false,\"auto_merge\":false,\"pi_apply_threshold\":\"none\",\"standards\":\".kiln/standards.md\"}'",
      "output": ".wheel/outputs/kiln-config.json"
    },
    {
      "id": "read-prd",
      "type": "command",
      "command": "PRD_SLUG=$(cat .wheel/inputs/prd-slug.txt 2>/dev/null); PRD_PATH=\"docs/features/${PRD_SLUG}/PRD.md\"; if [ ! -f \"$PRD_PATH\" ]; then echo \"ERROR: PRD not found at $PRD_PATH\" >&2; exit 1; fi; echo \"$PRD_PATH\" > .wheel/outputs/prd-path.txt; cat \"$PRD_PATH\"",
      "output": ".wheel/outputs/prd-content.md"
    },
    {
      "id": "read-standards",
      "type": "command",
      "command": "STANDARDS=$(jq -r '.standards // \".kiln/standards.md\"' .wheel/outputs/kiln-config.json 2>/dev/null || echo '.kiln/standards.md'); cat \"$STANDARDS\" 2>/dev/null || echo '## Coding Standards\\n\\n_No standards file found — using defaults._'",
      "output": ".wheel/outputs/standards-block.md"
    },
    {
      "id": "init-run-manifest",
      "type": "command",
      "command": "RUN_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s); PRD_SLUG=$(cat .wheel/inputs/prd-slug.txt 2>/dev/null); BRANCH=$(git branch --show-current); mkdir -p \".kiln/runs/${RUN_ID}\"; echo \"{\\\"run_id\\\":\\\"${RUN_ID}\\\",\\\"prd\\\":\\\"docs/features/${PRD_SLUG}/PRD.md\\\",\\\"phase\\\":\\\"specify\\\",\\\"branch\\\":\\\"${BRANCH}\\\",\\\"pr\\\":null,\\\"decisions\\\":[],\\\"escalations\\\":[],\\\"cursor\\\":\\\"init-run-manifest\\\",\\\"cost\\\":{\\\"total_usd\\\":0,\\\"input_tokens\\\":0,\\\"output_tokens\\\":0,\\\"by_model\\\":{}}}\" > \".kiln/runs/${RUN_ID}/manifest.json\"; echo \"$RUN_ID\" > .wheel/outputs/run-id.txt; cat \".kiln/runs/${RUN_ID}/manifest.json\"",
      "output": ".wheel/outputs/run-manifest.json"
    },
    {
      "id": "query-precedent",
      "type": "command",
      "command": "bash \"${WORKFLOW_PLUGIN_DIR}/../plugin-kiln/scripts/run-sub-workflow.sh\" kiln:kiln-precedent || echo '> ⚠ Obsidian MCP unavailable — precedent skipped. Build continues without historical context.'",
      "on_failure": "skip",
      "output": ".wheel/outputs/precedent-block.md"
    },
    {
      "id": "specify",
      "type": "agent",
      "instruction": "You are the specifier. Your job is to produce a complete spec.md for the PRD.\n\n## Runtime Environment\nWORKFLOW_PLUGIN_DIR is available if needed for script execution.\n\n## Inputs\n- PRD: read .wheel/outputs/prd-content.md\n- Standards: read .wheel/outputs/standards-block.md — FOLLOW THESE. Naming, function size, and error handling rules apply to every interface you define.\n- Precedent: read .wheel/outputs/precedent-block.md — AVOID the listed mistakes.\n\n## Output\nWrite specs/<prd-slug>/spec.md with:\n- ## User Stories (one per actor)\n- ## Functional Requirements (FR-001, FR-002, ...)\n- ## Non-Functional Requirements (NFR-001, ...)\n- ## Acceptance Criteria (one scenario per FR)\n- ## Open Questions\n\nGet the prd-slug from the PRD filename path stored in .wheel/outputs/prd-path.txt.\n\nEmit JSON verdict: {\"agent\":\"specifier\",\"verdict\":\"pass\",\"spec_path\":\"specs/<slug>/spec.md\",\"fr_count\":N,\"open_questions\":[]}",
      "context_from": ["read-prd", "read-standards", "query-precedent"],
      "output": ".wheel/outputs/specify-verdict.json"
    },
    {
      "id": "checkpoint-post-spec",
      "type": "command",
      "command": "CHECKPOINTS=$(jq -r '.review_checkpoints // [] | join(\",\")' .wheel/outputs/kiln-config.json 2>/dev/null); BLOCKING=$(jq -r '.severity // \"pass\"' .wheel/outputs/specify-verdict.json 2>/dev/null); if echo \"$CHECKPOINTS\" | grep -q 'post-spec' || [ \"$BLOCKING\" = 'blocking' ]; then echo '{\"checkpoint\":\"post-spec\",\"action\":\"pause\"}'; else echo '{\"checkpoint\":\"post-spec\",\"action\":\"skip\"}'; fi",
      "output": ".wheel/outputs/checkpoint-post-spec.json"
    },
    {
      "id": "plan",
      "type": "agent",
      "instruction": "You are the planner. Produce plan.md and contracts/interfaces.md.\n\n## Inputs\n- Spec: read the spec.md path from .wheel/outputs/specify-verdict.json\n- Standards: read .wheel/outputs/standards-block.md — ALL interface names and function signatures MUST follow the naming rules. Function contracts MUST declare <=2 parameters or use an options object.\n- Precedent: read .wheel/outputs/precedent-block.md\n\n## Output\n1. specs/<slug>/plan.md — technical approach, phases, file list\n2. specs/<slug>/contracts/interfaces.md — EVERY exported function: name, params, return type, sync/async, which FR it satisfies\n\nEmit JSON verdict: {\"agent\":\"planner\",\"verdict\":\"pass\",\"plan_path\":\"...\",\"contracts_path\":\"...\",\"interface_count\":N}",
      "context_from": ["specify", "read-standards", "query-precedent"],
      "output": ".wheel/outputs/plan-verdict.json"
    },
    {
      "id": "tasks",
      "type": "agent",
      "instruction": "You are the task planner. Produce tasks.md from the spec and plan.\n\n## Inputs\n- Spec verdict: .wheel/outputs/specify-verdict.json\n- Plan verdict: .wheel/outputs/plan-verdict.json\n\n## Output\nspecs/<slug>/tasks.md with ordered, dependency-aware tasks. Each task must:\n- Reference the FR it implements\n- Reference the interface(s) from contracts/interfaces.md it touches\n- Be completable in a single session without breaking the build\n\nEmit JSON verdict: {\"agent\":\"task-planner\",\"verdict\":\"pass\",\"tasks_path\":\"...\",\"task_count\":N}",
      "context_from": ["specify", "plan"],
      "output": ".wheel/outputs/tasks-verdict.json"
    },
    {
      "id": "check-hooks-gate",
      "type": "command",
      "command": "SLUG=$(cat .wheel/inputs/prd-slug.txt 2>/dev/null); SPEC=\"specs/${SLUG}/spec.md\"; PLAN=\"specs/${SLUG}/plan.md\"; TASKS=\"specs/${SLUG}/tasks.md\"; CONTRACTS=\"specs/${SLUG}/contracts/interfaces.md\"; ERRORS=''; [ -f \"$SPEC\" ] || ERRORS=\"$ERRORS spec.md missing;\"; [ -f \"$PLAN\" ] || ERRORS=\"$ERRORS plan.md missing;\"; [ -f \"$TASKS\" ] || ERRORS=\"$ERRORS tasks.md missing;\"; [ -f \"$CONTRACTS\" ] || ERRORS=\"$ERRORS contracts/interfaces.md missing;\"; if [ -n \"$ERRORS\" ]; then echo \"GATE FAIL: $ERRORS\" >&2; exit 1; fi; echo 'GATE PASS: spec+plan+tasks+contracts present'; echo '{\"gate\":\"pass\"}'",
      "output": ".wheel/outputs/hooks-gate.json"
    },
    {
      "id": "dispatch-implement",
      "type": "command",
      "command": "SLUG=$(cat .wheel/inputs/prd-slug.txt); TASKS=\"specs/${SLUG}/tasks.md\"; STORIES=$(grep -E '^### US-' \"$TASKS\" | sed 's/### //' | jq -R -s 'split(\"\\n\") | map(select(length>0))'); COUNT=$(echo \"$STORIES\" | jq 'length'); echo \"{\\\"stories\\\":$STORIES,\\\"count\\\":$COUNT,\\\"tasks_path\\\":\\\"$TASKS\\\"}\" > .wheel/inputs/implement-dispatch.json; echo \"Dispatch: $COUNT user stories → $COUNT parallel implementers\"; cat .wheel/inputs/implement-dispatch.json",
      "output": ".wheel/inputs/implement-dispatch.json"
    },
    {
      "id": "implement",
      "type": "team",
      "members": [
        {
          "role": "kiln:implementer",
          "per": "item",
          "from": ".wheel/inputs/implement-dispatch.json",
          "field": "stories",
          "isolation": "worktree",
          "inject": {"run_id": ".wheel/outputs/run-id.txt", "contracts": ".wheel/outputs/plan-verdict.json"}
        },
        {
          "role": "kiln:spec-enforcer",
          "count": 1,
          "mode": "watch"
        },
        {
          "role": "kiln:qa-engineer",
          "count": 1,
          "mode": "checkpoint"
        }
      ],
      "merge_after": true,
      "merge_conflict_handler": "route:owner:2,then:escalate",
      "context_from": ["dispatch-implement", "tasks", "plan", "read-standards", "query-precedent"],
      "output": ".wheel/outputs/implement-verdict.json"
    },
    {
      "id": "run-tests",
      "type": "command",
      "command": "COVERAGE_GATE=$(cat .kiln/test-strategy.json 2>/dev/null | jq -r '.coverage_gate // 80'); TEST_CMD=$(cat .kiln/test-strategy.json 2>/dev/null | jq -r '.test // \"npm test\"'); eval \"$TEST_CMD\" 2>&1; EXIT=$?; echo \"{\\\"exit\\\":$EXIT,\\\"coverage_gate\\\":$COVERAGE_GATE}\"",
      "output": ".wheel/outputs/test-results.json"
    },
    {
      "id": "smoke-review",
      "type": "agent",
      "instruction": "You are the smoke reviewer. Verify the implementation works at runtime.\n\n## Inputs\n- Test strategy: read .kiln/test-strategy.json for start/ready/probe commands\n- Test results: read .wheel/outputs/test-results.json\n- PRD slug: read .wheel/inputs/prd-slug.txt\n\n## Steps\n1. Start the app per smoke.start in test-strategy.json\n2. Wait for smoke.ready endpoint to respond\n3. Execute smoke.probe (e.g., Playwright render or curl)\n4. If design_verify is true, screenshot the running app and compare vs design/<slug>/mockup.png (or .jpg/.html — use the first file found under design/<slug>/). Fidelity score: 0-100 subjective match estimate.\n5. Stop the app per smoke.teardown\n6. Write markdown report to specs/<slug>/smoke-report.md (test plan, steps executed, pass/fail per step, findings)\n\nTwo outputs:\n- Write .wheel/outputs/smoke-verdict.json: {\"agent\":\"smoke-reviewer\",\"verdict\":\"pass|fail\",\"findings\":[],\"fidelity_score\":null,\"report_path\":\"specs/<slug>/smoke-report.md\"}\n- Copy report to .wheel/outputs/smoke-report.md (build-summary reads from here)",
      "context_from": ["implement", "run-tests"],
      "output": ".wheel/outputs/smoke-verdict.json"
    },
    {
      "id": "checkpoint-post-implement",
      "type": "command",
      "command": "CHECKPOINTS=$(jq -r '.review_checkpoints // [] | join(\",\")' .wheel/outputs/kiln-config.json 2>/dev/null); BLOCKING=$(jq -r 'if (.verdict==\"fail\" or (.blockers|length)>0) then \"blocking\" else \"pass\" end' .wheel/outputs/implement-verdict.json 2>/dev/null || echo 'pass'); if echo \"$CHECKPOINTS\" | grep -q 'post-implement' || [ \"$BLOCKING\" = 'blocking' ]; then echo '{\"checkpoint\":\"post-implement\",\"action\":\"pause\"}'; else echo '{\"checkpoint\":\"post-implement\",\"action\":\"skip\"}'; fi",
      "output": ".wheel/outputs/checkpoint-post-implement.json"
    },
    {
      "id": "audit",
      "type": "team",
      "members": [
        {"role": "kiln:prd-auditor", "count": 1},
        {"role": "kiln:spec-enforcer", "count": 1},
        {"role": "kiln:quality-judge", "count": 1}
      ],
      "context_from": ["specify", "implement", "run-tests", "smoke-review"],
      "output": ".wheel/outputs/audit-raw-verdict.json"
    },
    {
      "id": "audit-synthesize",
      "type": "agent",
      "model_tier": "validator",
      "instruction": "You are the audit synthesizer. Merge all audit verdicts into a single result.\n\n## Inputs\n- .wheel/outputs/audit-raw-verdict.json — main auditor verdict\n\n## Task\n1. Read audit-raw-verdict.json.\n2. Determine overall severity: if any finding has severity=blocking → overall severity=blocking; if any=warn → severity=warn; else severity=pass.\n3. Deduplicate findings by file+FR if multiple auditors flagged the same issue.\n4. Write .wheel/outputs/audit-verdict.json:\n   {\"compliance_pct\":N, \"severity\":\"pass|warn|blocking\", \"findings\":[{\"severity\",\"fr\",\"file\",\"description\"}], \"blockers_path\":null|\"specs/<slug>/blockers.md\"}\n5. If severity=blocking, write each blocking finding to .wheel/outputs/blocking-findings.json.",
      "context_from": ["audit"],
      "output": ".wheel/outputs/audit-verdict.json"
    },
    {
      "id": "fix-blocking",
      "type": "agent",
      "model_tier": "implementer",
      "instruction": "You are the blocking-fix implementer. Resolve audit findings that are blocking the PR.\n\n## Inputs\n- .wheel/outputs/blocking-findings.json — list of blocking findings from audit-synthesize\n- .wheel/outputs/audit-verdict.json — full audit context\n- specs/<slug>/spec.md — spec for FR reference\n- specs/<slug>/contracts/interfaces.md — interface contracts\n\n## Task\n1. Read blocking-findings.json. If empty or absent, emit {\"fixed\": 0, \"skipped\": true} and stop.\n2. For each blocking finding: read the implicated file, understand the FR it violates, fix the implementation to satisfy the FR without breaking other contracts.\n3. After all fixes, run the test suite to verify nothing regressed.\n4. Write .wheel/outputs/fix-blocking-verdict.json: {\"fixed\": N, \"remaining\": N, \"findings\": [{\"fr\", \"file\", \"fix_summary\", \"status\": \"fixed|escalate\"}]}\n5. Any finding you cannot fix: mark status=escalate — these surface as priority 1 in kiln-next for human attention.\n\nDo NOT spawn sub-agents or call kiln-fix. Fix inline.",
      "context_from": ["audit-synthesize"],
      "on_failure": "route:kiln:debugger",
      "output": ".wheel/outputs/fix-blocking-verdict.json"
    },
    {
      "id": "checkpoint-pre-pr",
      "type": "command",
      "command": "CHECKPOINTS=$(jq -r '.review_checkpoints // [] | join(\",\")' .wheel/outputs/kiln-config.json 2>/dev/null); AUTO_PR=$(jq -r '.auto_pr // false' .wheel/outputs/kiln-config.json 2>/dev/null); BLOCKING=$(jq -r '.severity // \"pass\"' .wheel/outputs/audit-verdict.json 2>/dev/null); if [ \"$AUTO_PR\" = 'true' ]; then echo '{\"checkpoint\":\"pre-pr\",\"action\":\"skip\",\"reason\":\"auto_pr=true\"}'; elif echo \"$CHECKPOINTS\" | grep -q 'pre-pr' || [ \"$BLOCKING\" = 'blocking' ]; then echo '{\"checkpoint\":\"pre-pr\",\"action\":\"pause\"}'; else echo '{\"checkpoint\":\"pre-pr\",\"action\":\"skip\"}'; fi",
      "output": ".wheel/outputs/checkpoint-pre-pr.json"
    },
    {
      "id": "create-pr",
      "type": "command",
      "command": "SLUG=$(cat .wheel/inputs/prd-slug.txt 2>/dev/null); AUDIT=$(cat .wheel/outputs/audit-verdict.json 2>/dev/null | jq -r '.compliance_pct // \"?\"'); BRANCH=$(git branch --show-current); STYLE=$(jq -r '.branching.style // \"github-flow\"' .wheel/outputs/kiln-config.json 2>/dev/null); BASE=$(if [ \"$STYLE\" = 'gitflow' ]; then jq -r '.branching.integration_branch // \"dev\"' .wheel/outputs/kiln-config.json 2>/dev/null; else echo 'main'; fi); git push -u origin \"$BRANCH\" 2>&1; PR_URL=$(gh pr create --base \"$BASE\" --title \"feat($SLUG): build-prd pipeline\" --body \"PRD: docs/features/${SLUG}/PRD.md\\n\\nAudit compliance: ${AUDIT}%\\n\\nGenerated by kiln-build-prd workflow.\" --label 'build-prd' 2>&1); echo \"PR: $PR_URL\"; echo \"{\\\"pr_url\\\":\\\"$PR_URL\\\",\\\"base\\\":\\\"$BASE\\\"}\"",
      "output": ".wheel/outputs/pr-result.json"
    },
    {
      "id": "checkpoint-pre-merge",
      "type": "command",
      "command": "CHECKPOINTS=$(jq -r '.review_checkpoints // [] | join(\",\")' .wheel/outputs/kiln-config.json 2>/dev/null); AUTO_MERGE=$(jq -r '.auto_merge // false' .wheel/outputs/kiln-config.json 2>/dev/null); if [ \"$AUTO_MERGE\" = 'true' ]; then echo '{\"checkpoint\":\"pre-merge\",\"action\":\"skip\",\"reason\":\"auto_merge=true\"}'; elif echo \"$CHECKPOINTS\" | grep -q 'pre-merge'; then echo '{\"checkpoint\":\"pre-merge\",\"action\":\"pause\"}'; else echo '{\"checkpoint\":\"pre-merge\",\"action\":\"skip\"}'; fi",
      "output": ".wheel/outputs/checkpoint-pre-merge.json"
    },
    {
      "id": "collect-retro",
      "type": "agent",
      "instruction": "You are the retrospective collector. Gather all friction from this build run and write it to the ledger.\n\n## Inputs\nRead the run-id from .wheel/outputs/run-id.txt.\nRead all agent-notes from .kiln/runs/<run-id>/agent-notes/*.md.\nRead all verdict files: specify, plan, tasks, implement, audit.\nRead .wheel/outputs/run-manifest.json for run context.\n\n## Output\n1. For each friction point found, write a ledger entry to .kiln/ledger/<run-id>-<n>.json:\n   {id, kind:\"friction\"|\"mistake\", summary, detail, blast_radius, tags[], source_path, ts}\n2. For each concrete improvement proposal (not just friction — actionable change with a target file/prompt), write a proposal stub to .kiln/ledger/proposals/<run-id>-<n>.json:\n   {id, target, summary, patch_hint, risk:null, blast_radius, ledger_ref}\n   (risk is null — classify-proposals fills it in)\n3. Write a retro summary to .kiln/runs/<run-id>/retro.md:\n   - What went well\n   - What slowed us down\n   - Improvement proposals (concrete, actionable)\n4. For each mistake-class friction (hallucination, wrong assumption, incorrect output), write .wheel/inputs/mistake-data.json and call: wheel-run kiln:kiln-mistake-record\n5. Emit JSON: {\"agent\":\"retrospective\",\"ledger_entries\":N,\"proposals\":N,\"retro_path\":\"...\"}",
      "context_from": ["implement", "audit", "smoke-review"],
      "output": ".wheel/outputs/retro-verdict.json"
    },
    {
      "id": "classify-proposals",
      "type": "agent",
      "instruction": "You are the risk classifier. Classify each improvement proposal from the retro as low or high risk.\n\n## Inputs\nRead .wheel/outputs/retro-verdict.json for ledger entry paths.\nRead each .kiln/ledger/*.json entry where kind==\"friction\" from this run.\n\n## Classification rules\n- LOW risk: single-file prompt edit, no hook/gate changes, has a clear test, blast_radius=local\n- HIGH risk: touches hooks, gates, contracts, cross-plugin scripts, or has blast_radius=cross-plugin\n\n## Output\nFor each proposal, write .kiln/ledger/proposals/<id>.json with the schema:\n{id, target, patch, risk:\"low\"|\"high\", blast_radius, rationale, ledger_refs[]}\n\nEmit JSON: {\"agent\":\"risk-classifier\",\"low_count\":N,\"high_count\":N,\"proposal_paths\":[]}",
      "context_from": ["collect-retro"],
      "output": ".wheel/outputs/classify-verdict.json"
    },
    {
      "id": "apply-low-risk",
      "type": "command",
      "command": "PI_THRESHOLD=$(jq -r '.pi_apply_threshold // \"none\"' .wheel/outputs/kiln-config.json 2>/dev/null); if [ \"$PI_THRESHOLD\" = 'none' ]; then echo 'SKIP: pi_apply_threshold=none'; echo '{\"applied\":0,\"skipped\":\"threshold=none\"}'; exit 0; fi; LOW_COUNT=$(jq -r '.low_count // 0' .wheel/outputs/classify-verdict.json 2>/dev/null); echo \"Would auto-apply $LOW_COUNT low-risk proposals (threshold=$PI_THRESHOLD)\"; echo \"{\\\"applied\\\":0,\\\"pending\\\":$LOW_COUNT,\\\"threshold\\\":\\\"$PI_THRESHOLD\\\"}\"",
      "output": ".wheel/outputs/apply-result.json"
    },
    {
      "id": "update-run-manifest",
      "type": "command",
      "command": "RUN_ID=$(cat .wheel/outputs/run-id.txt 2>/dev/null); PR_URL=$(jq -r '.pr_url // null' .wheel/outputs/pr-result.json 2>/dev/null); if [ -n \"$RUN_ID\" ] && [ -f \".kiln/runs/${RUN_ID}/manifest.json\" ]; then jq \".phase=\\\"done\\\" | .pr=\\\"$PR_URL\\\" | .cursor=\\\"update-run-manifest\\\"\" \".kiln/runs/${RUN_ID}/manifest.json\" > /tmp/manifest-update.json && mv /tmp/manifest-update.json \".kiln/runs/${RUN_ID}/manifest.json\"; fi; echo 'Run manifest updated to done.'",
      "output": ".wheel/outputs/run-manifest-final.json"
    },
    {
      "id": "build-summary",
      "type": "agent",
      "model_tier": "validator",
      "on": "always",
      "context_from": ["read-prd", "specify", "audit-synthesize", "smoke-review", "collect-retro", "update-run-manifest"],
      "instruction": "You are the build summary agent. Generate a structured markdown summary of this build run for the human.\n\n## Inputs to read\n- .wheel/outputs/prd-content.md — feature name and user stories\n- .wheel/outputs/audit-verdict.json — compliance_pct, findings[]\n- .wheel/outputs/test-results.json — coverage %, pass/fail\n- .wheel/outputs/smoke-report.md — smoke test outcome\n- .wheel/outputs/pr-result.json — PR URL and number\n- .wheel/outputs/run-manifest-final.json — run_id, branch, prd path\n- Run: git diff --stat HEAD~1 to get files changed\n\n## Output format (MUST be markdown tables)\n\n### Overview\n| Field | Value |\n|---|---|\n| Feature | [<name>](<prd-path>) |\n| Branch | `<branch>` |\n| PR | [#<n>](<url>) |\n| Spec compliance | <pct>% |\n| Test coverage | <pct>% |\n| Smoke test | Passed / Failed |\n\n### What Changed\n| File | Change |\n|---|---|\n(from git diff --stat)\n\n### What to Test\n| User Story | How to verify | Expected result |\n|---|---|---|\n(derive from PRD user stories + spec acceptance criteria)\n\n### Findings\n| Severity | Finding |\n|---|---|\n(from audit + smoke; omit section entirely if no findings)\n\n### Links\n| Resource | Path |\n|---|---|\n| PR | <url> |\n| Spec | specs/<slug>/spec.md |\n| Contracts | specs/<slug>/contracts/interfaces.md |\n| Smoke report | specs/<slug>/smoke-report.md |\n| Retro | .kiln/runs/<id>/retro.md |\n\n## Save to file\nWrite the complete summary to .kiln/runs/<run-id>/summary.md\nThen print the full summary to your output (the human reads your output directly).",
      "output": ".kiln/runs/summary.md"
    }
  ]
}
```

**Skill wrapper input contract:** The `kiln-build-prd` SKILL.md is responsible for writing `.wheel/inputs/prd-slug.txt` (the feature slug, e.g. `2026-06-22-my-feature`) before calling `wheel-run kiln:kiln-build-prd`. The workflow's `read-prd` step reads this file on step 2; if it is absent, `read-prd` exits 1 and the workflow halts. The skill wrapper derives the slug from the user's argument or from the most recent `docs/features/` directory if no argument is given.

**Design mockup path convention:** When `design_first: true` is set and `smoke-review` runs `design_verify`, mockup files are expected at `design/<slug>/mockup.{png,jpg,html}` — the first file found wins. Trim writes mockups here via `trim-pull`. If no file exists under `design/<slug>/`, `fidelity_score` is set to `null` and the finding is reported as `info` severity (not blocking).

### New Agents (Phase 2)

#### `build-summary.md`
**Role:** Final step of every qualifying workflow (`kiln-build-prd`, `kiln-fix`). Reads all verdict outputs and the run's cost manifest, runs `git diff --stat`, renders the canonical 5-table build summary. Writes to `.kiln/runs/<run-id>/summary.md` AND prints to terminal output so the human sees it directly.

**Model tier:** `validator` (haiku — purely a formatter, no reasoning required)  
**Tools:** `Read`, `Write`, `Bash` (for `git diff --stat`)  
**`on: always`** — runs even if upstream steps failed; human always gets a summary

```markdown
---
name: build-summary
role: validator
model_tier: validator
on: always
tools: [Read, Write, Bash]
---

You are the build summary agent. Your job is to render a structured summary of this build run.

## Inputs to read
- .wheel/outputs/prd-content.md — feature name + user stories
- .wheel/outputs/audit-verdict.json — compliance_pct, findings[]
- .wheel/outputs/test-results.json — coverage %, pass/fail
- .wheel/outputs/smoke-report.md — smoke test result
- .wheel/outputs/pr-result.json — PR URL + number
- .wheel/outputs/run-manifest-final.json — run_id, branch, prd path, cost block
- Run: bash -c "git diff --stat HEAD~1" to get files changed

## Output (write to file AND print)
Render the 5-table markdown summary (Overview / What Changed / What to Test / Findings / Links)
as defined in the Structured Human Output design principle.

Include Tokens + Cost rows in Overview from run-manifest-final.json cost block.
Omit Findings section entirely if findings[] is empty.

Write to: .kiln/runs/<run-id>/summary.md  (get run_id from run-manifest-final.json)
Then print the full summary as your final output — the human reads this directly.
```

<!-- parallel-critic removed — redundant given precedent injection at implement start + spec-enforcer + audit. Future idea: a live pattern-watcher that fires mid-implementation when flag rate on a known mistake exceeds a threshold, escalating to pause rather than just flagging. Deferred until precedent corpus is large enough to make pattern-matching meaningful. -->

### Modified Skills

**`kiln-build-prd`** — becomes a thin wrapper that invokes `wheel-run kiln:kiln-build-prd`, passing the PRD slug as input. Gains a `--resume` flag: reads `.kiln/runs/<run-id>/manifest.json`, finds `cursor` (last completed step), and passes it to `wheel-run` as the start step so the workflow resumes from where it halted rather than restarting from scratch.

**`kiln-next`** — reads `.kiln/runs/*/manifest.json` to detect resumable in-progress runs; surfaces them as the top suggestion with the exact resume command.

**`kiln-fix`** — gains `--resume` flag. `kiln-fix.json` gains an `init-run-manifest` first step. On interruption, `kiln-next` surfaces: `/kiln:kiln-fix <slug> --resume`.

**`kiln-distill`** — same pattern. `kiln-distill.json` gains an `init-run-manifest` first step. On mid-draft interruption, `kiln-next` surfaces: `/kiln:kiln-distill --resume`.

---

## Phase 3 — Self-Improvement Loop

**Goal:** Friction captured during builds automatically closes into either L1 config patches (applied in-loop) or L2 skill-edit chips (surfaced to human). The loop is fully traceable.

### New Wheel Workflow

#### `plugin-kiln/workflows/kiln-self-improve.json`
```json
{
  "name": "kiln-self-improve",
  "version": "1.0.0",
  "description": "Collect build friction and retro, classify proposals by risk, auto-apply L1 patches or surface L2 chips",
  "steps": [
    {
      "id": "collect-friction",
      "type": "agent",
      "instruction": "You are the friction collector. Gather all unprocessed improvement proposals from the ledger.\n\n1. Read all files in .kiln/ledger/proposals/ where risk is not yet decided (no risk field or risk=null).\n2. Also read the latest retro from .kiln/runs/ (sort by ts, take most recent retro.md).\n3. Consolidate into a unified proposal list. Deduplicate by target file + similar instruction.\n4. Write .wheel/outputs/friction-consolidated.json: {proposals: [{id, target, instruction, source_run_id, tags}]}",
      "output": ".wheel/outputs/friction-consolidated.json"
    },
    {
      "id": "classify-risk",
      "type": "agent",
      "instruction": "You are the risk classifier. Classify each proposal as low or high risk.\n\n## Read\n.wheel/outputs/friction-consolidated.json\n\n## Classification\n- LOW: single-file SKILL.md or template edit, no hook/gate change, local blast_radius\n- HIGH: hook change, cross-plugin contract, gate logic, or uncertain blast_radius\n\nFor each proposal, update .kiln/ledger/proposals/<id>.json with risk field.\nEmit JSON: {\"low\":[{id,target,instruction}], \"high\":[{id,target,instruction}]}",
      "context_from": ["collect-friction"],
      "output": ".wheel/outputs/classified-risk.json"
    },
    {
      "id": "apply-l1-patches",
      "type": "agent",
      "instruction": "You are the L1 auto-applier. Apply low-risk proposals that target config files only.\n\n## Read\n.wheel/outputs/classified-risk.json — use the `low` array only.\n\n## L1 targets (config files only, never SKILL.md or scripts)\n- .kiln/config.json\n- .kiln/test-strategy.json\n- .kiln/standards.md\n\n## For each low-risk proposal targeting an L1 file:\n1. Read the current file\n2. Apply the instruction as a minimal edit\n3. Write back\n4. Commit with message: `config(kiln): auto-apply L1 improvement [<proposal-id>]`\n5. Record in .wheel/outputs/l1-applied.json: {applied:[{id,target,diff}]}\n\n## Proposals targeting SKILL.md, scripts, hooks, or workflows are NOT L1 — skip them here.",
      "context_from": ["classify-risk"],
      "output": ".wheel/outputs/l1-applied.json"
    },
    {
      "id": "surface-l2-chips",
      "type": "command",
      "command": "HIGH=$(cat .wheel/outputs/classified-risk.json 2>/dev/null | jq -r '.high // [] | length'); echo \"$HIGH high-risk proposals to surface as chips\"; cat .wheel/outputs/classified-risk.json | jq -r '.high[]? | \"  - [\\(.id)] \\(.target): \\(.instruction[0:80])\"' 2>/dev/null; echo '{\"chips_surfaced\":'$HIGH'}'",
      "output": ".wheel/outputs/l2-chips.json"
    },
    {
      "id": "write-summary",
      "type": "command",
      "command": "L1=$(cat .wheel/outputs/l1-applied.json 2>/dev/null | jq -r '.applied | length' 2>/dev/null || echo 0); L2=$(cat .wheel/outputs/l2-chips.json 2>/dev/null | jq -r '.chips_surfaced' 2>/dev/null || echo 0); echo \"Self-improve complete: $L1 L1 patches applied, $L2 L2 chips surfaced.\"; echo '{\"l1_applied\":'$L1',\"l2_chips\":'$L2'}' > .wheel/outputs/self-improve-summary.json",
      "output": ".wheel/outputs/self-improve-summary.json"
    },
    {
      "id": "sync-to-obsidian",
      "type": "agent",
      "instruction": "You are the Obsidian sync agent. Mirror all new and updated local ledger entries to Obsidian.\n\n1. Read all .kiln/ledger/*.json files where ts > last sync (or all if no prior sync record).\n2. For each entry: call mcp__obsidian-projects__create_note or update_note in the mistakes/ledger vault path.\n3. Call shelf-sync to reconcile the full vault.\n4. Write .wheel/outputs/obsidian-sync.json: {synced: N, skipped: 0, note: ''}\n\nIf any MCP call fails, write {synced: 0, skipped: N, note: 'Obsidian unavailable — entries remain in local ledger for next sync'} and exit cleanly.",
      "on_failure": "skip",
      "output": ".wheel/outputs/obsidian-sync.json"
    }
  ]
}
```

### Modified Skills

**`kiln-pi-apply`** — becomes a wrapper for `wheel-run kiln:kiln-self-improve`. The current manual "surface proposals" behavior is replaced by the workflow's automatic L1/L2 split.

**`kiln-improve`** — new skill; alias for `kiln-pi-apply` with the new workflow. Name change to reflect broader scope (not just PI, but all improvement proposals).

---

## Phase 4 — New Hooks + Gates

**Goal:** The coverage gate, test-traceability gate, and merge-bar standard are enforced automatically, not by convention.

### New Hooks (plugin-kiln/hooks/)

#### `coverage-gate.sh`
Fires on PostToolUse(Bash) when the `test` command runs. Reads `.kiln/test-strategy.json` for `coverage_gate`. Fails if coverage < gate, printing the gap.

```bash
#!/usr/bin/env bash
# Coverage gate — blocks proceed if test coverage below threshold
GATE=$(cat .kiln/test-strategy.json 2>/dev/null | jq -r '.coverage_gate // 80')
RESULT=$(cat .wheel/outputs/test-results.json 2>/dev/null | jq -r '.coverage // 100')
if (( $(echo "$RESULT < $GATE" | bc -l) )); then
  echo "COVERAGE GATE FAIL: ${RESULT}% < ${GATE}% required" >&2
  exit 1
fi
```

#### `untraced-test-gate.sh`
Fires on PreToolUse(Edit|Write) when editing `src/`. Scans recently written test files for FR references. Blocks if a test file has no `// FR-` comment.

#### `merge-bar.sh`
Fires on PreToolUse(Bash) when `gh pr create` is called. Checks:
1. Audit compliance >= 80% (reads `.wheel/outputs/audit-verdict.json`)
2. All tasks marked `[X]` in tasks.md
3. No open blockers in `specs/<slug>/blockers.md` marked `severity: blocking`

### hooks.json changes (plugin-kiln/hooks/hooks.json)

Add entries for all three new hooks alongside the existing four.

---

## Phase 5 — Observability + Vision Layer

**Goal:** Build runs are inspectable in real-time. UI projects are gated by design/code fidelity.

### Extended Skills

**`wheel-view`** — extend the existing static workflow inspector to stream from `.kiln/runs/<id>/journal` when a run is in progress. Shows live step completions, agent verdicts, and friction notes. No new skill name — enhanced in-place.

### New Mechanisms

#### `vision-verify`
Part of the `smoke-review` agent step. When `.kiln/test-strategy.json` has `design_verify: true`:
1. Take a screenshot of the running app's target route
2. Render the canonical `design/features/<slug>/` HTML mockup in a headless browser
3. Use Claude vision to compare — output `{route, match: pass|fail|warn, diff_notes}`
4. Fail the smoke step if match = fail

#### `vision-filter` (in `kiln-distill`)
Before routing a capture to the PRD, check it against `vision.md` non-goals and constraints. Accept if aligned; decline if contradicted (emit to `.kiln/issues/declined/` with reason).

#### `vision-drift-check` (in `audit` agent)
Add a check: does the implemented code diverge from `ARCHITECTURE.md` or `vision.md`? If yes, emit a finding with `kind: drift`.

---

### Trim Integration — Design-First Mode

When a user works design-first (Penpot → code rather than code → Penpot), the loop changes shape: feedback arrives in the form of design file updates, not just text captures. The `design_first` config key wires trim into the capture → distill cycle.

**Config flag:**

```json
"design_first": false
```

Set to `true` in `kiln-init` wizard step 5b. When enabled, `kiln-distill` automatically pulls the latest design artifacts before drafting PRDs.

**How it connects:**

| Trigger | Action | Step |
|---|---|---|
| `kiln-distill` invoked (design_first=true) | `sync-designs` step calls `trim-pull` to fetch latest Penpot tokens + component specs | step 2 of kiln-distill.json, `on_failure: "skip"` |
| `kiln-feedback` records a feedback note tagged `#design` | Background sub-agent checks `design_first`; if true, also calls `trim-pull` to capture any corresponding Penpot update | feedback capture hook |
| User adds feedback and design_first=true | Feedback entry prompts: "Do you have a Penpot update for this? (y/N)" — if yes, `trim-pull` runs inline | kiln-feedback wizard flow |

**`sync-designs` step in `kiln-distill.json`:**

```json
{
  "id": "sync-designs",
  "type": "command",
  "command": "DESIGN_FIRST=$(jq -r '.design_first // false' .kiln/config.json 2>/dev/null); if [ \"$DESIGN_FIRST\" = 'true' ]; then echo 'design_first mode: pulling latest Penpot designs...'; claude --print --model haiku 'Run /trim:trim-pull. Report: {synced: true|false, files_updated: N, error?: string}'; echo '{\"design_sync\": true}'; else echo '{\"design_sync\": false, \"reason\": \"design_first disabled\"}'; fi",
  "on_failure": "skip",
  "output": ".wheel/outputs/design-sync-result.json"
}
```

`on_failure: "skip"` means: if Penpot is unreachable or trim-pull errors, distill continues — design sync is advisory, not blocking.

**kiln-feedback integration (when design_first=true):**

The `kiln-feedback` skill gains a post-capture prompt: after writing the feedback file, if `design_first: true` and the feedback is tagged `#design` (or the user explicitly says design is changing), ask:

> "Do you have an updated Penpot design for this? If yes, trim-pull will run now to capture it."

If the user answers yes, the feedback skill runs `wheel-run trim:trim-pull` inline before sync. This keeps design tokens co-located in time with the feedback capture that motivated them.

---

## Complete Skills Registry

All 69 skills across 5 plugins. Status: **keep** = no changes needed · **change** = modifications required · **remove** = deprecated/replaced · **new** = doesn't exist yet.

### plugin-kiln (40 skills)

| Skill | Mode | Status | Reason |
|---|---|---|---|
| `audit` | pipeline | change | Becomes a parallel team step (prd-auditor + spec-enforcer + quality-judge); skill wraps the team dispatch |
| `implement` | pipeline | change | Becomes a team step in kiln-build-prd.json; parallel implementers per user story + spec-enforcer + qa-engineer |
| `kiln-analyze` | manual | keep | Standalone codebase analysis; unchanged |
| `kiln-analyze-issues` | manual | keep | Issue triage and deduplication; unchanged |
| `kiln-build-prd` | manual | change | Thin wrapper around `wheel-run kiln:kiln-build-prd`; gains `--resume` flag that reads run manifest cursor and restarts from last completed step |
| `kiln-checklist` | manual | remove | Superseded by specify's 6-gate quality loop; no pipeline reference; never auto-called |
| `kiln-clarify` | manual | keep | Pre-spec clarification pass for ambiguous requirements; unchanged |
| `kiln-claude-audit` | manual | remove | No pipeline reference; never referenced by any agent; no evidence of active use |
| `kiln-cleanup` | manual | keep | Housekeeping: remove stale specs, orphaned tasks; unchanged |
| `kiln-constitution` | manual | keep | Read/write project constitution; unchanged |
| `kiln-coverage` | manual | change | Read coverage gate from `.kiln/test-strategy.json` instead of hardcoded threshold |
| `kiln-create-prd` | manual | keep | Creates new PRDs from scratch; unchanged |
| `kiln-distill` | manual | change | Promoted to kiln-distill.json wheel workflow (read-captures → **sync-designs** → vision-filter → group-and-draft → mark-processed → trigger-build); sync-designs step invokes `trim-pull` when `design_first: true` in config.json; skill becomes thin wrapper |
| `kiln-doctor` | manual | change | Reads `doctor-manifest.json` (version-keyed required/optional checks); diagnostic table output; `--clean-worktrees` flag; new checks auto-added via manifest entries |
| `kiln-escalation-audit` | manual | remove | Zero references in build-prd or agents; unclear purpose; confirmed unused |
| `kiln-feedback` | manual | change | Capture strategic feedback to .kiln/feedback/; classify AI-failure feedback → auto-call kiln-mistake for those entries |
| `kiln-fix` | pipeline | change | Promoted to kiln-fix.json wheel workflow (diagnose → fix → verify → ledger → summary); auto-invoked by kiln-build-prd post-audit (blocking findings) and kiln-next (auto_build + failing tests); skill becomes thin wrapper |
| `kiln-hygiene` | manual | change | Add lint checks for new template files and config schema validity |
| `kiln-init` | manual | change | Idempotent: full 6-step wizard on first run; re-run detects existing `config_version` and asks only about new keys introduced since last init |
| `kiln-improve` | manual | **new** | Wrapper for kiln-self-improve.json workflow; replaces kiln-pi-apply with broader L1/L2 improvement loop |
| `kiln-ledger` | manual | **new** | Read-only view of .kiln/ledger/; filter by --kind, --tag, --last N; no writes |
| `kiln-merge-pr` | pipeline | keep | Merge PR and flip roadmap item state; unchanged |
| `kiln-mistake` | pipeline | change | Auto-triggered from kiln-report-issue (AI-class issues), kiln-feedback (AI-failure entries), and retrospective (end of build); also manually invokable; writes to .kiln/ledger/ + .kiln/mistakes/; enforce three-axis tagging |
| `kiln-next` | manual | change | Human-only session-start command; evaluates 8-level priority stack (pending review → interrupted run → failing tests → issues large batch → issues small batch → feedback/roadmap ready to distill → PRD unstarted → all clear); `issue_batch_threshold` gates issue track; `distill_threshold` gates feedback/roadmap track; always one clear recommended action |
| `kiln-pi-apply` | manual | **remove** | Replaced by kiln-improve which wraps kiln-self-improve.json and handles both L1 config patches and L2 skill chips |
| `kiln-qa-audit` | manual | keep | Post-build QA compliance audit; unchanged |
| `kiln-qa-checkpoint` | pipeline | keep | Mid-build QA checkpoint feedback; unchanged |
| `kiln-qa-final` | pipeline | keep | Final QA pass before PR; unchanged |
| `kiln-qa-pass` | manual | keep | QA live pass with Playwright; unchanged |
| `kiln-qa-pipeline` | pipeline | keep | Orchestrate full QA pipeline (setup → checkpoint → final → pass); unchanged |
| `kiln-qa-setup` | pipeline | keep | Scaffold QA environment, checklist, .env.test; unchanged |
| `kiln-report-issue` | manual | change | Fix issue numbering race condition; auto-route AI-class issues to kiln-mistake; increment shared shelf counter |
| `kiln-research` | manual | keep | Standalone research pass outside of build pipeline; unchanged |
| `kiln-reset-prd` | manual | keep | Reset PRD state to re-run a phase; unchanged |
| `kiln-resume` | manual | remove | Explicitly deprecated; kiln-next's SKILL.md says it replaces kiln-resume as session-start command |
| `kiln-roadmap` | manual | change | Add --vision flag for vision.md strategic edits that bypass roadmap type system |
| `kiln-taskstoissues` | manual | keep | Convert tasks.md items to GitHub issues; unchanged |
| `kiln-test` | manual | change | Read test command and coverage gate from .kiln/test-strategy.json instead of hardcoded defaults |
| `kiln-todo` | manual | keep | Track TODO/FIXME annotations in codebase; unchanged |
| `kiln-ux-evaluate` | manual | keep | UX evaluation using ux-rubric.md 10-dimension scoring; unchanged |
| `kiln-version` | manual | keep | Version bump and sync to package.json; unchanged |
| `plan` | pipeline | change | Inject .kiln/standards.md via compose-context.sh --standards; add research-first Phase 1.5 agent routing (synthesizer/judge) |
| `specify` | pipeline | change | Read precedent block from .wheel/outputs/precedent-block.md; run spec quality checklist loop before exiting |
| `tasks` | pipeline | keep | Task generation from spec + plan; user story organization unchanged |

### plugin-clay (6 skills)

| Skill | Mode | Status | Reason |
|---|---|---|---|
| `clay-create-repo` | manual | change | After repo scaffold + initial commit, run vision interview → write `.kiln/vision.md`; then prompt "Set up kiln now?" → if yes, delegate to `kiln-init` (which skips vision step since it already exists) |
| `clay-idea` | manual | keep | Idea seeding and products/ directory scaffold; unchanged |
| `clay-idea-research` | manual | keep | Classify and research candidate ideas; unchanged |
| `clay-list` | manual | keep | List all products in products/; unchanged |
| `clay-new-product` | manual | keep | Generate PRD and about.md from idea; unchanged |
| `clay-project-naming` | manual | keep | Generate name candidates (npm, domain, GitHub availability checks); unchanged |

### plugin-shelf (8 skills)

| Skill | Mode | Status | Reason |
|---|---|---|---|
| `shelf-create` | manual | keep | Create new Obsidian notes; unchanged |
| `shelf-feedback` | manual | keep | Mirror feedback entries to Obsidian; unchanged |
| `shelf-propose-manifest-improvement` | manual | keep | Propose manifest improvements from Obsidian vault; unchanged |
| `shelf-release` | manual | keep | Mirror release notes to Obsidian; unchanged |
| `shelf-repair` | manual | keep | Repair broken sync manifest; unchanged |
| `shelf-status` | manual | keep | Show sync status and pending items; unchanged |
| `shelf-sync` | manual | change | Add ledger-mirror step: sync .kiln/ledger/ entries and smoke-reports to Obsidian alongside issues/PRDs/progress |
| `shelf-update` | manual | keep | Update existing Obsidian notes; unchanged |

### plugin-trim (10 skills)

| Skill | Mode | Status | Reason |
|---|---|---|---|
| `trim-design` | manual | keep | Generate HTML mockups from vision + user flows; unchanged |
| `trim-diff` | manual | keep | Diff design vs current code; unchanged |
| `trim-edit` | manual | keep | Edit design in Penpot; unchanged |
| `trim-flows` | manual | keep | Generate user flow diagrams; unchanged |
| `trim-init` | manual | keep | Initialize trim in a project; unchanged |
| `trim-library` | manual | keep | Sync component library; unchanged |
| `trim-pull` | manual | keep | Pull latest design from Penpot source; unchanged |
| `trim-push` | manual | keep | Push design changes to Penpot; unchanged |
| `trim-redesign` | manual | keep | Trigger a full redesign pass; unchanged |
| `trim-verify` | manual | keep | Verify design/code fidelity; feeds vision-verify in smoke step |

### plugin-wheel (9 skills)

| Skill | Mode | Status | Reason |
|---|---|---|---|
| `wheel-create` | manual | keep | Create a new workflow JSON; unchanged |
| `wheel-init` | manual | keep | Initialize wheel in a project; unchanged |
| `wheel-list` | manual | keep | List all workflows and their status; unchanged |
| `wheel-run` | manual | keep | Run a workflow by name; unchanged |
| `wheel-skip` | manual | keep | Skip current step and advance; unchanged |
| `wheel-status` | manual | keep | Show current workflow run state; unchanged |
| `wheel-stop` | manual | keep | Stop a running workflow; unchanged |
| `wheel-test` | manual | keep | Run workflow test fixtures; unchanged |
| `wheel-view` | manual | change | Extend static inspector to stream live from .kiln/runs/\<id\>/journal; add pre/post hook visibility in output |

---

## Full Skills Change Table

### New Skills

| Skill | Plugin | Description |
|---|---|---|
| `kiln-ledger` | kiln | Read-only view of the precedent ledger; filter by kind/tag/date |
| `kiln-improve` | kiln | Wrapper for `kiln-self-improve` workflow; replaces `kiln-pi-apply` |

### Renamed / Replaced Skills

| Old | New | Reason |
|---|---|---|
| `kiln-pi-apply` | `kiln-improve` | Broader scope: all improvement proposals, not just PI |

### Modified Skills (behavior changes)

| Skill | Change |
|---|---|
| `kiln-next` | Read `.kiln/config.json`; detect resumable runs; surface distill signal when N captures pending |
| `kiln-build-prd` | Delegates to `kiln-build-prd.json` wheel workflow; standards + precedent injected automatically |
| `kiln-distill` | Add vision-filter step; emit signal to `kiln-next` when complete |
| `kiln-init` | Scaffold `.kiln/standards.md`, `.kiln/config.json`, `.kiln/test-strategy.json` |
| `clay-create-repo` | Same scaffolding additions as `kiln-init` |
| `kiln-roadmap` | Add `--vision` flag for strategic vision.md edits |
| `shelf-sync` | Extend `compute-work-list.sh` to include `.kiln/ledger/` entries; mirror ledger to Obsidian |

### Unchanged Skills (no modification needed)

kiln-mistake, kiln-report-issue, kiln-feedback, kiln-fix, kiln-qa-*, specify, plan, tasks, implement, audit, kiln-merge-pr, kiln-resume, kiln-analyze, kiln-doctor, kiln-hygiene, kiln-version, all shelf-* skills, all trim-* skills, all clay-* skills, all wheel-* skills

---

## Full Agents Change Table

### New Agents

| Agent | Plugin | Model | Description |
|---|---|---|---|
| `precedent-reader.md` | kiln | haiku | Semantic query over Obsidian mistakes; emits precedent block; `on_failure: skip` |
| `risk-classifier.md` | kiln | sonnet | Classifies improvement proposals as low/high risk |
| `build-summary.md` | kiln | haiku | Final step of every workflow — renders 5-table build summary; `on: always` |
| ~~`parallel-critic.md`~~ | — | — | Removed — redundant given precedent injection + spec-enforcer + audit. Future idea: live pattern-watcher with pause-escalation once precedent corpus is large enough. |

### Modified Agents

| Agent | Change |
|---|---|
| `smoke-tester.md` | Reads `.kiln/test-strategy.json` for start/ready/probe commands; adds vision-verify path |
| `prd-auditor.md` | Emits structured JSON verdict; adds vision-drift-check; reads run-manifest |
| `continuance.md` | Reads `.kiln/config.json` for review_mode on session resume |

---

## Full Workflows Change Table

### New Workflows

| Workflow | Plugin | Steps |
|---|---|---|
| `kiln-build-prd.json` | kiln | 26 steps — full pipeline with config gating, precedent, standards, run-manifest, dispatch, checkpoint agents, audit-synthesize, fix-blocking |
| `kiln-self-improve.json` | kiln | 5 steps — friction collect → classify → L1 apply → L2 chip → mirror |
| `kiln-precedent.json` | kiln | 2 steps — context extract → Obsidian search → precedent block |
| `kiln-mistake-record.json` | kiln | 3 steps — write local + ledger → sync Obsidian (skip) → summary; called by retro, report-issue, feedback |
| `kiln-distill.json` | kiln | 7 steps — read captures → sync-designs (skip if design_first=false) → vision-filter (skip) → group-and-draft → mark-processed → trigger-build → invoke-build (skip if auto_build=false) |

### Modified Workflows

| Workflow | Change |
|---|---|
| `shelf-sync.json` | Add `ledger-mirror` step: sync `.kiln/ledger/` entries to Obsidian |
| `kiln-report-issue.json` | Background sub-agent gains a `classify-issue` step (haiku): reads issue content, determines if AI-class mistake (hallucination, wrong assumption, incorrect output) vs user-reported bug/friction. If AI-class → calls `wheel-run kiln:kiln-mistake-record`. If not → local write + shelf-sync. Counter increments regardless of class. |

---

## New Config File Schemas

### `.kiln/standards.md`
Markdown. Scaffolded by `kiln-init`/`clay-create-repo`. Path referenced in `.kiln/config.json`.

### `.kiln/config.json`
```json
{
  "config_version": "1.0.0",
  "review_mode": "standard",
  "review_checkpoints": ["post-spec", "pre-pr"],
  "auto_build": false,
  "auto_pr": false,
  "auto_merge": false,
  "pi_apply_threshold": "none",
  "issue_batch_threshold": 5,
  "distill_threshold": 3,
  "standards": ".kiln/standards.md",
  "design_first": false,
  "branching": {
    "style": "github-flow",
    "per_feature": true
  },
  "models": {
    "validator": "claude-haiku-4-5-20251001",
    "researcher": "claude-sonnet-4-6",
    "implementer": "claude-sonnet-4-6",
    "auditor": "claude-sonnet-4-6",
    "oracle": "claude-sonnet-4-6"
  }
}
```

### `.kiln/test-strategy.json`
Machine config only — no scenarios, no probe scripts. The smoke-review agent derives what to test from PRD + spec context.

```json
{
  "project_type": "web-app",
  "install": "npm ci",
  "build": "npm run build",
  "test": "vitest run",
  "coverage_gate": 80,
  "smoke": {
    "start": "npm run dev",
    "port": 3000,
    "ready_url": "http://localhost:3000",
    "ready_timeout_seconds": 30,
    "credentials": ".kiln/qa/.env.test",
    "teardown": "kill"
  },
  "design_verify": false
}
```

### `.kiln/ledger/<id>.json`
```json
{
  "id": "YYYY-MM-DD-<slug>",
  "kind": "mistake | fix | retro | friction",
  "summary": "one-line",
  "detail": "full prose",
  "blast_radius": "local | cross-plugin | cross-project",
  "tags": ["mistake/assumption", "topic/hooks", "language/typescript"],
  "source_path": ".kiln/mistakes/YYYY-MM-DD-<slug>.md",
  "ts": "ISO-8601"
}
```

### `.kiln/runs/<id>/manifest.json`
```json
{
  "run_id": "uuid",
  "prd": "docs/features/<slug>/PRD.md",
  "phase": "specify | plan | tasks | implement | audit | pr | done",
  "branch": "build/<slug>-YYYYMMDD",
  "pr": "https://github.com/.../pull/N",
  "decisions": [],
  "escalations": [],
  "cursor": "last-completed-step-id"
}
```

---

## Workflow Pre/Post Hooks

Every wheel workflow JSON may declare a `hooks` block with `pre` and `post` command steps. These run outside the step graph — before any steps start (pre) and after the last step completes (post). Command-only; no agent steps in hooks.

### Schema

```json
{
  "name": "kiln-build-prd",
  "version": "1.0.0",
  "hooks": {
    "pre": {
      "command": "curl -s -X POST \"$WEBHOOK_URL\" -d \"{\\\"event\\\":\\\"workflow.start\\\",\\\"workflow\\\":\\\"$WHEEL_WORKFLOW_NAME\\\",\\\"run_id\\\":\\\"$WHEEL_RUN_ID\\\"}\" -H 'Content-Type: application/json' || true",
      "env_required": ["WEBHOOK_URL"]
    },
    "post": {
      "command": "bash \"${WORKFLOW_PLUGIN_DIR}/scripts/push-obs-snapshot.sh\" \"$WHEEL_RUN_ID\" \"$WHEEL_STATUS\"",
      "on": "always",
      "env_required": ["OBS_ENDPOINT"]
    }
  },
  "steps": [...]
}
```

### Fields

| Field | Required | Default | Description |
|---|---|---|---|
| `hooks.pre.command` | yes (if pre block exists) | — | Shell command to run before step 1 |
| `hooks.post.command` | yes (if post block exists) | — | Shell command to run after last step |
| `hooks.post.on` | no | `always` | `always` · `success` · `failure` — when to fire the post hook |
| `hooks.pre.env_required` | no | `[]` | If any listed env var is unset, skip hook with a warning (no abort) |
| `hooks.post.env_required` | no | `[]` | Same — hook self-skips gracefully when destination not configured |

### Wheel-exported variables available in hook commands

| Variable | Set at | Value |
|---|---|---|
| `$WHEEL_RUN_ID` | both pre and post | UUID for this workflow run |
| `$WHEEL_WORKFLOW_NAME` | both | e.g. `kiln-build-prd` |
| `$WHEEL_WORKFLOW_VERSION` | both | e.g. `1.0.0` |
| `$WHEEL_STATUS` | post only | `pass` · `fail` · `warn` |
| `$WHEEL_STEP_COUNT` | post only | Number of steps that executed |
| `$WHEEL_STEPS_PASSED` | post only | Number of steps that exited 0 |
| `$WHEEL_OUTPUTS_DIR` | both | `.wheel/outputs/` |
| `$WORKFLOW_PLUGIN_DIR` | both | Absolute path to plugin dir |

Pre-hooks that fail (non-zero exit) emit a warning but do NOT abort the workflow. Post-hooks that fail are logged but do not change the workflow exit status. Use `|| true` defensively when the destination may be unavailable.

### Example hook commands

```bash
# Push a Slack notification on completion
curl -s -X POST "$SLACK_WEBHOOK_URL" \
  -H 'Content-Type: application/json' \
  -d "{\"text\":\"*${WHEEL_WORKFLOW_NAME}* finished: ${WHEEL_STATUS} (${WHEEL_STEPS_PASSED}/${WHEEL_STEP_COUNT} steps)\"}" || true

# Write an observability snapshot to a local endpoint
curl -s -X POST "http://localhost:9000/events" \
  -d "run_id=${WHEEL_RUN_ID}&workflow=${WHEEL_WORKFLOW_NAME}&status=${WHEEL_STATUS}" || true

# Append a timestamped line to a shared build log
echo "$(date -u +%FT%TZ) | ${WHEEL_WORKFLOW_NAME} | ${WHEEL_RUN_ID} | ${WHEEL_STATUS}" \
  >> "${HOME}/.kiln/build-log.tsv"

# Push outputs snapshot to Obsidian via MCP script
bash "${WORKFLOW_PLUGIN_DIR}/scripts/push-obs-snapshot.sh" \
  "${WHEEL_RUN_ID}" "${WHEEL_STATUS}" "${WHEEL_OUTPUTS_DIR}" || true
```

### Wheel runtime changes required

- Parse `hooks.pre` and `hooks.post` blocks from workflow JSON on load
- Check `env_required` before running each hook; skip with `WARN: hook skipped — $VAR unset` if any var missing
- Run pre-hook in a clean subshell with wheel-exported variables in env
- Run post-hook after final step, after `WHEEL_STATUS` is resolved
- Both hooks share the same `$WORKFLOW_PLUGIN_DIR` templating used by agent steps
- Add `hooks` to the `workflow-format.md` template reference

---

## MCP Tool Additions

### Obsidian MCP — `search_vault`
```
search_vault(query: string, limit?: number = 20)
→ [{ path: string, title: string, frontmatter: object, excerpt: string }]
```

Exposes Obsidian's native search syntax (`tag:X AND tag:Y path:mistakes/`). Used by `precedent-reader` agent.

**Future (Phase 1+):** `semantic_search(text: string, k: number)` backed by Turso sqlite-vec.

---

## Build Order (Dependency Graph)

```
Phase 0: standards.md + config.json + init scaffolding
    ↓
Phase 1: ledger schema + precedent-reader + search_vault MCP
    ↓
Phase 2: kiln-build-prd.json workflow (depends on Phase 0+1 for injection)
    ↓
Phase 3: kiln-self-improve.json workflow (depends on Phase 2 for retro output)
    ↓
Phase 4: coverage + untraced-test + merge-bar hooks (depends on Phase 2 for test-strategy)
    ↓
Phase 5: cockpit + vision-verify (depends on Phase 2 for run-manifest + journal)
```

Phases 4 and 5 can proceed in parallel after Phase 3.

---

## Open Questions

1. ~~**`parallel-critic` authority**~~ — removed. Future idea: live pattern-watcher mid-implement with pause-escalation once precedent corpus is large enough to make matching meaningful.
2. **Issue numbering collision** — kiln-report-issue has a race condition on numbering. Needs a fix before Phase 0 ships (quick win).
3. **Shared capture counter** — shelf counter should increment on all 4 capture surfaces, not just report-issue. Fix in Phase 0 alongside counter-related changes.
4. **`kiln-next` distill signal** — surface "N captures ready to distill" when count exceeds threshold (e.g., 5). Implement in Phase 0 as part of kiln-next changes.
5. **L2 chip UI** — high-risk proposals currently have no UX for one-click apply. Depends on Claude Code task chip API.

---

## Speckit Pipeline

The **speckit** is the specify → plan → tasks → contracts unit. It runs before any `src/` edit; hooks enforce this. The pipeline has three distinct sub-phases inside `plan` that the master plan should track.

### Overview

```
/kiln:kiln-distill → PRD.md
        ↓
/specify  →  specs/<slug>/spec.md
              (quality-validation loop: checklist → iterative fix)
        ↓
/plan
  Phase 0: research (research-runner agent → research.md)
  Phase 1: design + contracts (plan.md + contracts/interfaces.md)
  Phase 1.5: research-first routing (synthesizer/judge agents)
        ↓
/tasks   →  specs/<slug>/tasks.md
        ↓
HOOKS GATE (spec+plan+tasks+contracts all present)
        ↓
/implement
```

### Specify — Quality Validation Loop

The `specify` skill does not exit on the first pass. After writing `spec.md` it runs a **spec quality checklist** that scores the spec against criteria. If any item fails, the skill runs an iterative fix loop — rewriting the offending sections — until all checks pass or the loop limit is reached.

**Checklist items (enforced before spec.md is committed):**
- Every FR is testable (not vague, contains MUST or MUST NOT)
- Every user story has ≥1 acceptance scenario with Given/When/Then
- No FR has unresolved `[NEEDS CLARIFICATION]` unless explicitly marked `open_question`
- Every user story has an `Independent Test` description
- Edge cases section is non-empty
- At least one `SC-NNN` success criterion exists

### Plan — Three Sub-Phases

**Phase 0: Research**
Spawns `research-runner` agent to investigate the technical approach. Writes `specs/<slug>/research.md`. Covers: existing solutions, comparable implementations, potential pitfalls, stack fit. SKIPPED if `research.md` already exists (resumable).

**Phase 1: Design + Contracts**
Writes:
- `specs/<slug>/plan.md` — technical approach, phases, file list
- `specs/<slug>/contracts/interfaces.md` — every exported function signature (name, params, return type, sync/async, which FR). Single source of truth for all implementers.
- `specs/<slug>/data-model.md` (when feature involves entities)
- `specs/<slug>/quickstart.md` (when feature is a library or CLI)

**Phase 1.5: Research-First Agent Routing**
When running in research-first mode (new API surface, unknown third-party), `plan` spawns:
- `research-runner` (synthesizer) — generates N candidate approaches
- `output-quality-judge` — scores each approach, selects winner

The winning approach becomes the basis for Phase 1 design. Non-winners are archived in `research.md`.

### Interface Contracts as Anchor

`contracts/interfaces.md` is the single source of truth for the entire build.
- All function names MUST comply with `standards.md` naming rules
- All signatures MUST match exactly in `src/` — hooks block divergence
- If a signature must change during implementation, update `contracts/interfaces.md` FIRST and commit
- Every function in contracts must reference its originating FR

### Tasks — User Story Organization

Tasks are grouped by user story (US1, US2, US3) so each story is independently deliverable. Every task carries:
- `[P]` tag if it can run in parallel (different files, no dependencies)
- `[USN]` tag linking it to a user story
- Exact file paths

The tasks format requires a **Foundational phase** (Phase 2 of tasks) that blocks ALL user story phases — it contains shared infrastructure (DB schema, auth framework, base models) that every story depends on.

---

## Templates Registry

### Existing Templates (plugin-kiln/templates/)

| File | Purpose | Used by |
|---|---|---|
| `spec-template.md` | Spec scaffold: user stories, FRs, success criteria, assumptions | `/specify` |
| `plan-template.md` | Plan scaffold: summary, tech context, structure, complexity tracking | `/plan` |
| `tasks-template.md` | Task list scaffold organized by user story + phases | `/tasks` |
| `interfaces-template.md` | Interface contracts scaffold: function signatures with FR refs | `/plan` Phase 1 |
| `constitution-template.md` | Project constitution: principles, governance, design reference | `/kiln-init` |
| `vision-template.md` | Product vision: what / not / winning / constraints — apex context doc | `/clay-create-repo`, `/kiln-roadmap --vision` |
| `issue.md` | Issue/bug/friction report with frontmatter: type, severity, category, status | `/kiln-report-issue` |
| `checklist-template.md` | QA checklist scaffold for qa-engineer agent | `/kiln-qa-setup` |
| `ux-rubric.md` | 10-dimension UX scoring rubric (Tier A/B/C, weighted formula) | `ux-evaluator` agent |
| `agent-file-template.md` | New agent file scaffold: frontmatter, role, tools, output format | Manual / `/kiln-hygiene` |
| `workflow-format.md` | Wheel workflow JSON format reference | Manual |
| `kiln-manifest.json` | Plugin manifest scaffold | `/kiln-init` |
| `roadmap-template.md` | Roadmap document scaffold | `/kiln-roadmap` |
| `roadmap-item-template.md` | Single roadmap item frontmatter + body | `/kiln-roadmap` |
| `roadmap-phase-template.md` | Phase document scaffold | `/kiln-roadmap` |
| `roadmap-critique-template.md` | Roadmap critique / retro item | `/kiln-roadmap` |

### New Scaffold Files (plugin-kiln/scaffold/)

Read from the plugin install path — NOT copied to consumer projects.

| File | Purpose | Read by |
|---|---|---|
| `config-schema.json` | Version-keyed config key declarations; maps each key to the version that introduced it | `kiln-init` (idempotent re-run diff) |
| `doctor-manifest.json` | Version-keyed required/optional health check declarations | `kiln-doctor` |

### New Templates (to add in Phase 0–1)

#### `standards-template.md` (new — Phase 0)
Scaffolded into `.kiln/standards.md` on `kiln-init`/`clay-create-repo`. Path referenced by `config.json standards` key.

```markdown
## Coding Standards

### Naming
- names are pronounceable and searchable — no abbreviations, no encodings
- one word per concept (fetch not retrieve/get/pull mixed across the codebase)
- functions named as verbs, booleans as predicates (isActive, hasPermission)
- classes/modules named as nouns describing what they ARE, not what they DO

### Functions
- do one thing at one level of abstraction
- <= 20 lines, <= 2 parameters — extract an object or split if more are needed
- no flag arguments — split into two named functions instead
- no side effects — a function that says it reads should only read

### Comments
- do not comment WHAT the code does — rename or restructure instead
- only write a comment to explain WHY: a hidden constraint, a non-obvious invariant

### Error handling
- throw exceptions, never return null or error codes from internal functions
- never pass null — guard at system boundaries, trust contracts internally
- fail loudly at boundaries (user input, external APIs), fail silently nowhere

### Structure
- single responsibility — one reason to change per module
- tell don't ask — don't reach into an object's state to make decisions for it
- no circular dependencies across layers

### Tests
- one concept per test, assertion names describe the failure
- every test references its spec FR in a comment
- no stubs on integration paths
```

#### `config-template.json` (new — Phase 0)
Scaffolded into `.kiln/config.json` on `kiln-init`/`clay-create-repo`.

```json
{
  "review_mode": "standard",
  "review_checkpoints": ["post-spec", "pre-pr"],
  "auto_build": false,
  "auto_pr": false,
  "auto_merge": false,
  "pi_apply_threshold": "none",
  "issue_batch_threshold": 5,
  "distill_threshold": 3,
  "standards": ".kiln/standards.md"
}
```

#### `test-strategy-template.json` (new — Phase 0)
Scaffolded into `.kiln/test-strategy.json` on `kiln-init`.

`test-strategy.json` is **machine config only** — it tells the agent how to start, wait for, and stop the app. It does NOT specify what to test. The smoke-review agent derives its own test plan from the PRD, spec, and design context.

```json
{
  "project_type": "web-app",
  "install": "npm ci",
  "build": "npm run build",
  "test": "vitest run",
  "coverage_gate": 80,
  "smoke": {
    "start": "npm run dev",
    "port": 3000,
    "ready_url": "http://localhost:3000",
    "ready_timeout_seconds": 30,
    "credentials": ".kiln/qa/.env.test",
    "teardown": "kill"
  },
  "design_verify": false
}
```

What the smoke-review agent does with this:
1. Reads the PRD, spec FRs, and `contracts/interfaces.md` to understand what was built
2. If `design_verify: true`, reads `design/features/<slug>/` mockups
3. Starts the app with `smoke.start`, polls `smoke.ready_url` (every 2s, up to `ready_timeout_seconds`)
4. Derives its own test plan — one scenario per FR that has a visible user-facing surface
5. Executes scenarios using browser tools (Playwright / Chrome MCP)
6. Writes `specs/<slug>/smoke-report.md` — the generated test plan + results (see template below)
7. Emits JSON verdict: `{agent, verdict:pass|fail|warn, scenarios_run, scenarios_passed, fidelity_score}`
8. Tears down app

The model learns what to smoke test by accumulating past smoke reports in Obsidian. The `precedent-reader` can surface "here's how we smoke-tested a similar feature" for context.

#### `ledger-entry-template.json` (new — Phase 1)
Template for `.kiln/ledger/<id>.json` entries. Written by `collect-retro` agent and `kiln-mistake` skill.

```json
{
  "id": "YYYY-MM-DD-<slug>",
  "kind": "mistake",
  "summary": "<one-line description>",
  "detail": "<full prose — what happened, root cause, how to avoid>",
  "blast_radius": "local",
  "tags": ["mistake/assumption", "topic/hooks", "language/typescript"],
  "source_path": ".kiln/mistakes/YYYY-MM-DD-<slug>.md",
  "ts": "ISO-8601"
}
```

Three-axis tagging convention:
- `mistake/<class>` — e.g. `mistake/assumption`, `mistake/race-condition`, `mistake/scope-creep`
- `topic/<area>` — e.g. `topic/hooks`, `topic/wheel`, `topic/shelf`, `topic/contracts`
- `language/<lang>` or `framework/<fw>` — e.g. `language/typescript`, `framework/vitest`

#### `run-manifest-template.json` (new — Phase 1)
Template for `.kiln/runs/<id>/manifest.json`. Written at `init-run-manifest` step in `kiln-build-prd.json`.

```json
{
  "run_id": "<uuid>",
  "prd": "docs/features/<slug>/PRD.md",
  "phase": "specify",
  "branch": "build/<slug>-YYYYMMDD",
  "pr": null,
  "decisions": [],
  "escalations": [],
  "cursor": "init-run-manifest"
}
```

#### `retro-template.md` (new — Phase 2)
Template for `.kiln/runs/<id>/retro.md`. Written by `collect-retro` agent.

```markdown
---
run_id: <uuid>
prd: docs/features/<slug>/PRD.md
date: YYYY-MM-DD
compliance_pct: <N>
---

## What went well

- <item>

## What slowed us down

- <item>

## Improvement proposals

### Proposal 1 — <title>
- **Target**: <file or area>
- **Instruction**: <concrete actionable change>
- **Risk guess**: low | high
- **Blast radius**: local | cross-plugin
```

#### `smoke-report-template.md` (new — Phase 2)
Written by `smoke-review` agent to `specs/<slug>/smoke-report.md` after each run. This is the traceability artifact — it documents what was tested and why, generated from the agent's understanding of the spec rather than a pre-written recipe.

```markdown
---
run_id: <uuid>
prd: docs/features/<slug>/PRD.md
date: YYYY-MM-DD
verdict: pass | fail | warn
scenarios_run: <N>
scenarios_passed: <N>
fidelity_score: null | 0-10
---

## Test Context

<!-- Agent's reasoning for what it chose to test and why -->
Tested against: PRD `docs/features/<slug>/PRD.md`, spec FRs: FR-001, FR-002, FR-003
Design verify: false

## Scenarios

### SC-001 — <derived from FR-001>
- **Route**: /
- **Auth**: not required
- **Actions**: <prose description of what the agent did>
- **Assertions**: <prose description of what the agent checked>
- **Result**: pass | fail | warn
- **Notes**: <any unexpected behavior>

### SC-002 — <derived from FR-002>
...

## Design Fidelity (if design_verify: true)

| Route | Reference mockup | Match | Notes |
|---|---|---|---|
| / | design/features/slug/home.html | pass | Minor color delta on CTA button |

## Summary

<One paragraph: what was tested, what passed, what failed, anything surprising>
```

Smoke reports are mirrored to Obsidian via `shelf-sync` alongside issues and PRDs. The `precedent-reader` can surface relevant past smoke reports ("here's how we smoke-tested a similar feature") for new runs.

#### `precedent-block-template.md` (new — Phase 1)
Standard format emitted by `precedent-reader` agent into `.wheel/outputs/precedent-block.md`.

```markdown
## Precedent — past mistakes relevant to this feature

> These are real mistakes made in prior builds. Read before specifying or implementing.

- **[severity]** `[mistake_class]` — [assumption that was wrong]
  ✓ Correction: [what to do instead]
  _(source: [project-slug], [date])_
```

If no relevant mistakes found, the agent writes:

```markdown
## Precedent

_No relevant past mistakes found for this feature._
```

