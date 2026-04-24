# Feature Specification: Coach-Driven Capture Ergonomics

**Feature Branch**: `build/coach-driven-capture-ergonomics-20260424`
**Created**: 2026-04-24
**Status**: Draft
**Input**: PRD at `docs/features/2026-04-24-coach-driven-capture-ergonomics/PRD.md`
**Derived From**:
- `.kiln/feedback/2026-04-23-we-should-add-a-way.md`
- `.kiln/feedback/2026-04-24-roadmap-agent-should-be-more-encouraging.md`
- `.kiln/issues/2026-04-23-claude-md-audit-lacks-project-context.md`
- `.kiln/issues/2026-04-24-kiln-vision-self-exploring-and-self-updating.md`

## Overview

Kiln's four capture surfaces — `/kiln:kiln-roadmap` item capture, `/kiln:kiln-roadmap --vision`, `/kiln:kiln-claude-audit`, and `/kiln:kiln-distill` — behave as cold-start checklists rather than coaching surfaces. This feature introduces a shared project-context reader and upgrades each surface to (a) read repo state first, (b) propose coached defaults, and (c) support accept-all / multi-select shortcuts. The change is additive: existing `--quick` and single-theme paths keep working unchanged.

## Clarifications

The PRD is frozen; the following implementation-shaping decisions were resolved during spec drafting:

1. **Multi-theme distill slug disambiguation** — When two selected themes share the same date + theme slug, the implementation uses a numeric suffix (`-1`, `-2`, ...) on the second and subsequent emitted PRDs. Rationale: deterministic, reversible, matches the existing three-group sort semantics without requiring theme-slug rewriting. (Resolves PRD "Risks & Open Questions" item 2.)
2. **Vision diff grouping** — Line-level vision edits are grouped **by vision section** (one section, one prompt block) on re-run, with a per-section accept-all option nested inside a global accept-all. Rationale: bounds prompt verbosity on active repos while preserving per-line granularity. (Resolves PRD "Risks & Open Questions" item 4.)
3. **External best-practices cache staleness threshold** — The cached copy of Anthropic's CLAUDE.md guidance at `plugin-kiln/rubrics/claude-md-best-practices.md` records a `fetched:` date; the audit flags the cache as stale when `fetched:` is older than 30 days. (Resolves PRD "Risks & Open Questions" item 3.)
4. **Partial-snapshot vision fallback** — When `.kiln/roadmap/items/` is empty but PRDs / README / CLAUDE.md exist, `--vision` drafts a partial vision from the available sources and annotates each section with the evidence that was (and was not) available. Only the fully-empty case (FR-010) triggers the banner-style blank-slate fallback. (Resolves PRD "Risks & Open Questions" item 6.)
5. **Tone validation for FR-006** — "Collaborative tone" is validated during PRD audit via manual review of SKILL.md prompt diffs. No CI assertion, no regex heuristic. (Acknowledges PRD "Risks & Open Questions" item 5.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Coached roadmap interview (Priority: P1)

A user runs `/kiln:kiln-roadmap <description>` (non-`--quick`) expecting to capture an item. The skill first emits a one-paragraph orientation showing how the described item fits the current phase, nearby items, and open critiques. Then for each interview question, the skill proposes a best-guess answer with a one-line rationale and offers `[accept / tweak / reject]`. The user can type `accept-all` at any point to finalize the item using suggested answers for unresolved questions.

**Why this priority**: This is the single most-invoked capture surface. Turning it from interrogation to coaching is the headline UX win of this PRD.

**Independent Test**: Run `/kiln:kiln-roadmap "add a dark-mode toggle"` in a repo that has at least one phase and one existing item. Verify (1) orientation paragraph appears before the first question, (2) each question offers a suggested answer with rationale, (3) `accept-all` finalizes the item without further prompts, (4) the resulting item file's frontmatter matches the suggested-or-tweaked values.

**Acceptance Scenarios**:

1. **Given** a repo with 1+ phase and 1+ roadmap item, **When** the user runs `/kiln:kiln-roadmap "<desc>"`, **Then** the skill emits an orientation block citing current phase, nearest items, and any open critiques before asking Question 1.
2. **Given** the skill has asked Question 1 with a proposed answer, **When** the user types `accept`, **Then** the proposed answer is recorded and Question 2 is asked.
3. **Given** the skill has asked Question 1, **When** the user types `accept-all`, **Then** all remaining questions are auto-resolved using their suggested answers and the item is written to `.kiln/roadmap/items/<slug>.md`.
4. **Given** the skill has asked Question 1, **When** the user types `tweak: <new value> then accept-all`, **Then** Question 1 uses the tweaked value, remaining questions use their suggestions, and the item is finalized.
5. **Given** the user runs `/kiln:kiln-roadmap --quick "<desc>"`, **When** the command completes, **Then** no orientation, no suggestions, no interview — existing behavior is preserved byte-for-byte.

---

### User Story 2 — Vision self-exploration on first run (Priority: P1)

A user runs `/kiln:kiln-roadmap --vision` in a repo that has PRDs and roadmap items but no `.kiln/vision.md` (or a stub one). The skill reads project state, drafts all four vision sections populated with concrete bullets, and cites evidence per line. The user reviews, accepts / edits, and the file is written with `last_updated:` stamped.

**Why this priority**: Today the vision skill hands back a blank template — users routinely skip it entirely. Shipping a first-draft-from-evidence makes the skill useful on day one.

**Independent Test**: Run `/kiln:kiln-roadmap --vision` in a repo with at least 3 PRDs and 5 roadmap items but no `.kiln/vision.md`. Verify (1) all four vision sections contain bullets, (2) every bullet cites its evidence (e.g., `derived from: docs/features/.../PRD.md`), (3) the file is written only after user confirmation.

**Acceptance Scenarios**:

1. **Given** `.kiln/vision.md` does not exist and the repo has 3+ PRDs, **When** the user runs `/kiln:kiln-roadmap --vision`, **Then** the skill drafts all four vision sections with evidence-citing bullets before asking for confirmation.
2. **Given** `.kiln/vision.md` exists and is populated, **When** the user runs `/kiln:kiln-roadmap --vision`, **Then** the skill produces a per-section diff of proposed edits and offers global accept-all / reject-all plus per-section accept-all.
3. **Given** the user accepts one edit, **When** the file is written, **Then** `last_updated:` in the frontmatter is bumped to today's ISO date.
4. **Given** the repo has no PRDs, no roadmap items, no README, and no CLAUDE.md, **When** the user runs `/kiln:kiln-roadmap --vision`, **Then** the skill emits a one-line banner announcing the blank-slate fallback and reverts to the existing open-ended question path.
5. **Given** the repo has PRDs and README but empty `.kiln/roadmap/items/`, **When** the user runs `/kiln:kiln-roadmap --vision`, **Then** the skill drafts a partial vision from available sources and annotates which sections used which evidence.

---

### User Story 3 — Project-context-grounded CLAUDE.md audit (Priority: P2)

A user runs `/kiln:kiln-claude-audit`. Before applying the usefulness rubric, the audit reads the project-context snapshot and extracts the repo's current commands, tech stack, and active phase. The generated preview at `.kiln/logs/claude-md-audit-<timestamp>.md` cites specific drift (e.g., "Active Technologies lists phase 06 but current phase is 08") and adds an "External best-practices deltas" subsection evaluating CLAUDE.md against Anthropic's published guidance.

**Why this priority**: Audit findings are currently generic and easy to ignore. Grounding them in project evidence makes them actionable.

**Independent Test**: Run `/kiln:kiln-claude-audit` in a repo where CLAUDE.md's Active Technologies section references a phase that is no longer current. Verify (1) the preview flags the phase drift with a specific citation, (2) a dedicated "External best-practices deltas" subsection is present, (3) no edits are applied to CLAUDE.md.

**Acceptance Scenarios**:

1. **Given** `CLAUDE.md` lists an old phase and the current phase is different, **When** the user runs `/kiln:kiln-claude-audit`, **Then** the preview log cites the specific section name and proposes a concrete edit grounded in the current phase.
2. **Given** the external best-practices cache is <30 days old, **When** the audit runs, **Then** the preview contains an "External best-practices deltas" subsection with at least one finding tied to the cached guidance.
3. **Given** the external best-practices cache is >30 days old, **When** the audit runs, **Then** the preview flags cache staleness and the audit attempts (and logs the result of) a fresh `WebFetch`.
4. **Given** the audit completes, **When** the user inspects `CLAUDE.md`, **Then** no changes have been applied — the audit remains propose-don't-apply.

---

### User Story 4 — Multi-theme distill with run-plan (Priority: P2)

A user runs `/kiln:kiln-distill` with a backlog containing several ripe themes. After the existing theme-grouping step, the skill presents a multi-select picker. The user selects N themes; the skill emits N PRDs — one per theme — under `docs/features/<date>-<slug>[-N]/PRD.md`, flips only the source entries actually bundled into each PRD, and prints a run-plan suggesting pipeline order.

**Why this priority**: Power users bundle several distillations per session. Today each requires a separate invocation.

**Independent Test**: Run `/kiln:kiln-distill` in a repo with at least 3 distinct themes. Select 2. Verify (1) two PRDs are emitted, (2) each PRD's `derived_from:` list references only its own source entries, (3) a run-plan block at the end of the output suggests `/kiln:kiln-build-prd <slug-1>` → `/kiln:kiln-build-prd <slug-2>` with rationale, (4) re-running the same command against unchanged state produces byte-identical PRDs.

**Acceptance Scenarios**:

1. **Given** the backlog has 3+ themes, **When** the user runs `/kiln:kiln-distill` and selects 2, **Then** exactly 2 PRDs are written and no others.
2. **Given** two themes share date + slug, **When** both are selected, **Then** the second PRD's directory is suffixed `-2` (numeric) and the first stays un-suffixed.
3. **Given** N PRDs are emitted, **When** the run-plan prints, **Then** it lists N `/kiln:kiln-build-prd <slug>` lines in an explicit order with a one-line rationale per line.
4. **Given** a source entry belongs to Theme A only, **When** both Theme A and Theme B are distilled, **Then** that entry's status flip affects Theme A's PRD only — Theme B's PRD does not touch it.
5. **Given** the user runs `/kiln:kiln-distill` with a single theme (or the default path), **When** the command completes, **Then** no multi-select picker appears and output is byte-identical to pre-change behavior.
6. **Given** an emitted PRD's `derived_from:` list, **When** it is sorted, **Then** it follows the three-group ordering (feedback, issue, roadmap-item) with filename-ASC within each group — the existing NFR-003 determinism guarantee holds per-PRD.

---

### Edge Cases

- **Project-context reader unavailable** — If the reader script errors (e.g., malformed YAML in a roadmap item), consuming skills must surface the error and fall back to existing non-coached behavior rather than silently masking the failure.
- **Very large repo** — With ~50 PRDs + ~100 items, the reader must still complete in <2 s (NFR-001). Scripts must avoid O(n²) scans.
- **Network unreachable during best-practices fetch** — `/kiln:kiln-claude-audit` must complete using the cached copy and log a single-line "cache used, network unreachable" note.
- **Roadmap item with unknown/ambiguous fields** — Coached suggestions must be sourced only from project-context signals, never invented; unknown fields get a `[suggestion: —, rationale: no evidence in repo]` placeholder to preserve tone calibration.
- **User accepts all then reviews the written item and wants to change one value** — The user must be able to run `/kiln:kiln-roadmap --reclassify` or manually edit the item file; this feature does not add an in-interview post-commit rewrite path.
- **Multi-theme distill with a single viable theme** — The multi-select picker still appears; selecting the lone theme yields identical output to single-theme behavior.
- **Distill re-run on same backlog** — Byte-identical output per emitted PRD; source-entry state flips are idempotent.
- **Vision re-run on unchanged repo state** — Zero diffs proposed; the skill prints "no drift detected" and does not bump `last_updated:`.

## Requirements *(mandatory)*

### Functional Requirements

**Shared project-context reader**

- **FR-001**: The system MUST provide a shared project-context reader at `plugin-kiln/scripts/context/` (script or library) that returns a single structured JSON object describing repo-state signals: open PRDs (path + title + date from `docs/features/*/PRD.md`), roadmap items (grouped by phase + state, each with id / kind / state / phase / addresses), roadmap phases (name + status + start / complete dates), `.kiln/vision.md` contents (if any), `CLAUDE.md` contents, `README.md` contents, and the list of installed plugin manifests (`plugin-*/.claude-plugin/plugin.json` names + versions).
- **FR-002**: The reader MUST be defensive: missing sources (absent vision, zero PRDs, empty roadmap) return an empty field in the JSON rather than failing. Consuming skills decide the fallback policy.
- **FR-003 (shared-reader consumption contract)**: The reader MUST emit deterministic JSON — collections sorted by filename ASC, no timestamps or environment-varying strings — so two invocations against unchanged repo state produce byte-identical output (pairs with NFR-002).

**`/kiln:kiln-roadmap` interview coaching**

- **FR-004**: The item-capture interview (non-`--quick`) MUST, for each question, offer a best-guess suggested answer drawn from the user's initial description plus the project-context snapshot. Each question MUST render as: question text + proposed answer + one-line rationale + `[accept / tweak / reject]` affordance.
- **FR-005**: The interview MUST accept an `accept-all` command at any point, finalizing the item using the suggested answers for any remaining unanswered questions. The form `tweak <value> then accept-all` MUST also be accepted for the current question only; remaining questions still use suggestions.
- **FR-006**: Before the first question, the skill MUST emit a one-paragraph *orientation* block that (a) names the current phase, (b) lists up to 3 nearby items (by phase + kind), (c) lists any open critiques whose `addresses[]` might be relevant, and (d) summarizes the vision if `.kiln/vision.md` exists. This block MUST precede every non-`--quick` invocation.
- **FR-007**: The SKILL.md prompt for `/kiln:kiln-roadmap` MUST be rewritten to read collaboratively ("Here's what I think, tell me if I'm off") rather than interrogatively. This is a tone requirement — validated by manual review of the SKILL.md diff during PRD audit, not by automated test. (PRD FR-006.)

**`/kiln:kiln-roadmap --vision` self-exploration**

- **FR-008**: On invocation of `--vision` with no `.kiln/vision.md` (or an empty/stub file), the skill MUST consume the project-context snapshot (FR-001) and draft all four vision sections with concrete bullets, each bullet citing its evidence (e.g., `derived from: docs/features/<slug>/PRD.md`). The user reviews the draft and confirms / edits before the file is written.
- **FR-009**: On invocation of `--vision` with a populated `.kiln/vision.md`, the skill MUST diff repo-state against the current vision and present **per-section** proposed edits tied to specific evidence (e.g., `PRD for structured-roadmap shipped — propose adding typed roadmap items to 'What we are building' [yes / rephrase / skip]`). The skill MUST offer global accept-all, global reject-all, and per-section accept-all.
- **FR-010**: Any accepted edit MUST bump `last_updated:` in the vision frontmatter to today's ISO date. If no edits are accepted, `last_updated:` MUST NOT change.
- **FR-011**: When the project-context snapshot is fully empty (no PRDs, no items, no README, no CLAUDE.md), `--vision` MUST fall back to the existing blank-slate question path and MUST emit a one-line banner announcing the fallback.
- **FR-012**: When the snapshot is partial (some sources present, others missing — e.g., no roadmap items but PRDs and README exist), `--vision` MUST draft a partial vision from available sources and annotate which sections used which evidence; NO banner fallback is emitted in the partial case.

**`/kiln:kiln-claude-audit` project-context grounding**

- **FR-013**: Before applying the usefulness rubric, the audit MUST consume the project-context snapshot (FR-001) and extract the repo's current commands (from `CLAUDE.md` `## Available Commands` parse), tech stack (from plugin manifests + `## Tech Stack` blocks), active phase (from roadmap phases with `status: in-progress`), and known-gotchas (from rubric signals). The audit preview at `.kiln/logs/claude-md-audit-<timestamp>.md` MUST cite at least one of these context signals in its recommendations.
- **FR-014**: The audit MUST evaluate `CLAUDE.md` against Anthropic's published guidance at `https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md`, cached at `plugin-kiln/rubrics/claude-md-best-practices.md` with a `fetched:` date in frontmatter. The preview MUST emit a dedicated subsection titled `## External best-practices deltas` containing at least one finding per run (or an explicit "no deltas found" note if the CLAUDE.md fully complies).
- **FR-015**: If the live best-practices doc cannot be fetched (network error, 404), the audit MUST fall back to the cached copy and log a single-line `cache used, network unreachable` note in the preview. If the cached copy's `fetched:` date is >30 days old, the audit MUST additionally flag cache staleness in the preview.
- **FR-016**: The audit MUST remain **propose-don't-apply**: no edits are written to `CLAUDE.md` by this skill. All findings stay in the preview log (PRD FR-013).

**`/kiln:kiln-distill` multi-theme emission**

- **FR-017**: After the existing theme-grouping step, the skill MUST offer a multi-select picker. The user selects N≥1 themes; the skill emits exactly N PRDs, one per selected theme, under `docs/features/<date>-<slug>[-M]/PRD.md` (numeric suffix `-2`, `-3`, ... applied when two selections share date + slug — first occurrence remains un-suffixed).
- **FR-018**: When N≥2 PRDs are emitted, the skill MUST print a **run-plan block** at the end of the output summarizing the emitted PRDs and suggesting `/kiln:kiln-build-prd <slug-1>` → `/kiln:kiln-build-prd <slug-2>` in an explicit order, with a one-line rationale per line (e.g., "foundational: touches shared reader" or "highest severity from bundle"). The run-plan MUST be omitted when only 1 PRD is emitted.
- **FR-019**: Source-entry status flips (Step 5 of distill) MUST be partitioned per-PRD: each emitted PRD only flips the entries it actually bundled. Cross-PRD accidental overwrites are prohibited — the implementation MUST assert per-flip that the target entry is in the current PRD's bundle.
- **FR-020**: The `derived_from:` invariant (three-group sort: feedback / issue / roadmap-item; filename-ASC within each group; frontmatter ↔ source-table parity) MUST apply independently to each emitted PRD. The existing determinism guarantee (spec `prd-derived-from-frontmatter` FR-037, structured-roadmap contract §7.2) MUST hold per-PRD.
- **FR-021**: Single-theme distill (N=1, or unchanged default path) MUST produce byte-identical output to pre-change behavior. The multi-select picker MAY appear in single-viable-theme repos; selecting the lone theme MUST yield byte-identical single-theme output.

### Non-Functional Requirements

- **NFR-001 (performance)**: The project-context reader MUST complete in <2 s on a repo with ~50 PRDs and ~100 roadmap items (PRD NFR-001). Measured by `time` wrapper in CI smoke test.
- **NFR-002 (determinism)**: Two invocations of the reader against unchanged repo state MUST produce byte-identical JSON output. Every collection MUST be sorted by filename ASC. No timestamps, no PIDs, no environment-varying strings.
- **NFR-003 (per-PRD determinism)**: Each emitted PRD in multi-theme distill MUST independently satisfy the `derived_from:` three-group-sort invariant. Re-running `/kiln:kiln-distill` against unchanged state MUST produce byte-identical per-PRD output.
- **NFR-004 (offline-safe)**: No network calls in the normal capture path. The only network-requiring piece is the `/kiln:kiln-claude-audit` external best-practices fetch (FR-014), which MUST degrade gracefully to the cached copy on failure.
- **NFR-005 (backward compat)**: `--quick` in `/kiln:kiln-roadmap` MUST continue to skip all interview + orientation logic. Single-theme `/kiln:kiln-distill` MUST produce byte-identical output to pre-change behavior. No existing caller sees a regression.
- **NFR-006 (hook-safety)**: New shell scripts under `plugin-kiln/scripts/context/` MUST NOT be invoked by PreToolUse hooks. They are called only by skill bodies. This keeps hook overhead unchanged.

### Key Entities

- **ProjectContextSnapshot** — Structured JSON emitted by the shared reader. Fields: `prds[]`, `roadmap_items[]` (grouped by `phase` + `state`), `roadmap_phases[]`, `vision` (object or null), `claude_md` (string or null), `readme` (string or null), `plugins[]`. Sort order documented in contracts/interfaces.md.
- **CoachedQuestion** — In-memory object passed through the roadmap interview loop. Fields: `id`, `question_text`, `suggested_answer`, `rationale`, `user_response` (one of `accept | tweak:<value> | reject | accept-all | skip`).
- **VisionDiff** — Per-section diff object for `--vision` re-run. Fields: `section_name`, `proposed_edits[]` (each with `line_index`, `current_text`, `proposed_text`, `evidence`), `user_action` (one of `accept-section | reject-section | step-through`).
- **ClaudeAuditFinding** — Individual finding row written into the preview log. Fields: `rubric_source` (internal vs external), `section`, `current`, `proposed`, `evidence`, `severity`.
- **DistillSelection** — User's multi-select result. Fields: `selected_themes[]`, `emitted_prds[]` (each with `slug`, `path`, `bundled_entries[]`), `run_plan` (list of suggested build-prd invocations with rationales, only populated when N≥2).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In coached interviews, users accept the suggested answer (unmodified) for ≥60% of questions on typical captures — measured by counting `accept` vs `tweak`/`reject`/`accept-all` across the first 20 real invocations post-ship.
- **SC-002**: First-run `/kiln:kiln-roadmap --vision` against a populated repo produces a vision document with all four sections non-empty on the first review pass (no additional back-and-forth required). Pass rate ≥90% across 10 repos of varying size.
- **SC-003**: Every `/kiln:kiln-claude-audit` preview log references at least one project-context signal (current phase, tech-stack drift, or command drift) AND at least one external-best-practices delta. Measured by grepping the preview file.
- **SC-004**: `/kiln:kiln-distill` with N themes selected emits exactly N PRDs with correct per-PRD source-entry status flips, zero cross-PRD contamination. Measured by automated test comparing source-entry states before/after.
- **SC-005**: Re-running `/kiln:kiln-distill` against unchanged state produces byte-identical per-PRD output (re-run diff is empty). Measured by `diff` in automated test.
- **SC-006**: Project-context reader completes in <2 seconds on a repo with ~50 PRDs and ~100 items. Measured by `time` in CI smoke test.
- **SC-007**: `--quick` and single-theme distill paths show zero behavioral change vs. pre-ship baseline. Measured by golden-file diff on representative fixtures.

## Assumptions

- Consumers already have the `structured-roadmap` substrate (`.kiln/roadmap/items/`, `.kiln/roadmap/phases/`) in place. Repos without it trigger existing fallback paths in the consuming skills.
- The `plugin-kiln/scripts/roadmap/` helpers (`list-items.sh`, `parse-item-frontmatter.sh`) are stable dependencies of the new reader. No changes to their signatures are in scope for this feature.
- `CLAUDE.md` lives at the repo root (kiln convention). Non-standard locations are out of scope.
- The `WebFetch` tool is available in the Claude Code runtime used by `/kiln:kiln-claude-audit`. If absent (offline CI, sandboxed env), FR-015's cache fallback is the normal path.
- Four vision sections are: "Mission", "What we are building", "What we are not building", and "Current phase" — the structure already mandated by the vision template.
- The existing `/kiln:kiln-distill` step sequence (read-backlog → group-themes → emit-PRD → flip-states) is preserved; multi-select inserts between group-themes and emit-PRD.
- No new MCP servers, no new plugin dependencies. All work stays inside `plugin-kiln/`.
- Manual SKILL.md prompt review (FR-007 tone, PRD FR-006) is an accepted validation path for this feature; not every behavior is unit-testable.

## Dependencies

- `plugin-kiln/scripts/roadmap/list-items.sh` — enumerates roadmap items by phase/state (existing).
- `plugin-kiln/scripts/roadmap/parse-item-frontmatter.sh` — parses item frontmatter (existing).
- `plugin-kiln/rubrics/claude-md-usefulness.md` — internal audit rubric (existing, unchanged).
- `plugin-kiln/rubrics/structural-hygiene.md` — unrelated, not consumed.
- `WebFetch` tool for FR-014 (optional; cached fallback always available).
- Spec `prd-derived-from-frontmatter` FR-037 — inherited determinism invariant applied per-PRD.
- Spec `structured-roadmap` contract §7.2 — three-group sort invariant applied per-PRD.
