---
derived_from:
  - .kiln/feedback/2026-04-23-we-should-add-a-way.md
  - .kiln/feedback/2026-04-24-roadmap-agent-should-be-more-encouraging.md
  - .kiln/issues/2026-04-23-claude-md-audit-lacks-project-context.md
  - .kiln/issues/2026-04-24-kiln-vision-self-exploring-and-self-updating.md
distilled_date: 2026-04-24
theme: coach-driven-capture-ergonomics
---
# Feature PRD: Coach-Driven Capture Ergonomics

**Date**: 2026-04-24
**Status**: Draft
**Parent PRD**: —

## Background

Kiln's capture surfaces — `/kiln:kiln-roadmap` (item + vision), `/kiln:kiln-claude-audit`, and `/kiln:kiln-distill` — currently behave like checklists. They ask blank-slate questions, emit thin analyses, and require the user to supply the reasoning the skill should itself be providing. The strategic feedback in this bundle names the pattern directly: capture "feels dull," the interview "feels like form-filling," and follow-up steps are one-at-a-time when the user is ready to commit to several at once. The underlying concern is that skills do not use the rich evidence the repo already contains (PRDs, roadmap items, phases, CLAUDE.md, README, plugin manifests) to seed or coach the interaction — so the user is cold-starting a conversation the tool could be leading.

The tactical issues bundled alongside this feedback reinforce the same arc: the `/kiln:kiln-claude-audit` skill is applying a generic rubric without reading project context first, and `/kiln:kiln-roadmap --vision` shows a blank template rather than a draft derived from the repo. Both failures point to the same missing capability — a shared "read the project state, propose a draft, then coach the user through diffs" pattern that the ergonomic skills can lean on.

### Source Issues

| # | Source Entry | Source | Type | GitHub Issue | Severity / Area |
|---|--------------|--------|------|--------------|------------------|
| 1 | [Distill should support selecting multiple themes and emitting multiple PRDs in sequence](.kiln/feedback/2026-04-23-we-should-add-a-way.md) | .kiln/feedback/ | feedback | — | medium / ergonomics |
| 2 | [Roadmap interview should coach with insight, not just interrogate](.kiln/feedback/2026-04-24-roadmap-agent-should-be-more-encouraging.md) | .kiln/feedback/ | feedback | — | medium / ergonomics |
| 3 | [CLAUDE.md audit does not take project context into account](.kiln/issues/2026-04-23-claude-md-audit-lacks-project-context.md) | .kiln/issues/ | issue | — | medium / kiln |
| 4 | [`/kiln:kiln-roadmap --vision` should self-explore the repo first, then ask clarifying questions, and self-update](.kiln/issues/2026-04-24-kiln-vision-self-exploring-and-self-updating.md) | .kiln/issues/ | issue | — | medium / ergonomics |

## Problem Statement

Capture ergonomics in kiln are stuck at the "collect raw strings from the user" stage. The skills that define the product's authoring surface — roadmap capture, vision maintenance, CLAUDE.md audit, and distill — each have a specific ergonomic failure mode:

- **Roadmap capture** asks questions without offering insight, suggestions, or accept-all shortcuts. Users disengage mid-interview or submit thin one-liners because the interview does not explain *why* answers matter or *what* a good answer looks like.
- **Vision maintenance** starts from a blank template even when the repo contains months of PRDs, phase files, and roadmap items that could seed a first draft. The user is asked to cold-start a document the skill could be 80% populating.
- **CLAUDE.md audit** applies an abstract usefulness rubric without first reading the repo it is auditing, so its suggestions are generic rather than project-specific — and miss the guidance already published at `code.claude.com/docs/en/best-practices#write-an-effective-claude-md`.
- **Distill** forces one-theme-at-a-time PRD creation even when the user has pre-decided to bundle multiple themes in sequence, adding friction to the very ritual meant to compress backlog into PRDs.

These are four instances of one missing pattern: skills that should be coaching from project context are instead interrogating against a blank slate.

