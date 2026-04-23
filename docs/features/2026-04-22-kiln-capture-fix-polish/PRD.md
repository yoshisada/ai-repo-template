# Feature PRD: Kiln Capture-and-Fix Loop Polish

**Date**: 2026-04-22
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md) (placeholder; product context inherited from `CLAUDE.md`)

## Background

Two concurrent pieces of friction surfaced during the `plugin-naming-consistency` + `report-issue-speedup` runs, both in the kiln authoring loop:

1. **`/kiln:kiln-fix` Step 7 ("Record the Fix")** leans on `TeamCreate` + wheel team-spawn to write a single Obsidian note and optionally propose a single manifest patch. In practice the haiku recorder teammate has stalled on the terminal `TaskUpdate`, requiring main-chat intervention to unblock `TeamDelete`. The same work — one MCP write with a templated body — can run inline in main chat with zero failure surface. On top of that, the fix flow ends with a report but no "what's next" nudge, unlike `/kiln:kiln-next` which always closes with a suggested command.
2. **Capture is issue-only today.** `/kiln:kiln-report-issue` logs bugs and friction, but there is no dedicated path for strategic product feedback (what's wrong with the core mission, not with a specific command). Meanwhile, `/kiln:kiln-issue-to-prd` is scoped to issues by name, even though the same distillation pipeline could fairly consume feedback entries and weight them higher.

Both pieces are ergonomic polish on the kiln internal loop — neither adds a new product surface, but both remove repeated friction the maintainer has surfaced explicitly.

### Source Issues

| # | Backlog Entry | GitHub Issue | Type | Severity |
|---|---------------|--------------|------|----------|
| 1 | [`/kiln:fix` Step 7 recorder stalls; reconsider wheel/teams for fix recording](../../../.kiln/issues/2026-04-21-kiln-fix-step7-recorder-stall-teams.md) | — | issue (reliability) | medium |
| 2 | [`/kiln:fix` should not use the wheel plugin for the fix-recording step](../../../.kiln/issues/2026-04-21-kiln-fix-drop-wheel-plugin-from-recording.md) | — | issue (architecture) | medium |
| 3 | [`/kiln:fix` should prompt "what's next" after completion](../../../.kiln/issues/2026-04-21-fix-skill-should-prompt-next-step.md) | — | issue (skill-UX) | medium |
| 4 | [Add feedback capture tool and rename issue-to-prd](../../../.kiln/issues/2026-04-21-add-feedback-tool-and-rename-issue-to-prd.md) | — | enhancement | high |

## Problem Statement

The kiln authoring loop (capture → fix → distill → build) has three soft spots that cost the maintainer real time and attention:

- **Fix-recording is over-engineered for the work it does.** Spawning two short-lived Claude agent teams to write one Obsidian note and one optional manifest proposal has produced a recorder stall (issue #1), required manual task and team cleanup from main chat, and inherits wheel's grandchild-resolver failure modes (issue #2). The same write is one MCP call when done inline.
- **The fix report is a dead end.** After a fix lands (or escalates), there's no prompt suggesting what to do next. The maintainer either forgets to verify, drifts, or has to run `/kiln:kiln-next` from memory. Issue #3 is the direct ask.
- **Capture is bug-shaped only.** Issues and friction go into `.kiln/issues/`. Strategic feedback about product direction has nowhere to land. Distillation (`/kiln:kiln-issue-to-prd`) takes issues and never sees feedback, so PRD priorities are shaped entirely by tactical fixes. Issue #4 is the explicit ask for a parallel feedback surface + a rename to reflect the expanded distillation scope.

## Goals

- Replace `/kiln:kiln-fix` Step 7's team-spawn flow with inline MCP writes — one call for the Obsidian note, optionally one call for the manifest-improvement proposal.
- End every `/kiln:kiln-fix` run with a `## What's Next?` block suggesting a concrete next command, matching the `/kiln:kiln-next` pattern.
- Add a `/kiln:kiln-feedback` skill that writes strategic feedback entries to `.kiln/feedback/*.md`.
- Rename `/kiln:kiln-issue-to-prd` to a name that covers both issues AND feedback (proposed: `/kiln:kiln-distill`); make the renamed skill read from both `.kiln/issues/` and `.kiln/feedback/`, weighting feedback higher in the generated PRD narrative.

## Non-Goals

- Eliminating the wheel/teams primitive from the rest of the codebase — this PRD only removes it from `/kiln:kiln-fix` Step 7, where the work is mechanical. The build-prd pipeline, the kiln-report-issue workflow, and other team-driven flows stay as-is.
- Migrating `.kiln/issues/` entries to a new schema. Existing files keep their current frontmatter; only the NEW `.kiln/feedback/*.md` entries get a distinct shape.
- Redesigning the `/kiln:kiln-fix` debug loop (Steps 1–5). This PRD only touches Step 7 (recording) and adds a Step 8 (what's-next prompt).
- Writing a migration path for old `/kiln:kiln-issue-to-prd` references in skills / docs. A single-commit rename with a one-line deprecation note is acceptable.
- Building a "feedback triage" agent or auto-routing from feedback to build-prd. Feedback stays static-on-disk until the distill skill consumes it.

## Requirements

### Functional Requirements

**`/kiln:kiln-fix` Step 7 refactor — inline MCP writes**

- **FR-001 (from: #2 + #1)** `/kiln:kiln-fix` Step 7 MUST perform the Obsidian fix-note write inline in main chat via a single `mcp__claude_ai_obsidian-projects__create_file` (or `-manifest__create_file` for manifest paths) call, not via `TeamCreate` / `TaskCreate` / team dispatch.
- **FR-002 (from: #2)** The team briefs at `plugin-kiln/skills/kiln-fix/team-briefs/fix-record.md` and `team-briefs/fix-reflect.md` MUST be removed. The render-team-brief.sh helper SHOULD be removed too (no remaining callers).
- **FR-003 (from: #2)** The manifest-improvement reflect step MUST run inline in main chat: main chat reads the envelope, applies a deterministic gate (e.g., "skip unless the fix touched a file under `plugin-*/templates/` or `@manifest/` was explicitly named"), and if the gate passes, writes the proposal via one `mcp__claude_ai_obsidian-manifest__create_file` into `@inbox/open/`. No team-spawn, no wheel workflow.
- **FR-004 (from: #2)** The helpers `compose-envelope.sh`, `write-local-record.sh`, `validate-reflect-output.sh`, `check-manifest-target-exists.sh`, and `derive-proposal-slug.sh` SHOULD be preserved — they are useful pure functions on the envelope/reflect output and stay callable from inline main-chat bash.
- **FR-005 (from: #1)** After FR-001/FR-002/FR-003 land, `/kiln:kiln-fix` MUST NOT call `TeamCreate`, `TaskCreate`, `TaskUpdate`, or `TeamDelete` in Step 7. No teammate-lifecycle failure modes remain.
- **FR-006 (from: #1, #2)** When the Obsidian MCP server is unavailable, Step 7 MUST fall back gracefully: still write the local record, skip the Obsidian write, report "Obsidian skipped (MCP unavailable)" in the final output. No retry loops, no hangs.

**`/kiln:kiln-fix` UX — "what's next" prompt**

- **FR-007 (from: #3)** `/kiln:kiln-fix` MUST close every successful run, every escalated run, AND every recording-skip outcome with a `## What's Next?` section. The section MUST offer 2–4 concrete next commands chosen from at least: `/kiln:kiln-next`, `/kiln:kiln-qa-final` (if the fix touched UI-adjacent paths), `/kiln:kiln-report-issue <follow-up>`, "review and ship the PR" (if a PR was created), or "nothing urgent — you're done".
- **FR-008 (from: #3)** The suggestion logic MAY be static or dynamic. If dynamic: UI-adjacent fix → suggest `/kiln:kiln-qa-final` first; escalation → suggest `/kiln:kiln-report-issue` first; other → `/kiln:kiln-next` first. Static (a fixed 4-line menu) is also acceptable and strictly simpler.

**Feedback capture + distill rename**

- **FR-009 (from: #4)** A new skill `/kiln:kiln-feedback` MUST exist. It writes strategic-feedback entries to `.kiln/feedback/<YYYY-MM-DD>-<slug>.md`. The skill prompts for (or accepts as arg) a description, classifies the entry (severity, area of the product), and writes a frontmatter-plus-body markdown file. Minimum frontmatter: `type: feedback`, `date`, `status: open`, `severity`, `area` (one of: `mission`, `scope`, `ergonomics`, `architecture`, `other`).
- **FR-010 (from: #4)** `/kiln:kiln-issue-to-prd` MUST be renamed. The new name MUST reflect its expanded scope (both issues and feedback). Proposed: `/kiln:kiln-distill`. The rename follows the hard-cutover pattern (no legacy alias). Every cross-reference (CLAUDE.md, docs, other skills, `/kiln:kiln-next` whitelist) MUST update in lockstep.
- **FR-011 (from: #4)** The renamed distill skill MUST read from BOTH `.kiln/issues/*.md` (status: open) AND `.kiln/feedback/*.md` (status: open) when bundling items into a PRD.
- **FR-012 (from: #4)** In the generated PRD, feedback items MUST be weighted higher than issues:
  - Feedback themes appear FIRST in the PRD's Background / Problem sections
  - The PRD narrative is shaped around feedback themes where they exist
  - Issue-level fixes appear as the tactical layer underneath
  - If feedback and issues conflict, the feedback's direction overrides the issue unless the issue cites a hard bug (e.g., a failing test)
- **FR-013 (from: #4)** After the PRD is written, the distill skill MUST update EACH included item's `status: open` → `status: prd-created` AND add `prd: docs/features/<date>-<slug>/PRD.md` — same protocol that the current skill uses for issues, now applied to feedback too.

### Non-Functional Requirements

- **NFR-001** No new runtime dependencies. All work uses existing Bash + MCP + the existing kiln/shelf helper scripts.
- **NFR-002** Hard cutover on the rename — no legacy aliases, no compatibility shim. Matches the pattern set by PR #121 and PR #127.
- **NFR-003** The Step 7 inline path MUST NOT add more than ~2k tokens to main-chat context on a typical fix (per the issue #2 acceptance bullet; measured as the envelope composition + one MCP write + optional one MCP write for reflect).

## User Stories

- **US-001** As a plugin maintainer running `/kiln:kiln-fix`, I want Step 7 to complete without the recorder stalling, so I don't have to manually call `TaskUpdate` and `shutdown_request` from main chat to unblock teardown. (FR-001, FR-005)
- **US-002** As a plugin maintainer who just landed a fix, I want the skill to end with a "what's next" nudge so I don't drift or forget to verify. (FR-007)
- **US-003** As a plugin maintainer noticing something wrong about the product's direction (not a specific bug), I want a `/kiln:kiln-feedback` command that captures it in a typed file the same way `/kiln:kiln-report-issue` captures bugs. (FR-009)
- **US-004** As a plugin maintainer distilling backlog into a PRD, I want feedback items to drive the PRD narrative and issues to be the tactical layer underneath, so the strategic direction isn't drowned out by a pile of "/kiln:fix did X wrong" tickets. (FR-011, FR-012)

## Success Criteria

- **SC-001 No team-spawn in `/kiln:kiln-fix` Step 7.** After this lands, `grep -nE 'TeamCreate|TaskCreate|TaskUpdate|TeamDelete' plugin-kiln/skills/kiln-fix/SKILL.md` returns zero hits. Smoke verified by running `/kiln:kiln-fix <trivial bug>` end-to-end and observing: local record written, Obsidian note written, no teammate lifecycle in the session transcript, final report printed.
- **SC-002 No recorder stalls.** Three consecutive successful `/kiln:kiln-fix` runs on different bugs complete without main-chat intervention to mark tasks completed or request shutdown.
- **SC-003 Every `/kiln:kiln-fix` ends with `## What's Next?`.** Grep the final report output for the literal header `## What's Next?` — it MUST appear on successful, escalated, and MCP-unavailable terminal paths.
- **SC-004 `/kiln:kiln-feedback` round-trip.** Invoking `/kiln:kiln-feedback "test feedback"` creates a file at `.kiln/feedback/<YYYY-MM-DD>-test-feedback.md` with the required frontmatter, and the file is picked up by the renamed distill skill on the next run.
- **SC-005 Distill weights feedback.** A test backlog with one feedback item and one issue produces a PRD whose Background/Problem Statement sections cite the feedback first; the issue appears in Requirements as a tactical FR under the feedback-shaped theme.
- **SC-006 Hard rename.** After the distill rename lands, `grep -rn 'kiln-issue-to-prd' plugin-*/ CLAUDE.md docs/` returns only intentional historical hits (retrospective notes, prior-feature spec bodies). Every live reference points to the new name.

## Tech Stack

Inherited from the parent product — no additions:

- Markdown (skill/agent definitions)
- Bash 5.x (inline flow in Step 7 + existing helper scripts)
- Obsidian MCP tools (`mcp__claude_ai_obsidian-projects__*`, `mcp__claude_ai_obsidian-manifest__*`)
- `jq` for JSON parsing (already assumed)

## Risks & Open Questions

- **Inline reflect judgment vs. deterministic gate.** FR-003 allows either main-chat judgment ("does this fix reveal a manifest gap?") OR a deterministic file-path gate. Main-chat judgment is more flexible but costs ~1–2k tokens per fix; a deterministic gate is cheaper but may skip legitimate reflects. Plan phase should pick — recommend starting with the deterministic gate (cheap + predictable), leaving the door open for a judgment-based upgrade if gate false-negatives become visible.
- **Rename collision check.** Before committing to `/kiln:kiln-distill`, the plan phase should grep across kiln/shelf/clay/trim/wheel for any existing skill or workflow named `distill` — the plugin-prefix convention makes collisions unlikely but not impossible.
- **Feedback schema drift.** FR-009 proposes a minimum frontmatter (`type`, `date`, `status`, `severity`, `area`). If future feedback surfaces (e.g., `/kiln:kiln-mistake`) want a similar shape, the plan phase should decide whether to unify or keep distinct — prefer keeping distinct until a second use case exists.
- **Feedback-higher-than-issues conflict resolution** (FR-012). The "override" rule is mostly narrative — the plan phase may prefer a softer "highlight-first-then-tactical" framing over an "override" one. Spec phase should tighten the language.
- **Plugin cache divergence.** As always, once this lands, consumer repos need a plugin refresh to pick up the new skill names and Step 7 behavior. Same known property as PR #121 / PR #127.
