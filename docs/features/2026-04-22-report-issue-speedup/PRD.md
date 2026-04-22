# Feature PRD: Report-Issue Speedup

## Parent Product

- Parent PRD: [docs/PRD.md](../../PRD.md) (currently a placeholder template — product context inherited from `CLAUDE.md` and existing plugin skill set)
- Product: `@yoshisada/kiln` — spec-first development harness for Claude Code, distributed as a plugin marketplace with five plugins (kiln, shelf, clay, trim, wheel).

## Feature Overview

Restructure `/kiln:kiln-report-issue` so the synchronous path does only the minimum needed to file the issue and show it in the Obsidian dashboard. Move everything else — full GitHub↔Obsidian reconciliation (`shelf-sync`) and reflection (`propose-manifest-improvement`) — into a background sub-agent that fires every Nth invocation, gated by a counter stored in `.shelf-config`.

The user's report-issue invocation returns fast with the issue filed locally and visible in Obsidian. Heavy reconciliation still happens on a cadence but no longer blocks the user.

## Problem / Motivation

`/kiln:kiln-report-issue` today is a 4-step wheel workflow whose last two steps are expensive sub-workflows:

1. `check-existing-issues` — cheap command
2. `create-issue` — agent (classify + write `.kiln/issues/<file>.md`)
3. `propose-manifest-improvement` — sub-workflow with its own agent (reflection on the run)
4. `full-sync` — `shelf-sync` sub-workflow (13 steps, two agent calls, includes ANOTHER `propose-manifest-improvement` call nested inside)

Per `memory/project_workflow_token_usage.md`, a single `/kiln:kiln-report-issue` round-trip costs ~64.5k tokens. For what the user experiences as "file a one-line bug," that is unacceptable. The user surfaced this directly — "report issue seems like it takes WAY too long."

The actual value-carrying work is **steps 1–2 plus writing one Obsidian note**. Everything else is batchable reconciliation that does not need to be on the critical path.

## Goals

- Synchronous `/kiln:kiln-report-issue` returns after filing the local issue file and the single corresponding Obsidian note — no GitHub round-trip, no full vault reconciliation, no reflection.
- Full `shelf-sync` and `propose-manifest-improvement` still run — but in a background sub-agent that the user does not wait on.
- Full sync runs every `N` invocations (counter in `.shelf-config`, default `N=10`), not every time. This amortizes reconciliation cost over many report-issue calls.
- Remove the duplicated `propose-manifest-improvement` that currently runs inline inside `shelf-sync`. Reflection belongs at the top of the report-issue flow (now in the background sub-agent), not nested.

## Non-Goals

- Changing `.kiln/issues/*.md` file format or template.
- Changing the Obsidian MCP schema, vault layout, or note template.
- Making the threshold configurable via a CLI flag — it's a `.shelf-config` value.
- Applying the "background sub-agent + counter" pattern to other skills (`/kiln:kiln-mistake`, `/kiln:kiln-todo`, etc.). This PRD proves the pattern for report-issue only; generalizing is a follow-on.
- Building a queue/retry system for dropped background sub-agents. If a background sub-agent fails, the next report-issue invocation will increment the counter and eventually trigger another sync. Good enough.
- Changing the behavior of `/shelf:shelf-sync` when invoked directly (beyond removing its inline `propose-manifest-improvement` step).

## Target Users

Kiln plugin maintainers (primary — Ryan / yoshisada) and consumer-repo users who invoke `/kiln:kiln-report-issue` during day-to-day work. The benefit is latency: filing a backlog item should feel like jotting a note, not kicking off a multi-minute pipeline.

## Core User Stories

- **US-001** As a plugin maintainer, when I type `/kiln:kiln-report-issue <description>`, I get confirmation that the issue was filed (both local file and Obsidian note) in well under the current baseline, so I can stay in flow and not feel punished for capturing friction.
- **US-002** As a plugin maintainer, I still want my Obsidian vault to stay in sync with GitHub and the local `.kiln/issues/` tree — but not on every report-issue. Running full reconciliation every ~10 invocations is plenty.
- **US-003** As someone who directly runs `/shelf:shelf-sync` (for example, after pulling from a teammate), I want a lean sync that does reconciliation without the nested reflection step — reflection is a separate concern that runs on its own cadence.

## Functional Requirements

