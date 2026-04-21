---
name: shelf-status
description: Display a formatted project status summary from Obsidian. Shows status, next step, latest progress, open issue count, and human-needed items. Read-only — does not modify anything.
---

# shelf:shelf-status — Quick Project Status View

Display a formatted summary of the project's current state from Obsidian. This is a read-only command — it never writes or modifies any files.

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

## Step 2: Read Project Dashboard (FR-028)

```
mcp__obsidian-projects__read_file({ path: "{base_path}/{slug}/{slug}.md" })
```

- If not found: suggest "No project found — run `/shelf:shelf-create` first" and STOP (FR-028)
- If MCP fails: warn "MCP server unavailable — cannot read project status" and STOP (NFR-004)

## Step 3: Parse Dashboard Frontmatter (FR-024, FR-003)

Extract from YAML frontmatter:
- `status` — current project status
- `next_step` — what to do next
- `last_updated` — when the project was last updated
- `tags` — tech stack and category tags
- `repo` — repository URL
- `project` — backlink to project dashboard (e.g., `"[[slug]]"`) — display if present

## Step 4: Read Latest Progress Entry (FR-025)

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

## Step 5: Count Open Issues (FR-026)

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

Note: Issue notes now include `project`, `tags`, `source`, `severity` fields in frontmatter (from template system). Parse these for richer display if present.

**If MCP fails**: warn "Could not read issues" and continue (NFR-004)

## Step 6: Extract Human Needed Items (FR-027)

From the dashboard content (already read in Step 3), parse the `## Human Needed` section:
- Extract all `- [ ]` (pending) and `- [x]` (completed) items
- Count pending vs completed

## Step 7: Display Formatted Summary

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

## Status Label Validation (FR-013)

Before setting or displaying a project status, read the canonical status list from `plugin-shelf/status-labels.md`.

- If the status is in the canonical list: use it as-is
- If the status matches a non-canonical equivalent: normalize to the canonical value and warn the user
- If the status is unrecognized: warn "Unknown status '{value}' — canonical values are: idea, active, paused, blocked, completed, archived"

When displaying status, if the stored value is a non-canonical equivalent, show the canonical value with a note: "Status: active (normalized from 'in-progress')"

## Rules

- **Read-only** — this skill NEVER writes or modifies any files in Obsidian
- **All reads go through MCP** — never read directly from the filesystem for Obsidian content (NFR-001)
- **No hardcoded vault paths** — always use the resolved base path (NFR-002, NFR-003)
- **Graceful degradation** — if MCP is unavailable, warn and exit cleanly (NFR-004)
- **Partial results** — if some sections can't be read, display what's available with notes about missing sections
