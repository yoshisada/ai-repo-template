# Feature Specification: Escalation Audit — Detect Stuck State + Auto-Flip Item Lifecycle

**Feature Branch**: `build/escalation-audit-20260426`
**Created**: 2026-04-26
**Status**: Draft
**Input**: PRD `docs/features/2026-04-26-escalation-audit/PRD.md` (3 themes / 16 FRs / 5 NFRs / 7 SCs)

## User Scenarios & Testing *(mandatory)*

Three themes ship together because each closes a different "state-machine drift" loop. Themes A and B are concrete code edits; Theme C is foundational scaffolding (events-feed primitive) for verdict-tagging follow-on PRDs.

### User Story 1 — Auto-flip roadmap items on PR merge (Priority: P1) 🎯 MVP

When `/kiln:kiln-build-prd` ships a PRD via merged PR, the roadmap items in `derived_from:` automatically flip `state: distilled → state: shipped`, gain `status: shipped` + `pr: <number>` + `shipped_date: <YYYY-MM-DD>`. No manual sweeps required.

**Why this priority**: Empirically the highest-friction drift today. PR #186 just shipped 8 items that needed manual flipping (twice in this session); PR #155 stayed stale 24h. Every merged build-prd PR pays this tax until this story lands.

**Independent Test**: Drop a fake `.kiln/roadmap/items/*.md` corpus + a PRD with a `derived_from:` block, simulate `gh pr view` returning `state: MERGED`, invoke the Step 4b auto-flip sub-step inline. Assert each derived item has `state: shipped`, `status: shipped`, `pr: <stub>`, `shipped_date: <today>` patched into its frontmatter atomically. Re-run on already-shipped items — assert no double-write of `pr:` (idempotent).

**Acceptance Scenarios**:

1. **Given** a PRD with 3 entries in `derived_from:` and `gh pr view <N> --json state` returns `MERGED`, **When** Step 4b's auto-flip sub-step runs, **Then** all 3 items end with `state: shipped` + `status: shipped` + `pr: <N>` + `shipped_date: <today>` and the diagnostic line includes `auto-flip=success items=3`.
2. **Given** the same PRD but `gh pr view <N>` returns `state: OPEN`, **When** Step 4b runs, **Then** no item is mutated and the diagnostic emits `pr-state=OPEN auto-flip=skipped`.
3. **Given** an item already at `state: shipped` with a populated `pr:` field, **When** Step 4b's auto-flip is re-run on the same merged PR, **Then** the file is byte-identical (no `pr:` duplication, no `shipped_date:` overwrite).
4. **Given** `update-item-state.sh <path> shipped` is invoked with `--status shipped`, **When** the script runs, **Then** BOTH `state:` and `status:` lines are atomically rewritten in one tempfile-and-mv cycle (no partial-write window).
5. **Given** 10 derived_from items, **When** the auto-flip sub-step runs end-to-end, **Then** wall-clock elapsed time from sub-step start to diagnostic emit is ≤ 5 seconds (NFR-001).

---

### User Story 2 — `--check` flags drifted items via merged-PR cross-reference (Priority: P1)

When the maintainer runs `/kiln:kiln-roadmap --check`, any item with `state: distilled | specced` AND a populated `prd:` field whose expected build branch has a merged PR is flagged with the PR number plus a copy-paste fix suggestion. Catches every pre-existing drift across the 81-item roadmap in one sweep.

**Why this priority**: Auto-flip (US1) only catches NEW merges; existing drift requires a sweep. Without the safety net, the cleanup-cost trap stays open even after auto-flip lands. P1 because it solves SC-006 (post-merge manual verification of the 8 items just shipped).

**Independent Test**: Seed a single item with `state: distilled` + `prd: <fake>` + a fake build branch whose `gh pr list --state merged --head <branch>` returns a merged PR number; assert `--check` flags it with a `gh pr view <N>` reference and a fix command (`update-item-state.sh <path> shipped --status shipped`).

**Acceptance Scenarios**:

1. **Given** an item `state: distilled` + `prd: docs/features/<x>/PRD.md` and `git for-each-ref --points-at <merge-sha>` resolves to `build/<x>-<date>`, **When** `--check` runs, **Then** the item appears in the report under a "Merged-PR drift" section with the resolved PR number and a copy-paste shell line.
2. **Given** an item `state: distilled` with NO populated `prd:` field, **When** `--check` runs, **Then** the merged-PR cross-reference is a no-op for that item — existing checks 1–4 (NFR-004 backward-compat) emit unchanged.
3. **Given** the ref-walk fails (no merge SHA available), **When** `--check` runs, **Then** the heuristic `build/<theme>-<YYYYMMDD>` fallback is used and the report's Notes section documents the heuristic+fallback for that item (R-2 mitigation).
4. **Given** the 8 items just shipped via PR #186 (already at `state: shipped`), **When** `--check` runs, **Then** they are NOT flagged (idempotent against already-flipped items).

---

### User Story 3 — Pipeline shutdown-nag loop (Priority: P2)

After Step 6's initial `shutdown_request` broadcast, the team-lead enters `/loop` dynamic-mode polling that re-pokes stragglers every ~60s, capped at 10 ticks, with `TaskStop` force-shutdown fallback. Self-terminates when the team is empty.

**Why this priority**: Verified pattern from THIS session's PR #186 (the loop went smoothly without nag, but stragglers in earlier builds required maintainer babysitting). P2 because the maintainer has manual `wheel:wheel-stop` available; auto-nag is convenience, not a critical gap.

**Independent Test**: Direct grep-style assertions on `kiln-build-prd/SKILL.md` Step 6 verify (a) the loop invocation exists with `~60s` ticks, (b) the 10-tick cap is documented and gated, (c) the force-shutdown fallback uses `TaskStop` on the teammate's owning task, (d) the loop self-terminates when team is empty. Full `/loop` integration test deferred per B-1 substrate gap.

**Acceptance Scenarios**:

1. **Given** Step 6 is reached and the initial `shutdown_request` broadcast completes, **When** the lead enters the shutdown-nag loop, **Then** `ScheduleWakeup` is invoked with `delaySeconds` ≈ 60 and a self-pacing prompt referencing "check pipeline shutdown progress".
2. **Given** a teammate has not terminated after the initial broadcast, **When** a tick fires, **Then** `shutdown_request` is re-sent to that teammate and the diagnostic line `tick=<N> teammate=<name> action=re-poke` is emitted.
3. **Given** the same teammate has been re-poked across 10 ticks, **When** the 11th tick would fire, **Then** the lead invokes `TaskStop` on the teammate's owning task instead and emits `force-shutdown teammate=<name> reason=10-tick-timeout`. The cap is configurable via `KILN_SHUTDOWN_NAG_MAX_TICKS` (default 10) per R-3.
4. **Given** every teammate has terminated, **When** the next tick check runs, **Then** the loop self-terminates by NOT calling `ScheduleWakeup` again — Step 6 proceeds to TeamDelete.
5. **Given** a teammate that already approved-then-terminated, **When** the loop re-sends `shutdown_request` due to a polling race, **Then** the action is a no-op (no error, no wasted ticks) (NFR-005).

---

### User Story 4 — `/kiln:kiln-escalation-audit` inventories pause events (Priority: P1)

A new `/kiln:kiln-escalation-audit` skill (no flags V1) walks the last 30 days of pause-event sources (`.wheel/history/*.json` `awaiting_user_input`, git-log `confirm-never-silent` mentions, `.kiln/logs/*.md` hook-block events) and emits one markdown report at `.kiln/logs/escalation-audit-<timestamp>.md` with Summary + Events + Notes sections. NO verdict-tagging — V1 is inventory-only.

**Why this priority**: Foundation primitive that every future autonomy-calibration follow-on PRD will consume. P1 because without an inventory dump, the system can't even see its own pause patterns — and the cheaper "dump events" version per the umbrella item's design discussion is the explicit V1 scope.

**Independent Test**: Drop a fixture `.wheel/history/` with 3 known `awaiting_user_input: true` entries + a clean `.kiln/logs/`, invoke `/kiln:kiln-escalation-audit`, assert the report has exactly 3 events in `## Events` (chronological) + matching counts in `## Summary` + verdict-deferred placeholder in `## Notes`. Re-run — assert byte-identical Events section (NFR-003).

**Acceptance Scenarios**:

1. **Given** a fixture corpus with 3 wheel pause events, 1 confirm-never-silent commit, 0 hook-block events, **When** the skill runs, **Then** the report's `## Summary` shows `wheel: 3, confirm-never-silent: 1, hook-block: 0` and `## Events` lists 4 rows sorted by `(timestamp ASC, source ASC, surface ASC)`.
2. **Given** an empty corpus (no pause events anywhere), **When** the skill runs, **Then** the report body reads "No pause events found in the last 30 days" instead of failing or emitting an empty Events section.
3. **Given** a corpus with mixed-source timestamps (file mtime vs JSON `started_at`), **When** events are emitted, **Then** all timestamps are normalized to ISO-8601 UTC before sorting (OQ-3 resolution).
4. **Given** the same corpus is fed twice, **When** the skill is re-invoked, **Then** the `## Events` and `## Summary` sections are byte-identical (timestamp section header excepted) (NFR-003).
5. **Given** any run, **When** the skill emits its report, **Then** `## Notes` ends with the literal string `*Verdict-tagging deferred — see roadmap item 2026-04-24-escalation-audit for design context.*` (FR-014).

---

### User Story 5 — `kiln-doctor` `4-escalation-frequency` tripwire (Priority: P3)

When `/kiln:kiln-doctor` runs and `.wheel/history/` contains > 20 `awaiting_user_input: true` entries in the last 7 days, the doctor emits a tripwire suggesting the maintainer run `/kiln:kiln-escalation-audit`. Tripwire only — does NOT auto-invoke the skill.

**Why this priority**: Lightweight discoverability hook for US4. P3 because the maintainer can always invoke the skill manually; this is a "you may want to" prompt.

**Independent Test**: Seed `.wheel/history/` with 21 fake `awaiting_user_input: true` entries inside the 7-day window; run doctor diagnose; assert the report contains a `4-escalation-frequency` row with status `WARN` and the suggestion line `consider running /kiln:kiln-escalation-audit`.

**Acceptance Scenarios**:

1. **Given** `.wheel/history/` has 25 `awaiting_user_input: true` entries in the last 7 days, **When** doctor diagnose runs, **Then** subcheck `4-escalation-frequency` reports `WARN` with the suggestion line referencing `/kiln:kiln-escalation-audit`.
2. **Given** `.wheel/history/` has 5 `awaiting_user_input: true` entries in the last 7 days (under threshold), **When** doctor diagnose runs, **Then** subcheck `4-escalation-frequency` reports `OK` and emits no suggestion.
3. **Given** any state, **When** doctor diagnose runs, **Then** subcheck `4-escalation-frequency` does NOT auto-invoke `/kiln:kiln-escalation-audit` — the suggestion is text only.

---

### Edge Cases

- PRD with empty `derived_from:` block (or missing entirely) — Step 4b auto-flip is a no-op, diagnostic line emits `auto-flip=skipped reason=no-derived-from`.
- PRD `derived_from:` references a path that does not exist on disk (already-archived item) — append to `MISSING_ENTRIES`, log it, do NOT abort the pipeline.
- `gh` CLI unavailable / not authenticated — auto-flip degrades to no-op + diagnostic `pr-state=unknown auto-flip=skipped reason=gh-unavailable`. Step 4b does NOT abort the pipeline.
- `ScheduleWakeup` is unavailable in the harness running Step 6 — shutdown-nag loop falls through to a single fallback `wheel:wheel-stop` invocation + emits a warning.
- `.wheel/history/` does not exist — escalation-audit treats as zero events (empty-corpus path).
- Multiple PRs map to the same build branch (rare, e.g., re-opened PR) — `--check` picks the most recent merged PR per branch and notes the disambiguation in the report's Notes section.
- Hook-block events in `.kiln/logs/*.md` use varied formats — V1 grep is permissive; non-matching logs are silently ignored (no false-positive events).

## Requirements *(mandatory)*

### Functional Requirements

#### Theme A — Item lifecycle auto-flip

