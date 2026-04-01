---
name: report-issue
description: Log a bug, friction point, or improvement idea to the project backlog. Creates a timestamped entry in .kiln/issues/. Use as "/report-issue <description>" or "/report-issue #42" to import from GitHub.
---

# Report Issue — Log to Backlog

Quickly capture a bug, friction point, or improvement idea so it doesn't get lost. Each entry lands in `.kiln/issues/` as a standalone file that can be reviewed, prioritized, and eventually bundled into a PRD via `/issue-to-prd`.

## User Input

```text
$ARGUMENTS
```

## Step 1: Parse Input

Determine the source:

- **GitHub issue reference** (e.g., `#42`, `42`, or a URL): Fetch the issue with `gh issue view <number> --json title,body,labels,state` and extract the title, description, and labels.
- **Inline text** (anything else): Use the text as the issue description. Ask the user for a one-line title if the text is longer than one sentence.
- **Empty**: Ask the user: "What's the issue? Describe the bug, friction, or improvement."

## Step 2: Classify

Determine these fields — infer from context, ask only if ambiguous:

1. **Type**: `bug` | `friction` | `improvement` | `feature-request`
2. **Severity**: `blocking` | `high` | `medium` | `low`
3. **Category** — which part of the system is affected:
   - `skills` — skill behavior, prompts, flow
   - `agents` — agent definitions, team structure
   - `hooks` — enforcement rules
   - `templates` — spec/plan/task templates
   - `scaffold` — init script, project structure
   - `workflow` — kiln pipeline, build-prd orchestration
   - `other`
4. **Source**: `retro` | `manual` | `github-issue` | `pipeline-run`
   - `retro` — came from a pipeline retrospective
   - `manual` — user reported it directly
   - `github-issue` — imported from a GitHub issue
   - `pipeline-run` — observed during a specific pipeline run

If importing from a GitHub issue, map labels to type/severity where possible. Default to `improvement` / `medium` if unclear.

## Step 3: Create Backlog Entry

Create `.kiln/issues/` directory if it doesn't exist.

Generate a filename: `YYYY-MM-DD-<short-slug>.md` (e.g., `2026-03-30-missing-dockerfile.md`).

Write the file with this structure:

```markdown
---
title: "<title>"
type: <bug|friction|improvement|feature-request>
severity: <blocking|high|medium|low>
category: <skills|agents|hooks|templates|scaffold|workflow|other>
source: <retro|manual|github-issue|pipeline-run>
github_issue: <number or null>
status: open
date: YYYY-MM-DD
---

## Description

<Full description of the issue>

## Impact

<Who/what is affected and how>

## Suggested Fix

<Brief idea of what the fix looks like, if known. "TBD" is fine.>
```

## Step 4: Confirm

Report back:

```
Logged to .kiln/issues/<filename>

  Type: <type> | Severity: <severity> | Category: <category>

Run /issue-to-prd to bundle open backlog items into a PRD.
```

## Rules

- One issue per file — don't append to existing files
- Don't duplicate: before creating, check if `.kiln/issues/` already has an entry with the same GitHub issue number or a very similar title. If so, tell the user and offer to update the existing entry instead.
- Don't auto-commit — the user may want to review or edit the entry first
- Keep descriptions concise but specific — quote error messages, file paths, or command output when relevant
- If the user reports multiple issues at once (e.g., a retro with 5 findings), create separate files for each one
