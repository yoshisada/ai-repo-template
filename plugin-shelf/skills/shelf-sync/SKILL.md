---
name: shelf-sync
description: Sync issues, docs, and tech tags from GitHub and the local repo to Obsidian. Creates/updates issue notes with templates and tags, closes archived issues, syncs PRD summaries as doc notes, and refreshes tech stack tags on the dashboard.
---

# shelf-sync — Sync Issues, Docs & Tags to Obsidian

Pull open issues from GitHub and `.kiln/issues/` into Obsidian as individual issue notes. Updates existing notes, closes archived ones, syncs PRD summaries as doc notes, refreshes tech stack tags, and skips anything unchanged since the last sync.

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

## Step 8: Create/Update Issue Notes (FR-003, FR-004, FR-005, FR-006, FR-008)

**Template resolution** (FR-004): Read the issue template. First check if `.shelf/templates/issue.md` exists in the repo. If it does, use that. Otherwise, use `plugin-shelf/templates/issue.md`.

**Tag derivation** (FR-006, FR-008): For each issue, derive tags using the algorithm from `plugin-shelf/tags.md`:
1. `source/*` — GitHub issues -> `source/github`, backlog -> `source/backlog`
2. `severity/*` — From labels or frontmatter. Default: `severity/medium`
3. `type/*` — From labels or frontmatter `type` field. Default: `type/improvement`
4. `category/*` — Infer from content: mentions skills -> `category/skills`, agents -> `category/agents`, hooks -> `category/hooks`, templates -> `category/templates`, scaffold -> `category/scaffold`, else -> `category/workflow`

For each issue that needs creating or updating, replace placeholders in the template:

**For GitHub issues** (source: `github`):
- `{title}` — issue title
- `{status}` — `open` or `closed`
- `{severity}` — derived from labels (bug=high, enhancement=medium, else=medium)
- `{source}` — `GitHub #{number}`
- `{github_number}` — the issue number
- `{slug}` — project slug (for `project: "[[{slug}]]"` backlink, FR-005)
- `{source_tag}` — `source/github`
- `{severity_tag}` — derived severity tag
- `{type_tag}` — derived type tag
- `{category_tag}` — derived category tag
- `{body}` — issue body text
- `{sync_footer}` — `*Synced from GitHub issue #{number}*`
- `{last_synced}` — ISO 8601 timestamp

**For backlog issues** (source: `backlog`):
- `{source}` — `backlog:{filename}`
- `{github_number}` — `null`
- `{source_tag}` — `source/backlog`
- Other fields derived from backlog frontmatter

```
mcp__obsidian-projects__create_file or update_file({
  path: "{base_path}/{slug}/issues/{slug-from-title}.md",
  content: "{rendered issue template}"
})
```

**If any individual MCP call fails**: warn for that issue, increment an error counter, and continue with the rest (NFR-004)

## Step 9: Close Archived Issues (FR-009, FR-010)

After issue sync, check for archived backlog items that should be closed in Obsidian.

For each existing Obsidian issue note with `source: "backlog:*"`:
1. Extract the source filename from the `source` field (e.g., `backlog:my-issue.md` -> `my-issue.md`)
2. Check if the file exists at `.kiln/issues/{filename}`:
   ```bash
   ls .kiln/issues/{filename} 2>/dev/null
   ```
3. If NOT found in `.kiln/issues/`, check `.kiln/issues/completed/`:
   ```bash
   ls .kiln/issues/completed/{filename} 2>/dev/null
   ```
4. If found in `completed/`: update the Obsidian note to `status: closed` via MCP
5. Increment a `closed` counter for each note marked closed (FR-010)

**If MCP fails for any note**: warn and continue with the rest (NFR-004)

## Step 10: Sync Docs (FR-011, FR-012, FR-013)

Scan for feature PRDs and create/update doc notes in Obsidian.

1. Find all PRDs:
   ```bash
   ls docs/features/*/PRD.md 2>/dev/null
   ```

2. For each PRD found:
   a. Read the PRD file
   b. Extract the feature slug from the directory name (e.g., `docs/features/2026-04-03-shelf-sync-v2/PRD.md` -> `shelf-sync-v2`)
   c. Extract the title from the first `# ` heading
   d. Extract 1-2 sentence summary from the `## Problem Statement` section (first paragraph). If not found, fall back to `## Background` first paragraph
   e. Count `FR-` occurrences for `fr_count`
   f. Count `NFR-` occurrences for `nfr_count`
   g. Extract `Status:` field value for `doc_status`

