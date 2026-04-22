---
name: "kiln-todo"
description: "Quick task jotting without the full spec pipeline. Manage ad-hoc TODOs in .kiln/todos.md."
---

# Todo — Quick Task Management

Manage lightweight TODOs in `.kiln/todos.md` without going through the full spec pipeline.

```text
$ARGUMENTS
```

## Usage

```
/kiln:kiln-todo                   — List all open TODOs
/kiln:kiln-todo buy milk          — Add a new TODO
/kiln:kiln-todo done 2            — Mark item #2 as complete
/kiln:kiln-todo clear             — Remove all completed items
```

## Step 1: Parse Arguments — FR-013

Parse user input to determine the operation mode:

- **No arguments** → List mode (FR-014)
- **`done <N>`** → Mark done mode (FR-016)
- **`clear`** → Clear completed mode (FR-017)
- **Anything else** → Add mode — the entire argument string is the TODO text (FR-015)

## Step 2: Ensure File Exists — FR-018

Check if `.kiln/todos.md` exists. If not, create it:

```markdown
# TODOs

```

The file format is plain markdown — one checkbox item per line, compatible with any markdown viewer.

## Step 3: Execute Operation

### List Mode (no arguments) — FR-014

Read `.kiln/todos.md` and display all items with their index numbers:

```
## TODOs

1. [ ] Buy milk (2026-04-04)
2. [x] Fix login bug (2026-04-03) [done: 2026-04-04]
3. [ ] Write tests for auth module (2026-04-04)
```

If the file has no items, display: "No TODOs yet. Add one with `/kiln:kiln-todo <text>`."

### Add Mode (`/kiln:kiln-todo <text>`) — FR-015

Append a new item to `.kiln/todos.md`:

```
- [ ] <text> (<today's date>)
```

Where `<today's date>` is in `YYYY-MM-DD` format. Get today's date:

```bash
date +%Y-%m-%d
```

Display confirmation: "Added: `- [ ] <text> (<date>)`"

### Done Mode (`/kiln:kiln-todo done <N>`) — FR-016

Read `.kiln/todos.md`, find the Nth checkbox item (counting from 1), and change it from `- [ ]` to `- [x]`, appending a completion date:

```
- [x] <text> (<original-date>) [done: <today's date>]
```

If N is out of range, display: "Item #N not found. You have M items."

If item #N is already marked done, display: "Item #N is already complete."

Display confirmation: "Done: `- [x] <text>`"

### Clear Mode (`/kiln:kiln-todo clear`) — FR-017

Read `.kiln/todos.md` and remove all lines matching `- [x]`. Keep all `- [ ]` lines and any non-item lines (headers, blank lines).

Display how many completed items were removed: "Cleared N completed items. M items remaining."

If no completed items exist, display: "No completed items to clear."

## Rules

- File path is always `.kiln/todos.md` relative to repo root — FR-018
- One checkbox item per line — FR-018
- Date format is always `YYYY-MM-DD` — FR-015, FR-016
- Items are indexed starting from 1 when displayed — FR-014
- Never modify the `# TODOs` header line — FR-018
- The file must be valid markdown at all times — FR-018
