# Auditor notes — report-issue-speedup

Author: auditor teammate
Date: 2026-04-22
Branch: `build/report-issue-speedup-20260422`

## What went smoothly

- The spec, plan, tasks, contracts, and smoke-results were all well-cross-referenced. The PRD→Spec→Code→Test traceability was easy to verify: every PRD FR has a named spec FR-001..FR-010, every spec FR has a code-change location called out in `plan.md`'s component inventory, and every SC has either smoke evidence in `smoke-results.md` or a clearly named static `jq` / `grep` verification. When audits are boring, the pipeline is working.
- The implementer's `implementer.md` note was invaluable. Four points that would otherwise have cost me 20+ minutes of diffing and log-hunting were stated plainly: flock-absent-on-macOS fallback, BSD-awk-vs-gawk gotcha, newline-in-printf-via-command-substitution bug, and the scaffold-template-doesn't-exist path. Auditors thrive when implementers document the sharp edges they hit.
- Behavior-change grep sweep was concrete and bounded (the PRD explicitly named it as a gate). The one plausible-looking blocker (`kiln-mistake.json`'s terminal `shelf:shelf-sync` call) unraveled cleanly because `kiln-mistake.json` also calls `shelf:shelf-propose-manifest-improvement` explicitly as a sibling step — no behavior loss from FR-007. Naming that gate in the spec saved the audit from becoming a guessing game.

## What was harder than it should have been

### The "live verification" gates that teammates cannot actually run

The team lead's Task #3 brief explicitly asked me to run three live slash-command probes — `/shelf:shelf-sync` directly, `/kiln:kiln-report-issue` with counter=9 (to prove fire-and-forget), and `/kiln:kiln-report-issue` lean-path. None of these are achievable from a teammate Agent context. The Claude Code teammate surface exposes Bash, Read/Write/Edit, TaskList/TaskGet/TaskUpdate, SendMessage, and MCP tools — it does NOT expose "invoke a slash command" (there's no `SkillRun` or equivalent on the deferred-tools list). The implementer hit the exact same wall for tasks B-3, C-3, D-3, E-2, H-1.

**Proposed improvement to the pipeline** — when a task brief includes a live-verification step, the task description itself should state whether it requires a main-thread Claude Code harness (flag it as "MAIN-THREAD ONLY") or whether a Bash-level equivalent exists. In this case, both Phase H and Task #3 effectively required the same main-thread follow-up, so the "live check" gate is de facto a **pre-merge human-driven gate, not a pipeline-driven gate**. Marking it as such in the Task description (rather than framing it as something the teammate should do) would avoid two successive teammates spending cycles explaining why they can't do it.

### `.wheel/` archived state files leaking into every `git status`

The branch-start state included 11+ untracked `.wheel/history/*.json` and `.wheel/state_*.json` files from prior wheel runs. These are wheel's own archival artifacts, not my feature's output, and the implementer correctly noted them as pre-existing non-issues. But they clutter every `git status` and every pre-commit review, forcing me to double-check that none of my own audit activity accidentally tracked them. `.wheel/history/` should almost certainly be in `.gitignore` at the repo root; leaving it tracked just means every wheel-using repo has this friction in perpetuity. Raising this as a standalone improvement suggestion — not in scope for this PRD.

### The DEFERRED markers in `tasks.md` look like hacks

Several Phase B/C/D/E/H tasks are marked `[X]` with `(DEFERRED to live verification)` inline. Technically each one is satisfied at the static-analysis level (the bar the teammate could meet), but the convention of `[X]` means "done" and a DEFERRED gate isn't done, it's transferred. A future reader skimming `tasks.md` might miss the deferral and merge thinking the pipeline covered everything. I'd propose a new task status or prefix (`[D]` for deferred, `[~]` for partial) and wire hooks / audit skill to surface those differently than `[X]`. For this feature, I mitigated by making `blockers.md` list the three deferred gates as explicit DG-1, DG-2, DG-3 entries with reproduction procedures.

### The pipeline's "smoke must run 11x live" requirement is ambitious given the constraint

