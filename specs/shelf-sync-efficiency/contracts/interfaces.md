# Interface Contracts: Shelf Full Sync v4

**Feature**: shelf-sync-efficiency
**Artifact**: `plugin-shelf/workflows/shelf-full-sync.json` (v4)
**Date**: 2026-04-10

This file is the single source of truth for the v4 workflow shape. The implementer MUST match every step ID, type, input source, output path, and JSON schema below exactly. If a signature needs to change, update this file FIRST.

---

## 1. Workflow top-level

```json
{
  "name": "shelf-full-sync",
  "version": "4.0.0",
  "steps": [ ... ]
}
```

- `name`: MUST be the literal string `"shelf-full-sync"` (FR-004).
- `version`: MUST be `"4.0.0"`.
- `steps`: ordered array of ten step objects, exactly in the order listed in §2.

---

## 2. Step list (ordered)

| # | id | type | terminal |
|---|---|---|---|
| 1 | `gather-repo-state` | command | no |
| 2 | `read-shelf-config` | command | no |
| 3 | `fetch-github-issues` | command | no |
| 4 | `read-backlog-issues` | command | no |
| 5 | `read-feature-prds` | command | no |
| 6 | `detect-tech-stack` | command | no |
| 7 | `obsidian-discover` | **agent** | no |
| 8 | `compute-work-list` | command | no |
| 9 | `obsidian-apply` | **agent** | no |
| 10 | `generate-sync-summary` | command | **yes** |

**Agent-step count**: exactly 2 (`obsidian-discover`, `obsidian-apply`). FR-001 ceiling.

---

## 3. Command step contracts (unchanged from v3)

Steps 1–6 are preserved verbatim from v3. The implementer MUST NOT modify their `command` strings.

| id | output path |
|---|---|
| gather-repo-state | `.wheel/outputs/gather-repo-state.txt` |
| read-shelf-config | `.wheel/outputs/read-shelf-config.txt` |
| fetch-github-issues | `.wheel/outputs/fetch-github-issues.txt` |
| read-backlog-issues | `.wheel/outputs/read-backlog-issues.txt` |
| read-feature-prds | `.wheel/outputs/read-feature-prds.txt` |
| detect-tech-stack | `.wheel/outputs/detect-tech-stack.txt` |

---

## 4. `obsidian-discover` (agent step, #7)

### Purpose
List current Obsidian state for the project and emit a compact index so `compute-work-list` can do deterministic diffing.

### Contract

```json
{
  "id": "obsidian-discover",
  "type": "agent",
  "instruction": "<see §4.2>",
  "context_from": ["read-shelf-config"],
  "output": ".wheel/outputs/obsidian-index.json"
}
```

### 4.1 `context_from` — exactly one entry

- `read-shelf-config` — only to resolve `base_path` and `slug`.
- MUST NOT include `fetch-github-issues`, `read-backlog-issues`, `read-feature-prds`, `detect-tech-stack`, or `gather-repo-state`. The discovery agent does not need them.

### 4.2 Agent instructions — required behavior

The agent MUST:
1. Parse `base_path` and `slug` from the `read-shelf-config` output.
2. Verify the project dashboard exists:
   `mcp__obsidian-projects__read_file({ path: "{base_path}/{slug}/{slug}.md" })`
   - If missing: emit `{"project_exists": false, "issues": [], "docs": [], "dashboard": null}` and stop.
3. List existing issue notes:
   `mcp__obsidian-projects__list_files({ path: "{base_path}/{slug}/issues" })`
4. List existing doc notes:
   `mcp__obsidian-projects__list_files({ path: "{base_path}/{slug}/docs" })`
5. For each existing issue/doc note, read it and extract `last_synced`, `type`, `status`, `github_number` (if present), `source` (if present) from frontmatter. DO NOT include the note body in the index.
6. Read the dashboard and emit its current frontmatter as-is, plus the names of the top-level markdown sections (`## Section Name` lines only — not their contents).
7. Write the resulting index JSON to the output file in the shape in §4.3.

