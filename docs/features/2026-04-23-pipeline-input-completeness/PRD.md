# Feature PRD: Pipeline Input Completeness

**Date**: 2026-04-23
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md) (placeholder; product context inherited from `CLAUDE.md`)

## Background

Two pipeline-critical skills shipped this cycle with the same shape of bug: each skips an input it already has access to and should read. `/kiln:kiln-build-prd` Step 4b ("Issue Lifecycle Completion") scans `.kiln/issues/` but not `.kiln/feedback/`, so every distill-fed pipeline that bundles feedback items leaves them stuck in `status: prd-created` after the PRD merges. `shelf:shelf-write-issue-note` re-discovers the vault path on every invocation instead of reading the `base_path` + `slug` values that `.shelf-config` already provides. Both are small logic errors with compounding cost: the Step 4b miss drove the entire kiln-structural-hygiene feature (shipped as PR #144) as an external safety net, and the write-issue-note discovery cost recurs on every `/kiln:kiln-report-issue` run.

Neither bug requires a new feature or architecture change. Both are roughly 10-line fixes once the root cause is confirmed. This PRD bundles them because they share a failure pattern worth naming: **pipeline skills that skip available input signal**. Treating them as one unit of work lets the fix land alongside a small invariant — "skills read the full set of inputs their contract says they operate on, and read the config files their siblings already write to."

### Source Issues

| # | Source Item | Source | Type | GitHub Issue | Severity / Area |
|---|-------------|--------|------|--------------|------------------|
| 1 | [/kiln:kiln-build-prd Step 4b still broken — doesn't scan `.kiln/feedback/`](../../../.kiln/issues/2026-04-23-build-prd-step4b-still-broken-post-pr144.md) | `.kiln/issues/` | issue | — | high / workflow |
| 2 | [shelf-write-issue-note guesses the Obsidian path instead of reading `.shelf-config`](../../../.kiln/issues/2026-04-23-write-issue-note-ignores-shelf-config.md) | `.kiln/issues/` | issue | — | medium / shelf |

## Problem Statement

**Bug 1 — Step 4b input gap.** `/kiln:kiln-build-prd` Step 4b's job is to flip `status: prd-created` → `status: completed` + archive the item for every backlog entry whose `prd:` matches the PRD being built. The `/kiln:kiln-distill` skill updates both `.kiln/issues/*.md` AND `.kiln/feedback/*.md` to `prd-created` when it bundles items into a PRD. Step 4b's scan currently reaches only `.kiln/issues/`. Every pipeline that includes feedback-side items leaves them stuck afterward. Evidence: both pipelines merged today (PR #141 kiln-self-maintenance and PR #144 kiln-structural-hygiene) leaked 4 items total; 3 of 4 were feedback-side; the new hygiene audit immediately caught them. Step 4b is a 100% reproducing silent failure for the feedback dimension.

**Bug 2 — write-issue-note path discovery.** The `shelf:shelf-write-issue-note` sub-workflow targets `<base_path>/<slug>/issues/<issue-id>.md` in the Obsidian vault. `.shelf-config` at the repo root already carries `base_path`, `slug`, and the full `dashboard_path` — everything needed to compose the target path deterministically. Instead, the current implementation walks the vault to find the project folder, which burns vault-listing MCP calls on every `/kiln:kiln-report-issue` invocation and can drift if the guess diverges from config. The cost is small per invocation but compounding across the plugin's "lean foreground path" goal: the whole point of PR #129's report-issue-speedup was to minimize what the foreground does, and an avoidable discovery call undercuts that.

Both bugs are mechanical: add a second scan path in one case, read a config file before guessing in the other. Neither has a design question — the fix shape is obvious once the gap is named. The work is framing each fix with a smoke test and adding diagnostic output to prevent silent recurrence.

## Goals

- **Close the Step 4b input gap**: Step 4b scans BOTH `.kiln/issues/` AND `.kiln/feedback/` for `prd-created` items whose `prd:` matches the current build's PRD path, flips both to `completed`, and moves both into the respective `completed/` subdirectory.
- **Close the shelf-config gap**: `shelf:shelf-write-issue-note` reads `.shelf-config` to compose the target path. Vault-listing discovery is the fallback, not the default.
- **Prevent silent-regression recurrence**: both skills emit diagnostic output (counts matched, paths inspected) so future breaks are visible, not black-boxed. The Step 4b diagnostic is the missing piece that caused this whole chain of work — if Step 4b had reported "scanned X items, matched Y, flipped Z" from day one, the feedback-side miss would have been obvious the first time it happened.
- **Add smoke coverage**: both skills get a minimal fixture + smoke recipe so a future regression fails observably rather than silently.

## Non-Goals

- **No refactor of Step 4b's matching logic beyond the path-scan fix.** If the `prd:` string-comparison itself is also broken in ways this PRD doesn't catch, that's a separate `/kiln:kiln-fix` cycle.
- **No change to the `.shelf-config` schema.** The fields already there (`base_path`, `slug`, `dashboard_path`) are sufficient.
- **No change to the hygiene audit's `merged-prd-not-archived` rule.** That rule is the safety net. This PRD fixes the upstream bug; the safety net stays.
- **No broader "skills should read all their config" audit or policy engine.** Just the two specific fixes.
- **No new executable test harness.** Fixtures + shell-runnable assertions (the same pattern `kiln-claude-audit` and `kiln-hygiene` use). Executable test harnesses remain open follow-on work for a separate PRD.

## Requirements

### Functional Requirements

**Step 4b input completeness (Bug 1)**:

- **FR-001 (from: `.kiln/issues/2026-04-23-build-prd-step4b-still-broken-post-pr144.md`)** `/kiln:kiln-build-prd` Step 4b MUST scan BOTH `.kiln/issues/*.md` AND `.kiln/feedback/*.md` (top-level only, excluding `completed/` subdirectories) for items whose `status: prd-created` AND `prd:` frontmatter field matches the `$PRD_PATH` used for the current build.
- **FR-002 (from: same)** For every matched item, Step 4b MUST (a) replace the `status:` line with `status: completed`, (b) add a `completed_date: YYYY-MM-DD` line, (c) add a `pr: #<PR-number>` line referencing the PR opened by the audit-pr agent, (d) move the file from `.kiln/{issues,feedback}/<file>.md` to `.kiln/{issues,feedback}/completed/<file>.md`, preserving the originating directory.
- **FR-003 (from: same)** Step 4b MUST emit a single diagnostic line to its step output recording at minimum: `scanned_issues=N` (count of `.kiln/issues/*.md` inspected), `scanned_feedback=M` (count of `.kiln/feedback/*.md` inspected), `matched=K` (count of items whose `prd:` matched `$PRD_PATH`), `archived=K` (should equal matched on a successful run), and `prd_path=<$PRD_PATH>` (the path value used for matching). On a zero-match run, this line surfaces the mismatch for inspection rather than silently succeeding.
- **FR-004 (from: same)** Step 4b MUST normalize both the `prd:` field value AND the `$PRD_PATH` variable before comparison: strip trailing slash, strip leading `./`, reject absolute paths (Step 4b always runs from repo root so relative is canonical). If either side fails normalization (e.g., empty string, non-existent file), skip that item and include it in the diagnostic line's `skipped=<count>` column, not `matched`.
- **FR-005 (from: same)** If Step 4b matches zero items, the pipeline MUST still commit an empty "lifecycle noop" marker to a log file (`.kiln/logs/build-prd-step4b-<YYYY-MM-DD>.md`) recording the diagnostic line. This is the observability artifact — it turns a silent path into a trail.

**shelf-write-issue-note config awareness (Bug 2)**:

- **FR-006 (from: `.kiln/issues/2026-04-23-write-issue-note-ignores-shelf-config.md`)** `shelf:shelf-write-issue-note` MUST read `.shelf-config` at the repo root before invoking any vault-listing MCP call. When both `base_path` and `slug` are present, it MUST compose the target path as `${base_path}/${slug}/issues/<issue-id>.md` and write directly. No discovery calls needed.
- **FR-007 (from: same)** When `.shelf-config` is missing OR either `base_path` or `slug` is missing/empty, the skill MUST fall back to the current discovery behavior (vault listing) AND emit a one-line warning in its result JSON: `"path_source": "discovery (shelf-config incomplete)"`. The success path's result JSON records `"path_source": ".shelf-config (base_path + slug)"`.
- **FR-008 (from: same)** The skill MUST apply the same logic to sibling subfolder writes if any shelf sub-workflow uses this pattern (e.g., `fixes/`, `progress/`, `decisions/`). Plan phase confirms which shelf skills are in scope — FR-008 is conditional on the plan-phase sweep finding them. If only `write-issue-note` uses this pattern, FR-008 is satisfied trivially.

### Non-Functional Requirements

- **NFR-001** No new runtime dependencies. Bash + existing shelf scripts + existing MCP tools only.
- **NFR-002** Backwards compat: direct invocations of `shelf:shelf-write-issue-note` that target a project without a `.shelf-config` continue working unchanged via the discovery fallback (FR-007).
- **NFR-003** Step 4b's diagnostic log file (FR-005) stays under `.kiln/logs/` retention (kiln-manifest's `keep_last: 10` rule). Same lifecycle as `next-<timestamp>.md` and `claude-md-audit-<timestamp>.md` logs.
- **NFR-004** Idempotence: re-running Step 4b on a pipeline that already archived its matches produces zero new archives and a diagnostic line with `matched=0`. Same discipline the hygiene audit follows.

## User Stories

- **US-001** As a maintainer running `/kiln:kiln-build-prd` on a PRD that was distilled from both feedback and issues, I want Step 4b to archive all matching items — feedback and issues alike — so my backlog surface is accurate the moment the PR merges without needing a follow-up hygiene audit + manual archive. (FR-001, FR-002)
- **US-002** As a maintainer debugging why Step 4b seemed to "do nothing," I want a diagnostic line recording exactly what it scanned, what it matched, and what it archived, so silent misses are visible the first time instead of drifting for weeks. (FR-003, FR-005)
- **US-003** As a user typing `/kiln:kiln-report-issue "…"`, I want the Obsidian-note write to take the deterministic path (`.shelf-config` read) not the discovery path, so every invocation pays the minimum foreground cost consistent with the lean-path goal from PR #129. (FR-006)
- **US-004** As a consumer working on a project without `.shelf-config` (legacy scaffolds), I want the write step to still work via vault discovery, with a clear one-line warning that tells me to populate `.shelf-config` for the fast path. (FR-007)

## Success Criteria

- **SC-001 Step 4b scans both dirs.** Fixture with 1 `.kiln/issues/` item + 1 `.kiln/feedback/` item, both with matching `prd:`, run Step 4b manually: both flip to `completed` and both move to their respective `completed/` subdirectory. Verified by: fixture setup script + run + post-run `find` on `.kiln/{issues,feedback}/completed/`.
- **SC-002 Step 4b diagnostic emits on every run.** Run Step 4b against both matched and zero-match scenarios — the diagnostic line appears in the step output in both cases, with `scanned_issues`, `scanned_feedback`, `matched`, `archived`, `skipped`, `prd_path` fields present and non-empty. Verified by: grep the step output log for the field names after each scenario.
- **SC-003 Step 4b normalizes paths.** Fixture with one item whose `prd:` has a trailing slash and another with a leading `./` — both match the canonical `$PRD_PATH` and get archived. Verified by: fixture + scripted run.
- **SC-004 shelf-config path used when present.** `/kiln:kiln-report-issue "test"` against this repo (which has `.shelf-config`) produces a `shelf-write-issue-note-result.json` with `"path_source": ".shelf-config (base_path + slug)"` AND exactly zero vault `list_files` calls in the Obsidian MCP call history for that invocation. Verified by: post-run JSON inspection + manual/proxy MCP-call count.
- **SC-005 Discovery fallback still works.** Temporarily rename `.shelf-config` → `.shelf-config.bak`, re-run `/kiln:kiln-report-issue "test"`, confirm the file still gets written to the correct path AND the result JSON records `"path_source": "discovery (shelf-config incomplete)"`. Verified by: manual run + JSON inspection. Restore afterward.
- **SC-006 Idempotence.** Run Step 4b twice on a pipeline that already archived — second run reports `matched=0` and creates no new files. Verified by: git status after each run.
- **SC-007 Zero downstream regression.** The existing hygiene audit's `merged-prd-not-archived` rule still catches drift when Step 4b is bypassed (e.g., running `/kiln:kiln-build-prd` with Step 4b temporarily stubbed out via a feature flag). This PRD's fixes MUST NOT weaken the safety net. Verified by: pre-merge gate — hygiene audit fires correctly when Step 4b is disabled.
- **SC-008 Smoke fixtures exist.** `specs/pipeline-input-completeness/SMOKE.md` documents the 2 fixtures (Step 4b two-source fixture + write-issue-note shelf-config-present/absent fixture) and the exact commands to run each. Executable harness out of scope; documentation + runnability matters.

## Tech Stack

Inherited from the parent product — no additions:

- Markdown (skill definitions)
- Bash 5.x (Step 4b loop + shell-level `.shelf-config` parse)
- Obsidian MCP (`mcp__claude_ai_obsidian-projects__create_file`) — already assumed
- `jq`, `grep`, standard POSIX utilities

## Risks & Open Questions

- **Hidden second bug in Step 4b's path comparison.** Even after fixing the scan path (FR-001) and adding normalization (FR-004), there may be a separate `prd:` string format issue. FR-003's diagnostic output is the defensive answer — if matching still returns zero after the fix, the diagnostic line shows exactly what didn't match, and a follow-on `/kiln:kiln-fix` can target the actual mismatch. Accept this risk; don't try to fix speculatively.
- **FR-008 scope inflation.** The "sweep all shelf skills for discovery-vs-config pattern" clause could expand to writers beyond `write-issue-note` (e.g., `shelf-update`, `shelf-release`). Plan phase should enumerate and cap — recommend explicit scope to 1–3 skills max, others filed as follow-on issues if found.
- **Backwards-compat for old-style `.shelf-config`.** Some older `.shelf-config` files in consumer repos may have trailing whitespace, `CRLF` line endings, or quoted values. The parser should be defensive: strip surrounding whitespace, strip quotes, warn on unparseable lines per the existing `shelf-counter.sh` precedent.
- **Diagnostic log retention.** FR-005 writes to `.kiln/logs/`. With `keep_last: 10` retention, a week of pipelines can bump older build-prd diagnostics out. Plan phase should decide: separate retention for build-prd-step4b logs (higher keep-count for debugging leaks), or accept the default. Recommend default — if a leak recurs, the hygiene audit still catches it downstream.
- **Step 4b runs inside /kiln:kiln-build-prd which itself is a team-orchestrated skill.** The fix needs to be applied at the right layer (the team-lead's Step 4b execution, not an agent's implementation). Spec phase should pin: does Step 4b run in the team lead's context (main chat) or a dedicated agent? PRD currently assumes team lead; plan phase confirms.
- **No executable smoke-harness.** Matches kiln-claude-audit + kiln-hygiene precedent — fixtures documented, assertions shell-runnable, no test harness. If this is the third PRD in a row punting on executable tests, worth surfacing to the maintainer as "enough signal accumulated; time to prioritize."
