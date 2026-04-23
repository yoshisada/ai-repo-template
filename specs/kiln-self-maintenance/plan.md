# Implementation Plan: Kiln Self-Maintenance

**Branch**: `build/kiln-self-maintenance-20260423` | **Date**: 2026-04-23 | **Spec**: [spec.md](./spec.md)
**PRD**: `docs/features/2026-04-23-kiln-self-maintenance/PRD.md`

## Summary

Two sub-features, one frame ("kiln applies its own mechanical discipline to itself"):

- **Part A — CLAUDE.md audit mechanism**: versioned rubric artifact + `/kiln:kiln-claude-audit` skill + `/kiln:kiln-doctor` integration + scaffold rewrite + first-pass smoke-test audit. Output is git-diff-shaped review material; never auto-applied.
- **Part B — `/kiln:kiln-feedback` interview**: 3 default + up to 2 area-specific questions (≤5 cap) asked inline between the existing classification gate and the file write. Single in-prompt opt-out. Answers captured in a `## Interview` body section; frontmatter unchanged.

No new runtime dependencies. All work is Markdown (rubric, skill body edits, scaffold) + Bash (diff generation, greppy signals in kiln-doctor). The editorial LLM signal uses the existing agent-step pattern from `/kiln:kiln-audit`.

## Technical Context

**Language/Version**: Markdown (skill/rubric/scaffold/interface contracts) + Bash 5.x (inline shell in skill bodies; `git diff --no-index` for preview generation; `grep` for greppy signals; `jq` for optional JSON manipulation where useful).
**Primary Dependencies**: Existing kiln plugin infrastructure. No new runtime deps (NFR-001).
**Storage**: Filesystem — `plugin-kiln/rubrics/` for the rubric artifact, `.kiln/logs/` for audit output, `.kiln/feedback/` for feedback files (existing), optional `.kiln/claude-md-audit.config` for consumer overrides.
**Testing**: Smoke-test style. Fixture CLAUDE.md + audit invocation → empty-diff assertion for SC-001. Live audit against source-repo CLAUDE.md → non-empty-diff content check for SC-002. Scripted feedback invocations for SC-005..SC-007. No unit test framework — the plugin has none (existing norm).
**Target Platform**: macOS + Linux developer workstations (same as every other kiln skill).
**Project Type**: Claude Code plugin — Markdown skills/agents/rubric + scaffold templates. No compiled artifacts.
**Performance Goals**: `/kiln:kiln-doctor`'s CLAUDE.md subcheck must stay <2s (cheap greppy only). The dedicated audit skill has no latency target — it runs on demand and can spend LLM tokens on the editorial signal.
**Constraints**: Idempotent output (NFR-002). No wheel/MCP/background from feedback interview (NFR-003). Grep-discoverable rubric (NFR-004). No auto-apply of CLAUDE.md edits (FR-004).
**Scale/Scope**: Source repo CLAUDE.md ≈140 lines today; scaffold ≈137 lines; both expected to shrink substantially after Phase V. ~21 tasks across 6 phases, split between two implementers.

## Constitution Check

| Principle | Status | Notes |
|---|---|---|
| I. Spec-First Development (NON-NEGOTIABLE) | PASS | spec.md committed before any implementation. Every FR maps back to a PRD FR. |
| II. 80% Test Coverage Gate | N/A | Plugin has no unit test harness. Smoke-test verification (fixture + live) covers each SC. |
| III. PRD as Source of Truth | PASS | Spec and plan derive FRs/SCs directly from `docs/features/2026-04-23-kiln-self-maintenance/PRD.md`. No divergence. |
| IV. Hooks Enforce Rules | PASS | Hooks enforce spec+plan+tasks+[X] gate on `src/` — this feature touches `plugin-kiln/` and skill bodies, which are always-allow per the hook policy. Commit-hook blocks .env automatically. |
| V. E2E Testing Required | PASS (adapted) | Smoke-test equivalent: Phase V runs the audit skill against real source-repo CLAUDE.md; Phase U verifies interview via scripted invocation. |
| VI. Small, Focused Changes | PASS | Two implementers split on track lines; no file owned by both. Rubric ≤200 lines; skill body delta bounded. |
| VII. Interface Contracts Before Implementation (NON-NEGOTIABLE) | PASS | `contracts/interfaces.md` locks rubric schema, audit I/O, kiln-doctor subcheck signature, scaffold shape, interview schema, and feedback body shape before any Phase S/T/U task starts. |
| VIII. Incremental Task Completion (NON-NEGOTIABLE) | PASS | tasks.md structured so each task is a single reviewable unit; implementers mark `[X]` immediately and commit after each phase. |