### 4.3 Output JSON schema — `.wheel/outputs/obsidian-index.json`

```json
{
  "project_exists": true,
  "base_path": "projects",
  "slug": "ai-repo-template",
  "dashboard": {
    "frontmatter": {
      "type": "project",
      "status": "in-progress",
      "next_step": "string",
      "last_updated": "YYYY-MM-DD",
      "tags": ["language/javascript", "infra/github-actions"],
      "...other fields...": "..."
    },
    "section_headings": ["About", "Human Needed", "Feedback", "Feedback Log", "..."]
  },
  "issues": [
    {
      "path": "projects/ai-repo-template/issues/my-issue.md",
      "filename_slug": "my-issue",
      "last_synced": "2026-04-07T10:00:00Z",
      "status": "open",
      "github_number": 42,
      "source": "GitHub #42"
    }
  ],
  "docs": [
    {
      "path": "projects/ai-repo-template/docs/2026-04-10-feature.md",
      "filename_slug": "2026-04-10-feature",
      "last_synced": "2026-04-07T10:00:00Z",
      "prd_path": "docs/features/2026-04-10-feature/PRD.md"
    }
  ]
}
```

- MUST be valid JSON (parseable by `jq .`).
- MUST NOT contain any note body content. Only frontmatter-derived fields + section headings.

---

## 5. `compute-work-list` (command step, #8)

### Purpose
Pure deterministic diff: join repo state with the Obsidian index and compute exactly which notes need to be created, updated, closed, or skipped. Also compute the dashboard tag delta and the progress entry. Agents receive only the output of this step.

### Contract

```json
{
  "id": "compute-work-list",
  "type": "command",
  "command": "<Bash + jq pipeline, see §5.1>",
  "output": ".wheel/outputs/compute-work-list.json"
}
```

### 5.1 Command behavior

