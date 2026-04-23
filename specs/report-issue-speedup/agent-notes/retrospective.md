# Retrospective notes — report-issue-speedup

Author: retrospective teammate
Date: 2026-04-22
Branch: `build/report-issue-speedup-20260422`
PR: https://github.com/yoshisada/ai-repo-template/pull/129

## How I read the signals

Primary input: the three agent-notes files (`specifier.md`, `implementer.md`, `auditor.md`) + `blockers.md` + the team lead's brief. The agent-notes convention worked well — I did not need to poll live teammates, which kept context small and findings concrete. Every friction point I flag below is backed by a direct quote from one of the three notes plus a commit hash where relevant.

## The single recurring theme

**Teammates cannot invoke slash commands.** This blocked both the implementer (B-3, C-3, D-3, E-2, H-1 — implementer.md §"Phase B-3 + D-3 + E-2") and the auditor (DG-1, DG-2, DG-3 — auditor.md §"live verification gates"). It is the same wall, hit twice in a row, by two different roles. That is not a one-off friction; it is a pipeline-design invariant that the `/kiln:kiln-build-prd` brief does not name.

Today's mitigation is good enough — the auditor wrote `blockers.md` §"Deferred pre-merge validation" with exact DG-1/DG-2/DG-3 procedures, and the PR body carries them as a `- [ ]` checklist for the team lead to tick off in the main thread. That is a clean solve *for this PR*. But the convention was invented ad hoc by the auditor and is not documented in the skill. The next pipeline that touches a live-verification gate will rediscover it.

