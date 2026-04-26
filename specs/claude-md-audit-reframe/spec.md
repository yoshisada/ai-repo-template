# Feature Specification: CLAUDE.md Audit Reframe — Product-Focused Content + Plugin Guidance Sync

**Feature Branch**: `build/claude-md-audit-reframe-20260425`
**Created**: 2026-04-25
**Status**: Draft
**PRD**: `docs/features/2026-04-24-claude-md-audit-reframe/PRD.md`

**Input**: CLAUDE.md Audit Reframe — content-classification rubric + plugin-guidance sync + vision.md sync. Reframe `/kiln:kiln-claude-audit` so CLAUDE.md is graded on **product + feedback-loop narrative + convention rationale**, not on enumerations of plugin surface that Claude already receives at runtime. Add a `.claude-plugin/claude-guidance.md` convention so each plugin self-describes its when/why; the audit reconciles these into a managed `## Plugins` section in CLAUDE.md. Add a `vision.md`-sourced managed `## Product` section. Preserve all seven existing rubric rules; layer new rules additively.

> **PRD numbering note**: PRD jumps from FR-019 to FR-022. FR-020 and FR-021 are missing from the PRD source. This spec preserves the PRD's FR numbering verbatim (we do NOT renumber to fill the gap) so cross-references between PRD ↔ spec ↔ tasks ↔ code stay 1:1.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Plugin guidance auto-syncs into CLAUDE.md (Priority: P1) 🎯 MVP

A user has a repo with kiln, shelf, and wheel enabled. They run `/kiln:kiln-claude-audit`. The audit reads each enabled plugin's `.claude-plugin/claude-guidance.md`, builds an authoritative `## Plugins` section, diffs it against CLAUDE.md, and proposes the diff. No manual maintenance of plugin descriptions in CLAUDE.md.

**Why this priority**: This is the most concrete, demoable behavior change. It removes the largest source of CLAUDE.md drift today (hand-rolled plugin sections) and is a pre-req for the harder editorial reframe rules.

**Independent Test**: Wire 3+ first-party plugins with `claude-guidance.md` files. Run the audit on a CLAUDE.md without `## Plugins`. Verify the proposed diff inserts a deterministic, alphabetically-ordered `## Plugins` section containing each enabled plugin's guidance text with `## When to use` demoted to `#### When to use`. Re-run; verify zero new signals (idempotent).

**Acceptance Scenarios**:

1. **Given** a repo with kiln + shelf enabled and a CLAUDE.md without a `## Plugins` section, **When** the audit runs, **Then** the proposed diff inserts a `## Plugins` section with one `### kiln` and one `### shelf` subsection in that alphabetical order, each containing the plugin's guidance text with header demotion applied.
2. **Given** a repo where `## Plugins` already lists `kiln`, `shelf`, `trim` but `trim` was just disabled, **When** the audit runs, **Then** the proposed diff removes the `### trim` subsection only, leaving `### kiln` and `### shelf` untouched.
3. **Given** a repo where `## Plugins` matches the built section byte-for-byte, **When** the audit runs, **Then** no diff is proposed for that section and the Notes section confirms the section is in sync.
4. **Given** a plugin enabled but missing `.claude-plugin/claude-guidance.md`, **When** the audit runs, **Then** that plugin is silently skipped — neither flagged nor added to `## Plugins`.

---

### User Story 2 — vision.md → `## Product` sync surfaces the product narrative (Priority: P1)

A user has a `.kiln/vision.md` (created via `/kiln:kiln-roadmap --vision`). They run `/kiln:kiln-claude-audit`. The audit reads vision.md (or its delimited region), demotes its top-level heading, and proposes a synced `## Product` section in CLAUDE.md. If `vision.md` is missing AND CLAUDE.md has no `## Product` section, the audit fires `product-undefined` at the top of the Signal Summary with a high-signal coverage gap.

**Why this priority**: Same machine-managed sync mechanic as `## Plugins`, applied to the strategic narrative. Without this, CLAUDE.md never explains *what the product IS* — only how to operate the build pipeline.

