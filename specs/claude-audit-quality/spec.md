# Feature Specification: Claude-Audit Quality — Substance Over Mechanics

**Feature Branch**: `build/claude-audit-quality-20260425`
**Created**: 2026-04-25
**Status**: Draft
**PRD**: `docs/features/2026-04-26-claude-audit-quality/PRD.md`
**Research baseline**: `specs/claude-audit-quality/research.md` §Baseline

**Input**: Raise `/kiln:kiln-claude-audit`'s output bar from mechanical (length / freshness) to substance (does the audited file teach the project's thesis, loop, architecture). Every fired signal MUST produce a concrete artifact: a unified diff, an explicit `inconclusive` with a missing-document reason, or a `keep` (load-bearing protection). Editorial rules execute in the model's own context — no sub-LLM call, no "expensive" opt-out. `## Project Context` citations become load-bearing — removing the cited signal would change the verdict. Add four substance rules (`missing-thesis`, `missing-loop`, `missing-architectural-context`, `scaffold-undertaught`) plus a `recent-changes-anti-pattern` rule and a sibling-preview file convention. Sibling Theme F: retro insight self-rating (`insight_score:` frontmatter key + minimal substance rubric).

> **PRD ↔ spec numbering**: This spec preserves the PRD's FR-001..FR-025 numbering verbatim. NFR-001..NFR-004 and SC-001..SC-008 likewise mirror the PRD 1:1.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Substance findings lead the report (Priority: P1) 🎯 MVP

As the kiln maintainer, I run `/kiln:kiln-claude-audit` against the source repo's CLAUDE.md. The audit's `## Signal Summary` and `## Notes` open with substance findings — "your CLAUDE.md doesn't teach the project's thesis" — *before* mechanical findings like "the file is 305 lines." After the substance pass come the rubric mechanical signals; after those, external best-practices deltas.

**Why this priority**: This is the headline reordering that turns the audit from a length checker into a teaching-quality checker. Without it, every other Theme is invisible to the maintainer reading top-to-bottom.

**Independent Test**: Run the audit on the kiln source repo. Assert the first row of `## Signal Summary` has `signal_type: substance`. Assert the first finding paragraph in `## Notes` cites a substance rule (`missing-thesis` / `missing-loop` / `missing-architectural-context` / `scaffold-undertaught`).

**Acceptance Scenarios**:

1. **Given** a CLAUDE.md that fires both substance and mechanical signals, **When** the audit runs, **Then** the `## Signal Summary` table sorts substance rows first, mechanical rows second, external-best-practices deltas third (and external deltas continue to render in their own `## External best-practices deltas` sub-section, not as Signal Summary rows — see NFR-004 / Open Question 3).
2. **Given** a CLAUDE.md that passes all substance rules, **When** the audit runs, **Then** the Signal Summary's first row is the highest-severity mechanical finding; the substance pass MAY emit a one-line "(no substance signals fired)" placeholder for visibility.
3. **Given** the audit ran successfully, **When** a maintainer reads `## Notes` top-to-bottom, **Then** every substance finding is rendered before any mechanical finding, regardless of action type or severity.

---

### User Story 2 — Editorial rules execute, never silently punt (Priority: P1)

As the kiln maintainer, when an editorial rule (e.g. `duplicated-in-constitution`, `stale-section`) fires its match logic, the audit MUST either produce a concrete unified diff hunk or emit `inconclusive` with a *specific* reason: "reference document `<path>` not found on disk", "reference document parse failed: `<error>`", or "external dependency unavailable: `<dep>`". The phrase "editorial work is too expensive" is forbidden as an `inconclusive` reason.

**Why this priority**: This is the contract repair. The current state ships `inconclusive` everywhere as cheap absolution; the new contract forces the model to actually do the editorial pass it claims to perform.

**Independent Test**: Author a CLAUDE.md that paraphrases an article from `.specify/memory/constitution.md`. Run the audit. Assert `duplicated-in-constitution` fires with `action: duplication-flag` (NOT `inconclusive`) and a concrete unified diff identifying the duplicated paragraph.

**Acceptance Scenarios**:

1. **Given** a CLAUDE.md with paraphrased constitution content AND `.specify/memory/constitution.md` is present on disk, **When** the audit runs, **Then** `duplicated-in-constitution` fires with `action: duplication-flag` and emits a unified diff hunk.
2. **Given** `.specify/memory/constitution.md` is missing on disk, **When** the audit runs, **Then** `duplicated-in-constitution` emits `inconclusive` with `Notes` reason "reference document `.specify/memory/constitution.md` not found on disk".
3. **Given** any editorial rule fires its match logic, **When** the audit emits `inconclusive`, **Then** the `Notes` cell MUST cite one of the three legitimate triggers (missing reference, unparseable reference, external-dep failure) — and the rubric preamble lists these triggers exhaustively.
4. **Given** an editorial rule's match logic finds drift, **When** the audit emits a finding, **Then** the `## Proposed Diff` section contains a `git apply`-shaped unified diff with `rule_id:` annotation — zero `# ... No diff proposed pending maintainer call` comment-only hunks.

---

### User Story 3 — Substance rules surface "what this file fails to teach" (Priority: P1)

As the kiln maintainer, my CLAUDE.md may pass all length/freshness rules and still fail to teach Claude what the project IS. I want four substance rules that read `.kiln/vision.md`, the roadmap-phase status, the plugin layout, and (for scaffolds) the source-repo CLAUDE.md, and fire when the audited file fails to communicate those load-bearing concepts.

**Why this priority**: This is the new substantive surface. Without these rules, the audit can never catch the highest-cost drift — a CLAUDE.md that documents mechanics but never names the thesis.

**Independent Test**: Author a CLAUDE.md that passes every mechanical rule but contains no vision-pillar reference. Run the audit. Assert `missing-thesis` fires with `signal_type: substance`, `cost: editorial`, and a primary-justification citation pointing at `vision.body` (or equivalent `CTX_JSON` path).

**Acceptance Scenarios**:

1. **Given** `.kiln/vision.md` is present and the audited file's opener / `## What This Repo Is` body contains no vision-pillar phrase, **When** the audit runs, **Then** `missing-thesis` fires with `action: expand-candidate` and a proposed diff inserting a thesis paragraph derived from vision.md.
2. **Given** `.kiln/vision.md` is present and `.kiln/roadmap/phases/<active>.md` indicates the project has shipped at least one feedback loop (`status: in-progress` or `complete`), **When** the audited file does NOT name the loop's input → consumer → output relationship, **Then** `missing-loop` fires.
3. **Given** the source repo contains >1 `plugin-*/` root, **When** the audited file's `## Architecture` section describes only one plugin, **Then** `missing-architectural-context` fires.
4. **Given** the audited file is `plugin-*/scaffold/CLAUDE.md` (a scaffold template), **When** the source-repo `CLAUDE.md` teaches load-bearing concepts (thesis, loop, architecture pointers) that the scaffold does not, **Then** `scaffold-undertaught` fires with a per-concept enumeration of what's missing.

---

### User Story 4 — Project-context citations are load-bearing (Priority: P2)

As the kiln maintainer, when an audit finding cites `.kiln/vision.md` or another `CTX_JSON` path, I want that citation to be the *primary justification* for the finding — the audit MUST include a one-line "remove-this-citation-and-verdict-changes-because" rationale. Decorative correlations ("shipped PRD count: 46") are flagged in audit-of-audit mode (out of scope here) and forbidden as primary justifications.

**Why this priority**: This is what makes Theme C teeth-bearing. Without a load-bearing-citation requirement, citations decay back into post-hoc decoration.

**Independent Test**: Author a structurally-clean CLAUDE.md that diverges from `.kiln/vision.md` content. Run the audit. Assert ≥1 substance finding emits with a `## Notes` row containing a `removing this citation would change the verdict because: <reason>` line, and the citation path resolves to a real `CTX_JSON` field.

**Acceptance Scenarios**:

1. **Given** a CLAUDE.md fires a substance finding, **When** the audit emits the finding, **Then** the `Notes` row MUST include a one-line "remove-this-citation-and-verdict-changes-because: <reason>" rationale, AND the cited path MUST resolve to a non-empty field in `CTX_JSON`.
2. **Given** an audit run produces zero project-context-driven findings (no rule whose `match_rule:` reads from `CTX_JSON` fired), **When** the audit log is rendered, **Then** the Signal Summary contains a `(no project-context signals fired)` row so the absence is visible (not silent).
3. **Given** a finding's justification cites `vision.body` and a maintainer hypothetically removes that citation, **When** they re-evaluate, **Then** the finding's verdict would flip — verifiable by a Notes-section assertion phrase per Risk R-2 mitigation.

---

### User Story 5 — `## Recent Changes` is treated as anti-pattern + sibling-preview file convention (Priority: P2)

