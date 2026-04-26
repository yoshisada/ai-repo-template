# Implementation Plan: CLAUDE.md Audit Reframe

**Branch**: `build/claude-md-audit-reframe-20260425` | **Date**: 2026-04-25 | **Spec**: `specs/claude-md-audit-reframe/spec.md`
**Input**: Feature specification from `specs/claude-md-audit-reframe/spec.md`
**PRD**: `docs/features/2026-04-24-claude-md-audit-reframe/PRD.md`

## Summary

Reframe `/kiln:kiln-claude-audit` along three concern axes:

1. **Content classification + new rules** (FR-001..FR-008): an editorial LLM call classifies every `## ` section into `product | feedback-loop | convention-rationale | plugin-surface | preference | unclassified`. Four new rules layer on the classification (`enumeration-bloat`, `benefit-missing`, `loop-incomplete`, `hook-claim-mismatch`) and run alongside the existing seven rules.
2. **Plugin-guidance sync** (FR-009..FR-016, FR-017, FR-018..FR-019): each plugin ships a `.claude-plugin/claude-guidance.md`; the audit enumerates enabled plugins (project + user settings union), reads each guidance file, builds a deterministic `## Plugins` section, and proposes a diff. Plugins without the file are skipped silently. New `.kiln/claude-md-audit.config` override keys provide escape hatches.
3. **vision.md → `## Product` sync** (FR-022..FR-029): same machine-managed sync mechanic as `## Plugins`, sourced from `.kiln/vision.md` (whole file ≤40 lines, or fenced region). Three new rules cover the coverage gap (`product-undefined`), source-quality (`product-slot-missing`), and drift (`product-section-stale`).

All seven existing rules continue to run unchanged (FR-030); signal reconciliation is extended so `enumeration-bloat` wins over `load-bearing-section` for `plugin-surface` sections (FR-031).

The implementation is split between two implementer agents working on **disjoint file sets**:

- **`impl-audit-logic`** — owns all audit logic: extends `plugin-kiln/skills/kiln-claude-audit/SKILL.md` with new steps (classification, sync, vision sync, override parsing extension), extends `plugin-kiln/rubrics/claude-md-usefulness.md` with new rule entries + Convention Notes, updates `plugin-kiln/templates/vision-template.md` if needed for `product-undefined`'s scaffold proposal.
- **`impl-plugin-guidance`** — owns all five new `.claude-plugin/claude-guidance.md` files (kiln, shelf, wheel, clay, trim). Pure content authoring; touches no skill / rubric / hook code.

The two implementers do NOT share files. Tasks are wired so each phase declares its owner explicitly.

## Technical Context

**Language/Version**: Bash 5.x (skill body and helper scripts), Markdown (skill definitions, rubric, guidance files, templates), YAML-ish frontmatter (rule entries inside the rubric).
**Primary Dependencies**: `jq` (settings JSON parsing), POSIX utilities (`grep -F`, `awk`, `sed`, `find`), the existing editorial-LLM call convention used by `duplicated-in-prd` / `duplicated-in-constitution` / `stale-section` (no new LLM infra).
**Storage**: file-based. Audit output → `.kiln/logs/claude-md-audit-<TIMESTAMP>.md`. Override config → `.kiln/claude-md-audit.config`. Plugin guidance → `<plugin-dir>/.claude-plugin/claude-guidance.md`. Vision source → `.kiln/vision.md`.
**Testing**: kiln test harness (`/kiln:kiln-test plugin-kiln <test>`) — fixture-based skill tests under `plugin-kiln/tests/`. Existing claude-audit fixtures cover the 7 pre-existing rules; new fixtures cover each new rule + each new override.
**Target Platform**: macOS + Linux dev environments; both shipping kiln consumers and the source repo. Source-repo mode and consumer mode are both first-class (FR-012).
**Project Type**: Claude Code plugin source repo (skills + rubrics + templates + scaffold). No `src/` tree — kiln plugin internals.
**Performance Goals**: Editorial-rule latency unconstrained per existing skill convention (cf. SKILL.md Step 5 footer: "Editorial LLM calls have no latency target for this skill"). Cheap-rule total runtime budget continues to fit comfortably under the 2s `/kiln:kiln-doctor` subcheck (the doctor uses cheap rules only).
**Constraints**: Two-runs-on-unchanged-inputs idempotence (NFR-002 carried forward — extends to new rules and new sections). No new runtime deps. Audit MUST NOT apply edits — propose-diff-only contract is non-negotiable.
**Scale/Scope**: ~5 plugins per consumer; ~20–40 sections per CLAUDE.md; ~5–10 enabled plugins worst-case. The editorial classification call runs once per audit (single LLM call returns classifications for all sections in one shot — see "LLM call shape" below).

