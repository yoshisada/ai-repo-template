---
name: shelf-propose-manifest-improvement
description: Reflect on the current run's artifacts and, only when a concrete actionable change to a manifest type or template file is identified, file a single proposal in @inbox/open/ via Obsidian MCP. Silent no-op otherwise. Used by kiln:kiln-mistake, kiln:kiln-report-issue, and shelf:shelf-sync — invoke standalone via this skill to test in isolation.
---

# shelf:shelf-propose-manifest-improvement — File a Manifest-Type Improvement Proposal

This is the standalone entrypoint for the `shelf:shelf-propose-manifest-improvement` sub-workflow (FR-017). It reflects on the current run's `.wheel/outputs/*` artifacts and — **only** when it can identify a concrete, actionable textual change to a file under `@manifest/types/` or `@manifest/templates/` — writes a single proposal note to `@inbox/open/` via the Obsidian MCP.

Every other run, silent no-op: no file, no log line, no side effect.

## How to invoke

```text
/wheel:run shelf:shelf-propose-manifest-improvement
```

This skill dispatches that exactly. No arguments.

## What the sub-workflow does

1. **reflect** (agent): Scans `.wheel/outputs/*` for evidence of a manifest gap (schema missing a field, template producing a confusing artifact, etc.). Emits a JSON verdict to `.wheel/outputs/propose-manifest-improvement.json`.
2. **write-proposal-dispatch** (command): Deterministic gate — validates the JSON, confirms `current` text appears verbatim in the target file, derives a filename slug from `why`, and emits a dispatch envelope. Silent on any skip path.
3. **write-proposal-mcp** (agent): Reads the envelope. On `skip`, does nothing. On `write`, calls `mcp__claude_ai_obsidian-manifest__create_file` exactly once. On MCP unavailable, writes a one-line warning and exits 0.

## Invariants

- **Silent on skip** (FR-007): zero stdout, zero stderr, zero files created.
- **Scope-bounded** (FR-004): proposals only target `@manifest/types/*.md` or `@manifest/templates/*.md`. Shelf skills, plugin workflows, the constitution, and other vault paths are force-skipped.
- **Exact-patch gate** (FR-005): `current` text is byte-verified against the target file before any write.
- **One proposal per run**: multiple candidates are dropped to the single most concrete one.
- **Non-blocking** (FR-015): MCP unavailability warns once and exits 0 — the caller workflow continues.

## Where proposals land

`@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md` with frontmatter (`type: proposal`, `target`, `date`) and four H2 sections in order: `## Target`, `## Current`, `## Proposed`, `## Why`.

## When to run standalone vs as a sub-workflow step

- **Sub-workflow** (the normal path): `shelf:shelf-sync`, `kiln:kiln-report-issue`, and `kiln:kiln-mistake` each invoke this sub-workflow as their pre-terminal step. No manual invocation needed — proposals surface automatically on any caller run that produced relevant context.
- **Standalone** (this skill): useful for testing, or when you want to reflect on an ad-hoc set of artifacts already seeded under `.wheel/outputs/`.

## Troubleshooting

- **Nothing happened** — that's the design. Skip runs are silent. Check `.wheel/outputs/propose-manifest-improvement-dispatch.json` to see whether the gate force-skipped (it always exists after a run).
- **Proposal not written after a seemingly valid reflect output** — the `current` text may not match byte-for-byte. Re-check against the target file. Or the `why` field may not cite a concrete run artifact.
- **`warn: obsidian MCP unavailable`** in `.wheel/outputs/propose-manifest-improvement-mcp.txt` — Obsidian is not connected. Reconnect the MCP and re-run.
