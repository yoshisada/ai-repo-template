---
name: speckit-run
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

## Time Tracking

**IMPORTANT**: Track wall-clock time for the pipeline and each teammate. This provides a rough proxy for resource usage when token counts are unavailable.

1. Record the pipeline start time (ISO 8601) before spawning any teammates.
2. When creating each task via `TaskCreate`, include `metadata: { "startedAt": "" }`.
3. Instruct each teammate to record their start time in task metadata via `TaskUpdate` with `metadata: { "startedAt": "<ISO timestamp>" }` when they begin work.
4. When a teammate completes their task, they should set `metadata: { "completedAt": "<ISO timestamp>" }`.
5. The retrospective and final report use these timestamps to calculate per-role and total durations.

## Pre-Flight

1. If no user input was provided, ask the user for a feature description.
2. Read `docs/PRD.md` — extract the feature scope, functional requirements, deliverables, and any named external dependencies.
3. Read `.specify/memory/constitution.md` — note any constraints that affect team structure.
4. Create a fresh git branch from main.
5. Record the pipeline start time: `pipeline_start = <current ISO 8601 timestamp>`.

## Step 1: Analyze the PRD and Design the Team

### Required Roles (in order)

The pipeline always flows through these roles. This is the minimum — you MUST have at least one teammate per role:

1. **Specifier** — Runs `/speckit.specify`, `/speckit.plan`, `/speckit.tasks`. Produces all spec artifacts and commits them. Always runs first.
2. **Researcher** — Resolves external dependencies referenced in the PRD. Clones starters to `vendor/`, documents findings in `research.md`. Runs after specifier if the PRD names external projects; skip this role if there are no external deps.
3. **Implementer** — Runs `/speckit.implement`. Executes the task plan phase-by-phase, writes code matching contracts, marks tasks `[X]`, commits per phase. Runs after specifier (and researcher if present).
4. **Auditor** — Runs after all implementers finish. Each auditor gets a **fresh context** (no implementation history polluting their judgment). Split auditors by concern so they can run in parallel:
   - **audit-compliance**: Runs `/speckit.audit` — PRD→Spec→Code→Test verification
   - **audit-tests**: Verifies test quality — no stubs, real assertions, coverage gate
   - **audit-smoke**: Builds and runs the project in a temp dir, verifies runtime behavior
   - **audit-pr**: Creates the PR with stats from all other auditors

   For simple features, one auditor can do all of these. For complex features, split them so each auditor starts with a clean context and a focused lens.
5. **Retrospective** — Messages all teammates for feedback and token usage, creates a GitHub issue with findings, and opens an improvement PR if warranted. Runs last, before shutdown.

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
4. What's the total teammate count? → Keep it under 6. More teammates = more coordination overhead. Aim for 5-6 tasks per teammate.

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
| R | **Retrospective** | **retrospective** | **auditor** | **Self-improvement — feeds back into the skill and template. ALWAYS the second-to-last task. MUST run BEFORE shutdown.** |

The retrospective task exists to make every pipeline run improve the next one. Skipping it means repeating the same friction forever.

### Additional Tasks (PRD-dependent)

Based on your PRD analysis, you may add:
- Multiple implementation tasks (one per independent component) for parallelism
- A separate researcher task if external deps need resolving
- Multiple audit tasks split by concern (compliance, tests, smoke) for parallelism

### Task Dependencies

Wire dependencies following these rules:
- All implementation tasks depend on the specifier task
- Researcher task (if present) depends on the specifier task
- Implementer tasks depend on the researcher task (if present)
- Audit tasks depend on ALL implementation tasks
- **Retrospective depends on audit** (it runs after the PR is created but BEFORE shutdown)

### Task Dependency Example

```
Task 1: Specify (no deps)                → owner: specifier
Task 2: Research (depends: 1)            → owner: researcher
Task 3: Impl CLI (depends: 2)            → owner: impl-cli
Task 4: Impl templates (depends: 2)      → owner: impl-templates
Task 5: Audit + smoke + PR (depends: 3, 4) → owner: auditor
Task 6: Retrospective (depends: 5)       → owner: retrospective  ← ALWAYS LAST
```

