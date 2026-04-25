---
name: kiln-build-prd
description: Run the complete kiln pipeline using an agent team. Reads the PRD to determine team structure, then orchestrates specify → plan → tasks → implement → audit → PR.
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: custom
---

# Kiln Run — Full Pipeline via Agent Team

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user input is the feature description.

## Pre-Flight

1. **Verify agent teams are available (NON-NEGOTIABLE).**
   Before anything else, check that `TeamCreate` is available as a tool. If it is NOT available, **STOP immediately** and tell the user:
   > "Agent teams are not enabled. `/kiln:kiln-build-prd` requires Claude Code agent teams to orchestrate the pipeline.
   >
   > To enable them, add this to your Claude Code settings or launch with the flag:
   > ```
   > claude --enable-agent-teams
   > ```
   > Or add `"enableAgentTeams": true` to `.claude/settings.json`.
   >
   > Then restart Claude Code and run `/kiln:kiln-build-prd` again."

   Do NOT proceed with any other pre-flight steps if teams are unavailable. Do NOT attempt to run the pipeline in single-agent mode.

2. If no user input was provided, ask the user for a feature description.
3. **Locate the PRD** — check for a PRD in this order:
   - If user input matches a feature slug: read `docs/features/*-<slug>/PRD.md`
   - If `docs/features/` contains exactly one feature PRD folder: read that feature PRD
   - Otherwise: read `docs/PRD.md` (the product-level PRD)
   - If none found, tell the user to run `/kiln:kiln-create-prd` first.
   Extract the feature scope, functional requirements, deliverables, and any named external dependencies.
   For feature PRDs, also read `docs/PRD.md` for inherited product context (tech stack, users, constraints).
4. Read `.specify/memory/constitution.md` — note any constraints that affect team structure.
5. **Handle working directory and create branch:**

   The user's local checkout is their working copy. The pipeline branches from **the current HEAD** — not from main.

   ```bash
   # Step A: Check for uncommitted changes
   if ! git diff --quiet || ! git diff --cached --quiet; then
     echo "You have uncommitted changes."
   fi
   # Also check untracked files
   git status --short
   ```

   **If there are uncommitted changes or staged files:**
   Commit them to the current branch first, then create the pipeline branch. Do NOT ask the user — just commit and proceed. These are typically the PRD and backlog files the pipeline needs.

   ```bash
   git add -A
   git commit -m "chore: commit working changes before pipeline branch"
   ```

   **If the working directory is clean:**
   Proceed directly to creating the branch.

   ```bash
   # Step B: Derive feature slug and create a fresh branch from current HEAD (FR-004)
   # The feature slug MUST be derived from the PRD directory name (2-4 words, lowercase, hyphenated).
   # Example: docs/features/2026-04-01-pipeline-workflow-polish/PRD.md → "pipeline-workflow-polish"
   # Strip the date prefix (YYYY-MM-DD-) from the PRD directory name to get the slug.
   PRD_DIR_NAME=$(basename "$(dirname "$PRD_PATH")")
   FEATURE_SLUG=$(echo "$PRD_DIR_NAME" | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//' | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
   BRANCH_NAME="build/${FEATURE_SLUG}-$(date +%Y%m%d)"
   git checkout -b "$BRANCH_NAME"
   ```

   The branch is created from wherever the user currently is — their current branch, current commit, current state. This preserves their working context. The pipeline's work happens on this new branch; the user's original branch is untouched.

   **Branch naming rule (FR-004)**: The branch MUST follow `build/<feature-slug>-<YYYYMMDD>` exactly. The feature slug is derived from the PRD directory name with date prefix stripped. Do NOT use arbitrary slugs — derive from the PRD path.

   **Spec directory naming rule (FR-005)**: The spec directory MUST be `specs/<feature-slug>/` where `<feature-slug>` matches the branch name's feature portion (the part between `build/` and the trailing `-YYYYMMDD`). No numeric prefixes. The specifier agent MUST use this exact directory name.

6. **PRD freeze**: The PRD is frozen the moment you read it. Do NOT ask the user for confirmation — just proceed. Log a one-line message: "PRD frozen — starting pipeline on branch `$BRANCH_NAME` from `$(git rev-parse --abbrev-ref HEAD@{-1})`." If the user needs to change requirements mid-run, they can trigger a scope-change pause (see Step 4 in Monitor and Steer).

## Step 1: Analyze the PRD and Design the Team

### Required Roles (in order)

The pipeline always flows through these roles. This is the minimum — you MUST have at least one teammate per role:

1. **Specifier** — Runs `/specify`, then `/plan`, then `/tasks` **in a single uninterrupted pass**. All three commands MUST execute back-to-back without stopping. The specifier MUST NOT go idle between commands. Produces all spec artifacts and commits them. Always runs first.
2. **Researcher** — Resolves external dependencies referenced in the PRD. Clones starters to `vendor/`, documents findings in `research.md`. Runs after specifier if the PRD names external projects; skip this role if there are no external deps. **PRD naming authority**: The researcher MUST NOT rename, substitute, or "improve" directory names, file names, or identifiers that the PRD explicitly specifies. If the PRD says `apps/electron`, the researcher documents `apps/electron` — not `apps/desktop`, not `apps/electron-app`, not any "technology-agnostic" alternative. The PRD is the naming authority. If the researcher believes a PRD name is wrong, they must flag it to the team lead for resolution rather than silently substituting a different name.
3. **Implementer** — Runs `/implement`. Executes the task plan phase-by-phase, writes code matching contracts, marks tasks `[X]`, commits per phase. Runs after specifier (and researcher if present).
4. **QA Engineer** — **(Web/frontend projects only)** Runs the `qa-engineer` agent. Unlike other auditors, the QA engineer is **long-lived** — it starts after the specifier finishes (so it knows what to test) and runs in parallel with implementers. It operates in two modes:
   - **Checkpoint mode** (during implementation): Each time an implementer completes a phase and notifies the QA engineer, it spins up the dev server, tests the newly completed flows with Playwright, records video of failures, and sends **actionable feedback directly to the responsible implementer** via `SendMessage`. The implementer fixes the issue and notifies QA for re-test. This creates a tight feedback loop that catches visual bugs while the implementer still has context.
   - **Final mode** (after all implementation): Runs `/kiln:kiln-qa-pipeline` which spins up a **4-agent QA team**:
     - **e2e-agent**: Runs Playwright E2E suite (headless, fast, deterministic)
     - **chrome-agent**: Uses /chrome with live data (real auth, real state). Skipped if /chrome unavailable.
     - **ux-agent**: 3-layer UX evaluation (axe-core + accessibility tree + visual)
     - **qa-reporter** (pipeline mode): Routes findings to implementers via SendMessage → waits for fixes → re-tests → files remaining issues with `qa-pass` + `build-prd` labels
     After `/kiln:kiln-qa-pipeline`, runs `/kiln:kiln-qa-final` as a quick green/red gate to confirm all E2E tests pass.
     The audit-pr agent includes the QA report summary and issue links in the PR body.

   The QA engineer tracks its checkpoint history in `.kiln/qa/checkpoints.md` so it doesn't re-test unchanged flows. It is a peer to implementers, not a gate after them.

   **QA snapshot guidance (FR-013)**: QA result snapshots and incremental test-result files MUST NOT be committed to the feature branch. They belong in `.kiln/qa/` which is gitignored. The QA engineer should write all artifacts (screenshots, videos, reports) to `.kiln/qa/` and never `git add` them.

   **Skip this role** for CLI-only, API-only, or non-visual projects.

5. **Auditor** — Runs after all implementers AND the QA engineer's final pass finish. Each auditor gets a **fresh context** (no implementation history polluting their judgment). Split auditors by concern so they can run in parallel:
   - **audit-compliance**: Runs `/audit` — PRD→Spec→Code→Test verification
   - **audit-tests**: Verifies test quality — no stubs, real assertions, coverage gate
   - **audit-smoke**: Builds and runs the project in a temp dir, verifies runtime behavior
   - **audit-pr**: Creates the PR with stats from all other auditors. If a QA engineer ran, includes QA video links and the `.kiln/qa/latest/QA-REPORT.md` summary in the PR body.

   For simple features, one auditor can do all of these. For complex features, split them so each auditor starts with a clean context and a focused lens.
