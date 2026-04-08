# Implementer Friction Notes: Infrastructure (impl-infra)

**Agent**: impl-infra
**Tasks**: T001-T004 (Phase 1), T012 (Phase 7), T013-T014 (Phase 8)
**Date**: 2026-04-07

## What Went Smoothly

- Plugin scaffold (Phase 1) was straightforward — existing kiln/wheel/shelf plugins provided clear conventions to follow.
- T014 was a no-op because the workflows field was included in plugin.json at creation time (T001). This is the right approach — create the manifest complete from the start rather than patching it later.
- clay-list SKILL.md (T012) was simple to write since the status derivation logic was clearly specified in contracts/interfaces.md.
- All JSON files validated on first attempt.

## Friction Points

1. **marketplace.json reference**: The specifier noted that plugin-kiln's marketplace.json might not exist as a checked-in file. It doesn't — only plugin-wheel has one. I used plugin-wheel's as reference instead. Future: consider standardizing which plugins have marketplace.json.

2. **clay_derive_status duplication**: The contracts require identical status derivation logic in clay-list SKILL.md and clay-sync.json. In clay-list, it's expressed as Markdown instructions (the LLM implements it). In clay-sync.json, it's a bash command in the scan-products step. The logic is semantically identical but expressed in two different formats. This is a maintenance risk — if status categories change, both must be updated.

3. **Version hook auto-increment**: The version-increment hook bumped plugin.json and package.json versions from 636 to 637+ during file creation. This is expected behavior but worth noting — the version in contracts/interfaces.md (000.000.000.000) was a placeholder, not a literal target.

4. **Phase 8 dependency on Phase 2**: The plan says Phase 8 depends on Phase 2 (wheel manifest enhancement). In practice, I could create the workflow JSON file without waiting for wheel discovery to be implemented — the file just needs to exist. The dependency is only for *runtime execution* of `clay:clay-sync`, not for file creation.

## Decisions Made

- Included `"workflows": ["workflows/clay-sync.json"]` in plugin.json from the start (T001) rather than as a separate T014 step — avoids an unnecessary edit cycle.
- Used `listed: false` in marketplace.json — same as wheel. Clay is not ready for marketplace listing.
- Did not include a `bin` entry in package.json — clay doesn't need an init script like kiln/wheel do. Skills are the primary interface.

## Blockers

None. All assigned tasks completed successfully.
