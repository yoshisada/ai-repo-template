---
name: kiln-distill
description: Bundle open backlog items from `.kiln/issues/` AND open strategic feedback from `.kiln/feedback/` into a feature PRD. Groups related items by theme (feedback themes first per FR-012), prioritizes them, and generates a PRD ready for `/kiln:kiln-build-prd`. Use as "/kiln:kiln-distill" (all open) or "/kiln:kiln-distill <category>" to filter.
---

# Kiln Distill — Bundle Backlog + Feedback into a Feature PRD

Read all open backlog entries from `.kiln/issues/` AND all open strategic feedback entries from `.kiln/feedback/`, group related items into coherent themes, and generate a feature PRD that can be built with `/kiln:kiln-build-prd`.

Feedback (strategic: mission / scope / ergonomics / architecture) shapes the PRD narrative — Background, Problem Statement, and Goals are written around feedback themes first. Issues (tactical: bugs / friction) form the FR layer under the feedback-shaped themes (FR-012).

## User Input

```text
$ARGUMENTS
```

## Step 1: Read Both Sources (Feedback + Backlog)

Read open items from both directories — feedback first, issues second. Preserve the source-type tag on every item throughout the rest of the flow.

```
# Pseudocode — reference shape (Contract 3)
feedback_files = glob(".kiln/feedback/*.md") with frontmatter.status == "open"
issue_files    = glob(".kiln/issues/*.md", top-level only) with frontmatter.status == "open"

# Tag each item with its source type (persists through grouping, PRD rendering, and status update)
feedback_items = [{...parsed frontmatter, type_tag: "feedback"} for f in feedback_files]
issue_items    = [{...parsed frontmatter, type_tag: "issue"}    for f in issue_files]

all_items = feedback_items + issue_items   # feedback FIRST — preserves FR-012 ordering

if empty(all_items):
    report "No open backlog or feedback items. Use /kiln:kiln-feedback or /kiln:kiln-report-issue to log items first."
    stop
```

Notes:

- For feedback files, parse: `id`, `title`, `type: feedback`, `date`, `status`, `severity`, `area`, `repo`, optional `files`. The `type_tag` is derived from source directory (`.kiln/feedback/` → `feedback`), NOT from the frontmatter `type:` field — though they should agree.
- For issue files, parse: `title`, `type`, `severity`, `category`, `status`, `date`, `github_issue`. The `type_tag` is `issue`.
- **Filter**: only include entries where `status: open`.
- **If the user provided a filter** (e.g., `/kiln:kiln-distill templates`): further filter each side — for issues, match on `category`; for feedback, match on `area`. Same free-text match on both.
- **Top-level only** for `.kiln/issues/` — do NOT recurse into `completed/` (FR-025).

## Step 2: Group by Theme (Feedback-First)

Analyze the open items and group them into coherent themes. A theme is a set of related items that should be addressed together because they share:
- The same root cause or concern
- The same affected area (`area:` for feedback, `category:` for issues)
- A logical dependency

**Ordering rules (FR-012)**:
1. Within a theme, list feedback items FIRST, then issue items.
2. Themes that contain any feedback item appear BEFORE themes that are issue-only.
3. Within each section, sort by highest severity inside the theme.

Present the grouping to the user with the two-section shape:

```markdown
## Backlog Summary: N open items (F feedback + I issues)

### Feedback-shaped themes

#### Theme 1: <theme name>
**Items**: N | **Highest severity**: <severity>
- [feedback] [<title>](.kiln/feedback/<file>) — <area>, <severity>
- [feedback] [<title>](.kiln/feedback/<file>) — <area>, <severity>
- [issue]    [<title>](.kiln/issues/<file>) — <type>, <severity>

#### Theme 2: <theme name>
**Items**: N | **Highest severity**: <severity>
- [feedback] [<title>](.kiln/feedback/<file>) — <area>, <severity>
- [issue]    [<title>](.kiln/issues/<file>) — <type>, <severity>

### Issue-only themes

#### Theme 3: <theme name>
**Items**: N | **Highest severity**: <severity>
- [issue] [<title>](.kiln/issues/<file>) — <type>, <severity>

### Ungrouped
- [feedback] [<title>](.kiln/feedback/<file>) — <area>, <severity>
- [issue]    [<title>](.kiln/issues/<file>) — <type>, <severity>
```

If there are no feedback items in the run, the "Feedback-shaped themes" section is omitted and the grouping reverts to today's issue-only shape.

## Step 3: Select Scope

Ask the user which themes to include in the PRD:

- **All themes**: "Bundle everything into one PRD"
- **Specific themes**: "Just themes 1 and 3"
- **Single theme**: "Only theme 2"
- **Custom selection**: "These specific items: <list>"

If there's only one theme, skip this step and proceed.

## Step 4: Generate the Feature PRD

Using the selected items, generate a feature PRD following the same structure as `/kiln:kiln-create-prd` Mode B (feature addition).

### PRD Location

Create: `docs/features/<YYYY-MM-DD>-<theme-slug>/PRD.md`

