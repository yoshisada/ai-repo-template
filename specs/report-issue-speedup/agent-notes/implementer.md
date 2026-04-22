# Implementer notes — report-issue-speedup

Author: implementer teammate
Date: 2026-04-22
Branch: `build/report-issue-speedup-20260422`

## Dispatch mechanism — option (a) chosen, empirical gate deferred

Per plan.md §Unknown 1 and the team lead's unblock message, option (a) — wheel agent-step whose instruction spawns exactly one `Agent` tool call with `run_in_background: true` — was selected over option (b) (nohup + disown via a command step).

**Rationale** (restating the plan's):
- Wheel already uses this pattern at `plugin-wheel/lib/dispatch.sh:1731`.
- A detached `claude -p` subshell from a command step does NOT inherit MCP, which the bg sub-agent needs to run `shelf-sync` → it would fail at the `obsidian-apply` step.

**What I could NOT validate empirically from this teammate context**: whether the outer agent (the `dispatch-background-sync` step itself) actually returns control to wheel as soon as it writes its output file, vs. wheel waiting on the spawned sub-agent. Invoking `/kiln:kiln-report-issue` live requires the main-thread Claude Code harness, not a sub-agent Agent invocation — I can issue tool calls and shell commands but not slash commands that drive the wheel runtime.

**Concrete mitigation**: the dispatch-step instruction names the fallback mechanism (nohup + disown command-step form) inline so a maintainer applying E-3 in response to a Phase H live-test failure doesn't need to re-derive it from plan.md. They can drop in a pre-scripted command-step replacement.

**Recommendation to team lead**: in the live interactive session before merging, set `shelf_full_sync_counter = 9` in `.shelf-config`, run `/kiln:kiln-report-issue "phase-h-gate test"`, and time the foreground return. If the foreground is done in < ~15 seconds and the bg log shows the full-sync line AFTER the foreground return: E-2 passes, ship. Otherwise apply E-3.

## Counter helper — flock absent on macOS

The `command -v flock` guard in `shelf-counter.sh` correctly short-circuits the flock branch on macOS, where flock is not part of the default toolchain (the util-linux package is not installed). The fallback (unlocked atomic tempfile+mv) ran for all Phase A and Phase H smoke iterations. Contract FR-006 explicitly permits ±1 drift in this path — verified via a fresh threshold=3, 10-iteration run (Phase A-4) and the threshold=10, 11-iteration run (Phase H). No drift observed under single-process exercise (expected — drift only surfaces under true concurrent callers, which I could not simulate in this context).

**Implication for consumers**: any macOS dev without util-linux will run unlocked. In practice `/kiln:kiln-report-issue` is not typically invoked back-to-back within milliseconds, so drift is rare. If a team wants true serialization, document `brew install util-linux` or equivalent — I did NOT add this to the scaffold because it changes the tool matrix.

## append-bg-log.sh — newline bug caught in smoke

First attempt used `printf '%s' "$line"` where `$line` was built via `printf '…%s…\n' … | $( )`. Command substitution strips trailing newlines, so all 11 "lines" concatenated onto one physical line. `grep -c 'action=full-sync'` happened to return 1 anyway (because matching is per-line and only one physical line existed) — almost a silent-wrong-answer bug.

Fixed by moving the newline into the final emit site: `printf '%s\n' "$line"`. Smoke re-run produced 11 distinct lines. The learning applies broadly — don't newline-in-format + command-substitute; newline-terminate at the write site.

## Parse script — POSIX awk, not gawk

`parse-create-issue-output.sh` initially used `match($0, /regex/, arr)` for capturing groups, which is a gawk extension. macOS ships BSD awk by default and quietly failed ("awk: syntax error"), but still produced a partial JSON with empty frontmatter — another potential silent-wrong-answer bug. Rewrote using `index($0, ":")` + `substr` for POSIX portability.

**Takeaway for future scripts in this plugin**: default to POSIX awk idioms only, since plugin consumers may run on BSD (macOS), busybox (some CI), or gawk alike.

## Phase B-3 + D-3 + E-2 — live MCP and slash-command smoke deferred

These three sub-tasks all require a live interactive session to exercise the Obsidian MCP + wheel runtime end-to-end. Marked as deferred to Phase H / team-lead verification in tasks.md with explicit language. Static evidence (jq step-count checks, grep of workflow JSONs for synchronous-heavy-op references, 11-iteration counter exercise) covers everything that CAN be exercised without a live session.

## What the plan got wrong (or under-specified) that I had to correct

1. **Scaffold `.shelf-config` template**: plan.md's component #8 says "Scaffold defaults for new keys — plugin-shelf/scaffold/.shelf-config.template (or init path that writes .shelf-config)". There is no `scaffold/` dir in plugin-shelf, and `init.mjs` does not write `.shelf-config` — `/shelf:shelf-create`'s `write-shelf-config` step does. I wired `shelf-counter.sh ensure-defaults` into that step (runs on both CREATED and SKIPPED branches), which is idempotent and covers both new-project and existing-project cases. This matches the "If no explicit template exists, add a call to `shelf-counter.sh ensure-defaults`" fallback that tasks.md A-2 already permits.

2. **Sub-workflow step count**: plan.md's contract §6 says the sub-workflow has "4 steps including a terminal write-result step". A single agent step could satisfy the result-write contract (its `output` field IS the result file), but to match tasks.md B-1's literal 4-step breakdown I added a thin `finalize-result` command step whose only job is to normalize/validate the JSON contract file (fills in a `{"action":"failed",...}` stub if the agent produced nothing or invalid JSON). This also gives us a resilience property the plan didn't spec: if the agent hard-crashes before emitting, the caller still sees a well-formed contract result rather than an empty file.

3. **Agent prompt escape-sequence hygiene**: the concrete prototype in plan.md §Unknown 1 uses raw `\n` inside a JSON string, which works for JSON parse but requires care when the instruction is a multi-line markdown block. I wrote the instructions as flat-ish text with literal `\n` JSON escapes throughout, matching the style of the existing `shelf-sync` obsidian-apply instruction. This is a stylistic call — not a correction — but worth noting for future workflow authors.

4. **Self-check gating**: the task description asked for a grep self-check on the final `kiln-report-issue.json` for any residual synchronous `shelf-sync` / `propose-manifest-improvement` references outside the dispatch step. I ran that and got: the only string matches are inside `dispatch-background-sync.instruction` — which is the bg sub-agent's prompt, not a synchronous workflow-step reference. Passes per the rule's spirit and letter. Documented this distinction in commit message text for Phase D+E+F so a future reader doesn't wonder why the grep returned non-zero.

## Counter auto-upgrade of stale `.shelf-config` on this repo

The `ensure-defaults` call was run once against this repo's `.shelf-config` during Phase A commit. Before: 3 keys (base_path, slug, dashboard_path). After: 5 keys (added `shelf_full_sync_counter = 0` and `shelf_full_sync_threshold = 10` appended at the bottom). Existing keys and the top-of-file comment untouched. AS-003 (missing-keys auto-upgrade) verified.

## Known non-issues

- **Pre-existing `.wheel/history/` stopped/success state files in git status**: these predate this feature branch (from the earlier wheel grandchild fix session visible in the git log). Left them untouched — they're gitignored anyway per `.wheel/state.json` / `.wheel/.locks/` entries. Actually they are NOT ignored — but they are wheel's own state-file archival, not this feature's concern. If the team lead wants them cleaned up, a separate `git clean -n .wheel/history/` run covers it; I did not touch them because destructive-ops policy says don't unless asked.