**Independent Test**: Provide a 30-line `.kiln/vision.md`. Run the audit on a CLAUDE.md without `## Product`. Verify the proposed diff inserts `## Product` with vision content (demoted headings). Then update vision.md and re-run; verify the proposed diff replaces the section. Then delete vision.md; verify `product-undefined` fires.

**Acceptance Scenarios**:

1. **Given** `.kiln/vision.md` exists with ≤40 lines and `## Product` is absent from CLAUDE.md, **When** the audit runs, **Then** the proposed diff inserts `## Product` containing the entire vision.md body with `#` demoted to `## Product` and `##` headings demoted to `###`.
2. **Given** `.kiln/vision.md` contains `<!-- claude-md-sync:start -->` ... `<!-- claude-md-sync:end -->` markers, **When** the audit runs, **Then** only the fenced region is mirrored to `## Product`; content outside the markers is ignored.
3. **Given** neither `.kiln/vision.md` nor a `## Product` section exists in CLAUDE.md, **When** the audit runs, **Then** rule `product-undefined` fires at the top of the Signal Summary with action `expand-candidate`, and the proposed diff includes both a vision.md scaffold and a `## Product` placeholder section.
4. **Given** `.kiln/claude-md-audit.config` contains `product_sync = false  # reason: this repo has no product aspirations doc`, **When** the audit runs, **Then** no `product-*` rules fire and `## Product` (if present in CLAUDE.md) is classified like any other section under FR-001.

---

### User Story 3 — Enumeration bloat is flagged, narrative is preserved (Priority: P1)

A user's CLAUDE.md has a `## Available Commands` section listing every kiln skill. They run `/kiln:kiln-claude-audit`. The audit classifies that section as `plugin-surface` and fires `enumeration-bloat` with a removal-candidate diff. A separate section `## Mandatory Workflow` is classified as `convention-rationale` and is left alone (or expanded if missing a `Why:` line).

**Why this priority**: The whole reframe is meaningless without enforcement on the dominant drift class. Enumeration sections are the largest token waste in current CLAUDE.md files.

**Independent Test**: Author a CLAUDE.md containing one enumeration section (skill list), one `convention-rationale` section with rationale, one without rationale, and one `preference` section. Run the audit. Assert: enumeration → flagged, rationale → kept, missing-rationale → flagged `benefit-missing` with `expand-candidate`, preference → kept.

**Acceptance Scenarios**:

1. **Given** a CLAUDE.md `## Available Commands` section listing skills, **When** the audit runs, **Then** rule `enumeration-bloat` fires with action `removal-candidate` and rationale "Claude receives available skills / agents / commands via runtime context."
2. **Given** a CLAUDE.md section classified as `convention-rationale` containing the word "because" or "Why:", **When** the audit runs, **Then** `benefit-missing` does not fire for that section.
3. **Given** a CLAUDE.md section classified as `convention-rationale` but containing no rationale phrasing, **When** the audit runs, **Then** `benefit-missing` fires with action `expand-candidate` and the proposed diff inserts a placeholder `Why:` line.
4. **Given** `.kiln/claude-md-audit.config` contains `exclude_section_from_classification = ^## Available Commands$  # reason: I prefer this enumeration`, **When** the audit runs, **Then** that section is classified as `preference` and `enumeration-bloat` does not fire.

---

### User Story 4 — Hook/claim consistency catches stale assertions (Priority: P2)

CLAUDE.md says "the version-increment hook bumps the 4th segment on every edit." A refactor removed that hook. The user runs `/kiln:kiln-claude-audit`. The audit greps the hook scripts, finds no enforcement, and fires `hook-claim-mismatch` with action `correction-candidate`.

**Why this priority**: Wrong claims are worse than missing content — they actively mislead Claude. But the rule is grep-based and false-positive-prone, so it's P2 not P1.

**Independent Test**: Author a CLAUDE.md with two hook claims — one matched by grep against `plugin-*/hooks/*.sh`, one orphaned. Run the audit. Assert exactly one `hook-claim-mismatch` signal for the orphan.

