# Implementation Plan: Vision Tooling

**Branch**: `build/vision-tooling-20260427` | **Date**: 2026-04-27 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/vision-tooling/spec.md`

## Summary

Turn `.kiln/vision.md` from prose into a live instrument. Four cooperating themes:

- **A — Simple-params CLI**: Add section-targeted `--add-*` / `--update-*` flags to `/kiln:kiln-roadmap --vision`. Atomic temp+mv writes via `.kiln/.vision.lock`. Skips coached interview when any simple-params flag is present. Reuses existing shelf mirror dispatch.
- **B — Vision-alignment check**: New mode `/kiln:kiln-roadmap --check-vision-alignment`. Walks open `.kiln/roadmap/items/*.md`, LLM-maps each to vision pillars, emits a 3-section report (Aligned / Multi-aligned / Drifters) with the inference-caveat header verbatim. Report-only.
- **C — Forward-looking coaching**: At end of every coached `--vision` interview run (NOT simple-params), opt-in prompt offers ≤5 evidence-cited suggestions tagged gap/opportunity/adjacency/non-goal-revisit. Per-suggestion accept/decline/skip. Declined suggestions persist under `.kiln/roadmap/items/declined/` for dedup.
- **D — Win-condition scorecard**: New skill `/kiln:kiln-metrics`. Orchestrator + 8 extractor scripts at `plugin-kiln/scripts/metrics/extract-signal-{a..h}.sh` produce a tabular scorecard against this repo's six-month signals. Graceful degrade to `unmeasurable`. Writes to stdout AND `.kiln/logs/metrics-<timestamp>.md`.

Implementation substrate: shell scripts + skill markdown — same as the rest of `plugin-kiln/`. LLM steps (Theme B mappings, Theme C suggestions) reuse the coach-driven-capture Claude-CLI substrate (PR #157). All vision-mutating writes use temp+mv + `.kiln/.vision.lock` (mirroring the `.shelf-config.lock` pattern). Tests live under `plugin-kiln/tests/` as shell-only fixtures executed by the `kiln-test` harness (PR #189 convention).

## Technical Context

**Language/Version**: Bash 3.2+ (macOS default) and Bash 4+ where `flock` is available; markdown for skill definitions.
**Primary Dependencies**: `jq` (already required across plugin-kiln), `awk`/`sed` (POSIX), `flock` (Linux; gracefully degrade on macOS — `.shelf-config.lock` precedent), `git`, `claude` CLI for LLM-mediated steps (PR #157 substrate), existing `plugin-kiln/scripts/roadmap/*.sh` helpers (parse, validate, update-state, list-items).
**Storage**: File-based — `.kiln/vision.md`, `.kiln/roadmap/items/`, `.kiln/roadmap/items/declined/` (NEW dir), `.kiln/logs/metrics-*.md` (NEW). Lockfile at `.kiln/.vision.lock` (NEW, gitignored).
**Testing**: `plugin-kiln/tests/<feature>/run.sh` shell fixtures invoked via the `kiln-test` harness. Coverage gate via assertion-block counts (PR #189 convention).
**Target Platform**: Local dev machine (macOS-first; Linux for CI smoke tests). Plugin runs inside Claude Code harness; helpers are pure shell so they work in `claude --print` subprocess shells too.
**Project Type**: CLI tool / Claude Code plugin extension. Internal-first (NFR-002): Theme D is sized for THIS repo's eight signals.
**Performance Goals**: SC-001 — simple-params invocation completes in < 3 seconds wall-clock from invocation to file-on-disk. Theme D scorecard: no formal target (quarterly cadence); informal target ≤ 30 seconds for the 8-extractor sweep on this repo's current state.
**Constraints**: NFR-003 atomic writes; NFR-005 byte-identical fallback path when no new flags; NFR-001 deterministic output for A/B-shape/D-extractors. No new external services; no new npm deps.
**Scale/Scope**: One vision file (~50 lines), ~50–200 open roadmap items at any time, 8 fixed signals in V1.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Article | Constraint | Plan compliance |
|---|---|---|
| I. Spec-First | Spec must exist with FRs + acceptance scenarios before implementation. | `specs/vision-tooling/spec.md` exists with FR-001..FR-022, NFR-001..005, SC-001..010, four user stories with Given/When/Then. PASS. |
| II. 80% Coverage | New/modified code ≥80% line+branch. Shell-only: assertion-block counts (PR #189). | Each Theme owns a `plugin-kiln/tests/<theme>/run.sh` fixture; coverage = ratio of code-paths exercised by assertion blocks. Plan budgets per-theme assertion floors (Theme A ≥ 12, B ≥ 8, C ≥ 10, D ≥ 16). PASS. |
| III. PRD Source of Truth | Specs must not contradict PRD. | Spec preserves PRD FR/NFR/SC numbering verbatim; FR-021/FR-022 only resolve PRD OQ-1/OQ-2 (additive, not contradictory). PASS. |
| IV. Hooks Enforce Rules | 4-gate hook blocks `src/` edits without spec+plan+tasks+`[X]`. | This repo's hook target is `src/`; this feature touches `plugin-kiln/`, which is not under `src/` (this is the plugin source repo, not a consumer). The 4-gate still applies via spec/plan/tasks artifacts. PASS — once tasks.md ships and at least one task is `[X]`. |
| V. E2E Testing | CLI/user-facing tools need E2E tests against compiled artifact. | Each theme's tests invoke real `claude --print` subprocesses (kiln-test harness pattern) against `/tmp/kiln-test-<uuid>/` fixtures. PASS. |
| VI. Small, Focused | One bounded area per task; files under 500 lines. | Each helper script is single-purpose (atomic-write, validate-flags, walk-items, render-report, dispatch-shelf). Largest file projected: orchestrator for `kiln-metrics` (~250 lines). PASS. |
| VII. Interface Contracts | `contracts/interfaces.md` MUST define exact signatures for every exported function before implementation. | This plan emits `specs/vision-tooling/contracts/interfaces.md` (see below) covering 14 helper scripts + 2 skill orchestrator entry points. PASS. |
| VIII. Incremental Task Completion | Each task `[X]` immediately on completion; commit after each phase. | tasks.md (next phase) emits ordered tasks; `/implement` enforces incremental marking + per-phase commits. PASS by-design. |

**Verdict**: PASS. No violations to justify in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/vision-tooling/
├── plan.md                          # This file
├── spec.md                          # Feature spec (already written)
├── contracts/
│   └── interfaces.md                # Phase-1 contract output (this plan emits)
├── checklists/
│   └── requirements.md              # Spec quality checklist (already written)
├── agent-notes/
│   └── specifier.md                 # Friction notes (specifier writes after tasks.md)
├── tasks.md                         # /tasks output (next phase, NOT this plan)
└── blockers.md                      # /implement output, only if PRD audit finds gaps
```

No `research.md`, `data-model.md`, or `quickstart.md` are emitted: this PRD has no `needs_research:` / `fixture_corpus:` / `empirical_quality:` frontmatter (Phase 1.5 probe = `skip`); no NEEDS CLARIFICATION markers in the spec; data model is fully captured in spec.md `Key Entities`; quickstart for an internal CLI extension is the SKILL.md help text itself.

### Source Code (repository root)

```text
plugin-kiln/
├── skills/
│   ├── kiln-roadmap/
│   │   └── SKILL.md                          # MODIFIED: add --add-*, --update-*, --check-vision-alignment, opt-in forward-pass prompt + dispatch
│   └── kiln-metrics/                         # NEW skill dir
│       └── SKILL.md                          # NEW
├── scripts/
│   ├── roadmap/                              # existing dir — add helpers below
│   │   ├── vision-write-section.sh           # NEW (FR-001/002/003 atomic write)
│   │   ├── vision-flag-validator.sh          # NEW (FR-005 mutual-exclusion)
│   │   ├── vision-section-flag-map.sh        # NEW (FR-021 flag↔section table)
│   │   ├── vision-shelf-dispatch.sh          # NEW (FR-004 shelf mirror dispatch wrapper)
│   │   ├── vision-alignment-walk.sh          # NEW (FR-006 walk open items)
│   │   ├── vision-alignment-map.sh           # NEW (FR-007 LLM map item→pillars)
│   │   ├── vision-alignment-render.sh        # NEW (FR-008 emit 3-section report)
│   │   ├── vision-forward-pass.sh            # NEW (FR-010/011 opt-in prompt + suggestion gen)
│   │   ├── vision-forward-decision.sh        # NEW (FR-012 per-suggestion accept/decline/skip)
│   │   ├── vision-forward-decline-write.sh   # NEW (FR-013/022 declined-record writer)
│   │   └── vision-forward-dedup-load.sh      # NEW (FR-013 declined-set loader)
│   └── metrics/                              # NEW dir
│       ├── orchestrator.sh                   # NEW (FR-015/019 walk + aggregate + write log)
│       ├── render-row.sh                     # NEW (FR-016 column shape)
│       ├── extract-signal-a.sh               # NEW
│       ├── extract-signal-b.sh               # NEW
│       ├── extract-signal-c.sh               # NEW
│       ├── extract-signal-d.sh               # NEW
│       ├── extract-signal-e.sh               # NEW
│       ├── extract-signal-f.sh               # NEW
│       ├── extract-signal-g.sh               # NEW
│       └── extract-signal-h.sh               # NEW
└── tests/
    ├── vision-simple-params/                 # NEW (Theme A)
    │   └── run.sh
    ├── vision-alignment-check/               # NEW (Theme B)
    │   └── run.sh
    ├── vision-forward-pass/                  # NEW (Theme C, mock-LLM via env-var)
    │   └── run.sh
    ├── kiln-metrics/                         # NEW (Theme D)
    │   └── run.sh
    └── vision-coached-back-compat/           # NEW (NFR-005, fixture-baseline)
        ├── run.sh
        └── fixtures/
            └── pre-prd-coached-output.txt    # captured BEFORE any code edits

.kiln/
├── .vision.lock                              # NEW (gitignored, runtime)
├── roadmap/items/declined/                   # NEW (FR-022)
└── logs/metrics-<timestamp>.md               # NEW (runtime; .kiln/logs/ is gitignored)

.gitignore                                    # MODIFIED: add .kiln/.vision.lock if not already covered
plugin-kiln/.claude-plugin/plugin.json        # MODIFIED: register kiln-metrics skill
```

**Structure Decision**: extend `plugin-kiln/` in place. New helper scripts live under existing or new subdirectories of `plugin-kiln/scripts/`. New skill `kiln-metrics` gets its own dir under `plugin-kiln/skills/`. Tests follow PR #189's per-feature `run.sh`-fixture convention. No new top-level dirs; no new tooling dependencies; the entire feature is `bash + markdown + claude CLI`. The plugin manifest `plugin-kiln/.claude-plugin/plugin.json` is the only metadata file to touch (registers the new skill).

## Phase 0 — Research

Status: **SKIPPED** (no NEEDS CLARIFICATION markers in spec; no `needs_research:` frontmatter on PRD).

The four areas that could plausibly have triggered research are pre-resolved:

1. **Atomic write pattern** — already established by `.shelf-config.lock` and `plugin-shelf/scripts/shelf-counter.sh`'s `flock`-when-available, RMW-with-±1-drift-otherwise pattern (FR-006 of report-issue-speedup). Reuse verbatim.
2. **LLM-mediated semantic mapping** — `read-project-context.sh` from PR #157 (coach-driven-capture-ergonomics) is the canonical grounding source; `claude --print` is the canonical invocation surface. Reuse verbatim.
3. **Per-extractor signal model** — PRD FR-018 mandates per-extractor scripts; the rest is implementation. Each extractor reads its own data source (git log / `.kiln/` / `.wheel/history/` / `docs/features/`) and emits a single row line. No research needed; signals (a)–(h) are fixed in `.kiln/vision.md` lines 25–32.
4. **Pre-PRD coached-interview fixture (NFR-005 / SC-009)** — captured by Phase-1 task T001 (see tasks.md) BEFORE any edits to `kiln-roadmap/SKILL.md`. This is the byte-identity baseline.

## Phase 1 — Design & Contracts

### Phase 1.5 — Research-first plan-time agents

Probe outcome: **`skip`**. PRD has no `needs_research`, no `fixture_corpus`, no `empirical_quality`. Per the plan-skill outline ("If `ROUTE == skip`: return immediately. NO spawn. NO net-new subprocess. NO further work in Phase 1.5."), Phase 1.5 is a structural no-op for this PRD.

### 1.1 — Data model

Captured in spec.md `Key Entities` section. No separate `data-model.md` because all entities are file-based and externally observable (vision file structure, roadmap item frontmatter, scorecard row shape, suggestion shape). Recap:

- **Vision file** — `.kiln/vision.md` with YAML frontmatter `last_updated:` + named markdown sections (mapped via FR-021).
- **Roadmap item** — existing structured-roadmap artifact; Theme B walks; Theme C writes `kind: non-goal` declined records under `.kiln/roadmap/items/declined/`.
- **Vision pillar** — bullet under *Guiding constraints* OR a constraint clause within *What it is not*.
- **Forward-pass suggestion** — ephemeral `{title, tag ∈ {gap, opportunity, adjacency, non-goal-revisit}, body, evidence_cite}`; persisted only on decline.
- **Scorecard row** — `{signal_id ∈ a..h, signal_label, current_value, target, status ∈ {on-track, at-risk, unmeasurable}, evidence}`.
- **Section-flag mapping** — single-source table maintained in `vision-section-flag-map.sh`:

  | Flag | Section header | Operation |
  |---|---|---|
  | `--add-mission` | `## What we are building` | append paragraph (the section is prose, not a bullet list) — V1 appends as new paragraph; coached interview required to mutate existing prose |
  | `--update-what-we-are-building` | `## What we are building` | replace section body |
  | `--add-out-of-scope` | `## What it is not` | append paragraph |
  | `--update-what-it-is-not` | `## What it is not` | replace section body |
  | `--add-success-signal` | `## How we'll know we're winning` (under "Six-month signals:" prefix) | append new bullet (typically next letter after `(h)`, e.g., `(i)`) |
  | `--add-constraint` | `## Guiding constraints` | append bullet |
  | `--add-non-goal` | `## What it is not` | append bullet (note: differs from `--add-out-of-scope` which appends a paragraph; `--add-non-goal` is bullet-form for terse capture) |

  Note on `--add-mission` / `--add-out-of-scope` semantics: PRD FR-001 lists them as *append* flags, but the target sections are prose, not bullets. V1 appends a new blank-line-separated paragraph; it does NOT mutate existing prose. In-place edits to existing prose require the coached interview (consistent with the spec's `--success-signal` Assumption: append-only via simple-params).

### 1.2 — Contracts

Written to `specs/vision-tooling/contracts/interfaces.md`. Covers:

- 11 new helper scripts under `plugin-kiln/scripts/roadmap/` (Themes A/B/C).
- 1 orchestrator + 1 row-renderer + 8 extractors under `plugin-kiln/scripts/metrics/` (Theme D).
- 2 skill orchestrator entry points: `kiln-roadmap/SKILL.md` (modified) + `kiln-metrics/SKILL.md` (new).

Every script has: invocation signature (positional args + flag args), env-var inputs, stdout shape, exit codes, side-effects, error-output shape. Mock injection points (`KILN_TEST_MOCK_LLM_DIR`) are declared for LLM-mediated helpers per CLAUDE.md Rule 5.

### 1.3 — Quickstart

Quickstart for this feature = the new SKILL.md `--help` text + the four spec user stories. No separate `quickstart.md` is emitted; the SKILL.md edits in Theme A and Theme D ARE the quickstart documentation.

### 1.4 — Agent context update

Run as part of `/implement`'s pre-edit phase, not here. The new skill `kiln-metrics` will be picked up by the agent context updater on next session start.

## Implementation Phases

Phasing is dictated by spec priorities (P1 → P3) and the NFR-005 fixture-capture ordering constraint.

### Phase 0 — Pre-edit fixture capture (T001)

**Must run BEFORE any code edits.** Captures the pre-PRD `kiln-roadmap --vision` coached-interview output against a fixture vision.md, stored at `plugin-kiln/tests/vision-coached-back-compat/fixtures/pre-prd-coached-output.txt`. This is the SC-009 / NFR-005 baseline.

Acceptance: file exists, ≥1 byte, committed. Without this baseline, no later phase can assert byte-identity.

### Phase A — Theme A: Simple-params CLI (P1)

**Goal**: `/kiln:kiln-roadmap --vision --add-* / --update-*` works end-to-end with atomic writes, last_updated bump, shelf dispatch (when configured), flag-conflict refusal.

**Tasks (per-FR)**:
- FR-021: `vision-section-flag-map.sh` — exports the single-source mapping table.
- FR-005: `vision-flag-validator.sh` — parses argv, asserts mutual exclusion, exits non-zero with shaped error before any I/O.
- FR-001/FR-002/FR-003: `vision-write-section.sh` — atomic temp+mv with `.kiln/.vision.lock` (flock-when-available; ±1 drift accepted on macOS per `shelf-counter.sh` precedent), bumps `last_updated:` BEFORE writing the body change.
- FR-004: `vision-shelf-dispatch.sh` — wraps existing dispatch logic, warns-and-continues when `.shelf-config` missing.
- Integration: edit `kiln-roadmap/SKILL.md` to route `--add-*` / `--update-*` → validator → write → dispatch; SKIP coached interview on any simple-params flag (FR-001 last sentence + FR-014 invariant).

**Tests**:
- `plugin-kiln/tests/vision-simple-params/run.sh` — assertions for SC-001 (3-second budget, last_updated bump, verbatim text under correct section), SC-002 (flag-conflict refusal + empty diff), FR-004 (warn-and-continue with missing `.shelf-config`), FR-001 final sentence (interview skip).
- `plugin-kiln/tests/vision-coached-back-compat/run.sh` — assertion that `kiln-roadmap --vision` with NO new flags produces output byte-identical to `pre-prd-coached-output.txt` (SC-009).

**Independently shippable**: yes. Theme A has no dependency on B/C/D.

### Phase B+C — Theme B + Theme C (P2)

Bundled because Theme C's `--promote` hand-off and the forward-pass prompt live in the same `--vision` interview tail; splitting them would require touching the same SKILL.md region twice.

**Theme B Tasks**:
- FR-006: `vision-alignment-walk.sh` — emits open-item paths (`status != shipped` AND `state != shipped`).
- FR-007: `vision-alignment-map.sh` — LLM-mediated mapping via `claude --print`; reuses `read-project-context.sh` from PR #157. Mock injection via `KILN_TEST_MOCK_LLM_DIR`.
- FR-008/FR-009: `vision-alignment-render.sh` — 3-section report with caveat header verbatim; report-only.
- Integration: edit `kiln-roadmap/SKILL.md` to dispatch `--check-vision-alignment` → walk → map → render → stdout.

**Theme C Tasks**:
- FR-010: edit coached `--vision` interview tail in `kiln-roadmap/SKILL.md` to emit the literal opt-in prompt with default `N`.
- FR-011: `vision-forward-pass.sh` — generates ≤5 suggestions with required tag set + evidence cites; LLM-mediated.
- FR-013/FR-022: `vision-forward-dedup-load.sh` — loads `.kiln/roadmap/items/declined/*.md` titles + tags; passes as exclusion list to forward-pass.
- FR-012: `vision-forward-decision.sh` — per-suggestion confirm-never-silent prompt (accept/decline/skip).
- FR-013/FR-022: `vision-forward-decline-write.sh` — writes `kind: non-goal` declined record under `.kiln/roadmap/items/declined/`.
- FR-014: prompt-emission guard — coached path only; simple-params flow MUST NOT call vision-forward-pass.sh (asserted by SC-010 test).

**Tests**:
- `plugin-kiln/tests/vision-alignment-check/run.sh` — SC-003 (3 sections in order, caveat header verbatim, empty git diff), FR-006 (shipped items excluded), FR-008 (multi-aligned section populated when fixture has dual-pillar item), FR-009 (no mutation).
- `plugin-kiln/tests/vision-forward-pass/run.sh` — SC-004 (literal prompt, default-N exit), SC-005 (≤5 suggestions, required tags, evidence cites, accept/decline/skip routing), SC-006 (dedup), SC-010 (simple-params path emits zero forward-pass prompts).

### Phase D — Theme D: Win-condition scorecard (P3)

**Tasks**:
- FR-015/FR-019: `metrics/orchestrator.sh` — walks repo state, calls each extractor, aggregates rows, writes log at `.kiln/logs/metrics-<UTC-timestamp>.md` AND stdout.
- FR-016: `metrics/render-row.sh` — emits one row in the prescribed pipe-delimited shape.
- FR-017: graceful-degrade — orchestrator catches non-zero extractor exits and substitutes `unmeasurable` row + reason.
- FR-018: `metrics/extract-signal-{a..h}.sh` — eight scripts, one per signal:
  - `(a)`: count of merged PRs with the `build-prd` label that closed an `idea-*` issue with ≤2 escalation events (proxy for "zero-to-few human interventions").
  - `(b)`: count of confirm-never-silent escalations from `.wheel/history/` over the last 90 days (target: trending down or stable; status from delta).
  - `(c)`: count of `.kiln/issues/`, `.kiln/feedback/`, and `.kiln/roadmap/items/` entries that became PRDs in `docs/features/` (matched by `derived_from:`).
  - `(d)`: count of `.kiln/mistakes/` entries that produced a manifest-improvement proposal that landed (matched by Obsidian `@inbox/closed/`).
  - `(e)`: count of `.kiln/logs/hook-*.log` entries showing a blocked `src/` edit attempt + `.env` commit attempt (last 30 days).
  - `(f)`: shelf + trim sync drift count from latest `.shelf-config` / `.trim/` audit logs.
  - `(g)`: smoke-test pass rate from `plugin-kiln/tests/` runs over the last 30 days.
  - `(h)`: count of declined-records in `.kiln/roadmap/items/declined/` matched against external feedback sources.
- Skill: new `plugin-kiln/skills/kiln-metrics/SKILL.md` invokes orchestrator; plugin manifest registration.

**Tests**:
- `plugin-kiln/tests/kiln-metrics/run.sh` — SC-007 (8 rows, prescribed columns, both stdout + log), SC-008 (force one extractor missing → unmeasurable + exit 0), FR-019 (timestamped log, no overwrite of prior log), FR-018 (each extractor invocable in isolation).

## Risks & Mitigations (carried from PRD)

- **R-1 Theme B determinism caveat visibility** — caveat header is verbatim, terse, and includes the V2 schema-extension pointer (see FR-007 spec text).
- **R-2 Theme C forward-pass quality** — hard cap ≤5 + evidence-cite-required + decline-persistence; iterate after first month per PRD R-2.
- **R-3 Theme D V1 scope drift** — extractors are fixed at 8; FR-018 keeps them per-script so consumer-rubric generalization (V2) is purely additive.
- **R-4 NFR-005 baseline-capture ordering** — addressed by Phase 0 / T001: fixture captured BEFORE any code edits; if T001 is skipped, Theme A is blocked.

## Complexity Tracking

(empty — no Constitution Check violations to justify)
