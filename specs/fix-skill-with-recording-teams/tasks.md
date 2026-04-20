# Tasks: Fix Skill with Recording Teams

**Input**: Design documents at `specs/fix-skill-with-recording-teams/`
**Prerequisites**: `spec.md`, `plan.md`, `contracts/interfaces.md`, `research.md`, `data-model.md`, `quickstart.md` (all present)

**Tests**: Pure bash `.sh` scripts are REQUIRED by this feature (FR-024, FR-030). Written TDD-adjacent: helpers and their tests are authored together, in the same phase per helper.

**Organization**: Sized for one implementer. 20 tasks total. Ordered by topological dependency — Setup → Foundational → US1 (happy path) → US2 (escalation) → US4/US5 (reflect) → US9 (manifest type) → US10 (portability) → Polish. Stories US3 (debug-loop preservation), US6 (token overhead), US7 (context isolation), US8 (MCP unavailability) are cross-cutting constraints enforced by the brief-template text and skill-edit guardrails in foundational/feature tasks — not separate phases.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Different file AND no ordering dependency with another [P]-marked task at the same rank. Safe to run in parallel.
- **[Story]**: Which user story (spec.md) this task primarily serves. Cross-cutting tasks have no story tag.

## Path Conventions

All helper scripts under `plugin-kiln/scripts/fix-recording/`. Tests under the same dir's `__tests__/`. Skill edit at `plugin-kiln/skills/fix/SKILL.md`. Manifest type staging at `specs/fix-skill-with-recording-teams/assets/manifest-types/fix.md`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the scaffold directories + gitignore + staging path so every subsequent task has a landing place. No code yet.

- [X] T001 Add `.kiln/fixes/` to `.gitignore` at repo root (one line after the existing `.kiln/qa/` entry), and verify the line is present by running `grep -Fxq '.kiln/fixes/' .gitignore`. Implements **FR-021**.
- [X] T002 [P] Create the helper-script directory and test directory: `plugin-kiln/scripts/fix-recording/` and `plugin-kiln/scripts/fix-recording/__tests__/`. Add a short `README.md` in each with one sentence explaining the dir's role. Implements the structure decision from **plan.md** (Source Code tree).
- [X] T003 [P] Create the staging path for the manifest type: `specs/fix-skill-with-recording-teams/assets/manifest-types/`. Implements decision **R3** and prepares T015's landing location.

**Checkpoint**: Scratch directories exist and gitignore is updated. No behavior yet.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The test harness + the two shortest helpers, because every subsequent phase depends on them.

**⚠️ CRITICAL**: No story-phase work can begin until this phase is complete.

- [X] T004 Author `plugin-kiln/scripts/fix-recording/__tests__/run-all.sh` — a pure-bash entrypoint that sources every `test-*.sh` in the same directory, runs each via `bash -e`, prints a per-test PASS/FAIL line, exits 0 only if all pass. Header comment cites **FR-024** and **FR-030**. Exit-1 on any failure.
- [X] T005 Author `plugin-kiln/scripts/fix-recording/strip-credentials.sh` with header citing **FR-026** and signature per `contracts/interfaces.md` → "strip-credentials.sh". Same task: author `__tests__/test-strip-credentials.sh` with at least three cases — (a) no `.kiln/qa/.env.test` present → passthrough; (b) credential line present → stripped; (c) comment/blank lines in env file → NOT treated as filters. Both files in one commit.
- [X] T006 Author `plugin-kiln/scripts/fix-recording/resolve-project-name.sh` with header citing **FR-013** and signature per contracts. Same task: author `__tests__/test-resolve-project-name.sh` covering (a) `.shelf-config` with `project_name=foo` → `foo`; (b) no `.shelf-config`, in a git repo → `basename`; (c) neither → empty stdout, exit 0. Both files in one commit.

