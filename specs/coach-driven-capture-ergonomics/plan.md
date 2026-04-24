# Implementation Plan: Coach-Driven Capture Ergonomics

**Branch**: `build/coach-driven-capture-ergonomics-20260424` | **Date**: 2026-04-24 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/coach-driven-capture-ergonomics/spec.md`
**PRD**: `docs/features/2026-04-24-coach-driven-capture-ergonomics/PRD.md` (frozen)

## Summary

Ship a shared project-context reader under `plugin-kiln/scripts/context/` and upgrade four capture surfaces (`/kiln:kiln-roadmap` item interview, `/kiln:kiln-roadmap --vision`, `/kiln:kiln-claude-audit`, `/kiln:kiln-distill`) from cold-start interrogation to coach-from-evidence. The reader is the load-bearing dependency: three implementers consume it (directly or indirectly), and interface stability must be locked before parallel implementation begins.

Primary technical approach: a single Bash + `jq` script (`plugin-kiln/scripts/context/read-project-context.sh`) emits a deterministic JSON snapshot; each consuming skill updates its SKILL.md to invoke the script, parse specific fields with `jq`, and branch accordingly. No new runtime dependencies; no compiled code; no hook-path changes.

## Technical Context

**Language/Version**: Bash 5.x (script bodies), `jq` ≥1.6 (JSON parsing), Markdown (skill prompts + rubric docs).
**Primary Dependencies**: Existing `plugin-kiln/scripts/roadmap/list-items.sh` and `parse-item-frontmatter.sh`; `WebFetch` tool (optional, for FR-014 external best-practices fetch).
**Storage**: File-based — markdown artifacts under `.kiln/`, `docs/features/`, `specs/`; no database, no server state.
**Testing**: Shell-level unit tests via `bats` where practical (reader determinism, slug disambiguation); integration via `/kiln:kiln-test` plugin-skill substrate against `plugin-kiln/tests/` fixtures.
**Target Platform**: macOS + Linux (Bash 5.x / `jq`), invoked by Claude Code as skill bodies. No Windows support required.
**Project Type**: Claude Code plugin (`plugin-kiln/`) — skills (markdown), scripts (bash), templates (markdown).
**Performance Goals**: Project-context reader <2 s on ~50 PRDs + ~100 roadmap items (NFR-001).
**Constraints**: Offline-safe by default (NFR-004); deterministic byte-identical output on unchanged inputs (NFR-002, NFR-003); no PreToolUse-hook invocation of new scripts (NFR-006); `--quick` and single-theme distill paths byte-identical to pre-change (NFR-005).
**Scale/Scope**: 1 new shell script (~150–250 lines), 3 SKILL.md rewrites, 1 new rubric markdown (`claude-md-best-practices.md`), new fixtures + contract tests. Estimated ~800 LOC across scripts + tests.

## Constitution Check

**Gate — Spec-First (Article I)**: spec.md written and committed before any src/ edits. ✅

**Gate — 80% Coverage (Article II)**: New scripts (`read-project-context.sh`, distill multi-theme helpers) ship with `bats` tests; coverage of new branches tracked per task.

**Gate — PRD Source of Truth (Article III)**: PRD frozen; spec cites PRD FR mappings in every FR; no divergence.

**Gate — Hooks (Article IV)**: New scripts are NOT invoked by PreToolUse hooks. Existing hooks unchanged. ✅

**Gate — E2E (Article V)**: `/kiln:kiln-test` substrate runs real `claude --print` subprocesses against fixtures for each of the four surfaces post-implementation.

**Gate — Small, Focused (Article VI)**: Each phase below touches one bounded area; all shell scripts stay <500 lines.

**Gate — Interface Contracts (Article VII)**: `contracts/interfaces.md` published in this plan phase defines the reader's JSON schema + every helper signature before any parallel implementation starts.

**Gate — Incremental Completion (Article VIII)**: `tasks.md` is organized per-FR; each task is committed individually with `[X]` mark.

**No violations requiring complexity-tracking justification.**

## Project Structure

### Documentation (this feature)

```text
specs/coach-driven-capture-ergonomics/
├── spec.md                        # Already written (Phase spec)
├── plan.md                        # This file
├── contracts/
│   └── interfaces.md              # Mandatory — shared reader signatures + per-consumer call sites
├── research.md                    # Short — notes on fixtures + external-fetch caching strategy
├── tasks.md                       # Phase tasks (ownership-tagged)
├── agent-notes/
│   └── specifier.md               # Friction note (written pre-completion)
└── checklists/
    └── requirements.md            # Spec quality checklist (standard kiln artifact)
