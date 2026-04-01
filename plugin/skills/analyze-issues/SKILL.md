---
name: analyze-issues
description: Triage open GitHub issues — categorize, label, flag actionable ones, suggest closures with confirmation, and offer backlog creation via /report-issue.
---

# Analyze Issues

Triage accumulated GitHub issues by categorizing them, applying labels, flagging actionable ones with explanations, suggesting closures for informational/stale issues, and offering to convert flagged issues into `.kiln/issues/` backlog items.

## User Input

```text
$ARGUMENTS
```

## Step 1: Validate Prerequisites

Before doing anything, verify the `gh` CLI is available and authenticated.

Run this command:

```bash
gh auth status
```

- **If the command fails** (exit code non-zero, or `gh` is not found): Stop and tell the user:
  > The `gh` CLI is not installed or not authenticated. Install it from https://cli.github.com and run `gh auth login` before using `/analyze-issues`.
- **If the command succeeds**: Proceed to Step 2.

## Step 2: Fetch Open Issues

Fetch all open issues (up to 50):

```bash
gh issue list --state open --json number,title,body,labels,createdAt,updatedAt --limit 50
```

Parse the JSON output into a list of issues. Each issue has: `number`, `title`, `body`, `labels` (array of label objects with `name`), `createdAt`, `updatedAt`.

- **If the result is an empty array** (`[]`): Report "No issues to analyze" and stop.
- **If the command fails**: Report the error and stop.
- Otherwise, store the full list as ALL_ISSUES and proceed to Step 3.

## Step 3: Filter Issues

Check if `$ARGUMENTS` contains `--reanalyze`.

- **If `--reanalyze` is present**: Use ALL_ISSUES as ISSUES_TO_PROCESS. Skip no issues.
- **If `--reanalyze` is NOT present**: Filter ALL_ISSUES to only those that do **not** have a label named `analyzed`. Store the filtered list as ISSUES_TO_PROCESS.

After filtering:

- **If ISSUES_TO_PROCESS is empty**: Report "No new issues to analyze (all open issues already have the `analyzed` label). Run with `--reanalyze` to re-process them." and stop.
- Otherwise, report how many issues will be processed (e.g., "Analyzing 4 of 14 open issues (10 already analyzed)") and proceed to Step 4.

## Step 4: Analyze Each Issue

For each issue in ISSUES_TO_PROCESS, read its title and body and determine:

### 4a. Category

Assign exactly **one** category based on what the issue is about:

| Category | Assign when the issue is about... |
|----------|-----------------------------------|
| `skills` | Skill behavior, prompts, flow, new skill requests, slash commands |
| `agents` | Agent definitions, team structure, agent behavior, model assignments |
| `hooks` | Enforcement rules, hook behavior, gate logic, PreToolUse scripts |
| `templates` | Spec/plan/task/interface templates, template formatting |
| `scaffold` | Init script, project structure, scaffolding, bin/init.mjs |
| `workflow` | Kiln pipeline, build-prd orchestration, process flow, phase ordering |
| `other` | Anything that does not fit the above categories |

If an issue spans multiple areas, pick the **primary** area — the one the issue is mainly requesting a change to.

### 4b. Actionability

Determine if the issue is **actionable** — meaning it contains something worth acting on:

**Flag as actionable** when the issue contains:
- A concrete improvement suggestion with a clear implementation path
- A bug report with reproducible steps or specific error details
- A process change that would measurably improve the workflow
- A performance or reliability concern with specific evidence

**Do NOT flag as actionable** when the issue is:
- A purely informational summary with no recommendations
- A build/run log with no suggested changes
- A status report or retrospective finding that is observation-only

For each actionable issue, write a **one-sentence explanation** of why it is worth acting on (e.g., "Adds retry logic that would prevent webhook delivery failures observed in 3 recent builds").

### 4c. Closure Suggestion

Determine if the issue should be **suggested for closure**:

**Suggest closure** when the issue is:
- Purely informational with no action items (e.g., a build summary)
- Describing behavior that has already been fixed (check if the issue content references something now resolved)
- A duplicate of another open issue in ISSUES_TO_PROCESS
- Stale — no activity for >90 days (compare `updatedAt` to today) and no clear action

