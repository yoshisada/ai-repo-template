# Feature Spec: Pipeline Input Completeness

**Feature slug**: `pipeline-input-completeness`
**Branch**: `build/pipeline-input-completeness-20260423`
**Parent PRD**: [docs/features/2026-04-23-pipeline-input-completeness/PRD.md](../../docs/features/2026-04-23-pipeline-input-completeness/PRD.md)
**Status**: Draft
**Date**: 2026-04-23

## Summary

Two pipeline-critical skills shipped with the same shape of bug: each skips an input it already has access to.

1. `/kiln:kiln-build-prd` Step 4b ("Issue Lifecycle Completion") scans `.kiln/issues/` only — it never reaches `.kiln/feedback/`. Every distill-fed pipeline that bundles feedback items leaves them stuck at `status: prd-created`. 100% repro: today's two merged pipelines (PR #141, PR #144) leaked 4 items total; 3 of 4 were feedback-side.
2. `shelf:shelf-write-issue-note` (the wheel sub-workflow that writes the Obsidian note) reads `.shelf-config` in step `read-shelf-config` but the contract is loose: when `slug`/`base_path` parsing fails, the agent silently falls back to ad-hoc derivation (and may re-issue listing calls). The fast path is also un-instrumented: callers can't tell whether `.shelf-config` was actually used or a fallback fired.

This spec covers the smallest fixes that close both gaps and make any future regression visible the first time it happens, not the third.

## Inherited Context

From `CLAUDE.md`:

- This is the **plugin source repo** for `@yoshisada/kiln`. `src/` and `tests/` do not exist here — they are scaffolded into consumer projects.
- Hooks (4-gate enforcement) physically block edits to `src/` without spec/plan/tasks/[X]. This spec edits **plugin sources** (`plugin-kiln/skills/`, `plugin-shelf/workflows/`, `plugin-shelf/scripts/`), not `src/`. The hook gates still apply via the spec-first contract; the plugin-source files just live outside `src/`.
- "Skills" are user-invocable markdown command bodies (Step 4b lives in `plugin-kiln/skills/kiln-build-prd/SKILL.md`); "wheel workflows" are JSON pipelines (`shelf-write-issue-note` is a wheel workflow under `plugin-shelf/workflows/`).
- The plugin workflow portability rule (CLAUDE.md §"Plugin workflow portability") applies: any new shell scripts referenced from workflow command steps MUST resolve via `${WORKFLOW_PLUGIN_DIR}` — never via repo-relative `plugin-shelf/scripts/...`.
- Diagnostic output goes to `.kiln/logs/` with `keep_last: 10` retention (kiln-manifest rule).

From `.specify/memory/constitution.md`:

- Article I (Spec-First) — this spec is the gate before edits.
- Article VI (Small, Focused Changes) — both fixes are ~10 lines apiece. No premature abstraction.
- Article VII (Interface Contracts) — `contracts/interfaces.md` carries the exact bash pseudocode, the diagnostic-line literal template, the `.shelf-config` parse routine, and the `shelf-write-issue-note-result.json` schema.
- Article VIII (Incremental Task Completion) — tasks ship in 6 phases; commit per phase.

From the PRD's "Risks & Open Questions":

- Step 4b runs in the **team lead's main-chat context**, not in a dedicated agent. PRD §risks calls this out and asks plan to confirm — confirmed in plan.md Decision 1.
- FR-008 scope is capped at **0 additional shelf skills** in this PRD — a sweep of `plugin-shelf/skills/*` and `plugin-shelf/workflows/*` shows the other writers (`shelf-update`, `shelf-release`, `shelf-create`, `shelf-status`, `shelf-feedback`, `shelf-repair`) already read `.shelf-config` correctly. See plan.md Decision 2.
- Diagnostic-log retention uses the default `keep_last: 10`. PRD §risks recommends default; this spec accepts. See plan.md Decision 3.
- No executable test harness. Fixtures + shell-runnable assertions, matching the `kiln-claude-audit` and `kiln-hygiene` precedent.

## Current State (verified by reading the source)

