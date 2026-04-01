# Feature PRD: Continuance Agent (/next)

## Parent Product

[kiln](../../PRD.md) — spec-first development workflow plugin for Claude Code.

## Feature Overview

A continuance agent that analyzes the full state of a project — build artifacts, retrospectives, QA results, audit findings, GitHub issues, and backlog items — and produces a prioritized list of concrete next steps. It replaces the existing `/resume` skill with a more capable `/next` skill that serves two triggers:

1. **Post-build-prd**: Runs automatically at the end of every `/build-prd` pipeline to recommend what to do after the build completes.
2. **Session start**: Invoked manually via `/next` to pick up where you left off in any session (the current `/resume` use case).

## Problem / Motivation

After `/build-prd` completes, the user is left with a retrospective, audit results, QA findings, and possibly open blockers — but no clear guidance on what to do next. The current `/resume` skill only checks for in-progress artifacts and is limited in scope. Users have to manually piece together their next move from multiple sources.

This feature closes the loop: every build-prd ends with a clear "here's what to do next" recommendation, and every new session starts the same way.

## Goals

- Provide a single, authoritative "what's next" recommendation after every build-prd and at the start of every session
- Surface all open gaps across the full project state — nothing falls through the cracks
- Map every suggestion to a concrete kiln command (`/specify`, `/fix`, `/build-prd`, `/qa-pass`, etc.)
- Replace `/resume` with `/next` as a strictly more capable successor
- Persist analysis in `.kiln/logs/` so recommendations are reviewable and trackable

## Non-Goals

- Auto-executing suggestions — the agent recommends, the user decides
- Creating new PRDs or specs automatically — it can suggest `/specify` but won't run it
- Slack, email, or external notifications
- Replacing human judgment on prioritization — it ranks by heuristics, the user overrides freely

## Target Users

- Developers using kiln for spec-driven development
- Teams running `/build-prd` pipelines who need clear post-build guidance
- Any kiln user starting a new session who wants to resume efficiently

## Core User Stories

- As a developer who just finished a `/build-prd` run, I want to see a prioritized list of next steps so I know exactly what to work on without manually reviewing every artifact.
- As a developer starting a new session, I want to run `/next` and immediately understand the project state and what needs attention.
- As a developer, I want each suggestion to include the exact kiln command to run so I can act on it immediately.
- As a developer, I want the continuance report saved to disk so I can reference it later or share it with my team.
- As a developer, I want the agent to update the backlog (`.kiln/issues/`) when it discovers gaps that aren't already tracked.

## Functional Requirements

### FR-001: Full Project State Analysis

The continuance agent MUST review all of the following sources when available:

- `specs/*/tasks.md` — incomplete tasks (`[ ]` items)
- `specs/*/blockers.md` — documented blockers from audit
- `specs/*/retrospective.md` — lessons learned and action items from build-prd
- QA results — Playwright test failures, `/qa-pass` findings
- Audit findings — PRD compliance gaps from `/audit`
- `.kiln/issues/` — open backlog items
- GitHub issues — open issues on the repo
- GitHub PR comments — unresolved review feedback
- `specs/*/spec.md` — unimplemented FRs (cross-referenced with tasks)

### FR-002: Prioritized Recommendations

The agent MUST produce a prioritized list of next steps, ordered by:

1. **Blockers** — things that prevent progress (failing tests, unresolved blockers.md items)
2. **Incomplete work** — unchecked tasks from the most recent build
3. **QA/audit gaps** — findings that need fixing
4. **Backlog items** — open issues and feature requests
5. **Improvements** — retrospective action items and optimization opportunities

Each recommendation MUST include:
- A one-line description of what needs to be done
- The kiln command to execute (e.g., `/fix`, `/implement`, `/qa-pass`, `/specify`)
- Priority level (critical / high / medium / low)
- Source reference (which artifact surfaced this item)

### FR-003: Dual Output

The agent MUST produce both:

