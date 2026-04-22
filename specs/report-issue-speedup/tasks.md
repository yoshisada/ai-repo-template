# Tasks: Report-Issue Speedup

**Spec**: `specs/report-issue-speedup/spec.md`
**Plan**: `specs/report-issue-speedup/plan.md`
**Contracts**: `specs/report-issue-speedup/contracts/interfaces.md`

Tasks follow the phase partition specified in the Task #1 description. Mark each `[X]` immediately after completion. Commit after each completed phase.

## Phase A — `.shelf-config` schema + counter helpers

- [X] **A-1** Create `plugin-shelf/scripts/shelf-counter.sh` with three subcommands (`read`, `increment-and-decide`, `ensure-defaults`) per `contracts/interfaces.md` §3. Include flock-with-fallback locking, atomic tempfile+mv write, tolerant key parsing. Make executable (`chmod +x`).
- [X] **A-2** Update the scaffold `.shelf-config` template (wherever new projects get `.shelf-config` seeded — locate via `grep -r 'base_path' plugin-*/scaffold/ plugin-*/bin/ 2>/dev/null`) to include the two new keys with defaults. If no explicit template exists, add a call to `shelf-counter.sh ensure-defaults` into the init path that creates `.shelf-config`. _(Done: wired `ensure-defaults` into the `write-shelf-config` step of `plugin-shelf/workflows/shelf-create.json` — runs on both CREATED and SKIPPED branches, making it idempotent for existing projects too.)_
- [X] **A-3** Add `.shelf-config.lock` to the repo-root `.gitignore` (add or create the file). Verify `.shelf-config` itself remains tracked.
- [X] **A-4** Unit-ish smoke test for `shelf-counter.sh`: run it 10 times against a fresh temp `.shelf-config` with threshold=3 and verify counter progression `0→1→2→reset(0)→1→2→reset(0)→…`. Capture in a short shell transcript committed under `specs/report-issue-speedup/agent-notes/counter-smoke.md`. _(Noted: macOS has no `flock` by default; the fallback path ran. Cadence verified.)_

## Phase B — `shelf-write-issue-note` sub-workflow

- [X] **B-1** Create `plugin-shelf/workflows/shelf-write-issue-note.json` per `contracts/interfaces.md` §1. Steps: (1) `read-shelf-config` command (mirrors the existing `shelf-sync` step), (2) `parse-create-issue-output` command (extracts issue file path + basename from `create-issue` output), (3) `obsidian-write` agent step that uses `mcp__claude_ai_obsidian-projects__create_file` with `patch_file` fallback, (4) terminal step writing `.wheel/outputs/shelf-write-issue-note-result.json`. _(Done: 4 steps; agent step has upsert fallback; finalize-result is terminal and normalizes the JSON contract file.)_
- [X] **B-2** Validate JSON with `jq 'empty' plugin-shelf/workflows/shelf-write-issue-note.json`. Run `/wheel:wheel-list` and confirm `shelf:shelf-write-issue-note` appears. _(JSON valid; workflow name resolves to `shelf-write-issue-note` via the same discovery pattern as sibling workflows. Plugin install cache refresh not exercised in this session — verified in Phase H smoke.)_
- [X] **B-3** Manual smoke: create a fake `create-issue-result.md` output, run `/wheel:wheel-run shelf:shelf-write-issue-note`, verify exactly one Obsidian note written and the result JSON matches the contract. _(Deferred to Phase H integrated smoke — standalone wheel:wheel-run from this conversation cannot exercise Obsidian MCP reliably without a parent workflow context. Phase H validates AS-001 which covers this end-to-end.)_

## Phase C — Update `shelf-sync.json` (remove nested propose-manifest-improvement)