**Checkpoint**: Run `bash plugin-kiln/scripts/fix-recording/__tests__/run-all.sh` — must pass. Strip-credentials and resolve-project-name are production-ready and reusable.

---

## Phase 3: User Story 1 (P1) — Successful fix produces a durable record 🎯 MVP

**Goal**: The happy-path pipeline end-to-end: envelope composed, local record written, both teams spawned (even if team briefs are initial drafts), Obsidian note lands. This is the feature's MVP — delivers the durability promise for successful fixes.

**Independent Test**: Run `/kiln:fix` on a reproducible test-failure bug. Verify `.kiln/fixes/<date>-<slug>.md` exists, `@projects/<project>/fixes/<date>-<slug>.md` exists in Obsidian, both teams were spawned and deleted.

- [X] T007 [US1] Author `plugin-kiln/scripts/fix-recording/compose-envelope.sh` per contracts (all nine envelope fields, stdin/flags contract, invokes `resolve-project-name.sh` + `strip-credentials.sh` internally). Header cites **FR-001**, **FR-013**, **FR-026**. Same task: author `__tests__/test-compose-envelope.sh` covering a fully-populated `status: fixed` envelope: output is valid JSON via `jq`, all nine fields present, credential line from a seeded `.kiln/qa/.env.test` was stripped from `fix_summary`. Both files in one commit.
- [X] T008 [US1] Author `plugin-kiln/scripts/fix-recording/unique-filename.sh` per contracts. Header cites **FR-015**. Same task: author `__tests__/test-unique-filename.sh` with three cases — (a) empty dir → base filename; (b) one existing file with the same stem → appends `-2`; (c) existing `-2` and `-3` → appends `-4`. Both files in one commit.
- [X] T009 [US1] Author `plugin-kiln/scripts/fix-recording/write-local-record.sh` per contracts (reads envelope JSON, emits markdown file per the FR-006 section schema, uses `unique-filename.sh` for collision handling, calls `derive-proposal-slug.sh` via `${SHELF_SCRIPTS_DIR}`). Header cites **FR-002**, **FR-006**, **FR-014**, **FR-015**, **FR-029**. Same task: author `__tests__/test-write-local-record.sh` verifying frontmatter fields, five H2 sections in order, `## Escalation notes` is `_none_` for `status: fixed`. Both files in one commit.

**Checkpoint**: The three deterministic helpers (compose + unique-filename + write-local-record) are verified. Together they own Steps 7.2–7.4 of the skill edit — no skill-prompt authoring yet.

- [X] T010 [US1] Author `plugin-kiln/scripts/fix-recording/render-team-brief.sh` per contracts (reads a template on stdin, substitutes six placeholders via flags, exits 1 on any unsubstituted placeholder). Header cites **FR-025**, **FR-027**, **FR-028**. Same task: author `__tests__/test-render-team-brief-fix-record.sh` and `__tests__/test-render-team-brief-fix-reflect.sh` as two thin fixtures that feed a small template + all-flags invocation and assert every placeholder was substituted and the resulting text contains the right anchor strings ("create_file", "read envelope at", "scripts-dir", etc. — enough to detect placeholder leakage). One commit for all three files.
- [X] T011 [US1] Author the `fix-record` team-brief template. Location per plan R4 — start inline in `plugin-kiln/skills/fix/SKILL.md` under a new `## Step 7 team briefs` subsection. If appending it plus the fix-reflect brief (T013) would push SKILL.md past 500 lines, instead create `plugin-kiln/skills/fix/team-briefs/fix-record.md` and reference it from SKILL.md. The brief must encode exactly the `fix-record` contract from `contracts/interfaces.md` (inputs, allowed tools, forbidden tools, escape-hatch conditions, terminal states 1–4). Cites **FR-003**, **FR-004**, **FR-007**, **FR-011**, **FR-016**, **FR-018**.
- [X] T012 [US1] Edit `plugin-kiln/skills/fix/SKILL.md` — add "Step 7: Record the fix" following Step 6 and preserving all existing text. Step 7 must implement the 11-item contract from `contracts/interfaces.md` → "Module: Skill-level contracts". Key requirements the edit must satisfy: (a) the whole Step 7 section starts with a line explicitly asserting that Steps 2b–5 complete in main chat before this step begins — **FR-020**; (b) resolves `SHELF_SCRIPTS_DIR` per R1; (c) issues both `TeamCreate` + `TaskCreate` pairs in one tool-call batch — **FR-003**; (d) polls tasks to completion and runs `TeamDelete` for both teams on every terminal outcome — **FR-017**; (e) deletes transient scratch files; (f) does NOT invoke `shelf:shelf-full-sync` or any wheel workflow — **FR-019**, **FR-023**; (g) extends the existing user-facing report format with the local-record path and Obsidian-note path. Commit only after both templates (T011 + T013) are drafted.

