# Contract Edits — Mistake Capture

**Authored by**: impl-shelf during Phase 2 review (T004).

## Edit 1: MCP scope for @inbox/open/ proposal writes (§5, §6)

**Contract as written**: `interfaces.md` §5 specifies `mcp__obsidian-projects__create_file` / `patch_file` for the proposal write, and §6 specifies `mcp__obsidian-projects__list_files` for the `@inbox/open/` reconciliation.

**Verified fact (via `get_permissions` on both MCPs, 2026-04-16)**:
- `mcp__obsidian-projects__*` permissions: `/@manifest` read-only, `/@second-brain/projects` readwrite. **No access to `@inbox`.**
- `mcp__claude_ai_obsidian-manifest__*` permissions: `/@manifest` readwrite, `/@second-brain` read-only, `/@ai` readwrite, `/@inbox` **readwrite**.

**Conclusion**: The projects MCP cannot write to `@inbox/open/`. The manifest MCP is the only scope with the required permission. Research §R2 anticipated this fallback; we are taking it.

**Resolution applied in implementation**:
- In `plugin-shelf/workflows/shelf-full-sync.json` `obsidian-apply` step (§5): mistake-proposal creates/patches go through `mcp__claude_ai_obsidian-manifest__create_file` and `mcp__claude_ai_obsidian-manifest__patch_file`. Existing issue/doc writes continue to use `mcp__obsidian-projects__*` because they target `@second-brain/projects/` which the projects MCP owns.
- In `plugin-shelf/scripts/update-sync-manifest.sh` (§6): `@inbox/open/` reconciliation uses `mcp__claude_ai_obsidian-manifest__list_files`. Note: update-sync-manifest.sh is a shell command, it cannot call MCP directly — see Edit 2.

## Edit 2: Reconciliation location must move to the agent step

**Contract as written**: `interfaces.md` §6 specifies that `update-sync-manifest.sh` calls `mcp__obsidian-projects__list_files` for `@inbox/open/` reconciliation. This is infeasible — `update-sync-manifest.sh` is a wheel command step (pure bash + jq), not an agent step. Command steps cannot invoke MCP tools.

**Resolution applied in implementation**:
- The `list_files` call for `@inbox/open/` moves into the `obsidian-apply` agent step (which already has MCP access). The agent performs reconciliation inline: after processing `create/update/skip` on mistakes, it lists `@inbox/open/` (guarded by "only if there's at least one prior mistake entry to reconcile, OR any new ones just created") and emits a new sub-object in its results JSON: `mistakes.reconciliation: [{path, new_state}]`.
- `update-sync-manifest.sh` consumes this `reconciliation` array and applies `open → filed` transitions to the manifest.
- Constraint from §6 preserved: the `list_files` call is skipped when no reconciliation input exists (sum of prior `mistakes[]` + new creations == 0).

This preserves the invariant "commands do no MCP, agents own all MCP," and keeps the contract's "one list_files per sync" constraint intact.

## Edit 3: source-hash key discovery

**Contract as written**: §4 says `compute-work-list.sh` should look up manifest entries "by `path` (NOT by filename_slug)". The manifest's `mistakes[]` array (new) is keyed by `path`.

**No edit needed** — documenting for implementer self-reference: use `path` as the primary key throughout, identical to how `issues[]` is keyed by `github_number` and `docs[]` by `slug`.
