# Feature Specification: Vision Tooling — Cheap to Update, Drift-Checked, Forward-Projecting, Measurable

**Feature Branch**: `build/vision-tooling-20260427`
**Created**: 2026-04-27
**Status**: Draft
**Input**: Distilled from PRD `docs/features/2026-04-27-vision-tooling/PRD.md` (themes A/B/C/D).
**Source roadmap items** (`derived_from:`):
- `.kiln/roadmap/items/2026-04-24-vision-alignment-check.md`
- `.kiln/roadmap/items/2026-04-24-vision-proactive-system-coaching.md`
- `.kiln/roadmap/items/2026-04-24-win-condition-scorecard.md`
- `.kiln/roadmap/items/2026-04-25-vision-simple-params-cli.md`

## Background (informational, not normative)

`.kiln/vision.md` is the load-bearing product principles file. Today it is *prose*: the file exists, the content is articulated, but the **tooling** around it has lagged. Updates require a heavyweight coached interview; nothing flags roadmap drift against the stated pillars; nothing surfaces forward-looking opportunities derived from the vision; and the eight six-month signals (a)–(h) in `.kiln/vision.md` are aspirational language rather than measured values. This feature ships four cooperating themes — Theme A (cheap update path), Theme B (drift report), Theme C (forward pass), Theme D (scorecard) — that together turn the vision file from a document into a live instrument while preserving the existing coached interview as the canonical first-run / major-edit path.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Capture a fresh principle in seconds (Priority: P1)

As the maintainer in the middle of a session, when an architectural principle surfaces (e.g. "wheel is plugin-agnostic infrastructure"), I run a single-flag invocation of `/kiln:kiln-roadmap --vision` that appends the principle to the right section of `.kiln/vision.md`, bumps `last_updated:`, and dispatches the existing shelf mirror — without going through the full coached interview.

**Why this priority**: Update friction is the most acute capture surface in this PRD: a one-line addition either becomes a multi-minute interview or — empirically (2026-04-25) — it becomes a direct file edit that bypasses guardrails. Closing this gap is the highest-leverage move because it changes a daily-frequency interaction.

**Independent Test**: Theme A ships standalone. The maintainer runs `/kiln:kiln-roadmap --vision --add-constraint "<text>"` against a fixture vision.md and verifies (a) the bullet appears verbatim under the right section, (b) frontmatter `last_updated:` bumps to today's UTC date, (c) shelf mirror dispatch fires when configured, (d) elapsed wall-clock under 3 seconds.

**Acceptance Scenarios** (verbatim from PRD):

1. **Given** a valid `.kiln/vision.md` with a known `last_updated:`, **When** the maintainer runs `/kiln:kiln-roadmap --vision --add-constraint "Test constraint — <UTC-timestamp>"`, **Then** vision.md gains the constraint as a new bullet under the Guiding constraints section, frontmatter `last_updated:` is bumped to today's `date -u +%Y-%m-%d`, the constraint text appears verbatim, and total elapsed time from invocation to file-on-disk is under 3 seconds. *(SC-001)*
2. **Given** the maintainer mistakenly passes two simple-params flags, **When** they run `/kiln:kiln-roadmap --vision --add-constraint "x" --add-non-goal "y"`, **Then** the skill exits non-zero with a clear flag-conflict error BEFORE touching `vision.md`; `git diff .kiln/vision.md` returns empty after the failed invocation. *(SC-002)*
3. **Given** `.shelf-config` is absent or incomplete, **When** the maintainer runs any simple-params flag, **Then** the skill emits ONE warning matching the existing `kiln-roadmap` warning shape and continues — it does NOT fail; the vision write still completes. *(FR-004)*
4. **Given** the maintainer runs `/kiln:kiln-roadmap --vision` with NO new flags, **When** the coached interview executes, **Then** the stdout transcript and the resulting `vision.md` mutation are byte-identical to the pre-PRD coached interview (captured baseline fixture). *(SC-009 / NFR-005)*

---

### User Story 2 — See where the queue drifts off-thesis (Priority: P2)

As the maintainer monthly, I run a single command and see which queued roadmap items don't ladder up to any vision pillar so I can review the drifter list and decide which to demote or close.

