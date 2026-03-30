---
name: build-prd
description: Run the complete speckit pipeline using an agent team. Reads the PRD to determine team structure, then orchestrates specify → plan → tasks → implement → audit → PR.
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: custom
---

# Speckit Run — Full Pipeline via Agent Team

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user input is the feature description.

## Pre-Flight

1. **Verify agent teams are available (NON-NEGOTIABLE).**
   Before anything else, check that `TeamCreate` is available as a tool. If it is NOT available, **STOP immediately** and tell the user:
   > "Agent teams are not enabled. `/build-prd` requires Claude Code agent teams to orchestrate the pipeline.
   >
   > To enable them, add this to your Claude Code settings or launch with the flag:
   > ```
   > claude --enable-agent-teams
   > ```
   > Or add `"enableAgentTeams": true` to `.claude/settings.json`.
   >
   > Then restart Claude Code and run `/build-prd` again."

   Do NOT proceed with any other pre-flight steps if teams are unavailable. Do NOT attempt to run the pipeline in single-agent mode.

2. If no user input was provided, ask the user for a feature description.
3. **Locate the PRD** — check for a PRD in this order:
   - If user input matches a feature slug: read `docs/features/*-<slug>/PRD.md`
   - If `docs/features/` contains exactly one feature PRD folder: read that feature PRD
   - Otherwise: read `docs/PRD.md` (the product-level PRD)
   - If none found, tell the user to run `/create-prd` first.
   Extract the feature scope, functional requirements, deliverables, and any named external dependencies.
   For feature PRDs, also read `docs/PRD.md` for inherited product context (tech stack, users, constraints).
4. Read `.specify/memory/constitution.md` — note any constraints that affect team structure.
5. Create a fresh git branch from main.
6. **PRD freeze**: The PRD is frozen the moment you read it. Do NOT ask the user for confirmation — just proceed. Log a one-line message: "PRD frozen — starting pipeline." If the user needs to change requirements mid-run, they can trigger a scope-change pause (see Step 4 in Monitor and Steer).

## Step 1: Analyze the PRD and Design the Team

### Required Roles (in order)

The pipeline always flows through these roles. This is the minimum — you MUST have at least one teammate per role:

1. **Specifier** — Runs `/speckit.specify`, then `/speckit.plan`, then `/speckit.tasks` **in a single uninterrupted pass**. All three commands MUST execute back-to-back without stopping. The specifier MUST NOT go idle between commands. Produces all spec artifacts and commits them. Always runs first.
2. **Researcher** — Resolves external dependencies referenced in the PRD. Clones starters to `vendor/`, documents findings in `research.md`. Runs after specifier if the PRD names external projects; skip this role if there are no external deps. **PRD naming authority**: The researcher MUST NOT rename, substitute, or "improve" directory names, file names, or identifiers that the PRD explicitly specifies. If the PRD says `apps/electron`, the researcher documents `apps/electron` — not `apps/desktop`, not `apps/electron-app`, not any "technology-agnostic" alternative. The PRD is the naming authority. If the researcher believes a PRD name is wrong, they must flag it to the team lead for resolution rather than silently substituting a different name.
3. **Implementer** — Runs `/speckit.implement`. Executes the task plan phase-by-phase, writes code matching contracts, marks tasks `[X]`, commits per phase. Runs after specifier (and researcher if present).
4. **Auditor** — Runs after all implementers finish. Each auditor gets a **fresh context** (no implementation history polluting their judgment). Split auditors by concern so they can run in parallel:
   - **audit-compliance**: Runs `/speckit.audit` — PRD→Spec→Code→Test verification
   - **audit-tests**: Verifies test quality — no stubs, real assertions, coverage gate
   - **audit-smoke**: Builds and runs the project in a temp dir, verifies runtime behavior
   - **audit-pr**: Creates the PR with stats from all other auditors

   For simple features, one auditor can do all of these. For complex features, split them so each auditor starts with a clean context and a focused lens.
5. **Retrospective** — Messages all teammates for feedback, creates a GitHub issue with findings. Runs last, before shutdown.

### Scaling Up

Based on what you read in the PRD, decide where to add parallelism:

- **Multiple independent components?** (e.g., CLI + templates + module system) → Spawn multiple implementers, one per component, working on different files in parallel. They all depend on the specifier finishing but can run concurrently with each other.
- **Large module count?** (e.g., 5 installable modules) → Spawn one implementer per module, each owning its own files.
- **Complex external deps?** → Spawn a dedicated researcher alongside the specifier so research can start as soon as the plan is done.
- **Multiple audit concerns?** (compliance, test quality, runtime) → Spawn multiple auditors with different focus areas running in parallel. Each auditor gets a fresh context — no implementation history — so their judgment isn't biased by what they saw being built.

