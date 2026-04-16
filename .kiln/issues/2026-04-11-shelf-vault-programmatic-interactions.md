---
title: "shelf: make vault interactions programmatic — decide Road A vs Road B for doc sync"
type: architecture
severity: high
category: shelf
source: live-run-regression
github_issue: null
repo: https://github.com/yoshisada/ai-repo-template
status: open
date: 2026-04-11
files:
  - plugin-shelf/workflows/shelf-full-sync.json
  - plugin-shelf/scripts/compute-work-list.sh
  - specs/shelf-sync-efficiency/blockers.md
---

## Background

The shelf-sync-efficiency feature (PR #90, branch `build/shelf-sync-efficiency-20260410`)
consolidated shelf-full-sync from 4 agent steps to 2 by moving diff computation
into a deterministic bash/jq command step (`compute-work-list.sh`). This worked
for issue sync but exposed a fundamental architectural tension for doc sync.

## The Problem

v3 agents inferred vault content by reading PRD files with an LLM:
- `summary` — a meaningful one-line summary derived from reading the PRD
- `status` — reflects actual implementation state ("implemented", "in-progress", etc.)
- `tags` — includes `status/*` and `category/*` taxonomy entries

v4's deterministic bash cannot reproduce these. It hardcodes:
- `summary = title` (not a real summary)
- `status = "Draft"` (always)
- `tags = ["doc/prd"]` (no taxonomy)

A live run on this vault revealed that all 24 doc updates would regress
these fields in the existing vault. The workflow was stopped before obsidian-apply
executed — vault was not corrupted.

This is blocker B-005 in `specs/shelf-sync-efficiency/blockers.md`.

## Architectural Options

### Road A — Vault schema split (programmatic vs inferred fields)

Split vault frontmatter into two classes:
- **Programmatic fields**: `source`, `github_number`, `last_synced`, `project`, `type`
  — always overwritten on sync, derived from machine-readable data
- **Inferred fields**: `summary`, `status`, `category`, `tags` (taxonomy)
  — set once by agent on CREATE, never overwritten on UPDATE

Implementation:
1. obsidian-apply uses patch-not-replace for existing notes (read → merge → write)
2. Add vault migration script to classify existing note fields
3. Update obsidian-discover index to record which fields are "inferred-owned"
4. Document the schema split in shelf vault spec

**Pros**: Cleanest long-term model. Sync never corrupts human/LLM-curated content.
**Cons**: Requires vault migration. Adds complexity to obsidian-apply. One-time migration cost.

### Road B — Merge-aware obsidian-apply (no schema change)

Keep compute-work-list.sh for issue/path/source fields. obsidian-apply reads
each existing note before writing, preserving fields it doesn't own:
- On CREATE: write full frontmatter including inferred fields (LLM fills summary/status/tags)
- On UPDATE: read existing note, overwrite only programmatic fields, preserve the rest

**Pros**: No vault migration. Simpler spec change. obsidian-apply already has
MCP read access.
**Cons**: obsidian-apply makes N additional MCP reads (one per updated note).
On large vaults this adds latency and may push token cost up. Semantics are
implicit ("preserve fields we don't set") rather than explicit schema.

## Recommendation

**Road B** is lower-risk for this iteration. The additional reads are bounded by
the work-list size (only notes actually changing), not total vault size. Road A
is the better long-term architecture but should be a separate feature.

Road B steps:
1. Update spec (FR-003 parity definition, obsidian-apply behavior)
2. Update contracts/interfaces.md (obsidian-apply gets a merge-mode flag)
3. Change obsidian-apply agent prompt to read-before-write for updates
4. Re-run live benchmark to confirm parity and measure token impact

## Related

- Blocker: `specs/shelf-sync-efficiency/blockers.md` B-002, B-005
- PR: yoshisada/ai-repo-template#90 (blocked pending this decision)
- Audit log: `.kiln/logs/build-shelf-sync-efficiency-20260410-20260410-172818.md`