1. **Terminal summary**: A concise, scannable list printed directly in the conversation (max 15 items, grouped by priority)
2. **Persistent report**: A detailed markdown file saved to `.kiln/logs/next-<YYYY-MM-DD-HHmmss>.md` containing the full analysis, all recommendations, and source references

### FR-004: Backlog Updates

When the agent discovers gaps that are not already tracked in `.kiln/issues/`, it MUST:

- Create new issue files in `.kiln/issues/` following the existing naming convention (`<YYYY-MM-DD>-<slug>.md`)
- Tag auto-created issues with `[auto:continuance]` in the file content so they're distinguishable from manually reported issues
- NOT duplicate issues that already exist (match by title/description similarity)

### FR-005: /next Skill (Replaces /resume)

- The `/next` skill MUST replace `/resume` as the session-start command
- `/resume` SHOULD be kept as a deprecated alias that runs `/next` with a deprecation notice
- `/next` accepts an optional `--brief` flag that outputs only the top 5 recommendations without saving a report file

### FR-006: Post-build-prd Integration

- The continuance agent MUST run automatically as the final step of every `/build-prd` pipeline
- It runs AFTER the retrospective agent completes
- Its output is included in the build-prd terminal summary

### FR-007: Command Actionability

- Every recommendation MUST map to a valid kiln command or a specific manual action
- The agent MUST NOT suggest vague actions like "review the code" or "think about improvements"
- If a recommendation requires multiple steps, list them as a numbered sequence of commands

## Absolute Musts

1. **Tech stack**: No additions — markdown agent + skill within existing plugin structure
2. **Backward compatibility**: `/resume` must continue to work (as alias) during transition
3. **Idempotent**: Running `/next` twice in the same state produces the same recommendations
4. **No auto-execution**: The agent suggests but never runs commands on behalf of the user

## Tech Stack

Inherited from kiln plugin — no additions or overrides needed:
- Markdown-based agent definition (`plugin/agents/continuance.md`)
- Markdown-based skill definition (`plugin/skills/next/`)
- Shell/bash for any hook integrations
- GitHub CLI (`gh`) for issue and PR queries

## Impact on Existing Features

### Replaces
- `/resume` — replaced by `/next` with `/resume` kept as a deprecated alias

### Extends
- `/build-prd` — adds a continuance step after retrospective as the final pipeline stage

### No Impact
- All other skills and agents remain unchanged
- No breaking changes to existing workflows

## Success Metrics

1. **Actionability**: 90%+ of suggestions map to a concrete kiln command — measured by sampling reports and checking command validity
2. **Coverage**: The agent surfaces all open gaps — no missed blockers, incomplete tasks, or unaddressed QA findings when cross-referenced against actual project state
3. **Adoption**: `/next` usage frequency per session (target: run at least once per session by active users)

## Risks / Unknowns

- **GitHub API rate limits**: Querying issues and PR comments on every `/next` invocation may hit rate limits for repos with high activity. Mitigation: cache results with a short TTL or make external queries opt-in.
- **Noise vs signal**: If the project has many open items, the recommendation list could be overwhelming. Mitigation: strict prioritization and the `--brief` flag.
- **Deduplication accuracy**: Matching new gaps against existing `.kiln/issues/` entries requires fuzzy matching. Risk of false positives (missed duplicates) or false negatives (incorrect dedup). Mitigation: conservative matching — prefer creating a new issue over missing one.

## Assumptions

- The retrospective agent in `/build-prd` produces a `retrospective.md` file with structured content that can be parsed
- GitHub CLI (`gh`) is available and authenticated in environments where GitHub integration is used
- `.kiln/issues/` follows a consistent file naming and content format

## Open Questions

- Should `/next` support filtering by category (e.g., `/next --qa-only`, `/next --blockers-only`)?
- Should the continuance report include a "project health score" (e.g., percentage of tasks complete, test pass rate)?
- When running post-build-prd, should the agent wait for user confirmation before creating backlog issues, or create them silently?