- **FR-001 Lean synchronous path.** The foreground `/kiln:kiln-report-issue` flow runs, in order: (1) `check-existing-issues`, (2) `create-issue` agent (produces `.kiln/issues/<file>.md`), (3) a new single-issue Obsidian write sub-workflow, (4) fire-and-forget spawn of the background sub-agent, (5) return to the user. No `shelf-sync`, no `propose-manifest-improvement`, on this path.
- **FR-002 Single-issue Obsidian write sub-workflow.** A new shelf sub-workflow (proposed name `shelf-write-issue-note`) owns creating ONE Obsidian note for the newly-filed issue — no vault-wide reconciliation, no manifest update, no GitHub fetch. It uses the same Obsidian note template that `shelf-sync` uses today so notes written by both paths converge.
- **FR-003 Background sub-agent dispatch.** After the Obsidian note is written, `/kiln:kiln-report-issue` spawns a background sub-agent (via Claude Code's Agent tool with `run_in_background: true`) and returns immediately. The main skill does NOT wait on the sub-agent to complete.
- **FR-004 Counter-gated full sync.** The background sub-agent reads `shelf_full_sync_counter` from `.shelf-config`, increments it by 1, then: if the new value ≥ `shelf_full_sync_threshold` (default `10`), runs `/shelf:shelf-sync` AND `/shelf:shelf-propose-manifest-improvement`, then resets the counter to `0`; else writes the incremented value back and exits.
- **FR-005 `.shelf-config` keys.** Two new keys: `shelf_full_sync_counter` (integer, default `0`) and `shelf_full_sync_threshold` (integer, default `10`). The scaffold / init flow writes the defaults; existing `.shelf-config` files are upgraded on next read (missing keys are treated as defaults and written back).
- **FR-006 Counter concurrency.** The counter read-modify-write is protected by a file lock (`flock` on `.shelf-config` or a sibling lockfile) so two near-simultaneous report-issue invocations do not lose increments. If locking is unavailable for some reason (exotic shells, Windows), fall back to a "best-effort increment with ±1 drift accepted" behavior — never hang.
- **FR-007 Remove inline `propose-manifest-improvement` from `shelf-sync`.** The `shelf-sync` workflow loses its internal `propose-manifest-improvement` step. Reflection now runs exclusively in the background sub-agent's full-sync path (as a sibling step alongside shelf-sync, not nested inside it).
- **FR-008 Background sub-agent idempotence.** If two background sub-agents overlap, each will try to increment and possibly trigger a full sync. That is fine: the `shelf-sync` workflow is already designed to be re-entrant (its own `obsidian-apply` agent uses upserts). The counter lock in FR-006 keeps their increments consistent.
- **FR-009 Observability.** The background sub-agent writes a one-line log entry per invocation to `.kiln/logs/report-issue-bg-<YYYY-MM-DD>.md` (append-only): timestamp, counter-before, counter-after, action-taken (`increment` or `full-sync`). No verbose telemetry — just enough to debug "did the background sync fire?"
- **FR-010 `/kiln:kiln-report-issue` user-facing output.** On return, the skill prints the issue file path, the Obsidian note target, and a one-line note that background reconciliation was dispatched (e.g., "background sync queued — full reconciliation next at invocation 7/10").

## Absolute Musts

1. **Synchronous path stays lean** — steps beyond local file write + single Obsidian note write MUST NOT run in the foreground. A regression here defeats the whole feature.
2. **No lost issues** — every invocation MUST produce `.kiln/issues/<file>.md` AND a visible Obsidian note before the skill returns, even if the background sub-agent fails to spawn or crashes.
3. **`/shelf:shelf-sync` still works standalone** — removing the inline `propose-manifest-improvement` step MUST NOT break direct invocations of `/shelf:shelf-sync`. The behavior change is documented but the skill itself keeps working.
4. **Tech stack: Bash + JSON + Obsidian MCP + wheel engine** — no new runtime dependencies, no new libraries. This is a workflow restructure plus a new config key.

## Tech Stack

Inherited from the parent product — no additions, no overrides. Specifically:

- Bash 5.x (hook scripts, workflow command steps, counter read-modify-write)
- JSON workflows (wheel engine)
- Markdown (skill definitions, log entries)
- Obsidian MCP tools (`mcp__claude_ai_obsidian-projects__*`, `mcp__claude_ai_obsidian-manifest__*`)
- `jq` (JSON parsing — already assumed), `flock` (counter lock — POSIX standard)
- Claude Code Agent tool with `run_in_background: true` for fire-and-forget sub-agents
- Wheel engine (`plugin-wheel/`) for workflow orchestration and sub-workflow invocation

## Impact on Existing Features

**Changed behavior**:

- **`/kiln:kiln-report-issue`** — much faster foreground path; background reconciliation invisible to the user except via the one-line status message.
- **`/shelf:shelf-sync`** — no longer runs `propose-manifest-improvement` internally. Anyone who relied on that nested reflection must now either run the reflection separately or accept that reflection only fires on the background-sub-agent path. Documented in the skill body and in CLAUDE.md.
- **`.shelf-config`** — gains two new keys. Existing configs auto-upgrade on first read (missing keys treated as defaults).

**Unchanged**:

- `.kiln/issues/<file>.md` format and template
- Obsidian note template, vault layout
- `/shelf:shelf-propose-manifest-improvement` standalone behavior
- All other plugin skills

**Known risks**:

- The background sub-agent pattern is new territory for this codebase. If `run_in_background: true` from inside a wheel `agent` step does not actually fire-and-forget (e.g., the wheel engine waits for the step to complete before returning control to the user), we'll need a different dispatch mechanism — possibly a `command`-type step that runs `claude -p "..." &` in a disowned subshell. Plan phase must validate this before implementation.
- Counter drift if `flock` is unavailable — accepted per FR-006.

## Success Metrics

- **SC-001 Foreground token/time reduction.** A single `/kiln:kiln-report-issue` invocation (with no full-sync triggered) consumes ≤ 25% of the current ~64.5k-token baseline. Measured by comparing wheel state + sub-agent transcripts before and after.
- **SC-002 Every invocation produces both artifacts.** After any `/kiln:kiln-report-issue` call, the new `.kiln/issues/<file>.md` exists AND the corresponding Obsidian note exists. Verified by a post-invocation check step in the skill itself (sanity log) plus manual spot check.
- **SC-003 Counter cadence.** Running `/kiln:kiln-report-issue` 10 times in a row triggers exactly one full-sync (on the 10th invocation), with the counter at `0` after the fire and incrementing `1, 2, …, 9` on the preceding calls. Verified by reading `.shelf-config` + the bg log.
- **SC-004 `shelf-sync` standalone leanness.** Running `/shelf:shelf-sync` directly does not invoke `propose-manifest-improvement` anywhere. Verified by grep for step IDs in the workflow JSON and by inspecting wheel state after a direct invocation.

## Risks / Unknowns

- **Background-agent mechanics inside wheel.** The Claude Code `Agent` tool supports `run_in_background: true` at the top level, but whether a wheel `agent`-type step respects it (or blocks until the sub-agent completes) is unverified. Plan phase must probe this and, if needed, specify a fallback: use a `command`-type step that runs `claude -p "<prompt>" >/dev/null 2>&1 &` or similar disowned subshell. Prototype early.
- **Counter lock portability.** `flock` is POSIX but Bash-on-Windows (Git Bash, WSL) behavior varies. The fallback to "best effort, ±1 drift" (FR-006) is the safety valve.
- **Obsidian MCP availability from background sub-agent.** The background sub-agent needs Obsidian MCP tools. If the sub-agent spawns in a context without those MCP servers loaded, the full-sync leg will fail. Plan phase confirms the MCP surface inherits into sub-agents.
- **Existing nested `propose-manifest-improvement`** — removing it from `shelf-sync` is a behavioral change that could surprise downstream users if any have built automation around the inline call. Scan for direct references before landing.

## Assumptions

- The wheel `agent`-type step can spawn a sub-agent with `run_in_background: true` and return control immediately. If this turns out false, the plan phase's fallback (command-step with disowned subshell) keeps the design intact.
- `.shelf-config` is safe to read-modify-write under a file lock. Today's config is plain-text key-value, not a managed format.
- 10 is a sensible default threshold — frequent enough that Obsidian dashboard drift stays small (≤10 issues un-reconciled at any time), sparse enough to amortize sync cost. Tunable per-project via `.shelf-config`.
- Single-issue Obsidian note writes share the template with `shelf-sync`'s bulk path, so notes converge in format regardless of which path created them.
- No other skill currently depends on `propose-manifest-improvement` firing inside `shelf-sync`. If the plan phase finds one that does, it becomes an explicit blocker to document.

## Open Questions

- Should the foreground path's "background sync queued" one-liner be verbose (show counter `N/threshold`) or silent? Default to verbose; flip to silent via a `.shelf-config` flag if users find it noisy — out-of-scope for this PRD, tracked as follow-on.
- Should the background log be per-day (`.kiln/logs/report-issue-bg-<YYYY-MM-DD>.md`) or a single rolling file? Per-day keeps files small and greppable by date — going with that unless the plan phase finds a better pattern.
