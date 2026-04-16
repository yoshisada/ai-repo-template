# Interface Contracts: Shelf Full Sync v5

**Feature**: shelf-sync-efficiency
**Artifact**: `plugin-shelf/workflows/shelf-full-sync.json` (v5)
**Date**: 2026-04-16

This file is the single source of truth for the v5 workflow shape. The implementer MUST match every step ID, type, input source, output path, and JSON schema below exactly. If a signature needs to change, update this file FIRST.

---

## 1. Workflow top-level

```json
{
  "name": "shelf-full-sync",
  "version": "5.0.0",
  "steps": [ ... ]
}
```

- `name`: MUST be the literal string `"shelf-full-sync"` (FR-004).
- `version`: MUST be `"5.0.0"`.
- `steps`: ordered array of eleven step objects, exactly in the order listed in §2.

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
| 7 | `read-sync-manifest` | command | no |
| 8 | `compute-work-list` | command | no |
| 9 | `obsidian-apply` | **agent** | no |
| 10 | `update-sync-manifest` | command | no |
| 11 | `generate-sync-summary` | command | **yes** |

**Agent-step count**: exactly 1 (`obsidian-apply`). FR-001 ceiling (v5 tightens from <=2 to <=1).

---

## 3. Command step contracts (unchanged from v3)

Steps 1-6 are preserved verbatim from v3. The implementer MUST NOT modify their `command` strings.

| id | output path |
|---|---|
| gather-repo-state | `.wheel/outputs/gather-repo-state.txt` |
| read-shelf-config | `.wheel/outputs/read-shelf-config.txt` |
| fetch-github-issues | `.wheel/outputs/fetch-github-issues.txt` |
| read-backlog-issues | `.wheel/outputs/read-backlog-issues.txt` |
| read-feature-prds | `.wheel/outputs/read-feature-prds.txt` |
| detect-tech-stack | `.wheel/outputs/detect-tech-stack.txt` |

---

## 4. `read-sync-manifest` (command step, #7)

### Purpose
Read the local `.shelf-sync.json` manifest and emit it as a compact JSON file for `compute-work-list` to consume. If the manifest does not exist (cold start / first run), emit an empty manifest structure.

### Contract

```json
{
  "id": "read-sync-manifest",
  "type": "command",
  "command": "<Bash, see §4.1>",
  "output": ".wheel/outputs/sync-manifest.json"
}
```

### 4.1 Command behavior

The command MUST, using only Bash 5.x + `jq`:
1. Check if `.shelf-sync.json` exists at the repo root.
2. If it exists: validate it is parseable JSON (`jq . .shelf-sync.json`), then copy it to the output path.
3. If it does NOT exist (cold start): emit the empty manifest structure (§4.2) to the output path.
4. Exit 0 on success, non-zero on JSON parse failure.

### 4.2 Manifest JSON schema — `.shelf-sync.json`

```json
{
  "version": "1.0",
  "last_synced": "2026-04-16T12:00:00Z",
  "issues": [
    {
      "github_number": 42,
      "filename_slug": "my-issue",
      "path": "projects/ai-repo-template/issues/my-issue.md",
      "source_hash": "sha256:abc123def456...",
      "last_synced": "2026-04-16T12:00:00Z"
    }
  ],
  "docs": [
    {
      "slug": "shelf-sync-efficiency",
      "path": "projects/ai-repo-template/docs/shelf-sync-efficiency.md",
      "source_hash": "sha256:abc123def456...",
      "prd_path": "docs/features/2026-04-10-shelf-sync-efficiency/PRD.md",
      "last_synced": "2026-04-16T12:00:00Z"
    }
  ]
}
```

**Empty manifest** (cold start):

```json
{
  "version": "1.0",
  "last_synced": null,
  "issues": [],
  "docs": []
}
```

**`source_hash` computation**:
- Issues: `sha256` of the JSON string `{"number": N, "updatedAt": "..."}` (changes on any GitHub update).
- Docs: `sha256` of the entire PRD file content (changes when PRD changes).

---

## 5. `compute-work-list` (command step, #8)

