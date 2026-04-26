---
description: "Implementation plan for claude-audit-quality — substance rules + output discipline + retro insight-score"
---

# Implementation Plan: Claude-Audit Quality

**Feature Branch**: `build/claude-audit-quality-20260425`
**Spec**: `specs/claude-audit-quality/spec.md`
**Research**: `specs/claude-audit-quality/research.md` (Baseline by `researcher-baseline`, 2026-04-25)
**PRD**: `docs/features/2026-04-26-claude-audit-quality/PRD.md`

## Summary

Raise `/kiln:kiln-claude-audit`'s output bar from mechanics to substance. Six surface changes:

1. **Output discipline** (Theme A) — every fired signal produces a concrete artifact: unified diff, `inconclusive` with one of three legitimate reasons, or `keep`. No comment-only diffs, no "expensive" `inconclusive` punts.
2. **Substance rules** (Theme B) — four new rubric rules (`missing-thesis`, `missing-loop`, `missing-architectural-context`, `scaffold-undertaught`) read `CTX_JSON` paths and fire when the audited file fails to teach load-bearing concepts.
3. **Grounded citations + ordering** (Theme C) — every cited project-context signal MUST be primary justification (one-line "remove-citation-and-verdict-changes-because" rationale per finding); audit ordering leads with substance.
4. **Recent-Changes anti-pattern** (Theme D) — new rule `recent-changes-anti-pattern`; circular load-bearing reworded to require prose citation, not rule-`match_rule:` citation.
5. **Sibling-preview convention** (Theme E) — codify `<audit-log>-proposed-<basename>.md` per audited path with proposed diffs; permitted-files list updated; cross-reference rendered in audit log.
6. **Retro insight-score** (Theme F) — `kiln-build-prd` retrospective agent self-rates `insight_score: 1-5` against a new rubric `plugin-kiln/rubrics/retro-quality.md`; team-lead surfaces low scores in pipeline summary.

Two implementer scopes:
- **`impl-claude-audit`** owns Themes A-E (skill body + rubric edits)
- **`impl-tests-and-retro`** owns Theme F (retro agent + retro rubric) AND the five test fixtures (FR-002, FR-005, FR-011, FR-014, FR-019)

## Technical Context

- **Language**: Bash 5.x for skill-side scripts, Markdown for rubric/skill authoring, YAML frontmatter for retro issue body. Python3 (stdlib `json`/`re`) tolerated as fallback for frontmatter parsing — no new runtime dependency.
- **Toolchain**: existing `/kiln:kiln-claude-audit` skill body, `plugin-kiln/rubrics/claude-md-usefulness.md`, `plugin-kiln/rubrics/claude-md-best-practices.md`, `plugin-kiln/scripts/context/read-project-context.sh` (CTX_JSON emitter — assumed stable; reader currently has the jq 1.7.1-apple control-character workaround in place per commit `09590a9`).
- **Editorial pattern**: editorial rules execute in the model's own context — no sub-LLM call. Reference docs (`.kiln/vision.md`, `.specify/memory/constitution.md`, `plugin-kiln/scaffold/CLAUDE.md`, source-repo `CLAUDE.md`) are read via `cat` / `awk` and passed inline.
- **Test harness**: `/kiln:kiln-test plugin-kiln <fixture>` per existing `plugin-kiln/tests/` convention. Each fixture is self-contained with its own scaffolded `.kiln/` if it needs one.
- **Scope binding for NFR-001**: bash-side only (median 0.786 s baseline → ≤ 1.022 s gate). Editorial-LLM time NOT covered. Spec.md NFR-001 documents this exhaustively.
- **Scope binding for NFR-003**: within-scope idempotence only (two runs of same scope on unchanged inputs). New substance rules' bytes ARE expected to differ from pre-PR baseline by definition; carve-out applies to no-X paths only. Spec.md NFR-003 documents this exhaustively.

## Constitution Check

| Article | Compliance |
|---|---|
| I (Spec-First) | ✅ Spec written before code; FR-NN ↔ task IDs maintained 1:1 |
| II (80% Coverage) | ✅ Five fixture-based test scenarios under `plugin-kiln/tests/` cover every new rule; rubric/skill changes are markdown-only and exercised end-to-end via `/kiln:kiln-test` |
| III (PRD as Source of Truth) | ✅ Spec mirrors PRD's FR-001..FR-025, NFR-001..NFR-004, SC-001..SC-008 verbatim; reconciliation per Step 1.5 documented in NFR-001 / NFR-003 / Open Questions |
| IV (Hooks Enforce Rules) | ✅ No hook changes; existing 4-gate enforcement applies to skill/agent/rubric edits |
| V (E2E Testing) | ✅ Five fixtures invoke real `/kiln:kiln-test` subprocesses against `/tmp/kiln-test-<uuid>/` per kiln-test contract |
| VI (Small, Focused) | ✅ Theme partitioning enforces bounded changes; no file > 500 lines targeted |
| VII (Interface Contracts) | ✅ `contracts/interfaces.md` defines every NEW rule's frontmatter shape, sibling-preview file path schema, retro frontmatter keys, audit log section ordering |
| VIII (Incremental Tasks) | ✅ Tasks.md partitions work into A→B→C→D→E phases for impl-claude-audit; Theme F + fixtures phased independently |

