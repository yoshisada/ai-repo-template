---
name: shelf-release
description: Record a release in Obsidian. Creates a release note with auto-generated changelog from git history, and appends a progress entry marking the release event.
---

# shelf:shelf-release — Record a Release

Create a release note in Obsidian with an auto-generated changelog from git history. Also appends a progress entry documenting the release event.

## User Input

```text
$ARGUMENTS
```

Parse these optional flags from the arguments:
- `--version "1.2.0"` — version override
- `--summary "text"` — human-readable one-liner for the release

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

## Step 2: Detect Version (FR-035)

If `--version` was provided, use it. Otherwise, auto-detect in order:

1. Read `VERSION` file: `cat VERSION`
2. Read from `package.json`: `node -p "require('./package.json').version"` (if package.json exists)
3. Read from git tags: `git describe --tags --abbrev=0`

If none found, ask the user: "Could not detect version. What version is this release?"

Store as `$VERSION`.

## Step 3: Check for Duplicate Release (FR-038)

```
mcp__obsidian-projects__read_file({ path: "{base_path}/{slug}/releases/v{version}.md" })
```

- If the file exists: warn **"Release note already exists for v{version}. Aborting to avoid overwriting."** and STOP
- If not found (error): proceed

**If MCP fails for other reasons**: warn "MCP server unavailable — cannot create release note" and STOP (NFR-004)

## Step 4: Generate Changelog (FR-036)

Find the previous release tag:
```bash
git tag --sort=-version:refname | head -5
```

If a previous tag exists, generate changelog between that tag and HEAD:
```bash
git log {previous_tag}..HEAD --oneline --no-decorate
```

Also find merged PRs:
```bash
git log {previous_tag}..HEAD --merges --oneline
```

If no previous tag exists, use the last 20 commits:
```bash
git log -20 --oneline --no-decorate
```

Format the changelog as a markdown list:
```markdown
- {commit_hash} {commit_message}
- {commit_hash} {commit_message} (PR #{number})
```

## Step 5: Resolve Summary (FR-037)

If `--summary` was provided, use it.

If not, ask the user: "One-liner summary for this release?" and wait for a response.

## Step 6: Create Release Note (FR-034, FR-003, FR-004, FR-005)

**Template resolution** (FR-004): Read the release template. First check if `.shelf/templates/release.md` exists in the repo. If it does, use that. Otherwise, use `plugin-shelf/templates/release.md`.

Replace placeholders in the template:
- `{version}` — the release version
- `{date}` — today `YYYY-MM-DD`
- `{summary}` — one-liner release summary
- `{changelog}` — formatted changelog entries
- `{slug}` — project slug (for `project: "[[{slug}]]"` backlink, FR-005)

The template includes `tags: status/implemented` (FR-008).

```
mcp__obsidian-projects__create_file({
  path: "{base_path}/{slug}/releases/v{version}.md",
  content: "{rendered release template}"
})
```

**If MCP fails**: warn "Could not create release note" and STOP (NFR-004)

## Step 7: Append Progress Entry (FR-039)

Follow the same pattern as shelf:shelf-update for appending a progress entry:

1. Determine current month: `YYYY-MM`
2. Read or create the monthly progress file:
   ```
   mcp__obsidian-projects__read_file({ path: "{base_path}/{slug}/progress/{YYYY-MM}.md" })
   ```
   If not found, create it with a header.

3. Append a release progress entry:
   ```
   mcp__obsidian-projects__update_file({
     path: "{base_path}/{slug}/progress/{YYYY-MM}.md",
     content: "{existing_content}\n\n## {YYYY-MM-DD}\n\n**Summary**: Released v{version} — {summary}\n\n**Links**: [Release note](../releases/v{version}.md)\n"
   })
   ```

**If MCP fails**: warn "Could not append progress entry" and continue (NFR-004)

## Step 8: Report Results

```
Release v{version} recorded in Obsidian.

  Release note: {base_path}/{slug}/releases/v{version}.md
  Progress:     Appended to progress/{YYYY-MM}.md
  Changelog:    {N} commits since {previous_tag or 'initial'}

Summary: {summary}
```

## Rules

- **All writes go through MCP** — never write directly to the filesystem for Obsidian content (NFR-001)
- **No hardcoded vault paths** — always use the resolved base path (NFR-002, NFR-003)
- **Graceful degradation** — if MCP is unavailable, warn and exit cleanly (NFR-004)
- **No secrets in notes** — do not include API keys, tokens, or credentials (NFR-005)
- **Idempotency guard** — always check for existing release note before creating (FR-038)
- **Auto-detect version** — try VERSION, package.json, git tags before asking the user (FR-035)