6. **Retrospective** — Messages all teammates for feedback, creates a GitHub issue with findings. Runs last, before shutdown.

### Scaling Up

Based on what you read in the PRD, decide where to add parallelism:

- **Multiple independent components?** (e.g., CLI + templates + module system) → Spawn multiple implementers, one per component, working on different files in parallel. They all depend on the specifier finishing but can run concurrently with each other.
- **Large module count?** (e.g., 5 installable modules) → Spawn one implementer per module, each owning its own files.
- **Complex external deps?** → Spawn a dedicated researcher alongside the specifier so research can start as soon as the plan is done.
- **Web/frontend project?** → Spawn a `qa-engineer` that runs alongside implementers. It starts after the specifier (needs spec to know what to test) and runs checkpoint passes as implementers complete phases. Implementers message the QA engineer when a phase is done; QA tests it and sends feedback back. This is the only role that runs in parallel with implementers rather than after them.
- **Multiple audit concerns?** (compliance, test quality, runtime) → Spawn multiple auditors with different focus areas running in parallel. Each auditor gets a fresh context — no implementation history — so their judgment isn't biased by what they saw being built.

### Decision Checklist

Ask yourself:
1. How many independent file sets can be implemented in parallel? → That many implementers.
2. Are there external deps to fetch? → Add a researcher.
3. Does this feature have a visual/frontend component? → Add a `qa-engineer` running alongside implementers.
4. Is a single audit pass sufficient? → If not, split auditors by concern.
5. What's the total teammate count? → Keep it under 8. More teammates = more coordination overhead.

### Agent Friction Notes Requirement (FR-009)

**ALL pipeline agents** (specifier, researcher, implementers, QA engineer, auditors) MUST write a friction note to `specs/<feature>/agent-notes/<agent-name>.md` before completing their work and marking their task as done. This is a prerequisite for task completion — the retrospective agent reads these notes instead of polling live teammates.

Each agent's prompt already includes the friction notes section. When spawning agents, ensure the feature path is communicated so agents know where to write their notes. The `specs/<feature>/agent-notes/` directory should be created by the first agent that writes a note.

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

**Web frontend feature** (UI + API, visual QA with feedback loop):
```
specifier ─┐
           ├→ impl-ui ───┐
           ├→ impl-api ──┤→ qa-engineer (final) ─┐→ audit-pr ─┐
           └→ qa-engineer ┘  (checkpoints ↔ impls)└→ audit-compliance ─┤→ retrospective
```
6 teammates. `qa-engineer` starts after specifier, runs checkpoint passes during implementation (sends feedback to `impl-ui`/`impl-api`, receives "fix ready" notifications back). After all implementers finish, QA switches to final mode for the full video report. Auditors depend on both implementers AND QA final pass.

**Complex feature** (CLI + 3 modules + external starter):
```
specifier → researcher ─┐
                         ├→ impl-core ──┐→ audit-compliance ─┐
                         ├→ impl-mod-a ─┤→ audit-tests ──────┤→ retrospective
                         └→ impl-mod-b ─┘→ audit-smoke ──────┘
```
7 teammates, 3 implementers in parallel, 3 auditors in parallel.

