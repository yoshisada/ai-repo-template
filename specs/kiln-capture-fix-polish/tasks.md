# Tasks: Kiln Capture-and-Fix Loop Polish

**Spec**: [spec.md](./spec.md)
**Plan**: [plan.md](./plan.md)
**Contracts**: [contracts/interfaces.md](./contracts/interfaces.md)

Total: 22 tasks across 6 phases. Tracks run in parallel after this task file lands.

| Track                    | Phases      | Task range |
|--------------------------|-------------|------------|
| impl-fix-polish          | A + B       | T001..T009 |
| impl-feedback-distill    | C + D + E   | T010..T021 |
| Last implementer to land | F           | T022       |

## Legend

- `[ ]` = not done. `[X]` = done (mark immediately after completion — constitutional VIII).
- Each task lists its FR reference(s), owning track, and target file(s).

---

## Phase A — `/kiln:kiln-fix` Step 7 inline refactor (impl-fix-polish, 6 tasks)

- [X] **T001** (FR-001, FR-005) — In `plugin-kiln/skills/kiln-fix/SKILL.md`, rewrite **Step 7.5** to delete the "Render both team briefs" block entirely. Replace with a short "Read the envelope to derive slug / date / project_name" block that sets the same variables (`today`, `slug`, `project_name`, `abs_envelope`) the downstream inline MCP call will need. Keep Step 7.3 (compose envelope) and Step 7.4 (write local record) unchanged.

- [X] **T002** (FR-001, FR-005, FR-006) — In `plugin-kiln/skills/kiln-fix/SKILL.md`, replace **Step 7.6** ("Spawn both teams in parallel") with an inline `mcp__claude_ai_obsidian-projects__create_file` call. The call writes the fix note to `@projects/<project_name>/fixes/<date>-<slug>.md` with a body rendered from the envelope (reuse the body shape that was previously inside `team-briefs/fix-record.md`). On MCP error / unavailable, fall back per FR-006: keep local record, print `Obsidian note: skipped (MCP unavailable)`, continue to Step 7.9 cleanup.

- [X] **T003** (FR-003, FR-005) — In `plugin-kiln/skills/kiln-fix/SKILL.md`, replace **Step 7.7** (poll to completion) with an inline reflect block that: (a) evaluates the deterministic reflect gate predicate from `contracts/interfaces.md` Contract 2, (b) if gate fires, derives a proposal slug and writes to `@inbox/open/<YYYY-MM-DD>-manifest-improvement-<slug>.md` via `mcp__claude_ai_obsidian-manifest__create_file`, (c) if gate does not fire, silently skip. On MCP error, report `Manifest proposal: skipped (MCP unavailable)` and continue.

- [X] **T004** (FR-002, FR-005) — Delete `plugin-kiln/skills/kiln-fix/team-briefs/fix-record.md`, `plugin-kiln/skills/kiln-fix/team-briefs/fix-reflect.md`, and the empty parent directory `plugin-kiln/skills/kiln-fix/team-briefs/`. Delete `plugin-kiln/scripts/fix-recording/render-team-brief.sh`. Verify `compose-envelope.sh`, `write-local-record.sh`, `resolve-project-name.sh`, `strip-credentials.sh`, `unique-filename.sh`, and `__tests__/` remain.

- [X] **T005** (FR-005) — In `plugin-kiln/skills/kiln-fix/SKILL.md`, delete the now-unused Step 7.8 ("TeamDelete regardless of outcome") section entirely. Renumber 7.9 → 7.8 (Cleanup transient scratch) and 7.10 → 7.9 (User-facing report). Verify `grep -nE 'TeamCreate|TaskCreate|TaskUpdate|TeamDelete' plugin-kiln/skills/kiln-fix/SKILL.md` returns zero hits (SC-001 smoke).

- [X] **T006** (FR-004) — In `plugin-kiln/skills/kiln-fix/SKILL.md`, update Step 7's opening paragraph and the `### Constraints enforced by this step` block to match the inline flow: drop references to "spawns two parallel short-lived teams" and `TeamDelete`. Leave FR-019/FR-020/FR-025 cross-references that still apply (no wheel workflow, no team-spawn).

