# Feature Specification: Structured Roadmap Planning Layer

**Feature Branch**: `build/structured-roadmap-20260424`
**Created**: 2026-04-24
**Status**: Draft
**Source PRD**: `docs/features/2026-04-23-structured-roadmap/PRD.md`

## Summary

Replace `/kiln:kiln-roadmap`'s one-liner scratchpad with a structured product-planning layer rooted at `.kiln/vision.md` + `.kiln/roadmap/`. Items are **typed** (`feature | goal | research | constraint | non-goal | milestone | critique`) under a single schema and live one-file-per-item under `.kiln/roadmap/items/`. Phases live under `.kiln/roadmap/phases/`. Capture goes through an **adversarial interview** that pushes back on thin ideas. `/kiln:kiln-distill` is extended to consume items as a third input stream alongside feedback + issues, with `--phase`, `--addresses`, and `--kind` filters. Every roadmap file mirrors to Obsidian via a new `shelf:shelf-write-roadmap-note` helper that reads `.shelf-config` (no vault discovery).

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Capture a feature idea with context-aware placement (Priority: P1) 🎯 MVP

The user types `/kiln:kiln-roadmap add a way to batch-process X`. The skill reads vision + phases + existing items, classifies the description as `kind: feature`, and runs the adversarial interview (≤5 questions: hardest part, assumptions, dependencies, cheaper version, what-breaks). It places the item in the right phase with AI-native sizing only and writes one file under `.kiln/roadmap/items/`.

**Why this priority**: This is the dominant capture path. Without it, the new system is unusable for its primary use case.

**Independent Test**: Run `/kiln:kiln-roadmap add a way to batch-process X` against a fresh `.kiln/roadmap/`; verify (a) one item file is created under `.kiln/roadmap/items/<YYYY-MM-DD>-<slug>.md`, (b) frontmatter includes `kind: feature`, `state: planned`, `blast_radius`, `review_cost`, `context_cost`, (c) NO `human_time` / `t_shirt` fields exist anywhere in the file, (d) the relevant phase file under `.kiln/roadmap/phases/<phase>.md` lists the new item id, (e) Obsidian mirror lands at `<base_path>/<slug>/roadmap/items/<basename>` with no vault discovery.

**Acceptance Scenarios**:

1. **Given** a fresh repo with `.shelf-config` populated and no `.kiln/roadmap/`, **When** the user runs `/kiln:kiln-roadmap add a way to batch-process X`, **Then** `.kiln/vision.md` and `.kiln/roadmap/{phases,items}/` are created from templates and one item file is written with `kind: feature` and AI-native sizing fields populated.
2. **Given** existing phases (`current`, `next`, `later`, `unsorted`) under `.kiln/roadmap/phases/`, **When** the interview completes, **Then** the item file's `phase:` matches the phase chosen during the interview AND the chosen phase's body lists the item id.
3. **Given** the item is written successfully, **When** the skill exits, **Then** the Obsidian mirror file exists at `<base_path>/<slug>/roadmap/items/<basename>` with no `list_files` discovery call having been made.

---

### User Story 2 — Record a critique and let it steer work (Priority: P1)

The user types `/kiln:kiln-roadmap kiln uses too many tokens compared to doing it by hand`. The skill auto-detects `kind: critique`, asks for `proof_path` (what would need to ship/measure to invalidate this critique), and writes the critique with `status: open`. Later features can reference the critique via `addresses: [<critique-id>]`, and `/kiln:kiln-distill --addresses <critique-id>` bundles them into a focused PRD.

**Why this priority**: Critiques are the highest-leverage steering mechanism in the system; they ship as seed content (FR-029) so the user must be able to add and reference them on day one.

**Independent Test**: Run `/kiln:kiln-roadmap kiln uses too many tokens`. Verify (a) `kind: critique` is auto-detected, (b) `proof_path` is captured (required), (c) `status: open` is set, (d) the file lives at `.kiln/roadmap/items/<YYYY-MM-DD>-<slug>.md`. Then run `/kiln:kiln-distill --addresses <critique-id>` and verify the generated PRD references the critique.

**Acceptance Scenarios**:

