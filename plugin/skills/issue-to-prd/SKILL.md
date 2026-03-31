---
name: issue-to-prd
description: Bundle open backlog items from docs/backlog/ into a feature PRD. Groups related issues by theme, prioritizes them, and generates a PRD ready for /build-prd. Use as "/issue-to-prd" (all open) or "/issue-to-prd <category>" to filter.
---

# Issue to PRD — Bundle Backlog into a Feature PRD

Read all open backlog entries from `docs/backlog/`, group related issues into coherent themes, and generate a feature PRD that can be built with `/build-prd`.

## User Input

```text
$ARGUMENTS
```

## Step 1: Read the Backlog

1. Read all `.md` files in `docs/backlog/`
2. Parse the frontmatter of each file — extract title, type, severity, category, status, date, github_issue
3. **Filter**: Only include entries where `status: open`
4. **If user provided a filter** (e.g., `/issue-to-prd templates`): further filter by category match
5. **If no open entries found**: Tell the user "No open backlog items found. Use `/report-issue` to log issues first." and stop.

## Step 2: Group by Theme

Analyze the open entries and group them into coherent themes. A theme is a set of related issues that should be fixed together because they share:
- The same root cause
- The same affected area (category)
- A logical dependency (fixing one requires or enables fixing another)

Present the grouping to the user:

```markdown
## Backlog Summary: N open items

### Theme 1: <theme name>
**Items**: N | **Highest severity**: <severity>
- [<title>](docs/backlog/<file>) — <type>, <severity>
- [<title>](docs/backlog/<file>) — <type>, <severity>

### Theme 2: <theme name>
**Items**: N | **Highest severity**: <severity>
- [<title>](docs/backlog/<file>) — <type>, <severity>

### Ungrouped
- [<title>](docs/backlog/<file>) — <type>, <severity>
```

## Step 3: Select Scope

Ask the user which themes to include in the PRD:

- **All themes**: "Bundle everything into one PRD"
- **Specific themes**: "Just themes 1 and 3"
- **Single theme**: "Only theme 2"
- **Custom selection**: "These specific items: <list>"

If there's only one theme, skip this step and proceed.

## Step 4: Generate the Feature PRD

Using the selected items, generate a feature PRD following the same structure as `/create-prd` Mode B (feature addition).

### PRD Location

Create: `docs/features/<YYYY-MM-DD>-<theme-slug>/PRD.md`

### PRD Content

The PRD must:

1. **Reference every backlog item** it addresses — link to the `docs/backlog/` file and GitHub issue number (if any)
2. **Synthesize, don't copy-paste** — combine related issues into coherent requirements, don't just list them
3. **Include these sections**:

```markdown
# Feature PRD: <Theme Name>

**Date**: YYYY-MM-DD
**Status**: Draft
**Parent PRD**: [link to docs/PRD.md if exists]

## Background

<Why this work is needed — synthesize the backlog items into a narrative>

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [title](docs/backlog/file.md) | #N or — | type | severity |

## Problem Statement

<1-2 paragraphs: what's broken or missing, who's affected, what's the cost of not fixing it>

## Goals

<Bulleted list of what "done" looks like>

## Non-Goals

<What this PRD explicitly does NOT address>

## Requirements

### Functional Requirements

<FR-001 through FR-NNN, each traceable to one or more source issues>

### Non-Functional Requirements

<Performance, reliability, backwards compatibility constraints>

## User Stories

<Derived from the backlog items — who needs what and why>

## Success Criteria

<Measurable outcomes — how do we know this worked>

## Tech Stack

<Inherited from parent PRD, plus any additions needed>

## Risks & Open Questions

<Unknowns, dependencies, things that could go wrong>
```

4. **Map requirements to backlog items**: Every FR-NNN should reference which backlog entry it addresses (e.g., `FR-001 (from: missing-dockerfile.md)`)
5. **Prioritize**: Order requirements by severity of their source issues (blocking > high > medium > low)

## Step 5: Update Backlog Status

After the PRD is written, update each included backlog entry:
- Change `status: open` to `status: prd-created`
- Add a line to the file: `prd: docs/features/<date>-<slug>/PRD.md`

## Step 6: Report

```markdown
## PRD Created

**Location**: docs/features/<date>-<slug>/PRD.md
**Addresses**: N backlog items
**Requirements**: N functional requirements

### Backlog items included:
- [x] <title> — <severity>
- [x] <title> — <severity>

### Remaining open backlog items: N

**Next step**: Review the PRD, then run `/build-prd <slug>` to execute the full pipeline.
```

## Rules

- Never delete backlog entries — only update their status
- If the user has no parent PRD (`docs/PRD.md` doesn't exist), the generated PRD is standalone — don't require a parent
- Don't invent requirements that aren't backed by backlog items — the PRD should solve what was reported, nothing more
- If a backlog item references a GitHub issue, include the issue number in the PRD for traceability
- Keep the PRD focused — if themes are too different to fit in one coherent PRD, suggest splitting into multiple PRDs
- Don't auto-commit — let the user review first
