---
name: speckit-run
description: Run the complete speckit pipeline (specify → plan → research → tasks → commit → implement with per-phase audit → smoke test → PR) using subagents to prevent context compaction. Use this instead of running each speckit command manually.
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: custom
---

# Speckit Run — Full Pipeline Orchestrator

Run the complete speckit workflow as a series of subagents, each with a fresh context window. This prevents context compaction from losing critical instructions mid-workflow.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty). The user input is the feature description.

## Why Subagents?

Each speckit command expands into a large prompt. Running them sequentially in one context causes auto-compaction — earlier instructions (including "don't stop") get compressed away. By running each step in its own agent, every step gets a full, fresh context.

## Token Tracking

**IMPORTANT**: Track token usage from every subagent. Each Agent tool result includes `total_tokens` in its usage metadata. After each agent completes, record:
- Step name
- Token count

Keep a running total. Include the breakdown in the PR body and final report.

## Pipeline

Execute the following steps **sequentially**. Each step MUST complete before the next begins. Use the **Agent tool** with `subagent_type: "general-purpose"` for each step unless a specific subagent_type is noted. Do NOT run speckit commands directly in the main context.

### Step 1: Specify

Launch an agent with this prompt:

```
Read docs/PRD.md and .specify/memory/constitution.md for context.
Run /speckit.specify with this feature description: {user input}
Do not ask questions — the PRD has everything needed.
When done, report the spec file path and branch name.
```

Wait for completion. Extract the feature branch name and spec path from the result.

### Step 2: Plan

Launch an agent with this prompt:

```
Read .specify/memory/constitution.md and specs/{feature}/spec.md for context.
Run /speckit.plan for feature: {feature branch name}
Do not ask questions. Generate research.md, data-model.md, contracts/interfaces.md, quickstart.md.
When done, report all generated artifact paths.
```

Wait for completion.

### Step 3: Resolve External Dependencies (MAY ASK QUESTIONS)

**This is the ONLY step in the pipeline that may come back with questions for the user.**

Launch an agent with this prompt:

```
You are a research agent resolving external dependencies for feature {feature branch name}.

Read these files for context:
- docs/PRD.md — the product requirements (look for named projects, frameworks, starters, libraries)
- specs/{feature}/research.md — technology decisions made during planning
- specs/{feature}/plan.md — the implementation plan
- specs/{feature}/spec.md — the feature specification

Your job is to find and fetch every external project, starter, template, or library that the PRD and plan reference BY NAME. These are real projects that exist on GitHub or npm — not things to build from scratch.

For each named external dependency:

1. SEARCH GitHub and the web to find the actual repository or package
2. If it's a starter/template repo (e.g., "Tamagui Takeout", "takeout-free", "create-t3-app"):
   - Clone or download it into vendor/{name}/ in the project root
   - Document its file structure in specs/{feature}/research.md under a new "## External Dependencies" section
   - Note which parts should be used as the base template vs adapted vs ignored
3. If it's a library/package:
   - Verify the correct package name and latest stable version
   - Document it in research.md
4. If you CANNOT find or access a dependency:
   - Report it as a QUESTION to the user: "The PRD references {name} but I cannot find/access it. Please provide: (a) a URL/path, (b) confirm it should be recreated from scratch, or (c) suggest an alternative."

Update these files with your findings:
- specs/{feature}/research.md — add "## External Dependencies" section with URLs, paths, and integration notes
- specs/{feature}/plan.md — update template/file references to point to actual vendor/ paths where applicable

Report:
- Dependencies resolved: [list with URLs]
- Dependencies cloned to vendor/: [list with paths]
- Questions for user: [list — ONLY if something cannot be found or accessed]
```

Wait for completion.

**If the agent returns questions**: Present them to the user and wait for answers. Then send the answers back to the agent (via SendMessage) so it can finish resolving.

**If no questions**: Proceed to Step 4.

### Step 4: Tasks

Launch an agent with this prompt:

```
Read specs/{feature}/spec.md, specs/{feature}/plan.md, specs/{feature}/research.md, and specs/{feature}/contracts/interfaces.md.
Run /speckit.tasks for feature: {feature branch name}
Do not ask questions. Generate the complete task breakdown.
When done, report the tasks.md path and total task count.
```

Wait for completion. **Parse the tasks.md to extract the list of phases** (Phase 1, Phase 2, etc.) — you will need this for Step 6.

### Step 5: Commit Artifacts

Do this step directly (not in a subagent). Commit all spec artifacts and any vendor/ dependencies:

```bash
git add specs/{feature}/ vendor/ CLAUDE.md
git commit -m "Add spec artifacts for {feature}"
```

(If vendor/ doesn't exist or is empty, that's fine — git add will skip it.)