1. **Given** a description matching critique heuristics ("too many", "broken", "X compared to Y" framings of complaint), **When** the skill classifies, **Then** `kind: critique` is proposed and the interview asks for `proof_path` (required field).
2. **Given** a feature item with `addresses: [<critique-id>]`, **When** `/kiln:kiln-distill --addresses <critique-id>` runs, **Then** the PRD lists the feature in its `derived_from:` frontmatter and the body references the critique by id.
3. **Given** the seed critique bootstrap runs on first invocation, **When** the user inspects `.kiln/roadmap/items/`, **Then** three pre-filled critique files exist (token-cost, unauditable-buggy-code, too-much-setup) each with editable `proof_path` text.

---

### User Story 3 — Quick capture without the interview (Priority: P2)

The user is in a hurry and types `/kiln:kiln-roadmap --quick some idea I want to not forget`. The skill writes a stub item to the `unsorted` phase with `state: planned` and minimal frontmatter — body is the raw description. No interview, no follow-up loop, no Obsidian-roundtrip wait.

**Why this priority**: Without the escape hatch, interview fatigue (Risk #1 in the PRD) drives users back to the old scratchpad. Quick path is the safety valve.

**Independent Test**: Run `/kiln:kiln-roadmap --quick capture this`. Verify the file lands in `unsorted` phase with no interview prompts shown.

**Acceptance Scenarios**:

1. **Given** the `--quick` flag, **When** the skill runs, **Then** zero interview questions are asked and the item lands at `phase: unsorted, state: planned` with `kind: feature` (default) and the raw description as body.
2. **Given** a non-interactive session (no TTY), **When** the skill runs without `--quick`, **Then** it auto-detects non-interactive mode and falls back to the quick path.
3. **Given** `--quick` mode, **When** the item is written, **Then** the FR-018c follow-up prompt is suppressed.

---

### User Story 4 — Cross-surface routing is confirm-never-silent (Priority: P1)

The user types `/kiln:kiln-roadmap the build is broken`. The skill detects tactical framing and asks: "This sounds like an issue. Route to (a) `/kiln:kiln-report-issue`, (b) keep in roadmap, (c) `/kiln:kiln-feedback`?" If the user picks (a), the skill **invokes** `/kiln:kiln-report-issue <description>` (via the `Skill` tool) — it does NOT print "go run X instead" and exit.

**Why this priority**: Silent re-routing breaks the user's mental model of where their words went (Absolute Must #6). Misuse of the skill happens daily; routing must be visible and actionable.

**Independent Test**: Run `/kiln:kiln-roadmap the build is broken` in a session that records skill invocations. Verify (a) the routing prompt is shown, (b) on user-pick of `/kiln:kiln-report-issue`, the target skill is invoked with the original description, (c) NO roadmap item is written when the user routes away.

**Acceptance Scenarios**:

1. **Given** tactical framing ("X is broken / slow / wrong / crashes / hangs / doesn't work"), **When** the skill runs, **Then** it shows the three-way routing prompt before any classification or item write.
2. **Given** the user picks `/kiln:kiln-report-issue` at the prompt, **When** the skill executes the hand-off, **Then** it invokes `/kiln:kiln-report-issue <original-description>` via the `Skill` tool and exits without writing to `.kiln/roadmap/items/`.
3. **Given** ambiguous framing, **When** classification is uncertain, **Then** the skill presents all three options and waits for user choice rather than guessing.

---

### User Story 5 — Distill across streams with filters (Priority: P1)

The user runs `/kiln:kiln-distill --phase current` (or `--addresses <critique-id>`, or `--kind research`). Distill bundles matching items + feedback + issues into one themed PRD with feedback-led narrative (existing FR-012 ordering preserved) and item-led Implementation Hints.

**Why this priority**: The whole point of structured roadmap is that distill consumes it. Without this story, items are just paperwork.

**Independent Test**: With at least one item, one feedback file, and one issue file all matching `--phase current`, run `/kiln:kiln-distill --phase current`. Verify the PRD's `derived_from:` lists all three (feedback first, then items, then issues), and the item's `state` transitions to `distilled` with a `prd:` field.

**Acceptance Scenarios**:

1. **Given** items, feedback, and issues all in scope, **When** `/kiln:kiln-distill --phase current` runs, **Then** the generated PRD's `derived_from:` frontmatter includes paths from all three streams, sorted feedback → items → issues, filename ASC within each group (extending FR-012 ordering with a third group).
2. **Given** `--addresses <critique-id>`, **When** distill runs, **Then** only items whose `addresses:` array contains `<critique-id>` are bundled (plus feedback / issues that match the same theme tag if applicable; items are the primary filter).
3. **Given** an item is selected by distill, **When** the PRD finalizes, **Then** the item file is updated to `state: distilled` and a `prd:` frontmatter key points at the generated PRD path.
4. **Given** items carry `implementation_hints:`, **When** the PRD is rendered, **Then** an `## Implementation Hints` (or `## Known Unknowns`) section in the PRD reproduces the hints with item-id back-references.

---

### User Story 6 — Update the vision (Priority: P3)

The user types `/kiln:kiln-roadmap --vision`. The skill shows the current `.kiln/vision.md`, runs a short interview asking what's changed, writes the update, and patches the Obsidian mirror.

**Why this priority**: Useful but not blocking — the vision file can be hand-edited if needed; the dedicated path is a convenience that ships in v1.

**Independent Test**: Run `/kiln:kiln-roadmap --vision`. Verify `.kiln/vision.md` is updated and the Obsidian mirror at `<base_path>/<slug>/vision.md` is patched (not recreated, frontmatter preserved per FR-031).

**Acceptance Scenarios**:

1. **Given** `.kiln/vision.md` exists, **When** `--vision` runs, **Then** the current content is shown, a short interview is run, and the file is updated.
2. **Given** the vision is updated on disk, **When** the Obsidian mirror is patched, **Then** `mcp__claude_ai_obsidian-projects__patch_file` is used (NOT `update_file`) and existing frontmatter survives.

---

### User Story 7 — Phase management (Priority: P2)

The user types `/kiln:kiln-roadmap --phase start current`, `/kiln:kiln-roadmap --phase complete current`, or `/kiln:kiln-roadmap --phase create v2-foundations --order 5`. Only one phase may be `in-progress` at a time.

**Why this priority**: Required by the promotion lifecycle (planned → in-phase transition fires when phase activates). Without it, items get stuck in `planned`.

**Independent Test**: Create two phases, `--phase start` one, then attempt to `--phase start` the other. The skill must refuse and instruct the user to complete or pause the current one first.

**Acceptance Scenarios**:

1. **Given** no phase is `in-progress`, **When** `--phase start <name>` runs, **Then** that phase's `status` becomes `in-progress`, its `started:` is stamped, and all items assigned to it transition `state: planned → in-phase`.
2. **Given** a phase is already `in-progress`, **When** `--phase start <other>` runs, **Then** the skill refuses with a clear error and exits non-zero.
3. **Given** `--phase complete <name>` runs, **Then** the phase's `status` becomes `complete`, its `completed:` is stamped, and items assigned to it are NOT auto-deleted (FR-012).

---

### User Story 8 — Migration of legacy roadmap (Priority: P2)

On first run after this feature ships, if `.kiln/roadmap.md` exists, the skill parses each bullet into a `kind: feature` item with `phase: unsorted`, archives the legacy file to `.kiln/roadmap.legacy.md`, and prints a count + instructions.

**Why this priority**: Without migration, the user's existing roadmap is silently abandoned. The migration ships once, runs once, and gets out of the way.

**Independent Test**: Place a `.kiln/roadmap.md` with N bullets; run any `/kiln:kiln-roadmap` command. Verify (a) N item files appear under `.kiln/roadmap/items/` with `phase: unsorted`, (b) `.kiln/roadmap.legacy.md` exists and is byte-identical to the original, (c) the user is told to run `/kiln:kiln-roadmap --reclassify` to walk the unsorted items.

**Acceptance Scenarios**:

1. **Given** a legacy `.kiln/roadmap.md` with bullets under theme groups, **When** the skill runs for the first time after upgrade, **Then** every bullet becomes one item file with `kind: feature`, `phase: unsorted`, `state: planned`.
2. **Given** migration completes, **When** the user inspects the repo, **Then** the legacy file is renamed to `.kiln/roadmap.legacy.md` (NOT deleted) and the migration is idempotent — re-running does NOT re-migrate.

---

### User Story 9 — Multi-item input handling (Priority: P2)

The user types `/kiln:kiln-roadmap add batch-processing and also add a CLI shortcut`. The skill detects two distinct items and asks: "(a) two separate items, (b) one bundled, (c) split and review?" Default is (a). On (a)/(c), the capture flow runs once per item, but the phase-assignment interview runs ONCE up front (FR-018b) for the batch.

**Why this priority**: Multi-item dumps are common in practice and matching the existing `/kiln:kiln-feedback` / `/kiln:kiln-report-issue` policy of one-file-per-item keeps the system consistent.

**Independent Test**: Run `/kiln:kiln-roadmap add X and also add Y`. Verify the multi-item prompt appears and that on (a), two item files are created with the same `phase` (set once) and per-item interview answers.

**Acceptance Scenarios**:

1. **Given** a description with bullets / numbered list / "and also" / newline-separated thing-to-build phrases, **When** the skill runs, **Then** the multi-item prompt is shown with default (a).
2. **Given** the user picks (a), **When** capture proceeds, **Then** N item files are created with one shared phase-assignment but per-item interview answers.

---

### User Story 10 — Follow-up loop (Priority: P3)

After each item (or batch) is written, the skill asks "anything else on your mind?". If yes, it loops back to FR-014 (cross-surface routing) so the next item can route to issues / feedback / roadmap. On exit, it prints a per-surface session summary.

**Why this priority**: Quality-of-life; the system is functional without it but session capture density drops.

**Independent Test**: Run `/kiln:kiln-roadmap add X`, answer "yes" to the follow-up with a tactical description, confirm routing to `/kiln:kiln-report-issue`. Verify session summary lists "1 roadmap item, 1 issue".

**Acceptance Scenarios**:

1. **Given** an item is written successfully and the session is interactive AND not `--quick`, **When** the skill finishes the item, **Then** it asks "anything else on your mind?".
2. **Given** the user provides a follow-up description, **When** the skill processes it, **Then** it re-enters the FR-014 routing logic and may route to `/kiln:kiln-report-issue` or `/kiln:kiln-feedback`.
3. **Given** the user says no / exits, **When** the skill terminates, **Then** it prints `captured N roadmap items, M issues, K feedback this session` with paths.

---

### Edge Cases

- **`.shelf-config` missing or partial**: The skill logs a warning and continues writing to `.kiln/` only; Obsidian mirror is skipped this run. (Inherits the blocker dependency in PRD §FR-004 — once the blocker fix lands, `.shelf-config` is the canonical source.)
- **Duplicate item description**: The skill checks existing `.kiln/roadmap/items/*.md` for fuzzy-matching titles and warns if a near-duplicate exists; user picks "create anyway" or "abort".
- **Critique with no `proof_path`**: The interview re-asks until the user provides one, OR the user explicitly skips with `--no-proof-path` (warning recorded in body).
- **Item references unknown `addresses:` critique-id**: The skill warns and asks the user to confirm or fix; does NOT silently drop the reference.
- **Non-interactive session uses `--vision` or `--phase`**: Skill exits with a clear error — these flags require interaction.
- **`/specify` runs against a distilled item**: The item's `state` transitions `distilled → specced`; if the item is not in `state: distilled`, `/specify` does NOT block but logs that the item lifecycle is being skipped.
- **Migration races a manual edit of `.kiln/roadmap.md`**: Migration only fires when `.kiln/roadmap.md` exists AND `.kiln/roadmap.legacy.md` does NOT. After migration, `.kiln/roadmap.md` is removed (renamed) so the race window closes.

## Requirements *(mandatory)*

### Functional Requirements

The functional requirements below are inherited from `docs/features/2026-04-23-structured-roadmap/PRD.md` (FR-001 through FR-031). They are restated here with stable spec FR-IDs so implementation comments and tests can reference them. The PRD-FR → spec-FR mapping is 1:1 for FR-001..FR-031; spec FR-032..FR-040 are new derived requirements that the spec adds.

#### Directory + bootstrap

- **FR-001**: System MUST create `.kiln/vision.md` from a template on first run if missing. (PRD FR-001)
- **FR-002**: System MUST create `.kiln/roadmap/{phases,items}/` on first run, pre-populating `phases/unsorted.md` as the default landing spot. (PRD FR-002)
- **FR-003**: System MUST mirror every roadmap file to Obsidian using `<base_path>/<slug>/<relative-path>` composition from `.shelf-config`. (PRD FR-003)
- **FR-004**: Obsidian path composition MUST read `.shelf-config` directly (no vault discovery / no `list_files`). This depends on the blocker `2026-04-23-write-issue-note-ignores-shelf-config` being fixed first. (PRD FR-004)

#### Phase schema

- **FR-005**: Phase frontmatter required: `name`, `status` (`planned | in-progress | complete`), `order` (integer), `started` (ISO date, optional), `completed` (ISO date, optional). (PRD FR-005)
- **FR-006**: Phase body contains a short description plus an auto-maintained bulleted list of item-ids assigned to the phase. (PRD FR-006)

#### Item schema

- **FR-007**: Item frontmatter required: `id` (`<YYYY-MM-DD>-<slug>`), `title`, `kind`, `date`, `status`, `phase`, `state`. (PRD FR-007)
- **FR-008**: Item frontmatter required (sizing — AI-native only): `blast_radius` (`isolated | feature | cross-cutting | infra`), `review_cost` (`trivial | moderate | careful | expert`), `context_cost` (free-text rough estimate). The schema MUST forbid `human_time`, `t_shirt_size`, `effort_days`, or any other human-time / T-shirt sizing field. Validators MUST reject items containing forbidden fields. (PRD FR-008)
- **FR-009**: Item frontmatter optional: `depends_on: [<item-id>, ...]`, `addresses: [<critique-id>, ...]`, `implementation_hints` (free-text). (PRD FR-009)
- **FR-010**: `kind` is one of: `feature | goal | research | constraint | non-goal | milestone | critique`. (PRD FR-010)
- **FR-011**: `kind: critique` items MUST carry a required `proof_path` field; status lifecycle: `open | partially-disproved | disproved`. (PRD FR-011)
- **FR-012**: Items MUST NOT be auto-deleted on phase completion or feature-ship; status is updated, file persists. (PRD FR-012)

#### Capture skill

- **FR-013**: `/kiln:kiln-roadmap <description>` MUST first read `.kiln/vision.md`, `.kiln/roadmap/phases/*.md`, and `.kiln/roadmap/items/*.md` to build context before classification. (PRD FR-013)
- **FR-014**: Cross-surface routing MUST run BEFORE within-roadmap classification. Heuristics: tactical framing → offer `/kiln:kiln-report-issue`; strategic framing → offer `/kiln:kiln-feedback`; product-intent framing → stay in roadmap. Ambiguous → present all three and ask. NEVER silently re-route. (PRD FR-014, Absolute Must #6)
- **FR-014a**: After routing confirms roadmap, system MUST auto-detect `kind` (critique-like → critique; investigate/research → research; "we will not" → non-goal; default → feature). If ambiguous, ask user. (PRD FR-014a)
- **FR-014b**: When the user picks a non-roadmap surface at the routing prompt, the roadmap skill MUST invoke the target skill via the `Skill` tool with the original description as its argument, then exit. It MUST NOT merely print "go run X instead". (PRD FR-014b)
- **FR-015**: Interview is adversarial per kind, ≤5 questions per kind, each individually skippable. Per-kind question banks defined in `contracts/interfaces.md` §Interview. (PRD FR-015)
- **FR-016**: Interview places the item in a phase using existing phase content as context; user can override. (PRD FR-016)
- **FR-017**: Interview captures AI-native sizing (`blast_radius`, `review_cost`, `context_cost`) ONLY — never asks for human-time or T-shirt sizes. (PRD FR-017, Absolute Must #3)
- **FR-018**: `--quick` flag (or auto-detect short input / non-interactive sessions) skips the interview; item lands at `phase: unsorted`, `state: planned`, body = raw description. (PRD FR-018)
- **FR-018a**: Multi-item input handling — detect bullets / numbered lists / "and also / plus / as well as" / newline-separated thing-to-build phrases. Prompt user with (a) N separate items [default], (b) one bundled item, (c) split and review. (PRD FR-018a)
- **FR-018b**: Multi-item splits share the phase-assignment interview ONCE up front; per-item interviews still run. (PRD FR-018b)
- **FR-018c**: After each item (or batch) is written, ask "anything else on your mind?" and loop back through FR-014 routing on yes. Skipped under `--quick` and non-interactive sessions. On exit, print per-surface session summary. (PRD FR-018c)
- **FR-019**: `/kiln:kiln-roadmap --vision` runs a short vision-update interview, writes `.kiln/vision.md`, patches Obsidian mirror. (PRD FR-019)
- **FR-020**: `/kiln:kiln-roadmap --phase <action>` supports `start <name>`, `complete <name>`, `create <name> --order <N>`. Only one phase may be `in-progress` at a time. (PRD FR-020)

#### Promotion lifecycle

- **FR-021**: Items carry `state` independent of `kind`: `planned | in-phase | distilled | specced | shipped`. Transitions: planned → in-phase (auto, on phase activation); in-phase → distilled (auto, written by distill); distilled → specced (auto, written by `/specify` / `kiln:specify`); specced → shipped (manual in v1). (PRD FR-021)
- **FR-022**: `/kiln:kiln-roadmap --check` MUST report items whose `state` is inconsistent with their `phase` / spec / PR status. (PRD FR-022)

#### Distill integration

- **FR-023**: `/kiln:kiln-distill` MUST ingest `.kiln/roadmap/items/*.md` as a third input stream alongside `.kiln/feedback/` and `.kiln/issues/`. (PRD FR-023)
- **FR-024**: When items are present, distill's narrative MUST lead with feedback first (existing FR-012 from `kiln-distill`) AND items second (features in current phase). Issues remain the tactical layer. (PRD FR-024)
- **FR-025**: Distill MUST support filters: `--phase <name>` (default: current), `--addresses <critique-id>`, `--kind <kind>`. (PRD FR-025)
- **FR-026**: When distill promotes an item, it MUST write `state: distilled` to the item file and add a `prd:` field pointing at the generated PRD. (PRD FR-026)
- **FR-027**: `implementation_hints` from items MUST flow into the PRD's `## Implementation Hints` section with item-id back-references — no re-elicitation. (PRD FR-027)

#### Migration

- **FR-028**: On first run, if `.kiln/roadmap.md` (legacy) exists AND `.kiln/roadmap.legacy.md` does NOT, parse bullets into `kind: feature` items with `phase: unsorted`, archive the legacy file to `.kiln/roadmap.legacy.md`, and report a count + `--reclassify` instruction. Idempotent (no re-migration on re-run). (PRD FR-028)
- **FR-029**: Bootstrap with three seed critiques: "kiln uses too many tokens compared to doing it by hand", "kiln produces unauditable buggy code", "kiln requires too much setup". Each ships with a pre-filled `proof_path` text. (PRD FR-029)

#### Obsidian sync

- **FR-030**: All create/update operations on roadmap files MUST dispatch to a new `shelf:shelf-write-roadmap-note` workflow (mirroring the `shelf:shelf-write-issue-note` shape) that composes paths from `.shelf-config` and writes the `roadmap/` subtree. (PRD FR-030)
- **FR-031**: Vision updates MUST use `mcp__claude_ai_obsidian-projects__patch_file` (frontmatter-preserving). Item create uses `create_file`; item update uses `patch_file`. (PRD FR-031)

#### Spec-derived (NEW)

- **FR-032**: Spec directory MUST be `specs/structured-roadmap/` — no numeric prefix, no variants. (Pipeline canonical-paths, derived from team-lead briefing.)
- **FR-033**: `/kiln:kiln-next` MUST surface `state: in-phase` items from the active phase as candidates for "what to work on next", listed AFTER any in-flight pipeline state but BEFORE general suggestions.
- **FR-034**: `/specify` (alias `/kiln:specify`) MUST update the source item's `state: distilled → specced` when run against a PRD whose `derived_from:` references one or more `.kiln/roadmap/items/*.md` files. The transition is a one-line frontmatter update — no other changes to the item file.
- **FR-035**: The new `shelf-write-roadmap-note` workflow MUST follow the same shape as `shelf-write-issue-note`: 4 steps (`read-shelf-config` → `parse-roadmap-input` → `obsidian-write` → `finalize-result`) with the same JSON result contract (`{ source_file, obsidian_path, action, path_source, errors }`). Path composition: `<base_path>/<slug>/{vision.md | roadmap/phases/<file> | roadmap/items/<file>}`.
- **FR-036**: Cross-surface hand-off (FR-014b) MUST be E2E-testable — the test asserts the target skill was invoked with the correct argument, NOT that text instructing the user appeared.
- **FR-037**: All item / phase frontmatter writes MUST be idempotent: re-running the skill with identical inputs produces byte-identical files (NFR-determinism), so distill's NFR-003 byte-identical guarantee continues to hold.
- **FR-038**: Schema validators (`validateItemFrontmatter`, `validatePhaseFrontmatter`) are exposed as importable Bash helpers under `plugin-kiln/scripts/roadmap/` so other skills (distill, next, specify hook) can validate before consuming.
- **FR-039**: The follow-up loop (FR-018c) MUST gracefully exit on three signals: explicit "no", empty input, or non-interactive session detection. There is NO infinite loop path.
- **FR-040**: When `.shelf-config` is missing or partial AND the user has NOT explicitly opted out of Obsidian sync, the skill MUST print one warning per session ("Obsidian mirror skipped — `.shelf-config` incomplete") and continue with `.kiln/` writes only. The skill MUST NOT fail the capture.

### Key Entities

- **Vision** (`.kiln/vision.md`) — Single Markdown file with optional frontmatter; the user's narrative product vision. Mirrored to `<base_path>/<slug>/vision.md` via `patch_file`.
- **Phase** (`.kiln/roadmap/phases/<name>.md`) — Frontmatter (`name`, `status`, `order`, `started?`, `completed?`) + body (description + auto-maintained item-id list). Mirrored to `<base_path>/<slug>/roadmap/phases/<name>.md`.
- **Item** (`.kiln/roadmap/items/<YYYY-MM-DD>-<slug>.md`) — Frontmatter (`id`, `title`, `kind`, `date`, `status`, `phase`, `state`, sizing fields, optional `depends_on`, `addresses`, `implementation_hints`, optional `proof_path` for critiques) + body (rich description from interview). Mirrored to `<base_path>/<slug>/roadmap/items/<basename>`.
- **Critique** — A specialization of Item with `kind: critique`, required `proof_path`, status lifecycle `open | partially-disproved | disproved`.
- **`.shelf-config`** — KV file at repo root; canonical source of `slug`, `base_path`, `dashboard_path`. NEVER discovered.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of new product-direction ideas captured via `/kiln:kiln-roadmap` land as structured items under `.kiln/roadmap/items/`. Measured by: zero new bullets appear in `.kiln/roadmap.md` (legacy file is archived) and `.kiln/roadmap/items/` is the only destination.
- **SC-002**: Within one cycle of shipping, every `/kiln:kiln-distill` run that has at least one item in scope produces a PRD whose `derived_from:` frontmatter references ≥1 item file. Measured by `grep -l "\.kiln/roadmap/items/" docs/features/*/PRD.md`.
- **SC-003**: At least one seed critique transitions `open → partially-disproved` after a feature that references it via `addresses:` ships. Validates the end-to-end proof_path flow.
- **SC-004**: Every file in `.kiln/roadmap/` and `.kiln/vision.md` has a corresponding Obsidian note. Measured by listing both trees and diffing — zero local-only files.
- **SC-005**: Adversarial interview takes ≤90 seconds wall-clock end-to-end for a feature item (≤5 questions, each individually skippable). Measured by manual timing across 3 captures.
- **SC-006**: Schema validator rejects 100% of items containing `human_time`, `t_shirt_size`, or `effort_days`. Measured by validator unit tests.

## Assumptions

- The product owner is a solo dev interacting via Claude Code chat (no web UI).
- `.shelf-config` is the canonical mapping repo → Obsidian project; the blocker fix (issue `2026-04-23-write-issue-note-ignores-shelf-config`) makes ALL shelf helpers read it. This feature does NOT ship until that blocker is closed.
- `/kiln:kiln-distill` is the one and only consumer of roadmap items — no other skill walks the roadmap tree.
- The Obsidian vault is "nice-to-have" — `.kiln/` is the source of truth. If Obsidian is unreachable, capture still succeeds.
- All slash commands referenced (`/specify`, `/kiln:specify`, `/kiln:kiln-distill`, `/kiln:kiln-next`, `/kiln:kiln-report-issue`, `/kiln:kiln-feedback`) are existing skills; this feature MODIFIES three of them (distill, next, specify) and does NOT introduce new entrypoints beyond `/kiln:kiln-roadmap` flags and `shelf:shelf-write-roadmap-note`.

## Out of Scope (deferred)

Mirror of PRD §Non-Goals — restated for spec-clarity:

- Review-cadence / staleness nagging
- Retrospective loop (critique → `disproved` automation; the manual transition IS in v1)
- Cross-project roadmap view
- GitHub issue sync from roadmap items
- Human-time / T-shirt sizing (explicitly forbidden by FR-008)
- Automated `proof_path` measurement from telemetry