## Goals

- Make every capture / audit surface **project-context-aware by default**: read the repo's existing artifacts (PRDs, roadmap items, phases, CLAUDE.md, README, plugin manifests) before asking the user anything.
- Turn open-ended interview questions into **coached proposals** — the skill suggests best-guess answers, the user accepts / tweaks / rejects.
- Provide **accept-all / accept-with-tweaks** shortcuts so a user ready to commit is not forced to step through every question individually.
- Support **multi-theme distill** so a user who wants to emit several PRDs in sequence can do so from a single `/kiln:kiln-distill` invocation.
- Extend CLAUDE.md audit to **read the current project state** and evaluate the file against Anthropic's published CLAUDE.md best-practices in addition to the internal rubric.
- Make vision maintenance **diff-first, not rewrite-first**: on re-run, propose targeted edits grounded in evidence rather than re-asking the same three open-ended prompts.

## Non-Goals

- Replacing the existing rubrics (`plugin-kiln/rubrics/claude-md-usefulness.md`, `structural-hygiene.md`). This PRD extends them with project-context signals; it does not deprecate them.
- Auto-applying proposed edits to `CLAUDE.md` or `.kiln/vision.md` without human review. Every proposal stays diff-shaped and user-approved.
- Redesigning `/kiln:kiln-feedback`, `/kiln:kiln-report-issue`, `/kiln:kiln-mistake`. Their interviews are already scoped to a single capture action; coaching applies here only if an explicit follow-up surfaces.
- Adding coaching to agent-team skills (`/kiln:kiln-build-prd`, QA agents). This PRD is scoped to user-facing capture skills.
- Building a new standalone "project-context summarizer" skill. The reader is a shared helper used by the four target skills, not a user-invocable command.

## Requirements

### Functional Requirements

**Shared project-context reader**

- **FR-001 (from: both issues; motivates the shared layer)** — Introduce a shared project-context reader (script or library under `plugin-kiln/scripts/context/`) that returns a structured snapshot of the repo's capture-relevant signals: open PRDs (under `docs/features/*/PRD.md`), roadmap items grouped by phase + state, roadmap phases with status, the current `.kiln/vision.md` (if any), `CLAUDE.md`, `README.md`, and the list of installed plugin manifests. Output must be a single JSON object the consuming skills can parse.
- **FR-002 (from: both issues)** — The reader must be defensive: if a source is missing (no vision, no PRDs, empty roadmap), it returns an empty field rather than failing. Consuming skills decide whether to fall back.

**`/kiln:kiln-roadmap` interview coaching** (from: .kiln/feedback/2026-04-24-roadmap-agent-should-be-more-encouraging.md)

- **FR-003** — The item-capture interview (non-`--quick`) must, for each question, offer a best-guess suggested answer drawn from the user's initial description + the project-context snapshot. Format: question + proposed answer + rationale one-liner + `[accept / tweak / reject]` affordance.
- **FR-004** — The interview must support an `accept-all` command that finalizes the item using the suggested answers for any remaining unanswered questions. A `tweak X then accept-all` form must also be accepted.
- **FR-005** — Before the first question, the skill must emit a one-paragraph *orientation* block that explains how this item connects to the existing roadmap (current phase, nearby items, open critiques that may be addressed, the vision if present). This is the "why it matters" framing that converts the interview from a checklist into a conversation.
- **FR-006** — The interview text must read collaboratively (e.g., "Here's what I think, tell me if I'm off") rather than interrogatively. This is a tone requirement — not a template match — and is validated by reviewing the SKILL.md prompt updates during PRD audit.

**`/kiln:kiln-roadmap --vision` self-exploration** (from: .kiln/issues/2026-04-24-kiln-vision-self-exploring-and-self-updating.md)

