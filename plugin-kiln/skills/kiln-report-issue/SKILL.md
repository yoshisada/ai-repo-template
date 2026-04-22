---
name: kiln-report-issue
description: Log a bug, friction point, or improvement idea to the project backlog. Creates a timestamped entry in .kiln/issues/. Use as "/kiln:kiln-report-issue <description>" or "/kiln:kiln-report-issue #42" to import from GitHub.
---

# Report Issue — Log to Backlog

Quickly capture a bug, friction point, or improvement idea so it doesn't get lost. This skill delegates to the `report-issue` wheel workflow, which creates the issue file and syncs to Obsidian via shelf.

## User Input

```text
$ARGUMENTS
```

## Step 1: Validate Input and Gather Context

If `$ARGUMENTS` is empty, ask the user: "What's the issue? Describe the bug, friction, or improvement."

Otherwise, confirm the issue description is in the conversation context — the workflow's agent step will reference it.

### Auto-detect repo URL (FR-012)

```bash
# Detect repo URL — graceful failure if gh unavailable or not authenticated
REPO_URL=$(gh repo view --json url -q '.url' 2>/dev/null || echo "")
echo "repo_url=$REPO_URL"
```

If `REPO_URL` is non-empty, include it in the issue frontmatter as `repo: <URL>`.
If empty (gh not installed, not authenticated, or no remote), set `repo: null`.

### Extract file paths from description (FR-012)

Scan the issue description text (`$ARGUMENTS`) for file paths — strings containing `/` with common code extensions (`.ts`, `.tsx`, `.js`, `.jsx`, `.md`, `.json`, `.sh`, `.mjs`, `.py`, `.go`, `.rs`) or paths that start with `src/`, `plugin-`, `specs/`, `.kiln/`, etc.

Include any detected paths in the issue frontmatter as:
```yaml
files:
  - path/to/file1.ts
  - path/to/file2.md
```

If no file paths are found in the description, omit the `files` field entirely.

## Step 2: Run Workflow

Run `/wheel:wheel-run kiln:kiln-report-issue` to execute the workflow. The workflow runs a **lean, 4-step foreground path** (see `specs/report-issue-speedup/` for the FR-001 contract):

1. `check-existing-issues` — scans `.kiln/issues/` for duplicates
2. `create-issue` — classifies and writes the new backlog file in `.kiln/issues/`
3. `write-issue-note` — invokes `shelf:shelf-write-issue-note` to write ONE Obsidian note for the freshly-filed backlog issue. No GitHub fetches, no dashboard updates, no progress writes — just a single `create_file` (with `patch_file` fallback on cold-start collisions).
4. `dispatch-background-sync` — fire-and-forget spawn of a background sub-agent that handles heavier reconciliation, then returns control to the user with the 3-line FR-010 summary (issue path, Obsidian path, invocation-count status).

The user's issue description (from `$ARGUMENTS` above) is already in the conversation context — the workflow's agent step will use it.

### Counter-gated background reconciliation

`.shelf-config` carries two integer keys that control how often the background sub-agent runs a full reconciliation:

- `shelf_full_sync_counter` (default `0`) — increments by 1 every invocation. The background sub-agent owns this counter; the foreground only reads it for display.
- `shelf_full_sync_threshold` (default `10`) — when the counter reaches the threshold, the next background sub-agent invocation resets the counter to 0 AND runs `/shelf:shelf-sync` + `/shelf:shelf-propose-manifest-improvement` to completion.

Both keys are auto-appended to `.shelf-config` if missing (via `plugin-shelf/scripts/shelf-counter.sh ensure-defaults`). The counter RMW is flock-guarded where available; on systems without `flock` (macOS default, exotic Git Bash builds) it runs unlocked and accepts ±1 drift.

Every background invocation appends one line to `.kiln/logs/report-issue-bg-<YYYY-MM-DD>.md` (per-day file, ISO-8601 timestamps, pipe-delimited fields).

## Rules

- If the user reports multiple issues at once, run the workflow once per issue
- If `$ARGUMENTS` is empty, ask before starting the workflow — don't start it with no description
- The foreground path MUST NOT wait for the background sub-agent. If it appears to hang after step 3, the background dispatch mechanism has regressed — see `specs/report-issue-speedup/plan.md` §Unknown 1 for the designated fallback.