### Feedback-first narrative shape (FR-012, Contract 3 PRD-rendering rule)

When the selected items include ANY feedback entries, the PRD narrative MUST lead with feedback themes:

- **`## Background`**: cite feedback themes FIRST — paragraph 1 synthesizes the strategic concerns raised by feedback. Paragraph 2+ brings in issues as the tactical layer that reinforces the feedback theme.
- **`## Problem Statement`**: same feedback-first order. Open with the strategic problem from feedback, then name the tactical pain points from issues that demonstrate it.
- **`## Goals`**: bullets keyed off feedback themes wherever any exist. Issue-only themes contribute additional goal bullets BENEATH the feedback-derived ones.
- **`## Requirements → ### Functional Requirements`**: within each theme, feedback-derived FRs appear BEFORE issue-derived FRs. Each FR still references its source item (`FR-001 (from: <feedback-or-issue-filename>.md)`).
- **`### Source Issues`** table: add a `Type` column with values `feedback` or `issue`. Sort rows so all feedback entries appear BEFORE issue entries.

If there are NO feedback items in the run, fall back to the prior issue-only narrative shape (no forced feedback framing).

### PRD Content

The PRD must:

1. **Reference every source item** it addresses — link to the source file (`.kiln/feedback/...` or `.kiln/issues/...`) and GitHub issue number (if any, issues only)
2. **Synthesize, don't copy-paste** — combine related items into coherent requirements, don't just list them
3. **Include these sections**:

```markdown
# Feature PRD: <Theme Name>

**Date**: YYYY-MM-DD
**Status**: Draft
**Parent PRD**: [link to docs/PRD.md if exists]

## Background

<Why this work is needed — feedback themes FIRST when any feedback present, then tactical issues as supporting evidence>

### Source Issues

| # | Source Item | Source | Type | GitHub Issue | Severity / Area |
|---|-------------|--------|------|--------------|------------------|
| 1 | [title](.kiln/feedback/file.md) | .kiln/feedback/ | feedback | — | high / mission |
| 2 | [title](.kiln/feedback/file.md) | .kiln/feedback/ | feedback | — | medium / ergonomics |
| 3 | [title](.kiln/issues/file.md)   | .kiln/issues/   | issue    | #N or — | high / <category> |

(Feedback rows first, issues second — FR-012.)

## Problem Statement

<1-2 paragraphs — feedback-first when any feedback is present. Strategic problem stated from feedback, tactical evidence from issues.>

## Goals

<Bulleted list — feedback-theme goals first, issue-theme goals beneath>

## Non-Goals

<What this PRD explicitly does NOT address>

## Requirements

### Functional Requirements

<FR-001 through FR-NNN. Within each theme, feedback-derived FRs come FIRST. Each FR traceable to source file.>

### Non-Functional Requirements

<Performance, reliability, backwards compatibility constraints>

## User Stories

<Derived from the source items — who needs what and why>

## Success Criteria

<Measurable outcomes — how do we know this worked>

## Tech Stack

<Inherited from parent PRD, plus any additions needed>

## Risks & Open Questions

<Unknowns, dependencies, things that could go wrong>
```

4. **Map requirements to source items**: every FR-NNN should reference which source it addresses (e.g., `FR-001 (from: .kiln/feedback/2026-04-22-scope-creep.md)` or `FR-005 (from: .kiln/issues/broken-button.md)`)
5. **Prioritize**: within a theme, order by feedback-first, then by severity (critical > high > medium > low; for issues: blocking > high > medium > low)

## Step 5: Update Source Status (Both Feedback and Issues)

After the PRD is written, update each included source item — feedback or issue. The protocol is identical (FR-013, Contract 3 status-update rule):

- Change `status: open` → `status: prd-created`
- Append a new frontmatter key: `prd: docs/features/<date>-<slug>/PRD.md`

Both `.kiln/issues/*.md` and `.kiln/feedback/*.md` files get the same update. Source type is irrelevant to the update protocol.

## Step 6: Report

```markdown
## PRD Created

**Location**: docs/features/<date>-<slug>/PRD.md
**Addresses**: N items (F feedback + I issues)
**Requirements**: N functional requirements

### Included feedback:
- [x] <title> — <severity> / <area>

### Included issues:
- [x] <title> — <severity>

### Remaining open items: F feedback + I issues

**Next step**: Review the PRD, then run `/kiln:kiln-build-prd <slug>` to execute the full pipeline.
```

## Rules

- Never delete feedback or issue entries — only update their status
- If the user has no parent PRD (`docs/PRD.md` doesn't exist), the generated PRD is standalone — don't require a parent
- Don't invent requirements that aren't backed by a source item — the PRD should address what was reported, nothing more
- If an issue item references a GitHub issue, include the issue number in the PRD for traceability (feedback has no GitHub issue column)
- Keep the PRD focused — if themes are too different to fit in one coherent PRD, suggest splitting into multiple PRDs
- Feedback leads the narrative — do NOT bury a feedback theme beneath tactical issues in the PRD body (FR-012)
- Don't auto-commit — let the user review first