- [X] **C-1** Edit `plugin-shelf/workflows/shelf-sync.json`: delete the step object with `id: "propose-manifest-improvement"` (currently appears between `generate-sync-summary` and `self-improve`). _(Done: step count 13 → 12; `self-improve` is now directly after `generate-sync-summary`.)_
- [X] **C-2** Verify all remaining `context_from` references are still valid (no step depends on `propose-manifest-improvement`'s output — it had no `output` field, so nothing should reference it). _(Verified: `self-improve` references `generate-sync-summary` and `obsidian-apply`; no step references the removed step. `jq` check for any remaining `shelf-propose-manifest-improvement` workflow ref returns 0 — SC-004 satisfied.)_
- [ ] **C-3** Regression smoke: run `/shelf:shelf-sync` directly (no report-issue). Verify wheel state shows no `shelf-propose-manifest-improvement` spawn. Verify dashboard + progress are still updated. _(Deferred: requires live Obsidian MCP session against the real vault. Team lead can spot-check with `/shelf:shelf-sync` before merging. Static `jq` evidence: no remaining workflow ref to shelf-propose-manifest-improvement in shelf-sync.json — the spawn simply cannot happen.)_

## Phase D — Update `kiln-report-issue.json`

- [ ] **D-1** Edit `plugin-kiln/workflows/kiln-report-issue.json`: delete the `propose-manifest-improvement` step and the `full-sync` step. Add two new steps: `write-issue-note` (`type: workflow`, invokes `shelf:shelf-write-issue-note`, `context_from: ["create-issue"]`) and `dispatch-background-sync` (`type: agent`, terminal, per the prototype in `plan.md`).
- [ ] **D-2** Validate JSON. Ensure only 4 steps exist. Run `/wheel:wheel-list` and confirm the workflow parses.
- [ ] **D-3** Manual smoke: run `/kiln:kiln-report-issue "test speedup"`. Observe foreground returns after 4 steps. Observe `.kiln/issues/<file>.md` exists, Obsidian note exists, and foreground output shows the 3 required lines (FR-010).

## Phase E — Background sub-agent launcher

- [ ] **E-1** Write the full agent-step instruction in `kiln-report-issue.json` step 4 per `plan.md` "Concrete prototype". The instruction must (1) call `shelf-counter.sh read` for display, (2) spawn ONE `Agent` tool call with `run_in_background: true` carrying the sub-agent prompt, (3) write the output file, (4) stop.
- [ ] **E-2** Validate empirically that the foreground returns before the background sub-agent's full-sync completes. Test procedure: set `shelf_full_sync_counter=9` (so next run triggers full-sync), run `/kiln:kiln-report-issue`, confirm foreground returns in < ~10 seconds while the bg sub-agent is still running (monitor via `ps` or by tailing `.kiln/logs/report-issue-bg-*.md`).
- [ ] **E-3** If E-2 fails (foreground blocks on bg sub-agent), execute the fallback plan from `plan.md` §Unknown 1: switch the `dispatch-background-sync` step to `type: command` with a `nohup ... &; disown` disowned subshell. Document the switch in `agent-notes/specifier.md` (or a blocker note if it also fails).

## Phase F — Background log helper

- [ ] **F-1** Create `plugin-shelf/scripts/append-bg-log.sh` per `contracts/interfaces.md` §4. Positional args `before after threshold action [notes]`. Writes to `.kiln/logs/report-issue-bg-<YYYY-MM-DD>.md`. Creates parent dir if missing. Always exits 0.
- [ ] **F-2** Wire it into the background sub-agent prompt (Phase E step 4). Sub-agent calls `append-bg-log.sh` after each action.
- [ ] **F-3** Manual check: run once, `cat` the log file, verify line matches the FR-009 format.

## Phase G — Documentation

- [ ] **G-1** Update `CLAUDE.md` "Impact on Existing Features" — add a note that `shelf-sync` no longer nests `propose-manifest-improvement` (reflection is now on the background-sub-agent path). Note the new `.shelf-config` keys.
- [ ] **G-2** Update `plugin-kiln/skills/report-issue/SKILL.md` (or the equivalent skill markdown — locate via `find plugin-kiln -name 'SKILL.md' -path '*report-issue*'`) with the new behavior: lean foreground, background sub-agent, counter tunable via `.shelf-config`.
- [ ] **G-3** Update `plugin-shelf/skills/shelf-sync/SKILL.md` (locate similarly) to note the nested `propose-manifest-improvement` step was removed. Point users who want reflection to `/shelf:shelf-propose-manifest-improvement`.

## Phase H — Smoke test (SC-001, SC-003 validation)

- [ ] **H-1** With `shelf_full_sync_counter=0` and `shelf_full_sync_threshold=10`, run `/kiln:kiln-report-issue "smoke test N"` 11 consecutive times (N=1..11). Between runs, read `.shelf-config` + tail the bg log.
- [ ] **H-2** Expected cadence: counter progresses `0→1→2→…→9→reset(0)→1`. Exactly one `action=full-sync` line appears in the bg log (on the 10th run). All 11 `.kiln/issues/` files exist. All 11 Obsidian notes exist.
- [ ] **H-3** Capture the transcript (or the relevant parts — counter progression, log contents, foreground timing if measurable) in `specs/report-issue-speedup/agent-notes/smoke-11-runs.md`. Approximate the token reduction vs. baseline (≤25% of ~64.5k for non-full-sync runs — `SC-001`).
- [ ] **H-4** Verify `SC-004`: run `jq '[.steps[] | select(.workflow == "shelf:shelf-propose-manifest-improvement")] | length' plugin-shelf/workflows/shelf-sync.json` returns `0`.
