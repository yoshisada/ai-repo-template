# Auditor Friction Notes — v5

**Agent**: auditor
**Date**: 2026-04-16
**Branch**: `build/shelf-sync-efficiency-20260416`

## What went well

- All validation gates passed cleanly: JSON valid, bash syntax OK, agent count = 1.
- FR compliance was straightforward to verify — the contracts/interfaces.md is precise enough that checking the implementation is mechanical.
- The CREATE vs UPDATE split in the obsidian-apply agent instruction is clearly documented with explicit "CRITICAL: DO NOT" callouts for inferred fields.
- Atomic write pattern (tmp + mv) in update-sync-manifest.sh is correct.

## Friction

- **blockers.md was stale for v5**: The summary table still said "agent count = 2" (v4) and B-003 mitigation referenced the now-removed `obsidian-discover` agent. Fixed during audit. Implementer should update blockers.md references when making architectural changes.
- **source_hash computation differs between issues and docs**: Issues use base64 of JSON (jq `@base64` in compute-work-list.sh) while docs use actual sha256 via `shasum -a 256`. This is technically correct per contract but could be confusing for future maintainers. Not a bug — just a note.
- **No empirical verification possible**: B-001 (token cost) and B-003 (large vault) remain unverified empirically. This is expected given session constraints but should be the first thing tested after merge.

## Recommendations

1. Run `/wheel-run shelf-full-sync` on the pinned benchmark repo immediately after merge to close B-001.
2. Consider normalizing source_hash computation to use real sha256 for both issues and docs in a follow-up.
