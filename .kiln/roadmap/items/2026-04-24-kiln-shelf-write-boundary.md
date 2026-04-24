---
id: 2026-04-24-kiln-shelf-write-boundary
title: "kiln must not write directly to shelf-owned files"
kind: constraint
date: 2026-04-24
status: active
phase: unsorted
state: planned
blast_radius: cross-cutting
review_cost: careful
context_cost: 2 sessions
implementation_hints: |
  Enforcement pattern: kiln skills and wheel workflows emit intent as variables exported at the end
  of a run (e.g., `SHELF_SYNC_ISSUES=true`, `SHELF_SYNC_PROGRESS=true`). Shelf subscribes to those
  signals via a stop-hook-style mechanism and decides whether to act — sync, skip, or batch.

  Concretely:
    - Kiln skills MUST NOT call `mcp__claude_ai_obsidian-*` tools directly.
    - Kiln skills MUST NOT invoke shelf workflows inline (the current `shelf:shelf-write-*` pattern
      from inside a kiln skill violates this boundary).
    - Kiln skills MAY export intent variables or write to a shared "kiln-intent" channel that shelf
      reads post-run.
    - Shelf owns ALL Obsidian writes. Shelf is the only system that reads `.shelf-config`.

  Migration path:
    1. Audit current kiln→Obsidian coupling points (roadmap mirror, report-issue mirror, mistake mirror, etc.).
    2. Replace each direct shelf-workflow call with an intent export.
    3. Add a shelf stop-hook that reads intent and fires matching sync steps.
    4. Delete the inline shelf dispatches from kiln skills.

  Test: install kiln without shelf in a fresh repo. Every kiln skill MUST complete cleanly with no
  Obsidian-related errors and no skipped-step warnings beyond a single FR-040-style "shelf disabled" notice.
---

# kiln must not write directly to shelf-owned files

## Why this constraint

Shelf is a more personal layer — it's Obsidian-specific, vault-specific, and opinionated about how notes are structured. Not every kiln user will run shelf. Today, kiln skills invoke shelf workflows inline (e.g., `shelf:shelf-write-roadmap-note` is called from inside `/kiln:kiln-roadmap`), which creates an implicit dependency: if you don't have shelf configured, kiln skills degrade gracefully *at best* and produce confusing warnings *at worst*.

The constraint establishes a clean architectural split: **kiln emits intent, shelf decides.** Kiln stays a portable spec-first development harness. Shelf stays an optional personal-knowledge-management layer that reads kiln's outputs. Neither system directly writes to files the other owns.

## What would need to change to revisit this

- If kiln decided to ship an opinionated persistence layer (beyond `.kiln/` local files) as a first-class concern, and shelf became one implementation among several — then the boundary might shift to "kiln writes through a persistence-adapter interface" rather than "kiln doesn't write at all."
- If shelf became mandatory for all kiln users (e.g., the pipeline stopped working without Obsidian), the personal-layer framing would collapse and the constraint would be moot.

Neither is on the table today.

## Items that would violate this if built naively

- Any wheel workflow in a kiln plugin that calls `mcp__claude_ai_obsidian-*` directly in a command or agent step.
- Any kiln skill that invokes `shelf:shelf-*` via the Skill tool inline instead of exporting intent for shelf to consume post-run.
- Any new feature that reads `.shelf-config` from inside a kiln skill (only shelf owns that file).

The Apr 2026 change to `/kiln:kiln-report-issue` that spawns a background sub-agent for `shelf-sync` is directionally on the right side of this constraint (kiln decides *when*, shelf decides *what*), but the in-line `shelf:shelf-write-issue-note` call in the foreground path still needs migration.