**Acceptance Scenarios**:

1. **Given** CLAUDE.md asserts "hooks block X" and grep across `plugin-*/hooks/*.sh` for keywords from X returns ≥1 hit, **When** the audit runs, **Then** `hook-claim-mismatch` does not fire.
2. **Given** CLAUDE.md asserts "the foo-hook bumps Y" and grep across `plugin-*/hooks/*.sh` for "foo-hook" or related keywords returns 0 hits, **When** the audit runs, **Then** `hook-claim-mismatch` fires with action `correction-candidate` and Notes the claim text + the hook directory searched.

---

### User Story 5 — Feedback-loop narrative gap is surfaced (Priority: P2)

The repo has `.kiln/issues/`, `.kiln/feedback/`, `.kiln/roadmap/`, and `.kiln/mistakes/` directories with content. CLAUDE.md describes `/kiln:kiln-report-issue` but never explains how captured items become PRDs via `/kiln:kiln-distill`. The audit fires `loop-incomplete` with a proposed diff that inserts the linkage paragraph.

**Why this priority**: The feedback loop is the load-bearing narrative — without it, Claude treats capture surfaces as isolated tools. But it's editorial and only matters once the simpler bloat rules pass.

**Independent Test**: Author a CLAUDE.md describing only `/kiln:kiln-report-issue` (no mention of `/kiln:kiln-distill` or PRD output) in a repo with `.kiln/issues/` populated. Run the audit. Assert `loop-incomplete` fires with `expand-candidate`.

**Acceptance Scenarios**:

1. **Given** the repo has any of `.kiln/issues/`, `.kiln/feedback/`, `.kiln/roadmap/`, `.kiln/mistakes/`, `.kiln/fixes/` populated AND CLAUDE.md does not mention `/kiln:kiln-distill` (or the canonical consumer of those capture surfaces), **When** the audit runs, **Then** `loop-incomplete` fires with action `expand-candidate`.
2. **Given** CLAUDE.md mentions both the capture surfaces and `/kiln:kiln-distill` (or names the equivalent consumer), **When** the audit runs, **Then** `loop-incomplete` does not fire.

---

### User Story 6 — Plugin author updates guidance, downstream consumers see the change (Priority: P2)

The kiln maintainer rewrites `plugin-kiln/.claude-plugin/claude-guidance.md`. Downstream consumers running the audit see a proposed diff updating only kiln's `### kiln` subsection inside `## Plugins`. Other subsections are untouched.

**Why this priority**: This is the plugin-author-to-consumer feedback loop the convention enables. It's tested as a behavior of US1's sync mechanic, not a new rule.

**Independent Test**: Modify `plugin-kiln/.claude-plugin/claude-guidance.md`. Run the audit on a CLAUDE.md whose existing `## Plugins` section reflects the prior kiln content. Assert the proposed diff swaps the kiln subsection only.

**Acceptance Scenarios**:

1. **Given** an updated `plugin-kiln/.claude-plugin/claude-guidance.md`, **When** the audit runs on a downstream CLAUDE.md, **Then** the proposed diff replaces only the `### kiln` subsection inside `## Plugins`.

---

### Edge Cases