The system automatically unblocks dependent tasks when their dependencies complete.

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
- Instructions to use `TaskUpdate` to mark tasks in-progress when starting and completed when done, including `metadata: { "startedAt": "<ISO timestamp>" }` when starting and `metadata: { "completedAt": "<ISO timestamp>" }` when done
- Instructions to use `SendMessage` to notify dependent teammates when unblocked
- Instructions to check `TaskList` after completing each task to find the next available work
- Instructions to read `~/.claude/teams/{team-name}/config.json` to discover other teammates by name

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

## Step 5: Retrospective (NON-NEGOTIABLE — do NOT skip)

**STOP. Before sending ANY shutdown requests, the retrospective MUST run.**

The retrospective teammate was already spawned in Step 3 with the other teammates. It has been waiting (blocked on the audit task). Once the auditor completes and the retrospective task unblocks, the retrospective teammate should begin automatically. If it doesn't, nudge it via `SendMessage`.

The retrospective teammate's job:
1. Messages every still-running teammate asking: "What friction did you hit? What would you change about the workflow, the speckit commands, or the team structure? Also, please report your total token usage (input + output tokens)."
2. Collects their responses (feedback + token counts)
3. Reviews the pipeline artifacts for additional evidence:
   - `specs/{feature}/blockers.md` — documented blockers
   - `git log` — commit flow and any fixup commits that indicate rework
   - Test results — any failures, flaky tests, environment issues
   - Task list — tasks that were stuck, reassigned, or took unusually long
4. Collects timing data from task metadata (`startedAt`, `completedAt`) via `TaskGet` for each task, calculates per-role durations and total pipeline wall-clock time.
5. Creates a GitHub issue on the **ai-repo-template** repo with `gh issue create -R yoshisada/ai-repo-template` containing:
   - **What worked well** (with evidence)
   - **What didn't work well** (with evidence)
   - **Proposed changes** — concrete suggestions for the skill, speckit commands, team structure, or codebase
   - **Token usage** — per-teammate token counts (input + output) and pipeline total
   - **Timing breakdown** — per-role wall-clock durations and total pipeline time
6. If any proposed changes are **high-confidence fixes** (clear bugs, documented friction that hit multiple agents, or violations of the constitution), create a PR with exact diffs:
   - Clone the ai-repo-template repo (if not already present) and create a branch: `retro/{feature}-{date}`
   - Apply ONLY changes that are **absolutely required** — fixes for problems that caused real friction or failures during this run. Do NOT include speculative improvements or nice-to-haves.
   - Each changed file must have a clear justification tied to evidence from the retro (teammate feedback, blockers, fixup commits)
   - Open a PR with `gh pr create -R yoshisada/ai-repo-template` linking back to the retro issue
   - If no changes meet the high-confidence bar, skip the PR and note "No high-confidence fixes identified" in the issue
7. Reports the issue URL (and PR URL if created) back to the lead
8. Marks its task as completed via `TaskUpdate`

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
| Retrospective | [Done/Failed] | {issue URL}, {PR URL or "no fixes needed"} |

**Branch**: {branch name}
**PR**: {URL}
**Tests**: {count} passing, {coverage}% coverage
**Compliance**: {percentage}
**Blockers**: {count} — see specs/{feature}/blockers.md
**Smoke Test**: {PASS/FAIL}
**Retrospective**: {issue URL}
**Wall-Clock Time**: {total pipeline duration}
**Total Tokens**: {pipeline total tokens}

### Timing & Token Breakdown

| Role | Duration | Tokens (in/out) |
|------|----------|-----------------|
| Specifier | {duration} | {input}/{output} |
| Researcher | {duration or N/A} | {input}/{output} |
| Implementer(s) | {duration — longest if parallel} | {input}/{output} |
| Auditor | {duration} | {input}/{output} |
| Retrospective | {duration} | {input}/{output} |
| **Total Pipeline** | **{start to finish}** | **{total input}/{total output}** |
```

## Error Handling

- If a teammate fails, check its last message and task status
- If `/speckit.implement` stops early, spawn a replacement to continue from where it left off
- Unfixable gaps go in `specs/{feature}/blockers.md` — pipeline continues
- Do NOT retry automatically — report to the user and ask how to proceed
- If TeamDelete fails because teammates are still active, shut them down first