### Decision Checklist

Ask yourself:
1. How many independent file sets can be implemented in parallel? → That many implementers.
2. Are there external deps to fetch? → Add a researcher.
3. Is a single audit pass sufficient? → If not, split auditors by concern.
4. What's the total teammate count? → Keep it under 8. More teammates = more coordination overhead.

### Implementer Sizing Rule

**After tasks.md is generated**, check the task count per implementer. If any single implementer would own more than 20 tasks, split them into multiple implementers by component or phase. A single implementer doing 50+ tasks will take too long, delaying the auditor and causing the pipeline to bottleneck.

Example: If tasks.md has 73 tasks split across CLI (20), templates (27), and modules (16), spawn 3 implementers — not 1 or 2. The "keep under 6" guidance applies to non-implementer roles; add implementers as needed to keep each one under ~20 tasks.

### Example Team Structures

**Simple feature** (single module, no external deps):
```
specifier → implementer → auditor → retrospective
```
3 teammates, fully serial.

**Medium feature** (CLI + templates, one external dep):
```
specifier → researcher ─┐
                         ├→ impl-cli ──┐→ audit-code ──┐
                         └→ impl-tmpl ─┘→ audit-tests ─┤→ retrospective
```
5 teammates, 2 implementers in parallel, 2 auditors in parallel.

**Complex feature** (CLI + 3 modules + external starter):
```
specifier → researcher ─┐
                         ├→ impl-core ──┐→ audit-compliance ─┐
                         ├→ impl-mod-a ─┤→ audit-tests ──────┤→ retrospective
                         └→ impl-mod-b ─┘→ audit-smoke ──────┘
```
7 teammates, 3 implementers in parallel, 3 auditors in parallel.