**Step 4b** — `plugin-kiln/skills/kiln-build-prd/SKILL.md`, lines 590–631 (heading: `## Step 4b: Issue Lifecycle Completion (FR-007, FR-008)`). Current pseudocode iterates `.kiln/issues/*.md` only; `mv` target hardcodes `.kiln/issues/completed/`. No `.kiln/feedback/` scan. No diagnostic line. No log file. The matching uses raw `[ "$prd_field" = "$PRD_PATH" ]` with no normalization.

**`shelf-write-issue-note`** — `plugin-shelf/workflows/shelf-write-issue-note.json`, 4 steps:

1. `read-shelf-config` (command) — `cat .shelf-config` if present; otherwise emits `slug=<git-remote-basename>` + `base_path=projects`.
2. `parse-create-issue-output` (command) — calls `${WORKFLOW_PLUGIN_DIR}/scripts/parse-create-issue-output.sh`.
3. `obsidian-write` (agent) — instructed to "parse `slug = <value>` and `base_path = <value>` (space-padded `=`)", with fallback to git-remote derivation.
4. `finalize-result` (command) — coerces malformed JSON to `action: "failed"`.

The bug surface is in step 1 (no defensive parse — uses raw `cat`, vulnerable to quoted values, CRLF, comments) and step 3 (the agent has no `path_source` field to record which path it took, so callers can't observe a regression).

**`.shelf-config`** — current shape (this repo):

```
# Shelf configuration — maps this repo to its Obsidian project
base_path = @second-brain/projects
slug = ai-repo-template
dashboard_path = @second-brain/projects/ai-repo-template/ai-repo-template.md
shelf_full_sync_counter = 2
shelf_full_sync_threshold = 10
```

**`shelf-counter.sh`** — `plugin-shelf/scripts/shelf-counter.sh`, function `_read_key()` (lines 41–51) is the **defensive parse precedent**: matches `^${key}[[:space:]]*=`, takes `tail -1`, strips `^[^=]+=[[:space:]]*`, then `tr -d ' \t\r'`. Spec §contracts adopts the same pattern verbatim.

## User Stories

### US-001 — Pipeline archives feedback items, not just issues (FR-001, FR-002)

**As** a maintainer running `/kiln:kiln-build-prd` on a PRD distilled from both feedback and issues,
**I want** Step 4b to flip & archive every matching item — feedback-side and issue-side alike —
**so that** my backlog surface is accurate the moment the PR merges, with no follow-up hygiene-audit + manual archive.

- **Given** `.kiln/issues/foo.md` has `status: prd-created` + `prd: docs/features/2026-04-23-x/PRD.md`,
  **And** `.kiln/feedback/bar.md` has `status: prd-created` + `prd: docs/features/2026-04-23-x/PRD.md`,
  **And** the build is for that PRD,
  **When** Step 4b runs after the PR is opened,
  **Then** `foo.md` moves to `.kiln/issues/completed/foo.md` with `status: completed`, `completed_date: <today>`, `pr: #N`,
  **And** `bar.md` moves to `.kiln/feedback/completed/bar.md` with the same updates.

### US-002 — Diagnostic line every run (FR-003, FR-005)

**As** a maintainer debugging "Step 4b looks like it did nothing",
**I want** a single diagnostic line written to the step output every run (matched OR zero-match),
**so that** the next silent miss is visible the first time, not after weeks of accumulated drift.

- **Given** any pipeline run reaches Step 4b,
  **When** the step finishes (matched or not),
  **Then** the step output contains a single line of the form
  `step4b: scanned_issues=<N> scanned_feedback=<M> matched=<K> archived=<K> skipped=<S> prd_path=<PRD_PATH>`,
  **And** the same line is appended to `.kiln/logs/build-prd-step4b-<YYYY-MM-DD>.md`.

### US-003 — Lean foreground for `/kiln:kiln-report-issue` (FR-006)

**As** a user typing `/kiln:kiln-report-issue "..."` against a project that has a populated `.shelf-config`,
**I want** the Obsidian write to compose its target path deterministically from `.shelf-config`,
**so that** every invocation pays the minimum foreground cost (the lean-path goal from PR #129).

- **Given** `.shelf-config` exists at the repo root with non-empty `base_path` AND `slug`,
  **When** the `shelf-write-issue-note` sub-workflow runs,
  **Then** the result JSON records `"path_source": ".shelf-config (base_path + slug)"`,
  **And** zero `mcp__claude_ai_obsidian-projects__list_files` calls are issued during the run.

### US-004 — Discovery fallback still works (FR-007)

**As** a consumer working on a project without `.shelf-config` (legacy scaffolds, or the file deleted/renamed),
**I want** the write step to still succeed via the prior derivation (git-remote basename + `projects` default),
**so that** legacy projects keep working AND the fallback is observable in the result JSON.

- **Given** `.shelf-config` is missing OR `base_path`/`slug` is empty/unparseable,
  **When** `shelf-write-issue-note` runs,
  **Then** the step still writes the note to a deterministic path,
  **And** the result JSON records `"path_source": "discovery (shelf-config incomplete)"`,
  **And** the result JSON's `errors` array stays empty (a missing config is not an error).

## Requirements

### Functional Requirements

#### Step 4b input completeness (Bug 1)

- **FR-001** Step 4b MUST scan BOTH `.kiln/issues/*.md` AND `.kiln/feedback/*.md` (top-level only; the `*/completed/` subdirectories are excluded by the `*.md` glob — the loop matches `for f in .kiln/issues/*.md .kiln/feedback/*.md` not `**/*.md`). For every file whose `status:` line normalizes to `prd-created` AND whose normalized `prd:` field equals the normalized `$PRD_PATH`, the file is a "match". (PRD FR-001)

- **FR-002** For each matched file, Step 4b MUST:
  (a) replace the existing `status:` line in-place with `status: completed`,
  (b) insert `completed_date: YYYY-MM-DD` (today's UTC date) immediately after the `status:` line,
  (c) insert `pr: #<PR-number>` (the number returned by audit-pr) immediately after `completed_date`,
  (d) `mkdir -p` the originating directory's `completed/` subdir,
  (e) `mv` the file into `<originating-dir>/completed/<basename>` — **preserving the originating directory** (`.kiln/issues/foo.md` → `.kiln/issues/completed/foo.md`; `.kiln/feedback/bar.md` → `.kiln/feedback/completed/bar.md`).
  If `mv` fails for any single file, log a per-file warning to the diagnostic, **do not abort the loop**, and count that file as `skipped`. (PRD FR-002)

- **FR-003** Step 4b MUST emit a single diagnostic line to its step output, exactly once per run, with this literal format:

  ```
  step4b: scanned_issues=<N> scanned_feedback=<M> matched=<K> archived=<K> skipped=<S> prd_path=<PRD_PATH>
  ```

  All six fields MUST be present and non-empty (use `0` for empty counts; use the literal `<PRD_PATH>` value, never empty). On a zero-match run, this line is the only signal of what happened. (PRD FR-003)

- **FR-004** Both sides of the comparison MUST be normalized BEFORE comparing:
  - Strip leading `./`
  - Strip trailing `/`
  - Strip surrounding ASCII whitespace (`\t`, ` `, `\r`)
  - Reject absolute paths (paths starting with `/`) — Step 4b runs from repo root, relative is canonical.
  If either side fails to normalize to a non-empty relative path, OR the resulting `prd:` value names a file that does not exist on disk, the file is **skipped** (counted in `skipped=<S>`, NOT in `matched=<K>`). (PRD FR-004)

- **FR-005** On every run — matched OR zero-match — Step 4b MUST append the diagnostic line to `.kiln/logs/build-prd-step4b-<YYYY-MM-DD>.md` (one date file per UTC day; `>>` append, not overwrite — if the file already exists the run is appended as a new line). The file MUST be created if it does not exist. The file MUST be `git add`-ed and committed in the same commit as the archived files (or, on a zero-match run, in a single commit named `chore: step4b lifecycle noop — <PRD_PATH>`). Retention follows the existing `.kiln/logs/` rule (`keep_last: 10`); no separate retention. (PRD FR-005)

#### `shelf-write-issue-note` config awareness (Bug 2)

- **FR-006** The `obsidian-write` agent step in `plugin-shelf/workflows/shelf-write-issue-note.json` MUST source `slug` and `base_path` from `.shelf-config` using the defensive parse routine specified in `contracts/interfaces.md` §3 (matches `shelf-counter.sh`'s `_read_key()` pattern). When BOTH `slug` and `base_path` are present and non-empty after parsing, the agent MUST:
  - Compose the target path as `${base_path}/${slug}/issues/<basename>`,
  - Skip any `mcp__claude_ai_obsidian-projects__list_files` call,
  - Set `result.path_source` to the literal string `".shelf-config (base_path + slug)"`. (PRD FR-006)

- **FR-007** When `.shelf-config` is missing OR EITHER `slug` OR `base_path` is empty/unparseable, the agent MUST fall back to the existing derivation (`slug = $(basename of git remote, .git stripped)`, `base_path = projects`), AND set `result.path_source` to the literal string `"discovery (shelf-config incomplete)"`. The fallback path MUST NOT add `errors` entries — a missing config is a normal degraded mode, not a failure. (PRD FR-007)

- **FR-008** Sweep result (per plan.md Decision 2): NO additional shelf skills require this fix. The other shelf writers (`shelf-update`, `shelf-release`, `shelf-create`, `shelf-status`, `shelf-feedback`, `shelf-repair`) already read `.shelf-config` and compose paths from `base_path + slug`. FR-008 is satisfied trivially by `shelf-write-issue-note` alone. (PRD FR-008)

### Non-Functional Requirements

- **NFR-001** No new runtime dependencies. Bash 5.x + existing wheel/MCP tools only. (PRD NFR-001)
- **NFR-002** Backwards compat: direct invocations of `shelf:shelf-write-issue-note` against a project without `.shelf-config` continue working unchanged via the FR-007 fallback. (PRD NFR-002)
- **NFR-003** Step 4b's diagnostic log file (FR-005) lives under `.kiln/logs/` and follows that directory's existing `keep_last: 10` rule (no separate retention). (PRD NFR-003)
- **NFR-004** Idempotence: re-running Step 4b after a successful archive produces zero new archives, `matched=0`, and a single fresh diagnostic-line entry in today's log file. The pipeline does not error. (PRD NFR-004)
- **NFR-005** (derived) The Step 4b implementation lives entirely in the team lead's main-chat context (the bash block under `## Step 4b` in `kiln-build-prd/SKILL.md`). It is NOT a dedicated agent. See plan.md Decision 1.
- **NFR-006** (derived) All shell scripts referenced from a wheel command step MUST be invoked via `${WORKFLOW_PLUGIN_DIR}/scripts/<name>.sh`. No repo-relative `plugin-shelf/scripts/...` paths in workflow JSON (CLAUDE.md plugin-portability invariant).

## Success Criteria

- **SC-001 — Step 4b scans both dirs.** Fixture: 1 `.kiln/issues/foo.md` + 1 `.kiln/feedback/bar.md`, both with matching `prd:`. After Step 4b: both files have moved into their respective `completed/` subdir; both have `status: completed`, `completed_date`, `pr:` lines. Verified by `find .kiln/issues/completed/ .kiln/feedback/completed/ -name 'foo.md' -o -name 'bar.md' | wc -l` returning `2`. (PRD SC-001)

- **SC-002 — Diagnostic emits on every run.** Two scenarios — matched + zero-match — both produce a step-output line containing `scanned_issues=`, `scanned_feedback=`, `matched=`, `archived=`, `skipped=`, `prd_path=`. Verified by `grep -E '^step4b: scanned_issues=[0-9]+ scanned_feedback=[0-9]+ matched=[0-9]+ archived=[0-9]+ skipped=[0-9]+ prd_path=' <step-output>`. (PRD SC-002)

- **SC-003 — Path normalization.** Fixture: one item with `prd: ./docs/features/2026-04-23-x/PRD.md` (leading `./`), another with `prd: docs/features/2026-04-23-x/PRD.md/` (trailing `/`); `$PRD_PATH=docs/features/2026-04-23-x/PRD.md`. Both match and archive. Verified by post-run `find` returning both files in `completed/`. (PRD SC-003)

- **SC-004 — `.shelf-config` path used when present.** Run `/kiln:kiln-report-issue "smoke fixture 1"` against this repo. Inspect `.wheel/outputs/shelf-write-issue-note-result.json`: `path_source` equals `".shelf-config (base_path + slug)"`. Cross-check the agent transcript: zero `mcp__claude_ai_obsidian-projects__list_files` calls. (PRD SC-004)

- **SC-005 — Discovery fallback still works.** `mv .shelf-config .shelf-config.bak`, run `/kiln:kiln-report-issue "smoke fixture 2"`, confirm the note is written, `path_source` equals `"discovery (shelf-config incomplete)"`, `errors == []`. `mv .shelf-config.bak .shelf-config` afterward. (PRD SC-005)

- **SC-006 — Idempotence.** Run Step 4b twice on a pipeline where the first run already archived. Second run reports `matched=0`, creates no new files, produces a fresh diagnostic line in today's log. Verified by `git status --short` returning only the log-file modification (and no new commits required if the diff is whitespace-only — but the log line MUST be present). (PRD SC-006)

- **SC-007 — Zero downstream regression.** Toggle Step 4b off (comment out the scan loop), re-run a fixture pipeline; the existing `/kiln:kiln-hygiene` audit's `merged-prd-not-archived` rule still catches the unarchived items. Verified by running `/kiln:kiln-hygiene` and seeing the same items flagged in the preview at `.kiln/logs/structural-hygiene-<timestamp>.md`. (PRD SC-007)

- **SC-008 — Smoke fixtures exist.** `specs/pipeline-input-completeness/SMOKE.md` documents the 2 fixtures (Step 4b two-source fixture; write-issue-note shelf-config-present/absent fixture) with copy-pasteable bash commands and expected post-run shell assertions. (PRD SC-008)

## Out of Scope (defers to follow-on PRDs)

- Refactor of the `prd:` matching logic beyond the path-scan + normalization fix.
- Schema change to `.shelf-config`.
- Change to the hygiene audit's `merged-prd-not-archived` rule.
- Broader "skills should read all their config" audit/policy engine.
- Executable test harness for `.kiln/issues/` lifecycle.
- Sweep of additional shelf skills for the discovery-vs-config pattern (sweep done in plan; result: zero gaps).

## Dependencies & Assumptions

- **Audit-pr agent reports the PR number to the team lead.** Step 4b uses `$PR_NUMBER` from the team-lead context. The current Step 4b pseudocode already assumes this. No new contract surface.
- **`$PRD_PATH` is in scope at Step 4b time.** Set in Pre-Flight step 3. No change needed.
- **`gh` CLI present** for any optional GitHub-side close (out of scope for this PRD — Step 4b only manipulates local files).
- **`date -u +%Y-%m-%d`** is the canonical date for log-file naming AND `completed_date` field.

## Risks (carried from PRD)

| Risk | Mitigation in this spec |
|---|---|
| Hidden second bug in `prd:` comparison beyond normalization | FR-003's diagnostic line surfaces residual mismatches; follow-on `/kiln:kiln-fix` if observed |
| FR-008 scope inflation | Capped at 0 additional skills (sweep done in plan.md §Decision 2) |
| Old `.shelf-config` files (CRLF, quoted, trailing whitespace) | Defensive parse routine matches `shelf-counter.sh`'s `_read_key()` pattern (contracts §3) |
| Diagnostic-log retention | Default `keep_last: 10`; rationale in plan.md §Decision 3 |
| Step 4b execution layer ambiguity | Pinned to team-lead main-chat (NFR-005, plan.md §Decision 1) |
| No executable smoke harness | Documented in SMOKE.md; matches kiln-claude-audit + kiln-hygiene precedent |

## Acceptance Definition

This spec is "implemented" when:
- All 8 FRs are met (verified by SC-001 through SC-008)
- `tasks.md` is fully `[X]`
- A clean run of `/kiln:kiln-build-prd` on this PRD itself archives this spec's source issues (`.kiln/issues/2026-04-23-build-prd-step4b-still-broken-post-pr144.md` and `.kiln/issues/2026-04-23-write-issue-note-ignores-shelf-config.md`) into `.kiln/issues/completed/`
- `/kiln:kiln-hygiene` after the merge reports zero `merged-prd-not-archived` items for this PRD's slug