Task #2 step H-1 said "run `/kiln:kiln-report-issue "smoke test N"` 11 consecutive times" — 11 live slash-command invocations is expensive (easily 30–60 minutes of wall-clock + a fair amount of Obsidian vault clutter to clean up) even when the foreground IS fast. Suggest: demote H-1 to "run `/kiln:kiln-report-issue` once with counter=9 to verify full-sync branch + once with counter=0 to verify increment branch" — 2 live runs, not 11. The 11-iteration cadence is already proved by the bash-level script exercise (which I re-ran against the real repo's config during this audit).

## One bug I confirmed doesn't exist

The implementer's `implementer.md` warns about a past newline bug in `append-bg-log.sh` where command-substitution stripped `\n`. I re-ran 11 iterations fresh against this repo's real `.shelf-config` + the bg log file, then `grep -c 'action=full-sync' .kiln/logs/report-issue-bg-2026-04-22.md` returned exactly 1, and `wc -l` returned the expected 11 from my run. The fix held. The script's comment at line 30–32 explicitly warns future editors not to remove the newline — good defensive docs.

## Preserved contract under load

The atomic-tempfile+mv `_write_key` implementation in `shelf-counter.sh` correctly preserved this repo's `.shelf-config` top-of-file comment line, the three pre-existing keys (`base_path`, `slug`, `dashboard_path`), AND the two new keys — across 11 successive rewrites. I diffed the file content before and after the audit exercise and only the `shelf_full_sync_counter` value line differed. Solid.

## Non-blocker observations worth noting for follow-up

- `plugin-shelf/skills/shelf-propose-manifest-improvement/SKILL.md:40` still says "`shelf:shelf-sync` ... invoke this sub-workflow as their pre-terminal step". After FR-007 this is false for shelf-sync standalone (only kiln-mistake does). Wording decay — file a small doc update as a follow-up, not a blocker.
- `plugin-shelf/skills/shelf-sync/SKILL.md:176` references `docs/features/2026-04-03-shelf-sync-v2/PRD.md` as an example path — unchanged, just noting the example directory doesn't appear to exist in this tree. Cosmetic.
- Audit left behind a `.kiln/logs/report-issue-bg-2026-04-22.md` with 11 auditor-live-* lines plus the earlier implementer-smoke lines. This is the expected log file per FR-009; leaving it in place as evidence for the audit trail (it will auto-rotate per-day anyway).

## Summary

| Criterion | Verdict | Evidence |
|-----------|---------|----------|
| PRD→Spec coverage | PASS | Every PRD FR (FR-001..FR-010) mapped to a spec FR. |
| Spec→Code coverage | PASS | Every spec FR has a corresponding code diff in the 6 feature commits. |
| Spec→Test coverage | PARTIAL (see DG-1..DG-3) | Static jq/grep verification + bash-level script exercise covers most. Three live slash-command gates deferred to main-thread. |
| SC-001 (fg ≤25% of 64.5k baseline) | PASS (static) + DEFERRED empirical | Workflow composition estimate 5–10k; live measurement is DG-3. |
| SC-002 (both artifacts on every call) | STRUCTURAL PASS + DEFERRED empirical | Shape of foreground workflow guarantees artifact creation before return; end-to-end artifact check is DG-3. |
| SC-003 (counter cadence) | PASS | Live 11-iteration exercise against THIS repo's real `.shelf-config`. Exactly 1 full-sync at iter 10, cadence perfect. |
| SC-004 (shelf-sync leanness) | PASS (static) + DEFERRED empirical | `jq` + `grep` both return 0 for the removed workflow reference; live invocation is DG-1. |
| Behavior-change audit | PASS | No downstream caller depends on shelf-sync's removed inline reflection step. |
| Version bump + PR | pending team lead approval to proceed | see SendMessage thread |

Recommendation: **SHIP** after the team-lead pass DG-1, DG-2, DG-3 in the main thread. The static evidence is strong enough that I'd be surprised if the live runs failed, but the honest answer is "we'll know for sure after the main-thread probe."