- **FR-007** — On first invocation with no `.kiln/vision.md` (or an empty/stub file), `--vision` must consume the project-context snapshot (FR-001) and draft all four vision sections with concrete content, each line citing its evidence (e.g., "derived from: docs/features/<slug>/PRD.md"). The user reviews the draft and confirms / edits.
- **FR-008** — On subsequent invocations with a populated vision, `--vision` must diff repo-state against the current vision and present *line-level proposed edits* tied to specific evidence (e.g., "PRD for structured-roadmap shipped — propose adding typed roadmap items to 'What we are building' [yes / rephrase / skip]"). The user may accept-all, reject-all, or step through.
- **FR-009** — Any accepted edit bumps `last_updated:` in the vision frontmatter.
- **FR-010** — Fallback: if the project-context snapshot is empty (brand-new repo, no PRDs, no items), `--vision` falls back to the existing blank-slate question path. A one-line banner must announce the fallback.

**`/kiln:kiln-claude-audit` project-context grounding** (from: .kiln/issues/2026-04-23-claude-md-audit-lacks-project-context.md)

- **FR-011** — Before applying the usefulness rubric, the audit must consume the project-context snapshot and extract the repo's current commands, tech stack, active phases, and known-gotchas. The audit preview at `.kiln/logs/claude-md-audit-<timestamp>.md` must cite this context in its recommendations (e.g., "section 'Active Technologies' drifted — current phase is `08-in-flight` but Active Technologies block still lists phase 06 branches").
- **FR-012** — The audit must additionally evaluate `CLAUDE.md` against Anthropic's published guidance at `https://code.claude.com/docs/en/best-practices#write-an-effective-claude-md`. Guidance is fetched or mirrored into `plugin-kiln/rubrics/claude-md-best-practices.md` as a cached reference; the audit emits a second sub-section in the preview titled "External best-practices deltas." If the live doc cannot be fetched, the audit falls back to the cached copy and flags the staleness.
- **FR-013** — The audit continues to be a **propose-don't-apply** skill. Every finding stays in the preview log; no edits to `CLAUDE.md` are applied automatically.

**`/kiln:kiln-distill` multi-theme emission** (from: .kiln/feedback/2026-04-23-we-should-add-a-way.md)

- **FR-014** — After grouping themes (current Step 2), distill must offer a multi-select option: the user can pick **N≥1 themes**, and distill will emit **one PRD per selected theme** under `docs/features/<date>-<slug>-N/PRD.md` (or similar disambiguating slug).
- **FR-015** — When multiple PRDs are emitted, distill must present a **run-plan block** at the end summarizing the emitted PRDs and suggesting `/kiln:kiln-build-prd <slug-1>` → `/kiln:kiln-build-prd <slug-2>` in order, with a brief rationale for the suggested order (typically highest-severity / foundational first).
- **FR-016** — Source-entry status flips (Step 5 of distill) must be partitioned correctly: each emitted PRD only flips the entries it actually bundled. Cross-PRD accidental overwrites are prohibited.
- **FR-017** — The `derived_from:` invariant (three-group sort, filename ASC within each group, frontmatter ↔ source-table parity) applies independently to **each** emitted PRD. The NFR-003 determinism guarantee is preserved per-PRD.

### Non-Functional Requirements

