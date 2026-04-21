# Quickstart / Smoke Test: Fix Skill with Recording Teams

This walkthrough is the manual end-to-end verification for the feature (standing in for CI-level E2E, per plan.md's Constitution-Check note on Principle V). Run it once after implementation to confirm the full pipeline works.

## Preconditions

- Kiln plugin installed in a repo (source-repo run OR consumer-repo run — pick one per pass).
- Obsidian MCP (`mcp__claude_ai_obsidian-manifest__*`) connected, with a vault that has `@projects/<project>/` convention.
- `.shelf-config` present at repo root with `project_name=<slug>` set (for Obsidian write path) OR `git rev-parse --show-toplevel` is resolvable.
- `.gitignore` contains `.kiln/fixes/` (FR-021 — verify first).
- A seeded reproducible bug on a scratch branch. Either:
  - A failing test: add a test that fails deterministically, commit it.
  - A runtime error: commit a small code change that causes a runtime error in a trivial flow.

## Happy path — successful fix

1. From the scratch branch, invoke:

   ```text
   /kiln:fix Tests fail in <describe the test in plain words>
   ```

2. Watch main chat. Verify:
   - The debug loop runs entirely in main chat (diagnose → fix → verify, iterating). No `TeamCreate` tool call appears during the loop.
   - A commit lands on the scratch branch.

3. After the commit, verify the main-chat transcript includes:
   - Exactly one `compose-envelope.sh` (or equivalent) block that wrote `.kiln/fixes/.envelope-<timestamp>.json`.
   - Exactly one `write-local-record.sh` invocation that printed the path of the new `.kiln/fixes/<date>-<slug>.md` file.
   - Exactly two `TeamCreate` calls (fix-record + fix-reflect), both issued in the same skill step.
   - Exactly two `TaskCreate` calls (one per team).
   - Zero or small number of `SendMessage` exchanges (escape hatch only; FR-010/FR-011).
   - Exactly two `TeamDelete` calls after the tasks complete.
   - Final user-facing report naming the local record path and the Obsidian note path.

4. File-level assertions:

   ```bash
   # Local record
   ls -1 .kiln/fixes/*.md
   # → prints exactly one new file (plus any pre-existing — inspect by date)

   # Frontmatter
   head -20 .kiln/fixes/<date>-<slug>.md
   # → type: fix, date: <today>, status: fixed, commit: <hash>, files_changed: [...]

   # Transient scratch cleaned up
   ls -1 .kiln/fixes/.envelope-*.json .kiln/fixes/.reflect-output-*.json 2>/dev/null
   # → empty
   ```

5. Obsidian-level assertions (via MCP read or vault inspection):
   - `@projects/<project>/fixes/<date>-<slug>.md` exists.
   - Frontmatter matches the local record plus tag axes populated.
   - Body has five H2 sections in order; wikilinks present per FR-007.

6. Inbox assertions (most common path — trivial fix reveals no manifest gap):
   - `@inbox/open/` gains no new file.
   - No `fix-reflect` log line in main chat.

## Escalated path — 9-attempt exhaustion

Harder to stage without a deliberately unfixable bug; when you have one, run `/kiln:fix` against it and let the debug loop exhaust. Verify:

- The local record and Obsidian note both exist with `status: escalated` and `commit: null`.
- `## Escalation notes` section is populated with techniques tried.
- `## Files changed` lists inspected files (not modified).
- `fix-reflect` still ran (reflect is not special-cased for escalated runs per User Story 2).

## Reflect happy path — seeded manifest gap

To verify SC-003 (reflect precision), craft a bug whose `root_cause` obviously names a missing field in `@manifest/types/project-dashboard.md` (or any manifest type file). Run `/kiln:fix`. Verify:

- A single file appears at `@inbox/open/<date>-manifest-improvement-<slug>.md`.
- `type: proposal`, `target`, `date` frontmatter; four H2 sections in order.
- `current` text appears verbatim in the target manifest file.
- `why` sentence cites a specific field from the envelope (issue text, commit hash, or a `files_changed` entry).

## Obsidian MCP unavailable

Disable MCP connection (close Obsidian, disconnect the server). Run `/kiln:fix` on a seeded bug. Verify:

- `.kiln/fixes/<date>-<slug>.md` is written successfully.
- Exactly one warning line appears in main chat (via `SendMessage` from fix-record).
- The final user-facing report lists the local record path and marks the Obsidian note as "skipped (MCP unavailable)".
- Both `TeamDelete` calls ran.

## Project name unresolvable

Temporarily `mv .shelf-config .shelf-config.bak` and invoke `/kiln:fix` inside a `git init`-style scratch that has no remote. Verify:

- The local record is still written.
- Obsidian write skips with a one-line warn.
- User-facing report marks Obsidian as skipped.

Restore `.shelf-config` after the test.

## Unit tests (pure bash)

```bash
bash plugin-kiln/scripts/fix-recording/__tests__/run-all.sh
# → exit 0 and a summary line "N/N tests passed"
```

Every helper (envelope compose, credential strip, local writer, resolve project name, unique filename, team brief renderer) has at least one dedicated test. The run-all script exits 1 on any failure.

## Consumer-repo portability spot-check

After the happy-path pass succeeds in the source repo, do one pass from a consumer repo that does NOT have `plugin-kiln/` or `plugin-shelf/` checked out (the plugin is installed via `~/.claude/plugins/cache/...`). Verify:

- No "No such file or directory" errors in main-chat tool output.
- The scripts under the plugin cache resolve via `${SHELF_SCRIPTS_DIR}`.
- The pipeline completes successfully and produces the same artifacts as in the source-repo run.

## Acceptance

The feature is accepted when all of the following hold:

- Unit tests: 100% of `run-all.sh` tests pass.
- Happy-path smoke: successful-fix run produces both local record and Obsidian note with correct shape.
- Escalated smoke: one escalated run produces both artifacts with `status: escalated`.
- Reflect smoke: one seeded-gap run produces a single valid `@inbox/open/` proposal; one non-gap run produces none.
- MCP-unavailable smoke: local record still written, warning surfaces, skill reports success.
- Consumer-repo smoke: pipeline succeeds in a repo with no plugin source checked out.

If any of the above fails, file a fix record (eat your own dog food) and iterate.