- **No CLAUDE.md at repo root** — out of scope per existing skill behavior; abort with the existing error message.
- **CLAUDE.md exists but no plugins enabled** — `## Plugins` (if present) is proposed for full removal; new audits skip the section entirely.
- **A plugin's guidance file is empty or malformed** — treat as "missing guidance" and skip silently per FR-013. Notes section records the skip with one line.
- **Two plugins ship subsections that name-collide (both want `### shelf`)** — impossible by construction (subsection name is the plugin name, plugin names are unique within `.claude/settings.json` enabled list). If detected anyway, surface as a hard failure in Notes; do not propose a diff.
- **`vision.md` exists but is empty / template placeholders only** — `product-slot-missing` fires per slot; the `## Product` sync still runs but mirrors the placeholder text (audit output flags both signals so the user sees the issue at the source).
- **Override config references an unknown rule_id (e.g., a rule from a future kiln version)** — already covered by existing skill behavior (warn + skip line). New rules added in this PRD inherit that handling automatically.
- **Editorial classification LLM fails for one section** — that section is recorded in Notes as `unclassified` (FR-004 default action: keep). Other sections classify normally.
- **First audit post-upgrade fires many `enumeration-bloat` signals on a long-lived CLAUDE.md** — expected and desired per PRD Risks. The audit output is a review surface, not an enforcement gate; the user applies piecemeal or sets `exclude_section_from_classification` to opt out per-section.
- **`vision.md` larger than 40 lines AND no fenced markers** — currently undefined by FR-023 (which says "≤40 lines OR fenced markers"). Spec decision: when vision.md is >40 lines and has no `claude-md-sync:start/end` markers, fire a sub-rule under `product-section-stale` with action `expand-candidate` proposing the user add markers around a summary region. Do NOT mirror the entire long file (would bloat CLAUDE.md and undo the reframe).

## Requirements *(mandatory)*

The following functional requirements mirror the PRD verbatim. PRD numbering is preserved (FR-020 and FR-021 are intentionally absent — see numbering note above).

### Content classification rubric

- **FR-001**: System MUST classify every `## ` section in CLAUDE.md into exactly one of: `product | feedback-loop | convention-rationale | plugin-surface | preference | unclassified`. Classification is via an editorial (LLM) call against rule-specific definitions stored in `plugin-kiln/rubrics/claude-md-usefulness.md`.
- **FR-002**: System MUST flag sections classified as `plugin-surface` with rule `enumeration-bloat` and action `removal-candidate`, citing the rationale "Claude receives available skills / agents / commands via runtime context", UNLESS the section is exempted by FR-017's `exclude_section_from_classification` override.
- **FR-003**: System MUST treat sections classified as `preference` as never-flagged-for-removal. Classification catches them so other rules don't crosshair them.
- **FR-004**: System MUST surface sections classified as `unclassified` in the audit output's Notes section with default action `keep` and a reviewer prompt. The audit MUST NOT silently delete content it could not classify.

### Benefit-narrative + feedback-loop rubric

- **FR-005**: System MUST run rule `benefit-missing` (editorial) on every section classified as `convention-rationale` or `feedback-loop`. The rule fires when the section contains no rationale phrasing (keywords: "because", "without this", "prevents", "so that", or a `Why:` line). On fire, action is `expand-candidate` and the proposed diff inserts a placeholder `Why:` line for the user to fill.
- **FR-006**: System MUST run rule `loop-incomplete` (editorial) when the repo has at least one capture surface (`.kiln/issues/`, `.kiln/feedback/`, `.kiln/roadmap/`, `.kiln/mistakes/`, `.kiln/fixes/`). The rule fires when CLAUDE.md does not name the canonical consumer (`/kiln:kiln-distill`) AND the expected output (PRD → spec → code). On fire, action is `expand-candidate` and the proposed diff inserts a linkage paragraph.

### Hook/claim consistency rubric

- **FR-007**: System MUST run rule `hook-claim-mismatch` (cheap + editorial hybrid). For each assertion in CLAUDE.md about hook behavior (claims naming hooks or hook-enforced behaviors), the rule extracts the claim text + named hook, greps `plugin-*/hooks/*.sh` for language enforcing the claim, and fires with action `correction-candidate` if no hook matches.
- **FR-008**: System MUST scope `hook-claim-mismatch` to static text presence only. Semantic verification (does the hook actually block X at runtime?) is out of scope. False positives from grep-missing-jq-filtered-logic are acceptable; the output is human-reviewed.

### Plugin-guidance convention

