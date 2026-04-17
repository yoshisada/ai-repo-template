# Data Model — Mistake Capture

**Date**: 2026-04-16

Five entities. All file-based — no database, no in-memory schema beyond what's already described.

---

## E1. Mistake Artifact

**Path**: `.kiln/mistakes/YYYY-MM-DD-<assumption-slug>.md`
**Owner**: Written by the `create-mistake` agent step. Never written by shelf. Never written directly by `/kiln:mistake` SKILL.md. Retained for history after filing.

### Frontmatter schema

Derived from `@manifest/types/mistake.md`. Enforced by the agent step's instruction (see contracts/interfaces.md §2).

| Field | Type | Required | Validation |
|---|---|---|---|
| `date` | ISO-8601 date `YYYY-MM-DD` | Yes | Defaults to today (UTC). |
| `status` | enum | Yes | `unresolved` \| `worked-around` \| `fixed` \| `accepted`. |
| `made_by` | string | Yes | Lowercase-kebab model ID (e.g., `claude-opus-4-7`). |
| `assumption` | string (1 sentence) | Yes | MUST start with `I `. Honesty lint rejects hedge words (contracts §2.2). |
| `correction` | string (1 sentence) | Yes | MUST start with `I `, `The `, or `It `. |
| `severity` | enum | Yes | `minor` \| `moderate` \| `major`. |
| `tags` | string array | Yes | Three-axis lint: exactly one `mistake/*`, ≥1 `topic/*`, ≥1 stack-axis tag (contracts §2.3). |

### Body schema

Five H2 sections in fixed order, every section present:

```markdown
# <Title>

## What happened
<text | _none_>

## The assumption
<text | _none_>

## The correction
<text | _none_>

## Recovery
<text | _none_>

## Prevention for future agents
<text | _none_>
```

Empty sections MUST contain the literal `_none_` on its own line. Section omission is invalid.

### Lifecycle

- **Created**: by the agent step on successful field-collection + lint + slug derivation.
- **Never modified** by the workflow or shelf after creation. Users may hand-edit, which triggers a `source_hash` change and a shelf re-propose (unless `proposal_state == "filed"` — see E3).
- **Never deleted** by the workflow or shelf. Accepted proposals leave the artifact in place as historical record.

### Filename convention

`YYYY-MM-DD-<assumption-slug>.md` where `<assumption-slug>` is derived from the `assumption` field (contracts §2.4). Collisions on the same date append `-2`, `-3`, ...

---

## E2. Proposal Note

**Path**: `@inbox/open/YYYY-MM-DD-mistake-<assumption-slug>.md`
**Owner**: Written by the `obsidian-apply` agent step (inside `shelf-full-sync`). Moved out of `@inbox/open/` by the human reviewer on acceptance.

### Frontmatter schema

See contracts/interfaces.md §5.1.

| Field | Type | Required | Notes |
|---|---|---|---|
| `type` | literal `manifest-proposal` | Yes | Per `@manifest/systems/projects.md`. |
| `kind` | literal `content-change` | Yes | PRD Non-Goal: v1 does not register a formal `mistake-draft` kind. |
| `target` | string | Yes | `@second-brain/projects/<project-slug>/mistakes/<source-filename>`. Literal path for the reviewer to target on accept. |
| `source_path` | string | Yes | Local path back to `.kiln/mistakes/<filename>`. |
| `source_hash` | string | Yes | `sha256:<hex>` of source file content, used for change detection. |
| `project` | wikilink string | Yes | `[[<project-slug>]]`. |
| `date` | ISO date | Yes | Matches source artifact. |
| `severity` | enum | Yes | Echoed from source. |
| `mistake_class` | string | Yes | The single `mistake/*` tag from source. Separated out for scannability in the inbox. |
| `tags` | string array | Yes | `mistake-draft` first, then all source tags. |
| `last_synced` | ISO-8601 UTC timestamp | Yes | Refreshed on every shelf sync that touches the proposal. |

### Body schema

See contracts/interfaces.md §5.2. Header block naming the proposal type → Summary block → full-body reproduction from the source artifact.

### Lifecycle

- **Created**: on first shelf sync after a new `.kiln/mistakes/` artifact appears.
- **Updated**: on a subsequent shelf sync if the source's `source_hash` has changed AND `proposal_state` is still `open`. Body is rewritten verbatim.
- **Filed**: when the reviewer moves the file out of `@inbox/open/` (typically to `@second-brain/projects/<slug>/mistakes/<filename>`). Shelf detects absence on next sync and transitions manifest state.

---

## E3. Sync Manifest `mistakes[]` Entry

**Location**: new top-level `mistakes[]` array in the existing sync manifest (whatever file `update-sync-manifest.sh` writes — currently `.wheel/outputs/sync-manifest.json`).

### Schema

See contracts/interfaces.md §6.

| Field | Type | Notes |
|---|---|---|
| `path` | string | Primary key — absolute/relative path of the source artifact (`.kiln/mistakes/<filename>`). |
| `filename_slug` | string | For log lines and debugging. |
| `date` | ISO date | Echoed from source. |
| `source_hash` | string | `sha256:<hex>`. Used for skip-on-unchanged (FR-013). |
| `proposal_path` | string | `@inbox/open/<proposal-filename>` — where shelf wrote (or will re-write) the proposal. |
| `proposal_state` | enum | `open` \| `filed`. Two-state machine; no reverse transition. |
| `last_synced` | ISO-8601 UTC timestamp | Updated on every sync touching this entry. |

### State machine

```text
          +---------+
          | (none)  |  -- source .kiln/mistakes/ file created
          +----+----+
               | first shelf sync
               v
          +---------+
          |  open   |  proposal exists in @inbox/open/
          +----+----+
               | reviewer moves proposal out of @inbox/open/
               v
          +---------+
          |  filed  |  never re-proposed (FR-014)
          +---------+
```

Transitions:
- `(none) → open`: first sync after source file appears.
- `open → open`: subsequent syncs where proposal still exists (hash may have changed; body may be refreshed).
- `open → filed`: `update-sync-manifest.sh`'s reconciliation step finds `proposal_path` absent from `@inbox/open/`.
- `filed → filed`: terminal; any further source edits are ignored.

---

## E4. Workflow Step Outputs

Ephemeral per-run files written under `.wheel/outputs/`. Cleared per wheel's existing conventions.

| Path | Written by | Format |
|---|---|---|
| `.wheel/outputs/check-existing-mistakes.txt` | `check-existing-mistakes.sh` (Step 1) | Plain text with two H2 sections (contracts §3). |
| `.wheel/outputs/create-mistake-result.md` | `create-mistake` agent (Step 2) | Markdown summary (contracts §2.1 step 9). |
| `.wheel/outputs/compute-work-list.json` | `compute-work-list.sh` (shelf) | JSON; adds `mistakes[]` and `counts.mistakes` sub-object (contracts §4). |
| `.wheel/outputs/obsidian-apply-results.json` | `obsidian-apply` agent (shelf) | JSON results; adds `mistakes: {created, updated, skipped}` (contracts §5). |

---

## E5. Workflow State File

**Path**: `.wheel/state_<session>_<pid>.json` during a run; archived to `.wheel/history/success/` or `.wheel/history/failure/` on completion.
**Owner**: wheel engine. Neither the skill, the workflow, nor shelf touches this directly.

No schema changes needed — the wheel engine handles this entirely. Listed here only to make explicit that every `/kiln:mistake` run produces exactly one state file (SC-004).