**Checkpoint**: MVP is runnable against a seeded successful-fix bug. Local record lands; Obsidian note lands; teams are spawned and deleted; main chat traffic is bounded.

---

## Phase 4: User Story 2 (P1) — Escalated fix still produces a record

**Goal**: Extend envelope composition and local-record writing to carry `status: escalated`, `commit_hash: null`, populated `## Escalation notes`. No new helper; just expand T007 + T009 test coverage.

**Independent Test**: Force debug loop to escalate; verify local record and Obsidian note both have `status: escalated` and a populated escalation section.

- [X] T013 [US2] Extend `plugin-kiln/scripts/fix-recording/__tests__/test-compose-envelope.sh` with a `status: escalated` case: `commit_hash` must be `null`, `files_changed` MAY be empty, `fix_summary` contains "techniques tried". Extend `__tests__/test-write-local-record.sh` with an escalated case: frontmatter `status: escalated`, `commit: null`, `## Escalation notes` is populated (NOT `_none_`), `## Files changed` may list inspected files. One commit. Cites **FR-012**.

**Checkpoint**: Escalated fixes are end-to-end-supported by the helpers. Skill edit from T012 already passes `--status escalated` when R7's condition holds — this phase just proves the downstream helpers behave.

---

## Phase 5: User Stories 4 + 5 (P2) — Reflect behaviors (silent + proposal)

**Goal**: Author the `fix-reflect` team brief. Reuses `check-manifest-target-exists.sh`, `validate-reflect-output.sh`, `derive-proposal-slug.sh` from `plugin-shelf/scripts/` via `${SHELF_SCRIPTS_DIR}`. No new helper.

**Independent Test**: (1) Run `/kiln:fix` on a trivial typo → `@inbox/open/` gains no file. (2) Run `/kiln:fix` on a seeded manifest-gap bug → `@inbox/open/<date>-manifest-improvement-<slug>.md` appears with FR-008 + FR-009 shape.

- [X] T014 [US4] [US5] Author the `fix-reflect` team-brief template. Same location decision as T011 (inline first, sibling file if SKILL.md exceeds 500 lines). The brief MUST encode the `fix-reflect` contract from `contracts/interfaces.md`: inputs available, allowed/forbidden tools, flow steps 1–5, exact-patch gate invocation, reflect-output path `.kiln/fixes/.reflect-output-<timestamp>.json`. Cites **FR-003**, **FR-008**, **FR-009**, **FR-010**, **FR-014**, **FR-018**, **FR-025**. T012 is updated in the same commit to wire this brief into the second `TeamCreate` call (if not already) — keep the skill edit self-consistent.

**Checkpoint**: Both team briefs exist, both are wired from SKILL.md. Reflect silent-on-no-op and proposal-on-gap paths both have complete prompt text.

---

## Phase 6: User Story 9 (P2) — Manifest type `fix.md`

**Goal**: Author the schema file that makes `fix-record` notes mean something in the vault.

