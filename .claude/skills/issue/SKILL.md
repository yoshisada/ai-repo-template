---
name: issue
description: Read a GitHub issue and analyze how the repo can be improved. Proposes concrete changes to skills, hooks, templates, agents, or the plugin structure. Use as "/issue 42" or "/issue https://github.com/yoshisada/ai-repo-template/issues/42".
---

# Issue — Analyze and Improve

Read a GitHub issue and figure out what to change in this repo.

## User Input

```text
$ARGUMENTS
```

## Step 1: Fetch the Issue

Parse the input to extract the issue number or URL:
- If a number (e.g., `42`): fetch from this repo — `gh issue view 42 --json title,body,comments,labels,state`
- If a URL: extract owner/repo and number, then fetch — `gh issue view <number> -R <owner/repo> --json title,body,comments,labels,state`
- If empty: run `gh issue list -R yoshisada/ai-repo-template --state open --limit 10` and ask the user to pick one.

## Step 2: Understand the Issue

Read the issue title, body, and all comments. Identify:
1. **What's the problem or request?** — bug, feature request, workflow friction, missing capability
2. **Which parts of the repo are affected?** — categorize into:
   - `plugin/skills/` — skill behavior, prompts, flow
   - `plugin/agents/` — agent definitions
   - `plugin/hooks/` — enforcement rules
   - `plugin/templates/` — spec/plan/task templates
   - `plugin/scaffold/` — init script, project structure
   - `.claude-plugin/marketplace.json` — distribution
   - `CLAUDE.md` — workflow rules
   - `.specify/` — constitution, speckit config
   - Other
3. **What's the severity?** — blocking, friction, nice-to-have

## Step 3: Explore the Affected Code

Read the specific files identified in Step 2. Understand the current behavior before proposing changes. Do NOT skip this — always read first.

## Step 4: Propose Changes

Present a concise plan:

```
## Issue #<number>: <title>

**Problem**: <1-2 sentence summary>

**Affected files**:
- `path/to/file.md` — <what needs to change>
- `path/to/other.md` — <what needs to change>

**Proposed fix**:
1. <specific change>
2. <specific change>

**Risk**: <low/medium/high> — <why>
```

## Step 5: Ask to Proceed

Ask the user: "Want me to implement these changes?"

If yes:
- Make the changes
- Commit with message: `fix: <description> (closes #<number>)`
- Push to main (or create a branch if the changes are large)

If no:
- Stop. The analysis is still useful as a comment on the issue.
- Offer: "Want me to post this analysis as a comment on the issue?"

## Rules

- Do NOT make changes without showing the plan first
- Keep changes minimal — fix the issue, don't refactor the world
- If the issue is unclear, ask the user for clarification before proposing
- If the issue is already fixed (closed or code already handles it), say so
- Reference the issue number in all commits
