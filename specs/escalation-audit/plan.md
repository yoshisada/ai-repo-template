# Implementation Plan: Escalation Audit — Detect Stuck State + Auto-Flip Item Lifecycle

**Branch**: `build/escalation-audit-20260426` | **Date**: 2026-04-26 | **Spec**: [spec.md](./spec.md)
**PRD**: [docs/features/2026-04-26-escalation-audit/PRD.md](../../docs/features/2026-04-26-escalation-audit/PRD.md)

## Summary

Three themes converge on closing state-machine drift loops in the kiln pipeline:

- **Theme A** (FR-001..FR-006) — Step 4b in `kiln-build-prd/SKILL.md` gains an inline auto-flip sub-step that reads the merged PRD's `derived_from:` and atomically flips each item's frontmatter (`state`/`status`/`pr`/`shipped_date`) via the existing `update-item-state.sh` (extended with a `--status` flag) once `gh pr view <N>` confirms `MERGED`. `/kiln:kiln-roadmap --check` gains a merged-PR cross-reference safety net that catches pre-existing drift across the whole roadmap.
- **Theme B** (FR-007..FR-010) — Step 6 of `kiln-build-prd/SKILL.md` gains a `/loop` dynamic-mode shutdown-nag pass with `ScheduleWakeup` ticks (~60s, 10-tick cap, env-var configurable), `TaskStop` force-shutdown fallback, and self-termination on empty team.
- **Theme C** (FR-011..FR-016) — A new `/kiln:kiln-escalation-audit` skill that walks `.wheel/history/`, git log, and `.kiln/logs/` for pause events in the last 30 days and emits a normalized markdown inventory at `.kiln/logs/escalation-audit-<timestamp>.md`. A `kiln-doctor` subcheck `4-escalation-frequency` tripwires when `> 20` wheel pauses land in the last 7 days.

Themes A + B both edit `kiln-build-prd/SKILL.md` → owned by `impl-themes-ab` (sequential phases). Theme C is independent → owned by `impl-theme-c`.

## Technical Context

**Language/Version**: Bash 5.x (script edits + new helper); markdown for skill bodies; YAML frontmatter for items/PRDs.
**Primary Dependencies**: `gh` CLI (PR-state queries), `jq` (JSON parsing), `awk` (frontmatter rewrites), `git` (ref resolution), `python3` (already used by `read_derived_from()` lineage but not added). Claude Code `ScheduleWakeup` + `loop` skill (already shipped) for Theme B. No new runtime deps.
**Storage**: Plain markdown + YAML files under `.kiln/roadmap/items/`, `.kiln/logs/`, `.wheel/history/`.
**Testing**: `plugin-kiln/tests/<fixture>/run.sh` shell harness (existing kiln-test convention). Four new fixtures (FR-006, FR-010, FR-015, SC-002).
**Target Platform**: macOS + Linux (existing kiln dev surfaces).
**Project Type**: Plugin — `plugin-kiln/`. Edits to skill markdown bodies, scripts, and tests; no consumer-side `src/` work.
**Performance Goals**: NFR-001 — Step 4b auto-flip ≤ 5 s for ≤ 10 items. Generous file-I/O budget; one cached `gh pr view` + ≤ 10 atomic awk rewrites is well under 1 s in typical environments.
**Constraints**: Workflow portability (CLAUDE.md §"Plugin workflow portability"); senior-engineer-merge bar; constitution Articles VII (Interface Contracts) and VIII (Incremental Task Completion).
**Scale/Scope**: Roadmap is 81 items today; typical PRD bundles 1–10 derived_from items.

## Constitution Check

*GATE: passes before Phase 0.*

