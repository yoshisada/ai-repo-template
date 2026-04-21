---
name: shelf-create
description: Scaffold a new project in Obsidian via wheel workflow. Creates the full directory structure, dashboard with auto-detected tech stack tags, progress-based initial status, and about.md — all via MCP.
---

# shelf:shelf-create — Scaffold New Project in Obsidian

Create a complete Obsidian project dashboard for the current repo. Runs as a wheel workflow with deterministic step ordering: gathers repo data first (config, progress signals, tech stack, metadata), then navigates the vault, checks for duplicates, and creates the project structure via MCP.

## User Input

```text
$ARGUMENTS
```

## Steps

### 1. Parse Input

If the user provided a project name as an argument, note it for the workflow (the workflow's `read-shelf-config` step will use `.shelf-config` or git remote defaults if no override is given).

### 2. Run Workflow

Delegate to the shelf:shelf-create wheel workflow:

```
/wheel:run shelf:shelf-create
```

The workflow executes these steps in order:
1. **read-shelf-config** — reads `.shelf-config` or derives defaults from git remote
2. **detect-repo-progress** — inspects repo for progress signals (specs, code, tests, commits, issues)
3. **detect-tech-stack** — scans for config files and parses dependencies
4. **get-repo-metadata** — extracts git remote URL and description
5. **resolve-vault-path** — navigates from vault root to verify/create base_path (FR-003, FR-004)
6. **check-duplicate** — verifies no existing project at target path (FR-005)
7. **create-project** — creates dashboard + about + directories using templates (FR-002, FR-006)
8. **write-shelf-config** — writes `.shelf-config` to repo root if it doesn't exist

### 3. Report Results

After the workflow completes, read the outputs and report:

```
Project '{slug}' created in Obsidian.

  Dashboard:    {base_path}/{slug}/{slug}.md
  About:        {base_path}/{slug}/docs/about.md
  Status:       {inferred status from progress detection}
  Tags:         {comma-separated tag list}
  Config:       .shelf-config {written | already existed}

  Directories created:
    - progress/
    - releases/
    - issues/
    - decisions/

Next: Run /shelf:shelf-update to record your first progress entry.
```

If the workflow detected a duplicate project, report: "Project '{slug}' already exists in Obsidian. Run /shelf:shelf-repair to update it."

## Status Label Validation (FR-013)

Before setting or displaying a project status, read the canonical status list from `plugin-shelf/status-labels.md`.

- If the status is in the canonical list: use it as-is
- If the status matches a non-canonical equivalent: normalize to the canonical value and warn the user
- If the status is unrecognized: warn "Unknown status '{value}' — canonical values are: idea, active, paused, blocked, completed, archived"

## Rules

- **All Obsidian writes go through MCP** — the workflow handles this via agent steps (NFR-001)
- **No hardcoded vault paths** — the workflow navigates from vault root (NFR-002, NFR-003)
- **Graceful degradation** — if MCP is unavailable, the workflow step fails with a clear error (NFR-004)
- **No secrets in notes** — do not include API keys, tokens, or credentials (NFR-005)
- **Idempotency guard** — the workflow checks for duplicates before creating (FR-005)