No violations — Complexity Tracking section intentionally empty.

## Locked Decisions

These five decisions are final for this feature. Implementers must not second-guess them; any deviation requires updating this plan file first.

### Decision 1 — Rubric location + override path

- **Plugin-embedded default (authoritative)**: `plugin-kiln/rubrics/claude-md-usefulness.md`. Ships with the plugin. Version-locked to the plugin release.
- **Consumer override (optional)**: `.kiln/claude-md-audit.config` at the consumer repo root. Plain key-value format matching the `.shelf-config` family (same key/value, `=` or `:` separator). No YAML, no JSON, no new parser.
- **Precedence rule**: **per-rule merge with repo override winning**. For each rule ID in the plugin default, if the same rule ID appears in the consumer's `.kiln/claude-md-audit.config`, the consumer value replaces it; otherwise the plugin default applies. Rule IDs not present in the plugin default but present in the override are ignored with a warning (forces the consumer to extend the plugin rubric via an upstream PR, not by drift).
- **Malformed-override behavior**: audit warns `claude-md-audit.config: unparseable at line N; falling back to plugin defaults` and proceeds with defaults only. Never silently applies a half-parsed override.

### Decision 2 — Editorial LLM cost strategy

- **Locked to PRD option (c) — split the two invocation paths.**
  - `/kiln:kiln-doctor`'s CLAUDE.md subcheck runs **only cheap greppy signals** from the rubric (load-bearing grep + freshness threshold checks by line count). No LLM calls. Must complete in <2s so doctor stays snappy.
  - The dedicated `/kiln:kiln-claude-audit` skill runs **the full rubric**, including editorial LLM signals for staleness and duplication against `docs/PRD.md` and `.specify/memory/constitution.md`. LLM calls happen here.
- Rejected (a) flag-gated editorial — adds a flag the maintainer has to remember; two invocations now mean two different surfaces.
- Rejected (b) content-hash caching — reasonable but overkill for a file audited on demand; can be added later if token cost becomes real pain. The rubric schema reserves a `cached: true` field in the signal definition to make future adoption mechanical.
- Signal definitions in the rubric MUST declare `cost: cheap | editorial` so the doctor subcheck can filter. The audit skill ignores the field (runs everything).

### Decision 3 — Scaffold rewrite scope

- **Locked to minimal skeleton.** Per-plugin READMEs (tracked in `.kiln/issues/2026-04-22-plugin-documentation.md`) carry the canonical-commands surface. The scaffolded `plugin-kiln/scaffold/CLAUDE.md` does NOT enumerate plugins or their commands.
- **Exact skeleton shape** (locked in `contracts/interfaces.md` §Consumer Scaffold Template Shape):
  - `# <Project Name> — Claude Code Instructions` (H1; project-name placeholder replaced by `init.mjs`)
  - `## Quick Start` — one-line pointer to `/kiln:kiln-next` + one-line pointer to `/kiln:kiln-init` for first-time setup. No more; no session-prompt reference (broken today).
  - `## Mandatory Workflow` — the 4 numbered steps (Read Constitution → /specify → /plan → /tasks → /implement) as short bullets, no sub-headings. 4-gate hooks mentioned in one line, not a section.
  - `## Available Commands` — ONE line per command class pointing to `/kiln:kiln-next` as the discovery entrypoint (e.g., `run /kiln:kiln-next at session start — it surfaces the right command for your current state`). No enumerated command list (moves to per-plugin READMEs).
  - `## Security` — unchanged from today (2-line block about .env + hooks).
- **What's explicitly removed**: "Implementation Rules", "File Organization" section (consumers vary), "Hooks Enforcement (4 Gates)" detail block (shortened to 1 line), "Versioning" (consumers don't own this — the plugin does), plus the full Available Commands enumeration.
- **Target length**: ≤40 lines. Current scaffold is 137 lines; the rewrite is substantial (SC-003 >50% lines changed).

### Decision 4 — Interview question count

- **Locked to 3 defaults + up to 2 area-specific = 5 max.**
- **3 default questions (exact wording)**:
  1. `What does "done" look like for this feedback? Describe the observable outcome.`
  2. `Who triggers the change, and when? (ad-hoc skill, hook, background agent, part of an existing skill, human maintainer decision…)`
  3. `What's the scope? Just this repo, consumer repos too, or other plugins as well?`
