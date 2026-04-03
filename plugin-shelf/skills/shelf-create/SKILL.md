---
name: shelf-create
description: Scaffold a new project in Obsidian. Creates the full directory structure, dashboard with auto-detected tech stack tags, and about.md — all via MCP. Run this once per repo to initialize the Obsidian project.
---

# shelf-create — Scaffold New Project in Obsidian

Create a complete Obsidian project dashboard for the current repo. Detects tech stack, generates frontmatter tags, and scaffolds the full directory structure — all via MCP.

## User Input

```text
$ARGUMENTS
```

## Step 1: Resolve Project Slug (FR-004)

Determine the project slug:

1. If the user provided a project name as an argument, use it as the slug
2. Otherwise, run: `git remote get-url origin` and extract the repo name (last path segment, strip `.git` suffix)
3. Slugify: lowercase, replace spaces with hyphens
4. Store as `$SLUG` for all vault path construction

## Step 2: Resolve Base Path (NFR-003)

Determine the Obsidian vault base path:

1. Check if `.shelf-config` exists in the repo root — if so, read the `base_path` value
2. Default: `projects`
3. All vault paths use: `{base_path}/{slug}/...`

## Step 3: Check for Duplicate Project (FR-005)

Before creating anything, check if the project already exists:

```
mcp__obsidian-projects__list_files({ path: "{base_path}/{slug}" })
```

- If files are returned: warn the user **"Project '{slug}' already exists in Obsidian. Aborting to avoid overwriting."** and STOP
- If empty or error (not found): proceed

## Step 4: Detect Tech Stack (FR-029)

Scan the repo for known config files and map them to namespaced tags:

| File | Tags |
|------|------|
| `package.json` | Parse `dependencies` and `devDependencies` for: `language/javascript` or `language/typescript` (if typescript present), `framework/react`, `framework/next`, `framework/vue`, `framework/express`, `framework/fastify`, etc. |
| `tsconfig.json` | `language/typescript` |
| `Cargo.toml` | `language/rust` |
| `pyproject.toml` or `requirements.txt` | `language/python` |
| `go.mod` | `language/go` |
| `Gemfile` | `language/ruby` |
| `.docker` or `Dockerfile` | `infra/docker` |
| `.github/workflows/` | `infra/github-actions` |

Run bash commands to check for these files:
```bash
ls package.json tsconfig.json Cargo.toml pyproject.toml requirements.txt go.mod Gemfile Dockerfile docker-compose.yml 2>/dev/null
```

If `package.json` exists, read it to extract dependency names:
```bash
cat package.json
```

Parse the dependencies and map framework names to tags.

## Step 5: Merge Custom Tags (FR-030)

If the user passed `--tags "tag1, tag2"` as an argument:
- Split on comma, trim whitespace
- Merge with auto-detected tags (no duplicates)

Combine all tags into a YAML list for frontmatter.

## Step 6: Get Repo Metadata

Gather additional repo info:
```bash
git remote get-url origin
```

Extract the repo URL for the `repo` frontmatter field.

Read repo description if available (from `package.json` description field or similar).

## Step 7: Create Dashboard (FR-002)

Create the main project dashboard file:

```
mcp__obsidian-projects__create_file({
  path: "{base_path}/{slug}/{slug}.md",
  content: "---
type: project
status: idea
repo: {repo_url}
tags:
  - {tag1}
  - {tag2}
  ...
next_step: \"\"
last_updated: {today YYYY-MM-DD}
---

# {slug}

## Human Needed

## Feedback

## Feedback Log
"
})
```

**If MCP fails**: warn the user ("MCP server unavailable — cannot create project") and STOP. Do not attempt filesystem writes. (NFR-004)

## Step 8: Create About Doc (FR-003)

```
mcp__obsidian-projects__create_file({
  path: "{base_path}/{slug}/docs/about.md",
  content: "# About {slug}

## Description
{repo_description or 'TBD'}

## Tech Stack
{list of detected tags, formatted as bullet points}

## Architecture
TBD
"
})
```

**If MCP fails**: warn and continue to next step (partial completion). (NFR-004)

## Step 9: Create Directory Structure (FR-001)

Create placeholder files to establish the directory structure. MCP file creation implicitly creates parent directories:

```
mcp__obsidian-projects__create_file({ path: "{base_path}/{slug}/progress/.gitkeep", content: "" })
mcp__obsidian-projects__create_file({ path: "{base_path}/{slug}/releases/.gitkeep", content: "" })
mcp__obsidian-projects__create_file({ path: "{base_path}/{slug}/issues/.gitkeep", content: "" })
mcp__obsidian-projects__create_file({ path: "{base_path}/{slug}/decisions/.gitkeep", content: "" })
```

**If any MCP call fails**: warn for that specific directory and continue with the rest. (NFR-004)

## Step 10: Report Results

Print a confirmation summary:

```
Project '{slug}' created in Obsidian.

  Dashboard: {base_path}/{slug}/{slug}.md
  About:     {base_path}/{slug}/docs/about.md
  Tags:      {comma-separated tag list}

  Directories created:
    - progress/
    - releases/
    - issues/
    - decisions/

Next: Run /shelf-update to record your first progress entry.
```

If any steps had partial failures, include a warnings section listing what failed.

## Rules

- **All writes go through MCP** — never write directly to the filesystem for Obsidian content (NFR-001, FR-006)
- **No hardcoded vault paths** — always use the resolved base path (NFR-002, NFR-003)
- **Graceful degradation** — if MCP is unavailable, warn and exit cleanly; never crash (NFR-004)
- **No secrets in notes** — do not include API keys, tokens, or credentials in any created files (NFR-005)
- **Idempotency guard** — always check for existing project before creating (FR-005)
