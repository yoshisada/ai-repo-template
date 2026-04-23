# Feature Spec: Kiln Capture-and-Fix Loop Polish

**Feature**: `kiln-capture-fix-polish`
**Branch**: `build/kiln-capture-fix-polish-20260422`
**PRD**: [docs/features/2026-04-22-kiln-capture-fix-polish/PRD.md](../../docs/features/2026-04-22-kiln-capture-fix-polish/PRD.md)
**Date**: 2026-04-22

## Summary

Polish the kiln authoring loop across three coherent areas:

- **A. `/kiln:kiln-fix` Step 7 refactor** — replace the `TeamCreate`/`TaskCreate` team-spawn path with inline main-chat MCP writes (one call for the Obsidian fix note, optionally one for a manifest-improvement proposal). Remove the two rendered team briefs and the rendering helper; keep the pure envelope/record/validate helpers.
- **B. `/kiln:kiln-fix` UX** — every terminal path (fixed, escalated, MCP-unavailable skip) closes with a `## What's Next?` section of 2–4 concrete next-command suggestions, matching the `/kiln:kiln-next` pattern.
- **C. New `/kiln:kiln-feedback` skill** — parallel to `/kiln:kiln-report-issue`, captures strategic product feedback to `.kiln/feedback/<YYYY-MM-DD>-<slug>.md` with a typed frontmatter schema.
- **D. Distill rename** — `/kiln:kiln-issue-to-prd` is renamed (hard-cutover) to `/kiln:kiln-distill`, taught to read both `.kiln/issues/` AND `.kiln/feedback/`, and weights feedback themes ahead of issues in the generated PRD narrative.

## User Stories

### US-001 (FR-001, FR-005) — Step 7 completes without recorder stalls

**As** a plugin maintainer running `/kiln:kiln-fix`,
**I want** Step 7 to complete without a haiku recorder teammate stalling on its terminal `TaskUpdate`,
**so that** I never have to intervene from main chat to unblock `TeamDelete`.

- **Given** a successful debug loop landed a fix commit,
- **When** Step 7 runs,
- **Then** main chat issues one `mcp__claude_ai_obsidian-projects__create_file` call for the fix note and control returns to the skill's final report without any `TeamCreate`, `TaskCreate`, `TaskUpdate`, `TeamDelete`, or `SendMessage` appearing in the transcript.

### US-002 (FR-007, FR-008) — "What's next" nudge after fix

**As** a plugin maintainer who just landed (or escalated) a fix,
**I want** the skill to close with a `## What's Next?` block of concrete next commands,
**so that** I don't drift or forget to verify.

- **Given** the skill reaches any terminal path (fixed / escalated / Obsidian skipped),
- **When** the final report is rendered,
- **Then** the report ends with a `## What's Next?` section of 2–4 concrete command suggestions chosen from the allowed set.

### US-003 (FR-009) — Strategic feedback capture

**As** a plugin maintainer noticing something wrong about the product's direction (not a specific bug),
**I want** a `/kiln:kiln-feedback <description>` command that writes a typed file to `.kiln/feedback/`,
**so that** strategic observations land somewhere durable instead of in chat scrollback.

- **Given** I run `/kiln:kiln-feedback "the distillation step feels issue-shaped and misses product-direction feedback"`,
- **When** the skill completes,
- **Then** a file `.kiln/feedback/2026-04-22-distillation-step-issue-shaped.md` exists with the required frontmatter (`type: feedback`, `date`, `status: open`, `severity`, `area`) and the description as the body.

### US-004 (FR-010, FR-011, FR-012) — Distill reads both sources, weights feedback

**As** a plugin maintainer running `/kiln:kiln-distill`,
**I want** the distilled PRD's Background/Problem sections to lead with feedback themes and relegate issues to the tactical layer beneath,
**so that** strategic direction shapes the PRD instead of being drowned in a pile of tactical bug tickets.

- **Given** `.kiln/feedback/` contains at least one open feedback item and `.kiln/issues/` contains at least one open issue,
- **When** `/kiln:kiln-distill` bundles them,
- **Then** the generated PRD's `## Background` and `## Problem Statement` sections cite the feedback theme first, and each issue appears as a tactical FR under the feedback-shaped theme.

### US-005 (FR-013) — Distill updates both sources' status