- **FR-009**: System MUST recognize `<plugin-dir>/.claude-plugin/claude-guidance.md` as the canonical Claude-facing guidance file for a plugin. The file is short markdown (~10–30 lines) with sections `## When to use` (required, 1–3 sentences), `## Key feedback loop` (optional), `## Non-obvious behavior` (optional). Skill enumerations, command catalogs, and agent lists MUST NOT appear in the file — they are plugin-surface and would be flagged for removal wherever they live.
- **FR-010**: System MUST treat `claude-guidance.md` as UTF-8 markdown, version-controlled with the plugin source. No separate versioning. Plugin authors update the file when the plugin's role changes materially.

### Plugin-guidance sync

- **FR-011**: System MUST enumerate enabled plugins by reading and union-ing the `enabledPlugins` (or equivalent) keys from `.claude/settings.json` (project-local) and `~/.claude/settings.json` (user-global).
- **FR-012**: System MUST resolve each enabled plugin's install path with this priority order:
  1. Source-repo mode — local `plugin-<name>/` directory if present.
  2. Consumer mode — `~/.claude/plugins/cache/<org>-<marketplace>/<plugin>/<version>/` matching the settings-declared version.
  3. Fallback — highest cached version under `~/.claude/plugins/cache/<org>-<marketplace>/<plugin>/`.
- **FR-013**: System MUST read each plugin's `.claude-plugin/claude-guidance.md` if present. Plugins without the file MUST be skipped silently (no signal, no warning) — guidance is opt-in per plugin.
- **FR-014**: System MUST build the authoritative `## Plugins` section in this exact shape:
  ```
  ## Plugins

  ### <plugin-name>

  <claude-guidance.md content, with its top-level `## When to use` demoted to `#### When to use`>

  ### <next-plugin-name>
  ...
  ```
  Plugins MUST be listed in alphabetical order (LC_ALL=C) by name for byte-deterministic diffs.
- **FR-015**: System MUST diff the built section against the existing `## Plugins` section in CLAUDE.md and propose:
  - Section absent → insertion at the file's end (or a deterministic anchor).
  - Section present and drifted → full-section replacement (one diff hunk).
  - Section present and byte-equal → no diff for the section.
  - Plugin listed in CLAUDE.md but no longer enabled → diff removes only that plugin's subsection.
- **FR-016**: System MUST treat `## Plugins` as machine-managed. Audit output Notes MUST include the line: "This section is auto-synced from per-plugin `.claude-plugin/claude-guidance.md` files. Edit the plugins, not CLAUDE.md, for persistent changes."

### Override surface

- **FR-017**: System MUST honor two new keys in `.kiln/claude-md-audit.config`:
  - `exclude_section_from_classification = <regex>, <regex>` — sections matching any regex are classified as `preference` and exempt from FR-002 / FR-005.
  - `exclude_plugin_from_sync = <plugin-name>, <plugin-name>` — listed plugins are skipped during FR-011's enumeration.
  Each value MUST have an inline `# reason: ...` comment; missing reason fires a warning in Notes.

### Anthropic alignment

- **FR-018**: System MUST cite https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md as the external rubric anchor in the audit output's Notes section. New rule rationales that depend on Anthropic's guidance MUST cite the specific claim from that page.
- **FR-019**: System MUST extend `plugin-kiln/rubrics/claude-md-usefulness.md` with a "Convention Notes" section documenting that `claude-guidance.md` is a kiln-specific convention. The migration path MUST be named: "If Anthropic ships an official field for Claude-facing plugin guidance (e.g., `plugin.json:claudeGuidance`), migrate to the official field and deprecate this convention within one release cycle."

### vision.md sync (FR-020 and FR-021 intentionally absent — PRD numbering preserved)

- **FR-022**: System MUST treat the `## Product` section in CLAUDE.md as machine-managed. Its contents MUST be synced from `.kiln/vision.md` per FR-023's region rules. Manual edits MUST be reverted on next sync, same policy as `## Plugins` per FR-016.
- **FR-023**: System MUST source `## Product` from one of two regions of `vision.md`:
  - The entire file body, if `vision.md` is ≤40 lines.
  - The fenced region delimited by `<!-- claude-md-sync:start -->` ... `<!-- claude-md-sync:end -->`, if those markers are present.
  When `vision.md` is >40 lines and markers are absent, fire a sub-signal under `product-section-stale` with action `expand-candidate` proposing the user add markers around a summary region. Do NOT mirror the full long file (per Edge Cases above).