## Constitution Check

| Article | Status | Notes |
|---|---|---|
| I. Spec-First (NON-NEGOTIABLE) | ✅ Pass | spec.md exists, FRs numbered, acceptance scenarios defined per US. |
| II. 80% Coverage Gate | ✅ Pass (best-effort) | This feature ships skill body + markdown rubric + content files. The kiln test harness exercises skill behavior end-to-end via fixtures (`plugin-kiln/tests/`). Line/branch coverage is not the relevant metric for skill-prompt code; FR coverage by fixture is. Each FR ties to ≥1 fixture per Phase 4 of tasks.md. |
| III. PRD as Source of Truth | ✅ Pass | spec.md mirrors `docs/features/2026-04-24-claude-md-audit-reframe/PRD.md` verbatim, including the FR-020/FR-021 numbering gap. |
| IV. Hooks Enforce Rules | ✅ Pass | This change does NOT modify any hook. The `/kiln:kiln-claude-audit` skill is propose-diff-only and never edits CLAUDE.md — preserved across all new rules. |
| V. E2E Testing Required | ✅ Pass | Each new rule + override has a dedicated kiln-test fixture under `plugin-kiln/tests/claude-audit-*/` that runs the real skill end-to-end. |
| VI. Small, Focused Changes | ✅ Pass | Skill body grows ~200 lines (PRD's own estimate); rubric grows ~100 lines for new rule entries + Convention Notes. Each change is local; no new abstractions. |
| VII. Interface Contracts | ✅ Pass | `contracts/interfaces.md` defines the rubric rule schema extension, the override config grammar extension, the audit output rendering extension, and the guidance file shape. |
| VIII. Incremental Task Completion | ✅ Pass | Tasks split per-FR cluster across user stories; `[X]` marked immediately on each task; commit per phase. |

**No violations** — Complexity Tracking section is empty.

## Project Structure

### Documentation (this feature)

```text
specs/claude-md-audit-reframe/
├── plan.md              # This file
├── spec.md              # Sibling — feature spec
├── contracts/
│   └── interfaces.md    # Rule schema, config grammar, output rendering, guidance file shape
├── agent-notes/
│   ├── specifier.md     # Friction note (this agent)
│   ├── impl-audit-logic.md      # (created by impl-audit-logic)
│   └── impl-plugin-guidance.md  # (created by impl-plugin-guidance)
└── tasks.md             # Phase-by-phase task breakdown with owner labels
```

No `research.md`, `data-model.md`, or `quickstart.md` for this feature — the rubric and FR set ARE the data model, and the user-facing entrypoint is the existing slash command.

### Source Code (repository root)

```text
plugin-kiln/
├── skills/
│   └── kiln-claude-audit/
│       └── SKILL.md                          # MODIFIED — impl-audit-logic
├── rubrics/
│   ├── claude-md-usefulness.md               # MODIFIED — impl-audit-logic (new rule entries + Convention Notes)
│   └── claude-md-best-practices.md           # UNCHANGED (cached external rubric)
├── templates/
│   └── vision-template.md                    # READ-ONLY — referenced by `product-undefined`'s scaffold proposal
└── tests/
    ├── claude-audit-classification/          # NEW — impl-audit-logic
    ├── claude-audit-enumeration-bloat/       # NEW — impl-audit-logic
    ├── claude-audit-benefit-missing/         # NEW — impl-audit-logic
    ├── claude-audit-loop-incomplete/         # NEW — impl-audit-logic
    ├── claude-audit-hook-claim-mismatch/     # NEW — impl-audit-logic
    ├── claude-audit-plugins-sync/            # NEW — impl-audit-logic
    ├── claude-audit-plugins-sync-disabled/   # NEW — impl-audit-logic (US1 AC #2 — plugin removal)
    ├── claude-audit-plugins-sync-missing/    # NEW — impl-audit-logic (FR-013 — silent skip)
    ├── claude-audit-product-sync/            # NEW — impl-audit-logic
    ├── claude-audit-product-undefined/       # NEW — impl-audit-logic (FR-025 — top-of-table)
    ├── claude-audit-product-slot-missing/    # NEW — impl-audit-logic (FR-026)
    ├── claude-audit-product-stale/           # NEW — impl-audit-logic (FR-027)
    ├── claude-audit-vision-fenced/           # NEW — impl-audit-logic (FR-023 fenced region)
    ├── claude-audit-vision-overlong/         # NEW — impl-audit-logic (FR-023 >40-line edge case)
    ├── claude-audit-override-section/        # NEW — impl-audit-logic (FR-017 exclude_section_from_classification)
    ├── claude-audit-override-plugin/         # NEW — impl-audit-logic (FR-017 exclude_plugin_from_sync)
    ├── claude-audit-override-product-sync/   # NEW — impl-audit-logic (FR-029 product_sync = false)
    └── claude-audit-existing-rules-regression/  # NEW — impl-audit-logic (SC-010 — existing 7 rules unchanged)

plugin-kiln/.claude-plugin/claude-guidance.md   # NEW — impl-plugin-guidance
plugin-shelf/.claude-plugin/claude-guidance.md  # NEW — impl-plugin-guidance
plugin-wheel/.claude-plugin/claude-guidance.md  # NEW — impl-plugin-guidance
plugin-clay/.claude-plugin/claude-guidance.md   # NEW — impl-plugin-guidance
plugin-trim/.claude-plugin/claude-guidance.md   # NEW — impl-plugin-guidance
```

**Structure Decision**: this is a kiln-plugin-internal change. The skill body extends an existing skill; the rubric extends an existing rubric; the new files are five guidance markdown files (one per first-party plugin) and ~16 new fixture directories under `plugin-kiln/tests/`. There is no `src/` tree to modify. The constitution's `src/` 4-gate enforcement does not apply because this PR ships zero `src/` edits — the spec/plan/tasks gates are enforced for the kiln-internal change itself.

### Implementer file ownership (NON-NEGOTIABLE — disjoint sets)

| Implementer | Files owned (write access) | FRs covered |
|---|---|---|
| `impl-audit-logic` | `plugin-kiln/skills/kiln-claude-audit/SKILL.md`, `plugin-kiln/rubrics/claude-md-usefulness.md`, all `plugin-kiln/tests/claude-audit-*/` fixture directories created in this PR, `specs/claude-md-audit-reframe/agent-notes/impl-audit-logic.md` | FR-001..FR-008, FR-011..FR-016, FR-017, FR-018..FR-019, FR-022..FR-029, FR-030..FR-031 |
| `impl-plugin-guidance` | `plugin-kiln/.claude-plugin/claude-guidance.md`, `plugin-shelf/.claude-plugin/claude-guidance.md`, `plugin-wheel/.claude-plugin/claude-guidance.md`, `plugin-clay/.claude-plugin/claude-guidance.md`, `plugin-trim/.claude-plugin/claude-guidance.md`, `specs/claude-md-audit-reframe/agent-notes/impl-plugin-guidance.md` | FR-009..FR-010 (the file-shape contract) |

The two sets are disjoint — neither implementer touches files owned by the other. If `impl-plugin-guidance` notices the audit logic needs a tweak to read their files correctly, they file an issue / message instead of editing the skill.

## Phase 0 — Research (skipped, with reason)

The team-lead instructions explicitly state: "The PRD's Success Metrics are POST-implementation absolute targets — NOT pre-existing baselines. You do NOT need to run baseline-capture research before /specify." All Success Criteria in `spec.md` are forward-looking targets that only become measurable once the new rules ship. There is no existing system state to baseline against (the rules don't exist yet; the guidance files don't exist yet; vision sync is brand new).

What WOULD warrant a research phase but does not apply here:
- Choosing a new LLM provider — N/A; existing editorial-LLM call convention is reused.
- Selecting a markdown parser — N/A; existing skill already parses CLAUDE.md sections.
- Comparing settings.json shapes between project and user — N/A; both follow Claude Code's known schema.

This decision is documented in `agent-notes/specifier.md` so the auditor doesn't flag a missing research artifact.

## Phase 1 — Design & Contracts

The contract artifact at `specs/claude-md-audit-reframe/contracts/interfaces.md` defines four contract surfaces:

1. **Rubric rule schema extension** — every new rule (`enumeration-bloat`, `benefit-missing`, `loop-incomplete`, `hook-claim-mismatch`, `product-undefined`, `product-slot-missing`, `product-section-stale`) follows the existing `rule_id / signal_type / cost / match_rule / action / rationale / cached` shape from the existing rubric. New rules add a `classification_input` field naming which classification result triggers the rule (e.g., `classification_input: plugin-surface` for `enumeration-bloat`).
2. **Override config grammar extension** — new keys `exclude_section_from_classification`, `exclude_plugin_from_sync`, `product_sync`. Comma-separated values; inline `# reason: ...` required; warning-not-error on missing reason.
3. **Audit output rendering extension** — new sections in `.kiln/logs/claude-md-audit-<TIMESTAMP>.md`: `## Plugins Sync` (always rendered when ≥1 plugin enabled), `## Vision Sync` (always rendered when sync is on), `### Vision.md Coverage` sub-section (under External Findings, per FR-026), Notes section adds the FR-016 reminder line.
4. **Plugin guidance file shape** — `<plugin-dir>/.claude-plugin/claude-guidance.md` with required `## When to use`, optional `## Key feedback loop` and `## Non-obvious behavior`, NO skill enumerations.

See `contracts/interfaces.md` for exact schemas and grammar.

### LLM call shape (single classification call, not per-section)

To stay within the editorial-rule budget and idempotence guarantees, the classification step issues a SINGLE LLM call per audited file. The prompt enumerates every section heading and asks for one classification per heading; the response is parsed as a JSON map `{ "<heading>": "<class>" }`. Failure of this call records ALL sections as `unclassified` (FR-004 default action: keep) — the audit still runs every other rule. This avoids per-section LLM call fan-out and keeps audit run time bounded.

The new editorial rules (`benefit-missing`, `loop-incomplete`) reuse the same per-rule LLM call shape as the existing `duplicated-in-prd` etc.

## Phase 2 — Implementation order (used by tasks.md)

The two implementers work in parallel after Phase 1 contracts land. Their phases are independent:

```
Phase 1: Contracts                                     [specifier — DONE in this commit]
Phase 2 (parallel):
  Phase 2A: impl-audit-logic     ──┐
  Phase 2B: impl-plugin-guidance ──┘
Phase 3: Audit + smoke test + PR                       [auditor]
Phase 4: Retrospective                                 [retrospective]
```

`impl-audit-logic`'s phases (Phase 2A) are themselves split:

```
2A.1  Rubric extension (new rule entries + Convention Notes)
2A.2  Override grammar extension (parsing in skill body)
2A.3  Classification step (single LLM call + map → signal-input wiring)
2A.4  Cheap rules (`enumeration-bloat`, `hook-claim-mismatch`, `product-undefined`, `product-section-stale`, vision-overlong sub-signal)
2A.5  Editorial rules (`benefit-missing`, `loop-incomplete`, `product-slot-missing`)
2A.6  Plugin sync (FR-011..FR-016)
2A.7  Vision sync (FR-022..FR-029)
2A.8  Output rendering extension + idempotence retest
2A.9  Fixtures — one per FR cluster (~16 dirs)
```

`impl-plugin-guidance`'s phases (Phase 2B) are simpler — one phase, five files, all parallel:

```
2B.1  Author all five .claude-plugin/claude-guidance.md files in parallel
2B.2  Self-verify each file matches the FR-009 shape (manual checklist)
```

Phase 2A and 2B can complete independently. Phase 3 audit + smoke test waits on both.

## Risks / Mitigations (carried forward from PRD §Risks)

- **LLM classification accuracy**: misclassifications produce wrong removal proposals. Mitigation: propose-diff-only + FR-017 override + human review.
- **Plugin guidance content quality**: third-party plugins may ship low-quality guidance. Mitigation: first-party reference implementations set the bar (impl-plugin-guidance owns this).
- **Sync collisions**: only one `## Plugins` section is managed. Plugins wanting content elsewhere are unsupported. Documented constraint.
- **Anthropic ships a conflicting field**: FR-019 documents the migration path. Low-probability, high-cost; accepted.
- **Existing CLAUDE.md has a lot of `enumeration-bloat`**: first audit produces large diffs. Expected; piecemeal application is the intended workflow.
- **`hook-claim-mismatch` false positives**: documented in FR-008; accepted.
- **`vision.md` >40 lines without markers**: handled by FR-023 sub-signal under `product-section-stale` per spec Edge Cases.

## Complexity Tracking

> Empty — no constitution violations to justify.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| (none) | (n/a) | (n/a) |