```

### Source Code (plugin-kiln layout — this is the plugin source repo)

```text
plugin-kiln/
├── scripts/
│   ├── context/                       # NEW — shared project-context reader
│   │   ├── read-project-context.sh    # FR-001 — emits ProjectContextSnapshot JSON
│   │   ├── read-prds.sh               # helper — scans docs/features/*/PRD.md
│   │   ├── read-plugins.sh            # helper — scans plugin-*/.claude-plugin/plugin.json
│   │   └── README.md                  # usage notes + JSON schema ref
│   ├── roadmap/                        # EXISTING — dependency only
│   └── distill/                        # NEW — multi-theme emission helpers
│       ├── select-themes.sh           # FR-017 — multi-select picker (emits selected-theme slugs)
│       ├── disambiguate-slug.sh       # FR-017 — numeric-suffix disambiguation
│       └── emit-run-plan.sh           # FR-018 — run-plan formatter
├── skills/
│   ├── kiln-roadmap/
│   │   └── SKILL.md                   # UPDATED — FR-004/005/006/007 + --vision FR-008..FR-012
│   ├── kiln-claude-audit/
│   │   └── SKILL.md                   # UPDATED — FR-013/014/015/016
│   └── kiln-distill/
│       └── SKILL.md                   # UPDATED — FR-017..FR-021
├── rubrics/
│   ├── claude-md-usefulness.md        # EXISTING — unchanged
│   └── claude-md-best-practices.md    # NEW — cached Anthropic guidance (FR-014)
└── tests/                              # NEW fixtures for /kiln:kiln-test substrate
    ├── project-context-reader-determinism/
    ├── roadmap-coached-interview-basic/
    ├── roadmap-vision-first-run/
    ├── roadmap-vision-re-run/
    ├── claude-audit-project-context/
    └── distill-multi-theme/