For each closure suggestion, write a **brief reason** (e.g., "informational only — no action items", "duplicate of #12", "stale — no activity since 2025-12-01").

An issue can be both actionable and NOT suggested for closure, or not actionable and suggested for closure, or neither. These are independent assessments.

Store the results for each issue: `number`, `title`, `category`, `is_actionable`, `actionable_reason` (if actionable), `suggest_close`, `close_reason` (if suggesting closure).

## Step 5: Present Results

Display the analysis results grouped by category. Use this format:

```
## Analysis Results

### category:skills (N issues)
- #12 "Add retry to webhook skill" — **Actionable**: Prevents delivery failures seen in recent builds
- #15 "Skill prompt too verbose" — **Actionable**: Reduces token usage by ~30%

### category:hooks (N issues)
- #8 "Hook timeout on large repos" — **Actionable**: Causes false blocks on repos with >100 files
- #19 "Build summary for run #45" — Suggest close: informational only

### category:other (N issues)
- #22 "General feedback on DX" — Suggest close: no specific action items

### Not categorized
(only if any issues failed to categorize — should not normally appear)
```

For each issue, show:
- Issue number and title
- If actionable: bold **Actionable** tag with the one-sentence explanation
- If suggested for closure: "Suggest close:" with the reason
- If neither: just the number and title (no extra tags)

## Step 6: Handle Closures

If no issues were suggested for closure in Step 4, skip this step entirely.

Otherwise, present the closure suggestions to the user:

```
## Suggested Closures

The following issues appear to be informational, resolved, stale, or duplicative:

1. #19 "Build summary for run #45" — informational only, no action items
2. #22 "General feedback on DX" — no specific action items
3. #31 "Stale hook investigation" — stale, no activity since 2025-10-15

Close all 3? (yes / no / pick individually)
```

Wait for the user's response:

- **"yes"** or **"all"**: Close all suggested issues.
- **"no"** or **"none"**: Skip all closures. No issues are closed.
- **"pick"** or **"individually"** or a list of numbers (e.g., "1, 3"): Let the user select which to close.

For each issue the user confirms for closure, run:

```bash
gh issue close <number> --comment "Closed by /analyze-issues: <reason>"
```

Track how many issues were closed for the summary report.

## Step 7: Create and Apply Labels

### 7a. Create Labels

First, ensure all required labels exist by running these commands. The `--force` flag makes this idempotent — safe to re-run.

```bash
gh label create "category:skills" --color "0E8A16" --force
gh label create "category:agents" --color "1D76DB" --force
gh label create "category:hooks" --color "D93F0B" --force
gh label create "category:templates" --color "FBCA04" --force
gh label create "category:scaffold" --color "B60205" --force
gh label create "category:workflow" --color "5319E7" --force
gh label create "category:other" --color "C5DEF5" --force
gh label create "analyzed" --color "EDEDED" --force
```

If any label creation fails (e.g., insufficient permissions), report the error for that label and continue with the remaining labels.

### 7b. Apply Labels

For each analyzed issue, apply the category label and the `analyzed` label:

```bash
gh issue edit <number> --add-label "category:<category>,analyzed"
```

If labeling fails for a specific issue, report the error and continue with the remaining issues. Do not stop the entire run.

## Step 8: Offer Backlog Creation

If no issues were flagged as actionable in Step 4, skip this step entirely.

Otherwise, present the actionable issues and offer to create backlog items:

```
## Backlog Creation

The following issues were flagged as actionable:

1. #12 "Add retry to webhook skill" — Prevents delivery failures seen in recent builds
2. #15 "Skill prompt too verbose" — Reduces token usage by ~30%
3. #8 "Hook timeout on large repos" — Causes false blocks on repos with >100 files

Create backlog items for these? (all / none / pick: 1,3)
```

Wait for the user's response:

- **"all"**: Create backlog items for all flagged issues.
- **"none"** or **"no"**: Skip backlog creation.
- **"pick"** or a list of numbers (e.g., "1, 3"): Create backlog items only for selected issues.

For each selected issue, invoke:

```
/report-issue #<number>
```

This uses the existing `/report-issue` skill which handles GitHub issue import, classification, and file creation in `.kiln/issues/`.

Track how many backlog items were created for the summary report.

## Step 9: Summary Report

## Rules
