---
name: kiln-roadmap
description: Append items to .kiln/roadmap.md with a one-liner description. Use as "/kiln:kiln-roadmap Add support for monorepo projects".
---

# Roadmap — Capture Future Work Ideas

Appends a one-liner item to `.kiln/roadmap.md` under the appropriate theme group. Creates the roadmap file from template if it does not exist.

## User Input

```text
$ARGUMENTS
```

## Step 1: Ensure Roadmap File Exists — FR-015

Check if `.kiln/roadmap.md` exists. If not, create it from the plugin template:

```bash
if [ ! -f ".kiln/roadmap.md" ]; then
  echo "ROADMAP_MISSING=true"
else
  echo "ROADMAP_MISSING=false"
fi
```

If the roadmap file does not exist:
1. Find the roadmap template at the plugin's `templates/roadmap-template.md` path
2. Copy it to `.kiln/roadmap.md`
3. Report: "Created .kiln/roadmap.md from template."

## Step 2: Parse Item Description — FR-015

The user's input (`$ARGUMENTS`) is the item description. If no input was provided, ask the user:

> What would you like to add to the roadmap?

The item should be a concise one-liner (one sentence or phrase).

## Step 3: Identify Theme Group — FR-015

Read `.kiln/roadmap.md` and identify the available theme groups (lines starting with `## `).

Match the item to the best theme group based on its content:
- **DX Improvements**: Developer experience, tooling, ergonomics, CLI improvements, workflow enhancements
- **New Capabilities**: New features, integrations, functionality additions
- **Tech Debt**: Refactoring, cleanup, performance, code quality, dependency updates
- **General**: Anything that does not clearly fit the above categories

If unsure, default to **General**.

## Step 4: Append Item — FR-015

Append the item as a markdown bullet (`- `) under the identified theme group in `.kiln/roadmap.md`.

The item is inserted after the last existing bullet in that group, or directly after the `## ` heading if the group is empty.

Report to the user:

```
Added to roadmap under "[Theme Group]":
- [item description]
```

## Rules

- NEVER reformat or reorganize existing roadmap content — only append
- NEVER add frontmatter, dates, priorities, or status tracking to items
- Items are simple one-liner bullets — no sub-bullets, no metadata
- If the user provides multiple items separated by newlines, add each as a separate bullet
- The roadmap file is a scratchpad, not a project plan — keep it lightweight