- **FR-024**: System MUST recognize the 7-slot `vision.md` schema:
  1. One-line product summary
  2. Primary target user (+ optional secondary)
  3. Top 3 jobs-to-be-done
  4. Non-goals (what the product is NOT)
  5. Current phase (pre-launch | early-access | maturing | mature | end-of-life)
  6. North-star metric / success shape
  7. Key differentiator
- **FR-025**: System MUST run rule `product-undefined` (cheap). When CLAUDE.md has no `## Product` section AND `.kiln/vision.md` does not exist, the rule MUST fire with action `expand-candidate` and propose a combined diff that creates `.kiln/vision.md` from the template AND adds a `## Product` placeholder to CLAUDE.md. This signal MUST appear at the top of the Signal Summary table regardless of normal sort order.
- **FR-026**: System MUST run rule `product-slot-missing` (editorial) against `vision.md` (not CLAUDE.md). Each of the 7 slots from FR-024 MUST contain at least one sentence of content; empty or template-placeholder slots fire one signal each with action `expand-candidate`. Findings MUST be rendered in a dedicated "Vision.md Coverage" sub-section to keep them separate from CLAUDE.md findings.
- **FR-027**: System MUST run rule `product-section-stale` (cheap). The current `## Product` section in CLAUDE.md MUST be compared against the synced-from-vision composition; differences fire with action `sync-candidate` and the proposed diff is the full-section swap (same mechanic as FR-015).
- **FR-028**: System MUST apply lightweight formatting on sync: `vision.md`'s top-level `#` title is demoted to `## Product`, and any `##` headings inside the synced region are demoted one level (to `###`). No LLM rewriting of voice/tone.
- **FR-029**: System MUST honor `.kiln/claude-md-audit.config` key `product_sync = false` to opt out of vision sync entirely. When set, `## Product` is left alone and classified under FR-001 like any other section. The override MUST require an inline `# reason: ...` per FR-017.

### Existing rubric preservation

- **FR-030**: System MUST continue to run all seven existing rules (`load-bearing-section`, `stale-migration-notice`, `recent-changes-overflow`, `active-technologies-overflow`, `duplicated-in-prd`, `duplicated-in-constitution`, `stale-section`). They are the drift-reducer axis; the new rules layer additively on the coverage axis. Both axes run every audit.
- **FR-031**: System MUST extend signal reconciliation: `load-bearing-section` continues to win over flag-for-removal signals, BUT `enumeration-bloat` (FR-002) MUST win over `load-bearing-section` for sections classified as `plugin-surface`. The new `product-*` rules (FR-025, FR-026, FR-027) MUST NOT conflict with `load-bearing-section` because `## Product` is machine-managed and never load-bearing.

### Key Entities

- **Plugin guidance file** (`.claude-plugin/claude-guidance.md`): UTF-8 markdown, ~10–30 lines, sections `## When to use` (required), `## Key feedback loop` (optional), `## Non-obvious behavior` (optional). One per plugin. Authoritative source for Claude-facing plugin description.
- **Section classification**: enum `product | feedback-loop | convention-rationale | plugin-surface | preference | unclassified`. Assigned per `## ` section by editorial LLM call.
- **Audit override config**: `.kiln/claude-md-audit.config` — extended with `exclude_section_from_classification`, `exclude_plugin_from_sync`, `product_sync` keys. Each requires inline `# reason: ...` comment.
- **vision.md sync region**: either the whole file (≤40 lines) or the fenced `<!-- claude-md-sync:start --> ... <!-- claude-md-sync:end -->` region. Source for the `## Product` section.
- **Audit signal**: `{ rule_id, signal_type, cost, file, section, action, count, justification }`. Rendered in the Signal Summary table; reconciled per FR-030/FR-031 before diff emission.

## Success Criteria *(mandatory)*