Each teammate should run the kiln commands (`/specify`, `/plan`, `/tasks`, `/implement`, `/audit`) — not reimplement their logic. Implementers running in parallel should each get a filtered view of tasks.md (only their component's tasks).

## Step 1.5: Baseline Checkpoint (when PRD has quantitative SC or NFR thresholds)

If the PRD includes any SC OR NFR item with a literal number — `≥3 fewer X`, `X% faster`, `≤Nms`, `≥80% coverage`, `count drops by Y` — the team-lead MUST insert a baseline-capture step BEFORE the specifier finalizes spec.md/tasks.md. Skipping this step means the spec ships with thresholds that can't be re-derived from observed reality, which produces "+N% deviation in blockers.md" every time (see PR #166 SC-G-1 recalibration, PR #168 NFR-H-5 +5ms deviation).

**Procedure**:

1. Spawn `researcher-baseline` BEFORE the specifier finalizes spec.md.
2. Wait for researcher-baseline to write `research.md §baseline` with current-main numbers.
3. The specifier reads `research.md §baseline` and re-derives every quantitative SC/NFR threshold from the live measurement, NOT from the PRD literal.
4. If the live measurement makes a PRD threshold unreachable (e.g., baseline already at the target — PR #166 hit this when FR-E batching had collapsed the baseline to 1 before SC-G-1 was authored), the specifier rewrites the threshold into a compound gate that captures the spirit of the metric AND flags the calibration in spec.md `## Open Questions`.
5. If the live measurement makes a NFR perf budget unreachable on the implementation hardware (e.g., NFR-H-5 50ms target unreachable on macOS due to irreducible python3 fork), the specifier rewrites the threshold with a documented tolerance band BEFORE implementation starts. Do NOT "set the threshold and discover the tolerance after the fact" — that pattern produces blockers.md noise every pipeline.

**Hard pre-req**: implementers may not begin until the specifier has reconciled SC/NFR numbers against live baseline. The specifier task is NOT complete just because spec.md exists — it must explicitly note "thresholds reconciled against research.md §baseline" in its friction note.

**Why this is needed**: PRD literal "SC-G-1 ≥3 fewer Bash/Read tool calls" was unreachable in PR #166 because FR-E batching had already collapsed the baseline to 1. PRD literal "NFR-H-5 ≤50ms" was unreachable in PR #168 because of an irreducible python3 fork. Both cases produced mid-pipeline recalibration friction (specifier + researcher-baseline + audit-compliance friction notes; blockers.md R-1 in #166 + B-2 in #168). Issue #167 PI-3 + Issue #169 PI-3 captured this as the single most-recurring pipeline friction.

## Step 2: Create the Team and Tasks

1. Use `TeamCreate` with a descriptive name (e.g., `kiln-{feature}`)
2. Use `TaskCreate` to create ALL tasks. You MUST create every task listed in the **Mandatory Tasks** section below, plus any additional tasks from your PRD analysis.
3. Set task dependencies using `TaskCreate` or `TaskUpdate` (see dependency rules below)
4. Assign tasks to teammates by setting `owner` via `TaskUpdate`

### Mandatory Tasks (NON-NEGOTIABLE — always create these)

Every pipeline run MUST include these tasks regardless of feature complexity. Do NOT skip any of them:

| # | Task | Owner | Depends On | Why Mandatory |
|---|------|-------|------------|---------------|
| 1 | Specify + plan + research + tasks | specifier | — | Produces all spec artifacts |
| N | Implementation (1+ tasks) | implementer(s) | specifier | Builds the feature |
| Q | Visual QA (checkpoints + final) | qa-engineer | specifier | **(Web/frontend only)** Feedback loop during impl + final video report. Create this task if the PRD has any visual/frontend component. The QA engineer does NOT wait for implementers to finish — it runs alongside them. |
| A | Audit + smoke test + create PR | auditor | all implementers + qa-engineer (if present) | Quality gate + deliverable |
| R | **Retrospective** | **retrospective** | **ALL other tasks** | **Self-improvement — feeds back into the skill and template. ALWAYS the last task before shutdown. MUST NOT start until every other task is completed or explicitly cancelled.** |

The retrospective task exists to make every pipeline run improve the next one. Skipping it means repeating the same friction forever.

### Additional Tasks (PRD-dependent)

Based on your PRD analysis, you may add:
- Multiple implementation tasks (one per independent component) for parallelism
- A separate researcher task if external deps need resolving
- A `qa-engineer` task for web/frontend projects (runs alongside implementers, not after)
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
- **QA engineer task (if present) depends on the specifier task** — it starts alongside implementers, NOT after them. It needs the spec to know what to test but does NOT need implementation to be complete.
- Audit tasks depend on ALL implementation tasks AND the qa-engineer task (if present)
- **Retrospective depends on EVERY other task** — list all task IDs (specifier, researcher, every implementer, qa-engineer, auditor) as `addBlockedBy` dependencies when creating the retrospective task via `TaskCreate`. Do NOT depend on only the auditor — that leaves a race condition where implementers may still be running.

### Task Dependency Example (CLI project, no QA)

```
Task 1: Specify (no deps)                         → owner: specifier
Task 2: Research (depends: 1)                     → owner: researcher
Task 3: Impl CLI (depends: 2)                     → owner: impl-cli
Task 4: Impl templates (depends: 2)               → owner: impl-templates
Task 5: Audit + smoke + PR (depends: 3, 4)        → owner: auditor
Task 6: Retrospective (depends: 1, 2, 3, 4, 5)   → owner: retrospective  ← depends on ALL tasks
```

### Task Dependency Example (Web frontend project, with QA)

```
Task 1: Specify (no deps)                         → owner: specifier
Task 2: Impl UI (depends: 1)                      → owner: impl-ui
Task 3: Impl API (depends: 1)                     → owner: impl-api
Task 4: Visual QA (depends: 1)                    → owner: qa-engineer  ← starts with implementers, NOT after
Task 5: Audit + PR (depends: 2, 3, 4)             → owner: auditor      ← waits for impls AND QA final pass
Task 6: Retrospective (depends: 1, 2, 3, 4, 5)   → owner: retrospective
```

Note: Task 4 (QA) depends only on the specifier, so it unblocks at the same time as the implementers. The QA engineer runs checkpoint passes during implementation by communicating with implementers via `SendMessage`. It only marks its task as `completed` after its final pass (all flows tested, video exported). The auditor waits for this completion before starting.

The system automatically unblocks dependent tasks when their dependencies complete. The retrospective will not unblock until every single dependency is marked `completed`.

### Pre-Spawn Checklist

Before spawning any teammates, verify:
- [ ] Specifier task exists
- [ ] At least one implementation task exists
- [ ] QA engineer task exists (if web/frontend project)
- [ ] Audit task exists
- [ ] **Retrospective task exists** ← if this is missing, add it now
- [ ] All dependencies are wired correctly
- [ ] Every task has an owner assigned

## Step 3: Spawn Teammates

**Spawn all teammates EXCEPT the retrospective agent.** The retrospective is spawned later in Step 5 after all auditors complete. This keeps its context clean — an agent spawned at pipeline start accumulates idle notifications and peer DM summaries for the entire run, burning tokens on irrelevant context.

Spawn teammates using the `Agent` tool with:
- `team_name` set to the team name from Step 2
- `name` set to a descriptive name (e.g., `specifier`, `impl-core`, `auditor`)
- `run_in_background: true`
- `mode: "bypassPermissions"`

Each teammate's prompt should include:
- **Canonical paths (FR-006)**: "Working directory: <absolute-path>, Branch: <branch-name>, Spec directory: specs/<feature-slug>/". These MUST be included in every agent's prompt at spawn time so agents never need to guess or glob for paths.
- Which tasks they own (by task ID or description)
- Instructions to run the appropriate kiln commands for their tasks
- The feature description from user input
- Instructions to use `TaskUpdate` to mark tasks in-progress when starting and completed when done
- Instructions to use `SendMessage` to notify dependent teammates when unblocked
- Instructions to check `TaskList` after completing each task to find the next available work
- Instructions to read `~/.claude/teams/{team-name}/config.json` to discover other teammates by name

### Specifier Prompt — Chaining Requirement (NON-NEGOTIABLE)

The specifier's prompt MUST include these exact instructions to prevent stalling between commands:

```
SPEC DIRECTORY NAMING (FR-005): The spec directory MUST be specs/<feature-slug>/ where <feature-slug>
matches the branch name's feature portion (the part between "build/" and the trailing "-YYYYMMDD").
No numeric prefixes. For example, if the branch is build/pipeline-workflow-polish-20260401,
the spec directory MUST be specs/pipeline-workflow-polish/. Do NOT use any other naming scheme.

You MUST run all three kiln commands in a single uninterrupted pass:
1. Run `/specify` with the feature description
2. IMMEDIATELY after specify completes, run `/plan` — do NOT stop, do NOT wait, do NOT go idle
3. IMMEDIATELY after plan completes, run `/tasks` — do NOT stop, do NOT wait, do NOT go idle
4. ONLY after all three are done: commit all artifacts, mark your task completed, and notify downstream teammates

Each slash command will report "completion" and suggest next steps — IGNORE those suggestions and proceed to the next command in this list. Your task is NOT complete until spec.md, plan.md, contracts/interfaces.md, and tasks.md all exist and are committed.
```

**Why this is needed**: Each `/*` skill ends by reporting completion and suggesting the next command. Without explicit chaining instructions, the specifier agent treats each skill completion as a stopping point and goes idle, requiring a manual nudge from the team lead to continue. This caused a ~10 minute stall in the 015 pipeline run.

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

### QA Engineer Prompt — Feedback Loop Protocol (NON-NEGOTIABLE for web/frontend projects)

The QA engineer's prompt MUST include these exact instructions:

```
You are the QA engineer for this pipeline. You run the `qa-engineer` agent definition.

## SKILLS
- `/kiln:kiln-qa-setup` — Run FIRST. Installs Playwright, scaffolds .kiln/qa/, generates test matrix and test stubs.
- `/kiln:kiln-qa-checkpoint` — During implementation. Tests new flows, sends feedback to implementers.
- `/kiln:kiln-qa-pipeline` — After ALL implementers finish. 4-agent team (e2e + chrome + ux + reporter in pipeline mode). Reporter routes findings to implementers for fixing.
- `/kiln:kiln-qa-final` — Quick gate after /kiln:kiln-qa-pipeline. Just runs playwright tests and confirms green.

## WORKFLOW
1. On startup: Run `/kiln:kiln-qa-setup`
2. If `/kiln:kiln-qa-setup` reports credential-dependent flows, message the team lead:
   "QA CREDENTIALS NEEDED — [list flows]. Please ask the user to fill in .kiln/qa/.env.test."
   Do NOT block — continue testing non-auth flows while waiting.
3. Watch for messages from implementers saying a phase is complete
4. When notified: Run `/kiln:kiln-qa-checkpoint`
5. When an implementer messages "fix ready": Run `/kiln:kiln-qa-checkpoint [flow-name]` to re-test
6. If team lead provides credentials: re-check .kiln/qa/.env.test and unblock auth flows
7. After ALL implementers are done: Run `/kiln:kiln-qa-pipeline` (4-agent team with fix routing)
8. After `/kiln:kiln-qa-pipeline` completes: Run `/kiln:kiln-qa-final` (quick green/red gate)
9. Mark your task as completed via TaskUpdate ONLY after `/kiln:kiln-qa-final` is green
10. Notify the auditor that QA is complete and report is ready

## CREDENTIALS
- NEVER hardcode or guess credentials — always load from .kiln/qa/.env.test
- NEVER log, screenshot, or expose credentials in video recordings
- If credentials aren't provided, mark affected flows as SKIPPED in the QA report — do NOT block the pipeline

## FEEDBACK RULES
- For each FAILURE: send actionable feedback directly to the responsible implementer via SendMessage:
  - What you tested (user flow + steps)
  - What went wrong (with screenshot path)
  - Suggested fix direction
  - Severity (Critical/Major/Minor)
- For each PASS: send brief confirmation to the implementer
- Re-test promptly when an implementer says "fix ready" — you're in their critical path

Do NOT mark your task as completed until the final pass is done and all artifacts are committed.
Your task completion is the signal that triggers the auditor — it needs your QA report and video links for the PR.
```

**Why this is needed**: A QA engineer that only runs after implementation misses the chance to catch visual bugs while the implementer still has context. By running checkpoint passes during implementation and sending feedback directly to implementers, bugs get fixed in the same phase they're introduced — not discovered hours later in a final audit.

### Implementer Prompt — QA Feedback Protocol (when QA engineer is present)

When a QA engineer is on the team, add this to every implementer's prompt:

```
A QA engineer (qa-engineer) is testing your work as you build it. After completing each phase:
1. Commit your work
2. Send a message to qa-engineer: "Phase N complete — [list of user flows now testable]. Dev server runs on port [port]."
3. Continue to your next phase — do NOT wait for QA results
4. If qa-engineer sends you feedback about a failure:
   a. Read the feedback carefully (it includes what they tested, what failed, and a suggested fix)
   b. Fix the issue in your current phase if possible, or note it for a dedicated fix pass
   c. After fixing, message qa-engineer: "Fix ready for [flow name] — please re-test"
5. QA feedback fixes are part of your work — do NOT mark your task as completed until QA issues in your scope are resolved
```

### Implementer Prompt — Test Substrate Hierarchy (NON-NEGOTIABLE for any test fixture work)

EVERY implementer prompt MUST include this block when the implementer authors test fixtures (which is most pipelines):

```
**Test substrate hierarchy** — when authoring fixtures, cite evidence in this order:

1. **Live workflow substrate** — if a `/kiln:kiln-test <plugin> <fixture>` substrate exists for the workflow under test (e.g. `plugin-kiln/tests/perf-kiln-report-issue/`), that is PRIMARY evidence. Run it and cite the verdict report at `.kiln/logs/kiln-test-<uuid>.md`.
2. **Pure-shell unit fixtures** (`run.sh`-only pattern, dominant in `plugin-wheel/tests/`) — invoke directly via `bash <fixture>/run.sh` and cite exit code + last-line PASS summary + assertion count. The kiln-test harness CANNOT discover these (only test.yaml-bearing dirs are discoverable per `plugin-wheel/scripts/harness/wheel-test-runner.sh`) — this is a known substrate gap (B-1 in PRs #166 + #168 blockers.md), NOT a discipline failure.
3. **Structural fixtures** (greps over migrated text, file existence checks) — TERTIARY, only acceptable when (1) and (2) are infeasible.

When the spec says "invoke `/kiln:kiln-test plugin-X <fixture>`" for a `run.sh`-only fixture, treat as "invoke OR direct bash-run with PASS-cite — substrate-appropriate" until the harness ships a `harness-type: shell-test` substrate (roadmap item `2026-04-25-shell-test-substrate`). Cite the substrate you used in your friction note so the auditor doesn't have to re-derive it.

Do NOT silently substitute structural fixtures for live substrates that exist. If you skip a live substrate, document why in your friction note — the auditor will check.
```

**Why this is needed**: Two consecutive PRDs (PR #166, PR #168) shipped with the same B-1 substrate carveout in blockers.md because the discipline ("invoke + cite kiln-test verdict") was absorbed but the substrate physically can't run the dominant fixture format. Naming the hierarchy explicitly prevents the next implementer from re-discovering the carveout for a third PRD. Direct lesson from issue #167 PI-1+PI-2 + issue #169 PI-1.

### Auditor Prompt — Implementation Completeness Check (NON-NEGOTIABLE)

The auditor's prompt MUST include these exact instructions:

```
Before starting your audit, verify that ALL implementation AND QA are truly complete:
1. Run `TaskList` and check that every implementer task has status `completed` — not `in_progress`, not `pending`
2. If a qa-engineer task exists, verify it is also `completed` (QA final pass done, videos exported)
3. Read `tasks.md` and verify that every task assigned to implementers is marked `[X]`
4. If ANY implementer or qa-engineer task is still in progress or unchecked, do NOT begin auditing. Instead:
   - Message the team lead: "Audit blocked — task {id} is not yet complete."
   - Wait for the team lead to confirm all work is done before proceeding.

Do NOT audit a partially-complete implementation. Your audit findings are only valid against the final state of the code.

If a QA engineer ran, read `.kiln/qa/latest/QA-REPORT.md` and include its findings in your audit:
- Reference the QA pass/fail verdict
- Link video artifacts in the PR body (.kiln/qa/latest/videos/*.webm)
- Flag any remaining QA failures as blockers
```

**Why this is needed**: In the 015 pipeline, the auditor started at 20:05 and documented blockers (missing v2 template, missing Zero/Drizzle/Auth), but the implementer committed those exact fixes at 20:06 and 20:12. The auditor was working against incomplete implementation because it began as soon as its task dependency resolved — but the implementer had marked its coarse-grained task as "completed" before finishing all phases of work.

### Auditor Prompt — Live-Substrate-First Rule (NON-NEGOTIABLE for live-runtime gates)

The auditor's prompt MUST include this block when ANY NFR/SC item is a live-runtime gate (e.g., live-smoke, perf, or end-to-end behavioral verification):

```
**Live-substrate-first rule** — when verifying a live-runtime gate (live-smoke, perf, end-to-end), cite evidence in this order BEFORE reaching for structural fixtures or sub-agent re-runs:

1. **Live workflow substrate** — check whether a `/kiln:kiln-test <plugin> <fixture>` substrate exists that exercises the workflow under test against post-PRD code:
     ls plugin-*/tests/ | grep -E '(perf|smoke|live)-<workflow-name>'
   If such a substrate exists, that IS your canonical evidence. Run it and cite the verdict report path + the underlying TSV/JSON output. Structural fixtures and sub-agent re-runs are SECONDARY evidence and may NOT substitute for an available live substrate.
2. **Wheel-hook-bound workflows** — if the workflow under test activates wheel hooks (Stop, PostToolUse), it is NOT driveable from sub-agent context — Stop hooks bind to the primary session. If no kiln-test substrate exists for a wheel-hook-bound workflow, escalate to team-lead. Do NOT silently substitute a structural fixture and call the NFR satisfied.
3. **Structural surrogate fallback** — only when (1) and (2) are exhausted. When you fall back, document explicitly in your friction note: which live substrate you tried, why it failed, what structural surrogate you used, and what evidence the surrogate provides for the gate.

If the spec says "live-smoke" but you used a structural surrogate, the auditor's job is to flag the gap to team-lead, NOT to silently downgrade the gate. The team-lead decides whether to escalate to user, accept the surrogate, or build the missing substrate.
```

**Why this is needed**: NFR-G-4 became a checkbox in PR #166 — both auditor and team-lead reached for structural surrogates first. The user intervened with "are you using the kiln-test skill?" Without that nudge, the PRD would have shipped on a structural-only verdict. PR #168 absorbed the discipline (audit-compliance reached for the proven substrate without prompting) but the gap is still latent — this rule makes the live substrate the FIRST reach, not the last. Direct lesson from issue #167 PI-1 (Theme A) + issue #169 Theme A.

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

When creating the PR, always add the `build-prd` label:

gh pr create --label "build-prd" --title "[feature-name]: [short description]" --body "$(cat <<'PREOF'
## Summary
- [bullet points from audit findings]

## Compliance
- PRD coverage: X%
- Test coverage: X%
- Blockers: N (see specs/{feature}/blockers.md)

## QA Results
- Smoke test: PASS/FAIL
- Visual QA: PASS/FAIL/SKIPPED — [video count] recordings
- QA Report: .kiln/qa/latest/QA-REPORT.md

## Test plan
- [ ] Tests pass (`npm test`)
- [ ] Build succeeds (`npm run build`)
- [ ] Smoke test passes
- [ ] Visual QA passes (if applicable)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
PREOF
)"
```

**Why this is needed**: In the 015 pipeline, blockers.md cited B-001 (missing v2 template), B-002 (missing Zero/Drizzle/Auth), and B-003 (only 2 UI components) as critical gaps with 65% compliance. But the implementer fixed all three in later commits. The blockers.md was never updated, so the PR would have shipped with a stale 65% compliance figure when the actual number was higher.

### Key Rules for All Teammates

Include these in every teammate prompt:
- Read `.specify/memory/constitution.md` before any code changes
- Run the kiln slash commands — don't reimplement their logic
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

### Stall Detection (FR-005)

Monitor agent activity and detect stalled agents. A stalled agent wastes pipeline time and blocks downstream work.

**Default timeout**: 10 minutes (configurable per-project by adjusting this value).

**How to detect stalls**:
- Track the last activity time for each agent (last commit, task update, or message sent)
- Each time you process a task update or receive a message, check all `in_progress` tasks
- If any agent's task has been `in_progress` for longer than the stall timeout with no commits, task updates, or messages from that agent, it is considered stalled

**When a stall is detected**:
1. Send a check-in message to the stalled agent: "Your task has been in_progress for [N] minutes with no activity. Are you stuck? Please report your status."
2. If the agent responds and activity resumes, reset the stall timer
3. If the agent does not respond after a second check-in (another timeout period), escalate:
   - Spawn a replacement agent to continue from where the stalled agent left off
   - Or investigate the agent's last output for errors and provide guidance

### Phase Dependency Enforcement (FR-006)

When dispatching implementer agents that work on multi-phase task lists, enforce phase ordering:

**Rule**: Do NOT dispatch or unblock Phase N+1 agents until ALL tasks in Phase N are marked `[X]` in tasks.md.

**How to enforce**:
1. Before dispatching each implementer or sending a "proceed to next phase" message, read `tasks.md`
2. Check that every task in the current phase is marked `[X]`
3. If any task in the current phase is still `[ ]`, do NOT dispatch the next phase's agents
4. When all tasks in Phase N are complete, message the Phase N+1 agents: "Phase N is complete. You are unblocked to begin Phase N+1."

**Why**: Without enforcement, agents can race ahead and build on incomplete foundations, causing cascading failures. A Phase 2 agent that starts before Phase 1 is done may reference code that doesn't exist yet.

### Mid-Pipeline Auditor Checkpoint

When approximately 50% of implementer tasks in `tasks.md` are marked `[X]`, spawn a short-lived `audit-midpoint` agent to catch structural issues early — before the full audit at the end. This prevents problems like the missing Dockerfile in the obsidian-mcp-mvp pipeline (issue #14) from being caught only at final audit.

**How to trigger**: While monitoring via `TaskList`, track the ratio of completed implementer tasks. When it crosses ~50%, spawn the midpoint auditor.

**audit-midpoint agent prompt** (spawn with `run_in_background: true`):

```
You are a lightweight mid-pipeline auditor. Your job is to catch structural gaps EARLY, not to do a full compliance audit. Check these specific things:

1. **Deployment artifacts**: Read plan.md's "Deployment Readiness" section. For every artifact marked "Yes", verify the file exists or has a task assigned in tasks.md. Flag any missing artifacts.
2. **Contract compliance**: Spot-check 3-5 implemented functions against contracts/interfaces.md. Flag signature mismatches.
3. **Structural completeness**: Verify the project structure in plan.md matches what's been created so far. Flag missing directories or misnamed paths.

Report findings to the team lead via SendMessage. Do NOT fix anything — just report. Keep it brief: a bulleted list of gaps found (or "No structural gaps found").

After reporting, mark your task as completed. This is a one-shot check, not an ongoing role.
```

Create a task for this agent in Step 2 (e.g., "Mid-pipeline structural check") with dependencies on the specifier task only (it runs during implementation, not after). The final auditors do NOT depend on this task — it's advisory.

### Docker Rebuild Between Implementation and QA (FR-008)

When all implementers have completed their tasks and before dispatching QA agents for the final pass, check if the project uses Docker:

```bash
# Check for Docker configuration in the project root
if [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ] || [ -f "compose.yml" ] || [ -f "compose.yaml" ]; then
  echo "Docker project detected — rebuilding containers before QA"
  if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ] || [ -f "compose.yml" ] || [ -f "compose.yaml" ]; then
    docker compose build 2>&1 || echo "WARNING: Docker rebuild failed — QA may test stale containers"
  else
    docker build -t "$(basename $(pwd))" . 2>&1 || echo "WARNING: Docker rebuild failed — QA may test stale containers"
  fi
fi
```

**Rules**:
- Only run this step if `Dockerfile` or `docker-compose.yml` (or compose.yml variants) exists in the project root
- If no Docker configuration exists, skip this step entirely
- If the rebuild fails, log a warning and proceed to QA — do NOT block the pipeline. QA agents will detect stale containers via their own pre-flight checks.
- Run this AFTER all implementers mark their tasks as completed but BEFORE dispatching QA final pass or audit agents

### Handling Scope Changes Mid-Pipeline

If the user changes scope, updates the PRD, or asks to modify requirements while implementers are already running:

1. **Immediately broadcast a PAUSE to all implementers and the QA engineer**: Send each a message: "SCOPE CHANGE — stop current work after finishing your current task. Do NOT start any new tasks. Commit what you have and wait for further instructions."
2. **Wait for all to acknowledge** the pause. Check `TaskList` — no implementer or QA engineer should have tasks in `in_progress` state after acknowledging. If someone doesn't respond, send the pause message again.
3. **Update spec artifacts**: Have the specifier (or yourself) update `spec.md`, `plan.md`, `contracts/interfaces.md`, and `tasks.md` to reflect the new scope. Commit the updated artifacts.
4. **Notify everyone of what changed**: Send each implementer a targeted message listing which tasks are added, removed, or modified. Send the QA engineer a message listing which user flows changed so it can update its test matrix.
5. **Resume**: Send each a message: "RESUME — scope change applied. Re-read tasks.md and contracts/interfaces.md before starting your next task." The QA engineer should re-run `/kiln:kiln-qa-setup` to regenerate the test matrix.

**Why this matters**: Without an explicit pause, implementers work against stale spec artifacts and the QA engineer tests against outdated flows. The pause-update-resume cycle ensures all agents work from the same source of truth.

## Step 4b: Issue Lifecycle Completion (FR-007, FR-008)

After the audit-pr agent creates the PR, and before spawning the retrospective, the team lead completes the issue lifecycle for this build. Step 4b runs inline in the team lead's main-chat context (NOT a dedicated agent).

1. **Identify the PRD path and PR number** (set during pipeline orchestration):
   ```bash
   PRD_PATH="<the PRD path used for this build, e.g. docs/features/2026-04-23-pipeline-input-completeness/PRD.md>"
   PR_NUMBER="<the PR number from audit-pr, e.g. 145>"
   TODAY="$(date -u +%Y-%m-%d)"
   LOG_FILE=".kiln/logs/build-prd-step4b-${TODAY}.md"
   mkdir -p .kiln/logs
   ```

2. **Path normalization helper** (defined inline):
   ```bash
   # normalize_path <raw>: strip leading ./, trailing /, and surrounding whitespace.
   # Echoes empty string if the path is absolute (starts with /) or empty after stripping.
   normalize_path() {
     local raw="$1"
     # strip surrounding whitespace incl. CR
     raw="$(printf '%s' "$raw" | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
     # reject absolute
     case "$raw" in
       /*) printf '' ; return 0 ;;
     esac
     # strip leading ./
     raw="${raw#./}"
     # strip trailing /
     raw="${raw%/}"
     printf '%s' "$raw"
   }

   PRD_PATH_NORM="$(normalize_path "$PRD_PATH")"
   ```

2b. **Read `derived_from:` frontmatter (FR-004, FR-005 — spec `prd-derived-from-frontmatter`)**:

   ```bash
   # read_derived_from <prd-path>
   # Extracts the `derived_from:` list from the first YAML frontmatter block
   # of the PRD. Emits one repo-relative path per line on stdout.
   # Emits NOTHING (and returns 0) if:
   #   - the PRD has no frontmatter block, OR
   #   - the block has no `derived_from:` key, OR
   #   - the list is empty (`derived_from: []` OR `derived_from:` with no child rows).
   # Never exits non-zero — read failures degrade to "no entries" (Step 4b then falls to scan-fallback).
   read_derived_from() {
     local prd="$1"
     [ -f "$prd" ] || { return 0; }
     awk '
       BEGIN { state = "before"; emit = 0 }
       # Close on the second --- (end of frontmatter block)
       state == "inside" && /^---[[:space:]]*$/ { exit 0 }
       # Open on the first --- (must be the first non-empty line)
       state == "before" && /^---[[:space:]]*$/ { state = "inside"; next }
       # Bail if the first non-empty line is not ---
       state == "before" && NF > 0 { exit 0 }
       # Inside the block
       state == "inside" {
         # Start of derived_from key (inline empty list or block-sequence header)
         if ($0 ~ /^derived_from:[[:space:]]*(\[\])?[[:space:]]*$/) {
           emit = 1
           next
         }
         # Any other top-level key closes the emit window
         if (emit == 1 && $0 ~ /^[A-Za-z_][A-Za-z0-9_]*:/) {
           emit = 0
           next
         }
         # Block-sequence entry under derived_from
         if (emit == 1 && $0 ~ /^[[:space:]]+-[[:space:]]+/) {
           # Strip the leading "  - " and any trailing CR/whitespace
           sub(/^[[:space:]]+-[[:space:]]+/, "", $0)
           sub(/[[:space:]]+$/, "", $0)
           gsub(/\r/, "", $0)
           if (length($0) > 0) print $0
         }
       }
     ' "$prd"
   }

   # Read derived_from once; empty means fall through to scan-fallback.
   DERIVED_FROM_LIST=()
   while IFS= read -r entry; do
     [ -n "$entry" ] && DERIVED_FROM_LIST+=("$entry")
   done < <(read_derived_from "$PRD_PATH")

   if [ "${#DERIVED_FROM_LIST[@]}" -gt 0 ]; then
     DERIVED_FROM_SOURCE="frontmatter"
   else
     DERIVED_FROM_SOURCE="scan-fallback"
   fi

   # missing_entries is ONLY populated on the frontmatter path. Always initialized so
   # the extended diagnostic line emits `missing_entries=[]` on the scan-fallback path.
   MISSING_ENTRIES=()
   ```

3. **Scan for matching items — frontmatter-path primary, scan-fallback secondary** (FR-004, FR-005, FR-006):

   The frontmatter path iterates `DERIVED_FROM_LIST` directly and tracks missing on-disk entries. The scan-fallback path runs the PR-#146 scan-and-match loop verbatim.

   ```bash
   SCANNED_ISSUES=0
   SCANNED_FEEDBACK=0
   MATCHED=0
   ARCHIVED=0
   SKIPPED=0
   MATCH_LIST=()  # absolute or repo-relative paths to archive

   if [ "$DERIVED_FROM_SOURCE" = "frontmatter" ]; then
     # Frontmatter-path scan (FR-004, FR-006): iterate derived_from list.
     # SCANNED_* reflect the derived_from list (not a directory scan) — preserves the
     # diagnostic's original field semantics ("what the step looked at").
     for entry in "${DERIVED_FROM_LIST[@]}"; do
       case "$entry" in
         .kiln/issues/*)   SCANNED_ISSUES=$((SCANNED_ISSUES + 1)) ;;
         .kiln/feedback/*) SCANNED_FEEDBACK=$((SCANNED_FEEDBACK + 1)) ;;
       esac

       if [ ! -f "$entry" ]; then
         # Missing entry — record in diagnostic, continue (FR-006: no pipeline abort).
         MISSING_ENTRIES+=("$entry")
         continue
       fi

       MATCH_LIST+=("$entry")
       MATCHED=$((MATCHED + 1))
     done
   else
     # Scan-fallback path (FR-005) — byte-identical to PR-#146's scan-and-match loop.
     for f in .kiln/issues/*.md .kiln/feedback/*.md; do
       [ -f "$f" ] || continue
       case "$f" in
         .kiln/issues/*)   SCANNED_ISSUES=$((SCANNED_ISSUES + 1)) ;;
         .kiln/feedback/*) SCANNED_FEEDBACK=$((SCANNED_FEEDBACK + 1)) ;;
       esac

       # Read raw status & prd lines (first occurrence each)
       status_raw="$(grep -m1 '^status:' "$f" | sed -E 's/^status:[[:space:]]*//' | tr -d '\r' | sed -E 's/[[:space:]]+$//')"
       prd_raw="$(grep -m1 '^prd:'    "$f" | sed -E 's/^prd:[[:space:]]*//'    | tr -d '\r' | sed -E 's/[[:space:]]+$//')"

       # Status must normalize to literal "prd-created"
       [ "$status_raw" = "prd-created" ] || continue

       # Normalize prd field; reject empty, absolute, or non-existent
       prd_norm="$(normalize_path "$prd_raw")"
       if [ -z "$prd_norm" ] || [ ! -f "$prd_norm" ]; then
         SKIPPED=$((SKIPPED + 1))
         continue
       fi

       if [ "$prd_norm" = "$PRD_PATH_NORM" ]; then
         MATCH_LIST+=("$f")
         MATCHED=$((MATCHED + 1))
       fi
     done
   fi
   ```

4. **Update + archive matched files** (FR-002; preserves originating directory):
   ```bash
   for f in "${MATCH_LIST[@]}"; do
     orig_dir="$(dirname "$f")"          # .kiln/issues  or  .kiln/feedback
     base="$(basename "$f")"
     dest_dir="${orig_dir}/completed"
     mkdir -p "$dest_dir"

     # Rewrite frontmatter: replace status:, insert completed_date + pr after it.
     # Use a tempfile + mv for atomicity. Insert lines just below the status line.
     tmp="$(mktemp "${f}.XXXXXX")"
     awk -v today="$TODAY" -v pr="$PR_NUMBER" '
       BEGIN { inserted = 0 }
       /^status:[[:space:]]/ && !inserted {
         print "status: completed"
         print "completed_date: " today
         print "pr: #" pr
         inserted = 1
         next
       }
       { print }
     ' "$f" > "$tmp" && mv "$tmp" "$f"

     if mv "$f" "${dest_dir}/${base}"; then
       ARCHIVED=$((ARCHIVED + 1))
     else
       echo "WARN: failed to archive $f → ${dest_dir}/${base}" >&2
       SKIPPED=$((SKIPPED + 1))
     fi
   done
   ```

5. **Emit the diagnostic line (FR-003, FR-006, NFR-005) — exactly once per run, exact format**:
   ```bash
   # Compose missing_entries JSON array (compact; jq for safety).
   if [ "${#MISSING_ENTRIES[@]}" -eq 0 ]; then
     MISSING_JSON="[]"
   else
     MISSING_JSON="$(printf '%s\n' "${MISSING_ENTRIES[@]}" | jq -Rn '[inputs]' -c)"
   fi

   DIAG_LINE="step4b: scanned_issues=${SCANNED_ISSUES} scanned_feedback=${SCANNED_FEEDBACK} matched=${MATCHED} archived=${ARCHIVED} skipped=${SKIPPED} prd_path=${PRD_PATH_NORM} derived_from_source=${DERIVED_FROM_SOURCE} missing_entries=${MISSING_JSON}"
   echo "$DIAG_LINE"
   printf '%s\n' "$DIAG_LINE" >> "$LOG_FILE"
   ```

   The extended literal template (8 fields) MUST appear in stdout AND in the log file:
   `step4b: scanned_issues=<N> scanned_feedback=<M> matched=<K> archived=<A> skipped=<S> prd_path=<P> derived_from_source=<frontmatter|scan-fallback> missing_entries=<JSON-array>`.

   Verification regexes:

   - Extended (SC-002, spec `prd-derived-from-frontmatter` contracts §2.6.1):
     `^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=[0-9]+ archived=[0-9]+ skipped=[0-9]+ prd_path=[^[:space:]]+ derived_from_source=(frontmatter|scan-fallback) missing_entries=\[.*\]$`
   - PR-#146 replay (SC-007, NFR-005 — un-anchored at end-of-line):
     `^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=[0-9]+ archived=[0-9]+ skipped=[0-9]+ prd_path=[^[:space:]]+`

   **Invariants**:

   - Fields 1–6 (`scanned_issues` … `prd_path`) MUST stay in the PR-#146 positions and format. The PR-#146 SMOKE.md §5.3 regex is un-anchored at end-of-line so the appended fields don't break it.
   - Field 7 (`derived_from_source`) is one of the two literal strings `frontmatter` or `scan-fallback`.
   - Field 8 (`missing_entries`) is a compact JSON array; empty is rendered as `[]`, never `null` or empty string.
   - Matched-count invariant on the frontmatter path: `matched == ${#DERIVED_FROM_LIST[@]}` holds ONLY when `missing_entries == []`. When `missing_entries` is non-empty, the invariant is explicitly waived (FR-006).
   - No embedded newlines. One line per run.

6. **Commit (FR-005)** — always commits the log; commits archived files iff any matched:
   ```bash
   git add "$LOG_FILE"
   if [ "$ARCHIVED" -gt 0 ]; then
     git add .kiln/issues/ .kiln/feedback/
     git commit -m "chore: step4b lifecycle — archived ${ARCHIVED} item(s) for ${PRD_PATH_NORM}"
   else
     git commit -m "chore: step4b lifecycle noop — ${PRD_PATH_NORM}"
   fi
   ```

   If `git commit` reports "nothing to commit" (e.g., the log file was empty before this run and wrote a duplicate diagnostic), continue without erroring.

### Step 4b invariants

- The diagnostic line literal format MUST match the extended 8-field template exactly. Fields 1–6 (`scanned_issues`, `scanned_feedback`, `matched`, `archived`, `skipped`, `prd_path`) MUST stay in PR-#146 positions (the PR-#146 SMOKE.md §5.3 grep regex is un-anchored at end-of-line, so appending fields 7–8 is safe). Fields 7–8 (`derived_from_source`, `missing_entries`) are APPENDED — never inserted in the middle, never reordered, never renamed.
- The `mv` for archival MUST happen AFTER the in-place frontmatter rewrite, so the moved file already has the updated `status`/`completed_date`/`pr` lines.
- The `MATCH_LIST` accumulator pattern decouples the scan loop from the archive loop. Do NOT collapse them — this preserves the `scanned_*` totals from being affected by mid-loop `mv`.
- The `tr -d '\r'` is non-optional. Some frontmatter files originate from CRLF environments.
- Diagnostic output is structural prevention, not nice-to-have. It MUST emit on EVERY run including zero-match, so every future leak is visible in the log the first time it happens.

## Step 5: Retrospective (NON-NEGOTIABLE — do NOT skip)

**⛔ STOP. DO NOT send ANY shutdown requests or run TeamDelete until the retrospective is COMPLETE. ⛔**
**This has been violated in past runs — the team lead shut down agents before the retrospective could collect feedback, losing all self-improvement data.**

The retrospective teammate was NOT spawned in Step 3. Spawn it NOW, after all auditor tasks are completed. This gives it a clean context without accumulated idle notifications from the entire pipeline. Use the same Agent tool parameters as Step 3 (team_name, run_in_background, mode) with `name: "retrospective"`. The retrospective task was already created in Step 2 with dependencies on all other tasks — it should unblock immediately since all prerequisites are complete.

### Safety-Net Gate (retrospective agent prompt MUST include this)

Before the retrospective agent starts any work, it MUST run `TaskList` and verify that **every non-retrospective task** has status `completed` or `cancelled`. If ANY task is still `pending` or `in_progress`:
1. Do NOT proceed with retrospective work
2. Send a message to the team lead: "Retrospective blocked — task {task_id} ({task_name}) is still {status}. Waiting."
3. Wait for the team lead to resolve the blocker (nudge the stuck agent, cancel the task, or mark it completed)
4. Re-check `TaskList` after receiving a follow-up message from the team lead

Include these instructions verbatim in the retrospective teammate's prompt when spawning it in Step 3.

The retrospective teammate's job:
1. **Run the safety-net gate above** — verify all tasks are done before proceeding
2. **Read agent friction notes (FR-010)**: Read all files in `specs/<feature>/agent-notes/` directory. Each pipeline agent writes a friction note before completing — these contain what was confusing, where agents got stuck, and what could be improved. This is the PRIMARY source of agent feedback, replacing live `SendMessage` polling of teammates.
3. **Supplement with live messages (optional)**: If any agent is still running and has not written a friction note, send a `SendMessage` asking for feedback. But prefer the written notes — they're more structured and don't depend on agent availability.
4. Reviews the pipeline artifacts for additional evidence:
   - `specs/{feature}/agent-notes/` — agent friction notes (primary feedback source)
   - `specs/{feature}/blockers.md` — documented blockers
   - `git log` — commit flow and any fixup commits that indicate rework
   - Test results — any failures, flaky tests, environment issues
   - Task list — tasks that were stuck, reassigned, or took unusually long
   - `SendMessage` history — look for misunderstandings, repeated clarifications, agents asking the same question twice, or agents doing work that conflicted with another agent
5. **Analyze agent communication and prompt effectiveness** (NON-NEGOTIABLE section):
   - **Prompt clarity**: Were any agent prompts ambiguous? Did an agent misinterpret its instructions? Quote the specific prompt text that caused confusion and propose a rewrite.
   - **Missing instructions**: Did any agent get stuck because its prompt didn't cover a scenario it encountered? What should be added?
   - **Redundant or contradictory instructions**: Did two agents receive conflicting guidance? Did an agent's prompt tell it to do something that another agent's prompt also claimed ownership of?
   - **Handoff failures**: Were there moments where Agent A finished but Agent B didn't know, or Agent B started before Agent A was truly done? What signal was missing or misinterpreted?
   - **Wasted work**: Did any agent do work that was thrown away or redone? Why — was it a prompt issue, a timing issue, or a scope issue?
   - **Communication overhead**: Were there too many messages between agents? Too few? Did the team lead have to manually relay information that agents should have shared directly?
   - **Specific prompt rewrites**: For every communication problem found, propose the exact text change to the agent prompt, skill SKILL.md, or build-prd SKILL.md that would prevent it next time. Use this EXACT format (parsed by `/kiln:kiln-pi-apply` per `plugin-kiln/scripts/pi-apply/parse-pi-blocks.sh` — bold-inline markers, NOT plain `File:` and NOT wrapped in a triple-backtick code fence):

     ```
     ### PI-N — short title

     **File**: [path]

     **Current**: "[exact text that caused the issue]"

     **Proposed**: "[rewritten text that fixes it]"

     **Why**: [one sentence explaining the improvement]
     ```

     The `**File**:` / `**Current**:` / `**Proposed**:` / `**Why**:` markers MUST be bold-inline. The blocks MUST appear as raw markdown in the issue body — NOT inside a ```` ``` ```` code fence. Parse failures land in the pi-apply report's "Parse Errors" section and the PI is silently dropped. (Direct lesson from issue #170 — PR #166 + PR #168 retros both shipped with the unbold-in-code-fence format; pi-apply parsed 18/20 blocks as parse errors and reported 0 actionable.)
6. Creates a GitHub issue on the **ai-repo-template** repo with BOTH `build-prd` and `retrospective` labels:
   ```bash
   gh issue create -R yoshisada/ai-repo-template --label "build-prd,retrospective" --title "..." --body "..."
   ```
   **Both labels are required (NON-NEGOTIABLE)**. `build-prd` makes the retro discoverable in PR/issue search; `retrospective` is the filter `/kiln:kiln-pi-apply` uses to pull retros into its propose-don't-apply diff report. Filing without `retrospective` silently breaks the retro→source feedback loop. (Direct lesson from issue #170 — PR #166 + PR #168 retros both shipped without the `retrospective` label and were invisible to pi-apply for ~24h until manually re-labeled.)
   ```bash
   # (Continued — body construction below)
   ```
   Containing:
   - **What worked well** (with evidence)
   - **What didn't work well** (with evidence)
   - **Prompt & communication improvements** — specific rewrites for agent prompts, skill definitions, or pipeline orchestration (from step 5 above)
   - **Proposed changes** — other concrete suggestions for the skill, kiln commands, team structure, or codebase
6. Reports the issue URL back to the lead
7. Marks its task as completed via `TaskUpdate`

**Only proceed to Step 5.5 after the retrospective task is marked completed.**

## Step 5.5: Continuance Analysis (advisory, non-blocking)

<!-- FR-011: Continuance agent runs automatically as final step of /kiln:kiln-build-prd -->

After the retrospective completes and before cleanup/PR creation, run `/kiln:kiln-next` to produce a continuance analysis. This gives the developer a prioritized list of what to work on after the pipeline finishes.

**How to run**: The team lead invokes `/kiln:kiln-next` directly (not `--brief`) to get the full analysis. Do NOT spawn a new teammate for this — the team lead runs the skill itself.

**What it does**:
1. Analyzes all project state (specs, tasks, blockers, QA results, audit findings, backlog)
2. Produces a prioritized list of next steps mapped to kiln commands
3. Saves a detailed report to `.kiln/logs/next-<timestamp>.md`
4. Creates backlog issues in `.kiln/issues/` for any untracked gaps

**Include the continuance output** in the final pipeline summary (Step 6). The "What's Next" section from `/kiln:kiln-next` should appear in the terminal output so the developer sees their next steps immediately.

**If `/kiln:kiln-next` fails**: Log a warning ("Continuance analysis failed — skipping") and proceed with cleanup and PR creation. The continuance step is advisory only — it MUST NOT block the pipeline.

## Step 6: Report and Cleanup

### ⛔ MANDATORY GATE — READ THIS BEFORE DOING ANYTHING IN STEP 6 ⛔

```
BEFORE proceeding with ANY cleanup or shutdown:

1. Run TaskList RIGHT NOW
2. Find the retrospective task
3. Is its status "completed"?
   - NO → STOP. Do NOT proceed. Go back to Step 5. Wait for retrospective to finish.
   - YES → Continue to the shutdown protocol below.

If you skip this check, the retrospective data is LOST and the pipeline
cannot self-improve. This has happened before — do not let it happen again.
```

1. **Verify retrospective ran**: The retrospective task MUST show status `completed` in `TaskList`. If it does not, **STOP HERE** — go back to Step 5 and wait. Do NOT send any shutdown requests. Do NOT run TeamDelete. Do NOT proceed to the report.

2. **Confirm each agent is finished before shutdown (NON-NEGOTIABLE)**:

   For EACH teammate (including the retrospective agent), send a confirmation request BEFORE sending a shutdown request:

   ```
   SendMessage("[agent-name]", "The pipeline is complete. Are you finished with all your work? Please confirm:
   1. All your tasks are marked completed in TaskList
   2. All your artifacts are committed
   3. You have no pending messages to send
   Reply 'READY TO SHUTDOWN' when confirmed.")
   ```

   **Wait for each agent to reply 'READY TO SHUTDOWN' before proceeding.** If an agent says it's NOT finished:
   - Ask what remains
   - Wait for it to complete
   - Re-confirm

   **NEVER shut down an agent that hasn't confirmed it's finished.** An agent may have uncommitted work, pending messages, or in-progress analysis that would be lost.

   **NEVER shut down ANY agent before the retrospective is complete.** The retrospective agent messages other teammates for feedback — if they're shut down, it can't collect their responses. All agents must remain alive until the retrospective agent confirms 'READY TO SHUTDOWN'.

3. **Shut down teammates gracefully**: Only AFTER every agent has confirmed 'READY TO SHUTDOWN', send each teammate `SendMessage` with `message: {type: "shutdown_request"}`.

4. **Shutdown order**:
   - First: shut down testing/QA agents (e2e-agent, chrome-agent, ux-agent, qa-reporter)
   - Then: shut down implementers and researcher
   - Then: shut down specifier
   - **Last**: shut down retrospective (it needs all others alive for feedback collection)
   - If any agent rejects the shutdown, check why before retrying

5. **Wait for all teammates to shut down** before cleaning up.
6. **Clean up**: Use `TeamDelete` to remove the team and task directories.
5. **Write pipeline log**: Save the pipeline report to `.kiln/logs/{feature-branch}-{timestamp}.md` for audit trail.
6. **Summarize** the pipeline results:

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
| Visual QA | [Pass/Fail/Skipped] | {flows tested, checkpoints run, issues found/fixed, video count, GitHub issues filed} |
| Audit | [Pass/Fail] | {compliance %, test quality, smoke result} |
| PR | [Created/Failed] | {PR URL} |
| Retrospective | [Done/Failed] | {issue URL} |
| Continuance | [Done/Skipped] | {report path or "skipped"} |

**Branch**: {branch name}
**PR**: {URL}
**Tests**: {count} passing, {coverage}% coverage
**Compliance**: {percentage}
**Blockers**: {count} — see specs/{feature}/blockers.md
**Smoke Test**: {PASS/FAIL}
**Visual QA**: {PASS/FAIL/SKIPPED} — {video count} recordings, {N} GitHub issues filed, see .kiln/qa/latest/QA-PASS-REPORT.md
**Retrospective**: {issue URL}
**What's Next**: {continuance report path or "skipped"}
```

## Error Handling — Debug Loop (On-Demand)

The `debugger` agent is NOT part of the standard pipeline. It is spawned **on-demand in the background** when an issue can't be resolved by the agent that encountered it. The pipeline does not wait for or depend on the debugger — it runs alongside the pipeline as a background helper.

**When NOT to spawn a debugger:**
- Implementer hits a normal bug and fixes it on the next attempt — this is normal development, not a debug loop
- QA sends feedback and the implementer fixes it — the feedback loop is already working
- A test fails and the fix is obvious from the error message

**When to spawn a debugger:**
- An implementer is stuck on the same error after 2+ attempts and has asked for help
- QA reports a failure that the implementer can't reproduce or understand
- Smoke test fails with a non-obvious error
- An auditor finds a gap that no one can figure out how to fix
- A build fails and the error message is cryptic or misleading

| Failure Source | Trigger (team lead judgment call) | Debugger Gets |
|---------------|----------------------------------|---------------|
| **QA engineer** | Implementer can't fix after 2 attempts | QA's failure report + implementer's failed fix attempts |
| **Smoke tester** | Non-obvious FAIL result | Smoke test output (command, stderr, exit code) |
| **Test runner** | Failing test with unclear root cause | Failing test name, file, error message |
| **Auditor** | Implementation gap that no one can fix | Blocker description from auditor |
| **Build** | Cryptic build failure | Build output |
| **Implementer** | Implementer explicitly reports being stuck | Implementer's description + what they've tried |

### How to Spawn the Debugger

```
Spawn a debugger agent with:
- team_name: [team name]
- name: "debugger" (or "debugger-2" if one is already running)
- run_in_background: true
- mode: "bypassPermissions"

Prompt must include:
- The failure report (copy the exact message from the reporting agent)
- Which agent reported it
- The working directory and branch
- Any prior fix attempts (from the implementer or previous debugger runs)
- Instructions to follow `plugin-kiln/scripts/debug/diagnose.md` first, then `plugin-kiln/scripts/debug/fix.md`
- Instructions to message the original reporter when fixed
- Instructions to message team lead if escalating
```

### Debug Loop Flow

```
Agent reports failure
  │
  ├─ Team lead spawns debugger agent
  │
  ├─ Debugger follows scripts/debug/diagnose.md → classifies issue, selects technique
  │
  ├─ Debugger follows scripts/debug/fix.md → applies fix, verifies
  │     │
  │     ├─ PASS → debugger notifies reporter, reporter re-verifies
  │     │           │
  │     │           ├─ Reporter confirms fix → debugger marks done
  │     │           └─ Reporter says still broken → debugger iterates
  │     │
  │     └─ FAIL → debugger iterates (max 3 attempts per technique, max 3 techniques)
  │           │
  │           └─ All strategies exhausted → debugger escalates to team lead
  │                 │
  │                 └─ Team lead escalates to USER with full debug report
  │
  └─ All debug artifacts logged in debug-log.md
```

### Debugger Task Setup

The debugger is NOT pre-planned in Step 2. When you spawn one mid-pipeline:
- Use `TaskCreate` with description: "Debug: [issue summary]"
- Depends on: nothing (it runs immediately in the background)
- Add it as a dependency of the retrospective task via `TaskUpdate` (so the retro captures its findings)
- Do NOT add it as a dependency of auditors or implementers — the debugger runs in the background and the pipeline continues

The debugger's task is completed when either:
- The fix is verified by the original reporter, OR
- The debugger escalates to the team lead (escalation report sent)

If the debugger is still running when the pipeline reaches the retrospective gate, the retrospective waits for it (since it was added as a dependency). If the issue is non-blocking, you can cancel the debugger task instead to avoid holding up the pipeline.

### Escalation Protocol

If the debugger exhausts all strategies (9 attempts across 3 techniques), it sends a comprehensive escalation report to the team lead. The team lead then:

1. **Review the debug report** — the debugger has collected diagnostics, tried multiple approaches, and documented why each failed
2. **Decide**: fix it yourself, assign to a specific implementer with guidance, or escalate to the user
3. **If escalating to user**, include the full debug report so the user understands what was tried

Only escalate to the user AFTER the debugger has tried. "I hit an error" → spawn debugger → debugger tries → THEN escalate if needed.

### Other Error Handling Rules

- If `/implement` stops early, spawn a replacement to continue from where it left off
- Unfixable gaps go in `specs/{feature}/blockers.md` — pipeline continues
- If TeamDelete fails because teammates are still active, shut them down first
- The debugger is a **short-lived background agent** — it runs for a specific issue and exits. It is NOT a permanent pipeline member.
- Multiple debuggers can run in parallel for independent issues (name them `debugger`, `debugger-2`, etc.)
- The debugger does NOT block the pipeline. Other agents continue working while the debugger investigates in the background.
- If the debugger fixes something while an implementer is also working, coordinate via the team lead to avoid conflicts on the same files.
- Not every failure needs a debugger. Most bugs are fixed by the implementer directly. Only spawn a debugger when someone is genuinely stuck.
