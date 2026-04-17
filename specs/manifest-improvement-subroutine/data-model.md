# Data Model: Manifest Improvement Subroutine

**Phase**: 1 (Plan) | **Date**: 2026-04-16

## Entity 1 — Reflect Output

**Location**: `.wheel/outputs/propose-manifest-improvement.json`
**Producer**: `reflect` step (agent)
**Consumer**: `write-proposal-dispatch.sh` (command sub-step of `write-proposal`)
**Visibility**: Internal, not user-surfaced.

### Schema (discriminated union)

```json
// Shape A — skip
{
  "skip": true
}

// Shape B — propose
{
  "skip": false,
  "target": "@manifest/types/<filename>.md" | "@manifest/templates/<filename>.md",
  "section": "<H2/H3 heading text, or 'lines N-M'>",
  "current": "<verbatim text currently in the target file>",
  "proposed": "<verbatim replacement text>",
  "why": "<one sentence, first-person or declarative, references a concrete run artifact>"
}
```

### Validation rules (enforced by `validate-reflect-output.sh`)

| Rule | Violation → |
|---|---|
| JSON must parse | force skip |
| Top-level `skip` key must be boolean | force skip |
| If `skip: true`, no other keys required | accept |
| If `skip: false`, all of `target`, `section`, `current`, `proposed`, `why` must be non-empty strings | force skip |
| `target` must match glob `@manifest/types/*.md` OR `@manifest/templates/*.md` | force skip |
| `current` must appear verbatim (byte-for-byte via `grep -F`) in the file at `target` path | force skip |
| `why` must contain at least one run-evidence reference — a path containing `/` OR `.wheel/` OR a filename extension (`.md`, `.json`, `.sh`, `.txt`, `.yaml`, `.yml`) | force skip |

"Force skip" means the dispatch envelope is `{"action": "skip"}` regardless of what the reflect output said. No user-visible diagnostic.

### Example (skip)

```json
{"skip": true}
```

### Example (propose)

```json
{
  "skip": false,
  "target": "@manifest/types/mistake.md",
  "section": "## Required frontmatter",
  "current": "- `severity` — enum: `minor` | `moderate` | `major`",
  "proposed": "- `severity` — enum: `minor` | `moderate` | `major` | `critical`",
  "why": "Run /kiln:mistake at .kiln/mistakes/2026-04-16-api-key-leak.md needed 'critical' severity for a production outage; current enum forced a false moderate."
}
```

## Entity 2 — Write-Proposal Dispatch Envelope

**Location**: `.wheel/outputs/propose-manifest-improvement-dispatch.json`
**Producer**: `write-proposal-dispatch.sh` (command sub-step)
**Consumer**: `write-proposal-mcp` agent sub-step (MCP write)
**Visibility**: Internal, not user-surfaced.

### Schema (discriminated union)

```json
// Shape A — skip (always possible)
{
  "action": "skip"
}

// Shape B — write (only when all validation passes)
{
  "action": "write",
  "target": "@manifest/types/<filename>.md" | "@manifest/templates/<filename>.md",
  "proposal_path": "@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md",
  "frontmatter": {
    "type": "proposal",
    "target": "<same as top-level target>",
    "date": "<YYYY-MM-DD>"
  },
  "body_sections": {
    "target_line": "<the target path, for display inside the body>",
    "section": "<section heading or line-range>",
    "current": "<verbatim text>",
    "proposed": "<verbatim replacement>",
    "why": "<one-sentence reason>"
  }
}
```

### Invariants

- `action` is always present and is always one of `"skip"` or `"write"`.
- `proposal_path` is always under `@inbox/open/` and always ends in `.md`.
- `frontmatter.date` is today's UTC date in ISO-8601 format (`YYYY-MM-DD`).
- The dispatch envelope is written atomically (write to temp + rename) to prevent partial reads.

## Entity 3 — Proposal File (markdown)

**Location**: `@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md`
**Producer**: `write-proposal-mcp` agent sub-step (via `mcp__claude_ai_obsidian-manifest__create_file`)
**Consumer**: Human maintainer reading `@inbox/open/` in Obsidian.
**Visibility**: User-visible, the payload of the feature.

### Exact file layout

```markdown
---
type: proposal
target: <@manifest/...-path from the reflect output>
date: <YYYY-MM-DD>
---

# Manifest Improvement Proposal

## Target

`<target path>` — <section heading or line-range>

## Current

```
<verbatim current text>
```

## Proposed

```
<verbatim proposed text>
```

## Why

<one-sentence reason grounded in the current run>
```

### Required structure (verified in integration tests)

- First three lines: `---`, frontmatter keys, `---` (YAML block).
- Frontmatter MUST contain, at minimum, `type: proposal`, `target: <path>`, `date: <YYYY-MM-DD>`. Additional keys are permitted but not required.
- After frontmatter: an optional H1 title (`# Manifest Improvement Proposal`), then four H2 sections in this exact order with these exact headings:
  1. `## Target`
  2. `## Current`
  3. `## Proposed`
  4. `## Why`
- Code fences around `## Current` and `## Proposed` content are recommended (to preserve verbatim whitespace) but not required by the contract — the content MUST be the verbatim strings from the reflect output either way.
- Filename: `<YYYY-MM-DD>-manifest-improvement-<slug>.md` where `<slug>` is derived per FR-10 (see slug algorithm in `research.md` R-003).

## Entity 4 — Manifest Target File (read-only reference)

**Location**: Any file matching `@manifest/types/*.md` or `@manifest/templates/*.md`.
**Role**: The target a proposal points at. Read-only from this sub-workflow's perspective — the sub-workflow never modifies manifest files directly (FR-8 prohibits).
**Validation**: `grep -F -- "$current" -- "$resolved_path"` must return exit 0.

**Path resolution**: The `@manifest/...` prefix is an Obsidian vault-relative path. For the verbatim match check, the bash script resolves it against the configured Obsidian vault root (read from the wheel runtime environment or the shelf config). If the vault root cannot be resolved, `check-manifest-target-exists.sh` treats as fail → force skip.

## State transitions

There is no persistent state for this feature. Each run is independent:

```
(run starts)
     │
     ▼
[reflect step emits JSON]
     │
     ▼
[dispatch script reads JSON]
     │
     ├── invalid / skip: true / out-of-scope → dispatch envelope = skip → agent no-ops → (run ends silently)
     │
     └── all checks pass → dispatch envelope = write → agent MCP-writes → proposal file in @inbox/open/ → (run ends)

(next caller invocation repeats — no state carries over)
```

No deduplication state. No "proposed this before" memory. If the same improvement context arises twice, two proposals will be written on separate days (filename includes the date — no collision between days). Same-day re-occurrence produces a `-2` suffix per R-009.

## Key entity relationships (summary)

- Reflect Output is consumed exactly once by the dispatch script, which produces a Dispatch Envelope.
- The Dispatch Envelope is consumed exactly once by the MCP agent step, which either does nothing (skip) or produces a Proposal File.
- The Proposal File references a Manifest Target via its `target` frontmatter key and the first H2 section.
- No entity persists beyond the end of the run except the Proposal File (which is now in the vault and owned by the human reviewer).