### Step 6: Implement (Phase-by-Phase with Audit Gates)

**CRITICAL**: Do NOT launch a single agent for all phases. Instead, launch a **separate implement agent per phase** followed by an **audit agent** after each phase. This catches gaps early before they compound.

**Read `specs/{feature}/tasks.md` directly** to extract the phase list (e.g., "Phase 1: Setup", "Phase 2: Foundational", "Phase 3: User Story 1", etc.).

For **each phase** in order:

#### Step 6a: Implement Phase N

Launch an agent with this prompt:

```
You are implementing Phase {N} of feature {feature branch name}.

CRITICAL INSTRUCTIONS:
- Read specs/{feature}/tasks.md — find all tasks in Phase {N}
- Read specs/{feature}/contracts/interfaces.md — all functions must match these signatures
- Read specs/{feature}/plan.md — this is your technical architecture
- Read specs/{feature}/research.md — check for external dependencies in vendor/ that should be used instead of writing from scratch
- Read specs/{feature}/spec.md — this is your requirements source
- Read .specify/memory/constitution.md — these are governing principles

If vendor/ contains external starter templates or libraries referenced in plan.md, USE THEM as the base — do not recreate from scratch.

Implement ONLY the tasks in Phase {N}: {phase title}.
For each task:
1. Write the code matching the contract signatures exactly
2. Every function must reference its spec FR in a comment
3. Mark the task [X] in tasks.md immediately after completing it
4. Write tests for the code you implemented

Do NOT implement tasks from other phases.
Do NOT stop until every task in Phase {N} is marked [X].
If you hit an error, fix it and continue.
When done, run the tests for this phase and report results.
Commit your changes with message: "Implement Phase {N}: {phase title}"
```

Wait for completion.

#### Step 6b: Audit Phase N

After each phase completes, launch an **audit agent** (use `subagent_type: "prd-auditor"`) with this prompt:

```
You are auditing Phase {N} of feature {feature branch name}.

Read docs/PRD.md for the source requirements.
Read specs/{feature}/spec.md for the FRs.
Read specs/{feature}/contracts/interfaces.md for the function signatures.
Read specs/{feature}/tasks.md — check that all Phase {N} tasks are marked [X].

For every FR that Phase {N} tasks claimed to implement:

1. VERIFY the implementation exists — read the actual source file, find the function, confirm it matches the contract signature
2. VERIFY the FR comment exists in the source code (// FR-NNN)
3. VERIFY a test exists that references the acceptance scenario
4. VERIFY the test actually tests the behavior (not just a stub)
5. For template/scaffold tasks: VERIFY the generated files have real content, not just placeholders
6. If the PRD references an external project (starter, template, library): VERIFY the implementation actually uses it rather than recreating it from scratch

If ANY gap is found:
- Try to FIX it (add missing comment, write missing test, flesh out stub)
- If unfixable, document in specs/{feature}/blockers.md

Report:
- Phase {N} compliance: X/Y FRs verified
- Gaps found and fixed: [list]
- Blockers: [list]
- Test results for this phase
```

Wait for completion. **If the audit reports blockers, log them but continue to the next phase.**

#### Repeat 6a → 6b for every phase

Continue until all phases are implemented and audited.

### Step 7: Full Audit

After all phases are done, launch a final **audit agent** (use `subagent_type: "prd-auditor"`) with this prompt:

```
You are running the FINAL PRD compliance audit for feature {feature branch name}.

Read docs/PRD.md — extract EVERY functional requirement, deliverable, and user story.
Read specs/{feature}/spec.md — extract every FR-NNN.
Read specs/{feature}/contracts/interfaces.md — every function signature.
Read .specify/memory/constitution.md — governing principles.

Check BOTH directions:

Phase A — PRD → Spec: Does every PRD requirement have at least one covering FR?
Phase B — Spec → Code → Test: For every FR-NNN:
  1. Search source files for // FR-NNN comment — READ the actual function, not just the filename
  2. Verify the function signature matches contracts/interfaces.md
  3. Search test files for acceptance scenario references
  4. Verify tests actually test the behavior (not stubs)
  5. For templates/scaffolds: verify files contain real, functional content — not placeholder stubs

For generated project templates specifically:
  - Does the README exist with setup instructions, structure overview, and module guide?
  - Do template files contain real, runnable code (not just placeholder comments)?
  - Would a generated project actually install dependencies and start?
  - If the PRD names a specific starter/template (e.g., "Tamagui Takeout"), is the actual project used — not a from-scratch recreation?

Fix gaps or document blockers in specs/{feature}/blockers.md.
Report overall compliance percentage.
```

Wait for completion.

### Step 8: Smoke Test