No deviations to track.

## Project Structure

### Files this PR touches

```
plugin-kiln/
├── skills/
│   └── kiln-claude-audit/
│       └── SKILL.md                                          # Themes A-E surface changes (impl-claude-audit)
│   └── kiln-doctor/
│       └── SKILL.md                                          # FR-017 recent-changes-overflow handler (impl-claude-audit)
├── rubrics/
│   ├── claude-md-usefulness.md                               # FR-004 preamble + FR-006..FR-009 + FR-016 + FR-018 (impl-claude-audit)
│   └── retro-quality.md                                      # NEW; FR-025 (impl-tests-and-retro)
├── agents/
│   └── _src/
│       └── retrospective.md  (or whatever the retro agent file is) # FR-024 self-rating + frontmatter emit (impl-tests-and-retro)
└── tests/
    ├── claude-audit-no-comment-only-hunks/                   # FR-002 / SC-001 (impl-tests-and-retro)
    ├── claude-audit-editorial-pass-required/                 # FR-005 / SC-002 (impl-tests-and-retro)
    ├── claude-audit-substance/                               # FR-011 / SC-003 (impl-tests-and-retro)
    ├── claude-audit-grounded-finding-required/               # FR-014 / SC-004 (impl-tests-and-retro)
    └── claude-audit-recent-changes-anti-pattern/             # FR-019 / SC-005 (impl-tests-and-retro)

specs/claude-audit-quality/
├── spec.md
├── plan.md
├── research.md          (already authored by researcher-baseline)
├── contracts/
│   └── interfaces.md
├── tasks.md
└── agent-notes/
    ├── researcher-baseline.md   (already authored)
    └── specifier.md             (FR-009 friction note)
```

### Files this PR does NOT touch

- `.specify/memory/constitution.md` — no constitutional change.
- `plugin-kiln/scripts/context/read-project-context.sh` — assumed stable; reader fix is out of scope (flagged as PI by researcher-baseline).
- `plugin-wheel/*` — no wheel-runtime changes.
- `plugin-kiln/templates/*` — no spec/plan/tasks template changes.
- Hooks under `plugin-kiln/hooks/*.sh` — no hook changes.

## Phase 0 — Research

Done. See `specs/claude-audit-quality/research.md` §Baseline. Captured by `researcher-baseline` on 2026-04-25.

Key reconciliation outputs (applied to spec.md):
- NFR-001 binds to bash-side only; editorial-LLM time is not gated. Median 0.786 s, +30 % gate ≤ 1.022 s.
- NFR-003 within-scope idempotence; substance rules' new bytes are expected; carve-out applies to no-X paths.
- `external` is a separate-section concept, not a `signal_type` value; rubric schema unchanged on that axis.
- Baseline references `git rev-parse HEAD == 7058504` — current branch identical to `main` for CLAUDE.md / rubric / best-practices cache / `plugin-kiln/scripts/context/`.

## Phase 1 — Design & Contracts

`contracts/interfaces.md` defines (in this order):

1. **Rubric rule schema (extended)** — substance rules' new fields (`signal_type: substance`, optional `ctx_json_paths:` array enumerating `CTX_JSON` paths the `match_rule:` reads). Action enum reaffirmed; no new actions introduced.
2. **The four substance rules + `recent-changes-anti-pattern` + rubric preamble change** — full frontmatter shape per rule (`rule_id`, `signal_type`, `cost`, `match_rule`, `action`, `ctx_json_paths`, `rationale`, `cached`).
3. **Editorial-pass discipline contract (FR-003 / FR-004)** — rubric preamble's `inconclusive` trigger taxonomy: missing reference, unparseable reference, external-dep failure. "Expensive" is forbidden.
4. **Audit output ordering (FR-010 / FR-015)** — Signal Summary table sort key + Notes section ordering rule.
5. **Sibling-preview file path schema (FR-020)** — basename derivation algorithm + the post-apply state shape.
6. **Audit log cross-reference (FR-022) + footer cleanup convention (FR-023)** — verbatim string formats.
7. **Retro frontmatter keys (FR-024)** — YAML schema for `insight_score:` + `insight_score_justification:`; team-lead summary rendering rule.
8. **Retro substance rubric (FR-025)** — file shape for `plugin-kiln/rubrics/retro-quality.md`.