3. **Template resolution** (FR-004): Read the doc template. First check if `.shelf/templates/doc.md` exists in the repo. If it does, use that. Otherwise, use `plugin-shelf/templates/doc.md`.

4. **Tag derivation** (FR-007, FR-008): Derive 3 tags per the contracts:
   - `doc/*` — PRD -> `doc/prd`
   - `status/*` — Map status: `Draft` -> `status/open`, `Approved` -> `status/implemented`, else -> `status/in-progress`
   - `category/*` — Infer from content using same logic as issue tags

5. **Skip unchanged** (FR-013): Check if doc note already exists in Obsidian:
   ```
   mcp__obsidian-projects__read_file({ path: "{base_path}/{slug}/docs/{feature-slug}.md" })
   ```
   If it exists and the content would be identical, skip it. Track `docs_skipped` counter.

6. Create or update the doc note:
   ```
   mcp__obsidian-projects__create_file or update_file({
     path: "{base_path}/{slug}/docs/{feature-slug}.md",
     content: "{rendered doc template}"
   })
   ```

Track counters: `docs_created`, `docs_updated`, `docs_skipped`

**If MCP fails for any doc**: warn and continue (NFR-004)

## Step 11: Refresh Tech Stack Tags (FR-014, FR-015, FR-016)

Re-detect the tech stack and update dashboard tags if they've changed.

1. **Re-detect tech stack** (FR-014): Run the same detection as `/shelf-create` Step 3:
   ```bash
   ls package.json tsconfig.json Cargo.toml pyproject.toml requirements.txt go.mod Gemfile Dockerfile docker-compose.yml 2>/dev/null
   ```
   If `package.json` exists, read it to detect framework tags.

   Use the canonical lookup table from contracts:
   | File | Tags |
   |------|------|
   | `package.json` | Parse deps for: `language/javascript` or `language/typescript`, `framework/react`, `framework/next`, `framework/vue`, `framework/express`, `framework/fastify` |
   | `tsconfig.json` | `language/typescript` |
   | `Cargo.toml` | `language/rust` |
   | `pyproject.toml` or `requirements.txt` | `language/python` |
   | `go.mod` | `language/go` |
   | `Gemfile` | `language/ruby` |
   | `Dockerfile` or `docker-compose.yml` | `infra/docker` |
   | `.github/workflows/` | `infra/github-actions` |

2. **Read current dashboard tags** (FR-015): Parse the `tags:` field from the dashboard frontmatter (already read in Step 2).

3. **Compare and update** (FR-015): If detected tags differ from current dashboard tags:
   - Compute tags added (`detected - current`) and removed (`current - detected`)
   - Update the dashboard frontmatter `tags:` field with the new detected tags via MCP:
     ```
     mcp__obsidian-projects__update_file({
       path: "{base_path}/{slug}/{slug}.md",
       content: "{dashboard with updated tags}"
     })
     ```
   - Track `tags_added` and `tags_removed` counters (FR-016)

4. If tags are unchanged: set `tags_unchanged = true` (FR-016)

**If MCP fails**: warn "Could not update dashboard tags" and continue (NFR-004)

## Step 12: Report Results (FR-010, FR-013, FR-016)

Print the enhanced sync summary with all counters:

```
Sync complete for '{slug}'.

  Issues:  {N} created, {N} updated, {N} closed, {N} skipped
  Docs:    {N} created, {N} updated, {N} skipped
  Tags:    {+N added, -N removed | unchanged}
  {if errors: "Errors:  {N} failed (see warnings above)"}

Sources:
  - GitHub: {N} issues ({N} open, {N} closed)
  - Backlog: {N} items from .kiln/issues/
  - Docs: {N} PRDs from docs/features/
```

## Rules

- **All writes go through MCP** — never write directly to the filesystem for Obsidian content (NFR-001, FR-006)
- **No hardcoded vault paths** — always use the resolved base path (NFR-002, NFR-003)
- **Graceful degradation** — if MCP or gh CLI is unavailable, warn and continue with available sources (NFR-004)
- **No secrets in notes** — do not include API keys, tokens, or credentials (NFR-005)
- **Skip unchanged** — never rewrite an issue note that hasn't changed (FR-017)
- **Human-readable slugs** — filenames must be readable, not numeric IDs (FR-018)
- **Use templates** — all note creation uses templates with tag derivation (FR-003, FR-008)
- **Backlinks on every note** — all notes include `project: "[[{slug}]]"` (FR-005)