The command MUST, using only Bash 5.x + `jq`:
1. Parse `base_path` and `slug` from `.wheel/outputs/read-shelf-config.txt`.
2. Parse `.wheel/outputs/fetch-github-issues.txt` (GitHub issues JSON array).
3. Parse `.wheel/outputs/read-backlog-issues.txt` (backlog listing).
4. Parse `.wheel/outputs/read-feature-prds.txt` (PRD listing, one record per line).
5. Parse `.wheel/outputs/detect-tech-stack.txt` (tech-stack detection).
6. Parse `.wheel/outputs/gather-repo-state.txt` (recent commits + counts + task progress).
7. Parse `.wheel/outputs/obsidian-index.json` (Obsidian current state from step #7).
8. For each GitHub issue and each backlog issue: compute target path, determine action (`create` | `update` | `close` | `skip`) by comparing `updatedAt`/source state with the index's `last_synced`.
9. For each PRD: compute target path and determine action (`create` | `update` | `skip`) by comparing content hash with index.
10. Compute the dashboard tag delta: `{add: [...], remove: [...]}` by comparing detected tags against the index's `dashboard.frontmatter.tags`. If unchanged, emit `{add: [], remove: []}`.
11. Compute the progress entry payload from `gather-repo-state.txt`: `{yyyymm, date, summary, outcomes, links}`. `summary`, `outcomes`, and `links` are deterministic string extractions from the repo state file — no LLM, no judgment calls.
12. Emit the work list JSON (§5.2) to the output path.

### 5.2 Output JSON schema — `.wheel/outputs/compute-work-list.json`

```json
{
  "base_path": "projects",
  "slug": "ai-repo-template",
  "project_exists": true,
  "issues": [
    {
      "action": "create",
      "path": "projects/ai-repo-template/issues/my-issue.md",
      "filename_slug": "my-issue",
      "frontmatter": {
        "type": "issue",
        "status": "open",
        "severity": "medium",
        "source": "GitHub #42",
        "github_number": 42,
        "project": "[[ai-repo-template]]",
        "tags": ["source/github", "severity/medium", "type/bug", "category/hooks"],
        "last_synced": "2026-04-10T12:00:00Z"
      },
      "title": "my issue",
      "body": "<pre-rendered body markdown>"
    }
  ],
  "docs": [
    {
      "action": "update",
      "path": "projects/ai-repo-template/docs/2026-04-10-feature.md",
      "filename_slug": "2026-04-10-feature",
      "frontmatter": { "type": "doc", "...": "..." },
      "title": "Feature X",
      "body": "<pre-rendered body markdown>"
    }
  ],
  "dashboard": {
    "needs_update": true,
    "path": "projects/ai-repo-template/ai-repo-template.md",
    "frontmatter_patch": {
      "tags": ["language/typescript", "framework/react", "infra/github-actions"],
      "status": "in-progress",
      "next_step": "wire up v4",
      "last_updated": "2026-04-10"
    },
    "preserve_sections": ["About", "Human Needed", "Feedback", "Feedback Log"]
  },
  "progress": {
    "needs_update": true,
    "path": "projects/ai-repo-template/progress/2026-04.md",
    "create_if_missing": true,
    "append_entry": {
      "date": "2026-04-10",
      "summary": "string",
      "outcomes": ["string", "string"],
      "links": ["string"]
    }
  },
  "counts": {
    "issues": { "create": 0, "update": 0, "close": 0, "skip": 0 },
    "docs":   { "create": 0, "update": 0, "skip": 0 }
  }
}
```

- Every `action: "create"` or `action: "update"` entry MUST include the fully-rendered `frontmatter` object and `body` string. The apply agent does NOT perform any templating — it only writes what the work list dictates.
- Every `action: "skip"` or `action: "close"` entry MAY omit `body`.
- `dashboard.frontmatter_patch` is a partial frontmatter merge; the apply agent MUST merge these fields into the existing dashboard frontmatter without removing any other fields.
- `preserve_sections` is an explicit reminder to the apply agent of sections it MUST NOT modify.

---

## 6. `obsidian-apply` (agent step, #9)

### Purpose
Consume the work list and apply all Obsidian writes. No decisions, no templating, no diffing.

### Contract

```json
{
  "id": "obsidian-apply",
  "type": "agent",
  "instruction": "<see §6.2>",
  "context_from": ["read-shelf-config", "compute-work-list"],
  "output": ".wheel/outputs/obsidian-apply-results.json"
}
```

### 6.1 `context_from` — exactly two entries

- `read-shelf-config` — for `base_path` + `slug` (cheap, redundant but explicit).
- `compute-work-list` — the work list JSON.
- MUST NOT include `fetch-github-issues`, `read-backlog-issues`, `read-feature-prds`, `detect-tech-stack`, `gather-repo-state`, or `obsidian-index.json`. FR-002 / FR-013.

### 6.2 Agent instructions — required behavior

The agent MUST:
1. Read the work list from `.wheel/outputs/compute-work-list.json`.
2. If `project_exists: false`, emit `{"skipped": "no-project", "errors": []}` and stop.
3. For each entry in `issues` and `docs`:
   - `skip`/`close` actions with body omitted → update frontmatter only (for `close`) or do nothing (for `skip`).
   - `create` → `mcp__obsidian-projects__create_file({ path, content })` where `content` is the YAML frontmatter block from the entry followed by `# {title}` and the `body`.
   - `update` → `mcp__obsidian-projects__update_file({ path, content })` with the same content shape.
4. For `dashboard.needs_update: true`:
   - `mcp__obsidian-projects__read_file` the dashboard once.
   - Merge `frontmatter_patch` into its frontmatter (keys in patch overwrite; other keys preserved).
   - Preserve every section in `preserve_sections` byte-for-byte.
   - `mcp__obsidian-projects__update_file` once with the combined result.
5. For `progress.needs_update: true`:
   - Read the target file if it exists.
   - If missing and `create_if_missing: true`, create it with the standard progress header.
   - Append the `append_entry` formatted as the v3 progress entry (h2 date heading, Summary, Key outcomes, Links).
   - Use `update_file` (or `create_file` on first create) — exactly one MCP call per progress file.
6. Emit a results JSON (§6.3) to the output path.

The agent MUST NOT make any MCP `list_files` calls. All listing was done in `obsidian-discover`.

### 6.3 Output JSON schema — `.wheel/outputs/obsidian-apply-results.json`

```json
{
  "issues": { "created": 0, "updated": 0, "closed": 0, "skipped": 0 },
  "docs":   { "created": 0, "updated": 0, "skipped": 0 },
  "dashboard": { "updated": true, "tags_added": 2, "tags_removed": 0 },
  "progress": { "file": "projects/ai-repo-template/progress/2026-04.md", "appended": true },
  "errors": [
    { "step": "string", "path": "string", "message": "string" }
  ]
}
```

- `errors` MUST be an array (possibly empty). Every MCP failure MUST be captured here; the agent MUST NOT abort on first error — it MUST continue and record.

---

## 7. `generate-sync-summary` (terminal command step, #10)

### Purpose
Produce the terminal summary file at `.wheel/outputs/shelf-full-sync-summary.md`. Shape MUST match v3 for FR-005 / SC-006.

### Contract

```json
{
  "id": "generate-sync-summary",
  "type": "command",
  "command": "<Bash, see §7.1>",
  "output": ".wheel/outputs/shelf-full-sync-summary.md",
  "terminal": true
}
```

### 7.1 Command behavior

Reads `.wheel/outputs/compute-work-list.json` and `.wheel/outputs/obsidian-apply-results.json` via `jq`. Emits markdown with EXACTLY these sections in this order:

```markdown
# Shelf Full Sync Summary

**Date**: YYYY-MM-DD HH:MM:SS
**Project**: {slug}

## Issues
- Created: N
- Updated: N
- Closed: N
- Skipped: N

## Docs
- Created: N
- Updated: N
- Skipped: N

## Tags
- Added: N
- Removed: N
- Status: {changed|unchanged}

## Progress
- Entry appended: {yes|no}

## Errors
- Count: N
```

The five section headings MUST be exactly `## Issues`, `## Docs`, `## Tags`, `## Progress`, `## Errors` in this order.

---

## 8. Snapshot-diff harness contracts

### 8.1 `plugin-shelf/scripts/obsidian-snapshot-capture.sh`

```
Usage: obsidian-snapshot-capture.sh <base_path> <slug> <output_json>
```

- Walks every file under `{base_path}/{slug}/` in the live Obsidian vault via `mcp__obsidian-projects__list_files` + `read_file` (invoked through a temporary agent or via direct filesystem access if the vault is on disk — the implementer chooses based on availability).
- For each file, emits an object `{ path, frontmatter, body_sha256 }` where `frontmatter` is the YAML frontmatter parsed into a sorted-key JSON object with `last_synced` and `last_updated` normalized to `"<timestamp>"`, and `body_sha256` is the SHA-256 of the body with trailing whitespace trimmed from every line.
- Writes the resulting array to `<output_json>` sorted by `path`.
- Exit 0 on success, non-zero on failure.

### 8.2 `plugin-shelf/scripts/obsidian-snapshot-diff.sh`

```
Usage: obsidian-snapshot-diff.sh <baseline.json> <candidate.json>
```

- Reads both JSON files.
- Prints a human-readable diff: added files, removed files, changed files (with which fields differ).
- Exit 0 if identical, 1 if any differences, 2 on error.

---

## 9. Change control

Any change to §1–§8 during implementation MUST:
1. Update this file first.
2. Be committed with a message prefixed `contracts:` explaining the reason.
3. Be applied to `plugin-shelf/workflows/shelf-full-sync.json` immediately afterward.

No implementation work may drift from this contract silently.
