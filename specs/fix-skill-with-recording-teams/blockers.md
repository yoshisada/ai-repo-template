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

---

## T018 / T019 / T020 — Manual quickstart smoke walks deferred

**Status**: Unit-test coverage complete (8/8 pass). Manual end-to-end walks of `quickstart.md` deferred to the auditor or human reviewer.

**What happened**: T018–T020 require invoking `/kiln:fix` on a seeded bug in a scratch branch (happy path, MCP-unavailable path, consumer-repo portability spot-check) and observing main-chat output, Obsidian vault writes, and `TeamDelete` behavior. This requires:
1. An interactive Claude Code session where `/kiln:fix` can be invoked.
2. A seeded reproducible bug on a scratch branch.
3. Obsidian MCP connectivity for the happy-path walk, and a way to disable it for the MCP-unavailable walk.
4. A consumer repo with the plugin installed via `~/.claude/plugins/cache/...` for the portability walk.

The implementer's environment is non-interactive and cannot complete these walks. The plan's Constitution Check (Principle V) anticipates this — "True E2E for this feature would require a real Claude Code team-spawn in CI, which this plugin's test infra does not provide. We compensate with: (a) a `/fix` smoke test invoked manually (`quickstart.md`), (b) unit tests over every helper script, (c) team-brief fixture tests..."

**Impact on feature**: None on correctness. Unit tests exercise every helper's branches (FR-030 (a)–(f) + portability). Manual walks are needed for SC-001 / SC-005 / SC-007 / SC-008 / SC-009 / SC-010 acceptance, which are post-merge human verification.

**Follow-up**:
1. Auditor / human reviewer runs the four quickstart walks before final sign-off:
   - Happy path (successful fix).
   - Escalated path (optional — harder to stage).
   - Reflect seeded-gap path (optional — requires crafted bug).
   - MCP-unavailable path.
   - Project-name-unresolvable path.
   - Consumer-repo portability spot-check.
2. If any walk fails, file a fix record (eat-your-own-dog-food) and iterate.

**Acknowledged by**: implementer (2026-04-20).