- **I. Spec-First** — spec.md is committed before any implementation; every script function carries an `FR-NNN` comment; every test cites its acceptance scenario.
- **II. 80% Coverage** — Bash scripts are tested via `run.sh` fixtures. The new `--status` branch in `update-item-state.sh` is covered by FR-006 fixture; the new `--check` merged-PR cross-reference is covered by SC-002 fixture; the new escalation-audit skill is covered by FR-015 fixture; doctor subcheck `4-escalation-frequency` is covered by an inline assertion (SC-007).
- **III. PRD as Source of Truth** — every spec FR cites its source FR in the PRD by number. No divergence from the PRD's scope or non-goals.
- **IV. Hooks Enforce Rules** — this PRD's edits land in `plugin-kiln/skills/`, `plugin-kiln/scripts/`, `plugin-kiln/tests/`. The `require-spec.sh` hook gates only on consumer-`src/` edits, so plugin-author edits are unaffected (existing convention; verified by every prior plugin PR).
- **V. E2E Required** — four `run.sh` fixtures exercise the real shell scripts and skill markdown.
- **VI. Small, Focused Changes** — each task touches one bounded area; no file exceeds 500 lines after edits (`kiln-build-prd/SKILL.md` already 1332 lines; this PRD adds ~50 lines for Step 4b auto-flip + ~40 lines for Step 6 shutdown-nag — within budget for a single skill body).
- **VII. Interface Contracts** — `contracts/interfaces.md` defines `update-item-state.sh --status` signature, `--check` merged-PR cross-reference output, the shutdown-nag tick contract, and the escalation-audit report shape (matches FR-013).
- **VIII. Incremental Tasks** — tasks.md is structured into phases; `[X]` after each task; commit after each phase.

No violations. No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/escalation-audit/
├── plan.md                          # This file
├── spec.md                          # Feature specification (committed first)
├── contracts/
│   └── interfaces.md                # Function/script signatures + output shapes
├── tasks.md                         # Task breakdown (/tasks output)
├── agent-notes/                     # Per-agent friction notes
│   └── specifier.md                 # This agent's notes
└── blockers.md                      # SC-006 substrate-blocked carve-out (in-session)
```

### Source Code (plugin edits)

```text
# Theme A — Auto-flip on PR merge
plugin-kiln/skills/kiln-build-prd/SKILL.md          # Step 4b: inline auto-flip sub-step
plugin-kiln/scripts/roadmap/update-item-state.sh    # +--status flag (atomic)
plugin-kiln/skills/kiln-roadmap/SKILL.md            # §C: merged-PR cross-reference

# Theme B — Shutdown-nag loop
plugin-kiln/skills/kiln-build-prd/SKILL.md          # Step 6: /loop shutdown-nag pass

# Theme C — Escalation audit
plugin-kiln/skills/kiln-escalation-audit/SKILL.md   # NEW skill
plugin-kiln/skills/kiln-doctor/SKILL.md             # +subcheck 4-escalation-frequency