- **FR-001**: `plugin-kiln/skills/kiln-build-prd/SKILL.md` Step 4b MUST gain an "auto-flip roadmap items" sub-step that runs INLINE (no sub-agent) AFTER the audit-pr agent creates and merges the PR. It reads the merged PRD's `derived_from:` frontmatter, identifies entries matching `.kiln/roadmap/items/*.md`, and for each: invokes the updated `update-item-state.sh <path> shipped --status shipped` AND patches frontmatter to insert `pr: <number>` + `shipped_date: <YYYY-MM-DD>` if not already present.
- **FR-002**: `plugin-kiln/scripts/roadmap/update-item-state.sh` MUST accept an optional `--status <value>` flag in addition to its existing positional `<state>` argument. When `--status` is supplied, the script atomically rewrites BOTH the `state:` and `status:` lines inside the same tempfile-and-mv cycle. When omitted, the script's existing single-line behavior is preserved unchanged.
- **FR-003**: The auto-flip sub-step MUST fire only on PR merge confirmation. Detect via `gh pr view <number> --json state,mergedAt --jq '.state == "MERGED"'`. If the PR is not merged, the sub-step is a no-op and Step 4b emits a single diagnostic line `step4b-auto-flip: pr-state=<state> auto-flip=skipped`.
- **FR-004**: Auto-flip MUST be idempotent. Re-running the sub-step on already-`shipped` items MUST NOT double-patch `pr:` or overwrite an existing `shipped_date:`. Detection: presence of an unmodified `pr:` field with the same PR number is treated as already-applied.
- **FR-005**: `/kiln:kiln-roadmap --check` MUST gain a merged-PR cross-reference: for every item with `state: distilled | specced` AND a populated `prd:` field, resolve the PRD's expected build branch (prefer `git for-each-ref --points-at <merge-sha>`; fall back to heuristic `build/<theme>-<YYYYMMDD>` when ref-walk fails per R-2), query `gh pr list --state merged --head <branch> --json number`, flag stale items with the PR number plus a copy-paste fix command. The Notes section MUST document which path (ref-walk vs heuristic) resolved each finding.
- **FR-006**: Test fixture `plugin-kiln/tests/build-prd-auto-flip-on-merge/` (`run.sh` shape) MUST scaffold a fake `.kiln/roadmap/items/` + a fake PRD with `derived_from:`, simulate a merged PR via stub data (no live `gh` call), invoke the Step 4b auto-flip sub-step, and assert all items end at `state: shipped` + `status: shipped` + `pr: <stub>` + `shipped_date: <today>`.

#### Theme B — Pipeline shutdown-nag detection

- **FR-007**: `kiln-build-prd/SKILL.md` Step 6 MUST gain a `/loop` dynamic-mode shutdown-nag pass AFTER the initial `shutdown_request` broadcasts complete. The team-lead invokes `loop` with the prompt "check pipeline shutdown progress" and `ScheduleWakeup({delaySeconds: 60, …})`.
- **FR-008**: Each tick MUST: (a) read the current team config (`~/.claude/teams/<team>/config.json`), (b) enumerate teammates that have not terminated, (c) re-send `shutdown_request` to each non-terminated teammate, (d) emit one diagnostic line `tick=<N> teammate=<name> action=re-poke` per teammate. When the team is empty, the loop self-terminates by NOT calling `ScheduleWakeup` again.
- **FR-009**: After 10 ticks (configurable via `KILN_SHUTDOWN_NAG_MAX_TICKS`, default 10) on the same teammate, the team-lead MUST force-shutdown via `TaskStop` on the teammate's owning task and emit `force-shutdown teammate=<name> reason=10-tick-timeout`.
- **FR-010**: Test fixture `plugin-kiln/tests/build-prd-shutdown-nag-loop/` (`run.sh` shape) MUST verify the shutdown-nag contract via direct text assertions in `kiln-build-prd/SKILL.md` Step 6: (a) `ScheduleWakeup` invocation with ~60s ticks, (b) 10-tick cap with env-var override, (c) `TaskStop` force-shutdown fallback, (d) self-termination on empty team. Full `/loop` integration test deferred — wheel-hook-bound substrate gap (B-1).

#### Theme C — Escalation audit foundation

- **FR-011**: New skill `/kiln:kiln-escalation-audit` (no flags V1) MUST be shipped at `plugin-kiln/skills/kiln-escalation-audit/SKILL.md` and registered in the kiln plugin manifest. When invoked, it dumps pause events from the last 30 days to `.kiln/logs/escalation-audit-<timestamp>.md`. NO verdict-tagging — V1 is inventory-only.
- **FR-012**: Pause-event sources V1 MUST be exactly: (a) `.wheel/history/*.json` files where `awaiting_user_input == true`; (b) git log search for `confirm-never-silent` mentions in commit messages within the last 30 days; (c) hook-block events grep'd from `.kiln/logs/*.md` using a permissive regex. Each emitted row MUST be a record `{timestamp, source, event_type, context, surface}`. Idempotent — re-running on unchanged inputs MUST produce a byte-identical Events section.
- **FR-013**: Report shape MUST be: `# Escalation Audit Report — <ISO-8601-timestamp>`, then `## Summary` (event counts grouped by source AND by surface), then `## Events` (one row per event, chronological, sorted ASC by `(timestamp, source, surface)`), then `## Notes` (no-op rows, sources with zero events, error notes, verdict-deferred placeholder). Empty-corpus path: emit "No pause events found in the last 30 days" inside the report body instead of failing.
- **FR-014**: V1 MUST emit NO verdict tags. The `## Notes` section MUST end with the literal string `*Verdict-tagging deferred — see roadmap item 2026-04-24-escalation-audit for design context.*`.
- **FR-015**: Test fixture `plugin-kiln/tests/escalation-audit-inventory-shape/` (`run.sh` shape) MUST drop a fake `.wheel/history/` with 3 known `awaiting_user_input` events + a clean `.kiln/logs/`, invoke the skill, and assert the report has exactly 3 events in `## Events` and matching counts in `## Summary`.
- **FR-016**: `/kiln:kiln-doctor` MUST gain subcheck `4-escalation-frequency`: when `.wheel/history/` has > 20 `awaiting_user_input: true` events in the last 7 days, emit a `WARN` row with the suggestion line `consider running /kiln:kiln-escalation-audit`. Tripwire only — MUST NOT auto-invoke the skill.

