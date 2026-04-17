---
description: "Task breakdown for the Mistake Capture feature (plugin-kiln + plugin-shelf)."
---

# Tasks: Mistake Capture

**Input**: Design documents from `/specs/mistake-capture/`
**Prerequisites**: plan.md, spec.md, contracts/interfaces.md, research.md, data-model.md, quickstart.md (all present).

**Tests**: Not generated. Plugin assets are Markdown + Bash + JSON — there is no automated unit-test harness for the kiln/shelf plugins (per plan.md Complexity Tracking and `CLAUDE.md`: "There is no test suite for the plugin itself"). Validation is end-to-end via the smoke-test phase against `quickstart.md`.

**Organization**: Tasks are split by OWNER, not by user story, because the feature's scope splits cleanly across two plugins (plugin-kiln and plugin-shelf). Each owner's tasks are further grouped into phases. The two owners can execute their phases in parallel after Phase 2 completes.

**Portability rule (non-negotiable)**: Every command-step reference MUST use `${WORKFLOW_PLUGIN_DIR}/scripts/...`. Any occurrence of `plugin-kiln/scripts/...` or `plugin-shelf/scripts/...` in workflow JSON is a portability bug per `CLAUDE.md`.

## Format: `[ID] [P?] [Owner] Description`

- **[P]**: Task can run in parallel (touches a different file with no unmet dependency)
- **[kiln]**: Owned by impl-kiln (works under `plugin-kiln/`)
- **[shelf]**: Owned by impl-shelf (works under `plugin-shelf/`)
- **[both]**: Joint task (smoke test, audit)
- All paths are repo-relative to `/Users/ryansuematsu/Documents/github/personal/ai-repo-template/`

---

## Phase 1: Setup (shared)

**Purpose**: Ensure the feature branch, spec artifacts, and `.kiln/mistakes/` directory convention are in place before either implementer starts.

