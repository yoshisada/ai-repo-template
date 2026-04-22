---
name: shelf-sync
description: Sync issues, docs, and tech tags from GitHub and the local repo to Obsidian. Creates/updates issue notes with templates and tags, closes archived issues, syncs PRD summaries as doc notes, and refreshes tech stack tags on the dashboard.
---

# shelf:shelf-sync — Sync Issues, Docs & Tags to Obsidian

Pull open issues from GitHub and `.kiln/issues/` into Obsidian as individual issue notes. Updates existing notes, closes archived ones, syncs PRD summaries as doc notes, refreshes tech stack tags, and skips anything unchanged since the last sync.

> **Change (Apr 2026)**: `shelf-sync` no longer nests `shelf:shelf-propose-manifest-improvement` as an inline workflow step. Reflection is a separate concern now — invoked by the `/kiln:kiln-report-issue` background sub-agent on a counter-gated cadence, or manually via `/shelf:shelf-propose-manifest-improvement`. If you previously relied on `shelf-sync` to fire reflection, invoke it directly.

## User Input

```text
$ARGUMENTS
```

No arguments required. The workflow's `read-shelf-config` step resolves project identity from `.shelf-config` (or git remote defaults).

## Steps

### 1. Parse Input

If the user passed a project-name argument, note it for the workflow. Otherwise the workflow derives identity from `.shelf-config` or git remote.

### 2. Run Workflow

Delegate to the `shelf:shelf-sync` wheel workflow — the single source of truth for sync logic:

```
/wheel:wheel-run shelf:shelf-sync
```

The workflow executes these steps in order:
1. **gather-repo-state** — captures branch, version, recent commits
2. **read-shelf-config** — resolves `base_path`, `slug`, dashboard path
3. **fetch-github-issues** — pulls open/closed GitHub issues (graceful skip if `gh` unavailable)
4. **read-backlog-issues** — reads `.kiln/issues/*.md` frontmatter + bodies
5. **read-feature-prds** — reads `docs/features/*/PRD.md` for doc notes
6. **detect-tech-stack** — scans for config files (package.json, Cargo.toml, etc.) to derive tech tags
7. **read-sync-manifest** — reads `.shelf-sync.json` to know what's been synced before
8. **compute-work-list** — diffs current state against manifest to produce per-note actions (create/update/close/skip)
9. **obsidian-apply** — agent step; applies the work list via Obsidian MCP (upserts notes, refreshes dashboard tags)
10. **update-sync-manifest** — writes the new sync state to `.shelf-sync.json`
11. **generate-sync-summary** — prints the counters (created/updated/closed/skipped, tags added/removed, errors)
12. **self-improve** — agent step; optional reflection on this sync run

### 3. Report Results

After the workflow completes, the `generate-sync-summary` step prints the canonical output (issue/doc/tag counters + error count). Relay it to the user as-is; no additional summary needed.

## Rules

- **All writes go through the wheel workflow** — do NOT reimplement sync logic in this skill body. If logic needs to change, change `plugin-shelf/workflows/shelf-sync.json`.
- **Graceful degradation** — if `gh` or Obsidian MCP is unavailable, the workflow's individual steps handle fallback. Do NOT short-circuit this skill to bypass the workflow.
- **Status label canonicalization** — the workflow's `obsidian-apply` step enforces canonical status labels from `plugin-shelf/status-labels.md`.