These are post-implementation absolute targets per PRD Success Metrics — **not pre-existing baselines**. No baseline-checkpoint research was run before /specify because there is nothing to baseline against (the rules don't exist yet). See `agent-notes/specifier.md` for the rationale.

### Measurable Outcomes

- **SC-001**: After applying the audit's proposed diff and re-running, the same audit produces zero new signals (idempotent within its own output) on the source kiln repo.
- **SC-002**: ≥70% of `## ` sections in the kiln-repo CLAUDE.md classify as `product / feedback-loop / convention-rationale` after one audit-and-apply cycle. (Before reframe: sections are dominantly plugin-surface.)
- **SC-003**: 100% of sections classified as `convention-rationale` contain a `Why:` line (or equivalent rationale phrasing) after one audit-and-apply cycle. Measured by `benefit-missing` signals dropping to zero.
- **SC-004**: At least 3 first-party plugins (kiln, shelf, wheel — and ideally clay, trim) ship a `.claude-plugin/claude-guidance.md` file by the end of the implementation phase. The audit run on a multi-plugin repo produces a non-empty `## Plugins` section diff.
- **SC-005**: Plugins with no `claude-guidance.md` are skipped silently — no signal fires, no warning is logged. Verified by running the audit with one plugin missing the file.
- **SC-006**: `## Product` syncs from `.kiln/vision.md` deterministically — two consecutive audits on unchanged inputs produce byte-identical Signal Summary + Proposed Diff bodies (NFR-002 idempotence carried forward).
- **SC-007**: `product-undefined` fires at the top of the Signal Summary when both vision.md and `## Product` are absent. Position is verified by an integration test that asserts row 1 of the table is the `product-undefined` signal.
- **SC-008**: Override flags (`exclude_section_from_classification`, `exclude_plugin_from_sync`, `product_sync = false`) all suppress their target rules without affecting unrelated signals. Each override has a dedicated test case.
- **SC-009**: The audit's Notes section cites the Anthropic best-practices URL exactly once per run, regardless of which rules fired.
- **SC-010**: All seven pre-existing rules continue to fire on their existing test inputs after the reframe — zero regressions on the drift-reducer axis. Verified by re-running the existing kiln-claude-audit fixtures.

## Assumptions

- The existing `kiln-claude-audit` skill's editorial-rule LLM call pattern (used by `duplicated-in-prd`, `duplicated-in-constitution`, `stale-section`) can be reused for the new editorial rules (`benefit-missing`, `loop-incomplete`, classification call). No new LLM-call infrastructure required.
- Plugin authors are willing to maintain a ~20-line `claude-guidance.md` per plugin. First-party plugins set the example; third-party adoption is best-effort.
- `.claude/settings.json` and `~/.claude/settings.json` are the authoritative source for enabled plugins. Plugins enabled outside this surface fall outside FR-011's enumeration.
- CLAUDE.md at the repo root is the only CLAUDE.md the audit cares about. Nested CLAUDE.md files in subdirectories are out of scope (existing skill behavior preserved).
- The `.claude-plugin/claude-guidance.md` filename is kiln-specific — plugins authored for other ecosystems may not have it. Skipping silently per FR-013 keeps the convention non-coercive.
- `vision.md` follows the 7-slot schema from `2026-04-23-structured-roadmap` PRD's FR-001. If a repo has a custom vision.md without the schema, FR-026 (`product-slot-missing`) will fire on every slot — that's the signal, not a bug.
- Markdown header demotion (FR-014, FR-028) is a deterministic textual transform — no LLM rewriting. Predictability wins over voice-matching.
- The Anthropic best-practices URL is stable enough to cite. If the URL moves, FR-018 / FR-019 are updated in a follow-up PR.
- The audit continues to be propose-diff-only — every new rule honors the no-edits contract per existing skill behavior. The implementation MUST NOT introduce any code path that calls `Edit` / `Write` / `git apply` against CLAUDE.md.
- No new runtime dependencies. Existing toolchain (Bash 5.x, `jq`, editorial LLM call convention, markdown parsing already in the skill) covers all new behavior.
