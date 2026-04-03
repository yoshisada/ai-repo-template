---
name: shelf-feedback
description: Read and process feedback from the Obsidian project dashboard. Displays items with suggested actions, then archives them to the Feedback Log with timestamps. Run at session start to pick up notes left in Obsidian.
---

# shelf-feedback — Read and Process Feedback

Surface any feedback notes left in the Obsidian project dashboard's `## Feedback` section. Display each item with a suggested action, then archive processed items to `## Feedback Log` with a timestamp.

## User Input

```text
$ARGUMENTS
```

No arguments required.

## Step 1: Resolve Project Identity (FR-005, FR-006)

Determine the project slug and base path. Priority order: explicit argument > `.shelf-config` > git remote defaults.

1. If `.shelf-config` exists in the repo root:
   a. Parse it: skip lines starting with `#` (comments) and blank lines; split each remaining line on the first `=` to get key and value; trim whitespace from both
   b. Extract `base_path` and `slug` values
   c. If both are present and non-empty: use them as `$BASE_PATH` and `$SLUG` — do NOT derive from git remote or prompt the user (FR-006). Skip to substep 4
   d. If either is missing or empty: warn ".shelf-config is malformed — missing {key}. Falling back to defaults." and continue to substep 2
2. If no valid `.shelf-config`:
   a. If the user provided a project name as an argument: use it as `$SLUG`
   b. Otherwise: run `git remote get-url origin` and extract the repo name (last path segment, strip `.git` suffix) as `$SLUG`
   c. Set `$BASE_PATH = "projects"` (default)
3. All vault paths use: `{$BASE_PATH}/{$SLUG}/...`

## Step 2: Read Project Dashboard (FR-022)

```
mcp__obsidian-projects__read_file({ path: "{base_path}/{slug}/{slug}.md" })
```

- If not found: suggest "No project found — run `/shelf-create` first" and STOP (FR-022)
- If MCP fails: warn "MCP server unavailable — cannot read feedback" and STOP (NFR-004)

Store the full dashboard content for later update.

## Step 3: Extract Feedback Section (FR-019)

Parse the dashboard content and extract everything between `## Feedback` and the next `##` heading (which should be `## Feedback Log`).

- Each feedback item is a line starting with `- ` (a markdown list item)
- Trim whitespace, ignore empty lines

## Step 4: Check for Empty Feedback (FR-023)

If no feedback items found:
- Report: "No feedback items found in the Obsidian dashboard."
- STOP — no further action needed

## Step 5: Display Feedback and Suggest Actions (FR-020)

For each feedback item, categorize it and suggest an action:

| Pattern | Category | Suggested Action |
|---------|----------|-----------------|
| Contains "fix", "bug", "broken", "error" | Fix request | "Run `/fix {issue}` or `/shelf-sync` to track as an issue" |
| Contains "add", "feature", "want", "need" | Feature request | "Consider adding to backlog via `/report-issue`" |
| Contains "scope", "plan", "rethink", "consider" | Planning note | "Note for next `/specify` or `/plan` session" |
| Contains "urgent", "asap", "blocker" | Urgent | "Priority item — address before continuing" |
| Other | General note | "Informational — noted for this session" |

Display format:

```
## Feedback from Obsidian

1. **{category}**: {feedback text}
   Suggested action: {action}

2. **{category}**: {feedback text}
   Suggested action: {action}

...
```

## Step 6: Archive to Feedback Log (FR-021, FR-005)

After displaying all items, move them from `## Feedback` to `## Feedback Log`:

1. Get the current timestamp: `[YYYY-MM-DD HH:MM]`
2. For each feedback item, prepend the timestamp: `- [YYYY-MM-DD HH:MM] {item text}`
3. Rebuild the dashboard content:
   - Clear the `## Feedback` section (leave the heading, remove all items)
   - Append the timestamped items to the `## Feedback Log` section
   - Preserve all other sections unchanged (frontmatter, Human Needed, etc.)
   - **Preserve the `project: "[[{slug}]]"` backlink and `tags:` in frontmatter** (FR-005) — do not remove these fields when rewriting

```
mcp__obsidian-projects__update_file({
  path: "{base_path}/{slug}/{slug}.md",
  content: "{rebuilt dashboard with feedback archived}"
})
```

**If MCP fails**: warn "Could not archive feedback — items will reappear next time" (NFR-004)

## Step 7: Report Results

```
Processed {N} feedback item(s).

  Archived to Feedback Log with timestamp [{YYYY-MM-DD HH:MM}].
  {if any urgent items: "URGENT items noted above — address before continuing."}
```

## Rules

- **All writes go through MCP** — never write directly to the filesystem (NFR-001)
- **No hardcoded vault paths** — always use the resolved base path (NFR-002, NFR-003)
- **Graceful degradation** — if MCP is unavailable, warn and exit cleanly (NFR-004)
- **No secrets in notes** — do not include API keys, tokens, or credentials (NFR-005)
- **Read-then-write** — always read the full dashboard before updating to avoid clobbering
- **Preserve sections** — only modify Feedback and Feedback Log; leave everything else intact