**As** a plugin maintainer,
**I want** distill to update both feedback and issue entries' `status` to `prd-created` and stamp `prd: <path>` on each,
**so that** repeat runs don't re-include already-distilled items.

- **Given** `/kiln:kiln-distill` includes one feedback file and one issue file in a new PRD,
- **When** the PRD is written,
- **Then** both source files have `status: prd-created` and a `prd: docs/features/<date>-<slug>/PRD.md` line (matching the current issue protocol).

## Functional Requirements

### Area A — `/kiln:kiln-fix` Step 7 inline refactor

- **FR-001** `/kiln:kiln-fix` Step 7 MUST perform the Obsidian fix-note write inline in main chat via a single `mcp__claude_ai_obsidian-projects__create_file` call (or the `-manifest__create_file` variant when the target path lives under `@manifest/`). Team-spawn (`TeamCreate`, `TaskCreate`) MUST NOT be used for this write. (PRD FR-001)

- **FR-002** The team-brief files `plugin-kiln/skills/kiln-fix/team-briefs/fix-record.md` and `plugin-kiln/skills/kiln-fix/team-briefs/fix-reflect.md` MUST be deleted along with their parent `team-briefs/` directory. The helper `plugin-kiln/scripts/fix-recording/render-team-brief.sh` MUST also be deleted — it has no remaining callers after FR-001 lands. (PRD FR-002)

- **FR-003** The manifest-improvement reflect step MUST run inline in main chat under a **deterministic file-path gate** (locked in plan Decision 1). Main chat evaluates the gate against the composed envelope; if the gate returns true, it writes ONE proposal via `mcp__claude_ai_obsidian-manifest__create_file` into `@inbox/open/`. If the gate returns false, main chat silently skips the reflect (no proposal written, no user-visible error). Team-spawn and wheel workflows MUST NOT be used for reflect. (PRD FR-003)

- **FR-004** The helpers `compose-envelope.sh`, `write-local-record.sh`, `resolve-project-name.sh`, `strip-credentials.sh`, `unique-filename.sh`, and any envelope/record validation scripts under `plugin-kiln/scripts/fix-recording/__tests__/` MUST be preserved — they are pure functions on the envelope/output and remain callable from the inline main-chat bash. (PRD FR-004)

- **FR-005** After FR-001/FR-002/FR-003 land, `grep -nE 'TeamCreate|TaskCreate|TaskUpdate|TeamDelete' plugin-kiln/skills/kiln-fix/SKILL.md` MUST return zero hits. No teammate-lifecycle failure modes remain in the skill body. (PRD FR-005; SC-001)

- **FR-006** When the Obsidian MCP server is unavailable (the `create_file` call returns an error, times out, or the server is not connected), Step 7 MUST:
  1. Still write the local record via `write-local-record.sh` (the local record is the fallback of record).
  2. Skip the Obsidian call without retrying.
  3. Report `Obsidian note: skipped (MCP unavailable)` in the final user report.
  4. Still emit the `## What's Next?` block (per FR-007). (PRD FR-006)

### Area B — `/kiln:kiln-fix` "What's next" prompt

- **FR-007** Every `/kiln:kiln-fix` terminal path MUST close with a `## What's Next?` section. Terminal paths covered: (a) successful fix + commit (Step 5 success), (b) escalation after 9 debug attempts (Step 6), (c) Obsidian-unavailable recording skip (FR-006 outcome). The section MUST contain 2–4 concrete next-command bullets. (PRD FR-007; SC-003)

- **FR-008** Suggestion selection MAY be static or dynamic. The implementation MUST choose ONE of:
  - **Static menu** (simplest): the same 4-line menu rendered verbatim on every terminal path.
  - **Dynamic menu** (preferred per PRD): UI-adjacent fix → `/kiln:kiln-qa-final` first; escalation → `/kiln:kiln-report-issue <follow-up>` first; otherwise → `/kiln:kiln-next` first. A PR-created path MAY include "review and ship the PR".

  The allowed command set is: `/kiln:kiln-next`, `/kiln:kiln-qa-final`, `/kiln:kiln-report-issue <follow-up>`, "review and ship the PR" (if a PR was created this run), "nothing urgent — you're done". Exactly 2–4 bullets chosen from this set. (PRD FR-008)