**Independent Test**: After the feature lands, `@manifest/types/fix.md` is readable via MCP and every field/section the `fix-record` team writes validates against it.

- [X] T015 [US9] Author the `@manifest/types/fix.md` content at `specs/fix-skill-with-recording-teams/assets/manifest-types/fix.md`. Model on `@manifest/types/mistake.md` — prose intro, required-frontmatter section enumerating `type`, `date`, `status` (enum `fixed|escalated`), `commit`, `resolves_issue`, `files_changed` (list), `tags` (list); body-sections section enumerating the five H2s in order (`## Issue`, `## Root cause`, `## Fix`, `## Files changed`, `## Escalation notes`); tag-axes section publishing `fix/runtime-error`, `fix/regression`, `fix/test-failure`, `fix/build-failure`, `fix/ui`, `fix/performance`, `fix/documentation` plus inherited `topic/*` and one of `language/*|framework/*|lib/*|infra/*|testing/*`; and a concrete example note at the bottom. Cites **FR-005**, **FR-006**. Same task: perform the MCP write of the same content to `@manifest/types/fix.md` via `mcp__claude_ai_obsidian-manifest__create_file`. If the MCP is unavailable at implementation time, note this in a `blockers.md` and continue — the staging copy is authoritative. (MCP write deferred — see `blockers.md` "T015 — `@manifest/types/fix.md` MCP write not performed".)

**Checkpoint**: Vault has a schema for fix notes. Reviewers can critique the authored file in-repo.

---

## Phase 7: User Story 10 (P3) — Plugin portability

**Goal**: Verify no hardcoded `plugin-shelf/scripts/...` or `plugin-kiln/skills/...` path made it into any team brief or skill block.

**Independent Test**: Grep the skill + briefs for `plugin-shelf/scripts/` and `plugin-kiln/skills/` — all matches must be inside comments or code-fence examples, never in live substitution.

- [ ] T016 [US10] Write `plugin-kiln/scripts/fix-recording/__tests__/test-skill-portability.sh` — a pure-bash script that greps `plugin-kiln/skills/fix/SKILL.md` and any sibling brief under `plugin-kiln/skills/fix/team-briefs/` for the literal strings `plugin-shelf/scripts/` and `plugin-kiln/skills/`. Allow matches only inside `<!-- ... -->` HTML comment blocks or triple-backtick fenced code labeled with a non-shell language. Any other match exits 1. Add the test to `run-all.sh`. Cites **FR-025**.

**Checkpoint**: A regression test guards against future authoring accidents.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, smoke-run acknowledgement, per-phase commits. Cross-cutting invariants (FR-020 debug-loop preservation, FR-017 TeamDelete-always, FR-018 team context isolation, FR-016 MCP-unavailable) were enforced in T012 + T011 + T014 — this phase closes the loop.

- [ ] T017 Update `CLAUDE.md` Recent Changes section with a one-line entry pointing at `build/fix-skill-with-recording-teams-20260420` and the fix-recording feature. Bump VERSION's feature segment via `./scripts/version-bump.sh feature` (per the project's versioning convention). One commit.
- [ ] T018 [P] Walk `specs/fix-skill-with-recording-teams/quickstart.md` manually in a scratch branch inside the source repo with a seeded failing test. Record pass/fail per bullet list in the quickstart. If any bullet fails, return to the relevant phase (T012 for skill-level bugs, T011/T014 for brief bugs, T009 for local-record bugs). Do not mark this task complete until every bullet passes. Cites **SC-001**, **SC-005**, **SC-007**, **SC-009**.
- [ ] T019 [P] Walk `specs/fix-skill-with-recording-teams/quickstart.md` "Obsidian MCP unavailable" and "Project name unresolvable" cases. Verify the local record still lands, the final report names the skip, and `TeamDelete` still runs for both teams. Cites **SC-010**, **FR-013**, **FR-016**, **FR-017**.
- [ ] T020 [P] Walk `specs/fix-skill-with-recording-teams/quickstart.md` "Consumer-repo portability spot-check" — install the kiln plugin into a scratch repo that does NOT have `plugin-kiln/` or `plugin-shelf/` checked out, invoke `/kiln:fix` on a seeded bug, verify the full pipeline completes with no "No such file or directory" errors. Cites **SC-008**, **FR-025**.

