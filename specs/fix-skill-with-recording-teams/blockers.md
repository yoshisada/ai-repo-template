# Blockers for fix-skill-with-recording-teams

## T015 — `@manifest/types/fix.md` MCP write — RESOLVED 2026-04-21

**Status**: Vault write completed via `mcp__claude_ai_obsidian-manifest__create_file`. Staging copy and vault copy now in sync.

**Resolution**: On 2026-04-21, with `obsidian-manifest` MCP authenticated in this session, the staging file at `specs/fix-skill-with-recording-teams/assets/manifest-types/fix.md` was shipped to the vault at `@manifest/types/fix.md`. MCP call returned `{"path": "@manifest/types/fix.md"}`. The `fix-record` team can now validate against a real in-vault schema on the next `/kiln:fix` invocation.

**Original context** (preserved for history): The implementer environment did not have `mcp__claude_ai_obsidian-manifest__create_file` loaded during the build pipeline, so T015's vault write was deferred while the staging copy shipped with the PR. Resolved in a follow-up `/kiln:fix` session once the MCP was available.

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