**The right fix**: add a "MAIN-THREAD ONLY" marker convention to task descriptions, and teach the team-lead brief to recognise when a task is inherently main-thread (slash-command invocation, interactive prompts, Obsidian MCP probes that need the user's session) and mark it accordingly at `TaskCreate` time. Teammates see the marker in their `TaskGet` output and route such work back to the team lead via `SendMessage` with a pre-scripted "DEFERRED TO MAIN THREAD" protocol — instead of each teammate spending cycles explaining why they can't do it.

## Other cross-cutting observations

1. **BSD vs GNU utilities caught the implementer twice** (no `flock` on macOS, `gawk`'s `match(… , arr)` not in BSD awk). Both were fixed in-flight (commit `e699fae` for flock, `2048775` for awk). The plan documented the flock fallback (plan.md §Unknown 2) but not the awk divergence. Implementer briefs in build-prd should carry a standing "POSIX-portable by default" reminder — BSD/GNU utility divergences are a recurring class of bug in bash-heavy plugins, and the cost of flagging the class is a single sentence in the brief.

2. **Scaffold template ambiguity (A-2) was resolved cleanly by the implementer** (wiring `shelf-counter.sh ensure-defaults` into `shelf-create.json`'s `write-shelf-config` step — commit `e699fae`, implementer.md §"1. Scaffold .shelf-config template"). The specifier flagged this as underspecified in specifier.md §"Scaffold template location (Phase A-2)"; the implementer made a pragmatic call. This worked because the plan permitted the fallback explicitly ("If no explicit template exists, add a call to `shelf-counter.sh ensure-defaults`"). The lesson is not that the plan should have been less ambiguous — it is that **leaving a small, bounded seam for the implementer to close was the right move**, precisely because the specifier could not empirically resolve it in spec-only time.

3. **Prototype-early discipline did happen and did catch bugs**. The implementer prototyped the counter in Phase A smoke (counter-smoke.md) and the log appender in Phase H, and caught two silent-wrong-answer bugs: the `append-bg-log.sh` newline strip (commit `508b568`) and the BSD-awk parser bug (commit `2048775`, both described in implementer.md §"What the plan got wrong"). Both were of the form "script returns plausible output but is silently wrong". Prototype-early caught them; a later live-only test would probably have missed them because `grep -c 'action=full-sync'` would have matched on the concatenated line. Worth preserving the pattern.

4. **"Resolve two unknowns in plan" pattern was effective**. The PRD flagged FR-003's dispatch mechanism and FR-006's concurrency as unknowns. The specifier picked option (a) for FR-003 with documented rationale and a named fallback (specifier.md §"FR-003 dispatch mechanics"); the plan named the flock fallback explicitly. Implementer did not have to re-derive either. The only gap: the plan could not empirically verify that `run_in_background: true` actually returns foreground — that remains DG-2 in the deferred gates. The pattern is sound; the failure mode is the live-check constraint from theme #1.

5. **The three round-trips the team lead handled** (spec unblocks impl, impl unblocks audit, audit clarification about live checks) all traced back to theme #1. Each round-trip was effectively "teammate hit the main-thread wall, team lead needed to adjust scope or unblock with a DEFERRED marker." If the MAIN-THREAD-ONLY convention existed, two of those three round-trips would have been eliminated at task-creation time.

## What went well (evidence-backed)

- **Agent-notes as retro input** (FR-010 of kiln-build-prd): replaced live polling of teammates. I read three files and `blockers.md`, total ~350 lines, and had the full picture. No token cost to interrupt live agents for status. Auditor noted this too (auditor.md §"What went smoothly": "The implementer's `implementer.md` note was invaluable").
- **Static evidence + bash-layer exercise covered what live couldn't**: 11-iteration counter smoke (counter-smoke.md, ran twice — scratchdir in Phase A-4, real config in audit Pass 3) proved SC-003 cadence empirically without any slash-command invocation. Auditor independently re-ran it against this repo's real `.shelf-config` and got identical results (commit `a4c1e5a`). Demonstrates the "when slash commands aren't available, simulate the underlying primitive at the bash layer" pattern.
- **Deferred-gates checklist in PR body** (PR #129 `- [ ]` checkboxes): clean solve for "teammates can't finish what only the main thread can finish". The team lead gets a tight, procedure-documented checklist to tick off, and the blockers.md cross-reference means nothing is buried.
- **Plan's named fallbacks eliminated mid-pipeline panic**. When the implementer couldn't empirically validate E-2 (option a returns foreground fast), they did not have to derive option b; it was already pre-scripted in the dispatch step's instruction text (commit `468cfca`). Mid-pipeline unknown → documented fallback is the right pattern.
- **Parallel-per-plugin applied cleanly**. Phases A (shelf) and B (shelf) and D (kiln) could in principle have been parallelised by plugin; this run did them serially (single implementer) but the shape of the phase inventory supports future parallelisation. Worth preserving in the phase-partition template.
- **Behavior-change audit was bounded and concrete**. auditor.md §"What went smoothly" 3rd bullet: "Behavior-change grep sweep was concrete and bounded (the PRD explicitly named it as a gate)." The PRD named the gate; the auditor ran exactly one grep sweep and closed it. When auditors have precise gates named upfront, audits are boring — that is a feature.

## What was painful (evidence-backed)

- **Teammates can't invoke slash commands** (theme #1 above): two teammates, back-to-back, rediscovered the same wall. Evidence: implementer.md §"Phase B-3 + D-3 + E-2", auditor.md §"The 'live verification' gates that teammates cannot actually run", blockers.md §"Deferred pre-merge validation" DG-1/2/3.
- **`[X]` markers with `(DEFERRED to live verification)` are load-bearing docs pretending to be checkboxes** (auditor.md §"The DEFERRED markers in tasks.md look like hacks"). A future reader skimming `tasks.md` may conflate "done" with "deferred-but-checked". The auditor mitigated by surfacing DG-1/2/3 in `blockers.md` with procedures, but the convention is leaky.
- **BSD/GNU utility divergence cost two mid-stream rewrites** (flock, awk). Neither was signalled in plan.md as a known class of hazard.
- **`.wheel/history/` archival files clutter every git status** (auditor.md §".wheel/ archived state files leaking into every git status"). Not in scope for this PRD; file as follow-up.
- **"Run `/kiln:kiln-report-issue` 11× live" (H-1) was too ambitious** given the main-thread constraint (auditor.md §"The pipeline's 'smoke must run 11x live' requirement is ambitious"). The underlying primitive (counter + bg log) was verifiable at the bash layer; H-1 should have specified "demote to counter=9 + counter=0 — 2 runs" from the start.

## Proposed prompt rewrites

### 1. Introduce MAIN-THREAD-ONLY marker convention (PRIMARY — apply this)

```
File: plugin-kiln/skills/kiln-build-prd/SKILL.md
Current (around line 466, end of "Key Rules for All Teammates" section):
  - **Scope-change protocol**: If you receive a message containing "SCOPE CHANGE" from the team lead, finish your current task, commit your work, and STOP. Do not start any new tasks until you receive a "RESUME" message. After resuming, re-read `tasks.md` and `contracts/interfaces.md` before starting your next task — they may have changed.

Proposed (add a new bullet immediately after the scope-change protocol bullet):
  - **Main-thread-only tasks**: If a task description begins with `[MAIN-THREAD ONLY]` or a task step requires invoking a slash command (`/specify`, `/kiln:...`, `/shelf:...`, `/wheel:...`), interactive MCP prompts, or other harness-only operations, you CANNOT execute it from a teammate context — teammates have Bash, Read/Write/Edit, Task*, SendMessage, and MCP tools, but no way to invoke slash commands. Instead: (a) do every bash-layer-simulable part of the task, (b) document the results in your agent-notes file and in `specs/<feature>/blockers.md` under "Deferred pre-merge validation" with an exact reproduction procedure, (c) mark the task `[X]` with an explicit `(DEFERRED to main thread — see blockers.md §DG-N)` suffix, and (d) send a `SendMessage` to the team lead summarising what was deferred. Do NOT silently skip. The team lead runs the deferred gates in the main thread before merge.

Why: The report-issue-speedup run (PR #129) hit this wall in two consecutive teammates (implementer tasks B-3, C-3, D-3, E-2, H-1; auditor tasks DG-1, DG-2, DG-3) and each had to independently invent a deferral convention. Codifying the convention eliminates rediscovery cost.
```

Additionally, teach the team-lead brief to tag tasks at creation time:

```
File: plugin-kiln/skills/kiln-build-prd/SKILL.md
Current (line 196, "Mandatory Tasks (NON-NEGOTIABLE — always create these)" section heading):
  ### Mandatory Tasks (NON-NEGOTIABLE — always create these)

Proposed (add a new subsection immediately BEFORE this heading):
  ### Flagging main-thread-only work at TaskCreate time

  When you create tasks, audit each one for main-thread-only work. A task is main-thread-only if it requires:
  - Invoking a slash command (`/specify`, `/kiln:...`, `/shelf:...`, `/wheel:...`) — teammates cannot invoke slash commands, only Bash and MCP tools
  - Timing or fire-and-forget behaviour that only the harness can measure
  - Interactive MCP prompts that need the user's session

  For such tasks, prefix the task description with `[MAIN-THREAD ONLY]` and include an explicit note like:
  "This task requires invoking <slash-command> in the main-thread Claude Code harness. Teammates cannot complete it. Assign the bash-layer simulation (if any) to a teammate; the live invocation stays with the team lead as a pre-merge gate in `blockers.md` §Deferred pre-merge validation."

  Most pipelines have 0–3 such tasks. The retrospective for the report-issue-speedup pipeline found that failing to flag them causes teammates to rediscover the wall and consume 10–30 minutes per rediscovery explaining why they can't proceed.

Why: Today the convention emerges ad hoc from teammate friction. Flagging at TaskCreate eliminates the ad-hoc rediscovery cost and produces a deterministic pre-merge checklist for the team lead (today the auditor manually wrote `blockers.md` §"Deferred pre-merge validation" — next time this should be an explicit pipeline output).
```

### 2. POSIX-portable-by-default reminder for implementer prompts

```
File: plugin-kiln/skills/kiln-build-prd/SKILL.md
Current (around line 382, "Implementer Prompt — QA Feedback Protocol" section):
  ### Implementer Prompt — QA Feedback Protocol (when QA engineer is present)

Proposed (add a new sibling subsection BEFORE "QA Feedback Protocol"):
  ### Implementer Prompt — POSIX-portable shell defaults (NON-NEGOTIABLE for bash-heavy plugins)

  When an implementer's scope includes shell scripts under `plugin-*/scripts/` or `scaffold/`, add this to their prompt:

  ```
  Shell scripts in this plugin run on consumer machines: macOS (BSD utilities), Linux (GNU utilities), sometimes busybox CI. Default to POSIX-portable idioms:
  - awk: no `match($0, /re/, arr)` (gawk-only); use `index()` + `substr()`
  - flock: may be absent on macOS. Gate with `command -v flock` and provide an explicit fallback (documented behaviour under race, e.g. ±1 drift).
  - date: no `-d` flag (GNU-only) on BSD; use `date -j -f` on BSD or inline ISO.
  - sed -i: syntax differs between GNU (`sed -i 'expr' file`) and BSD (`sed -i '' 'expr' file`). Prefer tempfile+mv.
  - getopt: long-option support is GNU-only on most macOS boxen.
  If a script genuinely needs a GNU-only feature, document the requirement in the script header and provide a sane fallback or error-out path.
  ```

Why: The report-issue-speedup run caught two silent-wrong-answer bugs from BSD/GNU divergence — `gawk`-style `match(... , arr)` in `parse-create-issue-output.sh` (commit `2048775`) and absent `flock` on macOS (commit `e699fae`). Both were fixed mid-stream. A standing reminder in the implementer brief would catch the class at design time, not test time.
```

### 3. Reframe "run N times live" tasks at task-creation time

```
File: plugin-kiln/skills/kiln-build-prd/SKILL.md
Current (around line 218, "Task Granularity Rule"):
  ### Task Granularity Rule
  **Each implementer MUST have exactly one task that represents ALL of their work.** ...

Proposed (add a new paragraph at the end of the "Task Granularity Rule" subsection):
  **Do not over-specify live-run cardinality.** If a task involves live slash-command invocations, specify the minimum count that validates the primitive, not the full cadence. E.g., for a counter-gated workflow with threshold=10, one `counter=threshold-1` run + one `counter=0` run (2 invocations) proves both branches. The full 11-iteration cadence is verifiable at the bash layer against the same primitive (counter script + log file), which is faster, cheaper, and teammate-executable. Naming "run 11× live" in a task forces either 30+ minutes of main-thread runtime or a silent deferral to "we proved it at the bash layer". Prefer the latter at task-design time.

Why: auditor.md §"The pipeline's 'smoke must run 11x live' requirement is ambitious" — H-1 asked for 11 live runs; the cadence was proved at the bash layer instead. The PRD → task translation cost too much live-run budget for no additional signal.
```

## Cross-cutting patterns worth preserving

- **Resolve-unknowns-in-plan**: the PRD flags candidates, the plan picks one + documents a named fallback. Worked cleanly this run; both fallbacks (flock ±1 drift; nohup+disown for dispatch) were pre-scripted and ready. Keep as standard PRD convention.
- **Deferred-gates checklist in PR body** (`- [ ]` list cross-referencing `blockers.md`): clean solve for "pipeline can't finish what only the main thread can finish". Promote from ad hoc to documented convention via the MAIN-THREAD-ONLY proposal above.
- **Parallel-per-plugin partitioning**: phases partitioned by plugin boundary (`plugin-shelf` vs `plugin-kiln`) so they could in principle be parallelised. This run did it serially; the shape supports future parallelism without repartitioning.
- **Agent friction notes as retrospective input** (FR-010): retrospective reads three files instead of polling live teammates. Fast, cheap, high-signal. Already documented in SKILL.md line 143; keep.
- **Prototype-early-catches-silent-wrong-answers**: the implementer's Phase A smoke and Phase H smoke caught two silent-wrong-answer bugs (newline strip, BSD awk). Neither would have surfaced in a "only test the slash command end-to-end" discipline. Keep the plan-level expectation that bash-layer primitives get exercised before they get integrated.

## Follow-up PRDs worth filing

Most findings are addressable by prompt rewrites in SKILL.md. Two recurring patterns justify dedicated follow-ups:

1. **`.wheel/history/` gitignore cleanup** (auditor.md §".wheel/ archived state files leaking into every git status"): separate small PR, not a pipeline fix. Low priority, high ergonomic value.

2. **Teammate-to-main-thread bridge** (longer-term): the `MAIN-THREAD ONLY` marker is a mitigation — it makes the boundary explicit but does not remove it. A richer follow-up would be a pipeline mechanism for teammates to *request* main-thread execution of a specific slash command with arguments, such that the team lead executes it and returns the result to the requesting teammate via `SendMessage`. This would unblock `/kiln:kiln-report-issue` style end-to-end tests from teammate context. Scope it as a wheel/team-primitives enhancement, not a kiln one. Only worth filing if the MAIN-THREAD ONLY marker convention proves inadequate after 2–3 more pipeline runs.

## Action this run

Filing the GitHub issue is the commit-worthy output. The proposed prompt rewrites are specific enough to apply, but this retrospective will recommend the team lead review and apply proposal #1 (MAIN-THREAD ONLY marker) as the single most impactful change, since it addresses the dominant theme that recurred in two consecutive teammates. Proposals #2 and #3 are smaller and can be batched into a later `/kiln:kiln-fix` pass without losing value.
