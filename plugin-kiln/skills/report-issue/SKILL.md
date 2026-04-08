---
name: report-issue
description: Log a bug, friction point, or improvement idea to the project backlog. Creates a timestamped entry in .kiln/issues/. Use as "/report-issue <description>" or "/report-issue #42" to import from GitHub.
---

# Report Issue — Log to Backlog

Quickly capture a bug, friction point, or improvement idea so it doesn't get lost. This skill delegates to the `report-issue-and-sync` wheel workflow, which creates the issue file and syncs to Obsidian via shelf.

## User Input

```text
$ARGUMENTS
```

## Step 1: Validate Input

If `$ARGUMENTS` is empty, ask the user: "What's the issue? Describe the bug, friction, or improvement."

Otherwise, confirm the issue description is in the conversation context — the workflow's agent step will reference it.

## Step 2: Run Workflow

Run `/wheel-run kiln:report-issue-and-sync` to execute the workflow. The workflow will:

1. Check existing issues for duplicates
2. Classify and create the issue file in `.kiln/issues/`
3. Sync to Obsidian via `shelf-full-sync`

The user's issue description (from `$ARGUMENTS` above) is already in the conversation context — the workflow's agent step will use it.

## Rules

- If the user reports multiple issues at once, run the workflow once per issue
- If `$ARGUMENTS` is empty, ask before starting the workflow — don't start it with no description
