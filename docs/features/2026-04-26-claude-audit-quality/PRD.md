---
derived_from:
  - .kiln/roadmap/items/2026-04-24-claude-audit-deeper-pass-on-thin.md
  - .kiln/roadmap/items/2026-04-24-claude-audit-emit-real-diffs.md
  - .kiln/roadmap/items/2026-04-24-claude-audit-execute-editorial-rules.md
  - .kiln/roadmap/items/2026-04-24-claude-audit-grounded-citations.md
  - .kiln/roadmap/items/2026-04-24-claude-audit-rethink-recent-changes-rule.md
  - .kiln/roadmap/items/2026-04-24-claude-audit-sibling-preview-codified.md
  - .kiln/roadmap/items/2026-04-24-claude-audit-substance-rules.md
  - .kiln/roadmap/items/2026-04-24-retro-quality-auditor.md
distilled_date: 2026-04-26
theme: claude-audit-quality
---
# Feature PRD: Claude-Audit Quality — Substance Over Mechanics

**Date**: 2026-04-26
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md) — kiln plugin

## Background

Recently the roadmap surfaced these items in the **10-self-optimization** phase: `2026-04-24-claude-audit-deeper-pass-on-thin` (feature), `2026-04-24-claude-audit-emit-real-diffs` (feature), `2026-04-24-claude-audit-execute-editorial-rules` (feature), `2026-04-24-claude-audit-grounded-citations` (feature), `2026-04-24-claude-audit-rethink-recent-changes-rule` (feature), `2026-04-24-claude-audit-sibling-preview-codified` (feature), `2026-04-24-claude-audit-substance-rules` (feature), `2026-04-24-retro-quality-auditor` (feature).

`/kiln:kiln-claude-audit` exists to catch CLAUDE.md drift. In its current form it ships an audit that *looks* complete on the first run — rubric mechanical signals fired, project-context block rendered, best-practices deltas listed — while silently shipping shallow output. A maintainer who reads the report top-to-bottom and stops there will accept thin findings as the audit. In a real session, the user had to issue three explicit challenges before the audit produced substance ("isn't it your job to actually propose the new file?", "did you add anything about vision?", "do we still talk about those specify commands?"). Each challenge produced a better audit; the skill should produce that audit on the first run.

Eight items in the 10-self-optimization phase decompose this into discrete failure modes: comment-only diff hunks ("no diff proposed pending maintainer call"), editorial rules silently falling through to `inconclusive`, `## Project Context` citations that are post-hoc decoration rather than primary justification, no rule for "does this file teach the project's thesis", a circular `## Recent Changes` rule that exists because the rule cites the section, an undocumented sibling-preview convention, no notion of audit depth, and (sibling concern) no equivalent quality auditor for retrospectives. They share a single theme: **the system audits its own output, and right now the audit's bar is too low.** This PRD raises the bar — every fired signal produces a concrete artifact, every editorial rule actually evaluates, every project-context citation is load-bearing, and the rubric covers substance (does this teach the project) not just mechanics (length / freshness).

### Source Issues