As the kiln maintainer, the `## Recent Changes` section in CLAUDE.md exists today primarily because rules in `kiln-claude-audit` and `kiln-doctor` cite it (circular load-bearing). I want a rule `recent-changes-anti-pattern` that fires when the section is present and proposes a one-paragraph "Looking up recent changes" pointer (to `git log`, `.kiln/roadmap/phases/<active>.md`, `ls docs/features/`, `/kiln:kiln-next`). Separately, I want the sibling-preview file pattern (`-proposed-<basename>.md`) codified in the skill so I always get a side-by-side preview of the post-apply state.

**Why this priority**: P2 — both are quality-of-life improvements that compound, not on the critical path of "make the audit teach substance." Important but not MVP.

**Independent Test**: Author a CLAUDE.md containing `## Recent Changes`. Run the audit. Assert `recent-changes-anti-pattern` fires with action `removal-candidate` and a proposed diff replacing the section with the pointer paragraph. Assert a sibling preview file `<audit-log>-proposed-<basename>.md` is rendered alongside the audit log.

**Acceptance Scenarios**:

1. **Given** a CLAUDE.md contains `## Recent Changes`, **When** the audit runs, **Then** `recent-changes-anti-pattern` fires with `action: removal-candidate` and the proposed diff replaces the section with the standardized "Looking up recent changes" pointer block.
2. **Given** `recent-changes-anti-pattern` fires, **When** the audit also evaluates `recent-changes-overflow`, **Then** `recent-changes-overflow` is demoted to `keep` (the anti-pattern rule's removal proposal supersedes the overflow flag).
3. **Given** `## Recent Changes` is absent from the audited file, **When** the audit runs, **Then** `recent-changes-overflow` emits no signal (treats absence as no drift, not as missing-section coverage failure).
4. **Given** the audit produces ≥1 proposed diff for path `<P>`, **When** the audit log is written to `.kiln/logs/claude-md-audit-<TIMESTAMP>.md`, **Then** a sibling preview file at `.kiln/logs/claude-md-audit-<TIMESTAMP>-proposed-<basename>.md` is rendered (basename = path-slashes-replaced-with-`-`, e.g. `plugin-kiln-scaffold-CLAUDE.md`), containing the proposed final state of the audited file (post-apply).
5. **Given** a sibling preview file is rendered, **When** the audit log's `## Proposed Diff` header is emitted, **Then** the header is followed by a one-line cross-reference: `Side-by-side preview: see <audit-log-basename>-proposed-<basename>.md.`
6. **Given** an audit run completes, **When** the audit log footer is emitted, **Then** the footer includes the cleanup convention: `Once proposed diffs land, this audit log + sibling preview files can be archived to .kiln/logs/archive/ or deleted.`

---

### User Story 6 — Retro self-rates insight-score (Priority: P2)

As a retrospective consumer, when I read a `kiln-build-prd` retrospective issue, I want a `insight_score:` frontmatter key (1-5 with one-line justification) so I can spot low-substance retros without reading every body. Below threshold (default `3`), the team-lead surfaces the score in the pipeline summary.

**Why this priority**: P2 — sibling concern to the audit Theme; decoupled, and the cheapest version (agent self-rating) is what we ship per PRD Non-Goal "build a separate `/kiln:kiln-retro-audit` skill in this PRD".

**Independent Test**: Run a `kiln-build-prd` pipeline to completion. Assert the resulting retrospective GitHub issue body's frontmatter contains `insight_score: <integer 1-5>` and a `insight_score_justification: <one-line>` key. Assert the team-lead's pipeline summary message names the score.

**Acceptance Scenarios**:

1. **Given** a `kiln-build-prd` pipeline reaches the retrospective phase, **When** the retrospective agent emits the retro issue body, **Then** the body's YAML frontmatter contains `insight_score: <integer 1-5>` and `insight_score_justification: <one-line string>`.
2. **Given** a retrospective is written with `insight_score < 3`, **When** the team-lead emits the pipeline summary, **Then** the summary contains a "low-substance retrospective" line citing the score and its justification.
3. **Given** the retrospective agent is rating itself, **When** it consults the rubric `plugin-kiln/rubrics/retro-quality.md`, **Then** it cites the rubric verbatim in its self-rating prompt, applying the test "contains at least ONE of: (a) non-obvious cause-and-effect claim, (b) calibration update with reasoning, (c) process-change proposal".

---

## Requirements *(mandatory)*

The following functional requirements mirror the PRD verbatim (FR-001..FR-025). Numbering matches the PRD 1:1.

### Theme A: Output discipline (every fired signal produces an artifact)

- **FR-001**: `kiln-claude-audit/SKILL.md` Step 3.5 invariant — every fired signal MUST produce exactly one of: a concrete unified diff (git-apply-shaped, hunk-by-hunk, with `rule_id:` annotation), an explicit `inconclusive` row with a stated reason in Notes, or `keep` / `keep (load-bearing)` for rules that only ever emit keep. Comment-only diff hunks (e.g. `# ... No diff proposed pending maintainer call`) are forbidden.
- **FR-002**: Test fixture `plugin-kiln/tests/claude-audit-no-comment-only-hunks/` runs the audit against a CLAUDE.md known to fire the `external/length-density` rule and asserts the output contains zero `# ... No diff proposed` lines.
- **FR-003**: `kiln-claude-audit/SKILL.md` Step 3 contract — the model running the skill performs editorial evaluation in its own context. No sub-LLM call. For each editorial rule, the skill MUST load the reference document(s), read every `^## ` section, compare per `match_rule`, and emit findings or `(no fire)`. Skipping the comparison and marking `inconclusive` is forbidden unless reference documents are physically unavailable on disk.
- **FR-004**: Rubric preamble in `plugin-kiln/rubrics/claude-md-usefulness.md` documents the legitimate `inconclusive` triggers exhaustively: missing reference document, unparseable reference, failed external dependency (WebFetch / MCP). "Editorial work feels expensive" is explicitly NOT on the list.
- **FR-005**: Test fixture `plugin-kiln/tests/claude-audit-editorial-pass-required/` runs the audit against a CLAUDE.md known to contain a paraphrase of an article in `.specify/memory/constitution.md` and asserts `duplicated-in-constitution` fires (action: `duplication-flag`), NOT `inconclusive`.

### Theme B: Substance rules in the rubric

- **FR-006**: Add rule `missing-thesis` to `plugin-kiln/rubrics/claude-md-usefulness.md`. `signal_type: substance`, `cost: editorial`. Match: read `.kiln/vision.md` (when present); fire if NO vision-pillar phrase appears in the audited file's opener or `## What This Repo Is` body. Pre-filter: load all `^## ` headings + the first paragraph of vision.md as candidate phrases; only invoke the editorial pass if the cheap grep returns zero matches (Risk R-1 mitigation).
- **FR-007**: Add rule `missing-loop`. `signal_type: substance`, `cost: editorial`. Match: read vision + roadmap-phase status; if the project has shipped at least one feedback loop (any `.kiln/roadmap/phases/*.md` with `status: in-progress` or `complete`) AND the audited file does not draw the loop (input → consumer → output), fire.
- **FR-008**: Add rule `missing-architectural-context`. `signal_type: substance`, `cost: cheap`. Match: count distinct `plugin-*/` roots; if >1 and the audited file's `## Architecture` section describes only one, fire.
- **FR-009**: Add rule `scaffold-undertaught`. `signal_type: substance`, `cost: editorial`. Match: applies only to scaffold/template CLAUDE.md files (path glob `plugin-*/scaffold/CLAUDE.md`); verify the scaffold communicates the same load-bearing concepts (thesis, loop, architectural pointers) as the source repo's CLAUDE.md. On fire, action is `expand-candidate` with a per-concept enumeration of what's missing.
- **FR-010**: Substance findings rank above rubric mechanical findings in the audit log's `## Signal Summary` and `## Notes` sections. Output ordering: substance → mechanical → external best-practices.
- **FR-011**: Test fixture `plugin-kiln/tests/claude-audit-substance/` runs the audit against a CLAUDE.md that passes mechanical rules but has no vision-pillar reference and asserts `missing-thesis` fires.

### Theme C: Grounded citations + audit depth

- **FR-012**: Reword the Step 1 / FR-013 contract: every cited project-context signal in a finding's justification MUST be the *primary justification* — removing the signal would change the finding's verdict. Decorative correlations (e.g., "shipped PRD count 46 informs the length-density finding") are forbidden as primary justifications. Each finding's `Notes` row MUST include a one-line "remove-this-citation-and-verdict-changes-because: <reason>" rationale (Risk R-2 mitigation).
- **FR-013**: Replace the "audit MUST ground itself in project context" assertion with: every audit MUST contain at least one finding whose `match_rule` reads from `CTX_JSON` (vision body, roadmap items, plugin list, README, prior CLAUDE.md). If no project-context-driven finding fires, the audit MUST emit a `(no project-context signals fired)` row in the Signal Summary.
- **FR-014**: Test fixture `plugin-kiln/tests/claude-audit-grounded-finding-required/` — CLAUDE.md is structurally clean (passes all rubric rules) but diverges from `.kiln/vision.md` content. Asserts the audit emits ≥1 substance finding citing vision content as primary justification.
- **FR-015**: Reorder `kiln-claude-audit/SKILL.md` so the substance pass (FR-006..FR-011 rules) runs at Step 2, BEFORE the cheap rubric rules at Step 3. Output sections in the audit log render in this same order: substance → rubric → external.

### Theme D: Recent Changes anti-pattern + circular load-bearing

- **FR-016**: Add rule `recent-changes-anti-pattern` to `plugin-kiln/rubrics/claude-md-usefulness.md`. `signal_type: substance`, `cost: cheap`. Match: presence of `## Recent Changes` heading. Action: `removal-candidate`. Proposed diff: replace the section with a one-paragraph "## Looking up recent changes" pointer to `git log`, `.kiln/roadmap/phases/<active>.md`, `ls docs/features/`, and `/kiln:kiln-next`.
- **FR-017**: Update `kiln-claude-audit/SKILL.md` and `kiln-doctor/SKILL.md` `recent-changes-overflow` handlers: when `## Recent Changes` is absent, the rule emits no signal (treat as no drift). When `recent-changes-anti-pattern` has fired in the same audit, demote `recent-changes-overflow` to `keep`.
- **FR-018**: Reword `load-bearing-section` in the rubric: a section is load-bearing when cited from skill/agent/hook/workflow PROSE (instructions, descriptions, error messages). It is NOT load-bearing when cited only inside a rule's `match_rule:` field. Same applies to `## Active Technologies` (cited by `active-technologies-overflow`).
- **FR-019**: Test fixture `plugin-kiln/tests/claude-audit-recent-changes-anti-pattern/` runs the audit against a CLAUDE.md containing `## Recent Changes` and asserts `recent-changes-anti-pattern` fires with a removal-candidate diff.

### Theme E: Sibling preview convention

- **FR-020**: Update `kiln-claude-audit/SKILL.md` permitted-files list to include `.kiln/logs/claude-md-audit-<TIMESTAMP>-proposed-<basename>.md` (one sibling preview per audited file with non-empty proposed diffs). Naming convention: replace path slashes in basename with `-` (e.g. `plugin-kiln/scaffold/CLAUDE.md` → `-proposed-plugin-kiln-scaffold-CLAUDE.md`).
- **FR-021**: Add Step 4.5 to `kiln-claude-audit/SKILL.md`: render one sibling preview per audited path with at least one proposed diff. The preview file contains the proposed final state of the audited file (post-apply).
- **FR-022**: Audit log's `## Proposed Diff` section header gets a one-line cross-reference: `Side-by-side preview: see <audit-log-basename>-proposed-<basename>.md.`.
- **FR-023**: Audit log footer note: `Once proposed diffs land, this audit log + sibling preview files can be archived to .kiln/logs/archive/ or deleted.` (Cleanup convention; `kiln-doctor` integration deferred per item-low-severity ranking.)

### Theme F: Retro quality (cheapest version)

- **FR-024**: `kiln-build-prd` retrospective agent emits a self-rated insight score (1-5 with one-line justification) at retro write-time, recorded as YAML keys `insight_score:` and `insight_score_justification:` in the retro issue's frontmatter. Below threshold (default `3`) the team-lead surfaces the score in the pipeline summary so the user sees the gap.
- **FR-025**: Define a minimal substance rubric for retros (recorded in `plugin-kiln/rubrics/retro-quality.md`): a high-substance retro contains at least ONE of (a) a non-obvious cause-and-effect claim, (b) a calibration update with reasoning, (c) a process-change proposal. The agent's self-rating prompt cites this rubric verbatim.

### Non-Functional Requirements

- **NFR-001** — Audit completion time: substance rules MUST NOT increase total audit duration by more than 30% relative to the pre-PR baseline on the kiln source repo's CLAUDE.md.

  **Scope binding (reconciled against `research.md` §Baseline — Step 1.5)**: NFR-001 binds to the **bash-side / shell-portion** of `/kiln:kiln-claude-audit` only. The shell portion includes: `plugin-kiln/scripts/context/read-project-context.sh` invocation, rubric file load + `^### ` enumeration, best-practices cache header read, all cheap rubric rules (`load-bearing-section` citation grep — the dominant cost — `stale-migration-notice`, `recent-changes-overflow`, `active-technologies-overflow`, `hook-claim-mismatch` cheap pass), plugin enumeration + per-plugin guidance-file resolution, vision.md region detection. NFR-001 does NOT bind to editorial-LLM time (`duplicated-in-prd`, `duplicated-in-constitution`, `stale-section`, `enumeration-bloat` framing call, `benefit-missing`, `loop-incomplete`, `product-slot-missing`, FR-001 section-classification, the new substance rules' editorial passes, external-best-practices delta evaluation) — model-routed time is intrinsically not shell-measurable from a sub-agent and varies by daily routing. Editorial-time regressions are surfaced informally via Theme A's discipline gate (no silent `inconclusive` fallback) and via the substance pre-filter pattern (FR-006 R-1 mitigation), not via NFR-001.

  **Threshold (reconciled — Step 1.5)**: pre-PR median = **0.786 s** (5 sequential runs against the kiln source repo on branch `build/claude-audit-quality-20260425`, identical to `main` as of 2026-04-25; full timing table in research.md). +30% gate = post-PR median MUST be **≤ 1.022 s** measured by the same `/tmp/audit-bench.sh` script (source reproduced verbatim in research.md). Auditor (task #5) re-runs the script post-implementation; if the median crosses the gate, NFR-001 is broken.

  **Tolerance band (Open Question 1 — see below)**: the threshold is firm against the bash-side measurement. If post-implementation the bash-side median trends close to the gate (e.g. ≥ 0.95 s, > 95 % of cap), the auditor SHOULD raise an issue rather than auto-pass. The tolerance band is documented here so the auditor doesn't wrong-flag a noisy 1.05 s spike as a hard regression — five-run medians are the contract, not single-run wall-clock.

- **NFR-002**: Test fixtures (FR-002, FR-005, FR-011, FR-014, FR-019) MUST be self-contained and runnable via `/kiln:kiln-test plugin-kiln <fixture>` without external network calls.

- **NFR-003**: Re-running the audit on unchanged inputs MUST produce a byte-identical Signal Summary + Proposed Diff body (existing NFR from the original kiln-self-maintenance spec; preserved and extended to include the new substance rule outputs).

  **Scope binding + carve-out (reconciled against `research.md` §Baseline — Step 1.5)**: NFR-003 is a **within-scope idempotence gate** — two runs of the *same scope* on *unchanged inputs* MUST be byte-identical. NFR-003 is **NOT** a cross-PR or cross-scope diff gate. Specifically:

  1. **Substance rule carve-out**: This PR's new substance rules (FR-006..FR-011) and `recent-changes-anti-pattern` (FR-016) will produce DIFFERENT Signal Summary byte content vs the pre-PR baseline by definition — the rules didn't exist before, so they emit new content rows. This is expected behavior, NOT an NFR-003 violation. NFR-003 byte-identity asserts only on **the no-X paths** (i.e., when the audit is run against a CLAUDE.md that fires NO new substance rules — e.g., a CLAUDE.md that already teaches thesis + loop + architecture), in which case the post-PR audit's Signal Summary + Proposed Diff bytes MUST match the pre-PR audit's bytes for that input.

  2. **Scope distinction**: smoke-test-scope vs full-scope audit runs intentionally produce different output shapes (the smoke-scope log carries a `## Smoke-test verification` trailer and emits `inconclusive` rows for editorial passes the smoke caller deferred). NFR-003 binds to two runs *of the same scope* — comparing smoke-vs-full is out of scope.

  3. **Reference byte counts (anchor)**: per research.md §Baseline, a smoke-scope run on the kiln source repo emits `## Signal Summary` = **843 bytes / 11 lines** and `## Proposed Diff` = **2 281 bytes / 46 lines**. These anchor the *current* smoke-scope shape; post-PR full-scope numbers are a new shape and not directly comparable.

  4. **Auditor verification recipe (SC-007)**: run the new audit twice in a row against unchanged inputs (e.g. against the kiln source repo's CLAUDE.md), diff the two output files (ignoring only the `**Generated**: <ISO-timestamp>` header line), and assert zero diff in `## Signal Summary` + `## Proposed Diff`. The byte counts themselves will be NEW (full-scope post-implementation) but the within-scope byte-identity invariant holds.

- **NFR-004**: Backward compatibility — existing rubric rules (`stale-migration-notice`, `recent-changes-overflow`, `enumeration-bloat`, `hook-claim-mismatch`, etc.) continue to fire as before. New substance rules ADD to the output; they do not REPLACE existing ones.

  **External-deltas note (Open Question 3 reconciled)**: `external` is NOT a `signal_type` value in the rubric — it is a separate `## External best-practices deltas` section with its own table shape (per existing skill behavior and confirmed by researcher-baseline). FR-010's "substance → mechanical → external" output ordering refers to **section ordering** in the audit log, NOT signal_type membership. This PR does NOT introduce `external` as a true signal_type; the rubric schema is unchanged on that axis.

### Key Entities

- **Audit signal** (existing; extended): `{ rule_id, signal_type, cost, file, section, action, count, justification, notes }`. New `signal_type` value: `substance`. Rendered in the Signal Summary table; sorted per FR-010 (substance → mechanical) before diff emission. The `external` deltas remain in their own `## External best-practices deltas` section, unaffected by `signal_type` membership.
- **Substance rule** (new): rubric entry with `signal_type: substance` and one of `cost: cheap | editorial`. Reads `CTX_JSON` paths (`vision.body`, `roadmap.items`, `plugins.list`, `readme.body`, `claude_md.body`) and fires when the audited file fails a substance check. Each substance rule's `match_rule:` MUST name the `CTX_JSON` path(s) it reads.
- **Editorial pass discipline** (FR-003): the model running the skill performs editorial evaluation directly. No sub-LLM call. Reference documents (`.kiln/vision.md`, `.specify/memory/constitution.md`, `plugin-kiln/scaffold/CLAUDE.md`) are read from disk via `cat` / `awk` and passed inline to the editorial reasoning step.
- **Sibling preview file** (new): `.kiln/logs/claude-md-audit-<TIMESTAMP>-proposed-<basename>.md` — basename has path-slashes replaced with `-`. Contains the proposed final state of the audited file post-apply. One per audited path with ≥1 proposed diff. Cross-referenced from the audit log's `## Proposed Diff` header.
- **Retro insight rating** (new): YAML frontmatter keys `insight_score: <integer 1-5>` and `insight_score_justification: <one-line>` on `kiln-build-prd` retrospective issues. Self-rated by the retro agent against `plugin-kiln/rubrics/retro-quality.md`. Surfaced in the team-lead pipeline summary when below threshold (default `3`).
- **Retro substance rubric** (new): `plugin-kiln/rubrics/retro-quality.md`. Defines the self-rating test: a high-substance retro contains at least ONE of (a) non-obvious cause-and-effect claim, (b) calibration update with reasoning, (c) process-change proposal.

## Success Criteria *(mandatory)*

These mirror the PRD's SC-001..SC-008 verbatim with reconciled wording where necessary.

### Measurable Outcomes

- **SC-001**: `plugin-kiln/tests/claude-audit-no-comment-only-hunks/` passes (FR-002).
- **SC-002**: `plugin-kiln/tests/claude-audit-editorial-pass-required/` passes (FR-005).
- **SC-003**: `plugin-kiln/tests/claude-audit-substance/` passes — `missing-thesis` fires on a structurally-clean CLAUDE.md that lacks vision-pillar references (FR-011).
- **SC-004**: `plugin-kiln/tests/claude-audit-grounded-finding-required/` passes — at least one substance finding fires with primary-justification citation of `CTX_JSON` content (FR-014).
- **SC-005**: `plugin-kiln/tests/claude-audit-recent-changes-anti-pattern/` passes — `recent-changes-anti-pattern` fires with a removal-candidate diff (FR-019).
- **SC-006**: Running `/kiln:kiln-claude-audit` against the kiln source repo's CLAUDE.md emits a substance finding row in the Signal Summary that cites a vision pillar as primary justification — verified by `grep` of the audit log for `signal_type: substance` and confirming `match_rule:` references `vision.body` or equivalent `CTX_JSON` path.
- **SC-007**: Running the audit twice on unchanged inputs produces byte-identical Signal Summary + Proposed Diff bodies (NFR-003 carried forward, with the within-scope carve-out documented in NFR-003).
- **SC-008**: A `kiln-build-prd` pipeline run emits a retrospective issue whose body contains an `insight_score:` frontmatter key per FR-024.

## Assumptions

- The existing `kiln-claude-audit` skill executes editorial rules in the model's own context (no sub-LLM call infrastructure exists today, none introduced here). FR-003's "no sub-LLM call" reaffirms the existing implicit contract.
- `.kiln/vision.md` is present in the source repo (confirmed; created via `/kiln:kiln-roadmap --vision`). Substance rules that read `vision.body` therefore have non-empty input. Consumer projects without `.kiln/vision.md` get `inconclusive` rows for substance rules per the FR-004 trigger taxonomy.
- `.kiln/roadmap/phases/<phase>.md` files exist with parseable `status:` frontmatter (confirmed; current phase `10-self-optimization` has `status: in-progress`). FR-007's `missing-loop` rule reads from these.
- The `CTX_JSON` shape emitted by `plugin-kiln/scripts/context/read-project-context.sh` is stable and documented in that script's contract. New substance rules' `match_rule:` fields reference `CTX_JSON` paths by their existing names (`vision.body`, `roadmap.items`, `plugins.list`, `readme.body`, `claude_md.body`).
- The `read-project-context.sh` jq 1.7.1-apple control-character bug (noted in research.md and the prior commit `09590a9`) does NOT block this PR — the workaround is in place. If the reader is fixed during this PR's lifetime, NFR-001's bash-side median may drop slightly (free win, not a regression).
- `kiln-build-prd` retrospective agent has authority to write YAML frontmatter to its emitted GitHub issues (existing capability — no new infrastructure).
- The team-lead surfacing low-insight retros in the pipeline summary is a prompt change to the team-lead's wrap-up step, not new tool surface (FR-024 is a prompt + frontmatter change, not new code).
- Sibling preview files (Theme E) are written via the same `Write` tool path as the main audit log; no new permitted-files contract beyond the explicit FR-020 entry.
- The PRD's Non-Goal "build a separate `/kiln:kiln-retro-audit` skill in this PRD" is honored — Theme F ships only the cheapest version (agent self-rating + rubric file). Auditor escalation path (R-4) is a follow-on PR.

## Open Questions

- **OQ-1** (NFR-001 calibration — reconciled per Step 1.5): The bash-side median 0.786 s is firm; the +30 % gate is `≤ 1.022 s`. Open: should the auditor flag a "near-cap" trend (e.g. 0.95 s ≤ median ≤ 1.022 s) as a soft warning rather than an auto-pass? Recommendation: yes — auditor adds a one-line note in the audit-of-the-pipeline if the post-PR bash-side median is ≥ 95 % of cap. NOT a gate failure; a calibration signal.
- **OQ-2** (NFR-001 editorial scope — reconciled per Step 1.5): NFR-001 explicitly does NOT bind editorial-LLM time. Open: should a follow-up PRD add a separate "editorial pass tax" measurement (e.g. self-reported by the model in audit log Notes)? Out of scope here; flagged for the retrospective.
- **OQ-3** (NFR-003 cross-scope — reconciled per Step 1.5): smoke-vs-full audit runs intentionally produce different output shapes; NFR-003 is within-scope only. Open: should the SKILL drop the `## Smoke-test verification` trailer entirely (per researcher-baseline's PI proposal) so the contracted output shape is single? Out of scope here; flagged for the retrospective and as a follow-on PR.
- **OQ-4** (FR-016 active-phase reference — from PRD): `recent-changes-anti-pattern`'s proposed-diff body uses a generic `.kiln/roadmap/phases/<active-phase>.md` placeholder — preserves byte-identity across re-runs. The Notes section of the audit MAY include a one-line comment naming the current phase (e.g. `current phase: 10-self-optimization`) to ease apply-time interpretation; this comment is in Notes, not in the diff body, so byte-identity holds.
- **OQ-5** (FR-018 retroactive scope — from PRD): the load-bearing reword reinforces FR-031 of `claude-md-audit-reframe` (where `enumeration-bloat` already wins over `load-bearing-section` for `plugin-surface` sections) rather than conflicting. Add a one-line note in the rubric preamble cross-referencing FR-031.
- **OQ-6** (FR-009 scaffold-undertaught determinism — from PRD): "load-bearing concepts" is editorial — what's the deterministic set? Recommendation: enumerate three concept families in the rule body — (a) thesis (vision pillar), (b) loop (input → consumer → output), (c) architectural pointer (e.g. "scaffold deploys into consumer projects via X"). The rule fires per missing concept family; the proposed diff inserts one paragraph per missing family.
