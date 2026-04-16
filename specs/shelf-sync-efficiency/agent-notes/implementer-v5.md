# Implementer v5 Friction Notes

**Date**: 2026-04-16
**Tasks**: T026-T034 (Phase 5)

## What went well

1. **Contract-first approach paid off** — the v5 contracts were precise enough that implementation was mostly mechanical translation. Step IDs, output paths, and JSON schemas were all specified, leaving no ambiguity.

2. **Clean separation of concerns** — the read-sync-manifest / compute-work-list / update-sync-manifest pipeline is a clean three-stage pattern (read state, compute diff, write state) that's easy to reason about.

3. **patch_file solves B-002/B-005 elegantly** — the programmatic-vs-inferred field split means UPDATE never touches LLM-generated content. This was the simplest of the proposed resolutions.

## Friction points

1. **Issue hash computation in jq** — jq lacks a native sha256 function, so the issue source_hash uses base64 encoding of the JSON input as a deterministic fingerprint rather than a true sha256. For docs, bash `shasum -a 256` handles the real hash. This asymmetry is cosmetic (both are deterministic and change-detecting) but could confuse future readers.

2. **PRD parsing is fragile** — the `read-feature-prds.txt` format uses space-separated KEY=VALUE pairs where TITLE can contain spaces. The awk/sed parsing in compute-work-list.sh handles this but is brittle. A structured JSON output from read-feature-prds would be cleaner.

3. **update-sync-manifest.sh complexity** — the jq pipeline for merging manifest state is the most complex piece. It needs to handle create/update/close/skip across two collections (issues and docs) while checking error paths. The nested reduce operations work but are not easy to debug if something goes wrong.

## Decisions made

- Used `@base64` for issue hashes in jq (no native sha256) — acceptable because the hash only needs to be deterministic and change-detecting, not cryptographic.
- Kept `project_exists` check removed from v5 compute-work-list — the manifest approach doesn't need vault existence checks; if the manifest is empty, everything is CREATE.
- The `close` detection logic checks for manifest issues absent from the current GitHub issue list — this handles the case where issues are deleted or truly closed and removed from the `gh issue list --state all` results.