Launch a **smoke test agent** (use `subagent_type: "smoke-tester"`) with this prompt:

```
You are smoke testing feature {feature branch name}.

Read specs/{feature}/plan.md to determine the project type (CLI, web app, mobile, API).

Perform a full runtime smoke test:

1. Create a temp directory
2. Build the project (bun run build or equivalent)
3. Run the primary command or start the server
4. Verify it actually works:
   - CLI: run the main commands, check exit codes and output
   - Web: start dev server, curl the URL, verify 200 response with real content
   - Mobile: verify prebuild succeeds
   - API: hit health and primary endpoints

For CLI projects that generate other projects:
   - Run the create command to generate a project
   - cd into the generated project
   - Run bun install (or equivalent)
   - Verify it installs without errors
   - Try to start the dev server
   - Verify basic functionality works

Report PASS/FAIL for each check with exact error output on failure.
Clean up temp dir (keep on failure for debugging).
```

Wait for completion. **If smoke test FAILs, report the failures but do not retry.**

### Step 9: Create Pull Request

Do this step directly (not in a subagent).

1. **Check for branch conflicts**: Before pushing, verify the remote branch doesn't already exist:
   ```bash
   git ls-remote --heads origin {branch name}
   ```
   - If the remote branch exists, append a suffix: `{branch name}-v2`, `-v3`, etc. until a free name is found
   - Create and switch to the new branch name if needed: `git branch -m {new branch name}`

2. **Push the branch**:
   ```bash
   git push -u origin {branch name}
   ```

3. **Create the PR** using `gh pr create`:
   - Title: short summary of the feature (under 70 chars)
   - Body: include Summary (bullet points), Stats (files, tests, coverage, compliance), Test Plan (checklist of what was verified), and the smoke test result
   - Format:
   ```
   gh pr create --title "{title}" --body "$(cat <<'EOF'
   ## Summary
   - {bullet points from the pipeline report}

   ## Stats
   - **Files**: {count}
   - **Tests**: {count} passing, {coverage}% coverage
   - **Compliance**: {percentage} ({X}/{Y} FRs)
   - **Smoke Test**: {PASS/FAIL}

   ## Token Usage
   | Step | Tokens |
   |------|--------|
   | Specify | {n} |
   | Plan | {n} |
   | Research | {n} |
   | Tasks | {n} |
   | Phase 1 Impl | {n} |
   | Phase 1 Audit | {n} |
   | ... | ... |
   | Final Audit | {n} |
   | Smoke Test | {n} |
   | **Total** | **{sum}** |

   ## Test plan
   - [x] Unit tests passing
   - [x] E2E tests passing
   - [x] Coverage >= 80%
   - [x] PRD audit: {compliance}%
   - [x] Smoke test: {result}

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   EOF
   )"
   ```

4. **Report the PR URL** to the user.

### Step 10: Report

After all steps complete, summarize in the main context:

```
## Pipeline Report: {feature branch name}

| Step | Status | Details |
|------|--------|---------|
| Specify | [Done/Failed] | {FR count, user story count} |
| Plan | [Done/Failed] | {artifact count} |
| Research | [Done/Skipped/Questions] | {deps resolved, questions asked} |
| Tasks | [Done/Failed] | {phase count, task count} |
| Commit | [Done/Failed] | {commit hash} |
| Phase 1 Impl | [Done/Failed] | {tasks completed} |
| Phase 1 Audit | [Pass/Fail] | {compliance %} |
| ... | ... | ... |
| Phase N Impl | [Done/Failed] | {tasks completed} |
| Phase N Audit | [Pass/Fail] | {compliance %} |
| Final Audit | [Pass/Fail] | {overall compliance %} |
| Smoke Test | [Pass/Fail] | {checks passed/failed} |
| PR | [Created/Failed] | {PR URL} |

**Branch**: {branch name}
**PR**: {URL}
**Tests**: {count} passing, {coverage}% coverage
**Compliance**: {percentage}
**Blockers**: {count} — see specs/{feature}/blockers.md
**Smoke Test**: {PASS/FAIL}
**Total Tokens**: {sum across all agents}
```

## Error Handling

- If any agent fails, report the error and the step that failed
- Do NOT retry automatically — report to the user and ask how to proceed
- If an implement agent stops early (tasks remain unchecked in that phase), launch a new implement agent for the remaining tasks in that phase

## Notes

- Each agent gets a fresh context window — no compaction risk
- The main context stays lean — just orchestration and results
- Step 3 (Research) is the ONLY step that may ask the user questions — all other steps run autonomously
- Per-phase audits catch gaps early before they compound across phases
- The smoke test validates runtime behavior — not just test results
- The PR step safely handles existing branches by appending version suffixes
- Feature description comes from $ARGUMENTS or the user's message
