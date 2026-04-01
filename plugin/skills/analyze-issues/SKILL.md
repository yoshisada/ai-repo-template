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

## Step 5: Present Results

## Step 6: Handle Closures

## Step 7: Create Labels

## Step 8: Offer Backlog Creation

## Step 9: Summary Report

## Rules