### Purpose
Pure deterministic diff: join repo state with the sync manifest and compute exactly which notes need to be created, updated, or skipped. Also compute the dashboard tag delta and the progress entry. The single agent receives only the output of this step.

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
7. Parse `.wheel/outputs/sync-manifest.json` (sync manifest from step #7).
8. For each GitHub issue and each backlog issue:
   - Compute `source_hash` as `sha256` of `{"number": N, "updatedAt": "..."}`.
   - Look up the issue in the manifest's `issues[]` array by `github_number`.
   - If not found in manifest: action = `create`.
   - If found and `source_hash` differs: action = `update`.
   - If found and `source_hash` matches: action = `skip`.
   - For closed issues found in manifest: action = `close`.
9. For each PRD:
   - Compute `source_hash` as `sha256` of the PRD file content.
   - Look up the doc in the manifest's `docs[]` array by `slug`.
   - If not found in manifest: action = `create`.
   - If found and `source_hash` differs: action = `update`.
   - If found and `source_hash` matches: action = `skip`.
10. Compute the dashboard tag delta: `{add: [...], remove: [...]}` by comparing detected tags against a hardcoded or config-derived expected set. If unchanged, emit `{add: [], remove: []}`.
11. Compute the progress entry payload from `gather-repo-state.txt`: `{yyyymm, date, summary, outcomes, links}`. `summary`, `outcomes`, and `links` are deterministic string extractions from the repo state file.
12. Emit the work list JSON (§5.2) to the output path.

### 5.2 Output JSON schema — `.wheel/outputs/compute-work-list.json`

```json
{
  "base_path": "projects",
  "slug": "ai-repo-template",
  "issues": [
    {
      "action": "create",
      "path": "projects/ai-repo-template/issues/my-issue.md",
      "filename_slug": "my-issue",
      "github_number": 42,
      "source_hash": "sha256:abc123...",
      "source_data": {
        "title": "my issue",
        "body": "<issue body markdown>",
        "state": "open",
        "labels": ["bug", "hooks"],
        "created_at": "2026-04-10T...",
        "updated_at": "2026-04-10T..."
      }
    },
    {
      "action": "update",
      "path": "projects/ai-repo-template/issues/other-issue.md",
      "filename_slug": "other-issue",
      "github_number": 43,
      "source_hash": "sha256:def456...",
      "source_data": {
        "title": "other issue",
        "body": "<issue body markdown>",
        "state": "open",
        "labels": ["enhancement"],
        "created_at": "2026-04-09T...",
        "updated_at": "2026-04-16T..."
      }
    }
  ],
  "docs": [
    {
      "action": "create",
      "path": "projects/ai-repo-template/docs/shelf-sync-efficiency.md",
      "filename_slug": "shelf-sync-efficiency",
      "slug": "shelf-sync-efficiency",
      "source_hash": "sha256:ghi789...",
      "prd_path": "docs/features/2026-04-10-shelf-sync-efficiency/PRD.md",
      "source_data": {
        "prd_content": "<full PRD file content>"
      }
    },
    {
      "action": "update",
      "path": "projects/ai-repo-template/docs/other-feature.md",
      "filename_slug": "other-feature",
      "slug": "other-feature",
      "source_hash": "sha256:jkl012...",
      "prd_path": "docs/features/2026-04-10-other-feature/PRD.md",
      "source_data": {
        "prd_content": "<full PRD file content>"
      }
    }
  ],
  "dashboard": {
    "needs_update": true,
    "path": "projects/ai-repo-template/ai-repo-template.md",
    "frontmatter_patch": {
      "tags": ["language/typescript", "framework/react", "infra/github-actions"],
      "status": "in-progress",
      "next_step": "wire up v5",
      "last_updated": "2026-04-16"
    },
    "preserve_sections": ["About", "Human Needed", "Feedback", "Feedback Log"]
  },
  "progress": {
    "needs_update": true,
    "path": "projects/ai-repo-template/progress/2026-04.md",
    "create_if_missing": true,
    "append_entry": {
      "date": "2026-04-16",
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

**Key differences from v4**:
- Each `issues[]` and `docs[]` entry includes `source_hash` (for manifest update) and `source_data` (raw content for the agent to use on CREATE).
- For `action: "create"`: `source_data` contains the raw content the agent needs to generate inferred fields (summary, status, tags). For issues: `title`, `body`, `state`, `labels`. For docs: `prd_content`.
- For `action: "update"`: `source_data` is still provided but the agent MUST NOT use it to regenerate inferred fields. Only programmatic fields are patched.
- For `action: "skip"`: `source_data` MAY be omitted.
- `frontmatter` is NOT pre-rendered in the work list (unlike v4). On CREATE, the agent generates frontmatter including inferred fields. On UPDATE, the agent patches only programmatic fields.
- `dashboard` and `progress` shapes are unchanged from v4.

---

## 6. `obsidian-apply` (agent step, #9)

### Purpose
Consume the work list and apply all Obsidian writes. On CREATE: generate full frontmatter including inferred fields by reading source data. On UPDATE: patch only programmatic fields, preserving inferred fields set on create.

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
- MUST NOT include `fetch-github-issues`, `read-backlog-issues`, `read-feature-prds`, `detect-tech-stack`, `gather-repo-state`, or `sync-manifest.json`. FR-002 / FR-013.

### 6.2 Agent instructions — required behavior

The agent MUST:
1. Read the work list from `.wheel/outputs/compute-work-list.json`.
2. If the work list is empty (all counts zero, dashboard `needs_update: false`, progress `needs_update: false`), emit `{"skipped": "no-work", "errors": []}` and stop.
3. For each entry in `issues`:
   - **`skip`**: Do nothing.
   - **`close`**: `mcp__obsidian-projects__patch_file({ path, frontmatter: { status: "closed", last_synced: "<now>" } })`.
   - **`create`** (FR-016): Generate full frontmatter by reading `source_data`:
     - `type`: `"issue"`
     - `status`: derived from `source_data.state` (open/closed)
     - `severity`: inferred from `source_data.labels` (bug=high, enhancement=medium, etc.)
     - `summary`: 1-line summary generated from `source_data.title` + `source_data.body`
     - `source`: `"GitHub #N"`
     - `github_number`: from the entry
     - `project`: `"[[{slug}]]"`
     - `tags`: inferred from labels — `source/github`, `severity/*`, `type/*`, `category/*`
     - `last_synced`: current ISO timestamp
     - `category`: inferred from `source_data.labels` and `source_data.body`
     - Body: rendered from `source_data.body`
     - Use `mcp__obsidian-projects__create_file({ path, content })`.
   - **`update`** (FR-015): Patch ONLY programmatic fields:
     - `source`, `github_number`, `last_synced`, `project`, `status` (from `source_data.state`)
     - Use `mcp__obsidian-projects__patch_file({ path, frontmatter: { ...programmatic fields } })`.
     - MUST NOT touch: `summary`, `tags`, `category`, `severity` (these are inferred fields, owned by human/LLM after creation).
4. For each entry in `docs`:
   - **`skip`**: Do nothing.
   - **`create`** (FR-016): Generate full frontmatter by reading `source_data.prd_content`:
     - `type`: `"doc"`
     - `status`: inferred from PRD content (e.g., "Draft", "In Progress", "Complete")
     - `summary`: 1-line description generated from reading the PRD
     - `source`: `"PRD"`
     - `prd_path`: from the entry
     - `project`: `"[[{slug}]]"`
     - `tags`: inferred from PRD content — `doc/prd`, `status/*`, `category/*`
     - `category`: inferred from PRD content
     - `last_synced`: current ISO timestamp
     - Body: rendered summary of the PRD content
     - Use `mcp__obsidian-projects__create_file({ path, content })`.
   - **`update`** (FR-015): Patch ONLY programmatic fields:
     - `source`, `prd_path`, `last_synced`, `project`
     - Use `mcp__obsidian-projects__patch_file({ path, frontmatter: { ...programmatic fields } })`.
     - MUST NOT touch: `summary`, `status`, `tags`, `category` (these are inferred fields).
5. For `dashboard.needs_update: true`:
   - `mcp__obsidian-projects__read_file` the dashboard once.
   - Merge `frontmatter_patch` into its frontmatter (keys in patch overwrite; other keys preserved).
   - Preserve every section in `preserve_sections` byte-for-byte.
   - `mcp__obsidian-projects__update_file` once with the combined result.
6. For `progress.needs_update: true`:
   - Read the target file if it exists.
   - If missing and `create_if_missing: true`, create it with the standard progress header.
   - Append the `append_entry` formatted as the standard progress entry (h2 date heading, Summary, Key outcomes, Links).
   - Use `update_file` (or `create_file` on first create) — exactly one MCP call per progress file.
   - **Note**: once `append_file` MCP tool is available, this section can be simplified to a single append call without a read. Design progress handling as an isolated block for easy upgrade.
7. Emit a results JSON (§6.3) to the output path.

The agent MUST NOT make any MCP `list_files` calls. No vault reads are needed for diffing — the manifest handles that.

### 6.3 Field classification

| Classification | Fields | Set when | Modified on update? |
|---|---|---|---|
| **Programmatic** | `source`, `github_number`, `prd_path`, `project`, `last_synced`, `status` (issues only, from GitHub state) | CREATE and UPDATE | YES — always patched |
| **Inferred** | `summary`, `tags`, `category`, `severity`, `status` (docs only, from PRD reading) | CREATE only | NO — never touched on UPDATE |

**`status` field special handling**: For issues, `status` is programmatic (reflects GitHub open/closed state and changes on update). For docs, `status` is inferred (reflects the LLM's reading of the PRD and is set only on create).

### 6.4 Output JSON schema — `.wheel/outputs/obsidian-apply-results.json`

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

## 7. `update-sync-manifest` (command step, #10)

### Purpose
After obsidian-apply completes, update `.shelf-sync.json` with the new source hashes for all items that were created or updated. This ensures the next run can detect what has changed.

### Contract

```json
{
  "id": "update-sync-manifest",
  "type": "command",
  "command": "<Bash + jq pipeline, see §7.1>",
  "output": ".wheel/outputs/update-sync-manifest.txt"
}
```

### 7.1 Command behavior

The command MUST, using only Bash 5.x + `jq`:
1. Read `.wheel/outputs/compute-work-list.json` for the list of items and their `source_hash` values.
2. Read `.wheel/outputs/obsidian-apply-results.json` for success/failure status.
3. Read the existing `.shelf-sync.json` (or start from the empty manifest if it doesn't exist).
4. For each item in the work list where the apply succeeded (no error recorded for that path):
   - `action: "create"`: Add a new entry to the manifest's `issues[]` or `docs[]` with `source_hash`, `path`, `filename_slug`/`slug`, and `last_synced` set to now.
   - `action: "update"`: Update the existing manifest entry's `source_hash` and `last_synced`.
   - `action: "close"`: Remove the entry from the manifest (closed items don't need tracking).
   - `action: "skip"`: No change to manifest.
5. For items where the apply failed (error recorded): leave the manifest entry unchanged so the next run retries.
6. Set the top-level `last_synced` to the current ISO timestamp.
7. Write the updated manifest atomically to `.shelf-sync.json` (write to `.shelf-sync.json.tmp`, then `mv` to `.shelf-sync.json`) (FR-014).
8. Write a human-readable summary to the output path: number of entries added/updated/removed/unchanged.
9. Exit 0 on success, non-zero on failure.

### 7.2 Atomicity requirement (FR-014)

The manifest MUST be updated atomically. The command writes to a temp file first, then moves it into place. This prevents a partial write from corrupting the manifest if the process is interrupted.

---

## 8. `generate-sync-summary` (terminal command step, #11)

### Purpose
Produce the terminal summary file at `.wheel/outputs/shelf-full-sync-summary.md`. Shape MUST match v3 for FR-005 / SC-006.

### Contract

```json
{
  "id": "generate-sync-summary",
  "type": "command",
  "command": "<Bash, see §8.1>",
  "output": ".wheel/outputs/shelf-full-sync-summary.md",
  "terminal": true
}
```

### 8.1 Command behavior

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

## 9. Snapshot-diff harness contracts

### 9.1 `plugin-shelf/scripts/obsidian-snapshot-capture.sh`

```
Usage: obsidian-snapshot-capture.sh <base_path> <slug> <output_json>
```

- Walks every file under `{base_path}/{slug}/` in the live Obsidian vault via `mcp__obsidian-projects__list_files` + `read_file` (invoked through a temporary agent or via direct filesystem access if the vault is on disk — the implementer chooses based on availability).
- For each file, emits an object `{ path, frontmatter, body_sha256 }` where `frontmatter` is the YAML frontmatter parsed into a sorted-key JSON object with `last_synced` and `last_updated` normalized to `"<timestamp>"`, and `body_sha256` is the SHA-256 of the body with trailing whitespace trimmed from every line.
- Writes the resulting array to `<output_json>` sorted by `path`.
- Exit 0 on success, non-zero on failure.

### 9.2 `plugin-shelf/scripts/obsidian-snapshot-diff.sh`

```
Usage: obsidian-snapshot-diff.sh <baseline.json> <candidate.json>
```

- Reads both JSON files.
- Prints a human-readable diff: added files, removed files, changed files (with which fields differ).
- Exit 0 if identical, 1 if any differences, 2 on error.

---

## 10. Change control

Any change to §1-§9 during implementation MUST:
1. Update this file first.
2. Be committed with a message prefixed `contracts:` explaining the reason.
3. Be applied to `plugin-shelf/workflows/shelf-full-sync.json` immediately afterward.

No implementation work may drift from this contract silently.