**Checkpoint (feature done)**: All 20 tasks `[X]`. Unit tests green. All four manual smoke walks pass. PRD audit can run.

---

## Dependency graph

```text
T001 ─┐
T002 ─┼─► T004 ─► T005, T006 ─► T007 ─► T008 ─► T009 ─► T010 ─► T011 ─► T012
T003 ─┘                                           │                         │
                                                  │                         ▼
                                                  └──► T013 ◄───────────   T014 (uses T012 too)
                                                                              │
                                                                              ▼
                                                                             T015
                                                                              │
                                                                              ▼
                                                                             T016
                                                                              │
                                                                              ▼
                                                                             T017
                                                                              │
                                                                 ┌─────────┬──┴──┬────────┐
                                                                 ▼         ▼     ▼        ▼
                                                                T018      T019   T020
```

## Parallelism notes

- T002 + T003 are independent scaffolding; run in parallel.
- T005 + T006 are independent helpers; each can be authored in parallel once T004's run-all harness exists.
- T011 (fix-record brief) + T014 (fix-reflect brief) touch the same file (`SKILL.md`) when placed inline, so they serialize. If the implementer chooses sibling files per R4, they become parallel — the choice is driven by the growing line count of SKILL.md.
- T018 + T019 + T020 are independent smoke walks; all three run in parallel at the end.

## Implementation strategy

1. **MVP scope** = Phases 1–3 (T001–T012). Produces: successful `/kiln:fix` writes a local record, spawns both teams, Obsidian note lands. Even without reflect (Phase 5) or escalation polish (Phase 4) or manifest type (Phase 6), the skill is strictly better than today's commit-only trail.
2. **Add escalation (Phase 4)** — small, contained extension. Low risk.
3. **Add reflect (Phase 5)** — largest prompt-engineering risk (fix-reflect team brief). Keep the brief static; lean on `validate-reflect-output.sh` and `check-manifest-target-exists.sh` for correctness — do not let the agent invent novel validation.
4. **Author manifest type (Phase 6)** — can run before Phase 5 in practice if the implementer prefers; downstream correctness gates (`fix-record` schema conformance) depend on it existing in the vault.
5. **Portability regression test (Phase 7)** + **Polish (Phase 8)** close the loop.

## FR coverage cross-check

Every FR from spec.md is referenced by at least one task:

| FR | Task(s) |
|---|---|
| FR-001 | T007 |
| FR-002 | T009 |
| FR-003 | T011, T012, T014 |
| FR-004 | T011 |
| FR-005 | T015 |
| FR-006 | T009, T015 |
| FR-007 | T011 |
| FR-008 | T014 |
| FR-009 | T014 |
| FR-010 | T014 |
| FR-011 | T011 |
| FR-012 | T013 |
| FR-013 | T006, T007, T019 |
| FR-014 | T009, T014 |
| FR-015 | T008, T009 |
| FR-016 | T011, T019 |
| FR-017 | T012, T019 |
| FR-018 | T011, T014 |
| FR-019 | T012 |
| FR-020 | T012 |
| FR-021 | T001 |
| FR-022 | (constraint honored throughout — no task adds deps) |
| FR-023 | T012 |
| FR-024 | T004 (and every test task observes it) |
| FR-025 | T010, T014, T016, T020 |
| FR-026 | T005, T007 |
| FR-027 | T010 |
| FR-028 | T010, T011, T014 |
| FR-029 | T009 |
| FR-030 | T005, T006, T007, T008, T009, T010, T013 |

All 30 FRs covered.
