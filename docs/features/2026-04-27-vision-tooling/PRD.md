---
derived_from:
  - .kiln/roadmap/items/2026-04-24-vision-alignment-check.md
  - .kiln/roadmap/items/2026-04-24-vision-proactive-system-coaching.md
  - .kiln/roadmap/items/2026-04-24-win-condition-scorecard.md
  - .kiln/roadmap/items/2026-04-25-vision-simple-params-cli.md
distilled_date: 2026-04-27
theme: vision-tooling
---
# Feature PRD: Vision Tooling — Cheap to Update, Drift-Checked, Forward-Projecting, Measurable

**Date**: 2026-04-27
**Status**: Draft
**Parent PRD**: [docs/PRD.md](../../PRD.md)

## Background

`.kiln/vision.md` is the load-bearing product principles file: guiding constraints, what we're building, what's out of scope, success signals. It's read by every coach-driven-capture flow (PR #157), mirrored into CLAUDE.md (PR #180), and cited by retros. But the **tooling around it** has lagged: the file exists, the content is articulated, and yet there's no way to update it cheaply, no check that captures ladder up to it, no forward-looking layer that uses it to surface gaps, and no measurement against its stated win-conditions. Vision-as-static-prose is a documentation pattern; vision-as-live-instrument is what kiln's autonomy thesis needs.

