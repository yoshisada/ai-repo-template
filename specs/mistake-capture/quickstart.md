# Quickstart — Mistake Capture

**Audience**: the implementer (post-`/tasks`) verifying the feature works end-to-end. Also the smoke-test target for `/kiln:audit` and for `/kiln:qa-final`-equivalent plugin smoke.

Goal: from `/kiln:mistake` invocation to an accepted-and-filed proposal in under 10 minutes of wall clock, on a machine where the kiln + shelf + wheel plugins are installed and the Obsidian MCP is available.

---

## Prerequisites

1. Kiln plugin (`@yoshisada/kiln`) installed OR this source repo checked out.
2. Shelf plugin installed.
3. Wheel engine installed (post-`005e259` version — `WORKFLOW_PLUGIN_DIR` export required).
4. Obsidian MCP available (`mcp__obsidian-projects__*`).
5. `.shelf-config` file present at repo root with `slug=ai-repo-template` (or similar) and `base_path=projects`.

---

## Step 1 — Invoke the skill

In a Claude Code session, run:

```text
/kiln:mistake I assumed plugin caches live per-vault when they are actually per-project
```

Expected:
- The skill SKILL.md is read; the LLM guardrails block is present in conversation context.
- The skill invokes `/wheel-run kiln:report-mistake-and-sync`.

---

## Step 2 — Watch the three workflow steps execute

### 2a. `check-existing-mistakes` (command step)

Expected:
- `.wheel/outputs/check-existing-mistakes.txt` is written.
- Content begins with `## Existing Local Mistakes (.kiln/mistakes/)` and ends with either file paths or `(none)`.
- Second block begins with `## Recent Session Mistakes (@manifest/recent-session-mistakes/)` and prints file paths or `(not present)`.

Verify:
```bash
cat .wheel/outputs/check-existing-mistakes.txt
```

### 2b. `create-mistake` (agent step)

Expected behavior (from the contract §2.1):
- The agent reads the free-form description from activation context.
- Prompts for any missing fields: `status`, `severity`, `tags`, body sections.
- Infers `made_by` from its own runtime model, confirms with you.
- Rejects any hedged `assumption`/`correction` (trigger the lint yourself by typing `I may have thought caches were per-vault` — expect rejection, re-prompt).
- Rejects tag sets missing a required axis (try `["mistake/assumption", "language/bash"]` — expect rejection on missing `topic/*`).
- Writes `.kiln/mistakes/2026-04-16-assumed-plugin-caches-live-per-vault.md` (slug truncated if needed).
- Writes a summary to `.wheel/outputs/create-mistake-result.md`.

Verify:
```bash
ls .kiln/mistakes/
cat .kiln/mistakes/$(ls -t .kiln/mistakes/ | head -1)
cat .wheel/outputs/create-mistake-result.md
```

The artifact MUST have:
- All 7 required frontmatter fields (§E1).
- 5 body sections in order, each either with content or `_none_`.
- Slug derived from the `assumption` field (not from the correction).

### 2c. `full-sync` (terminal workflow step)

Expected:
- The outer workflow activates `shelf:shelf-full-sync`.
- `compute-work-list.sh` emits `mistakes[]` in `.wheel/outputs/compute-work-list.json` with one `create` action for the just-written artifact.
- `obsidian-apply` agent step writes a proposal to `@inbox/open/2026-04-16-mistake-assumed-plugin-caches-live-per-vault.md`.
- `update-sync-manifest.sh` adds a new `mistakes[]` entry with `proposal_state: "open"`.
- The outer workflow archives to `.wheel/history/success/`.

Verify:
```bash
# work list picked up the mistake
jq '.counts.mistakes, .mistakes' .wheel/outputs/compute-work-list.json

# obsidian-apply results include mistake counts
jq '.mistakes' .wheel/outputs/obsidian-apply-results.json

# sync manifest has the new entry
jq '.mistakes' .wheel/outputs/sync-manifest.json

# state file archived
ls .wheel/history/success/ | grep report-mistake
```

In Obsidian:
- Open `@inbox/open/`. A new file with the expected name is present.
- Frontmatter matches contracts §5.1 — `type: manifest-proposal`, `kind: content-change`, `target: @second-brain/projects/<slug>/mistakes/<source-filename>`, `mistake_class:` present, `tags:` starts with `mistake-draft`.
- Body has the header block, Summary block, and a verbatim reproduction of the source artifact's five sections.

---

## Step 3 — Accept the proposal (human step)

In Obsidian:
1. Open the proposal in `@inbox/open/`.
2. Move it to `@second-brain/projects/<slug>/mistakes/` (the `target:` field tells you where).

---

## Step 4 — Sync again; confirm no resurrection

Run:

```text
/wheel-run shelf:shelf-full-sync
```

Expected:
- `compute-work-list.json` shows `counts.mistakes.skip >= 1` (or similar) for the filed entry.
- `obsidian-apply-results.json` shows `mistakes.created: 0, updated: 0`.
- The sync manifest entry has transitioned to `proposal_state: "filed"`.
- The proposal is NOT recreated in `@inbox/open/`.

Verify:
```bash
jq '.mistakes[] | select(.path == ".kiln/mistakes/2026-04-16-assumed-plugin-caches-live-per-vault.md")' .wheel/outputs/sync-manifest.json
# Expect: "proposal_state": "filed"
```

---

## Step 5 — Confirm hedge-word rejection (lint smoke)

Run `/kiln:mistake` again with a hedge word in the assumption:

```text
/kiln:mistake I may have assumed the wrong thing
```

At the `assumption:` collection prompt in the `create-mistake` step, type literally:

```text
I may have assumed the WORKFLOW_PLUGIN_DIR was always exported
```

Expected:
- Agent rejects with a one-line explanation mentioning "may have" or "hedges".
- Re-prompts. Provide a lint-clean version:
  ```text
  I assumed the WORKFLOW_PLUGIN_DIR was always exported
  ```
- Agent accepts and continues.

---

## Step 6 — Confirm plugin portability

On a consumer repo (i.e., one where this source repo is NOT the cwd and only the installed plugin cache exists at `~/.claude/plugins/cache/yoshisada-speckit/kiln/<version>/`):

```text
/wheel-run kiln:report-mistake-and-sync
```

Expected:
- `.wheel/outputs/check-existing-mistakes.txt` is non-empty (the script was resolved via `${WORKFLOW_PLUGIN_DIR}`).
- Grep confirms no `plugin-kiln/scripts/` or `plugin-shelf/scripts/` strings in `report-mistake-and-sync.json`:
  ```bash
  grep -E 'plugin-(kiln|shelf)/scripts/' ~/.claude/plugins/cache/yoshisada-speckit/kiln/*/workflows/report-mistake-and-sync.json && echo FAIL || echo OK
  ```

---

## Exit criteria (all must pass)

- [ ] Step 2a output file exists and matches the format.
- [ ] Step 2b produced a schema-conformant artifact under `.kiln/mistakes/`.
- [ ] Step 2c produced a proposal under `@inbox/open/` with correct frontmatter and body.
- [ ] Step 3 accept-and-move leaves the source artifact in place.
- [ ] Step 4 second sync does not re-create the proposal; manifest shows `filed`.
- [ ] Step 5 hedge-word lint rejects on first try and accepts the revised input.
- [ ] Step 6 portability check returns OK from a consumer-only install.
- [ ] Exactly one state file in `.wheel/history/success/` per run; no orphans in `.wheel/state_*.json`.