| # | Source Entry | Source | Type | GitHub Issue | Severity / Area |
|---|--------------|--------|------|--------------|------------------|
| 1 | [claude-audit deeper-pass-on-thin](../../../.kiln/roadmap/items/2026-04-24-claude-audit-deeper-pass-on-thin.md) | .kiln/roadmap/items/ | item | — | feature / phase:10-self-optimization |
| 2 | [claude-audit emit-real-diffs](../../../.kiln/roadmap/items/2026-04-24-claude-audit-emit-real-diffs.md) | .kiln/roadmap/items/ | item | — | feature / phase:10-self-optimization |
| 3 | [claude-audit execute-editorial-rules](../../../.kiln/roadmap/items/2026-04-24-claude-audit-execute-editorial-rules.md) | .kiln/roadmap/items/ | item | — | feature / phase:10-self-optimization |
| 4 | [claude-audit grounded-citations](../../../.kiln/roadmap/items/2026-04-24-claude-audit-grounded-citations.md) | .kiln/roadmap/items/ | item | — | feature / phase:10-self-optimization |
| 5 | [claude-audit rethink-recent-changes-rule](../../../.kiln/roadmap/items/2026-04-24-claude-audit-rethink-recent-changes-rule.md) | .kiln/roadmap/items/ | item | — | feature / phase:10-self-optimization |
| 6 | [claude-audit sibling-preview-codified](../../../.kiln/roadmap/items/2026-04-24-claude-audit-sibling-preview-codified.md) | .kiln/roadmap/items/ | item | — | feature / phase:10-self-optimization |
| 7 | [claude-audit substance-rules](../../../.kiln/roadmap/items/2026-04-24-claude-audit-substance-rules.md) | .kiln/roadmap/items/ | item | — | feature / phase:10-self-optimization |
| 8 | [retro-quality-auditor](../../../.kiln/roadmap/items/2026-04-24-retro-quality-auditor.md) | .kiln/roadmap/items/ | item | — | feature / phase:10-self-optimization |

## Problem Statement

The audit's contract is to PROPOSE a change; in practice it punts back to the maintainer with comment-only diffs ("no diff proposed pending maintainer call"). The rubric's three editorial rules (`duplicated-in-prd`, `duplicated-in-constitution`, `stale-section`) produce `inconclusive` when the model running the skill — which IS the LLM — declares the editorial pass too expensive. Project-context citations are decorative correlations rather than load-bearing justifications. The rubric has no rules for the highest-cost form of drift: a CLAUDE.md that documents mechanics but never names the project's thesis, loop, or load-bearing concepts. A `## Recent Changes` section exists in CLAUDE.md primarily because rules in `kiln-claude-audit` and `kiln-doctor` cite it — circular load-bearing protection. The sibling-preview pattern (`-proposed-<basename>.md`) emerged ad-hoc in one session and isn't documented. There's no audit depth tier, so a thin first-pass audit looks identical to a deep audit.

These individually are skill-body or rubric edits; collectively they redefine what `/kiln:kiln-claude-audit` is *for* — substance evaluation against project-context, not mechanical hygiene against length thresholds. The retro-quality-auditor item is the same idea applied to retrospective issues: a retro that says "everything went smoothly" should fail a substance check the same way a CLAUDE.md missing the thesis fails this one.

## Goals

- Every fired signal in the audit log produces ONE of: a concrete unified diff, an explicit `inconclusive` with a reference-document reason, or a `keep` (load-bearing protection). No fourth bucket. (items 2, 3)
- The rubric grows four substance rules: `missing-thesis`, `missing-loop`, `missing-architectural-context`, `scaffold-undertaught`. They evaluate the audited file against `.kiln/vision.md` claims and project-context evidence, not against length / freshness. (item 7)
- Editorial rules execute in the model's own context. `inconclusive` is reserved for missing-on-disk reference documents, unparseable references, or genuine external-dependency failures. (item 3)
- `## Project Context` citations in findings are load-bearing — removing the cited signal would change the verdict. Decorative correlations are flagged in audit-of-audit mode. (item 4)
- Audit ordering leads with substance findings, then rubric mechanical findings, then external best-practices deltas. (item 1)
- `## Recent Changes` section is treated as an anti-pattern (rule `recent-changes-anti-pattern`); circular load-bearing protection is removed. The skill body and `kiln-doctor` subcheck handle absent sections gracefully. (item 5)
- Sibling-preview file pattern (`-proposed-<basename>.md`) is codified in the skill — naming convention, permitted-files list, audit-log cross-reference, cleanup convention. (item 6)
- A retro-quality auditor evaluates retrospective issues against a substance rubric (real cause-effect claim / calibration update / process change). Cheaper version: agent self-rates insight at write-time. (item 8)

## Non-Goals