## Phase 2 — Implementation order

The work decomposes across two implementer scopes. Within `impl-claude-audit`, the five themes phase strictly in order A → B → C → D → E (later themes depend on the rubric/preamble changes earlier themes land). `impl-tests-and-retro` runs in parallel for Theme F (retro agent edits + retro rubric file) but its **fixture work** must wait for `impl-claude-audit` Theme E to complete (fixtures exercise the post-Theme-E skill behavior end-to-end).

```
impl-claude-audit:    [A] → [B] → [C] → [D] → [E]
                                                    \
impl-tests-and-retro: [F retro agent + rubric] -----+--→ [5 fixtures]
                                                    /
                                                  (depends on impl-claude-audit completion)
```

### Phase 2A — `impl-claude-audit` themes A through E (sequential)

- **Theme A** (FR-001..FR-005 — output discipline): rubric preamble change (FR-004), SKILL.md Step 3 contract change (FR-003), Step 3.5 invariant (FR-001). NO new rules added in this theme — it's a discipline change to existing editorial rules.
- **Theme B** (FR-006..FR-011 — substance rules): four new rules in rubric, output ordering rule (FR-010) added to SKILL.md. Substance rules read `CTX_JSON` paths.
- **Theme C** (FR-012..FR-015 — grounded citations): rewording in skill body, project-context-driven row guarantee, substance-pass step reordering (Step 2 before Step 3).
- **Theme D** (FR-016..FR-019 — recent-changes anti-pattern): new rule `recent-changes-anti-pattern`, FR-017 handler updates in `kiln-claude-audit/SKILL.md` + `kiln-doctor/SKILL.md`, FR-018 load-bearing reword.
- **Theme E** (FR-020..FR-023 — sibling preview): permitted-files list update, Step 4.5 in skill body, cross-reference text, footer cleanup string.

### Phase 2B — `impl-tests-and-retro` Theme F (parallel)

- Theme F retro agent edits (FR-024) + retro rubric file (FR-025) — independent of impl-claude-audit; can land at any time.

### Phase 2C — `impl-tests-and-retro` fixtures (after impl-claude-audit completes)

- Five fixtures (FR-002, FR-005, FR-011, FR-014, FR-019), each runnable via `/kiln:kiln-test plugin-kiln <fixture>` per NFR-002.
- Sequencing within fixtures: each is independent of the others; can be authored in any order. They MAY be authored in parallel after Theme E's skill changes are committed.

## Risks / Mitigations (carried forward from PRD §Risks + research.md)

- **R-1** (substance rules editorial cost): pre-filter via cheap grep for vision-pillar phrases before invoking the editorial pass (FR-006). Mitigates NFR-001 latency exposure on the editorial side (informally; NFR-001 binds bash-only by design).
- **R-2** ("primary justification" verifiability): each finding emits a one-line "remove-citation-and-verdict-changes-because" rationale (FR-012). Fixture FR-014 asserts the rationale is present + non-empty.
- **R-3** (NFR-001 latency cap): the bash-side gate is firm (≤ 1.022 s); editorial latency is intentionally outside scope. Auditor flags near-cap (≥ 95 %) as a soft warning per OQ-1.
- **R-4** (retro self-rating reliability): cheapest version per PRD Non-Goal; if drift is observed in practice, escalate to a separate auditor agent in a follow-on PR.
- **R-5** (jq 1.7.1-apple control-character bug, from research.md): reader currently has the `09590a9` workaround. If the workaround degrades during this PR, baseline measurement may shift; auditor re-baselines from a known-clean checkout per researcher-baseline's note 5.

## Complexity Tracking

| Source of Complexity | Why It's Necessary | Why Simpler Doesn't Work |
|---|---|---|
| Substance rules read `CTX_JSON` (multiple paths) | Substance evaluation is grounded against project context (vision, roadmap, plugins, README). | Length / freshness rules are insufficient — they were the "shallow" surface this PRD is correcting. |
| Editorial discipline contract (FR-003) | Without it, editorial rules silently `inconclusive` and the audit's contract is fictional. | A "best-effort" editorial path leaves the same gap the PRD is solving. |
| Sibling-preview files (Theme E) | Side-by-side preview of the post-apply state is the substantive UX win for the maintainer. | Comment-only diffs and overlapping hunks defeat readability at apply time. |
| Within-scope NFR-003 carve-out | Substance rules ADD bytes by definition; cross-PR byte-identity is structurally impossible here. | Demanding cross-PR byte-identity would block this PR on a contradiction. |
| Retro rubric + self-rating prompt (Theme F) | A measurable "did this retro learn anything" signal that ships now. | A separate auditor agent is the next step, not the first step (PRD Non-Goal). |
