# Data Model: Fix Skill with Recording Teams

This document enumerates every data artifact the feature produces or consumes. Each entity is specified at the level of "what fields exist, what their types are, what constraints hold, and what produces/consumes them." Wire-level schemas (JSON shape, markdown shape) are pinned in `contracts/interfaces.md`.

## Entities

### 1. Fix Envelope

**Kind**: JSON object, persisted as a transient file.

**Location**: `.kiln/fixes/.envelope-<unix-timestamp>.json` (gitignored; deleted at skill cleanup).

**Producer**: `/kiln:fix` Step 7 (via `compose-envelope.sh`).

**Consumers**: `write-local-record.sh`, `fix-record` team, `fix-reflect` team.

**Fields**: see `contracts/interfaces.md` — nine required fields.

**State transitions**: none (write-once; deleted after both teams complete).

**Validation rules**:
- All nine fields present.
- `status` ∈ {`fixed`, `escalated`}.
- `commit_hash` null ⇔ `status == "escalated"`.
- No field contains any full-line match from `.kiln/qa/.env.test` (FR-026).

### 2. Local Fix Record

**Kind**: Markdown file with YAML frontmatter and five H2 sections.

**Location**: `.kiln/fixes/<YYYY-MM-DD>-<slug>.md` (gitignored; collision-disambiguated per FR-015).

**Producer**: `write-local-record.sh`.

**Consumers**: developer (direct file read), future AI agents scanning past fixes.

**Shape**: pinned in `contracts/interfaces.md` → `write-local-record.sh` → "Rendered markdown shape" block.

**State transitions**: none (write-once; never overwritten — collisions get a new filename).

**Validation rules**:
- Frontmatter keys: `type` (const `fix`), `date`, `status`, `commit`, `resolves_issue`, `files_changed` (list), `tags` (list, empty at local-write time).
- Body sections in exact order: `## Issue`, `## Root cause`, `## Fix`, `## Files changed`, `## Escalation notes`.

### 3. Obsidian Fix Note

**Kind**: Markdown file in the Obsidian vault, schema-conformant to `@manifest/types/fix.md`.

**Location**: `@projects/<project>/fixes/<YYYY-MM-DD>-<slug>.md`.

**Producer**: `fix-record` team (via `mcp__claude_ai_obsidian-manifest__create_file`).

**Consumers**: maintainers reviewing the vault, future AI agents, Obsidian search/graph tooling.

**Shape**: mirrors the Local Fix Record plus:
- Frontmatter `tags` populated with the tag axes declared in `@manifest/types/fix.md` (FR-006).
- Body includes wikilinks per FR-007: `[[<feature-spec-path>]]` if non-null; `[[#<issue-ref>]]` or explicit URL if `resolves_issue` non-null; plain `commit_hash` text otherwise.

**Validation rules**: same as Local Fix Record plus FR-006 tag-axis requirements.

### 4. Manifest Type `fix.md`

**Kind**: Markdown file in the Obsidian vault, authored once as part of this feature.

**Locations**:
- Staging copy: `specs/fix-skill-with-recording-teams/assets/manifest-types/fix.md` (committed).
- Vault copy: `@manifest/types/fix.md` (MCP-written during implementation).

**Producer**: implementer (manual authoring; dual-write during implementation tasks).

**Consumers**: `fix-record` team (conformance validation), maintainers, `fix-reflect` team (implicitly, as a potential target).

**Shape** (modeled on `@manifest/types/mistake.md`):
- Prose intro describing what a fix note is and when it is created.
- "Required frontmatter" section listing fields + types + enum values.
- "Body sections" section listing five H2 headings in order, with prose guidance per section.
- "Tag axes" section publishing the initial vocabulary (`fix/*` values, inherited `topic/*`, inherited stack axis).
- Example note at the bottom.

### 5. Manifest-Improvement Proposal (fix-sourced)

**Kind**: Markdown file in the Obsidian vault — identical shape to `shelf:propose-manifest-improvement` proposals.

**Location**: `@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md`.

**Producer**: `fix-reflect` team, only when the exact-patch gate approves.

**Consumers**: maintainers reviewing `@inbox/open/`.

**Shape**: frontmatter `type: proposal`, `target: <@manifest/types/...md or @manifest/templates/...md>`, `date`, followed by four H2 sections in order: `## Target`, `## Current`, `## Proposed`, `## Why`.

**State transitions**: write-once; maintainer triage moves it to `@inbox/accepted/` or `@inbox/rejected/` (those transitions are out of this feature's scope — same as the upstream subroutine).

### 6. Reflect Output (transient)

**Kind**: JSON file matching the `shelf:propose-manifest-improvement` reflect-output schema.

**Location**: `.kiln/fixes/.reflect-output-<unix-timestamp>.json` (gitignored; deleted at skill cleanup).

**Producer**: `fix-reflect` team's `reflector` agent.

**Consumer**: `validate-reflect-output.sh` (invoked by the same agent).

**Shape**: either `{"skip": true}` or an object with `skip: false` plus `target`, `section`, `current`, `proposed`, `why`.

## Relationships

```text
Debug loop (unchanged)
        │
        ▼
Compose envelope (main chat)            Strip credentials (per field)
        │                                        │
        ├────────────────────────────────────────┘
        ▼
Persist envelope JSON to .kiln/fixes/.envelope-*.json
        │
        ▼
Write local record (.kiln/fixes/<date>-<slug>.md)    ◄── uses slug from derive-proposal-slug.sh
        │
        ▼
Render team briefs (substitute envelope path + scripts dir + slug + date)
        │
        ▼
Spawn teams in parallel
        ├── fix-record  ─► read envelope ─► MCP create_file ─► @projects/<project>/fixes/<date>-<slug>.md
        └── fix-reflect ─► read envelope ─► reflect output ─► validate + check-target ─► (maybe) MCP create_file ─► @inbox/open/<date>-manifest-improvement-<slug>.md
        │
        ▼
Poll tasks to completion; handle SendMessage escapes
        │
        ▼
TeamDelete both teams (regardless of outcome)
        │
        ▼
Cleanup transient files (.envelope-*, .reflect-output-*)
        │
        ▼
Print user-facing report (Local record path + Obsidian note path + commit)
```

## Lifecycle invariants

- Every terminal `/kiln:fix` invocation produces exactly one Local Fix Record (successful or escalated).
- Every Local Fix Record corresponds to at most one Obsidian Fix Note. (Zero if `project_name` resolved to null or MCP unavailable.)
- Every terminal `/kiln:fix` invocation produces at most one Manifest-Improvement Proposal. Zero is the norm (SC-002: ≥70%).
- Transient envelope and reflect-output files MUST be deleted before the skill returns control to the user.
