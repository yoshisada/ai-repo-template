# Tasks: Pipeline Input Completeness

**Spec**: [spec.md](./spec.md)
**Plan**: [plan.md](./plan.md)
**Contracts**: [contracts/interfaces.md](./contracts/interfaces.md)
**Implementer count**: 1 (single implementer)
**Total tasks**: 11

Tasks are partitioned into 5 phases (Phase D is dropped per plan §Decision 2). Implementer MUST mark each `[X]` immediately on completion and commit per phase.

## Phase A — Step 4b: feedback scan + matching loop (FR-001, FR-002)

- [ ] **T01-1** Add the path-normalization helper and the two-source scan loop to Step 4b in `plugin-kiln/skills/kiln-build-prd/SKILL.md`.
  - Replace the current single-dir loop (lines ~596–610 of the existing Step 4b body) with the §1 step 2 helper + step 3 scan loop from `contracts/interfaces.md`.
  - Preserve the surrounding markdown prose (heading, intro paragraph, "If no matching issues are found..." trailer is replaced by the new diagnostic flow).
  - Validation: `grep -E 'for f in \.kiln/issues/\*\.md \.kiln/feedback/\*\.md' plugin-kiln/skills/kiln-build-prd/SKILL.md` returns a match.
  - **Maps to**: FR-001, FR-004 (normalize helper).
  - **Files**: `plugin-kiln/skills/kiln-build-prd/SKILL.md`.

- [ ] **T01-2** Add the archive loop with originating-directory preservation.
  - Append the §1 step 4 block (`for f in "${MATCH_LIST[@]}"; do …`) immediately after the scan loop.
  - Verify `mv` target uses `$(dirname "$f")/completed/` — NOT a hardcoded `.kiln/issues/completed/`.
  - Validation: `grep -E 'dest_dir="\${orig_dir}/completed"' plugin-kiln/skills/kiln-build-prd/SKILL.md` matches.
  - **Maps to**: FR-002.
  - **Files**: `plugin-kiln/skills/kiln-build-prd/SKILL.md`.

**Phase A commit**: `feat(kiln-build-prd): step 4b scans .kiln/feedback/ in addition to .kiln/issues/ (FR-001, FR-002)`

## Phase B — Step 4b: diagnostic + log marker (FR-003, FR-005)