**Why this priority**: Drift detection is read-only and inherits from existing roadmap-walking infrastructure. It has no destructive side-effects, ships independently of Themes A/C/D, and addresses a slow-cycle problem (queue creep) that surfaces only after months of capture — important but not daily-friction.

**Independent Test**: Run `/kiln:kiln-roadmap --check-vision-alignment` against the current repo's open items. Verify the report has three sections in order with the inference caveat header, `git diff` is empty after the run, and items with no plausible pillar appear in Drifters.

**Acceptance Scenarios** (verbatim from PRD):

1. **Given** a repo with a populated `.kiln/roadmap/items/`, **When** the maintainer runs `/kiln:kiln-roadmap --check-vision-alignment`, **Then** the emitted report contains the inference-caveat header verbatim, three sections in order (Aligned, Multi-aligned, Drifters), and zero file mutations (`git diff` empty post-run). *(SC-003)*
2. **Given** an item whose title and body match no vision pillar, **When** the alignment check runs, **Then** that item appears under Drifters and is NOT mutated, NOT moved, and NOT auto-promoted. *(FR-009)*
3. **Given** an item whose body could plausibly map to two pillars, **When** the alignment check runs, **Then** the item appears under Multi-aligned items (≥2 pillars). *(FR-008b)*
4. **Given** the maintainer reads the report, **When** they look for items with `status: shipped` or `state: shipped`, **Then** those items are excluded from the walk entirely (no row in any section). *(FR-006)*

---

### User Story 3 — Get forward-looking suggestions after a coached vision update (Priority: P2)