- **NFR-001** — The project-context reader must be fast enough to run at the start of every capture / audit invocation without noticeable latency (budget: <2 seconds on a repo of kiln's size, ~50 PRDs, ~100 roadmap items).
- **NFR-002** — The reader's output must be **deterministic** — two runs against unchanged repo state produce byte-identical JSON. Sort every collection by filename ASC.
- **NFR-003** — Multi-theme distill's per-PRD frontmatter emission must preserve the existing byte-identical-output-on-unchanged-input guarantee (spec `prd-derived-from-frontmatter` FR-037, three-group sort per `structured-roadmap` contract §7.2).
- **NFR-004** — Interview coaching additions must stay **offline-safe** — no network calls in the normal capture path. The external best-practices fetch in FR-012 is the only network-requiring piece and must degrade gracefully to the cached copy.
- **NFR-005** — Backward compatibility: callers who invoke `/kiln:kiln-roadmap <desc>` without reading orientation, or `/kiln:kiln-distill` with a single theme, see no behavioral regression. `--quick` still skips the interview entirely.

## User Stories

- **As a user capturing a new roadmap item**, I want the interview to tell me why this item matters and propose sensible answers, so I can commit quickly without re-deriving context the skill already has.
- **As a user running `/kiln:kiln-roadmap --vision` for the first time**, I want to see a draft vision derived from my PRDs and roadmap items, so I'm editing a starting point instead of staring at a blank template.
- **As a maintainer re-running `/kiln:kiln-roadmap --vision` months later**, I want to see line-level proposed edits tied to what has shipped since the last update, not a blank slate, so the vision document stays honest with minimal effort.
- **As a user running `/kiln:kiln-claude-audit`**, I want the preview to call out drift between `CLAUDE.md` and the repo's current commands, phases, and tech stack, and flag divergences from Anthropic's published best-practices, so the audit is specific rather than abstract.
- **As a user running `/kiln:kiln-distill` with several themes ripe for PRD-ing**, I want to select multiple themes in one invocation and get a run-plan for the pipeline, so I'm not repeating the ritual N times.

## Success Criteria

- Capturing a typical roadmap item via the coached interview takes ≤50% of the current question count for the user (measured by accepted-suggestion rate).
- A fresh-repo run of `/kiln:kiln-roadmap --vision` produces a vision document with all four sections populated on first review pass (no additional back-and-forth required).
- `/kiln:kiln-claude-audit` preview logs reference at least one project-context signal (current phase, tech stack drift, command drift) and at least one external-best-practices delta per run.
- `/kiln:kiln-distill` can emit N PRDs in a single invocation with correct per-PRD source-entry status flips and byte-identical determinism on re-run.
- No regression in `--quick` capture paths or single-theme distill.

## Tech Stack

Inherited from the existing plugin-kiln stack:

- Bash 5.x + `jq` for the project-context reader and scripts.
- Markdown for skill prompt updates and rubric extensions.
- `plugin-kiln/scripts/context/` as the new shared-helpers directory.
- Existing `plugin-kiln/scripts/roadmap/` helpers (`list-items.sh`, `parse-item-frontmatter.sh`) are dependencies.
- `WebFetch` tool for the external best-practices reference in `/kiln:kiln-claude-audit` (FR-012); cached copy at `plugin-kiln/rubrics/claude-md-best-practices.md`.

## Risks & Open Questions

- **Coaching suggestion quality** — If the suggested answers are consistently weak, the interview becomes noisier, not lighter. Mitigation: suggestions must be grounded in project-context snapshots, not invented — the skill shows its sources alongside the suggestion. Evaluate on first two real uses before committing to the pattern across all four surfaces.
- **Multi-theme distill PRD slug collisions** — If the user selects two themes that share a date + theme slug, disambiguation is required. Decision deferred to plan: either numeric suffix (`-1`, `-2`) or theme-slug de-dup at grouping time.
- **External best-practices doc drift** — `code.claude.com/docs/en/best-practices` may evolve. The cached copy must record a `fetched:` date and the audit should flag when the cache is >30 days old.
- **Vision diff UX** — Line-level diff proposals can get verbose on active repos. Plan phase needs to define a grouping strategy (by vision section) so the user is not buried in 50 individual y/n prompts.
- **Scope of coaching tone (FR-006)** — "Reads collaboratively" is not easily testable in CI. PRD audit should rely on manual review of the updated SKILL.md prompts; tests cover behavior, not tone.
- **Dependency on `structured-roadmap` items** — Empty `.kiln/roadmap/items/` (e.g., in a fresh consumer repo pre-migration) must still let `--vision` draft a partial vision from PRDs + README + CLAUDE.md alone. FR-010's fallback banner covers the fully-empty case; the partial case should be covered by plan-phase design.
