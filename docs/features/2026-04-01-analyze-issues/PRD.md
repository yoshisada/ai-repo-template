# Feature PRD: Analyze Issues Skill

**Date**: 2026-04-01
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)

## Background

The kiln plugin generates retrospective GitHub issues after every `/build-prd` pipeline run. Over time these accumulate — the ai-repo-template repo currently has 14 open retrospective issues. Many contain actionable feedback that should become backlog items, others are informational and can be closed, but there's no systematic way to triage them. Users have to manually read each issue, decide its value, categorize it, and act on it.

This feature adds a `/analyze-issues` skill that automates the triage: read all open issues, categorize them, flag the useful ones, suggest closures, and offer to create backlog items — all with user confirmation at each decision point.

## Problem Statement

Open GitHub issues accumulate after pipeline runs with no structured triage process. Users spend time manually reading issues to determine which contain actionable improvements, which are informational noise, and which category they belong to. This friction means retro findings often go unreviewed, and the issue list grows indefinitely.

## Goals

- Automatically categorize open GitHub issues using existing backlog categories
- Label analyzed issues with their category and an `analyzed` tag so they aren't re-processed
- Flag issues that contain actionable feedback, with a clear explanation of why
- Suggest issues to close (informational, resolved, or stale), with user confirmation before closing
- Offer to create `.kiln/issues/` backlog items from selected flagged issues via `/report-issue`

## Non-Goals

- Cross-repo issue analysis — only analyzes the current repo
- Modifying issue body or title content
- Auto-closing issues without user confirmation
- Analyzing closed issues or pull requests
- Creating backlog items automatically — user chooses which ones to create

## Requirements

### Functional Requirements

**FR-001**: The skill MUST read all open GitHub issues from the current repo using `gh issue list`.

**FR-002**: For each issue, the skill MUST assign a category from the existing backlog set: `skills`, `agents`, `hooks`, `templates`, `scaffold`, `workflow`, `other`.

**FR-003**: The skill MUST add a GitHub label matching the assigned category to each issue (e.g., `category:skills`). Labels MUST be created if they don't exist.

**FR-004**: The skill MUST add an `analyzed` label to each processed issue so subsequent runs skip already-analyzed issues.

**FR-005**: On subsequent runs, the skill MUST skip issues that already have the `analyzed` label, unless the user passes a `--reanalyze` flag.

**FR-006**: The skill MUST flag issues that contain actionable feedback (improvement suggestions, bug reports, process changes) and present them to the user with a brief explanation of why the issue is worth acting on.

**FR-007**: The skill MUST suggest issues to close — issues that are purely informational, already resolved, stale, or duplicative — with a brief reason for each suggestion.

**FR-008**: After presenting closure suggestions, the skill MUST prompt the user for confirmation before closing each issue (or offer batch close for all suggested).

**FR-009**: For flagged actionable issues, the skill MUST offer to create backlog items in `.kiln/issues/` by invoking `/report-issue` with the issue content. The user selects which flagged issues to convert.

**FR-010**: The skill MUST present a summary report at the end showing: total issues analyzed, categories assigned, issues flagged as actionable, issues suggested for closure, issues closed, backlog items created.

### Non-Functional Requirements

- Must work when `gh` CLI is available and authenticated; gracefully fail with a clear message if not
- Must handle repos with 0 open issues (report "no issues to analyze" and exit)
- Must not modify issue bodies or titles
- Should complete analysis of up to 50 issues in a single run
- Must be idempotent when run multiple times (the `analyzed` label prevents reprocessing)

## User Stories

- As a developer starting a session, I want to run `/analyze-issues` to quickly triage accumulated retro issues so I can act on the useful ones and close the rest.
- As a project maintainer, I want issues automatically categorized so I can filter by area (skills, agents, hooks, etc.) in the GitHub UI.
- As a developer reviewing retro findings, I want to see which issues contain actionable improvements so I can create backlog items for the ones worth pursuing.

## Success Criteria

- Running `/analyze-issues` on a repo with 14 open retro issues categorizes all of them and labels them `analyzed`
- Flagged issues include a clear, specific reason explaining why they're actionable
- User can close suggested issues in batch or individually with a single confirmation
- Running `/analyze-issues` a second time skips already-analyzed issues
- `--reanalyze` flag forces re-analysis of previously analyzed issues

## Tech Stack

- Markdown (skill definition)
- Bash (shell commands within skill — `gh` CLI for issue operations)
- No new dependencies

## Risks & Open Questions

- **Risk**: GitHub API rate limits could be hit on repos with many issues. Mitigation: limit to 50 issues per run, document the limit.
- **Q: Label naming convention** — should category labels be `category:skills` or just `skills`? Using `category:` prefix avoids collision with other labels.
- **Q: Batch vs interactive** — should the skill present all issues at once or go through them one at a time? Recommendation: present a grouped summary first, then interactive confirmation for closures and backlog creation.