# Tests (one fixture per FR-006/FR-010/FR-015/SC-002)
plugin-kiln/tests/build-prd-auto-flip-on-merge/run.sh
plugin-kiln/tests/roadmap-check-merged-pr-drift-detection/run.sh
plugin-kiln/tests/build-prd-shutdown-nag-loop/run.sh
plugin-kiln/tests/escalation-audit-inventory-shape/run.sh
```

**Structure Decision**: Plugin-source edits only. No consumer `src/` or `tests/` (this repo doesn't have those — they only exist in scaffolded consumer projects). All test fixtures use `run.sh` shape per the test-substrate hierarchy.

## Phase 0 — Research

(All decisions are inherited from the PRD, the existing plugin code, and the spec's "Decisions Resolved" section.)

| ID | Question | Decision | Source |
|----|----------|----------|--------|
| R-1 | Where does Step 4b auto-flip live in `kiln-build-prd/SKILL.md`? | Append a new `## Step 4b.5: Auto-flip roadmap items on merge (FR-001..FR-004)` block AFTER existing Step 4b finishes its issue/feedback archival commit and BEFORE Step 5 (Retrospective). The new block runs only after the audit-pr agent has created the PR and the team-lead's flow has detected merge. | spec FR-001, PRD FR-001, OQ-1 resolution |
| R-2 | Add `--status` to `update-item-state.sh` or create a sibling `update-item-status.sh`? | Extend `update-item-state.sh` with `--status` (PRD FR-002 explicitly allows either; extension keeps the API surface narrow and the atomic write self-contained). | PRD FR-002 |
| R-3 | How does Step 6 enter `/loop` dynamic mode? | Team-lead invokes the `loop` skill with self-paced `ScheduleWakeup({delaySeconds: 60, prompt: "<<autonomous-loop-dynamic>>", reason: "shutdown-nag tick"})` and a tick-counter persisted via the in-session conversation (no on-disk state required for V1; tick counter survives within the team-lead's main session). | spec US3, R-3 |
| R-4 | What's the canonical sort key for escalation-audit Events? | `(timestamp ASC, source ASC, surface ASC)` — declared in spec NFR-003. ISO-8601 UTC normalization happens before sort. | spec NFR-003, OQ-3 |
| R-5 | Where does the new `kiln-escalation-audit` skill register? | New SKILL.md at `plugin-kiln/skills/kiln-escalation-audit/SKILL.md`. Auto-discovered by the kiln plugin (no manual manifest entry required for skills under `plugin-kiln/skills/`). | existing kiln plugin convention |
| R-6 | What grep pattern for hook-block events in `.kiln/logs/*.md`? | Permissive: `^(BLOCKED|hook-block|require-spec.sh blocked)` — matches the existing block log emitters; non-matching lines are ignored (no false positives by default). | spec edge case + FR-012 |

No outstanding NEEDS CLARIFICATION items. Phase 0 complete.

## Phase 1 — Design & Contracts

### Data shapes

- **Roadmap-item frontmatter (touched fields only)**:
  ```yaml
  state: shipped         # was: distilled | specced
  status: shipped        # was: open | in-progress
  pr: <integer>          # NEW (only if absent)
  shipped_date: <YYYY-MM-DD>  # NEW (only if absent)
  ```
- **Step 4b auto-flip diagnostic line** (one-line, deterministic):
  `step4b-auto-flip: pr-state=<MERGED|OPEN|CLOSED|unknown> auto-flip=<success|skipped> items=<N> patched=<K> already_shipped=<S> reason=<empty|no-derived-from|gh-unavailable|pr-not-merged>`
- **`--check` merged-PR drift row** (one per flagged item):
  `[drift] <item-id> state=<distilled|specced> prd=<path> branch=<resolved-branch> pr=#<N> resolution=<ref-walk|heuristic>\n  fix: bash plugin-kiln/scripts/roadmap/update-item-state.sh <path> shipped --status shipped`
- **Shutdown-nag tick diagnostic** — one line per re-poke action:
  `tick=<N> teammate=<name> action=re-poke|already-terminated|force-shutdown reason=<empty|10-tick-timeout>`
- **Pause event row** (in `## Events`):
  `| <timestamp-iso> | <source> | <event_type> | <context-truncated-≤120ch> | <surface> |`
- **Escalation-audit report file** — section structure already declared in FR-013; no separate JSON sidecar in V1.

See `contracts/interfaces.md` for full signatures.

### Constitution re-check (post-design)

Still passing — no new violations from the data shapes above.

## Phase 2 — Tasks (handed off to `/tasks`)

`tasks.md` is generated by the `/tasks` step from this plan + spec. Tasks are organized by user story to allow independent verification. Implementer assignment is fixed:

- **`impl-themes-ab`** owns: Phase 1 (shared/setup), Phase 3 (US1 — auto-flip), Phase 4 (US2 — `--check` cross-reference), Phase 5 (US3 — shutdown-nag). Sequential within `kiln-build-prd/SKILL.md` to avoid concurrent-staging hazard.
- **`impl-theme-c`** owns: Phase 6 (US4 — escalation-audit skill), Phase 7 (US5 — doctor subcheck). Independent of Themes A + B.

## Complexity Tracking

(No constitution violations to justify.)

## Risks & Mitigations (carry-forward)

- **Concurrent-staging hazard** — only `impl-themes-ab` writes to `kiln-build-prd/SKILL.md`. Sequential phases inside that owner's task list (Phase 3 → Phase 4 → Phase 5).
- **`gh` rate limiting (R-1)** — Step 4b caches one `gh pr view` per PR; not per item.
- **Heuristic build-branch resolution (R-2)** — prefer ref-walk; fall back to heuristic; document choice in `--check` Notes.
- **10-tick cap (R-3)** — env-var configurable.
- **Inventory without verdict (R-4)** — V1 ships inventory; umbrella roadmap item stays open + in-phase.
- **Substrate gap (B-1)** — full `/loop` integration test deferred; FR-010 verifies via direct text assertions on SKILL.md only.
- **SC-006 in-session block (B-PUBLISH-CACHE-LAG carve-out 2b)** — recorded in `blockers.md` as a post-merge manual verification step; does NOT gate this PR.