- **Area → add-on map** (exact wording; 2 questions per substantive area, 0 for `other`):
  - `mission`: (a) `Which part of the stated mission does this change, extend, or contradict?` (b) `Who does this change the product FOR — and does that change the target user?`
  - `scope`: (a) `What's newly in scope after this change, and what (if anything) moves out of scope?` (b) `Is there an existing feature or plugin this supersedes or narrows?`
  - `ergonomics`: (a) `Which existing friction point does this resolve, and how will you know it's gone?` (b) `Is there a paired tactical backlog entry in .kiln/issues/ that this feedback pairs with? (path, or "none")`
  - `architecture`: (a) `What structural boundary or plugin shape does this change?` (b) `What does the rollout look like — one PR, staged, or a migration?`
  - `other`: no add-ons (total = 3 questions).
- Rejected 3+3=6 — fatigue risk on every feedback entry. 5 cap matches the PRD's "3–6 max" with a bias toward the lower end.

### Decision 5 — Interview skip UX

- **Locked to in-prompt opt-out as the LAST option at every interview prompt.** No CLI flag (matches clay-ideation-polish precedent — no flags on interactive skills).
- **Exact wording** (verbatim, last option at each prompt): `skip interview — just capture the one-liner`
- **Behavior on skip**: skill proceeds directly to file write with no `## Interview` section. Body equals raw `$ARGUMENTS` description. Frontmatter unchanged.
- **Scope of the skip**: skipping at ANY prompt (first or mid-interview) terminates the interview and writes immediately. The section, if any partial answers were collected, is DROPPED — skip is all-or-nothing. This keeps output shape binary: either full `## Interview` section or none.

## Project Structure

### Documentation (this feature)

```text
specs/kiln-self-maintenance/
├── spec.md                        # committed
├── plan.md                        # this file
├── tasks.md                       # next
├── contracts/
│   └── interfaces.md              # rubric schema + audit I/O + kiln-doctor signature + scaffold shape + interview schema + feedback body shape
└── agent-notes/
    └── specifier.md               # friction notes (written before Task #1 complete)
```

### Source Code (repository root)

```text
plugin-kiln/
├── rubrics/
│   └── claude-md-usefulness.md                     # NEW — Phase R (FR-002, FR-003)
├── skills/
│   ├── kiln-claude-audit/
│   │   └── SKILL.md                                # NEW — Phase S (FR-001, FR-004, FR-005)
│   ├── kiln-doctor/
│   │   └── SKILL.md                                # EDIT — Phase S (add CLAUDE.md subcheck; FR-001)
│   └── kiln-feedback/
│       └── SKILL.md                                # EDIT — Phase U (add interview steps 4b/4c; FR-007..FR-010)
└── scaffold/
    └── CLAUDE.md                                   # REWRITE — Phase T (FR-006)

.kiln/logs/
└── claude-md-audit-<timestamp>.md                  # OUTPUT (not committed beyond Phase V baseline)

CLAUDE.md                                           # EDIT in Phase V (FR-011, SC-008)
```

**Structure Decision**: Two parallel track-lines — `impl-claude-audit` owns `plugin-kiln/rubrics/`, `plugin-kiln/skills/kiln-claude-audit/`, `plugin-kiln/skills/kiln-doctor/`, `plugin-kiln/scaffold/CLAUDE.md`, and the Phase V edits to `CLAUDE.md`. `impl-feedback-interview` owns `plugin-kiln/skills/kiln-feedback/SKILL.md`. No file has two owners. Phases S and T are parallelizable under `impl-claude-audit`; Phase U is fully parallel with the A-track.

## Phase Overview

| Phase | Scope | Owner | Depends on | Parallel with |
|---|---|---|---|---|
| R | Research + Rubric artifact | impl-claude-audit | — | U (different file) |
| S | Audit skill + kiln-doctor subcheck | impl-claude-audit | R | U, T |
| T | Scaffold rewrite | impl-claude-audit | R (reads rubric for audit-clean check) | U, S |
| U | Feedback interview mode | impl-feedback-interview | — (independent) | R, S, T |
| V | First audit pass + accepted edits | impl-claude-audit | S, T | U |
| W | SMOKE.md + smoke-results docs | last-lander | R, S, T, U, V | — |

impl-claude-audit gets ≈15 tasks (Phases R, S, T, V + some of W); impl-feedback-interview gets ≈5 tasks (Phase U + some of W). Total target ≤21.

## Complexity Tracking

> No Constitution Check violations — intentionally empty.
