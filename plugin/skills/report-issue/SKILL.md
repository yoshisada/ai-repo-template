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

**Read the issue template** — FR-018: check for a consumer-customized template first, then fall back to the plugin default:
1. If `.kiln/templates/issue.md` exists in the project, read it as the template
2. Otherwise, read `plugin/templates/issue.md` (the plugin default)

Write the file using the template structure, filling in the frontmatter fields and section content based on the classification from Step 2.

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
