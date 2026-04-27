---
derived_from:
  - .kiln/roadmap/items/2026-04-24-escalation-audit.md
  - .kiln/roadmap/items/2026-04-25-build-prd-auto-flip-item-state.md
  - .kiln/roadmap/items/2026-04-25-escalation-shutdown-detection.md
distilled_date: 2026-04-26
theme: escalation-audit
---
# Feature PRD: Escalation Audit — Detect Stuck State + Auto-Flip Item Lifecycle

**Date**: 2026-04-26
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md) — kiln plugin

## Background

Recently the roadmap surfaced these items in the **10-self-optimization** phase: `2026-04-24-escalation-audit` (feature — umbrella), `2026-04-25-build-prd-auto-flip-item-state` (feature — concrete lifecycle gap), `2026-04-25-escalation-shutdown-detection` (feature — verified pattern from a real session).

The system is increasingly autonomous, but right now nothing closes the loop on **whether the system's autonomy decisions were right**. Three concrete failure modes — captured in three roadmap items — share one theme: when the system finishes work or pauses for input, the surrounding state-machine drifts away from reality unless a human manually reconciles it. PR #186's audit caught one (the 8 items that needed manual `state: distilled → shipped` flips after merge); the same friction has now recurred across multiple builds (`wheel-user-input` shipped via PR #155 and stayed stale for a day; FR-020 single-in-progress-phase invariant only tripped because of a downstream conflict). Pipeline shutdown detection has the inverse problem — the team-lead politely asks teammates to shut down once and stops, even when stragglers stay alive; the user has to notice and re-poke.

This PRD bundles the immediate-value tactical fixes (auto-flip on PR merge — Theme A) and a verified pattern for graceful pipeline windup (shutdown-nag loop — Theme B) with the broader self-improvement foundation (escalation audit — Theme C, in the cheapest "dump pause events to markdown" form per the umbrella item's design discussion). Themes A and B are concrete code/skill changes shipping in this PRD; Theme C is foundational scaffolding (the events-feed primitive) that future PRDs will consume to add verdict-tagging.

### Source Issues

| # | Source Entry | Source | Type | GitHub Issue | Severity / Area |
|---|--------------|--------|------|--------------|------------------|
| 1 | [escalation-audit](../../../.kiln/roadmap/items/2026-04-24-escalation-audit.md) | .kiln/roadmap/items/ | item | — | feature / umbrella |
| 2 | [build-prd-auto-flip-item-state](../../../.kiln/roadmap/items/2026-04-25-build-prd-auto-flip-item-state.md) | .kiln/roadmap/items/ | item | — | feature / lifecycle |
| 3 | [escalation-shutdown-detection](../../../.kiln/roadmap/items/2026-04-25-escalation-shutdown-detection.md) | .kiln/roadmap/items/ | item | — | feature / pipeline |

## Problem Statement

Three concrete drifts in the system's state machine — collectively a sign that "the system audits its own behavior" is currently aspirational, not enforced:

1. **Item-lifecycle drift on PR merge.** When `/kiln:kiln-build-prd` ships a PRD via merged PR, the roadmap items the PRD was distilled from stay frozen at `status: in-progress, state: distilled` even after merge. The PR number isn't recorded on the item. `/kiln:kiln-roadmap --check` doesn't catch this — it only validates structural fields, not "PRD's build branch has merged." Empirically: PR #155 shipped wheel-user-input on 2026-04-25; its item stayed stale for 24h until `--phase start` tripped FR-020 on a downstream conflict. PR #186 just shipped 8 items today that needed manual flipping (this session's bash script ran twice).

2. **Pipeline shutdown stragglers.** The team-lead sends `shutdown_request` to each teammate once at end-of-pipeline. If a teammate misses the signal or is mid-task, they don't shut down. The team-lead doesn't re-poke; the user has to notice. A verified pattern from THIS session's PR #186 pipeline (Step 6 shutdown sequence) shows graceful — but `/loop` dynamic-mode polling at 60s intervals could re-send shutdown_requests to stragglers automatically with bounded retries.

3. **No feedback loop on whether the system's pauses were right.** The vision win-condition is "high-signal escalations, not friction" — pauses fire only when precedent is genuinely absent. But nothing today reviews wheel `awaiting_user_input` events, skill confirm-never-silent prompts, hook blocks, or `--quick`-bypassed interviews to ask: was this pause needed, or did the gate fire when it shouldn't have? The system can't calibrate its autonomy without that feedback.

The shared theme — and what unifies these three items into one PRD — is that the system's state machine drifts when there's no automatic reconciliation step at lifecycle transitions. Theme A (auto-flip) reconciles roadmap state at merge time. Theme B (shutdown-nag) reconciles team state at pipeline end. Theme C (escalation audit) is the foundation for reconciling autonomy decisions over time.

## Goals

- **Theme A — Auto-flip on PR merge**: when a `/kiln:kiln-build-prd` pipeline's PR merges, the items in the PRD's `derived_from:` frontmatter automatically flip `state: distilled → state: shipped`, get `status: shipped`, and gain a `pr: <number>` back-reference. No manual scripts required.
- **Theme A safety net**: `/kiln:kiln-roadmap --check` gains a merged-PR cross-reference so any item that drifts (in this PRD's path or pre-existing items) is detectable in one sweep.
- **Theme B — Shutdown-nag loop**: at the end of `/kiln:kiln-build-prd` Step 6, the team-lead enters `/loop` dynamic-mode polling (~60s ticks, 10-tick cap, force-shutdown fallback via TaskStop) that re-sends `shutdown_request` to stragglers. Self-terminates when the team is empty.
- **Theme C — Escalation audit foundation (cheapest version)**: a new `/kiln:kiln-escalation-audit` skill that dumps pause events (wheel `awaiting_user_input` + skill confirm-never-silent + hook blocks) to a markdown report at `.kiln/logs/escalation-audit-<timestamp>.md`. No verdict-tagging yet — just inventory. Future PRDs add verdict-tagging once a corpus of human-tagged events accrues.
- **Cross-cutting**: every lifecycle transition gets an automation hook OR a tripwire. No silent state-machine drift.

## Non-Goals

- **Auto-verdict on pause events** (item 1's design question "How do we judge 'shouldn't have fired'?"). The cheaper version dumps events; humans review. Auto-grading is deferred until a tagged corpus exists. Avoid the circular trap of the system grading its own escalations using the same precedent that failed to prevent them.
- **Auto-promote shutdown stragglers to a separate retro issue.** That's `/kiln:kiln-pi-apply` territory — the shutdown loop just nags + force-shuts; if a teammate genuinely refused, that's a build-prd retro PI candidate, not this PRD's scope.
- **Auto-flip items distilled into a PRD that NEVER merges** (e.g., a PR closed without merging). The auto-flip fires on merged PRs only; abandoned PRDs require a maintainer call (or a separate `--reset-prd` flow already provided by `/kiln:kiln-reset-prd`).
- **Per-step-type pause-event audit** (umbrella item's design question "What counts as a pause event?"). Theme C's V1 inventories ALL pause events into one dump; per-substrate filtering is a follow-on once we see what the dump actually looks like.
- **Manifest-evolution-ledger integration** (umbrella item's design question "Relationship to manifest-evolution ledger"). The umbrella item flagged this as a design dependency; this PRD ships escalation-audit V1 as a standalone inventory (cheapest version) and lets the manifest-evolution-ledger PRD (parked in 10-self-optimization) decide its own integration when it activates.

## Implementation Hints

*(Items in this bundle don't carry non-empty `implementation_hints:` frontmatter. Source bodies above are the closest equivalent — the wheel-user-input source body's "Suggested Fix" sections A and B are the most prescriptive.)*

## Requirements

### Functional Requirements

#### Theme A — Item lifecycle auto-flip (FR-001..FR-006)

- **FR-001** (from: `2026-04-25-build-prd-auto-flip-item-state.md`) — `plugin-kiln/skills/kiln-build-prd/SKILL.md` Step 4b lifecycle gains an "auto-flip roadmap items" sub-step that runs INLINE (not a sub-agent) after the audit-pr agent creates the PR and the PR merges. It reads the merged PRD's `derived_from:` frontmatter, identifies entries matching `.kiln/roadmap/items/*.md`, and for each: runs `update-item-state.sh <path> shipped` AND patches frontmatter to add `status: shipped` + `pr: <number>` + `shipped_date: <YYYY-MM-DD>`.
- **FR-002** (from: `2026-04-25-build-prd-auto-flip-item-state.md`) — `plugin-kiln/scripts/roadmap/update-item-state.sh` (or a new sibling `update-item-status.sh`) MUST accept a `--status <value>` flag in addition to the existing `<state>` arg. Currently it only touches `state:`; the auto-flip needs to touch BOTH `state:` and `status:` atomically.
- **FR-003** (from: `2026-04-25-build-prd-auto-flip-item-state.md`) — The auto-flip step ONLY fires on PR merge confirmation. Detect via `gh pr view <number> --json state,mergedAt --jq '.state == "MERGED"'`. If the PR is not merged (still open, or closed-without-merge), the auto-flip is a no-op and Step 4b emits a diagnostic line `pr-state=<state> auto-flip=skipped`.
- **FR-004** (from: `2026-04-25-build-prd-auto-flip-item-state.md`) — Auto-flip is idempotent. Re-running the post-merge sub-step on already-`shipped` items is a no-op (no double-patching of `pr:` field; existing values preserved).
- **FR-005** (from: `2026-04-25-build-prd-auto-flip-item-state.md`) — `/kiln:kiln-roadmap --check` (FR-022 of structured-roadmap) gains a merged-PR cross-reference: for every item with `state: distilled | specced` AND a populated `prd:` field, resolve the PRD's expected build branch via heuristic `build/<theme>-<YYYYMMDD>`, query `gh pr list --state merged --head <branch>`, flag stale items with the PR number + a copy-paste fix suggestion. Catches every existing drifted item across the roadmap in one sweep.
- **FR-006** (from: `2026-04-25-build-prd-auto-flip-item-state.md`) — Test fixture `plugin-kiln/tests/build-prd-auto-flip-on-merge/` runs a `run.sh`-only fixture: scaffold a fake `.kiln/roadmap/items/` + a fake PRD with `derived_from:`, simulate a merged PR via stub data, invoke the Step 4b auto-flip, assert all items are `state: shipped` + `status: shipped` + `pr: <stub-number>`.

#### Theme B — Pipeline shutdown-nag detection (FR-007..FR-010)

- **FR-007** (from: `2026-04-25-escalation-shutdown-detection.md`) — `kiln-build-prd/SKILL.md` Step 6 (cleanup) gains a `/loop` dynamic-mode shutdown-nag pass AFTER initial `shutdown_request` broadcasts. The team-lead invokes the `loop` skill with the prompt "check pipeline shutdown progress" and `ScheduleWakeup` defaults to ~60s ticks.
- **FR-008** (from: `2026-04-25-escalation-shutdown-detection.md`) — Each tick: read team config (`~/.claude/teams/<team>/config.json`), enumerate teammates that haven't terminated, re-send `shutdown_request` to each. When the team is empty (every teammate terminated), the loop self-terminates by NOT calling `ScheduleWakeup` again.
- **FR-009** (from: `2026-04-25-escalation-shutdown-detection.md`) — Bounded retries: after 10 ticks (~10 minutes wall-clock) on the same teammate, the team-lead force-shutdown via `TaskStop` on the teammate's owning task. Diagnostic line emitted: `force-shutdown teammate=<name> reason=10-tick-timeout`.
- **FR-010** (from: `2026-04-25-escalation-shutdown-detection.md`) — Test fixture `plugin-kiln/tests/build-prd-shutdown-nag-loop/` (run.sh shape) verifies the shutdown sequence + the force-shutdown fallback contract via direct text assertions in SKILL.md (full `/loop` integration test deferred — wheel-hook-bound substrate gap, B-1).

#### Theme C — Escalation audit foundation (FR-011..FR-016)

- **FR-011** (from: `2026-04-24-escalation-audit.md`) — New skill `/kiln:kiln-escalation-audit` (no flags V1). When invoked, it dumps pause events from the last 30 days to a markdown report at `.kiln/logs/escalation-audit-<timestamp>.md`. NO verdict-tagging yet — V1 is inventory-only (cheaper version per umbrella item's design discussion).
- **FR-012** (from: `2026-04-24-escalation-audit.md`) — Pause-event sources V1: (a) `.wheel/history/*.json` files with `awaiting_user_input: true`; (b) git log search for `confirm-never-silent` mentions in commit messages; (c) hook-block events grep'd from `.kiln/logs/*.md`. Each source emits a row: `{timestamp, source, event_type, context, surface}`. Idempotent — re-running on unchanged inputs produces byte-identical output (NFR-003 sibling for this skill).
- **FR-013** (from: `2026-04-24-escalation-audit.md`) — Report shape: `# Escalation Audit Report — <timestamp>`, then `## Summary` (event counts by source + by surface), then `## Events` (one row per event, chronological), then `## Notes` (no-op rows, sources with zero events, error notes). Empty-corpus path: emit "No pause events found in the last 30 days" instead of failing.
- **FR-014** (from: `2026-04-24-escalation-audit.md`) — V1 emits NO verdict tags (`needed` / `shouldn't-have-fired` / `ambiguous`). The Notes section ends with a placeholder: "*Verdict-tagging deferred — see roadmap item 2026-04-24-escalation-audit for design context.*". Future PRD adds verdict UX.
- **FR-015** (from: `2026-04-24-escalation-audit.md`) — Test fixture `plugin-kiln/tests/escalation-audit-inventory-shape/` (run.sh) drops a fake `.wheel/history/` with 3 known pause events + a clean `.kiln/logs/`, invokes the skill, asserts the report has exactly 3 events in `## Events` + matching source counts in `## Summary`.
- **FR-016** (from: `2026-04-24-escalation-audit.md`) — `kiln-doctor` subcheck `4-escalation-frequency`: cheap signal that fires when `.wheel/history/` has >20 awaiting_user_input events in the last 7 days. Tripwire only — does NOT auto-invoke `/kiln:kiln-escalation-audit`; it just suggests "consider running `/kiln:kiln-escalation-audit`".

### Non-Functional Requirements

- **NFR-001** — Auto-flip latency: Step 4b auto-flip MUST complete within 5 seconds for ≤10 derived_from items (typical PRD bundle). Enforces the "no manual sweeps" goal — if the auto-flip is slow enough that the maintainer skips it, the PRD's value collapses.
- **NFR-002** — Test fixtures self-contained per existing kiln-test convention (no external network calls; all stubbed via fixture data).
- **NFR-003** — Escalation-audit report idempotence: re-running with the same `.wheel/history/` + `.kiln/logs/` corpus produces byte-identical Events section (timestamp section header excepted). Sort key: event timestamp ASC, then source ASC, then surface ASC. (Sibling of `/kiln:kiln-claude-audit` NFR-002.)
- **NFR-004** — Backward compat: existing `/kiln:kiln-roadmap --check` behavior preserved on items WITHOUT a populated `prd:` field. The new merged-PR cross-reference is additive (only fires on items that have a `prd:` to check).
- **NFR-005** — `/loop` shutdown-nag idempotent: re-sending `shutdown_request` to a teammate that already approved-then-terminated is a no-op (no error, no wasted ticks). Robust to teammate-state polling races.

## User Stories

- **As the kiln maintainer**, when I merge a build-prd PR, I want the source roadmap items to auto-flip to `state: shipped` with the PR number recorded — so the roadmap stays trustworthy without a manual cleanup step on every merge.
- **As the kiln maintainer**, when I run `/kiln:kiln-roadmap --check`, I want any item whose build PR has merged but state hasn't flipped to be flagged with the PR number — so I can audit and fix existing drift in one command instead of hunting per-item.
- **As the team-lead orchestrating a build-prd pipeline**, when teammates miss the initial shutdown request, I want the loop to re-poke them automatically until they shut down or the 10-tick force-shutdown fires — so the maintainer doesn't have to babysit pipeline windup.
- **As the kiln maintainer**, when I want to know whether the system's autonomy decisions have been calibrated correctly, I want a `/kiln:kiln-escalation-audit` command that dumps every pause event from the last 30 days into one report — so I can spot patterns (which surfaces fire too often, which fire correctly) before deciding which to tighten.

## Success Criteria

- **SC-001** — `plugin-kiln/tests/build-prd-auto-flip-on-merge/` passes (FR-006). Asserts derived_from items flip to `state: shipped` + `status: shipped` + `pr: <stub>` after a stub-merged PR.
- **SC-002** — `plugin-kiln/tests/roadmap-check-merged-pr-drift-detection/` passes — fixture sets up an item with `state: distilled` + `prd:` pointing at a fake-merged-PR build branch; asserts `/kiln:kiln-roadmap --check` flags it with the PR number.
- **SC-003** — `plugin-kiln/tests/build-prd-shutdown-nag-loop/` passes (FR-010). Direct grep-style assertions on SKILL.md verify the loop invocation + force-shutdown fallback contracts.
- **SC-004** — `plugin-kiln/tests/escalation-audit-inventory-shape/` passes (FR-015). Verifies report shape with stubbed pause-event corpus.
- **SC-005** — Re-running `/kiln:kiln-escalation-audit` on unchanged inputs produces byte-identical Events section (NFR-003 verification).
- **SC-006** — POST-MERGE manual verification: invoke `/kiln:kiln-roadmap --check` against the current repo (after this PRD ships); asserts the 8 items just shipped via PR #186 (which were manually flipped) are NOT flagged as drift, AND any pre-existing drifted item across the 81-item roadmap IS flagged. (Substrate-blocked in-session per B-PUBLISH-CACHE-LAG carve-out 2b.)
- **SC-007** — `kiln-doctor` subcheck `4-escalation-frequency` fires correctly when `.wheel/history/` has >20 awaiting_user_input events in the last 7 days (FR-016).

## Tech Stack

Inherited from kiln plugin: Bash 5.x, `jq`, `awk`, `python3` (stdlib `json`/`re` for YAML frontmatter parsing), `gh` CLI for PR-state queries. The `/loop` shutdown-nag pass uses Claude Code's `ScheduleWakeup` mechanic + the `loop` skill (already shipped). No new runtime dependencies.

## Risks & Open Questions

- **R-1** (auto-flip): GH API rate limits if a single PR has hundreds of derived_from items. Mitigation: batch via `gh pr view --json mergedAt` once per PR, not once per item; cache the merged-state lookup.
- **R-2** (auto-flip): heuristic for resolving "PRD's expected build branch" from the PRD path may miss edge cases (renamed branches, multi-branch PRs). Mitigation: prefer reading the actual merge commit's branch ref via `git for-each-ref --points-at <merge-sha>`; fall back to heuristic only when ref-walk fails. Document the heuristic + fallback in `--check`'s Notes section.
- **R-3** (shutdown-nag): the 10-tick cap is a magic number. NFR doesn't quite cover "what if a teammate is mid-long-task and 10 minutes is too short"? Mitigation: configurable via an env var `KILN_SHUTDOWN_NAG_MAX_TICKS` (default 10), document in CLAUDE.md plugin-conventions section.
- **R-4** (escalation-audit): the cheapest version dumps events without verdict — but if NO ONE ever hand-tags them, the corpus never accrues, and verdict-tagging stays forever-deferred. Mitigation: V1 ships the inventory; the umbrella item stays in roadmap (un-shipped, in-phase) so the verdict-tagging follow-on remains visible until a real second-pipeline lands it.
- **OQ-1** (auto-flip): should the auto-flip step ALSO update the phase file's `## Items` list (re-running `update-phase-status.sh register <id>` for each shipped item)? The phase file's auto-maintained list currently includes shipped items, so technically no rewrite needed — but verify behavior. Spec MUST clarify whether `update-phase-status.sh register` is called inside the auto-flip loop or not.
- **OQ-2** (shutdown-nag): does the loop-poller live in the team-lead's main session or in a dedicated `shutdown-nag` agent spawned just for windup? Main-session is simpler (matches the 2026-04-25 verified pattern); dedicated agent isolates the work but adds spawn overhead. Recommendation: main-session per the verified pattern; spec MUST document this is the V1 choice.
- **OQ-3** (escalation-audit): pause-event timestamp granularity — file mtime vs. embedded timestamp in event body? `.wheel/history/` files have embedded `started_at` / `ended_at` in JSON; `.kiln/logs/` use timestamped filenames. Spec MUST normalize to ISO-8601 UTC across sources for sort determinism (NFR-003).
- **OQ-4** (cross-cutting): all three themes touch `kiln-build-prd/SKILL.md` (themes A + B in Step 4b + Step 6) and the rubric/skill ecosystem (theme C creates a new skill). Concurrent-staging hazard from retro #187 PI-1 is RELEVANT — this PRD likely ships with 2-3 implementer agents; team-lead MUST cite the new concurrent-staging hazard guidance (just landed in commit `a85bd63`) in implementer prompts.
