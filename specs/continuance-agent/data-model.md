# Data Model: Continuance Agent (/next)

**Date**: 2026-03-31
**Feature**: [spec.md](./spec.md)

## Entities

### Recommendation

A single actionable next-step item produced by the continuance analysis.

| Field | Type | Description |
|-------|------|-------------|
| description | string | One-line summary of what needs to be done |
| command | string | The kiln command to execute (e.g., `/fix`, `/implement`, `/qa-pass`) |
| priority | enum | One of: `critical`, `high`, `medium`, `low` |
| source | string | Which artifact surfaced this item (e.g., `specs/auth/tasks.md`, `.kiln/issues/2026-03-30-login-bug.md`) |
| category | enum | One of: `blocker`, `incomplete-work`, `qa-audit-gap`, `backlog`, `improvement` |

### Continuance Report

The persistent markdown file saved to `.kiln/logs/`.

| Field | Type | Description |
|-------|------|-------------|
| timestamp | datetime | When the analysis was performed |
| branch | string | Current git branch at time of analysis |
| version | string | VERSION file content at time of analysis |
| sources_checked | list[string] | All artifact paths that were analyzed |
| sources_skipped | list[string] | Sources that were unavailable (e.g., GitHub when `gh` not present) |
| recommendations | list[Recommendation] | All recommendations, ordered by priority |
| summary | string | One-paragraph project state overview |

### Backlog Issue

An auto-created issue file in `.kiln/issues/`.

| Field | Type | Description |
|-------|------|-------------|
| filename | string | `<YYYY-MM-DD>-<slug>.md` |
| title | string | Issue title |
| description | string | Description of the gap |
| source | string | Which artifact surfaced this gap |
| tag | string | Always `[auto:continuance]` |
| created | datetime | When the issue was created |

## State Transitions

The continuance agent is stateless — it reads the current project state and produces output. There are no persistent state transitions. Each invocation is a fresh analysis.

## Relationships

```
Continuance Report
  └── contains 0..N Recommendations
        └── may trigger creation of 0..1 Backlog Issue (if gap not already tracked)
```

## File Locations

| Entity | Location | Format |
|--------|----------|--------|
| Continuance Report | `.kiln/logs/next-<YYYY-MM-DD-HHmmss>.md` | Markdown |
| Backlog Issue | `.kiln/issues/<YYYY-MM-DD>-<slug>.md` | Markdown |
| Terminal Summary | stdout | Markdown (max 15 items) |