### Non-Functional Requirements

- **NFR-001**: Step 4b auto-flip wall-clock latency ≤ 5 seconds for ≤ 10 derived_from items (typical PRD bundle). The auto-flip is small file I/O + one `gh pr view` per PR (cached) — the budget is generous; if the implementer measures > 1s the spec is comfortably under the threshold without further work.
- **NFR-002**: Test fixtures MUST be self-contained per existing kiln-test convention (no external network calls; `gh` calls stubbed via fixture data; no live `git push`).
- **NFR-003**: Escalation-audit report idempotence — re-running with the same `.wheel/history/` + `.kiln/logs/` corpus MUST produce a byte-identical `## Events` section (timestamp section header in the H1 excepted). Sort key: `(timestamp ASC, source ASC, surface ASC)`.
- **NFR-004**: Backward compat — existing `/kiln:kiln-roadmap --check` behavior on items WITHOUT a populated `prd:` field MUST be preserved. The new merged-PR cross-reference is additive.
- **NFR-005**: `/loop` shutdown-nag MUST be idempotent — re-sending `shutdown_request` to a teammate that already approved-then-terminated MUST be a no-op (no error, no wasted ticks).

### Key Entities

- **Roadmap item frontmatter** — YAML block at the top of `.kiln/roadmap/items/<id>.md`. Touched fields: `state`, `status`, `pr`, `shipped_date`. Other fields preserved byte-identical.
- **PRD frontmatter `derived_from:`** — YAML list of repo-relative paths. Read-only for this PRD; the parser is the existing `read_derived_from()` helper from Step 4b (`prd-derived-from-frontmatter` spec).
- **Pause event** — Logical record `{timestamp: ISO-8601-UTC, source: wheel|confirm-never-silent|hook-block, event_type: string, context: string, surface: skill|hook|workflow}`.
- **Escalation audit report** — Markdown file at `.kiln/logs/escalation-audit-<timestamp>.md`. Sections: H1 title, `## Summary`, `## Events`, `## Notes`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `plugin-kiln/tests/build-prd-auto-flip-on-merge/` passes (FR-006). Asserts derived_from items flip to `state: shipped` + `status: shipped` + `pr: <stub>` + `shipped_date: <today>` after a stub-merged PR.
- **SC-002**: `plugin-kiln/tests/roadmap-check-merged-pr-drift-detection/` (`run.sh` shape) passes — fixture sets up an item with `state: distilled` + `prd:` pointing at a fake-merged-PR build branch; asserts `--check` flags it with the PR number and a copy-paste fix command.
- **SC-003**: `plugin-kiln/tests/build-prd-shutdown-nag-loop/` passes (FR-010). Direct grep-style assertions on `kiln-build-prd/SKILL.md` Step 6 verify the loop invocation + 10-tick cap + force-shutdown fallback contracts.
- **SC-004**: `plugin-kiln/tests/escalation-audit-inventory-shape/` passes (FR-015). Verifies report shape + summary counts with stubbed pause-event corpus.
- **SC-005**: Re-running `/kiln:kiln-escalation-audit` on unchanged inputs produces a byte-identical `## Events` section (NFR-003 verification — covered by `escalation-audit-inventory-shape` second-run assertion).
- **SC-006**: POST-MERGE manual verification — invoke `/kiln:kiln-roadmap --check` against the live repo after this PRD ships. Assert (a) the 8 items just shipped via PR #186 are NOT flagged (they're already at `state: shipped`), AND (b) any pre-existing drifted item across the 81-item roadmap IS flagged. Substrate-blocked in-session per B-PUBLISH-CACHE-LAG carve-out 2b — documented in `blockers.md`.
- **SC-007**: `kiln-doctor` subcheck `4-escalation-frequency` fires WARN when `.wheel/history/` has > 20 `awaiting_user_input` events in the last 7 days and OK otherwise (FR-016, validated by an inline doctor smoke assertion in the audit phase).

