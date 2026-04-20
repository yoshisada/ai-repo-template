# Blockers for fix-skill-with-recording-teams

## T015 — `@manifest/types/fix.md` MCP write not performed

**Status**: Staging copy authoritative. Vault MCP write deferred to a human (or a later session with MCP connected).

**What happened**: T015 requires authoring `@manifest/types/fix.md` as a markdown artifact AND writing the same content to the vault via `mcp__claude_ai_obsidian-manifest__create_file`. The staging copy at `specs/fix-skill-with-recording-teams/assets/manifest-types/fix.md` was authored. The MCP create_file tool is not loaded in the implementer's environment this session — only obsidian-test-mcp / obsidian-truenas authentication stubs appear in the deferred tool list (no create_file primitive resolved after ToolSearch).

**Impact on feature**: Low but non-zero.
- The staging copy is the PR-reviewable source of truth — reviewers can critique the schema before it lands in the vault.
- Until the MCP write happens, the `fix-record` team has no in-vault schema to validate against. The team brief references `@manifest/types/fix.md`; on the first `/kiln:fix` run after feature merge, the team will either find the file (if a maintainer synced it) or fail the schema check silently.
- Per spec Edge Case "Manifest-type schema drift" + Assumption "@manifest/types/mistake.md is stable", the vault copy can be created post-merge without breaking downstream.

**Follow-up**:
1. On the next session where `mcp__claude_ai_obsidian-manifest__create_file` is available, run:
   ```
   path: @manifest/types/fix.md
   content: <contents of specs/fix-skill-with-recording-teams/assets/manifest-types/fix.md>
   ```
2. Alternatively, the maintainer can accept the PR and hand-copy the staging file into the vault before the first `/kiln:fix` runs post-merge.

**Acknowledged by**: implementer (2026-04-20).
