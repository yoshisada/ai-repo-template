# Implementation Plan: Workflow Governance

**Branch**: `build/workflow-governance-20260424` | **Date**: 2026-04-24 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/workflow-governance/spec.md`
**PRD**: `docs/features/2026-04-24-workflow-governance/PRD.md` (frozen)

## Summary

Three independently-releasable sub-initiatives shipped in one pipeline run:

1. **Hook verification** — FR-001/FR-002 already shipped in commit `86e3585`. Add test fixture at `plugin-kiln/tests/require-feature-branch-build-prefix/` to lock the regression boundary (FR-003).
2. **Roadmap-first PRD intake** — Graft a gate onto `/kiln:kiln-distill` that refuses un-promoted sources (FR-004/FR-005/FR-007/FR-008) and add `--promote` path to `/kiln:kiln-roadmap` (FR-006) so the gate has a viable escape hatch.
3. **Retro → source feedback loop** — New `/kiln:kiln-pi-apply` skill parses `File / Current / Proposed / Why` blocks from GitHub retrospective issues and emits a propose-don't-apply diff report with stable `pi-hash` dedup (FR-009–FR-013).

Primary technical approach: all three are Bash + `jq` + markdown. No compiled code, no new runtime dependencies, no new PreToolUse hooks. Each sub-initiative is its own implementer track and its own set of fixtures; merge order is flexible per NFR-004.

## Technical Context

**Language/Version**: Bash 5.x (script bodies + skill command steps), `jq` ≥ 1.6 (JSON parsing), `gh` CLI (GitHub retro issue fetch), `sha256sum` / `shasum -a 256` (pi-hash), Markdown (skills, rubric docs, reports).
**Primary Dependencies**: Existing `plugin-kiln/scripts/roadmap/*.sh` helpers (reused unchanged by FR-006 `--promote`); existing `plugin-kiln/skills/kiln-distill/SKILL.md` three-stream ingestion (extended, not rewritten, for FR-004/FR-005); existing `plugin-kiln/hooks/require-feature-branch.sh` (not edited — verified by fixture).
**Storage**: File-based — markdown under `.kiln/`, `docs/features/`, `plugin-kiln/skills/`, `plugin-kiln/tests/`; no database, no server state.
**Testing**: Shell-level assertions via `bats` where available; integration via the `/kiln:kiln-test` plugin-skill substrate against fixtures under `plugin-kiln/tests/`.
**Target Platform**: macOS + Linux (Bash 5.x / `jq` / `gh`), invoked by Claude Code as skill bodies. No Windows support.
**Project Type**: Claude Code plugin (`plugin-kiln/`) — skills (markdown), scripts (bash), templates (markdown).
**Performance Goals**: `/kiln:kiln-pi-apply` ≤ 60 s on ≤ 20 retro issues (NFR-002). Hook path ≤ 50 ms delta vs baseline (NFR-001).
**Constraints**: Propose-don't-apply discipline for `/kiln:kiln-pi-apply` (FR-010); byte-preservation of source file bodies on `--promote` (NFR-003); grandfathering of pre-existing PRDs (FR-008, NFR-005); deterministic pi-hash (FR-011); confirm-never-silent per-entry promotion UI (FR-005).
**Scale/Scope**: 1 new skill (`kiln-pi-apply`), 2 updated skills (`kiln-roadmap` adds `--promote`, `kiln-distill` adds gate), 1 test fixture trio, ~3 helper scripts, new rubric-free (no new rubrics). Estimated ~600 LOC across skill markdown + scripts + fixtures.

## Constitution Check

**Gate — Spec-First (Article I)**: spec.md written and committed before any implementation edits. ✅

**Gate — 80% Coverage (Article II)**: Each new shell script ships with a fixture under `plugin-kiln/tests/` that exercises its documented invocations. Coverage is measured at the behavior level (fixtures cover each FR's acceptance scenarios) rather than line-coverage, which is the existing plugin-repo convention (no compiled code).

**Gate — PRD Source of Truth (Article III)**: PRD frozen; every spec FR maps 1:1 to a PRD FR via the traceability table in spec.md; no divergence.

**Gate — Hooks (Article IV)**: No new PreToolUse hooks. The existing `require-feature-branch.sh` is not edited (FR-001/FR-002 already shipped). ✅

**Gate — E2E (Article V)**: `/kiln:kiln-test` substrate runs real `claude --print` subprocesses against fixtures for each of the three surfaces (hook, distill gate + promote, pi-apply).

**Gate — Small, Focused (Article VI)**: Each phase below touches one bounded area; all shell scripts stay < 500 lines; skill SKILL.md additions stay < 200 new lines each.

**Gate — Interface Contracts (Article VII)**: `contracts/interfaces.md` (this planning artifact) publishes every new script signature, every new skill invocation form, and the report schema for `pi-apply` before any parallel implementation starts.

**Gate — Incremental Completion (Article VIII)**: `tasks.md` is organized per-phase; each task commits individually with its `[X]` mark; phase-complete commits group small related tasks.

**No violations requiring complexity-tracking justification.**

## Project Structure

### Documentation (this feature)

```text
specs/workflow-governance/
├── spec.md                        # Written
├── plan.md                        # This file
├── contracts/
│   └── interfaces.md              # Mandatory — script + skill signatures
├── tasks.md                       # Phase-organized tasks (ownership-tagged)
├── agent-notes/
│   └── specifier.md               # Friction note (written pre-completion)
└── checklists/
    └── requirements.md            # Spec quality checklist (standard kiln artifact)
```

### Source Code (plugin-kiln layout — this is the plugin source repo, not a consumer project)

```text
plugin-kiln/
├── hooks/
│   └── require-feature-branch.sh        # UNCHANGED (FR-001/FR-002 already shipped in 86e3585)
├── skills/
│   ├── kiln-distill/
│   │   └── SKILL.md                     # UPDATED — FR-004/FR-005/FR-007/FR-008 gate
│   ├── kiln-roadmap/
│   │   └── SKILL.md                     # UPDATED — FR-006 --promote path
│   ├── kiln-pi-apply/
│   │   └── SKILL.md                     # NEW — FR-009/FR-010/FR-011/FR-012/FR-013
│   └── kiln-next/
│       └── SKILL.md                     # UPDATED (thin) — FR-013 discovery integration
├── scripts/
│   ├── distill/                         # NEW — gate helpers
│   │   ├── detect-un-promoted.sh        # FR-004 — scan selected theme bundle for un-promoted entries
│   │   └── invoke-promote-handoff.sh    # FR-005 — per-entry accept/skip loop
│   ├── roadmap/                         # EXISTING + ONE ADD
│   │   └── promote-source.sh            # NEW — FR-006 byte-preserving source update + new item write
│   └── pi-apply/                        # NEW — all pi-apply helpers
│       ├── fetch-retro-issues.sh        # FR-009 — gh issue list wrapper with JSON output
│       ├── parse-pi-blocks.sh           # FR-009 — File/Current/Proposed/Why regex extractor
│       ├── compute-pi-hash.sh           # FR-011 — sha256 truncated to 12 hex
│       ├── classify-pi-status.sh        # FR-012 — already-applied / stale / actionable
│       ├── render-pi-diff.sh            # FR-011 — unified-diff shape
│       └── emit-report.sh               # FR-010 — report assembler (writes .kiln/logs/pi-apply-*.md)
└── tests/                               # NEW fixtures
    ├── require-feature-branch-build-prefix/   # FR-003
    ├── distill-gate-refuses-un-promoted/      # FR-004 / FR-005
    ├── distill-gate-grandfathered-prd/        # FR-008 / NFR-005
    ├── roadmap-promote-basic/                 # FR-006 happy path
    ├── roadmap-promote-byte-preserve/         # FR-006 / NFR-003
    ├── roadmap-promote-idempotency/           # FR-006 second-invocation guard
    ├── pi-apply-report-basic/                 # FR-009 / FR-010 / FR-011
    ├── pi-apply-status-classification/        # FR-012
    └── pi-apply-dedup-determinism/            # SC-004 determinism guard
```

**Structure Decision**: This is the **plugin source repo** (per CLAUDE.md — "not a consumer project"), so all paths are under `plugin-kiln/`. No `src/` or `tests/` at repo root. Shell + markdown; no compile step.

## Phases

### Phase 1 — Hook verification fixture (FR-001 / FR-002 / FR-003)

**Owner**: `impl-governance`
**Blocks**: Nothing downstream (independent release per NFR-004).
**Scope**: Author the regression fixture for the already-shipped `build/*` accept-list entry.

**Key files**:
- `plugin-kiln/tests/require-feature-branch-build-prefix/run.sh` — entry-point
- `plugin-kiln/tests/require-feature-branch-build-prefix/fixture/` — minimal git-init scaffold with branch naming
- `plugin-kiln/tests/require-feature-branch-build-prefix/expected-stdout.txt` — empty (exit 0, no output)

**Exit criteria**:
- Positive case (`build/workflow-governance-20260424` + `specs/workflow-governance/spec.md` write) exits 0.
- Negative case — `main` — exits 2 with standard error.
- Negative case — `feature/foo` (unprefixed, not under `build/`) — exits 2.
- Runtime within 50 ms of baseline (NFR-001).

### Phase 2 — Roadmap `--promote` path (FR-006)

**Owner**: `impl-governance`
**Blocks**: Phase 3 (distill gate needs a viable escape hatch).
**Scope**: Extend `plugin-kiln/skills/kiln-roadmap/SKILL.md` with a `--promote <source>` branch and add `plugin-kiln/scripts/roadmap/promote-source.sh`.

**Key files**:
- `plugin-kiln/scripts/roadmap/promote-source.sh` — NEW, per `contracts/interfaces.md`
- `plugin-kiln/skills/kiln-roadmap/SKILL.md` — UPDATED, new Step N for `--promote <source>`
- `plugin-kiln/tests/roadmap-promote-basic/` — happy-path fixture
- `plugin-kiln/tests/roadmap-promote-byte-preserve/` — NFR-003 byte-diff assertion
- `plugin-kiln/tests/roadmap-promote-idempotency/` — second-invocation refusal

**Exit criteria**: All three fixtures pass. Byte-diff fixture confirms source body untouched.

### Phase 3 — Distill gate (FR-004 / FR-005 / FR-007 / FR-008)

**Owner**: `impl-governance`
**Depends on**: Phase 2 (promote path exists).
**Scope**: Update `plugin-kiln/skills/kiln-distill/SKILL.md` Step 0 / Step 1 to scan for un-promoted entries, surface per-entry promotion prompt, and call back into `/kiln:kiln-roadmap --promote` for each accepted entry. Preserve three-group sort shape (FR-007). Grandfather pre-existing PRDs (FR-008).

**Key files**:
- `plugin-kiln/scripts/distill/detect-un-promoted.sh` — NEW, per contract
- `plugin-kiln/scripts/distill/invoke-promote-handoff.sh` — NEW, per contract
- `plugin-kiln/skills/kiln-distill/SKILL.md` — UPDATED, new Step 0.5 (gate) before existing Step 1 ingestion
- `plugin-kiln/tests/distill-gate-refuses-un-promoted/` — FR-004 refusal
- `plugin-kiln/tests/distill-gate-grandfathered-prd/` — FR-008 + NFR-005

**Exit criteria**: Refusal fixture emits no PRD and shows per-entry prompt. Grandfathered fixture parses pre-existing PRDs without warning.

### Phase 4 — `/kiln:kiln-pi-apply` skill (FR-009 / FR-010 / FR-011 / FR-012 / FR-013)

**Owner**: `impl-pi-apply`
**Depends on**: Nothing (independent release per NFR-004).
**Scope**: New skill `plugin-kiln/skills/kiln-pi-apply/SKILL.md` with helper scripts under `plugin-kiln/scripts/pi-apply/` per contract. `/kiln:kiln-next` integration is a thin count + recommendation.

**Key files**:
- `plugin-kiln/skills/kiln-pi-apply/SKILL.md` — NEW
- `plugin-kiln/scripts/pi-apply/fetch-retro-issues.sh` — NEW
- `plugin-kiln/scripts/pi-apply/parse-pi-blocks.sh` — NEW
- `plugin-kiln/scripts/pi-apply/compute-pi-hash.sh` — NEW
- `plugin-kiln/scripts/pi-apply/classify-pi-status.sh` — NEW
- `plugin-kiln/scripts/pi-apply/render-pi-diff.sh` — NEW
- `plugin-kiln/scripts/pi-apply/emit-report.sh` — NEW
- `plugin-kiln/skills/kiln-next/SKILL.md` — UPDATED (thin — FR-013 discovery section)
- `plugin-kiln/tests/pi-apply-report-basic/` — happy path with 3 retro issues / 5 PI blocks
- `plugin-kiln/tests/pi-apply-status-classification/` — already-applied / stale / actionable branches
- `plugin-kiln/tests/pi-apply-dedup-determinism/` — SC-004 byte-identical re-run

**Exit criteria**: All three fixtures pass. Re-run produces byte-identical report body.

### Phase 5 — Integration + documentation polish

**Owner**: `impl-governance` (coordinates — both tracks merge here)
**Depends on**: Phases 1–4 complete.
**Scope**: Update `CLAUDE.md` Recent Changes; add the new commands to the command list; cross-link skills so `/kiln:kiln-next` surfaces `/kiln:kiln-pi-apply` when threshold met.

**Key files**:
- `CLAUDE.md` — Recent Changes + `/kiln:kiln-pi-apply` in command list
- `specs/workflow-governance/tasks.md` — marked all `[X]`

**Exit criteria**: PRD audit passes. Smoke test passes. All six SCs validated.

## Parallelization Plan

The two implementer tracks can run concurrently after spec + plan + tasks land:

- **Track A — impl-governance** (Phases 1 → 2 → 3 → 5): Phase 1 is independent. Phase 2 unblocks Phase 3. Phase 5 runs last.
- **Track B — impl-pi-apply** (Phase 4): Fully independent of Track A until Phase 5 integration. Can start the moment spec + plan + tasks are committed.

Both tracks share the `contracts/interfaces.md` contract — no cross-track script edits.

## Complexity Tracking

No constitutional deviations. Every file lives under an existing well-known path (`plugin-kiln/skills/`, `plugin-kiln/scripts/`, `plugin-kiln/tests/`). No new runtime dependencies. No new hooks. No new workflows. Three new skills — one meets a clear PRD mandate (`/kiln:kiln-pi-apply`), two are additive-flag changes to existing skills. Every FR has a direct fixture.

## Rollout Notes

- **Merge order** is flexible per NFR-004. Recommended: Phase 1 first (smallest, zero risk), then Phase 4 (independent, high value), then Phases 2+3 together (they couple via the escape-hatch dependency).
- **Feature flag**: none. All three changes are forward-looking; grandfathering (FR-008) ensures no existing artifact breaks.
- **Documentation**: `CLAUDE.md` gets three additions — `/kiln:kiln-roadmap --promote`, `/kiln:kiln-pi-apply`, and the distill gate behavior note. All in the "Available Commands" section plus a "Recent Changes" entry for `build/workflow-governance-20260424`.