## Assumptions

- The `gh` CLI is available and authenticated in the maintainer's environment when Step 4b auto-flip runs. When unavailable, auto-flip degrades to a logged no-op (edge case).
- The `derived_from:` frontmatter parser from `prd-derived-from-frontmatter` (`read_derived_from()`) is reusable verbatim — no signature changes to that helper required by this PRD.
- `ScheduleWakeup` is available in the team-lead's harness during Step 6 (verified pattern from PR #186 session). When unavailable, the shutdown-nag loop falls through to single-shot `wheel:wheel-stop`.
- `.wheel/history/*.json` files carry `awaiting_user_input: true` plus an embedded `started_at` ISO-8601 timestamp — consistent with the wheel-as-runtime spec output shape.
- `kiln-doctor`'s subcheck pattern follows the existing `3a..3h` numbering convention (FR-016's `4-escalation-frequency` adopts the next index).
- The maintainer is the sole consumer for V1 — multi-tenant escalation audit is out of scope.

## Dependencies & Risks

- **D-1** (FR-001): Step 4b auto-flip depends on the existing `read_derived_from()` parser shipped by `prd-derived-from-frontmatter`. No re-implementation required.
- **D-2** (FR-005): `--check`'s merged-PR cross-reference depends on the existing `parse-item-frontmatter.sh` + `list-items.sh` helpers in `plugin-kiln/scripts/roadmap/`.
- **R-1** (auto-flip): `gh` API rate limits if a single PRD has hundreds of `derived_from:` items. Mitigation: one `gh pr view --json state,mergedAt` per PR (cached), then per-item file edits — never one `gh` call per item.
- **R-2** (auto-flip): heuristic for resolving "PRD's expected build branch" may miss edge cases. Mitigation: prefer `git for-each-ref --points-at <merge-sha>`; document the heuristic+fallback in the `--check` Notes section.
- **R-3** (shutdown-nag): 10-tick cap is a magic number. Mitigation: configurable via `KILN_SHUTDOWN_NAG_MAX_TICKS` env var (default 10).
- **R-4** (escalation-audit): inventory without verdict-tagging risks the corpus never accruing. Mitigation: V1 ships inventory-only; the umbrella roadmap item stays open + in-phase so the verdict-tagging follow-on remains visible.

## Concurrent-Staging Hazard (cross-cutting — OQ-4)

Themes A and B BOTH edit `plugin-kiln/skills/kiln-build-prd/SKILL.md` (Step 4b for Theme A, Step 6 for Theme B). Per retro #187 PI-1 (commit `a85bd63`), implementer assignment MUST avoid concurrent staging on the same file. Tasks for Themes A + B are owned by ONE implementer (`impl-themes-ab`) with sequential phases. Theme C is independent (creates new files: a new skill directory + a new doctor subcheck section + new test fixtures) → owned by `impl-theme-c`.

## Decisions Resolved (from PRD Open Questions)

- **OQ-1** (auto-flip + phase file): Step 4b auto-flip does NOT re-run `update-phase-status.sh register` — the phase file's `## Items` list already includes shipped items per the existing convention. Spec records this as the V1 decision; if a follow-on PR finds the phase file drifts independently, that's a separate fix.
- **OQ-2** (shutdown-nag location): the loop-poller lives in the team-lead's main session (NOT a dedicated `shutdown-nag` agent). Matches the verified 2026-04-25 pattern; minimizes spawn overhead.
- **OQ-3** (timestamp granularity): all pause-event sources MUST be normalized to ISO-8601 UTC before sorting. `.wheel/history/` JSON `started_at` is the primary source; `.kiln/logs/*.md` filename timestamps fall through `date -u -d @<ts> +%FT%TZ` if a parseable epoch is embedded; otherwise file mtime is used (last-resort, documented in Notes).
- **OQ-4** (concurrent-staging hazard): see "Concurrent-Staging Hazard" section above.