- [ ] **T02-1** Add the per-file `skipped` accumulator hooks (already structured in T01-1's scan loop; verify they are present and correct).
  - The `SKIPPED=$((SKIPPED + 1))` increments on (a) failed normalization, (b) non-existent `prd:` target, (c) failed `mv`.
  - Validation: `grep -c 'SKIPPED=$((SKIPPED + 1))' plugin-kiln/skills/kiln-build-prd/SKILL.md` returns 2 (one in scan, one in archive on `mv` failure).
  - **Maps to**: FR-004.
  - **Files**: `plugin-kiln/skills/kiln-build-prd/SKILL.md`.

- [ ] **T02-2** Add the diagnostic-line emit step (§1 step 5).
  - Insert between the archive loop and the commit step.
  - Literal format MUST match `contracts/interfaces.md` §2. Verification: run the regex check from §2 on a sample stdout.
  - Validation: `grep -F 'step4b: scanned_issues=${SCANNED_ISSUES} scanned_feedback=${SCANNED_FEEDBACK}' plugin-kiln/skills/kiln-build-prd/SKILL.md` matches.
  - **Maps to**: FR-003.
  - **Files**: `plugin-kiln/skills/kiln-build-prd/SKILL.md`.

- [ ] **T02-3** Add the log-file append + commit logic (§1 step 6).
  - The log path uses `date -u +%Y-%m-%d` and lives at `.kiln/logs/build-prd-step4b-${TODAY}.md`.
  - Commit messages: `chore: step4b lifecycle — archived <N> item(s) for <PRD_PATH>` (matched) OR `chore: step4b lifecycle noop — <PRD_PATH>` (zero match).
  - Both branches MUST `git add "$LOG_FILE"`.
  - Validation: `grep -F '.kiln/logs/build-prd-step4b-${TODAY}.md' plugin-kiln/skills/kiln-build-prd/SKILL.md` matches.
  - **Maps to**: FR-005, NFR-003 (retention via `.kiln/logs/` default).
  - **Files**: `plugin-kiln/skills/kiln-build-prd/SKILL.md`.

**Phase B commit**: `feat(kiln-build-prd): step 4b emits diagnostic + log marker on every run (FR-003, FR-004, FR-005)`

## Phase C — `shelf-write-issue-note`: defensive parse + `path_source` (FR-006, FR-007)

- [ ] **T03-1** Replace the `read-shelf-config` step's command with the defensive parser from `contracts/interfaces.md` §3.
  - The output now follows the `## SHELF_CONFIG_PARSED ... ## END_SHELF_CONFIG_PARSED` block format.
  - If the implementer extracts the parser into a helper script, it MUST live at `plugin-shelf/scripts/parse-shelf-config.sh` and be invoked via `bash "${WORKFLOW_PLUGIN_DIR}/scripts/parse-shelf-config.sh"` (NEVER repo-relative — CLAUDE.md plugin-portability invariant).
  - Validation: `jq -r '.steps[] | select(.id=="read-shelf-config") | .command' plugin-shelf/workflows/shelf-write-issue-note.json` contains `SHELF_CONFIG_PARSED`.
  - **Maps to**: FR-006 (input parsing), NFR-006 (workflow portability).
  - **Files**: `plugin-shelf/workflows/shelf-write-issue-note.json`, optionally `plugin-shelf/scripts/parse-shelf-config.sh`.

- [ ] **T03-2** Update the `obsidian-write` agent instruction in the same workflow JSON.
  - Step 1 of the agent's instruction MUST consume the new structured `## SHELF_CONFIG_PARSED` block (not the legacy `cat` output).
  - The decision rule from `contracts/interfaces.md` §4 ("Decision rule for `path_source`") MUST be reflected in the agent's instruction verbatim, including the two literal `path_source` strings.
  - The Step 5 result-JSON template MUST include the `path_source` field.
  - The "MUST NOT call list_files" rule stays in place (no change).
  - Validation: `jq -r '.steps[] | select(.id=="obsidian-write") | .instruction' plugin-shelf/workflows/shelf-write-issue-note.json | grep -F '".shelf-config (base_path + slug)"'` matches.
  - **Maps to**: FR-006, FR-007.
  - **Files**: `plugin-shelf/workflows/shelf-write-issue-note.json`.

- [ ] **T03-3** Update `finalize-result` step's fallback JSON template to include `"path_source": "unknown"`.
  - The bash heredoc / `printf` in the `finalize-result` command needs the new field.
  - Validation: `jq -r '.steps[] | select(.id=="finalize-result") | .command' plugin-shelf/workflows/shelf-write-issue-note.json | grep -F 'path_source'` matches.
  - JSON validation: `jq . plugin-shelf/workflows/shelf-write-issue-note.json > /dev/null` exits 0.
  - **Maps to**: FR-007 (fallback observability).
  - **Files**: `plugin-shelf/workflows/shelf-write-issue-note.json`.

**Phase C commit**: `feat(shelf-write-issue-note): read .shelf-config defensively + record path_source (FR-006, FR-007)`

## ~~Phase D — Other shelf skills sweep~~ (DROPPED per plan §Decision 2)

Sweep performed in plan phase. Result: zero additional skills in scope. No tasks for Phase D.

## Phase E — Smoke fixtures + SMOKE.md (SC-008)

- [ ] **T04-1** Author `specs/pipeline-input-completeness/SMOKE.md` Step 4b section.
  - Includes §5.1, §5.2, §5.3, §5.6 fixture blocks from `contracts/interfaces.md` verbatim, with a brief introduction, "How to run", and per-block expected outputs.
  - Each block ends with the `echo OK || echo FAIL` assertion.
  - **Maps to**: SC-001, SC-002, SC-003, SC-006, SC-008.
  - **Files**: `specs/pipeline-input-completeness/SMOKE.md`.

- [ ] **T04-2** Author the `shelf-write-issue-note` section of `SMOKE.md`.
  - Includes §5.4 (shelf-config-present) and §5.5 (discovery-fallback) blocks verbatim.
  - Documents the `mv .shelf-config .shelf-config.bak` save-and-restore pattern.
  - **Maps to**: SC-004, SC-005, SC-008.
  - **Files**: `specs/pipeline-input-completeness/SMOKE.md`.

**Phase E commit**: `docs(spec): add SMOKE.md fixtures for pipeline-input-completeness (SC-008)`

## Phase F — Backwards-compat verification (NFR-002, SC-005, SC-007)

- [ ] **T05-1** Run all SMOKE.md fixtures end-to-end against the modified plugin sources, plus the SC-007 reverse-toggle check.
  - Document each fixture's `OK`/`FAIL` result in `specs/pipeline-input-completeness/agent-notes/implementer.md` under a "Backwards-compat verification" section.
  - For SC-007: temporarily comment out the Step 4b scan loop in a SCRATCH branch (DO NOT commit), run `/kiln:kiln-hygiene` against a pipeline state that should have leaked, confirm hygiene's `merged-prd-not-archived` rule still flags the items. Restore Step 4b on the working branch (no commit needed since the toggle was scratch-only). Document the result.
  - Validate `jq . plugin-shelf/workflows/shelf-write-issue-note.json > /dev/null` returns 0.
  - **Maps to**: NFR-002, NFR-004, SC-005, SC-006, SC-007.
  - **Files**: `specs/pipeline-input-completeness/agent-notes/implementer.md`.

**Phase F commit**: `chore(spec): backwards-compat verification log for pipeline-input-completeness (NFR-002, SC-007)`

## Friction Notes (NON-NEGOTIABLE)

Each agent MUST write `specs/pipeline-input-completeness/agent-notes/<agent-name>.md` BEFORE marking its top-level task `completed`. The retrospective reads these instead of polling live agents.

Per-agent notes:
- `specifier.md` — written by this specifier (now)
- `implementer.md` — written by the implementer at the end of Phase F (also carries the verification log per T05-1)
- `auditor.md` — written by the auditor before opening the PR

## Completion Definition

This task list is fully `[X]` when:
1. All 11 tasks above are marked `[X]`.
2. `jq . plugin-shelf/workflows/shelf-write-issue-note.json > /dev/null` exits 0.
3. `grep -E '^step4b: scanned_issues=' plugin-kiln/skills/kiln-build-prd/SKILL.md | wc -l` returns at least 1 (the literal template appears in the SKILL body).
4. `specs/pipeline-input-completeness/SMOKE.md` exists with both fixture sections.
5. `specs/pipeline-input-completeness/agent-notes/implementer.md` exists with the Phase F verification log.
6. The implementer has committed once per phase (5 commits expected — A, B, C, E, F).