Recently the roadmap surfaced these items in the **10-self-optimization** phase: `2026-04-24-vision-alignment-check` (feature), `2026-04-24-vision-proactive-system-coaching` (feature), `2026-04-24-win-condition-scorecard` (feature), `2026-04-25-vision-simple-params-cli` (feature). The four are not independent — they coalesce into a single coherent capability: `.kiln/vision.md` becomes a live instrument with cheap update paths, drift detection, forward projection, and measurable win-conditions, all sharing the same substrate (`/kiln:kiln-roadmap --vision` skill + `.kiln/vision.md` file + the read-project-context.sh reader from PR #157).

### Source Issues

| # | Source Entry | Source | Type | GitHub Issue | Severity / Area |
|---|--------------|--------|------|--------------|------------------|
| 1 | [Vision-alignment check — flag roadmap drift against the stated vision](../../../.kiln/roadmap/items/2026-04-24-vision-alignment-check.md) | .kiln/roadmap/items/ | item | — | feature / phase:10-self-optimization |
| 2 | [/kiln:kiln-roadmap --vision should proactively suggest system improvements and new features](../../../.kiln/roadmap/items/2026-04-24-vision-proactive-system-coaching.md) | .kiln/roadmap/items/ | item | — | feature / phase:10-self-optimization |
| 3 | [Win-condition scorecard — make the vision falsifiable](../../../.kiln/roadmap/items/2026-04-24-win-condition-scorecard.md) | .kiln/roadmap/items/ | item | — | feature / phase:10-self-optimization |
| 4 | [Vision updates need a simple-params CLI](../../../.kiln/roadmap/items/2026-04-25-vision-simple-params-cli.md) | .kiln/roadmap/items/ | item | — | feature / phase:10-self-optimization |

## Problem Statement

Vision is currently something the user writes *down*, not something that actively shapes work. Four concrete frictions:

1. **Update friction (item 4)**: Mid-session principles ("wheel is plugin-agnostic infrastructure" emerged 2026-04-25 from FR-A1 reversal) need capture *now while fresh*. The only canonical path is `/kiln:kiln-roadmap --vision`'s full coached interview — heavyweight orientation block + per-section diff prompts. For a one-line addition, the choice becomes: (a) full interview = minutes of UI for one bullet, (b) direct file edit = bypasses guardrails, (c) defer = principle decays. The user picked (b) on 2026-04-25; the precedent is bad.

2. **No drift gate (item 1)**: Roadmap items can accumulate without laddering up to any vision pillar. The current `--check` mode audits state consistency only. Off-thesis ideas creep in as the queue grows; nothing flags it.

3. **Backward-looking only (item 2)**: PR #157's coach-driven-capture made `--vision` self-draft from repo evidence. Good — but purely reconciliation. There's no forward-looking layer that asks "given the vision and what's already shipped, where could the system go next?" Vision becomes a record of what is, not a prompt for what could be.

4. **Aspirational, not measurable (item 3)**: The eight six-month signals in `.kiln/vision.md` (a)–(h) are prose. We can't tell if context-informed autonomy, the capture-loop closing, or external-feedback filtering are actually happening — or just believed.

The four items share substrate (vision.md + the `/kiln:kiln-roadmap --vision` skill) but address different failure modes. Bundled, they turn vision from a document into an instrument.

## Goals

- **Make updates cheap** so principles get captured fresh, not deferred (FR-001..FR-005).
- **Make drift visible** so the queue stays on-thesis (FR-006..FR-009).
- **Make the system suggest forward** so vision actively shapes new work (FR-010..FR-014).
- **Make the win-conditions falsifiable** so we know if the thesis is working (FR-015..FR-019).
- **Preserve the heavyweight coached interview** as the default for first-run drafts and major re-anchoring — the lightweight modes are *additions*, not replacements.
- **Internal-first for measurement**: ship the scorecard against THIS repo's vision; defer the generalized rubric framework to V2.

## Non-Goals

- **NOT replacing the heavyweight `/kiln:kiln-roadmap --vision` coached interview.** Simple-params is additive; the interview remains the canonical first-run / major-edit path.
- **NOT shipping a generalized scorecard / rubric framework that consumer projects can populate.** V1 measures the eight signals already articulated in this repo's `.kiln/vision.md`. Generalization is a V2 follow-on once we know which signals are reliably extractable.
- **NOT enforcing alignment-drift refusals.** The drift check is REPORT-ONLY in V1 — it surfaces drifters; the user decides what to move. Promotion-blocking and auto-relocation are V2.
- **NOT introducing `addresses_pillar:` frontmatter on items.** V1 uses inferred (LLM-driven) mapping with a determinism caveat documented. Schema change is V2 only if inferred turns out to be unreliable.
- **NOT auto-running the forward-looking pass.** It is OPT-IN at the end of every `--vision` flow (prompt: "Want me to suggest where the system could go next? [y/N]").
- **NOT spawning roadmap items silently** during forward-pass acceptance — every captured suggestion uses the existing confirm-never-silent hand-off (same pattern as `/kiln:kiln-roadmap --promote`).
- **NOT integrating the scorecard into `/kiln:kiln-next`** in V1. Standalone `/kiln:kiln-metrics` only; integration is V2 after we see how the report is used.

## Requirements

### Functional Requirements

#### Theme A — Simple-params CLI (item 4: vision-simple-params-cli)

- **FR-001** (from: `2026-04-25-vision-simple-params-cli.md`): `/kiln:kiln-roadmap --vision` MUST accept section-targeted append flags as alternatives to the coached interview: `--add-constraint <text>`, `--add-non-goal <text>`, `--add-success-signal <text>`, `--add-mission <text>`, `--add-out-of-scope <text>`. Each appends a new bullet to the named section atomically (temp + mv). When ANY of these flags is present, the heavyweight interview is SKIPPED.
- **FR-002** (from: `2026-04-25-vision-simple-params-cli.md`): `/kiln:kiln-roadmap --vision` MUST also accept section-targeted REPLACE flags: `--update-what-we-are-building <text>`, `--update-what-it-is-not <text>`. Replace forms substitute the entire section body with the provided text. Same atomic write semantics.
- **FR-003** (from: `2026-04-25-vision-simple-params-cli.md`): Every simple-params invocation MUST bump `last_updated:` in the vision frontmatter to `date -u +%Y-%m-%d` BEFORE the atomic write. The `last_updated:` bump is non-negotiable — it's the canonical way drift detectors flag stale vision content.
- **FR-004** (from: `2026-04-25-vision-simple-params-cli.md`): When `.shelf-config` is configured (per existing `--vision` mirror dispatch logic), simple-params MUST dispatch the shelf mirror update on success, byte-identical to what the coached interview emits. When `.shelf-config` is missing/incomplete, simple-params MUST emit ONE warning (matching the existing `kiln-roadmap` warning shape) and continue — do NOT fail.
- **FR-005** (from: `2026-04-25-vision-simple-params-cli.md`): Simple-params flags MUST be mutually exclusive with the coached interview AND with each other in a single invocation. Multiple `--add-*` or `--update-*` flags on the same call are REJECTED with a clear error. (Maintainer batches updates by re-invoking the skill, not by piling flags.) The validator runs BEFORE the file is touched — no partial writes on flag-conflict.

#### Theme B — Vision-alignment check (item 1: vision-alignment-check)

- **FR-006** (from: `2026-04-24-vision-alignment-check.md`): `/kiln:kiln-roadmap --check-vision-alignment` MUST be a new mode that walks every `.kiln/roadmap/items/*.md` with `status != shipped` and `state != shipped`, semantically maps each to one or more vision pillars from `.kiln/vision.md`, and emits an alignment report.
- **FR-007** (from: `2026-04-24-vision-alignment-check.md`): The mapping mechanism MUST be inferred (LLM-driven semantic match — item title + body → vision pillar). NO `addresses_pillar:` frontmatter schema change in V1. Determinism caveat: re-running on unchanged inputs MAY produce different mappings (LLM call). The report MUST include a header note declaring this caveat verbatim: `Mappings are LLM-inferred; re-runs on unchanged inputs may differ. For deterministic mapping, declare addresses_pillar: explicitly per item (V2 schema extension).`
- **FR-008** (from: `2026-04-24-vision-alignment-check.md`): The report MUST contain THREE sections in this order: (a) **Aligned items** — `<item-id>` → `<pillar>` (one line per item, sorted by item-id ASC); (b) **Multi-aligned items** — items mapping to ≥2 pillars (worth scrutiny: are they too broad?); (c) **Drifters** — items mapping to ZERO pillars (off-thesis candidates).
- **FR-009** (from: `2026-04-24-vision-alignment-check.md`): The check is REPORT-ONLY. Drifters are NOT mutated, NOT moved, NOT auto-promoted to `unsorted`. The user reads the report and decides. Promotion-blocking + auto-relocation are explicit V2 non-goals (see Non-Goals).

#### Theme C — Forward-looking proactive coaching (item 2: vision-proactive-system-coaching)

- **FR-010** (from: `2026-04-24-vision-proactive-system-coaching.md`): At the END of every coached `/kiln:kiln-roadmap --vision` interview run (i.e., when the heavyweight interview accepts the reconciled vision), the skill MUST emit a single opt-in prompt: `Want me to suggest where the system could go next? [y/N]`. Default is N (no forward pass). When user types `y`, run the forward-looking pass; otherwise exit normally.
- **FR-011** (from: `2026-04-24-vision-proactive-system-coaching.md`): The forward-looking pass MUST generate ≤5 suggestions, each tagged as one of: `gap` (vision mentions X, no roadmap-item describes how we'd get there), `opportunity` (pattern in recent PRDs/critiques suggests an emergent direction), `adjacency` (candidate capability extending current surface area), `non-goal-revisit` (existing `kind: non-goal` items worth re-examining now that context has changed). Each suggestion cites concrete evidence from PRDs, items, phases, or CLAUDE.md.
- **FR-012** (from: `2026-04-24-vision-proactive-system-coaching.md`): For each suggestion, the user is offered three actions in a per-suggestion confirm-never-silent prompt: `accept` (capture as roadmap item via the existing `/kiln:kiln-roadmap --promote` hand-off), `decline` (write to `.kiln/roadmap/items/<date>-<slug>-considered-and-declined.md` with `kind: non-goal` so future passes don't re-propose), `skip` (no record, may re-surface next pass).
- **FR-013** (from: `2026-04-24-vision-proactive-system-coaching.md`): Declined suggestions MUST persist on disk so the next forward pass deduplicates against them. Dedup key: suggestion title + tag. Persistence file: `.kiln/roadmap/items/<date>-<slug>-considered-and-declined.md` per declined entry.
- **FR-014** (from: `2026-04-24-vision-proactive-system-coaching.md`): Forward-pass invocations are tied to coached `--vision` runs ONLY — they do NOT fire on simple-params invocations (Theme A). Rationale: simple-params skips the interview by design; the forward pass is a thoughtful add-on to the heavyweight flow, not a per-update tax.

#### Theme D — Win-condition scorecard (item 3: win-condition-scorecard)

- **FR-015** (from: `2026-04-24-win-condition-scorecard.md`): A new skill `/kiln:kiln-metrics` MUST walk repo state (git log, `.kiln/`, `.wheel/history/`, `docs/features/`) and produce a scorecard against the eight six-month signals (a)–(h) in this repo's `.kiln/vision.md`.
- **FR-016** (from: `2026-04-24-win-condition-scorecard.md`): The scorecard MUST emit a tabular report with columns: `signal | current_value | target | status (on-track / at-risk / unmeasurable) | evidence (file/path/commit cite)`. One row per signal, eight rows in V1 (one per articulated signal in this repo's vision).
- **FR-017** (from: `2026-04-24-win-condition-scorecard.md`): The skill MUST degrade gracefully when a signal can't be measured — emit `status: unmeasurable` with `evidence: <reason>` instead of failing. The report still emits with eight rows; some may carry the unmeasurable verdict.
- **FR-018** (from: `2026-04-24-win-condition-scorecard.md`): Each signal extractor MUST be a separate shell function inside `plugin-kiln/scripts/metrics/` named `extract-signal-<a..h>.sh`. The orchestrator (`/kiln:kiln-metrics`) calls each extractor and aggregates. This makes adding/swapping signals a per-extractor PR rather than a skill rewrite.
- **FR-019** (from: `2026-04-24-win-condition-scorecard.md`): The scorecard report MUST be written to `.kiln/logs/metrics-<YYYY-MM-DD-HHMMSS>.md` and stdout. The log file is the audit trail; stdout is the user-facing surface.

### Non-Functional Requirements

- **NFR-001** (determinism boundaries): Theme A (simple-params), Theme B's report shape, and Theme D's extractors MUST be deterministic — same inputs produce byte-identical output. Theme B's *mappings* and Theme C's *suggestions* are explicitly LLM-inferred (NOT deterministic), and the report headers MUST surface that caveat verbatim. The non-deterministic boundary is named, not hidden.
- **NFR-002** (internal-first): Theme D ships against THIS repo's eight signals only. The skill's extractor surface (`plugin-kiln/scripts/metrics/extract-signal-<x>.sh`) is structured so a V2 generalization (consumer-configurable rubric) is additive — no rewrite. V1 is internal-only by construction; consumer use is undefined and unsupported.
- **NFR-003** (atomic writes): Every vision-mutating operation (Theme A's `--add-*` and `--update-*`) MUST use temp + mv atomic write. Partial writes are forbidden. Concurrent invocations MUST not corrupt the file (file-level lock at `.kiln/.vision.lock` — same pattern as `.shelf-config.lock`).
- **NFR-004** (coverage gate): Constitution Article II — ≥80% coverage on new code. Where shell-only fixtures (run.sh-only) are the substrate, count assertion blocks and cite per-extractor PASS counts (per-test-substrate-hierarchy convention from PR #189).
- **NFR-005** (back-compat for `/kiln:kiln-roadmap --vision`): The existing coached interview behavior MUST be byte-identical when invoked WITHOUT any new simple-params or `--check-vision-alignment` flag. Theme A's flags are additive; their absence preserves the pre-PRD path (NFR-005 byte-identity convention from PR #189).

## User Stories

- **As the maintainer mid-session**, when an architectural principle surfaces (like "wheel is plugin-agnostic infrastructure"), I run `/kiln:kiln-roadmap --vision --add-constraint "<text>"` and capture it in 5 seconds — including the `last_updated:` bump and shelf mirror dispatch — without touching `vision.md` directly.
- **As the maintainer monthly**, I run `/kiln:kiln-roadmap --check-vision-alignment` and see which queued items don't ladder up to any vision pillar. I review the drifter list, decide which to demote to `unsorted` or close, and the queue stays on-thesis.
- **As the maintainer after a coached vision update**, I accept the opt-in forward-pass prompt and get 5 specific suggestions tagged gap/opportunity/adjacency/non-goal-revisit. I accept 2, decline 1, skip 2 — and the 2 accepted suggestions land as roadmap items via the same hand-off as `/kiln:kiln-roadmap --promote`.
- **As the maintainer quarterly**, I run `/kiln:kiln-metrics` and get an eight-row scorecard against my vision's six-month signals. I see which are on-track, which are at-risk, and which are unmeasurable — with file-and-commit citations for every verdict. The vision is no longer aspirational prose; it's a falsifiable instrument.

## Success Criteria

- **SC-001** (Theme A live-fire): After shipping, the maintainer runs `/kiln:kiln-roadmap --vision --add-constraint "Test constraint — <UTC-timestamp>"` and verifies (a) `vision.md` gains the constraint as a new bullet under the right section, (b) frontmatter `last_updated:` is bumped to today, (c) the constraint text appears verbatim, (d) total elapsed time from invocation to file-on-disk < 3 seconds.
- **SC-002** (Theme A flag-conflict refusal): `/kiln:kiln-roadmap --vision --add-constraint "x" --add-non-goal "y"` MUST exit non-zero with a clear error before touching `vision.md`. Verified by `git diff .kiln/vision.md` returning empty after the failed invocation.
- **SC-003** (Theme B report shape): Running `/kiln:kiln-roadmap --check-vision-alignment` against the current repo's open items emits a report with the three required sections in order (Aligned, Multi-aligned, Drifters), the inference-caveat header verbatim, and zero file mutations (verified by `git diff` empty post-run).
- **SC-004** (Theme C opt-in path): A coached `/kiln:kiln-roadmap --vision` run that completes the heavyweight interview MUST end with the literal prompt `Want me to suggest where the system could go next? [y/N]`. Replying `n` (or default empty) MUST exit normally without writing `.kiln/roadmap/items/*-considered-and-declined.md`.
- **SC-005** (Theme C forward-pass shape): Replying `y` to SC-004 emits ≤5 suggestions, each tagged with one of {gap, opportunity, adjacency, non-goal-revisit} and each citing concrete evidence (file path or commit hash). Per-suggestion accept/decline/skip decisions are honored: `accept` invokes the existing `/kiln:kiln-roadmap --promote` hand-off, `decline` writes a `kind: non-goal` declined-record file, `skip` writes nothing.
- **SC-006** (Theme C dedup): A second forward-pass run after declining a suggestion MUST NOT re-emit the same suggestion (matched by title + tag). Verified by running the forward pass twice in a row with no intervening repo state changes.
- **SC-007** (Theme D scorecard shape): `/kiln:kiln-metrics` emits a report with 8 rows (one per signal a–h) in the prescribed column shape. Each row carries either `on-track`, `at-risk`, or `unmeasurable`. The report is written to both stdout AND `.kiln/logs/metrics-<timestamp>.md`.
- **SC-008** (Theme D graceful degrade): If at least one signal extractor cannot return a value (e.g., the data source is missing), the skill exits 0 (NOT non-zero), the report still emits with 8 rows, and the affected row carries `status: unmeasurable` with a reason in the `evidence` column.
- **SC-009** (cross-cutting back-compat): A regression test asserts that `/kiln:kiln-roadmap --vision` invoked WITHOUT new flags produces byte-identical output (stdout + `vision.md` mutations) to the pre-PRD coached interview. Captured via fixture: pre-PRD recording vs post-PRD invocation against the same fixture vision.md.
- **SC-010** (forward-pass tied to coached only): `/kiln:kiln-roadmap --vision --add-constraint "x"` (simple-params path) MUST NOT emit the forward-pass prompt. Verified by stdout grep returning zero matches for the prompt string after a simple-params invocation.

## Tech Stack

Inherited from parent PRD. No additions. Implementation is bash scripts + skill markdown — same substrate as the rest of `plugin-kiln/`. The LLM calls (Theme B mappings, Theme C suggestions) reuse the same Claude-CLI substrate that PR #157's coach-driven-capture established.

## Risks & Open Questions

- **R-1** (Theme B determinism boundary visibility): If users skim past the inference-caveat header, they may treat the alignment report as authoritative. Mitigation: header note is verbatim, terse, and includes the V2 schema-extension pointer. If observed in retros, escalate the determinism gap as a follow-on PRD (add `addresses_pillar:` frontmatter, schema migration).
- **R-2** (Theme C forward-pass quality): The first time the forward pass runs, it may surface plausible-but-low-quality suggestions (LLM artifacts). Mitigation: hard cap at ≤5 + evidence-cite-required + decline-persistence; iterate after first month of use.
- **R-3** (Theme D V1 scope drift): "Generalize the rubric framework" is a tempting V2 pull. Mitigation: spec.md MUST anchor on THIS repo's eight signals and explicitly reject the rubric-framework abstraction in scope-statement language.
- **R-4** (NFR-005 back-compat assertion): The byte-identical-coached-interview regression depends on a fixture capture of pre-PRD behavior. If the implementer doesn't capture the pre-PRD output BEFORE editing `kiln-roadmap/SKILL.md`, the assertion can't be authored. Specifier MUST flag this as a Phase-1 task (capture fixture before any code changes).
- **OQ-1** (Theme A flag set completeness): The 5 sections covered by `--add-*` (`--add-constraint`, `--add-non-goal`, `--add-success-signal`, `--add-mission`, `--add-out-of-scope`) plus the 2 covered by `--update-*` (`--update-what-we-are-building`, `--update-what-it-is-not`) match the canonical sections in `.kiln/vision.md` template. If the template grows new sections, the flag set needs to expand. Spec.md should anchor on a section-flag mapping table and call out the maintenance contract.
- **OQ-2** (Theme C declined-record naming): Declined-suggestion files use `kind: non-goal` and naming `<date>-<slug>-considered-and-declined.md`. Should they be in a separate subdir (`.kiln/roadmap/items/declined/`) to avoid polluting the main item list with negative records? Defer to specifier — both shapes are valid. Suggest: `.kiln/roadmap/items/declined/` for cleaner scan; main-list-only is the lazier option.
- **OQ-3** (Theme D `/kiln:kiln-next` integration): Spec edge case: should `/kiln:kiln-next` automatically include the latest scorecard verdict in its report? Out of scope for V1 (Non-Goal) but Forward-pass FR-011 already cites `/kiln:kiln-next` as a place where forward-suggestions might surface — there's a faint coupling worth flagging.

---

## Dependency note

This PRD assumes:
- PR #157 (coach-driven-capture-ergonomics) has shipped `read-project-context.sh` — which Theme B and Theme C use as their grounding source.
- PR #180 (CLAUDE.md audit reframe) has shipped vision sync into CLAUDE.md — Theme A's `last_updated:` bump triggers the existing mirror dispatch path.

Both are MERGED; no blocking dependency.