### Area C — `/kiln:kiln-feedback` capture skill

- **FR-009** A new skill `plugin-kiln/skills/kiln-feedback/SKILL.md` MUST exist. It MUST:
  1. Accept a free-form description as `$ARGUMENTS` (prompt for one if empty — matches `/kiln:kiln-report-issue` behavior).
  2. Derive a slug from the first ~6 words of the description (lowercase, non-alphanumerics collapsed to `-`, trailing `-` stripped). Matches `/kiln:kiln-report-issue`'s slug derivation.
  3. Classify the entry interactively OR from the `$ARGUMENTS` text for `severity` (one of `low|medium|high|critical`) and `area` (one of `mission|scope|ergonomics|architecture|other`). When ambiguous, ASK the user — do not guess.
  4. Write the file to `.kiln/feedback/<YYYY-MM-DD>-<slug>.md` with the feedback frontmatter schema (see `contracts/interfaces.md`) and the description as the body.
  5. Auto-detect repo URL via `gh repo view --json url -q '.url'` (same as report-issue). Include `repo:` in frontmatter; on failure emit `repo: null`.
  6. Scan `$ARGUMENTS` for file paths (same detection regex as report-issue) and include `files:` in frontmatter when any are found; otherwise omit the field.
  7. Print a one-line confirmation: `Feedback logged: .kiln/feedback/<file>.md`. No background sync, no Obsidian write — the feedback file is durable on disk and distill reads it on the next run. (PRD FR-009; SC-004)

### Area D — Distill rename + dual-source read + weighting

- **FR-010** `plugin-kiln/skills/kiln-issue-to-prd/` MUST be renamed to `plugin-kiln/skills/kiln-distill/` via `git mv`. The SKILL.md `name:` frontmatter MUST change to `kiln-distill`. `description:` MUST be updated to mention both issues AND feedback. No legacy alias, no shim, no redirect skill. (PRD FR-010; plan Decision 2 confirms `kiln-distill`.)

- **FR-011** The renamed distill skill MUST read from BOTH sources:
  - `.kiln/issues/*.md` where `status: open` (top-level only; NOT the `completed/` subdir — preserves current behavior).
  - `.kiln/feedback/*.md` where `status: open`.

  If neither directory has open entries, report "No open backlog or feedback items" and stop (matches current behavior). (PRD FR-011)