- Building a separate `/kiln:kiln-retro-audit` skill in this PRD — the item flags it as a design question; ship the cheapest version (agent self-rating) and let the auditor pattern accrete from there.
- Auto-applying audit findings — propose-don't-apply remains the contract.
- Implementing `--depth` flag with two tiers in this PRD. Default to substance-first ordering (option A from item 1); flag-handling can be a follow-on if the depth tradeoff turns out to need a knob.
- Audit-the-audit / re-audit mode (option C from item 1) — out of scope, file as follow-on if substance-first reordering doesn't close the gap.

## Implementation Hints

*(No items in this bundle have non-empty `implementation_hints:` frontmatter — the per-item bodies above are the closest equivalent. Implementer should treat each item's "Proposed direction" section as design intent, not authoritative implementation.)*

## Requirements

### Functional Requirements

#### Theme A: Output discipline (every fired signal produces an artifact)

- **FR-001** (from: `2026-04-24-claude-audit-emit-real-diffs.md`) — `kiln-claude-audit/SKILL.md` Step 3.5 invariant: every fired signal MUST produce exactly one of: a concrete unified diff (git-apply-shaped, hunk-by-hunk, with `rule_id:` annotation), an explicit `inconclusive` row with a stated reason in Notes, or `keep` / `keep (load-bearing)` for rules that only ever emit keep. Comment-only diff hunks ("no diff proposed pending maintainer call") are forbidden.
- **FR-002** (from: `2026-04-24-claude-audit-emit-real-diffs.md`) — Test fixture `plugin-kiln/tests/claude-audit-no-comment-only-hunks/` runs the audit against a CLAUDE.md known to fire the `external/length-density` rule and asserts the output contains zero `# ... No diff proposed` lines.
- **FR-003** (from: `2026-04-24-claude-audit-execute-editorial-rules.md`) — `kiln-claude-audit/SKILL.md` Step 3 contract: the model running the skill performs editorial evaluation in its own context — there is no sub-LLM call. For each editorial rule, the skill MUST load the reference document(s), read every `^## ` section, compare per `match_rule`, and emit findings or `(no fire)`. Skipping the comparison and marking `inconclusive` is forbidden unless reference documents are physically unavailable on disk.
- **FR-004** (from: `2026-04-24-claude-audit-execute-editorial-rules.md`) — Rubric preamble in `plugin-kiln/rubrics/claude-md-usefulness.md` documents the legitimate `inconclusive` triggers: missing reference document, unparseable reference, failed external dependency (WebFetch / MCP). "Editorial work feels expensive" is explicitly NOT on the list.
- **FR-005** (from: `2026-04-24-claude-audit-execute-editorial-rules.md`) — Test fixture `plugin-kiln/tests/claude-audit-editorial-pass-required/` runs the audit against a CLAUDE.md known to contain a paraphrase of an article in `.specify/memory/constitution.md` and asserts `duplicated-in-constitution` fires (action: `duplication-flag`), NOT `inconclusive`.

#### Theme B: Substance rules in the rubric

- **FR-006** (from: `2026-04-24-claude-audit-substance-rules.md`) — Add rule `missing-thesis` to `plugin-kiln/rubrics/claude-md-usefulness.md`. `signal_type: substance`, `cost: editorial`. Match: read `.kiln/vision.md` (when present); fire if NO vision pillar appears in the audited file's opener or `## What This Repo Is` body.
- **FR-007** (from: `2026-04-24-claude-audit-substance-rules.md`) — Add rule `missing-loop`. Match: read vision + roadmap-phase status; if the project has shipped a loop and the audited file does not draw it, fire.
- **FR-008** (from: `2026-04-24-claude-audit-substance-rules.md`) — Add rule `missing-architectural-context`. Match: count distinct `plugin-*/` roots; if >1 and the `## Architecture` section describes only one, fire.
- **FR-009** (from: `2026-04-24-claude-audit-substance-rules.md`) — Add rule `scaffold-undertaught`. Match: applies only to scaffold/template CLAUDE.md files; verify the scaffold communicates the same load-bearing concepts as the source repo's CLAUDE.md.
- **FR-010** (from: `2026-04-24-claude-audit-substance-rules.md`) — Substance findings rank above rubric mechanical findings in the audit log's `## Signal Summary` and `## Notes` sections. Output ordering: substance → mechanical → external best-practices.
- **FR-011** (from: `2026-04-24-claude-audit-substance-rules.md`) — Test fixture `plugin-kiln/tests/claude-audit-substance/` runs the audit against a CLAUDE.md that passes mechanical rules but has no vision-pillar reference and asserts `missing-thesis` fires.

#### Theme C: Grounded citations + audit depth

- **FR-012** (from: `2026-04-24-claude-audit-grounded-citations.md`) — Reword the Step 1 / FR-013 contract: every cited project-context signal in a finding's justification MUST be the *primary justification* — removing the signal would change the finding's verdict. Decorative correlations (e.g., "shipped PRD count 46 informs the length-density finding") are forbidden.
- **FR-013** (from: `2026-04-24-claude-audit-grounded-citations.md`) — Replace the "audit MUST ground itself in project context" assertion with: every audit MUST contain at least one finding whose `match_rule` reads from `CTX_JSON` (vision body, roadmap items, plugin list, README, prior CLAUDE.md). If no project-context-driven finding fires, the audit MUST emit a `(no project-context signals fired)` row in the Signal Summary.
- **FR-014** (from: `2026-04-24-claude-audit-grounded-citations.md`) — Test fixture `plugin-kiln/tests/claude-audit-grounded-finding-required/` — CLAUDE.md is structurally clean (passes all rubric rules) but diverges from `.kiln/vision.md` content. Asserts the audit emits ≥1 substance finding citing vision content as primary justification.
- **FR-015** (from: `2026-04-24-claude-audit-deeper-pass-on-thin.md`) — Reorder `kiln-claude-audit/SKILL.md` so the substance pass (FR-006..FR-011 rules) runs at Step 2, BEFORE the cheap rubric rules at Step 3. Output sections in the audit log render in this same order: substance → rubric → external.

#### Theme D: Recent Changes anti-pattern + circular load-bearing

- **FR-016** (from: `2026-04-24-claude-audit-rethink-recent-changes-rule.md`) — Add rule `recent-changes-anti-pattern` to `plugin-kiln/rubrics/claude-md-usefulness.md`. `signal_type: substance`, `cost: cheap`. Match: presence of `## Recent Changes` heading. Action: `removal-candidate`. Proposed diff: replace the section with a one-paragraph "## Looking up recent changes" pointer to `git log`, `.kiln/roadmap/phases/<active>.md`, `ls docs/features/`, and `/kiln:kiln-next`.
- **FR-017** (from: `2026-04-24-claude-audit-rethink-recent-changes-rule.md`) — Update `kiln-claude-audit/SKILL.md` and `kiln-doctor/SKILL.md` `recent-changes-overflow` handlers: when `## Recent Changes` is absent, the rule emits no signal (treat as no drift). When `recent-changes-anti-pattern` has fired in the same audit, demote `recent-changes-overflow` to `keep`.
- **FR-018** (from: `2026-04-24-claude-audit-rethink-recent-changes-rule.md`) — Reword `load-bearing-section` in the rubric: a section is load-bearing when cited from skill/agent/hook/workflow PROSE (instructions, descriptions, error messages). It is NOT load-bearing when cited only inside a rule's `match_rule:` field. Same applies to `## Active Technologies` (cited by `active-technologies-overflow`).
- **FR-019** (from: `2026-04-24-claude-audit-rethink-recent-changes-rule.md`) — Test fixture `plugin-kiln/tests/claude-audit-recent-changes-anti-pattern/` runs the audit against a CLAUDE.md containing `## Recent Changes` and asserts `recent-changes-anti-pattern` fires with a removal-candidate diff.

#### Theme E: Sibling preview convention

- **FR-020** (from: `2026-04-24-claude-audit-sibling-preview-codified.md`) — Update `kiln-claude-audit/SKILL.md` permitted-files list to include `.kiln/logs/claude-md-audit-<TIMESTAMP>-proposed-<basename>.md` (one sibling preview per audited file with non-empty proposed diffs). Naming convention: replace path slashes in basename with `-` (e.g., `plugin-kiln/scaffold/CLAUDE.md` → `-proposed-plugin-kiln-scaffold-CLAUDE.md`).
- **FR-021** (from: `2026-04-24-claude-audit-sibling-preview-codified.md`) — Add Step 4.5 to `kiln-claude-audit/SKILL.md`: render one sibling preview per audited path with at least one proposed diff. The preview file contains the proposed final state of the audited file (post-apply).
- **FR-022** (from: `2026-04-24-claude-audit-sibling-preview-codified.md`) — Audit log's `## Proposed Diff` section header gets a one-line cross-reference: "Side-by-side preview: see `<audit-log-basename>-proposed-<basename>.md`."
- **FR-023** (from: `2026-04-24-claude-audit-sibling-preview-codified.md`) — Audit log footer note: "Once proposed diffs land, this audit log + sibling preview files can be archived to `.kiln/logs/archive/` or deleted." (Cleanup convention; `kiln-doctor` integration deferred per item-low-severity ranking.)

#### Theme F: Retro quality (cheapest version)

- **FR-024** (from: `2026-04-24-retro-quality-auditor.md`) — `kiln-build-prd` retrospective agent emits a self-rated insight score (1-5 with one-line justification) at retro write-time, recorded as a YAML key `insight_score:` in the retro issue's frontmatter. Below threshold (default `3`) the team-lead surfaces the score in the pipeline summary so the user sees the gap.
- **FR-025** (from: `2026-04-24-retro-quality-auditor.md`) — Define a minimal substance rubric for retros (recorded in `plugin-kiln/rubrics/retro-quality.md`): a high-substance retro contains at least ONE of: (a) a non-obvious cause-and-effect claim, (b) a calibration update with reasoning, (c) a process-change proposal. The agent's self-rating prompt cites this rubric verbatim.

### Non-Functional Requirements

- **NFR-001** — Audit completion time: substance rules MUST NOT increase total audit duration by more than 30% relative to the pre-PR baseline on the kiln source repo's CLAUDE.md. (Substance rules are editorial and load-bearing; this caps the latency tax.)
- **NFR-002** — Test fixtures (FR-002, FR-005, FR-011, FR-014, FR-019) MUST be self-contained and runnable via `/kiln:kiln-test plugin-kiln <fixture>` without external network calls.
- **NFR-003** — Re-running the audit on unchanged inputs MUST produce a byte-identical Signal Summary + Proposed Diff body (existing NFR-002 from the original kiln-self-maintenance spec; preserved and extended to include the new substance rule outputs).
- **NFR-004** — Backward compatibility: existing rubric rules (`stale-migration-notice`, `recent-changes-overflow`, `enumeration-bloat`, `hook-claim-mismatch`, etc.) continue to fire as before. New substance rules ADD to the output; they do not REPLACE existing ones.

## User Stories

- **As the kiln maintainer**, when I run `/kiln:kiln-claude-audit`, I want substance findings to lead the report so I see "your CLAUDE.md doesn't teach the project's thesis" before "the file is 252 lines."
- **As the kiln maintainer**, when an editorial rule fires, I want a concrete diff or an `inconclusive` with a missing-document reason — never a comment-only "no diff proposed" punt.
- **As the kiln maintainer**, when an audit cites `.kiln/vision.md` content in a finding, I want that citation to be load-bearing — I should be able to verify "remove vision from the audit's context, finding wouldn't fire."
- **As a retrospective consumer** reading a build-prd retro, I want a `insight_score:` key so I can spot low-substance retros without reading every body.

## Success Criteria

- **SC-001** — `plugin-kiln/tests/claude-audit-no-comment-only-hunks/` passes (FR-002).
- **SC-002** — `plugin-kiln/tests/claude-audit-editorial-pass-required/` passes (FR-005).
- **SC-003** — `plugin-kiln/tests/claude-audit-substance/` passes — `missing-thesis` fires on a structurally-clean CLAUDE.md that lacks vision-pillar references (FR-011).
- **SC-004** — `plugin-kiln/tests/claude-audit-grounded-finding-required/` passes — at least one substance finding fires with primary-justification citation of `CTX_JSON` content (FR-014).
- **SC-005** — `plugin-kiln/tests/claude-audit-recent-changes-anti-pattern/` passes — `recent-changes-anti-pattern` fires with a removal-candidate diff (FR-019).
- **SC-006** — Running `/kiln:kiln-claude-audit` against the kiln source repo's CLAUDE.md emits a substance finding row in the Signal Summary that cites a vision pillar as primary justification — verified by grep'ing the audit log for `signal_type: substance` and confirming `match_rule:` references `vision.body` or equivalent `CTX_JSON` path.
- **SC-007** — Running the audit twice on unchanged inputs produces byte-identical Signal Summary + Proposed Diff bodies (NFR-003 carried forward).
- **SC-008** — A `kiln-build-prd` pipeline run emits a retrospective issue whose body contains an `insight_score:` frontmatter key per FR-024.

## Tech Stack

Inherited from kiln plugin: Bash 5.x, `jq`, `awk`, `python3` (stdlib `json`/`re` for YAML frontmatter parsing), Markdown for skill/rubric authoring. No new runtime dependencies. Editorial passes use the model running the skill (no sub-LLM call); reference documents (`.kiln/vision.md`, `.specify/memory/constitution.md`, `plugin-kiln/scaffold/CLAUDE.md`) are read from disk via `cat` / `awk` and passed inline to the editorial reasoning step.

## Risks & Open Questions

- **R-1**: Substance rules are editorial — defining "vision pillar appears in opener" mechanizably without becoming pedantic. Cheaper version: pre-filter via grep for any vision-pillar phrase (loaded from `.kiln/vision.md` headings); only invoke editorial pass when pre-filter fails.
- **R-2**: The "primary justification" assertion (FR-012) is itself substantive — verifying it requires evaluating each cited signal's load-bearingness. Tractable approach: the audit emits, per finding, a one-line "remove-this-citation-and-verdict-changes-because" rationale; FR-014 fixture asserts that rationale is present and non-empty.
- **R-3**: NFR-001 (latency cap) — substance rules add editorial work to every audit. Likely the kiln source repo's CLAUDE.md already triggers ~3-4 substance signals; the cap is meant to flag a regression, not to gate the change.
- **R-4** (sibling concern): The retro insight-score self-rating may be unreliable (the retro agent grading itself). FR-024 is the cheapest version per item 8's design discussion. If self-rating drifts in practice, escalate to a separate auditor agent — out of scope for this PRD.
- **OQ-1**: `recent-changes-anti-pattern` (FR-016) proposes a "## Looking up recent changes" pointer block. Does the rule's proposed-diff body name the *current* in-progress phase explicitly (`.kiln/roadmap/phases/10-self-optimization.md`), or does it use a generic placeholder (`.kiln/roadmap/phases/<active-phase>.md`)? Generic preserves byte-identity across re-runs; current-phase is more useful at apply time. Recommendation: generic with a Notes-section comment naming the current phase.
- **OQ-2**: Should FR-018's load-bearing reword apply retroactively to the `enumeration-bloat` rule's protection logic (claude-md-audit-reframe FR-031)? FR-031 says `enumeration-bloat` wins over `load-bearing-section` for `plugin-surface` sections. The new wording ("cited from prose, not from rule match_rule") reinforces FR-031 rather than conflicting — but worth a one-line note in the rubric preamble.
- **OQ-3**: Test-fixture overlap — five new fixtures (FR-002, FR-005, FR-011, FR-014, FR-019) all touch `kiln-claude-audit`. Should they share scaffolding (one common `setup.sh` that scaffolds a fake `.kiln/`)? Recommendation: each fixture is self-contained per existing kiln-test convention; some cross-fixture duplication is acceptable.