Each teammate should run the speckit commands (`/speckit.specify`, `/speckit.plan`, `/speckit.tasks`, `/speckit.implement`, `/speckit.audit`) — not reimplement their logic. Implementers running in parallel should each get a filtered view of tasks.md (only their component's tasks).

## Step 2: Create the Team and Tasks

1. Use `TeamCreate` with a descriptive name (e.g., `speckit-{feature}`)
2. Use `TaskCreate` to create ALL tasks. You MUST create every task listed in the **Mandatory Tasks** section below, plus any additional tasks from your PRD analysis.
3. Set task dependencies using `TaskCreate` or `TaskUpdate` (see dependency rules below)
4. Assign tasks to teammates by setting `owner` via `TaskUpdate`

### Mandatory Tasks (NON-NEGOTIABLE — always create these)

Every pipeline run MUST include these tasks regardless of feature complexity. Do NOT skip any of them:

| # | Task | Owner | Depends On | Why Mandatory |
|---|------|-------|------------|---------------|
| 1 | Specify + plan + research + tasks | specifier | — | Produces all spec artifacts |
| N | Implementation (1+ tasks) | implementer(s) | specifier | Builds the feature |
| A | Audit + smoke test + create PR | auditor | all implementers | Quality gate + deliverable |
| R | **Retrospective** | **retrospective** | **ALL other tasks (audit + every implementer + specifier + researcher)** | **Self-improvement — feeds back into the skill and template. ALWAYS the last task before shutdown. MUST NOT start until every other task is completed or explicitly cancelled.** |

The retrospective task exists to make every pipeline run improve the next one. Skipping it means repeating the same friction forever.

### Additional Tasks (PRD-dependent)

Based on your PRD analysis, you may add:
- Multiple implementation tasks (one per independent component) for parallelism
- A separate researcher task if external deps need resolving
- Multiple audit tasks split by concern (compliance, tests, smoke) for parallelism

### Task Granularity Rule

**Each implementer MUST have exactly one task that represents ALL of their work.** The implementer MUST NOT mark this task as `completed` until every phase and every sub-task in `tasks.md` that they own is finished and committed. The auditor depends on these task completions, so premature completion signals cause the auditor to run against incomplete code.

Include this in every implementer's prompt:

```
Do NOT mark your task as `completed` via TaskUpdate until ALL of the following are true:
- Every task assigned to you in tasks.md is marked [X]
- Every phase you own has been committed
- You have no remaining uncommitted work

Your task completion is the signal that triggers the auditor. If you mark it done early, the auditor will audit incomplete code and produce invalid findings.
```

### Task Dependencies

Wire dependencies following these rules:
- All implementation tasks depend on the specifier task
- Researcher task (if present) depends on the specifier task
- Implementer tasks depend on the researcher task (if present)
- Audit tasks depend on ALL implementation tasks
- **Retrospective depends on EVERY other task** — list all task IDs (specifier, researcher, every implementer, auditor) as `addBlockedBy` dependencies when creating the retrospective task via `TaskCreate`. Do NOT depend on only the auditor — that leaves a race condition where implementers may still be running.

### Task Dependency Example

```
Task 1: Specify (no deps)                         → owner: specifier
Task 2: Research (depends: 1)                     → owner: researcher
Task 3: Impl CLI (depends: 2)                     → owner: impl-cli
Task 4: Impl templates (depends: 2)               → owner: impl-templates
Task 5: Audit + smoke + PR (depends: 3, 4)        → owner: auditor
Task 6: Retrospective (depends: 1, 2, 3, 4, 5)   → owner: retrospective  ← depends on ALL tasks
```

The system automatically unblocks dependent tasks when their dependencies complete. The retrospective will not unblock until every single dependency is marked `completed`.

### Pre-Spawn Checklist

Before spawning any teammates, verify:
- [ ] Specifier task exists
- [ ] At least one implementation task exists
- [ ] Audit task exists
- [ ] **Retrospective task exists** ← if this is missing, add it now
- [ ] All dependencies are wired correctly
- [ ] Every task has an owner assigned

## Step 3: Spawn Teammates

Spawn teammates using the `Agent` tool with:
- `team_name` set to the team name from Step 2
- `name` set to a descriptive name (e.g., `specifier`, `impl-core`, `auditor`)
- `run_in_background: true`
- `mode: "bypassPermissions"`

Each teammate's prompt should include:
- The working directory and branch name
- Which tasks they own (by task ID or description)
- Instructions to run the appropriate speckit commands for their tasks
- The feature description from user input
- Instructions to use `TaskUpdate` to mark tasks in-progress when starting and completed when done
- Instructions to use `SendMessage` to notify dependent teammates when unblocked
- Instructions to check `TaskList` after completing each task to find the next available work
- Instructions to read `~/.claude/teams/{team-name}/config.json` to discover other teammates by name

### Specifier Prompt — Chaining Requirement (NON-NEGOTIABLE)

The specifier's prompt MUST include these exact instructions to prevent stalling between commands:

```
You MUST run all three speckit commands in a single uninterrupted pass:
1. Run `/speckit.specify` with the feature description
2. IMMEDIATELY after specify completes, run `/speckit.plan` — do NOT stop, do NOT wait, do NOT go idle
3. IMMEDIATELY after plan completes, run `/speckit.tasks` — do NOT stop, do NOT wait, do NOT go idle
4. ONLY after all three are done: commit all artifacts, mark your task completed, and notify downstream teammates

Each slash command will report "completion" and suggest next steps — IGNORE those suggestions and proceed to the next command in this list. Your task is NOT complete until spec.md, plan.md, contracts/interfaces.md, and tasks.md all exist and are committed.
```

**Why this is needed**: Each `/speckit.*` skill ends by reporting completion and suggesting the next command. Without explicit chaining instructions, the specifier agent treats each skill completion as a stopping point and goes idle, requiring a manual nudge from the team lead to continue. This caused a ~10 minute stall in the 015 pipeline run.

### Researcher Prompt — PRD Naming Authority (NON-NEGOTIABLE)

The researcher's prompt MUST include these exact instructions:

```
When documenting findings in research.md:
- If the PRD explicitly names a directory, file, package, or identifier, you MUST use that exact name. Do NOT substitute a "better", "cleaner", or "technology-agnostic" name.
- Example: If the PRD says `apps/electron`, document `apps/electron` — not `apps/desktop`.
- If you believe a PRD name is incorrect or problematic, flag it to the team lead with your reasoning. Do NOT silently rename it in your research output.
- Verify every directory name, package name, and file path in your research.md against the PRD before committing. Any mismatch is a bug.
```

**Why this is needed**: In the 015 pipeline, the researcher substituted `apps/desktop` for the PRD's `apps/electron`, documenting it as "technology-agnostic naming." This cascaded into spec artifacts and module definitions, requiring two fixup commits (`b142ba9`, `a8b35cc`) and manual mid-pipeline renaming across all affected files.

### Auditor Prompt — Implementation Completeness Check (NON-NEGOTIABLE)

The auditor's prompt MUST include these exact instructions:

```
Before starting your audit, verify that ALL implementation is truly complete:
1. Run `TaskList` and check that every implementer task has status `completed` — not `in_progress`, not `pending`
2. Read `tasks.md` and verify that every task assigned to implementers is marked `[X]`
3. If ANY implementer task is still in progress or unchecked, do NOT begin auditing. Instead:
   - Message the team lead: "Audit blocked — implementer task {id} is not yet complete."
   - Wait for the team lead to confirm all implementation is done before proceeding.

Do NOT audit a partially-complete implementation. Your audit findings are only valid against the final state of the code.
```

**Why this is needed**: In the 015 pipeline, the auditor started at 20:05 and documented blockers (missing v2 template, missing Zero/Drizzle/Auth), but the implementer committed those exact fixes at 20:06 and 20:12. The auditor was working against incomplete implementation because it began as soon as its task dependency resolved — but the implementer had marked its coarse-grained task as "completed" before finishing all phases of work.

### Auditor Prompt — Blocker Reconciliation Before PR (NON-NEGOTIABLE)

The auditor's prompt MUST also include:

```
Before creating the PR, reconcile blockers.md against the current code state:
1. Re-read every blocker in blockers.md
2. For each blocker, check if the code has been updated since it was documented:
   - Run `git log --oneline` and check for commits that may have addressed the blocker
   - Read the affected files to verify current state
3. If a blocker has been resolved by a later commit, update its status to "RESOLVED" with the commit hash
4. Update the compliance summary table to reflect the actual final state
5. Commit the updated blockers.md before creating the PR

The PR must reflect the FINAL state of the code, not a point-in-time snapshot from mid-implementation.
```

**Why this is needed**: In the 015 pipeline, blockers.md cited B-001 (missing v2 template), B-002 (missing Zero/Drizzle/Auth), and B-003 (only 2 UI components) as critical gaps with 65% compliance. But the implementer fixed all three in later commits. The blockers.md was never updated, so the PR would have shipped with a stale 65% compliance figure when the actual number was higher.

### Key Rules for All Teammates

Include these in every teammate prompt:
- Read `.specify/memory/constitution.md` before any code changes
- Run the speckit slash commands — don't reimplement their logic
- Mark tasks via `TaskUpdate` (in_progress → completed)
- After completing a task, check `TaskList` for the next unblocked, unassigned task
- Message the next teammate by **name** when their work is unblocked
- No two teammates should edit the same file — each owns specific file sets
- Every exported function MUST match `specs/<feature>/contracts/interfaces.md` exactly
- Mark tasks `[X]` in tasks.md IMMEDIATELY after completing each one
- Commit after each phase, not in one big batch
- Coverage gate: >=80%
- **Scope-change protocol**: If you receive a message containing "SCOPE CHANGE" from the team lead, finish your current task, commit your work, and STOP. Do not start any new tasks until you receive a "RESUME" message. After resuming, re-read `tasks.md` and `contracts/interfaces.md` before starting your next task — they may have changed.

### Teammate Idle Behavior

Teammates go idle after every turn — this is normal. An idle teammate can still receive messages. If a teammate sends a message and then goes idle, that's the expected flow (they sent their message and are waiting for a response). Do NOT treat idle as an error or shutdown.

## Step 4: Monitor and Steer

After spawning, you are the **team lead**. Your job is coordination, not implementation.

1. **Messages arrive automatically** — no need to poll. When teammates send messages, they appear as new conversation turns.
2. **Do NOT implement tasks yourself** — wait for teammates to complete their work.
3. If a teammate reports a blocked task that should be unblocked, nudge the blocking teammate or update the task status.
4. If a teammate is stuck on an error, investigate and provide guidance via `SendMessage`.
5. If a teammate stops early (tasks remain incomplete), spawn a replacement to continue.
6. Track progress via `TaskList` — check periodically to see what's done and what's blocked.

### Handling Teammate Communication

- Use `SendMessage` with the teammate's **name** (not agentId) to communicate.
- Peer DM visibility: when teammates message each other, a brief summary appears in their idle notification. This is informational — you don't need to respond.
- Use broadcast sparingly — token costs scale with team size.

### Handling Scope Changes Mid-Pipeline

If the user changes scope, updates the PRD, or asks to modify requirements while implementers are already running:

1. **Immediately broadcast a PAUSE to all implementers**: Send each implementer a message: "SCOPE CHANGE — stop current work after finishing your current task. Do NOT start any new tasks. Commit what you have and wait for further instructions."
2. **Wait for all implementers to acknowledge** the pause. Check `TaskList` — no implementer should have tasks in `in_progress` state after acknowledging. If an implementer doesn't respond, send the pause message again.
3. **Update spec artifacts**: Have the specifier (or yourself) update `spec.md`, `plan.md`, `contracts/interfaces.md`, and `tasks.md` to reflect the new scope. Commit the updated artifacts.
4. **Notify implementers of what changed**: Send each implementer a targeted message listing which tasks are added, removed, or modified. Reference the updated `tasks.md` and `contracts/interfaces.md`.
5. **Resume**: Send each implementer a message: "RESUME — scope change applied. Re-read tasks.md and contracts/interfaces.md before starting your next task."

**Why this matters**: Without an explicit pause, implementers work against stale spec artifacts. Their code won't match updated contracts, causing rework and audit failures. The pause-update-resume cycle ensures all agents work from the same source of truth.

## Step 5: Retrospective (NON-NEGOTIABLE — do NOT skip)

**STOP. Before sending ANY shutdown requests, the retrospective MUST run.**

The retrospective teammate was already spawned in Step 3 with the other teammates. It has been waiting (blocked on all other tasks). Once every task is completed and the retrospective task unblocks, the retrospective teammate should begin automatically. If it doesn't, nudge it via `SendMessage`.

### Safety-Net Gate (retrospective agent prompt MUST include this)

Before the retrospective agent starts any work, it MUST run `TaskList` and verify that **every non-retrospective task** has status `completed` or `cancelled`. If ANY task is still `pending` or `in_progress`:
1. Do NOT proceed with retrospective work
2. Send a message to the team lead: "Retrospective blocked — task {task_id} ({task_name}) is still {status}. Waiting."
3. Wait for the team lead to resolve the blocker (nudge the stuck agent, cancel the task, or mark it completed)
4. Re-check `TaskList` after receiving a follow-up message from the team lead

Include these instructions verbatim in the retrospective teammate's prompt when spawning it in Step 3.

The retrospective teammate's job:
1. **Run the safety-net gate above** — verify all tasks are done before proceeding
2. Messages every still-running teammate asking: "What friction did you hit? What would you change about the workflow, the speckit commands, or the team structure?"
3. Collects their responses
4. Reviews the pipeline artifacts for additional evidence:
   - `specs/{feature}/blockers.md` — documented blockers
   - `git log` — commit flow and any fixup commits that indicate rework
   - Test results — any failures, flaky tests, environment issues
   - Task list — tasks that were stuck, reassigned, or took unusually long
5. Creates a GitHub issue on the **ai-repo-template** repo with `gh issue create -R yoshisada/ai-repo-template` containing:
   - **What worked well** (with evidence)
   - **What didn't work well** (with evidence)
   - **Proposed changes** — concrete suggestions for the skill, speckit commands, team structure, or codebase
6. Reports the issue URL back to the lead
7. Marks its task as completed via `TaskUpdate`

**Only proceed to Step 6 after the retrospective task is marked completed.**

## Step 6: Report and Cleanup

1. **Verify retrospective ran**: Check `TaskList` — the retrospective task MUST be completed. If not, go back to Step 5.
2. **Shut down teammates gracefully**: Send each teammate `SendMessage` with `message: {type: "shutdown_request"}`. They can approve or reject — if rejected, check why before retrying.
3. **Wait for all teammates to shut down** before cleaning up.
4. **Clean up**: Use `TeamDelete` to remove the team and task directories.
5. **Summarize** the pipeline results:

```
## Pipeline Report: {feature branch name}

| Step | Status | Details |
|------|--------|---------|
| Specify | [Done/Failed] | {FR count, user story count} |
| Plan | [Done/Failed] | {artifact count} |
| Research | [Done/Skipped/Questions] | {deps resolved} |
| Tasks | [Done/Failed] | {phase count, task count} |
| Commit | [Done/Failed] | {commit hash} |
| Implementation | [Done/Failed] | {phases completed, tasks done} |
| Audit | [Pass/Fail] | {compliance %, test quality, smoke result} |
| PR | [Created/Failed] | {PR URL} |
| Retrospective | [Done/Failed] | {issue URL} |

**Branch**: {branch name}
**PR**: {URL}
**Tests**: {count} passing, {coverage}% coverage
**Compliance**: {percentage}
**Blockers**: {count} — see specs/{feature}/blockers.md
**Smoke Test**: {PASS/FAIL}
**Retrospective**: {issue URL}
```

## Error Handling

- If a teammate fails, check its last message and task status
- If `/speckit.implement` stops early, spawn a replacement to continue from where it left off
- Unfixable gaps go in `specs/{feature}/blockers.md` — pipeline continues
- Do NOT retry automatically — report to the user and ask how to proceed
- If TeamDelete fails because teammates are still active, shut them down first
