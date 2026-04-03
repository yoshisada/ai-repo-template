---
name: shelf-sync
description: Sync issues from GitHub and the local backlog to Obsidian. Creates or updates issue notes with frontmatter tracking status, severity, source, and last synced timestamp. Skips unchanged issues.
---

# shelf-sync — Sync Issues to Obsidian

Pull open issues from GitHub and `.kiln/issues/` into Obsidian as individual issue notes. Updates existing notes, closes resolved ones, and skips anything unchanged since the last sync.

## User Input

```text
$ARGUMENTS
```

No arguments required. This command is fully automatic.

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

## Step 2: Verify Project Exists

```
mcp__obsidian-projects__read_file({ path: "{base_path}/{slug}/{slug}.md" })
```

- If not found: suggest "No project found — run `/shelf-create` first" and STOP
- If MCP fails: warn "MCP server unavailable — cannot sync issues" and STOP (NFR-004)

## Step 3: Fetch GitHub Issues (FR-013)

Run:
```bash
gh issue list --state all --json number,title,state,labels,body,updatedAt --limit 100
```

- If `gh` is not installed or not authenticated: warn "GitHub CLI not authenticated — skipping GitHub issues" and continue with backlog-only sync
- Parse the JSON output into a list of issues

## Step 4: Read Backlog Issues (FR-014)

Check if `.kiln/issues/` directory exists:
```bash
ls .kiln/issues/*.md 2>/dev/null
```

- If directory doesn't exist or is empty: skip backlog sync
- If files exist: read each `.md` file and extract title, type, severity from frontmatter

## Step 5: Read Existing Obsidian Issue Notes

List current issue notes in Obsidian:
```
mcp__obsidian-projects__list_files({ path: "{base_path}/{slug}/issues" })
```

For each existing note (excluding `.gitkeep`):
```
mcp__obsidian-projects__read_file({ path: "{base_path}/{slug}/issues/{filename}" })
```

Extract `last_synced` and `source` from frontmatter to determine which issues need updating.

**If MCP fails**: warn and continue with what we have (NFR-004)

## Step 6: Determine Sync Actions (FR-017)

For each issue (GitHub + backlog), compare with existing Obsidian notes:

1. **New issue** (no matching Obsidian note): create
2. **Changed issue** (`updatedAt` > `last_synced`): update
3. **Unchanged issue** (`updatedAt` <= `last_synced`): skip (FR-017)
4. **Closed GitHub issue** with open Obsidian note: update to `status: closed` (FR-016)

Track counters: `created`, `updated`, `closed`, `skipped`

## Step 7: Generate Slug Filenames (FR-018)

For each issue that needs a note, generate a human-readable slug from the title:

1. Lowercase the title
2. Replace non-alphanumeric characters with hyphens
3. Collapse multiple hyphens into one
4. Trim leading/trailing hyphens
5. Truncate to 60 characters max
6. Append `.md`

Example: "Fix sidebar overflow on mobile" -> `fix-sidebar-overflow-on-mobile.md`

## Step 8: Create/Update Issue Notes (FR-013, FR-014, FR-015, FR-016, FR-018)

For each issue that needs creating or updating:

**For GitHub issues** (source: `github`):
```
mcp__obsidian-projects__create_file or update_file({
  path: "{base_path}/{slug}/issues/{slug-from-title}.md",
  content: "---
type: issue
status: {open or closed}
severity: {from labels: bug=high, enhancement=medium, else=medium}
source: \"GitHub #{number}\"
github_number: {number}
last_synced: {ISO 8601 timestamp}
---

# {title}

{body}

---
*Synced from GitHub issue #{number}*
"
})
```

**For backlog issues** (source: `backlog`):
```
mcp__obsidian-projects__create_file or update_file({
  path: "{base_path}/{slug}/issues/{slug-from-title}.md",
  content: "---
type: issue
status: open
severity: {from backlog frontmatter or medium}
source: \"backlog:{filename}\"
last_synced: {ISO 8601 timestamp}
---

# {title}

{body}

---
*Synced from .kiln/issues/{filename}*
"
})
```

**If any individual MCP call fails**: warn for that issue, increment an error counter, and continue with the rest (NFR-004)

## Step 9: Report Results

Print a sync summary:

```
Issue sync complete for '{slug}'.

  Created:   {N} new issue notes
  Updated:   {N} existing notes
  Closed:    {N} notes marked closed
  Skipped:   {N} unchanged
  {if errors: "Errors:    {N} failed (see warnings above)"}

Sources:
  - GitHub: {N} issues ({N} open, {N} closed)
  - Backlog: {N} items from .kiln/issues/
```

## Rules

- **All writes go through MCP** — never write directly to the filesystem for Obsidian content (NFR-001, FR-006)
- **No hardcoded vault paths** — always use the resolved base path (NFR-002, NFR-003)
- **Graceful degradation** — if MCP or gh CLI is unavailable, warn and continue with available sources (NFR-004)
- **No secrets in notes** — do not include API keys, tokens, or credentials (NFR-005)
- **Skip unchanged** — never rewrite an issue note that hasn't changed (FR-017)
- **Human-readable slugs** — filenames must be readable, not numeric IDs (FR-018)