```

**Structure Decision**: This is the **plugin source repo** (per CLAUDE.md — "not a consumer project"), so all paths are under `plugin-kiln/`. No `src/` or `tests/` at repo root. Shell + markdown; no compile step.

## Phases

### Phase 0 — Research (low overhead; one document)

Scope: confirm implementation decisions where PRD left room, write them into `research.md`. Output artifacts: `specs/coach-driven-capture-ergonomics/research.md` containing notes on:

1. Fixture approach for `/kiln:kiln-test` — reuse `plugin-kiln/tests/` substrate; each feature area gets one happy-path + one edge-case test.
2. JSON parsing strategy in skill bodies — `jq` pipelines inline in SKILL.md code blocks; no new helpers beyond what's necessary.
3. External best-practices cache strategy — single markdown file with YAML frontmatter carrying `fetched:` date; audit skill calls `WebFetch`, writes to cache on success, falls back on failure.
4. Slug disambiguation algorithm — sort selected themes deterministically (ASC by theme slug), process in order, increment suffix per collision.

Owner: **impl-context-roadmap** produces `research.md` as part of Task-set 1. Other implementers reference it.

### Phase 1 — Design & Contracts (blocks parallel implementation)

Scope: publish `contracts/interfaces.md` with:

- The `read-project-context.sh` script contract: arguments, exit codes, stdout JSON schema (field-by-field), sort guarantees.
- Helper script contracts (`read-prds.sh`, `read-plugins.sh`, `select-themes.sh`, `disambiguate-slug.sh`, `emit-run-plan.sh`).
- Per-consumer call-site contract: exactly how each SKILL.md invokes the reader and which `jq` queries it runs — this is how the three implementers avoid interpretation drift.

Output: `specs/coach-driven-capture-ergonomics/contracts/interfaces.md` (see template below; the actual file is written alongside this plan).

Owner: **specifier** (i.e., this task) writes the contracts file as part of plan phase.

### Phase 2 — Parallel Implementation

Three implementer tracks run in parallel once Phase 1 is committed. Dependency between tracks is through the contracts file — no shared code paths edited concurrently.

**Track A — impl-context-roadmap (FR-001 through FR-007)**

- Implement `plugin-kiln/scripts/context/read-project-context.sh` + two sub-helpers (`read-prds.sh`, `read-plugins.sh`).
- Add `bats` tests covering: deterministic output, missing-source defensiveness, performance budget (<2 s on fixture repo).
- Update `plugin-kiln/skills/kiln-roadmap/SKILL.md` item-capture path to (a) invoke the reader, (b) emit orientation block, (c) render coached questions with `[accept / tweak / reject]`, (d) handle `accept-all` + `tweak <value> then accept-all`, (e) rewrite prompt copy to collaborative tone.
- Add fixture test `plugin-kiln/tests/roadmap-coached-interview-basic/`.

**Track B — impl-vision-audit (FR-008 through FR-016)**

- Update `plugin-kiln/skills/kiln-roadmap/SKILL.md` `--vision` path: first-run draft (FR-008), re-run per-section diff (FR-009), `last_updated:` bump (FR-010), blank-slate banner fallback (FR-011), partial-snapshot handling (FR-012).
- Create `plugin-kiln/rubrics/claude-md-best-practices.md` with a `fetched:` date frontmatter (initial fetch committed by this track).
- Update `plugin-kiln/skills/kiln-claude-audit/SKILL.md`: consume reader (FR-013), add "External best-practices deltas" subsection (FR-014), cache-fallback + staleness flag (FR-015), remain propose-don't-apply (FR-016).
- Add fixtures: `roadmap-vision-first-run`, `roadmap-vision-re-run`, `claude-audit-project-context`.

**Track C — impl-distill-multi (FR-017 through FR-021)**

- Create `plugin-kiln/scripts/distill/select-themes.sh`, `disambiguate-slug.sh`, `emit-run-plan.sh`.
- Update `plugin-kiln/skills/kiln-distill/SKILL.md`: insert multi-select picker between theme-grouping and emit-PRD (FR-017); emit N PRDs with per-PRD state flips (FR-019); run-plan block at end when N≥2 (FR-018); preserve three-group-sort determinism per-PRD (FR-020); byte-identical single-theme path (FR-021).
- Add fixture: `distill-multi-theme`.

**Coordination**: Track A's deliverable (the reader script) is consumed by Track B and Track C. Track B and Track C may begin fixture work and SKILL.md edits in parallel once the interface contract is frozen; they can stub the reader invocation locally if needed and integrate once Track A lands the script. Interface contracts make this stubbing safe.

### Phase 3 — PRD audit + Smoke test + PR (team-level)

Handled by downstream pipeline tasks `audit-quality`, `audit-smoke-pr`. Specifier is not involved past this plan + tasks + contracts file.

## Complexity Tracking

No Constitution violations. No complexity-tracking entries required.

## Risks (plan-scoped)

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Reader determinism drifts across platforms (macOS vs Linux `sort`) | med | high (breaks NFR-002) | Set `LC_ALL=C` in the script; tests pin a repo fixture and run on both macOS + Linux CI. |
| `jq` syntax mistakes in SKILL.md code blocks | low | med | Contract file gives exact `jq` queries per field; implementers copy-paste. |
| `WebFetch` unavailable in test env | high | low | Cache-path is the default for tests; live-fetch only runs when CI explicitly exercises FR-015 online branch. |
| Multi-theme distill accidentally flips a non-bundled entry | low | high (NFR-003 breach) | FR-019 requires per-flip assertion; test asserts before/after state of an entry NOT bundled into the PRD being emitted. |
| Coached suggestions low-quality on sparse repos | med | med (UX regression) | Reader returns empty fields gracefully; skills emit `[suggestion: —, rationale: no evidence in repo]` placeholder rather than inventing values. |