## Phase B — `/kiln:kiln-fix` "What's Next?" block (impl-fix-polish, 3 tasks)

- [ ] **T007** (FR-007, FR-008) — In `plugin-kiln/skills/kiln-fix/SKILL.md` Step 5 ("Verify and Commit"), append a `## What's Next?` block to the "Report to the user" template. Use the dynamic selection policy from `contracts/interfaces.md` Contract 4: UI-adjacent → `/kiln:kiln-qa-final` first; else → `/kiln:kiln-next` first. Include "review and ship the PR" bullet when a PR was created this run.

- [ ] **T008** (FR-007, FR-008) — In `plugin-kiln/skills/kiln-fix/SKILL.md` Step 6 ("Handle Escalation"), append a `## What's Next?` block to the escalation report template. Selection: `/kiln:kiln-report-issue <follow-up>` first, then `/kiln:kiln-next`, optionally "nothing urgent — you're done".

- [ ] **T009** (FR-006, FR-007) — In `plugin-kiln/skills/kiln-fix/SKILL.md` Step 7.9 (user-facing report), extend the report template so the `## What's Next?` block appears on the Obsidian-skipped terminal path too. If MCP was unavailable this run, include a bullet suggesting `/kiln:kiln-fix` (retry after MCP reconnect) or `nothing urgent — you're done`.

## Phase C — `/kiln:kiln-feedback` skill (impl-feedback-distill, 4 tasks)

- [X] **T010** (FR-009) — Create `plugin-kiln/skills/kiln-feedback/SKILL.md` with frontmatter `name: kiln-feedback` and description "Log strategic product feedback about the core mission, scope, or direction to `.kiln/feedback/`. Distinct from `/kiln:kiln-report-issue` which captures bugs and friction. Use as `/kiln:kiln-feedback <description>`." Body: Step 1 validate `$ARGUMENTS` (prompt if empty, matching report-issue style).

- [X] **T011** (FR-009) — In `plugin-kiln/skills/kiln-feedback/SKILL.md`, add Step 2: slug derivation (first ~6 words, lowercased, non-alphanumerics → `-`, trim trailing `-`). Add Step 3: auto-detect repo URL via `gh repo view --json url -q '.url' 2>/dev/null`; on failure emit `repo: null`. Add Step 3b: scan `$ARGUMENTS` for file paths using the same regex as `plugin-kiln/skills/kiln-report-issue/SKILL.md`; include `files:` array only if any match.

- [X] **T012** (FR-009) — In `plugin-kiln/skills/kiln-feedback/SKILL.md`, add Step 4: classify `severity` (from `low|medium|high|critical`) and `area` (from `mission|scope|ergonomics|architecture|other`) by inspecting `$ARGUMENTS`. On ambiguity, ASK the user — do not guess. Add Step 5: write the file to `.kiln/feedback/<date>-<slug>.md` with the frontmatter schema from `contracts/interfaces.md` Contract 1 and `$ARGUMENTS` as the body.

- [X] **T013** (FR-009) — In `plugin-kiln/skills/kiln-feedback/SKILL.md`, add Step 6: print confirmation `Feedback logged: .kiln/feedback/<file>.md` (one line, no background sync, no Obsidian write). Add a `## Rules` section noting: no MCP writes, no wheel workflow, file is durable on disk; `/kiln:kiln-distill` picks it up on the next run.

## Phase D — Distill rename + dual-source read (impl-feedback-distill, 5 tasks)

- [ ] **T014** (FR-010, NFR-002) — `git mv plugin-kiln/skills/kiln-issue-to-prd plugin-kiln/skills/kiln-distill`. Update the `name:` frontmatter in `plugin-kiln/skills/kiln-distill/SKILL.md` from `kiln-issue-to-prd` to `kiln-distill`. Update the `description:` to mention both issues AND feedback. Update the skill's H1 and all in-body `/kiln:kiln-issue-to-prd` self-references to `/kiln:kiln-distill`.

