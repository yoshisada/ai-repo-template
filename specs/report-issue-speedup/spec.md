# Spec: Report-Issue Speedup

**Feature branch**: `build/report-issue-speedup-20260422`
**PRD**: `docs/features/2026-04-22-report-issue-speedup/PRD.md`
**Status**: Draft
**Date**: 2026-04-22

## Overview

Restructure `/kiln:kiln-report-issue` so the synchronous foreground path only does the minimum work needed to file the backlog issue (local `.kiln/issues/<file>.md` + single corresponding Obsidian note) and then returns. The existing `shelf-sync` reconciliation and `shelf-propose-manifest-improvement` reflection move into a background sub-agent that is dispatched fire-and-forget on every invocation but only performs the heavy work once every N invocations, gated by a counter in `.shelf-config`. As a secondary cleanup, `shelf-sync` drops its inline `propose-manifest-improvement` nested step — reflection is no longer duplicated.

## User Stories

### US-001 — Fast backlog capture (primary, from PRD US-001)

**As** a plugin maintainer
**I want** `/kiln:kiln-report-issue <description>` to return quickly after filing the issue
**So that** capturing friction does not pull me out of flow.

**Given/When/Then**:
- **Given** I am inside a consumer repo where `/kiln:kiln-report-issue` is available
- **When** I run `/kiln:kiln-report-issue "my bug description"`
- **Then** the skill returns after completing (1) `check-existing-issues`, (2) `create-issue` agent, (3) single-issue Obsidian note write, (4) background sub-agent dispatch — and NOT after running `shelf-sync` or `shelf-propose-manifest-improvement` in the foreground.

### US-002 — Obsidian dashboard stays roughly in sync (from PRD US-002)

**As** a plugin maintainer
**I want** my Obsidian vault reconciled with GitHub and local backlog on a cadence
**So that** the dashboard does not silently drift even though I am no longer paying for reconciliation on every invocation.

**Given/When/Then**:
- **Given** `.shelf-config` has `shelf_full_sync_threshold=10` and `shelf_full_sync_counter=9`
- **When** I run `/kiln:kiln-report-issue` for the 10th time in a row
- **Then** the background sub-agent runs full `/shelf:shelf-sync` AND `/shelf:shelf-propose-manifest-improvement`, resets `shelf_full_sync_counter` to `0`, and writes a log line to `.kiln/logs/report-issue-bg-<YYYY-MM-DD>.md` with `action-taken=full-sync`.

### US-003 — Leaner direct `/shelf:shelf-sync` (from PRD US-003)

**As** someone running `/shelf:shelf-sync` directly (e.g., after a teammate pull)
**I want** `shelf-sync` to no longer nest `propose-manifest-improvement` inside itself
**So that** reflection is a separate concern, called on its own cadence, not duplicated.

**Given/When/Then**:
- **Given** I run `/shelf:shelf-sync` directly
- **When** the workflow completes
- **Then** no `propose-manifest-improvement` step executed (verified by `jq` on `plugin-shelf/workflows/shelf-sync.json` — no step with `workflow: "shelf:shelf-propose-manifest-improvement"`).

## Functional Requirements

Each FR traces back to the corresponding PRD requirement.

### FR-001 — Lean synchronous path (PRD FR-001)

The `/kiln:kiln-report-issue` wheel workflow (`plugin-kiln/workflows/kiln-report-issue.json`) MUST consist of exactly four ordered steps in the foreground path:

1. `check-existing-issues` (command — unchanged)
2. `create-issue` (agent — unchanged)
3. `write-issue-note` (workflow — invokes new sub-workflow `shelf:shelf-write-issue-note`)
4. `dispatch-background-sync` (agent OR command, decided in plan — fire-and-forget dispatch of background sub-agent; terminal step)

The existing `propose-manifest-improvement` step and the `full-sync` step MUST be removed from this workflow JSON.

### FR-002 — Single-issue Obsidian note sub-workflow (PRD FR-002)

A new shelf sub-workflow named `shelf-write-issue-note` MUST exist at `plugin-shelf/workflows/shelf-write-issue-note.json`. It creates ONE Obsidian note for the freshly-filed backlog issue (the file produced by `create-issue`). It MUST:

- Read the new issue's path + parsed frontmatter from the output of `create-issue` (passed via wheel `context_from`).
- Use the same note template that `shelf-sync`'s `obsidian-apply` step uses for backlog issues (so notes from both paths converge in format).
- Write the note via `mcp__claude_ai_obsidian-projects__create_file` with fallback to `mcp__claude_ai_obsidian-projects__patch_file` on "already exists" (cold-start collision — mirrors `shelf-sync`'s obsidian-apply create fallback).
- MUST NOT fetch GitHub issues, MUST NOT update the dashboard, MUST NOT touch progress or manifest notes, MUST NOT call `shelf-propose-manifest-improvement`.

### FR-003 — Background sub-agent dispatch (PRD FR-003)

After `write-issue-note` completes, `/kiln:kiln-report-issue` MUST spawn a background sub-agent and immediately return control to the user. The dispatch mechanism is resolved in `plan.md` (two candidate approaches, (a) agent-step with `Agent` tool + `run_in_background: true`, or (b) command-step with disowned `claude -p` subshell — see `plan.md`). The foreground workflow MUST mark the dispatch step terminal and archive state without waiting for the sub-agent to finish.

### FR-004 — Counter-gated full sync (PRD FR-004)

The background sub-agent MUST:

1. Acquire the counter lock (FR-006).
2. Read `shelf_full_sync_counter` and `shelf_full_sync_threshold` from `.shelf-config` (treating missing keys as defaults per FR-005).
3. Increment the counter by 1.
4. If `(incremented counter) >= threshold`:
   a. Write `shelf_full_sync_counter=0` back to `.shelf-config`.
   b. Release lock.
   c. Run `/shelf:shelf-sync` to completion.
   d. Run `/shelf:shelf-propose-manifest-improvement` to completion.
   e. Append log line (FR-009) with `action-taken=full-sync`.
5. Else:
   a. Write the incremented counter back to `.shelf-config`.
   b. Release lock.
   c. Append log line (FR-009) with `action-taken=increment`.
   d. Exit.

The lock MUST be released before the heavy `shelf-sync` call so a second concurrent background sub-agent can increment the counter without waiting on `shelf-sync` to finish.

### FR-005 — `.shelf-config` keys + auto-upgrade (PRD FR-005)

Two new keys MUST be added to the `.shelf-config` schema:

- `shelf_full_sync_counter` (integer, default `0`)
- `shelf_full_sync_threshold` (integer, default `10`)

Behavior:
- Scaffold / init (`plugin-kiln/bin/init.mjs` and any `shelf` init path that writes `.shelf-config`) MUST write both keys with defaults for new projects.
- On read by the counter helper, missing keys MUST be treated as the defaults above AND written back to `.shelf-config` (auto-upgrade) so subsequent reads are consistent.
- Existing `.shelf-config` files (e.g., the one in this very repo) MUST be left structurally intact apart from the added keys — no reformatting of existing keys.

Exact format: existing `.shelf-config` uses `key = value` lines (space-padded equals). New keys MUST follow the same format.

### FR-006 — Counter concurrency (PRD FR-006)

The counter read-modify-write MUST be protected against lost updates from near-simultaneous background sub-agents. Details (exact bash, lock file location, flock fallback) are resolved in `plan.md`. Requirements the plan must satisfy:

- Normal path: `flock`-based exclusive lock on a sibling lockfile (NOT on `.shelf-config` itself, since other skills read that file).
- Fallback path (flock unavailable / fails): best-effort increment — accept ±1 drift rather than hanging or crashing.
- The lock MUST be released before the (potentially minutes-long) `shelf-sync` call. Only the read-modify-write section is serialized.

### FR-007 — Remove inline propose-manifest-improvement from shelf-sync (PRD FR-007)

`plugin-shelf/workflows/shelf-sync.json` MUST be edited to remove the step with `id: "propose-manifest-improvement"` (currently step 10 of 12 by JSON index). The step ordering and `context_from` references of all other steps MUST remain valid after the removal. The terminal step (`self-improve`) stays terminal.

### FR-008 — Background sub-agent idempotence (PRD FR-008)

If two background sub-agents overlap (both fire a `shelf-sync` at nearly the same time), both MUST be safe to run:

- `shelf-sync`'s `obsidian-apply` already uses upserts / create-or-patch fallbacks (verified in existing workflow).
- The counter lock (FR-006) guarantees no lost increments.
- No new queueing or deduplication is introduced.

### FR-009 — Observability log (PRD FR-009)

Every background sub-agent invocation MUST append ONE line to `.kiln/logs/report-issue-bg-<YYYY-MM-DD>.md` (one file per calendar day, UTC). Line format (pipe-delimited, so `grep`-able):

```
<ISO-8601 UTC timestamp> | counter_before=<N> | counter_after=<N> | threshold=<N> | action=<increment|full-sync> | notes=<optional short string>
```

Examples:
```
2026-04-22T17:03:12Z | counter_before=3 | counter_after=4 | threshold=10 | action=increment | notes=
2026-04-22T18:45:01Z | counter_before=9 | counter_after=0 | threshold=10 | action=full-sync | notes=
```

The log file MUST be created if missing (first write of the day). Parent directory `.kiln/logs/` MUST be created if missing.

### FR-010 — Foreground user-facing output (PRD FR-010)

On return from `/kiln:kiln-report-issue`, the user MUST see, at minimum:

- The path to the newly created `.kiln/issues/<file>.md`.
- The Obsidian note target path (e.g., `@second-brain/projects/<slug>/issues/<file>.md`).
- A one-line status that background reconciliation was dispatched, showing current counter and threshold — e.g., `background sync queued — full reconciliation next at invocation 7/10`.

The background sub-agent's own output (its log line, whether or not it triggered a full sync) MUST NOT block the foreground return.

## Absolute Musts (from PRD)

1. **Synchronous path stays lean.** Only 4 ordered steps run in the foreground; no `shelf-sync`, no `shelf-propose-manifest-improvement`. (FR-001)
2. **No lost issues.** Every invocation produces `.kiln/issues/<file>.md` AND an Obsidian note before the skill returns, even if the background sub-agent fails to spawn or crashes. (FR-001 + FR-002; the dispatch step runs AFTER the note-write step, so if dispatch fails, the artifacts already exist.)
3. **`/shelf:shelf-sync` still works standalone.** After FR-007, a direct invocation of `/shelf:shelf-sync` still produces a dashboard update, progress entry, and obsidian-apply — just without the nested reflection.
4. **No new runtime dependencies.** Bash + jq + flock + Obsidian MCP + wheel engine — all already present. No new libraries.

## Success Criteria (from PRD)

### SC-001 — Foreground token reduction

One `/kiln:kiln-report-issue` invocation that does NOT trigger a full sync (i.e., counter increments but doesn't roll over) consumes ≤ 25% of the current ~64.5k-token baseline. Measured by comparing wheel state + sub-agent transcripts before and after.

### SC-002 — Every invocation produces both artifacts

After any `/kiln:kiln-report-issue` call, `.kiln/issues/<new-file>.md` exists AND the corresponding Obsidian note exists. Verified by a post-invocation sanity check (manual spot-check against Obsidian vault + `ls .kiln/issues/`).

### SC-003 — Counter cadence

Running `/kiln:kiln-report-issue` 10 times in a row triggers exactly one full-sync (on the 10th invocation), with the counter at `0` after it fires and incrementing `1, 2, …, 9` on the preceding calls. Verified by reading `.shelf-config` and `.kiln/logs/report-issue-bg-<YYYY-MM-DD>.md` between runs.

### SC-004 — shelf-sync standalone leanness

After FR-007 lands, `jq '[.steps[] | select(.workflow == "shelf:shelf-propose-manifest-improvement")] | length' plugin-shelf/workflows/shelf-sync.json` returns `0`. A direct `/shelf:shelf-sync` invocation does not spawn a reflection step (verified by inspecting wheel state file after the run).

## Acceptance Scenarios

- **AS-001** (validates US-001, FR-001, FR-002, FR-003, FR-010): Run `/kiln:kiln-report-issue "test friction A"` in a repo with `shelf_full_sync_counter=0`. Skill returns after creating the issue file, Obsidian note, and dispatching background sub-agent. Foreground transcript shows only the 4 lean steps.
- **AS-002** (validates US-002, FR-004, FR-009): Run `/kiln:kiln-report-issue` 10 times in a row. After the 10th run, `.shelf-config` has `shelf_full_sync_counter=0`, the bg log shows exactly one `action=full-sync` line (the 10th), and the Obsidian vault has all 10 new issue notes present + the dashboard refreshed.
- **AS-003** (validates FR-005, init path): Delete `shelf_full_sync_counter` and `shelf_full_sync_threshold` keys from `.shelf-config`. Run `/kiln:kiln-report-issue` once. After the run, both keys exist in `.shelf-config` with the auto-written defaults (counter=1, threshold=10), and the bg log shows one `action=increment` line.
- **AS-004** (validates US-003, FR-007, SC-004): Run `/shelf:shelf-sync` directly (no report-issue). Wheel state shows no step with `workflow: "shelf:shelf-propose-manifest-improvement"`. Dashboard and progress notes still updated.
- **AS-005** (validates FR-006): Start two background sub-agents nearly simultaneously (simulated by running `/kiln:kiln-report-issue` twice in rapid succession with `shelf_full_sync_counter=8`). Final counter value after both bg sub-agents finish is `10 → reset to 0` OR `9 + 1 → 10 → reset to 0` — never `9` (lost increment).
- **AS-006** (validates FR-010): Foreground output of `/kiln:kiln-report-issue` always contains the three lines required by FR-010.

## Out of Scope

All items from PRD "Non-Goals":

- Changing `.kiln/issues/*.md` file format or template.
- Changing the Obsidian MCP schema, vault layout, or note template.
- Making the threshold CLI-configurable (it's a `.shelf-config` value).
- Generalizing the pattern to `/kiln:kiln-mistake`, `/kiln:kiln-todo`, or other skills.
- Queue/retry system for dropped background sub-agents.
- Changes to `/shelf:shelf-sync` behavior beyond removing the nested `propose-manifest-improvement` step.

## Dependencies

- Wheel engine (`plugin-wheel/lib/`) — already present, used for workflow orchestration. No changes to wheel core required.
- Obsidian MCP (`mcp__claude_ai_obsidian-projects__*` + `mcp__claude_ai_obsidian-manifest__*`) — already present, used for note writes.
- Claude Code Agent tool with `run_in_background: true` — already used elsewhere in this codebase (`plugin-wheel/lib/dispatch.sh:1731`), so the mechanism is proven to work for at least one dispatch path.
- `jq`, `flock` — both POSIX-standard, assumed available.
