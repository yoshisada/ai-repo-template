---
id: 2026-04-24-shelf-write-roadmap-note-needs-batching
title: "shelf-write-roadmap-note has no batching — capture flows that produce N files skip the Obsidian mirror entirely"
type: improvement
date: 2026-04-24
status: open
severity: medium
area: shelf
category: ergonomics
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-shelf/workflows/shelf-write-roadmap-note.json
  - plugin-shelf/scripts/parse-roadmap-input.sh
  - plugin-kiln/skills/kiln-roadmap/SKILL.md
  - plugin-kiln/skills/kiln-distill/SKILL.md
related:
  - 2026-04-24-kiln-report-issue-workflow-cant-batch
---

## Summary

`shelf:shelf-write-roadmap-note` is the Obsidian-mirror workflow for `.kiln/roadmap/items/`, `.kiln/roadmap/phases/`, and `.kiln/vision.md` writes. It dispatches **one note per invocation** — driven by a single `source_file` passed via `ROADMAP_INPUT_FILE` env var (or `ROADMAP_INPUT_BLOCK`, or stdin). Per the `parse-roadmap-input.sh` contract, there's no list or directory mode.

This breaks down for **capture flows that produce many files at once**:

- `/kiln:kiln-roadmap` spinning up a new phase + N items in one session — e.g., today's 09-research-first phase produced 1 phase file + 8 item files = **9 separate shelf-write-roadmap-note dispatches** if the skill follows its own contract.
- `/kiln:kiln-distill` in multi-theme N-PRD mode emits N PRD folders, each potentially triggering a sibling mirror call.
- Legacy-migration runs (`plugin-kiln/scripts/roadmap/migrate-legacy-roadmap.sh`) can produce 10-30 items in a single bootstrap; each would need its own dispatch.

Because the dispatch cost is high (one full wheel workflow per note, each spawning its own MCP-Obsidian session), the practical consequence is that skills **skip the mirror** in these flows and defer to `/shelf:shelf-sync` for reconciliation later. That defeats the FR-030 contract of `/kiln:kiln-roadmap` ("mirror is dispatched on every item write") and creates a soft bypass pattern identical to the one flagged in [2026-04-24-kiln-report-issue-workflow-cant-batch].

## Concrete pain

- Today's 09-research-first phase capture produced 9 files (1 phase + 8 items). Per-file dispatch would be 9 wheel invocations; I skipped the mirror entirely and surfaced it to the user as "say the word and I'll dispatch." That's the skill-bypass smell.
- The cost isn't just wheel overhead — `shelf-write-roadmap-note` opens an MCP Obsidian session per invocation, and MCP-Obsidian auth/handshake is non-trivial. Batching would amortize one session across N files.
- `.shelf-config` is read once per invocation (via `read-shelf-config.txt`). Ninety files = ninety reads. Trivial individually, compounding in aggregate.
- For multi-theme distill output, the ordering of Obsidian writes should be consistent (e.g., all items in a phase before the phase note, or vice versa) to avoid transient dangling links in the vault. Per-file dispatch can't enforce ordering; a batch caller can.
- Per-file result JSONs (one per invocation) fragment the outcome state — a batch invocation could emit a single array of `{source_file, obsidian_path, action, errors}` entries, making partial-failure visible as a single unit.

## Proposed direction

### (A) Accept a list of source files in one invocation

Extend `parse-roadmap-input.sh` + `shelf-write-roadmap-note.json` to accept:

```bash
# New: directory path — all .md files under it, filtered by frontmatter kind
export ROADMAP_INPUT_DIR=".kiln/roadmap/items/"

# New: explicit list file — one source_file path per line
export ROADMAP_INPUT_LIST=".kiln/inbox/2026-04-24-research-first-batch.txt"

# Legacy: single file (unchanged, still supported)
export ROADMAP_INPUT_FILE=".kiln/roadmap/items/2026-04-24-foo.md"
```

Workflow iterates the resolved list inside ONE wheel invocation. Shared steps (read-shelf-config, MCP-Obsidian session setup) run once; per-file steps (parse frontmatter, select action=create_file vs patch_file, write) loop.

### (B) Result JSON as per-file array

Result lands at `.wheel/outputs/shelf-write-roadmap-note-result.json` as:

```json
{
  "schema_version": "2",
  "count": 9,
  "results": [
    {"source_file": ".kiln/roadmap/phases/09-research-first.md", "obsidian_path": "...", "action": "create_file", "errors": []},
    {"source_file": ".kiln/roadmap/items/2026-04-24-research-first-fixture-format-mvp.md", "obsidian_path": "...", "action": "create_file", "errors": []},
    ...
  ],
  "failed_count": 0
}
```

Single-file callers keep current shape under `schema_version: 1`; batch callers get the array shape under `schema_version: 2`.

### (C) Ordering contract

Document (and enforce in the workflow) the Obsidian-write ordering rule: **phases before items that reference them, items before vision updates that cite them.** A sort-key helper (`plugin-shelf/scripts/sort-roadmap-writes.sh`) could compute the correct order from the input list's frontmatter.

## Cheaper interim fix

Callers that need batching today can invoke one shared `shelf:shelf-sync` at the end of their capture flow instead of per-file mirror. That's what's happening in practice — but it loses the immediacy guarantee. The fix restores immediacy without the per-file dispatch cost.

## Dependencies & related

- Sibling issue: [2026-04-24-kiln-report-issue-workflow-cant-batch](./2026-04-24-kiln-report-issue-workflow-cant-batch.md) — same underlying pattern (per-item wheel workflow needs batching), different target workflow.
- Also related: [2026-04-24-wheel-workflow-speed-batching-commands](./2026-04-24-wheel-workflow-speed-batching-commands.md) — intra-step command batching; orthogonal scope but the performance concerns compound.

## Why now

Surfaced during 09-research-first phase capture on 2026-04-24 — a 9-file roadmap write where the skill-bypass option was the only ergonomic one. Multi-theme distill (already shipped per build/coach-driven-capture-ergonomics-20260424) is the other consumer; every N-PRD run has this same friction. Ergonomics of the capture loop are a first-class vision concern ("the loop is the product"), so a bypass here erodes the core contract.