- [ ] **T015** (FR-011) — In `plugin-kiln/skills/kiln-distill/SKILL.md` Step 1, replace "Read all `.md` files in top-level `.kiln/issues/`" with dual-source read per `contracts/interfaces.md` Contract 3: read `.kiln/feedback/*.md` (`status: open`) AND `.kiln/issues/*.md` (top-level only, `status: open`). Tag each item with `type: feedback` or `type: issue` from its source directory. If both sets are empty, report "No open backlog or feedback items" and stop.

- [ ] **T016** (FR-012) — In `plugin-kiln/skills/kiln-distill/SKILL.md` Step 2 (group by theme), update the grouping language so feedback items are listed first within each theme, and themes containing any feedback are listed before issue-only themes. Update the sample "Backlog Summary" output to show the two-section shape (feedback themes first, then issue-only themes).

- [ ] **T017** (FR-012) — In `plugin-kiln/skills/kiln-distill/SKILL.md` Step 4 (Generate the Feature PRD), add a new subsection "Feedback-first narrative shape": `## Background` and `## Problem Statement` MUST cite feedback themes first; `## Goals` MUST be shaped around feedback themes where any exist; issue-level items MUST appear as tactical FRs under the feedback-shaped theme. Add a `Type` column to the `### Source Issues` sample table with values `feedback` / `issue`, feedback rows first.

- [ ] **T018** (FR-013) — In `plugin-kiln/skills/kiln-distill/SKILL.md` Step 5 (Update Backlog Status), broaden the language from "each included backlog entry" to "each included item — feedback or issue". Protocol is identical: `status: open` → `status: prd-created`; append `prd: docs/features/<date>-<slug>/PRD.md`. Note that both `.kiln/issues/` and `.kiln/feedback/` files get the update.

## Phase E — Cross-reference sweep (impl-feedback-distill, 3 tasks)

- [ ] **T019** (FR-014, SC-006) — Update `plugin-kiln/skills/kiln-next/SKILL.md:248` and `:342`: replace `/kiln:kiln-issue-to-prd` with `/kiln:kiln-distill`. Update `plugin-kiln/agents/continuance.md:69`: same replacement. Re-grep `plugin-kiln/` and `plugin-shelf/` for any other live references — these are the known ones but the grep must be rerun to catch anything added between plan and implementation.

- [ ] **T020** (FR-014, SC-006) — Update `docs/architecture.md` lines `37`, `187`, `269`: replace `/kiln:kiln-issue-to-prd` with `/kiln:kiln-distill`. Verify the diagram labels and surrounding prose still read correctly.

- [ ] **T021** (FR-014, SC-006) — Re-run `grep -rn 'kiln-issue-to-prd' plugin-*/ CLAUDE.md docs/architecture.md` after T014/T019/T020 land. Expected result: ONLY hits inside historical paths — PRD files, spec bodies under `specs/kiln-capture-fix-polish/`, `.kiln/issues/` entries, retrospective notes. Zero live hits in skills/agents/architecture docs.

## Phase F — Smoke-test documentation (last implementer, 1 task)

- [ ] **T022** (SC-001..SC-006) — Create `specs/kiln-capture-fix-polish/SMOKE.md` documenting the six smoke checks from `plan.md` §Smoke test plan, one command per SC. Include expected pass output for each. This is documentation only — no code change.

---

## Dependency notes

- Phase A tasks (T001..T006) mostly touch the same file — execute serially.
- Phase B tasks (T007..T009) extend A's work — execute after A completes.
- Phase C tasks (T010..T013) touch a new file only — can proceed in parallel with A and B.
- Phase D tasks (T014..T018) all touch the renamed skill — execute serially, T014 first.
- Phase E tasks (T019..T021) touch cross-references, MUST land after T014 (rename) so the grep in T021 reflects post-rename state.
- Phase F (T022) runs last, whichever track is free.

## Per-track task count

- impl-fix-polish: 9 tasks (T001..T009). ✓ under the 12-task cap.
- impl-feedback-distill: 12 tasks (T010..T021). ✓ at the 12-task cap.
- Last-lander: 1 task (T022).

## Completion protocol

Each task MUST be marked `[X]` **immediately** after completion (constitutional VIII). Commit after each phase — 6 commits total (A, B, C, D, E, F), plus the spec commit. Do not batch.