- **FR-012** In the generated PRD, feedback items MUST appear with higher weight than issues:
  1. The PRD's `## Background` and `## Problem Statement` sections MUST cite feedback themes FIRST (before issue themes).
  2. The PRD's `## Goals` MUST be shaped around feedback themes where any exist.
  3. Issue-level items MUST appear as tactical FRs under the feedback-shaped theme in `## Requirements`.
  4. The `### Source Issues` table MUST split into two sub-tables OR include a `Type` column with values `feedback` vs `issue`. Feedback rows MUST be listed first.
  5. If no feedback items are included in a given distill run, the PRD falls back to issue-only shape (matching today's behavior — FR-012 is a no-op when feedback is empty). (PRD FR-012; SC-005)

- **FR-013** After the PRD is written, the distill skill MUST update each included item's frontmatter regardless of source:
  - `status: open` → `status: prd-created`
  - Add `prd: docs/features/<date>-<slug>/PRD.md`

  The protocol applies identically to `.kiln/issues/` and `.kiln/feedback/` files. (PRD FR-013)

### Cross-cutting cleanup

- **FR-014 (derived, not in PRD)** Every LIVE reference to `/kiln:kiln-issue-to-prd` in non-historical paths MUST be updated to `/kiln:kiln-distill` in the same commit range as FR-010. Known live references:
  - `plugin-kiln/agents/continuance.md:69`
  - `plugin-kiln/skills/kiln-next/SKILL.md:248`
  - `plugin-kiln/skills/kiln-next/SKILL.md:342`
  - `docs/architecture.md:37,187,269`
  - `CLAUDE.md` if present (grep in implement phase).

  Historical paths (retrospective notes, prior-feature spec bodies, `.kiln/issues/` entries, `docs/features/2026-04-22-*/PRD.md`) are NOT updated — they describe history at the time of writing. (PRD SC-006)

## Non-Functional Requirements

- **NFR-001 (PRD NFR-001)** No new runtime dependencies. Work uses existing Bash 5.x + MCP (`mcp__claude_ai_obsidian-projects__*`, `mcp__claude_ai_obsidian-manifest__*`) + existing helpers under `plugin-kiln/scripts/fix-recording/`.

- **NFR-002 (PRD NFR-002)** Hard-cutover rename — no legacy alias skill, no compatibility shim, no redirect. Matches the pattern set by PR #121 and PR #127.

- **NFR-003 (PRD NFR-003)** The Step 7 inline path MUST NOT add more than ~2k tokens to main-chat context on a typical fix invocation. Measured as: envelope composition bash + ONE `create_file` MCP call + optional ONE `create_file` MCP call for reflect + final report rendering. No team-brief rendering, no team-spawn tool-call overhead.

## Success Criteria

- **SC-001 (PRD SC-001)** `grep -nE 'TeamCreate|TaskCreate|TaskUpdate|TeamDelete' plugin-kiln/skills/kiln-fix/SKILL.md` returns zero hits. Smoke-verified by running `/kiln:kiln-fix <trivial bug>` end-to-end and observing: local record written, Obsidian note written, no teammate lifecycle in the session transcript, final report printed.

- **SC-002 (PRD SC-002)** Three consecutive `/kiln:kiln-fix` runs on different bugs complete without main-chat intervention to mark tasks completed or request teammate shutdown. (Measured in the smoke-test phase.)

- **SC-003 (PRD SC-003)** The literal header `## What's Next?` appears in the final report on ALL three terminal paths: successful fix, escalation, Obsidian-skipped. Verified by grepping the rendered report.

- **SC-004 (PRD SC-004)** `/kiln:kiln-feedback "test feedback"` creates a file at `.kiln/feedback/<YYYY-MM-DD>-test-feedback.md` with the required frontmatter (all five required keys present and non-empty), and a subsequent `/kiln:kiln-distill` run picks up that file and includes it in a generated PRD with the feedback-first ordering of FR-012.

- **SC-005 (PRD SC-005)** A test backlog containing one feedback item and one issue produces a PRD whose `## Background` and `## Problem Statement` sections cite the feedback item first, and the issue appears in `## Requirements` as a tactical FR under the feedback-shaped theme.

- **SC-006 (PRD SC-006)** After the distill rename lands, `grep -rn 'kiln-issue-to-prd' plugin-*/ CLAUDE.md docs/` returns ONLY intentional historical hits (retrospective notes, prior-feature spec bodies, `.kiln/issues/` entries). Every live reference points to the new name.

## Out of Scope (inherits PRD Non-Goals)

- Removing wheel/teams from anywhere else in the codebase — this feature only touches `/kiln:kiln-fix` Step 7.
- Migrating `.kiln/issues/` entries to a new schema — existing files keep their current frontmatter.
- Redesigning the `/kiln:kiln-fix` debug loop (Steps 1–5) — only Step 7 and the new "What's Next?" (Step 8) are touched.
- Building a "feedback triage" agent or auto-routing feedback to build-prd — feedback stays static on disk.
- Writing a compatibility shim / legacy alias for the old distill name — hard cutover only.

## Traceability

Every FR above maps to at least one PRD requirement or a derived cleanup. Every user story maps to at least one FR. Every SC maps to at least one FR and to a PRD success criterion.

| Spec FR | PRD FR    | User Story | Success Criterion |
|---------|-----------|------------|-------------------|
| FR-001  | FR-001    | US-001     | SC-001            |
| FR-002  | FR-002    | US-001     | SC-001            |
| FR-003  | FR-003    | US-001     | SC-001            |
| FR-004  | FR-004    | —          | —                 |
| FR-005  | FR-005    | US-001     | SC-001, SC-002    |
| FR-006  | FR-006    | US-001     | SC-003            |
| FR-007  | FR-007    | US-002     | SC-003            |
| FR-008  | FR-008    | US-002     | SC-003            |
| FR-009  | FR-009    | US-003     | SC-004            |
| FR-010  | FR-010    | US-004     | SC-006            |
| FR-011  | FR-011    | US-004     | SC-004, SC-005    |
| FR-012  | FR-012    | US-004     | SC-005            |
| FR-013  | FR-013    | US-005     | SC-004            |
| FR-014  | (derived) | US-004     | SC-006            |