- [X] T001 [both] Verify branch `build/mistake-capture-20260416` is checked out and `specs/mistake-capture/` contains spec.md, plan.md, contracts/interfaces.md, research.md, data-model.md, quickstart.md. If any are missing, stop and fix before proceeding.
- [X] T002 [P] [kiln] Add `.kiln/mistakes/` to the "active work surfaces" note in `CLAUDE.md` ("Recent Changes" or equivalent section) so the directory convention is documented alongside `.kiln/issues/`, `.kiln/logs/`, `.kiln/qa/`. Reference: research.md §Open Questions — Resolved (#2).
- [X] T003 [P] [both] Confirm wheel post-`005e259` is on `main` via `git log --oneline main -- plugin-wheel/lib/dispatch.sh | head -5`. If the `WORKFLOW_PLUGIN_DIR` export is absent, this feature is blocked — stop and raise.

**Checkpoint**: Spec artifacts present, branch checked out, wheel portability fix confirmed.

---

## Phase 2: Foundational (blocking for both owners)

**Purpose**: Items that MUST land before either implementer's Phase 3 tasks can run to completion. Kept minimal because the feature has few upfront shared dependencies.

- [X] T004 [both] Review `contracts/interfaces.md` end-to-end. Both owners confirm they can meet every contract in their scope. If any contract is ambiguous, update `contracts/interfaces.md` FIRST (per constitution VII) before implementation. Paste any edits into `specs/mistake-capture/agent-notes/contract-edits.md`.

**Checkpoint**: Contracts are final. Phase 3 (impl-kiln) and Phase 4 (impl-shelf) may now start in parallel.

---

## Phase 3: impl-kiln — Skill + Workflow + Command-Step Script

**Owner**: impl-kiln
**Goal**: `/kiln:mistake` activates the `report-mistake-and-sync` wheel workflow, which on invocation collects a schema-conformant mistake artifact under `.kiln/mistakes/` and terminates into `shelf:shelf-full-sync`.
**Independent exit criterion**: `/wheel-run kiln:report-mistake-and-sync` completes Step 1 (command) and Step 2 (agent) producing `.wheel/outputs/check-existing-mistakes.txt` and `.kiln/mistakes/YYYY-MM-DD-<slug>.md` + `.wheel/outputs/create-mistake-result.md`. Step 3 (sub-workflow) activates even if shelf extensions have not yet landed; success of the sub-workflow is tested in Phase 5 smoke.

### 3a. Command-step script (prerequisite for the workflow)

- [X] T005 [kiln] Create `plugin-kiln/scripts/` directory if it does not exist. Reference: contracts/interfaces.md §3.
- [X] T006 [kiln] Write `plugin-kiln/scripts/check-existing-mistakes.sh` per contracts/interfaces.md §3 — shebang `#!/usr/bin/env bash`, `set -euo pipefail`, no args, emits two H2 blocks (`## Existing Local Mistakes` / `## Recent Session Mistakes`) to stdout, exit 0 on "no files found". Must NOT exceed 80 lines. Do not reference `plugin-kiln/scripts/...` internally (use `$0`-relative or absolute `$WORKFLOW_PLUGIN_DIR` only).
- [X] T007 [kiln] `chmod +x plugin-kiln/scripts/check-existing-mistakes.sh` and verify executable by running it directly from the repo root: `bash plugin-kiln/scripts/check-existing-mistakes.sh` — expect well-formed output even when `.kiln/mistakes/` does not exist.

### 3b. Workflow JSON

- [X] T008 [kiln] Create `plugin-kiln/workflows/report-mistake-and-sync.json` per contracts/interfaces.md §2 exactly: `name: "report-mistake-and-sync"`, `version: "1.0.0"`, three steps with IDs `check-existing-mistakes` (command), `create-mistake` (agent), `full-sync` (workflow, `terminal: true`). Use `bash "${WORKFLOW_PLUGIN_DIR}/scripts/check-existing-mistakes.sh"` — NOT `plugin-kiln/scripts/check-existing-mistakes.sh`.
- [X] T009 [kiln] Author the `create-mistake.instruction` string in the workflow JSON per contracts/interfaces.md §2.1 — 9 numbered steps, honesty lint per §2.2, three-axis tag lint per §2.3, slug derivation per §2.4. Include the exact `.wheel/outputs/create-mistake-result.md` markdown shape (contracts §2.1 step 9). The five required body sections (`## What happened`, `## The assumption`, `## The correction`, `## Recovery`, `## Prevention for future agents`) must be enumerated explicitly.
- [X] T010 [kiln] Validate the workflow JSON with `jq '.' plugin-kiln/workflows/report-mistake-and-sync.json > /dev/null` (syntax) and a grep check: `grep -E 'plugin-(kiln|shelf)/scripts/' plugin-kiln/workflows/report-mistake-and-sync.json && echo PORTABILITY_BUG || echo OK`. Must print `OK`.

### 3c. Skill entrypoint

- [X] T011 [kiln] Create `plugin-kiln/skills/mistake/` directory.
- [X] T012 [kiln] Write `plugin-kiln/skills/mistake/SKILL.md` per contracts/interfaces.md §1 — frontmatter with `name: mistake` and the contract description, body with the LLM guardrails block (quote/summarize `@manifest/types/mistake.md` honesty principle + severity calibration + "do not write about the human" + "filename slug names the trap"), and the `/wheel-run kiln:report-mistake-and-sync` invocation. No structured prompting, no lint, no file writes.
- [X] T013 [P] [kiln] Inspect `plugin-kiln/.claude-plugin/plugin.json`. If it maintains an explicit `skills:` listing, add `"mistake"` to it. If skills are auto-discovered (no explicit list), skip this task and document in the PR description. Reference: contracts/interfaces.md §7. **Done**: skills are auto-discovered (no `skills:` list), but also added the new workflow to `workflows:` list which IS maintained.

### 3d. Sanity activation test (local-only, no shelf dependency)

- [X] T014 [kiln] ~From the repo root, run `/wheel:wheel-list` and verify `report-mistake-and-sync` is listed under the kiln plugin.~ **Deferred to Phase 5 smoke** — `workflow_discover_plugin_workflows` (plugin-wheel/lib/workflow.sh:323) reads from `~/.claude/plugins/cache/...`, so the new workflow won't appear in `/wheel-list` until the plugin is re-installed via marketplace. Surrogate verification performed: `jq '.workflows' plugin-kiln/.claude-plugin/plugin.json` confirms registration; `jq` parses the workflow JSON cleanly; direct `eval` of `.steps[0].command` with `WORKFLOW_PLUGIN_DIR` exported produces expected two-H2-block stdout.
- [X] T015 [kiln] ~Run `/wheel:wheel-run kiln:report-mistake-and-sync` ...~ **Deferred to Phase 5 smoke** — same plugin-cache reason as T014. All static contract checks pass (3 steps, correct ids/types, version 1.0.0, `terminal: true` on `full-sync`, 9 numbered sub-steps in `create-mistake.instruction`, all 5 body-section headings enumerated, honesty-lint trigger list present, three-axis tag-lint present, slug derivation described). End-to-end activation with honesty/tag-lint re-prompt behaviour will be exercised in Phase 5 T036.

### 3e. impl-kiln commit

- [X] T016 [kiln] Write `specs/mistake-capture/agent-notes/impl-kiln.md` — friction note covering what was clear in the spec/plan/contracts, what was ambiguous, any assumption made, and what you wish was more explicit. This is the retrospective input.
- [X] T017 [kiln] Commit all plugin-kiln changes in one conventional commit: `feat(kiln): add /kiln:mistake skill + report-mistake-and-sync workflow`. Files: `plugin-kiln/skills/mistake/SKILL.md`, `plugin-kiln/workflows/report-mistake-and-sync.json`, `plugin-kiln/scripts/check-existing-mistakes.sh`, `plugin-kiln/.claude-plugin/plugin.json` (if T013 changed it), `CLAUDE.md` (if T002 changed it), `specs/mistake-capture/agent-notes/impl-kiln.md`. Do NOT stage plugin-shelf changes; those belong to Phase 4's commit. **Committed as `8bda712`** (also included `VERSION` + `plugin-kiln/package.json` version bumps from the auto-increment hook).

**Checkpoint**: Skill + workflow + script are functional end-to-end through Step 2. Step 3 awaits Phase 4.

---

## Phase 4: impl-shelf — Work-List Extension + Proposal Writes + Manifest Reconciliation

**Owner**: impl-shelf
**Goal**: On every `shelf-full-sync`, `.kiln/mistakes/*.md` is discovered, a proposal is written to `@inbox/open/` (first-time only), and the sync manifest tracks each artifact's `proposal_state` (`open` → `filed`) so accepted proposals are never resurrected.
**Independent exit criterion**: With at least one file present in `.kiln/mistakes/`, running `/wheel-run shelf:shelf-full-sync` (standalone — not via the mistake workflow) produces a proposal in `@inbox/open/`, adds a `mistakes[]` entry with `proposal_state: "open"` to the sync manifest, and on a subsequent sync where the proposal has been moved out of `@inbox/open/`, transitions the manifest entry to `proposal_state: "filed"` without re-creating the proposal.

### 4a. Work-list extension (compute-work-list.sh)

- [X] T018 [shelf] Extend `plugin-shelf/scripts/compute-work-list.sh` to add the `mistakes_actions` array per contracts/interfaces.md §4. Discovery scans `.kiln/mistakes/*.md` (no recursion), computes `source_hash = sha256:<hex>` using the existing `shasum -a 256` pattern (see the script's PRD-hash logic around the existing `source_hash` block), indexes by `path` against the sync-manifest `mistakes[]` array, and emits per-entry objects with `action ∈ {create, update, skip}`.
- [X] T019 [shelf] In `compute-work-list.sh`, apply the `proposal_state == "filed"` short-circuit from contracts §4 — a filed entry is always `skip` regardless of source-hash change. This enforces FR-014.
- [X] T020 [shelf] Extend the assembled JSON output at the bottom of `compute-work-list.sh` to include the new top-level `mistakes:` key and the new `counts.mistakes: {create, update, skip}` sub-object per contracts §4 ("Updated top-level schema of compute-work-list.json"). Use `jq -n ... --argjson mistakes "$mistakes_actions"`.
- [X] T021 [shelf] Run `bash plugin-shelf/scripts/compute-work-list.sh` with a seeded `.kiln/mistakes/sample.md` and verify the output JSON parses and the new `mistakes[]` array appears. Backward-compat check: run the shelf-full-sync workflow's downstream steps against the extended output and confirm the existing `obsidian-apply` logic does not break (since it currently ignores unknown top-level keys).

### 4b. Proposal write (shelf-full-sync.json obsidian-apply step)

- [X] T022 [shelf] Extend the `obsidian-apply` agent step's `instruction:` string in `plugin-shelf/workflows/shelf-full-sync.json` per contracts/interfaces.md §5 — added a new loop (step 5) after the `docs` loop that handles the `mistakes[]` array. MCP scope routed to `mcp__claude_ai_obsidian-manifest__*` per contract-edits Edit 1.
- [X] T023 [shelf] Extended final results JSON (step 9) to include `mistakes: {created, updated, skipped, reconciliation[]}`. Added step 8 (`@inbox/open/` reconciliation) per contracts §5.3. Field classification documented in the instruction.
- [X] T024 [shelf] Validated: `jq '.'` passes, grep for `plugin-(kiln|shelf)/scripts/` returns nothing — `PORTABILITY OK`.

### 4c. Manifest reconciliation (update-sync-manifest.sh)

- [X] T025 [shelf] Extend `plugin-shelf/scripts/update-sync-manifest.sh` to add the new top-level `mistakes[]` array per contracts/interfaces.md §6. Upsert per-artifact row with `path`, `filename_slug`, `date`, `source_hash`, `proposal_path`, `proposal_state: "open"`, `last_synced` (ISO-8601 UTC) using the work-list + `.wheel/outputs/obsidian-apply-results.json` (`.mistakes` sub-object). Verified against seeded results.
- [X] T026 [shelf] Reconciliation moved to the `obsidian-apply` agent step (manifest-scope `list_files`, see contract-edits Edit 2 + contracts §5.3). `update-sync-manifest.sh` consumes the agent's `mistakes.reconciliation[]` array and applies `open → filed` transitions. Verified: fixture transitions from `open → filed` correctly; `filed → open` is impossible by design.
- [X] T027 [shelf] Reconciliation guard lives in the agent step (skip `list_files` when no reconciliation needed) per contracts §5.3. On the shell-script side: when `results.mistakes.reconciliation` is an empty array, the reduce is a no-op — no transitions applied, no MCP traffic.
- [X] T028 [shelf] Validated: `bash -n plugin-shelf/scripts/update-sync-manifest.sh` passes; seeded-results end-to-end test confirmed both the `create → open` upsert and the `open → filed` transition (with FR-014 skip-on-hash-change also verified through compute-work-list).

### 4d. shelf-full-sync command-step portability (audit, not modify)

- [X] T029 [P] [shelf] Grep all of `plugin-shelf/workflows/*.json` confirmed clean — all command steps use `${WORKFLOW_PLUGIN_DIR}/scripts/...`. No legacy portability bugs present.

### 4e. Sanity activation test

- [X] T030 [shelf] Fixture created at `.kiln/mistakes/2026-04-16-fixture-shelf-discovers-mistakes.md` with all 7 frontmatter fields + 5 body sections. (Deleted per T034.)
- [X] T031 [shelf] Surrogate for full `/wheel-run` (the wheel plugin-cache indirection is out of scope for this task; Phase 5 re-validates in the consumer install). Verified end-to-end via direct command chain:
  - `bash plugin-shelf/scripts/compute-work-list.sh` emitted `mistakes[0].action == "create"`, `counts.mistakes.create == 1`, `mistakes_prior_state == []`, and all `source_data` fields populated (title, assumption, correction, severity, status, tags, made_by, date, body). Verified via jq.
  - Composed the obsidian-apply proposal frontmatter for the fixture via jq (same logic the agent runs) — shape matches contracts §5.1 exactly (type=manifest-proposal, kind=content-change, target=@second-brain/projects/ai-repo-template/mistakes/..., mistake_class=mistake/assumption, tags start with mistake-draft).
  - Actually invoked `mcp__claude_ai_obsidian-manifest__create_file` with the composed content on `@inbox/open/2026-04-16-mistake-fixture-shelf-discovers-mistakes.md` — write succeeded, permission path confirmed. `list_files` on `@inbox/open/` returned the new file.
  - Ran `bash plugin-shelf/scripts/update-sync-manifest.sh` with seeded results JSON (`mistakes.created: 1`); manifest gained one `mistakes[]` row with `proposal_state: "open"` and correct source_hash/proposal_path/last_synced.
- [X] T032 [shelf] Filed-state transition verified end-to-end:
  - Moved the proposal out of `@inbox/open/` (via `mcp__claude_ai_obsidian-manifest__move_file` to `@ai/`) — simulates human acceptance.
  - Re-ran `compute-work-list.sh` with seeded manifest (proposal_state=open, matching path): `counts.mistakes.skip == 1`, action resolved to `skip` because the manifest says state is still open, but `mistakes_prior_state[0]` correctly carries the open entry to the agent for reconciliation. Separately verified: when the manifest is pre-set to `filed`, hash-mismatch still produces `skip` (FR-014 enforced).
  - Seeded `results.mistakes.reconciliation = [{new_state: "filed", path, proposal_path}]` and ran `update-sync-manifest.sh`: the manifest row transitioned `open → filed` and summary reported `Filed: 1`.
  - Verified `filed → open` is unreachable by inspection of the jq reduce (only matches `$r.new_state == "filed"`).

### 4f. impl-shelf commit

- [X] T033 [shelf] Friction note written at `specs/mistake-capture/agent-notes/impl-shelf.md`. Covers clarity, ambiguities (MCP scope, command-vs-agent reconciliation ownership, prior-state projection), assumptions (frontmatter parsing, mistake_class selection), wishes (MCP access matrix, scope ownership at plan time), upstream-bug awareness, and retrospective signals.
- [X] T034 [shelf] Fixture deleted. Manifest is unchanged (the earlier reconciliation tests were run against `/tmp/shelf-sync-backup.json` and restored after each probe — `.shelf-sync.json` has no mistake-capture entries). Obsidian-side cleanup: proposal moved out of `@inbox/open/` (to `@ai/`) so the inbox is clean for reviewers.
- [X] T035 [shelf] Committed at `026ef7c` with message `feat(shelf): discover .kiln/mistakes/ and propose @inbox/open/ drafts`. Files: `plugin-shelf/scripts/compute-work-list.sh`, `plugin-shelf/scripts/update-sync-manifest.sh`, `plugin-shelf/workflows/shelf-full-sync.json`, `plugin-shelf/.claude-plugin/plugin.json` (version bump), `plugin-shelf/package.json` (version bump), `specs/mistake-capture/contracts/interfaces.md`, `specs/mistake-capture/tasks.md`, `specs/mistake-capture/agent-notes/impl-shelf.md`, `specs/mistake-capture/agent-notes/contract-edits.md`. No plugin-kiln files staged.

**Checkpoint**: Shelf extensions are functional end-to-end. `shelf:shelf-full-sync` handles mistakes as first-class work-list entries.

---

## Phase 5: End-to-end smoke (joint, against quickstart.md)

**Purpose**: Prove the full `/kiln:mistake` → wheel activation → artifact write → sub-workflow → `@inbox/open/` proposal round-trip works on a real invocation, matching quickstart.md exit criteria.

- [~] T036 [both] **DEFERRED post-merge** (see `blockers.md` Blocker 1). Cannot run end-to-end from source repo — `workflow_discover_plugin_workflows` reads from `~/.claude/plugins/cache/...` which does not yet contain `report-mistake-and-sync.json`. Auditor performed surrogate smoke: shelf work-list path exercised with real fixture (`.kiln/mistakes/2026-04-16-assumed-audit-fixture-cleanup-autonomous.md`) → `counts.mistakes.create: 1`, all `source_data` fields populated, fixture cleaned. Full `/wheel-run` walk-through scheduled for first post-merge session.
- [~] T037 [both] **DEFERRED post-merge** (see `blockers.md` Blocker 1). Portability grep on branch JSON is CLEAN: `grep -E 'plugin-(kiln|shelf)/scripts/' plugin-kiln/workflows/report-mistake-and-sync.json plugin-shelf/workflows/shelf-full-sync.json` → no matches. Consumer-install portability smoke requires new cache version and runs post-merge.
- [~] T038 [both] **DEFERRED post-merge** (see `blockers.md` Blocker 1). State-file hygiene validation needs 3 real `/wheel-run` invocations; blocked by same cache-staleness reason as T036/T037.

---

## Phase 6: Audit + PR (handled by task #4 in the parent team)

**Note**: The PRD-audit and PR-creation tasks are owned by a separate downstream teammate (task #4 in the parent team's TaskList). This section lists what they will expect:

- [X] T039 [both] Produce `specs/mistake-capture/agent-notes/auditor.md`. Auditor wrote it during Phase 6; see the file for the retrospective friction note.
- [X] T040 [both] PRD audit: 16/16 FRs mapped to code + surrogate smoke evidence in `specs/mistake-capture/blockers.md`. Single deferred item (Phase 5 end-to-end `/wheel-run` smoke) documented as Blocker 1 with resolution path.
- [X] T041 [both] PR opened with `build-prd` label. Title bumped to `feat(kiln,shelf): add /kiln:mistake capture workflow` per team-lead dispatch. URL captured in the task-completion SendMessage.

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (Setup)**: No dependencies — both owners do T001–T003 together or sequentially.
- **Phase 2 (Foundational)**: Depends on Phase 1. Single task T004 — reviewing contracts. Blocks Phase 3 and Phase 4.
- **Phase 3 (impl-kiln)**: Depends on Phase 2 complete. Can run FULLY in parallel with Phase 4 — no shared files.
- **Phase 4 (impl-shelf)**: Depends on Phase 2 complete. Can run FULLY in parallel with Phase 3 — no shared files.
- **Phase 5 (smoke)**: Depends on BOTH Phase 3 and Phase 4 being committed.
- **Phase 6 (audit + PR)**: Depends on Phase 5.

### Task-level dependencies inside each phase

**Phase 3 (impl-kiln)**:
- T005 blocks T006, T007
- T006, T007 block T008 (script must exist before workflow references it)
- T008 blocks T009 (JSON structure before instruction-string authoring)
- T009 blocks T010 (validate after authoring)
- T011 blocks T012 (dir before file)
- T010, T012 block T014, T015 (validation and activation require both JSON and skill)
- T013 is independent of T011/T012 and can run in parallel
- T016, T017 are terminal for Phase 3

**Phase 4 (impl-shelf)**:
- T018, T019, T020 block T021 (must write code before testing it)
- T022, T023 block T024 (authoring before validation)
- T025, T026, T027 block T028
- T029 is independent; run any time in Phase 4
- T021, T024, T028 block T030, T031 (need all three extensions before sanity)
- T031 blocks T032 (must create before testing filed-state transition)
- T033, T034, T035 are terminal for Phase 4

### Parallel opportunities

- Phase 1: T002 and T003 are `[P]` — run in parallel. T001 is the serial prerequisite.
- Phase 3: T013 is `[P]` — can run while the script and workflow are being authored.
- Phase 4: T029 is `[P]` — can run at any point during Phase 4.
- Phase 3 and Phase 4: ENTIRELY parallel after Phase 2. The plugin boundary is a hard file-ownership boundary.

---

## Parallel Example

```text
# After Phase 1 + Phase 2 complete, both implementers work simultaneously:

impl-kiln (Phase 3):
  T005 → T006 → T007 → T008 → T009 → T010 → T011 → T012 → T014 → T015 → T016 → T017
  T013 runs in parallel with T011/T012.

impl-shelf (Phase 4):
  T018 → T019 → T020 → T021 → T022 → T023 → T024 → T025 → T026 → T027 → T028 → T030 → T031 → T032 → T033 → T034 → T035
  T029 runs in parallel at any point.

Then Phase 5 (T036–T038) is run jointly by both owners.
```

---

## Implementation Strategy

### Walking-skeleton-first

Both owners should aim for a walking skeleton as their first increment:
- impl-kiln: a SKILL.md that invokes a minimal workflow that runs Step 1 to completion (even with a stub `create-mistake` instruction). Commit this first.
- impl-shelf: `compute-work-list.sh` that emits an empty `mistakes[]` array on no-artifacts AND a single-entry array on one fixture file. Commit this first.

Once both skeletons are in place, flesh out the agent instruction (T009), proposal-write (T022), and reconciliation (T026) in sequence, committing per-phase.

### Parallel team strategy

1. Both owners read contracts/interfaces.md end-to-end (T004).
2. impl-kiln starts Phase 3 (T005–T017) independently.
3. impl-shelf starts Phase 4 (T018–T035) independently.
4. Both regroup for Phase 5 smoke (T036–T038).
5. Downstream auditor teammate picks up Phase 6.

Cross-owner dependency risk: NONE during Phase 3 and Phase 4 — no shared files. The only joint artifact is `specs/mistake-capture/agent-notes/contract-edits.md` (T004), which either owner may write if they surface an ambiguity.

---

## Notes

- Every contract reference in this file points to `specs/mistake-capture/contracts/interfaces.md` §N. Do not reinvent a contract; update the file FIRST if divergence is necessary (constitution VII).
- Mark each task `[X]` IMMEDIATELY on completion per constitution VIII. Do not batch.
- Commit after each Phase (T017 for Phase 3, T035 for Phase 4, a joint commit for Phase 5 if any fixes are made).
- The `.kiln/mistakes/` directory is created by the workflow on first write — do not scaffold it in advance.
- Do NOT commit any fixture mistake files or proposal files produced during sanity/smoke tests.
- If the hedge-word lint rejects unexpectedly during smoke, the fix belongs to impl-kiln (the lint lives in the workflow's `create-mistake.instruction`).
- If the `@inbox/open/` proposal ends up in the wrong MCP scope, the fix belongs to impl-shelf (swap `mcp__obsidian-projects__*` → `mcp__claude_ai_obsidian-manifest__*` in the `obsidian-apply` instruction, per research.md §R2 fallback).
