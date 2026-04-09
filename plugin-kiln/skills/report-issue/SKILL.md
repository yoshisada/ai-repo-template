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

## Step 1: Validate Input and Gather Context

If `$ARGUMENTS` is empty, ask the user: "What's the issue? Describe the bug, friction, or improvement."

Otherwise, confirm the issue description is in the conversation context — the workflow's agent step will reference it.

### Auto-detect repo URL (FR-012)

```bash
# Detect repo URL — graceful failure if gh unavailable or not authenticated
REPO_URL=$(gh repo view --json url -q '.url' 2>/dev/null || echo "")
echo "repo_url=$REPO_URL"
```

If `REPO_URL` is non-empty, include it in the issue frontmatter as `repo: <URL>`.
If empty (gh not installed, not authenticated, or no remote), set `repo: null`.

### Extract file paths from description (FR-012)

Scan the issue description text (`$ARGUMENTS`) for file paths — strings containing `/` with common code extensions (`.ts`, `.tsx`, `.js`, `.jsx`, `.md`, `.json`, `.sh`, `.mjs`, `.py`, `.go`, `.rs`) or paths that start with `src/`, `plugin-`, `specs/`, `.kiln/`, etc.

Include any detected paths in the issue frontmatter as:
```yaml
files:
  - path/to/file1.ts
  - path/to/file2.md
```

If no file paths are found in the description, omit the `files` field entirely.

## Step 2: Run Workflow

Run `/wheel-run kiln:report-issue-and-sync` to execute the workflow. The workflow will:

1. Check existing issues for duplicates
2. Classify and create the issue file in `.kiln/issues/`
3. Sync to Obsidian via `shelf-full-sync`

The user's issue description (from `$ARGUMENTS` above) is already in the conversation context — the workflow's agent step will use it.

## Rules

- If the user reports multiple issues at once, run the workflow once per issue
- If `$ARGUMENTS` is empty, ask before starting the workflow — don't start it with no description
