---
name: repair
description: Re-apply current templates to an existing Obsidian project. Preserves user content (Feedback, Human Needed, Feedback Log, progress entries), normalizes status labels, and reports all changes via a diff preview.
---

# shelf:repair — Repair Existing Project

Re-apply the current dashboard template to an existing Obsidian project. Produces a diff report before making changes, preserves all user-written content, and normalizes non-canonical status labels to their canonical equivalents.

## User Input

```text
$ARGUMENTS
```

## Steps

### 1. Validate Project Exists

Check that `.shelf-config` exists in the repo root. If not, warn: "No .shelf-config found — run `/shelf:create` first or create .shelf-config manually." and STOP.

### 2. Run Workflow

Delegate to the shelf:repair wheel workflow:

```
/wheel:run shelf:repair
```

The workflow executes these steps in order:
1. **read-shelf-config** — reads project identity from `.shelf-config`
2. **read-current-template** — reads the current dashboard template
3. **read-existing-dashboard** — reads the current dashboard from Obsidian via MCP, extracts all sections
4. **generate-diff-report** — compares dashboard to template, flags non-canonical status, writes change report (FR-010)
5. **apply-repairs** — applies template structure while preserving user content (FR-009, FR-011)
6. **verify-repair** — re-reads dashboard and confirms it matches template structure

### 3. Report Results

After the workflow completes, read the outputs and report:

```
Project '{slug}' repaired in Obsidian.

  Changes applied:
  {list of structural changes from diff report}

  Content preserved:
  - Human Needed: {N} items
  - Feedback: {N} entries
  - Feedback Log: {N} entries

  Status: {canonical status} {if normalized: "(normalized from '{original}')"}

  Verification: {PASS | FAIL}
```

If verification failed, list specific issues.

## Status Label Validation (FR-013)

Before setting or displaying a project status, read the canonical status list from `plugin-shelf/status-labels.md`.

- If the status is in the canonical list: use it as-is
- If the status matches a non-canonical equivalent: normalize to the canonical value and warn the user
- If the status is unrecognized: warn "Unknown status '{value}' — canonical values are: idea, active, paused, blocked, completed, archived"

## Rules

- **All Obsidian writes go through MCP** — the workflow handles this via agent steps (NFR-001)
- **No hardcoded vault paths** — the workflow uses `.shelf-config` for path resolution (NFR-002)
- **Preserve user content** — Feedback, Human Needed, Feedback Log, and progress entries are never deleted (FR-009)
- **Diff before apply** — the workflow always generates a change report before modifying anything (FR-010)
- **Idempotent** — running shelf:repair twice produces the same result (NFR-002)