As the maintainer after a coached `/kiln:kiln-roadmap --vision` interview, I see an opt-in prompt offering forward-looking suggestions; if I accept, I get up to five evidence-cited candidates tagged as gap / opportunity / adjacency / non-goal-revisit. I accept some, decline others (which persist so they don't re-surface), and skip the rest.

**Why this priority**: P2 because forward-pass quality is unproven on first runs (R-2 risk in PRD). The opt-in default-N prompt is low-cost; the suggestion engine is LLM-mediated and benefits from running after Theme A/B are already trusted. Ships after Theme A but before/independent of Theme D.

**Independent Test**: Trigger a coached `--vision` run on a fixture, accept the opt-in, verify ≤5 suggestions emit with required tags + evidence cites, decline one, re-run, verify the declined suggestion does not re-emit. Also verify the simple-params path does NOT emit the prompt.

**Acceptance Scenarios** (verbatim from PRD):

1. **Given** a coached `/kiln:kiln-roadmap --vision` run that completes the heavyweight interview, **When** the interview accepts the reconciled vision, **Then** the skill emits the literal prompt `Want me to suggest where the system could go next? [y/N]`. Replying `n` (or default empty) exits normally without writing any `.kiln/roadmap/items/*-considered-and-declined.md` file. *(SC-004)*
2. **Given** SC-004 was answered `y`, **When** the forward pass runs, **Then** the skill emits ≤5 suggestions, each tagged with exactly one of `{gap, opportunity, adjacency, non-goal-revisit}` and each citing concrete evidence (a file path, item path, phase path, CLAUDE.md path, or commit hash). For each suggestion, an `accept` decision invokes the existing `/kiln:kiln-roadmap --promote` hand-off, `decline` writes a `kind: non-goal` declined-record file, and `skip` writes nothing. *(SC-005)*
3. **Given** a prior forward pass that declined a specific suggestion, **When** a second forward-pass run executes with no intervening repo state changes, **Then** the same suggestion (matched by title + tag) is NOT re-emitted. *(SC-006)*
4. **Given** the maintainer runs `/kiln:kiln-roadmap --vision --add-constraint "x"` (simple-params path), **When** the simple-params flow completes, **Then** stdout grep for the forward-pass prompt string returns zero matches — the prompt MUST NOT emit on simple-params invocations. *(SC-010)*

---

### User Story 4 — Get a falsifiable scorecard against the eight six-month signals (Priority: P3)

As the maintainer quarterly, I run `/kiln:kiln-metrics` and get an eight-row scorecard against this repo's vision signals (a)–(h), with a per-row status (on-track / at-risk / unmeasurable) and a file-or-commit citation for every verdict, written to both stdout and a timestamped log.

**Why this priority**: P3 because the scorecard is a quarterly cadence, ships against this repo's specific signals only (NFR-002), and depends on per-signal extractor heuristics that may need tuning after first use. High value (turns prose into instrument) but lowest immediate friction.

**Independent Test**: Run `/kiln:kiln-metrics` on this repo. Verify the report has eight rows (one per signal a–h) in the prescribed columns, each carrying one of {on-track, at-risk, unmeasurable}, with the report written to both stdout AND `.kiln/logs/metrics-<YYYY-MM-DD-HHMMSS>.md`. Force one extractor to fail (e.g., move a data source) and verify the skill exits 0 with that row carrying `unmeasurable` + a reason.

**Acceptance Scenarios** (verbatim from PRD):

1. **Given** a healthy repo with all data sources present, **When** the maintainer runs `/kiln:kiln-metrics`, **Then** the report contains exactly 8 rows (one per signal a–h) in the prescribed column shape, each carrying `on-track`, `at-risk`, or `unmeasurable`, written to BOTH stdout AND `.kiln/logs/metrics-<YYYY-MM-DD-HHMMSS>.md`. *(SC-007)*
2. **Given** at least one signal extractor cannot return a value (e.g., the data source is missing), **When** the maintainer runs `/kiln:kiln-metrics`, **Then** the skill exits 0 (NOT non-zero), the report still emits with 8 rows, and the affected row carries `status: unmeasurable` with a reason in the `evidence` column. *(SC-008)*
3. **Given** a previous run wrote a log at `.kiln/logs/metrics-<T1>.md`, **When** the maintainer runs the skill again at time T2 > T1, **Then** a new log file at `.kiln/logs/metrics-<T2>.md` is written without overwriting the previous one. *(FR-019)*
4. **Given** a maintainer wants to add a ninth signal in V2, **When** they inspect the extractor surface, **Then** each existing extractor lives at `plugin-kiln/scripts/metrics/extract-signal-<a..h>.sh` as a separate script; adding a new extractor requires only a new script + an orchestrator entry, not a skill rewrite. *(FR-018)*

---

### Edge Cases

- **Concurrent simple-params writes**: Two simultaneous `/kiln:kiln-roadmap --vision --add-*` invocations MUST NOT corrupt `vision.md`. The `.kiln/.vision.lock` file-level lock (NFR-003, mirroring `.shelf-config.lock`) serializes writers; second invocation either waits or fails cleanly with a clear "vision write in progress" message.
- **Crash mid-write**: A simple-params write that crashes between temp-file creation and `mv` MUST leave `vision.md` byte-identical to its pre-invocation state. Temp file may remain and is cleaned by the next successful invocation or manual rm.
- **Empty roadmap items dir for Theme B**: `--check-vision-alignment` against a repo with zero open items emits a report with the caveat header + three section headers + each section reading "(none)". No error.
- **Vision pillar set is empty**: If `.kiln/vision.md` has no parseable pillars, Theme B emits a header-level warning and treats EVERY open item as a Drifter. No mutation.
- **Forward-pass on a vision file with no `.kiln/roadmap/items/`**: Forward pass MAY still run; the lack of prior items is acceptable input. Suggestions should still be evidence-cited from PRDs/CLAUDE.md/phases as available.
- **Decline-record collision**: Two declined suggestions with identical slugs MUST not silently overwrite each other. Filename suffix (e.g., `-2`) or full-title hash disambiguates.
- **Scorecard run with `.kiln/logs/` missing**: Skill creates the directory before write; does not fail.
- **Extractor script missing**: If `extract-signal-<x>.sh` is missing for any signal x in (a)–(h), the orchestrator emits `unmeasurable` with `evidence: extractor missing` for that row and continues — same graceful-degrade discipline as data-source-missing.
- **Section-flag mismatch**: A simple-params flag whose target section does not exist in the current `vision.md` template (e.g., section was renamed) MUST exit non-zero with a clear "section <name> not found in vision.md" error before any write.

## Requirements *(mandatory)*

### Functional Requirements

#### Theme A — Simple-params CLI

- **FR-001**: `/kiln:kiln-roadmap --vision` MUST accept section-targeted append flags as alternatives to the coached interview: `--add-constraint <text>`, `--add-non-goal <text>`, `--add-success-signal <text>`, `--add-mission <text>`, `--add-out-of-scope <text>`. Each appends a new bullet to the named section atomically (temp + mv). When ANY of these flags is present, the heavyweight interview is SKIPPED. *(PRD FR-001)*
- **FR-002**: `/kiln:kiln-roadmap --vision` MUST also accept section-targeted REPLACE flags: `--update-what-we-are-building <text>`, `--update-what-it-is-not <text>`. Replace forms substitute the entire section body with the provided text using the same atomic write semantics. *(PRD FR-002)*
- **FR-003**: Every simple-params invocation MUST bump `last_updated:` in the vision frontmatter to `date -u +%Y-%m-%d` BEFORE the atomic write. The `last_updated:` bump is non-negotiable — it is the canonical signal drift detectors use to flag stale vision content. *(PRD FR-003)*
- **FR-004**: When `.shelf-config` is configured (per existing `--vision` mirror dispatch logic), simple-params MUST dispatch the shelf mirror update on success, byte-identical to what the coached interview emits. When `.shelf-config` is missing or incomplete, simple-params MUST emit ONE warning (matching the existing `kiln-roadmap` warning shape) and continue — it MUST NOT fail. *(PRD FR-004)*
- **FR-005**: Simple-params flags MUST be mutually exclusive with the coached interview AND with each other in a single invocation. Multiple `--add-*` or `--update-*` flags on the same call MUST be REJECTED with a clear error. The validator MUST run BEFORE the file is touched — partial writes on flag-conflict are forbidden. *(PRD FR-005)*

#### Theme B — Vision-alignment check

- **FR-006**: `/kiln:kiln-roadmap --check-vision-alignment` MUST be a new mode that walks every `.kiln/roadmap/items/*.md` with `status != shipped` AND `state != shipped`, semantically maps each to one or more vision pillars from `.kiln/vision.md`, and emits an alignment report. *(PRD FR-006)*
- **FR-007**: The mapping mechanism MUST be inferred (LLM-driven semantic match — item title + body → vision pillar). NO `addresses_pillar:` frontmatter schema change in V1. The report MUST include a header note declaring the determinism caveat verbatim: `Mappings are LLM-inferred; re-runs on unchanged inputs may differ. For deterministic mapping, declare addresses_pillar: explicitly per item (V2 schema extension).` *(PRD FR-007)*
- **FR-008**: The report MUST contain THREE sections in this order: (a) **Aligned items** — `<item-id>` → `<pillar>` (one line per item, sorted by item-id ASC); (b) **Multi-aligned items** — items mapping to ≥2 pillars; (c) **Drifters** — items mapping to ZERO pillars. *(PRD FR-008)*
- **FR-009**: The check MUST be REPORT-ONLY. Drifters MUST NOT be mutated, MUST NOT be moved, and MUST NOT be auto-promoted to `unsorted`. Promotion-blocking and auto-relocation are explicit V2 non-goals. *(PRD FR-009)*

#### Theme C — Forward-looking proactive coaching

- **FR-010**: At the END of every coached `/kiln:kiln-roadmap --vision` interview run (i.e., when the heavyweight interview accepts the reconciled vision), the skill MUST emit the single opt-in prompt `Want me to suggest where the system could go next? [y/N]`. The default is `N` (no forward pass). When the user types `y`, the forward-looking pass runs; otherwise the skill exits normally. *(PRD FR-010)*
- **FR-011**: The forward-looking pass MUST generate ≤5 suggestions, each tagged as exactly one of: `gap` (vision mentions X, no roadmap-item describes how we'd get there), `opportunity` (pattern in recent PRDs/critiques suggests an emergent direction), `adjacency` (candidate capability extending current surface area), `non-goal-revisit` (existing `kind: non-goal` items worth re-examining now that context has changed). Each suggestion MUST cite concrete evidence from PRDs, items, phases, or CLAUDE.md (file path or commit hash). *(PRD FR-011)*
- **FR-012**: For each suggestion, the user MUST be offered three actions in a per-suggestion confirm-never-silent prompt: `accept` (capture as a roadmap item via the existing `/kiln:kiln-roadmap --promote` hand-off), `decline` (write to `.kiln/roadmap/items/<date>-<slug>-considered-and-declined.md` with `kind: non-goal` so future passes do not re-propose), `skip` (no record; may re-surface next pass). *(PRD FR-012)*
- **FR-013**: Declined suggestions MUST persist on disk so the next forward pass deduplicates against them. Dedup key MUST be `suggestion title + tag`. Persistence file MUST be `.kiln/roadmap/items/<date>-<slug>-considered-and-declined.md` per declined entry. *(PRD FR-013)*
- **FR-014**: Forward-pass invocations MUST be tied to coached `--vision` runs ONLY. They MUST NOT fire on simple-params invocations (Theme A). *(PRD FR-014)*

#### Theme D — Win-condition scorecard

- **FR-015**: A new skill `/kiln:kiln-metrics` MUST walk repo state (git log, `.kiln/`, `.wheel/history/`, `docs/features/`) and produce a scorecard against the eight six-month signals (a)–(h) in this repo's `.kiln/vision.md`. *(PRD FR-015)*
- **FR-016**: The scorecard MUST emit a tabular report with columns: `signal | current_value | target | status (on-track / at-risk / unmeasurable) | evidence (file/path/commit cite)`. One row per signal; eight rows in V1. *(PRD FR-016)*
- **FR-017**: The skill MUST degrade gracefully when a signal cannot be measured — emit `status: unmeasurable` with `evidence: <reason>` instead of failing. The report MUST still emit with eight rows; some MAY carry the unmeasurable verdict. *(PRD FR-017)*
- **FR-018**: Each signal extractor MUST be a separate shell script inside `plugin-kiln/scripts/metrics/` named `extract-signal-<a..h>.sh`. The orchestrator (`/kiln:kiln-metrics`) calls each extractor and aggregates. Adding/swapping signals MUST be possible via per-extractor PRs without a skill rewrite. *(PRD FR-018)*
- **FR-019**: The scorecard report MUST be written to BOTH `.kiln/logs/metrics-<YYYY-MM-DD-HHMMSS>.md` and stdout. The log file is the audit trail; stdout is the user-facing surface. *(PRD FR-019)*

#### Cross-cutting

- **FR-020** (PRD FR-020 grep-verification of rename/rebrand) — N/A: this feature introduces no rename/rebrand. (Listed for template-completeness; intentionally vacuous.)
- **FR-021** (Section-flag mapping table — anchors OQ-1): The skill MUST anchor on a section-flag mapping table that lists every supported `--add-*` and `--update-*` flag against its target section in the canonical `.kiln/vision.md` template. Adding a new section to the template requires extending this table; the maintenance contract MUST be documented in the skill's `SKILL.md`.
- **FR-022** (Decline-record naming and location — resolves OQ-2): Declined-suggestion files MUST be written to `.kiln/roadmap/items/declined/<date>-<slug>-considered-and-declined.md` (subdirectory). Rationale: separates negative records from the main item list and matches the cleaner-scan option flagged in OQ-2.

### Non-Functional Requirements

- **NFR-001** (Determinism boundaries): Theme A (simple-params), Theme B's report shape (sections + sort order + caveat header), and Theme D's extractors MUST be deterministic — same inputs produce byte-identical output. Theme B's *mappings* and Theme C's *suggestions* are explicitly LLM-inferred (NOT deterministic), and the report headers MUST surface that caveat verbatim. *(PRD NFR-001)*
- **NFR-002** (Internal-first): Theme D ships against THIS repo's eight signals only. The extractor surface (`plugin-kiln/scripts/metrics/extract-signal-<x>.sh`) MUST be structured so a V2 generalization (consumer-configurable rubric) is additive — no rewrite required. Consumer use of `/kiln:kiln-metrics` in V1 is undefined and unsupported. *(PRD NFR-002)*
- **NFR-003** (Atomic writes): Every vision-mutating operation (Theme A's `--add-*` and `--update-*`) MUST use temp + mv atomic write. Partial writes are forbidden. Concurrent invocations MUST NOT corrupt the file — file-level lock at `.kiln/.vision.lock`, same pattern as `.shelf-config.lock`. *(PRD NFR-003)*
- **NFR-004** (Coverage gate): Constitution Article II — ≥80% line and branch coverage on new code. Where shell-only fixtures (run.sh-only) are the substrate, count assertion blocks and cite per-extractor PASS counts (per-test-substrate-hierarchy convention from PR #189). *(PRD NFR-004)*
- **NFR-005** (Back-compat for `/kiln:kiln-roadmap --vision`): The existing coached interview behavior MUST be byte-identical when invoked WITHOUT any new simple-params or `--check-vision-alignment` flag. Theme A's flags are additive; their absence MUST preserve the pre-PRD path. The byte-identity assertion MUST be backed by a captured pre-PRD fixture (per R-4 mitigation). *(PRD NFR-005)*

### Key Entities

- **Vision file (`.kiln/vision.md`)**: The mutable target. Has a YAML frontmatter (`last_updated:`) and named sections corresponding to Theme A's flag set: *What we are building*, *What it is not*, *How we'll know we're winning* (the "success signals" section, contains the eight (a)–(h) signals), *Guiding constraints*. The section-flag mapping (FR-021) is the canonical relationship.
- **Roadmap item (`.kiln/roadmap/items/<slug>.md`)**: Existing structured-roadmap artifact with `status`, `state`, `kind` frontmatter. Theme B walks these (`status != shipped` AND `state != shipped`); Theme C writes new ones (kind: non-goal) on decline.
- **Vision pillar**: A guiding constraint or commitment articulated in `.kiln/vision.md`. The pillar set is the union of bullets under *Guiding constraints* (and the prose under *What we are building* / *What it is not* where it identifies a constraint). Theme B's mapping target.
- **Forward-pass suggestion**: An ephemeral entity with fields `{title, tag ∈ {gap, opportunity, adjacency, non-goal-revisit}, body, evidence_cite}`. Persisted only on `decline` (as a roadmap item under `.kiln/roadmap/items/declined/`).
- **Scorecard row**: One row per signal with fields `{signal_id ∈ a..h, signal_label, current_value, target, status ∈ {on-track, at-risk, unmeasurable}, evidence}`. Aggregated by the orchestrator.
- **Signal extractor**: A shell script at `plugin-kiln/scripts/metrics/extract-signal-<x>.sh`. Inputs: repo root. Outputs: a structured row line on stdout (or `unmeasurable` + reason).

## Success Criteria *(mandatory)*

### Measurable Outcomes (verbatim from PRD)

- **SC-001** (Theme A live-fire): After shipping, the maintainer runs `/kiln:kiln-roadmap --vision --add-constraint "Test constraint — <UTC-timestamp>"` and verifies (a) `vision.md` gains the constraint as a new bullet under the right section, (b) frontmatter `last_updated:` is bumped to today, (c) the constraint text appears verbatim, (d) total elapsed time from invocation to file-on-disk < 3 seconds.
- **SC-002** (Theme A flag-conflict refusal): `/kiln:kiln-roadmap --vision --add-constraint "x" --add-non-goal "y"` MUST exit non-zero with a clear error before touching `vision.md`. Verified by `git diff .kiln/vision.md` returning empty after the failed invocation.
- **SC-003** (Theme B report shape): Running `/kiln:kiln-roadmap --check-vision-alignment` against the current repo's open items emits a report with the three required sections in order (Aligned, Multi-aligned, Drifters), the inference-caveat header verbatim, and zero file mutations (verified by `git diff` empty post-run).
- **SC-004** (Theme C opt-in path): A coached `/kiln:kiln-roadmap --vision` run that completes the heavyweight interview MUST end with the literal prompt `Want me to suggest where the system could go next? [y/N]`. Replying `n` (or default empty) MUST exit normally without writing `.kiln/roadmap/items/declined/*-considered-and-declined.md`.
- **SC-005** (Theme C forward-pass shape): Replying `y` to SC-004 emits ≤5 suggestions, each tagged with one of {gap, opportunity, adjacency, non-goal-revisit} and each citing concrete evidence (file path or commit hash). Per-suggestion accept/decline/skip decisions are honored: `accept` invokes the existing `/kiln:kiln-roadmap --promote` hand-off, `decline` writes a `kind: non-goal` declined-record file, `skip` writes nothing.
- **SC-006** (Theme C dedup): A second forward-pass run after declining a suggestion MUST NOT re-emit the same suggestion (matched by title + tag). Verified by running the forward pass twice in a row with no intervening repo state changes.
- **SC-007** (Theme D scorecard shape): `/kiln:kiln-metrics` emits a report with 8 rows (one per signal a–h) in the prescribed column shape. Each row carries either `on-track`, `at-risk`, or `unmeasurable`. The report is written to both stdout AND `.kiln/logs/metrics-<timestamp>.md`.
- **SC-008** (Theme D graceful degrade): If at least one signal extractor cannot return a value (e.g., the data source is missing), the skill exits 0 (NOT non-zero), the report still emits with 8 rows, and the affected row carries `status: unmeasurable` with a reason in the `evidence` column.
- **SC-009** (cross-cutting back-compat): A regression test asserts that `/kiln:kiln-roadmap --vision` invoked WITHOUT new flags produces byte-identical output (stdout + `vision.md` mutations) to the pre-PRD coached interview. Captured via fixture: pre-PRD recording vs post-PRD invocation against the same fixture vision.md.
- **SC-010** (forward-pass tied to coached only): `/kiln:kiln-roadmap --vision --add-constraint "x"` (simple-params path) MUST NOT emit the forward-pass prompt. Verified by stdout grep returning zero matches for the prompt string after a simple-params invocation.

## Assumptions

- The pre-PRD fixture for NFR-005 / SC-009 will be captured from the current `kiln-roadmap` SKILL.md BEFORE any code edits land — this is a Phase-1 task per R-4 mitigation.
- The canonical section labels in `.kiln/vision.md` are stable for the duration of this PRD: *What we are building*, *What it is not*, *How we'll know we're winning* (containing six-month signals (a)–(h)), *Guiding constraints*. The flag-to-section mapping table (FR-021) is the single source of truth for any divergence.
- The `--success-signal` flag (FR-001) appends to the *How we'll know we're winning* section (i.e., adds new bullets — typically labeled (i), (j), … — alongside the existing eight). This does not let a maintainer mutate `(a)`–`(h)` in place; in-place edit of an existing signal must use the coached interview.
- "Vision pillar" for Theme B mapping purposes = each bullet under *Guiding constraints* and each constraint articulated in *What it is not*. The eight six-month signals are NOT pillars (they are outcome targets).
- LLM-mediated steps (Theme B mappings, Theme C suggestions) reuse the same Claude-CLI substrate that PR #157's coach-driven-capture established; no new model or auth surface is introduced.
- `.shelf-config` warning shape and the `kiln-roadmap --vision` mirror dispatch path are unchanged — Theme A reuses them as-is.
- The `/kiln:kiln-roadmap --promote` hand-off contract is stable; Theme C's `accept` flow consumes it without modification.
- `.kiln/logs/` is created if missing during Theme D's first run; the skill MUST NOT fail because the log directory does not yet exist.
- Eight signals (a)–(h) are defined verbatim in this repo's current `.kiln/vision.md` (lines 25–32). The extractor surface is sized to that count; growing past eight is a V2 additive change (FR-018).
- `addresses_pillar:` frontmatter is explicitly OUT of scope (Non-Goal). All Theme B mappings are LLM-inferred for V1.

## Dependencies

- PR #157 (coach-driven-capture-ergonomics): MERGED. Theme B and Theme C consume `read-project-context.sh` as their grounding source.
- PR #180 (CLAUDE.md audit reframe): MERGED. Theme A's `last_updated:` bump triggers the existing CLAUDE.md mirror dispatch path.
- Structured-roadmap substrate (`plugin-kiln/scripts/roadmap/`): Theme C's `decline` write reuses item-frontmatter conventions; Theme B walks the existing items dir.

No blocking dependencies remain.
