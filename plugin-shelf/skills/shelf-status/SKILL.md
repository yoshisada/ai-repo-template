---
name: shelf-status
description: Display a formatted project status summary from Obsidian. Shows status, next step, latest progress, open issue count, and human-needed items. Read-only — does not modify anything.
---

# shelf-status — Quick Project Status View

Display a formatted summary of the project's current state from Obsidian. This is a read-only command — it never writes or modifies any files.

## User Input

```text
$ARGUMENTS
```

No arguments required.

## Step 1: Resolve Project Slug (FR-004)

1. If the user provided a project name as an argument, use it as the slug
2. Otherwise, run: `git remote get-url origin` and extract the repo name (last path segment, strip `.git` suffix)
3. Store as `$SLUG`

## Step 2: Resolve Base Path (NFR-003)

1. Check if `.shelf-config` exists in the repo root — if so, read the `base_path` value
2. Default: `projects`

## Step 3: Read Project Dashboard (FR-028)

```
mcp__obsidian-projects__read_file({ path: "{base_path}/{slug}/{slug}.md" })
```

- If not found: suggest "No project found — run `/shelf-create` first" and STOP (FR-028)
- If MCP fails: warn "MCP server unavailable — cannot read project status" and STOP (NFR-004)

## Step 4: Parse Dashboard Frontmatter (FR-024)

Extract from YAML frontmatter:
- `status` — current project status
- `next_step` — what to do next
- `last_updated` — when the project was last updated
- `tags` — tech stack and category tags
- `repo` — repository URL

## Step 5: Read Latest Progress Entry (FR-025)

List progress files:
```
mcp__obsidian-projects__list_files({ path: "{base_path}/{slug}/progress" })
```

- If no progress files (or only `.gitkeep`): note "No progress entries yet"
- Otherwise: sort filenames descending (latest month first), read the latest file:
  ```
  mcp__obsidian-projects__read_file({ path: "{base_path}/{slug}/progress/{latest_file}" })
  ```
  Extract the last `## YYYY-MM-DD` entry from that file.

**If MCP fails**: warn "Could not read progress" and continue with other sections (NFR-004)

## Step 6: Count Open Issues (FR-026)

List issue notes:
```
mcp__obsidian-projects__list_files({ path: "{base_path}/{slug}/issues" })
```

For each file (excluding `.gitkeep`):
```
mcp__obsidian-projects__read_file({ path: "{base_path}/{slug}/issues/{filename}" })
```

Parse frontmatter and count:
- Total issues
- Open issues (`status` != `closed`)
- Closed issues (`status` == `closed`)

**If MCP fails**: warn "Could not read issues" and continue (NFR-004)

## Step 7: Extract Human Needed Items (FR-027)

From the dashboard content (already read in Step 3), parse the `## Human Needed` section:
- Extract all `- [ ]` (pending) and `- [x]` (completed) items
- Count pending vs completed

## Step 8: Display Formatted Summary

Print the complete status view:

```
# Project: {slug}

  Status:       {status}
  Next step:    {next_step or 'Not set'}
  Last updated: {last_updated or 'Never'}
  Tags:         {comma-separated tags}
  Repo:         {repo_url}

## Latest Progress

{latest progress entry content, or "No progress entries yet"}

## Issues

  Open:   {N}
  Closed: {N}
  Total:  {N}

## Human Needed

{list of pending items as "- [ ] item", or "No items requiring human attention"}
{if completed items exist: list as "- [x] item"}
```

## Rules

- **Read-only** — this skill NEVER writes or modifies any files in Obsidian
- **All reads go through MCP** — never read directly from the filesystem for Obsidian content (NFR-001)
- **No hardcoded vault paths** — always use the resolved base path (NFR-002, NFR-003)
- **Graceful degradation** — if MCP is unavailable, warn and exit cleanly (NFR-004)
- **Partial results** — if some sections can't be read, display what's available with notes about missing sections
