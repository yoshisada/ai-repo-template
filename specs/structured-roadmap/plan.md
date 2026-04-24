# Implementation Plan: Structured Roadmap Planning Layer

**Branch**: `build/structured-roadmap-20260424` | **Date**: 2026-04-24 | **Spec**: [spec.md](./spec.md)
**Input**: `specs/structured-roadmap/spec.md` + `docs/features/2026-04-23-structured-roadmap/PRD.md`

## Summary

Replace `/kiln:kiln-roadmap`'s scratchpad with a structured product-planning layer (vision + phases + typed items + adversarial interview), extend `/kiln:kiln-distill` to consume items as a third stream with new filters, add a `shelf:shelf-write-roadmap-note` workflow that mirrors files to Obsidian using `.shelf-config`, and wire small touchpoints into `/kiln:kiln-next` and `/specify` for the promotion lifecycle. No new runtime dependencies — Markdown skills, Bash, jq, Obsidian MCP only.

## Technical Context

**Language/Version**: Bash 5.x (inline + helper scripts), Markdown (skill definitions, templates, stored artifacts), `jq` for JSON/frontmatter parsing.
**Primary Dependencies**: Existing kiln plugin infrastructure, Obsidian MCP (`mcp__claude_ai_obsidian-projects__create_file`, `patch_file`), `.shelf-config` parser (already shipped via `plugin-shelf/scripts/parse-shelf-config.sh`), wheel engine for the new `shelf-write-roadmap-note` workflow.
**Storage**: File-based — `.kiln/vision.md`, `.kiln/roadmap/{phases,items}/*.md` (Markdown with YAML frontmatter); Obsidian vault at `<base_path>/<slug>/` (mirror only, NOT source of truth).
**Testing**: Bash unit tests for validators + helpers under `plugin-kiln/tests/structured-roadmap-*/` (using the existing `/kiln:kiln-test` harness — `plugin-skill` substrate). Smoke test scaffolds a temp project and exercises the full capture → distill → specify flow.
**Target Platform**: macOS + Linux (POSIX shell). No Windows-specific behavior.
**Project Type**: Plugin (not consumer project) — all changes land under `plugin-kiln/` and `plugin-shelf/`.
**Performance Goals**: Capture-to-disk latency ≤2s for `--quick` path; ≤90s wall-clock for full adversarial interview (per SC-005). Distill with items in scope MUST NOT regress existing two-stream perf by more than 15% on typical inputs.
**Constraints**: Single source of truth = `.kiln/`. No vault discovery (FR-004). No human-time sizing fields (FR-008, schema-enforced). One Obsidian write per file change (FR-035). Cross-surface routing is confirm-never-silent (FR-014, FR-014b).
**Scale/Scope**: Single-repo single-user. Roadmap directory scales to low hundreds of items before any pagination concern.

## Constitution Check

| Principle | How this plan satisfies |
|-----------|-------------------------|
| I. Spec-First (NON-NEGOTIABLE) | spec.md committed before any implementation; FR-IDs cited in every task and (per Article VII/VIII) referenced in code comments + tests. |
| II. 80% Coverage Gate | Bash helpers under `plugin-kiln/scripts/roadmap/` ship with unit tests; aggregate coverage measured via `bashcov` or equivalent and gated at ≥80%. (See Phase 5 Verification.) |
| III. PRD as Source of Truth | spec.md cites PRD `docs/features/2026-04-23-structured-roadmap/PRD.md` for every inherited FR; spec adds FR-032..FR-040 as derived requirements with rationale. |
| IV. Hooks Enforce Rules | No new hooks; existing 4-gate hooks remain authoritative. The skill changes are pipeline-internal so hooks won't block their own edits (skill files are not under `src/`). |
| V. E2E Testing | The `/kiln:kiln-test` harness (`plugin-skill` substrate) exercises real `/kiln:kiln-roadmap` and `/kiln:kiln-distill` runs against `/tmp/kiln-test-<uuid>/` fixtures — no mocking. Smoke-tester agent runs the full flow end-to-end. |
| VI. Small Files | All new files target <500 lines; large skill SKILL.md split via `## ` headings; helpers split per-concern under `plugin-kiln/scripts/roadmap/`. |
| VII. Interface Contracts (NON-NEGOTIABLE) | `contracts/interfaces.md` defines exact signatures for every Bash helper + agent step output JSON shape + frontmatter schemas BEFORE implementation. |
| VIII. Incremental Task Completion (NON-NEGOTIABLE) | tasks.md groups work by Phase + User Story; each task marked `[X]` immediately on completion; commit after each phase. |

**Gate result**: PASS. No constitutional violations to justify.

## Project Structure

### Documentation (this feature)

```text
specs/structured-roadmap/
├── spec.md                       # /specify output (this feature)
├── plan.md                       # /plan output (this file)
├── contracts/
│   └── interfaces.md             # /plan output — single source of truth for signatures + schemas
├── tasks.md                      # /tasks output
├── agent-notes/                  # Per-agent friction notes (specifier, impl-roadmap, impl-integration, audit)
└── (research.md, data-model.md, quickstart.md — NOT generated; this feature is plugin-internal and reuses existing kiln infrastructure)
```

### Source Code (repository root) — files this feature touches

```text
plugin-kiln/
├── skills/
│   ├── kiln-roadmap/SKILL.md             # REWRITE — was 72-line scratchpad, becomes the structured-capture skill
│   ├── kiln-distill/SKILL.md             # MODIFY — add items stream + --phase/--addresses/--kind filters + state: distilled write
│   ├── kiln-next/SKILL.md                # MODIFY — surface state: in-phase items from active phase
│   └── kiln-specify/SKILL.md             # MODIFY — write state: specced when run against a roadmap-derived PRD (see kiln:specify)
├── templates/
│   ├── vision-template.md                # NEW — minimal vision starter
│   ├── roadmap-phase-template.md         # NEW — phase frontmatter + body skeleton
│   ├── roadmap-item-template.md          # NEW — item frontmatter (with sizing) + body skeleton
│   ├── roadmap-critique-template.md      # NEW — critique-specific (proof_path required)
│   └── roadmap-template.md               # KEEP for legacy migration reference; unused after migration
├── scripts/
│   └── roadmap/                          # NEW directory
│       ├── parse-item-frontmatter.sh     # NEW — parse one item file → JSON
│       ├── validate-item-frontmatter.sh  # NEW — schema validator (rejects forbidden sizing fields)
│       ├── validate-phase-frontmatter.sh # NEW — schema validator
│       ├── list-items.sh                 # NEW — glob + filter (by phase, kind, addresses)
│       ├── update-item-state.sh          # NEW — atomic frontmatter state transition
│       ├── update-phase-status.sh        # NEW — atomic phase status transition + item state cascade
│       ├── migrate-legacy-roadmap.sh     # NEW — one-shot migration of .kiln/roadmap.md
│       ├── seed-critiques.sh             # NEW — bootstrap three critique files
│       ├── classify-description.sh       # NEW — kind detection + cross-surface routing heuristic
│       └── detect-multi-item.sh          # NEW — multi-item input detection (FR-018a)
└── tests/                                # NEW dir tree under plugin-kiln/ (per-test scratch)
    ├── structured-roadmap-capture-feature/
    ├── structured-roadmap-capture-critique/
    ├── structured-roadmap-quick-path/
    ├── structured-roadmap-cross-surface-routing/
    ├── structured-roadmap-distill-three-streams/
    ├── structured-roadmap-distill-addresses-filter/
    ├── structured-roadmap-migration-legacy/
    ├── structured-roadmap-seed-critiques/
    └── structured-roadmap-shelf-mirror-paths/

plugin-shelf/
├── workflows/
│   └── shelf-write-roadmap-note.json     # NEW — mirrors shelf-write-issue-note shape
└── scripts/
    └── parse-roadmap-input.sh            # NEW — parses skill output into the agent-step input JSON

# (No edits to .specify/memory/constitution.md, no new hooks, no new top-level dirs.)
```

**Structure Decision**: Single-plugin repo (this is `plugin-kiln/` source repo). All changes land in `plugin-kiln/` (skills, templates, scripts, tests) and `plugin-shelf/` (one workflow + one helper script). Consumer projects pick up the changes by upgrading the plugin — no scaffolding changes required.

## Phases

### Phase 0 — Research & Confirm (no code)

Trivial: existing patterns are well-established. No `research.md` is generated; the inputs are:

- Existing `shelf-write-issue-note` workflow (4-step shape) — mirrored verbatim for `shelf-write-roadmap-note`.
- Existing `kiln-distill` SKILL.md (276 lines) — extended in place; do NOT fork.
- Existing `parse-shelf-config.sh` — reused as-is (assuming blocker fix lands first; see Deployment Readiness).
- Existing `/kiln:kiln-test` harness for E2E verification.

### Phase 1 — Contracts (impl-roadmap + impl-integration in parallel after this lands)

Owner: specifier (this is the deliverable that `/plan` produces alongside this file).

Output: `contracts/interfaces.md` defining:

1. Item / Phase / Vision frontmatter schemas (JSON-schema-shaped, but specified as Bash-validatable rules).
2. Bash helper signatures (`parse-item-frontmatter`, `validate-item-frontmatter`, `validate-phase-frontmatter`, `list-items`, `update-item-state`, `update-phase-status`, `migrate-legacy-roadmap`, `seed-critiques`, `classify-description`, `detect-multi-item`, `parse-roadmap-input`).
3. `shelf-write-roadmap-note` workflow contract (input JSON shape, output JSON shape, MCP tool whitelist).
4. Adversarial interview question banks per kind (≤5 questions each, individually skippable).
5. Cross-surface routing heuristic table (regex → surface mapping with examples).
6. Kind auto-detection heuristic table.
7. Forbidden-sizing-fields list (validator MUST reject these).

### Phase 2 — Roadmap implementer scope (impl-roadmap)

**Owner**: `impl-roadmap` (per team-lead briefing).

**Files this implementer owns end-to-end** — no overlap with impl-integration:

- `plugin-kiln/skills/kiln-roadmap/SKILL.md` — full rewrite per spec FR-013 .. FR-020 (capture + interview + phase mgmt + vision + check + reclassify).
- `plugin-kiln/templates/vision-template.md`, `roadmap-phase-template.md`, `roadmap-item-template.md`, `roadmap-critique-template.md` — NEW.
- `plugin-kiln/scripts/roadmap/*.sh` — all helpers listed in Phase 1.
- `plugin-kiln/tests/structured-roadmap-{capture-feature,capture-critique,quick-path,cross-surface-routing,migration-legacy,seed-critiques,phase-mgmt}/` — feature-side tests.

**Order within scope**:

1. Helpers (validators first — Article VII says contracts before behavior).
2. Templates.
3. Migration + seed-critiques (one-shot bootstrap).
4. Skill rewrite — capture flow, then interview, then `--quick`, then `--vision`, then `--phase`, then `--check`.
5. Cross-surface routing (FR-014 + FR-014b) — last because it's the entrypoint that gates everything.
6. Tests for each user story (US1 → US3 → US4 → US7 → US8 → US9 → US10) — interleaved with the matching feature.

**Hand-offs**: When phase 2 task `T-roadmap-helpers-validators` lands, impl-integration is unblocked on distill validation. SendMessage required at that point.

### Phase 3 — Integration implementer scope (impl-integration)

**Owner**: `impl-integration` (per team-lead briefing).

**Files this implementer owns end-to-end** — no overlap with impl-roadmap:

- `plugin-kiln/skills/kiln-distill/SKILL.md` — extension per spec FR-023 .. FR-027 (third stream + filters + state: distilled write + implementation_hints flow).
- `plugin-kiln/skills/kiln-next/SKILL.md` — small modification per spec FR-033 (surface in-phase items).
- `plugin-kiln/skills/kiln-specify/SKILL.md` — small modification per spec FR-034 (state: specced write hook).
- `plugin-shelf/workflows/shelf-write-roadmap-note.json` — NEW workflow per spec FR-030, FR-035.
- `plugin-shelf/scripts/parse-roadmap-input.sh` — NEW helper.
- `plugin-kiln/tests/structured-roadmap-{distill-three-streams,distill-addresses-filter,distill-kind-filter,next-surfaces-in-phase,specify-state-hook,shelf-mirror-paths}/` — integration-side tests.

**Order within scope**:

1. `shelf-write-roadmap-note.json` + `parse-roadmap-input.sh` (impl-roadmap can call into this helper as soon as it lands; coordinate via SendMessage).
2. Distill extension — third stream first, then filters, then state-write, then implementation_hints flow.
3. `/kiln:kiln-next` modification.
4. `/kiln:kiln-specify` modification.
5. Tests for each integration user story (US5 → US6 → US7 lifecycle assertions).

### Phase 4 — Audit + smoke (audit-compliance)

**Owner**: `audit-compliance`.

- PRD audit per `kiln:audit` — checks every PRD FR (FR-001..FR-031) is covered by spec FR-IDs and implementation/test traceability.
- Spec audit — checks FR-032..FR-040 are implemented and tested.
- Coverage check — ≥80% line + branch on new Bash helpers.
- Smoke test — scaffold temp consumer project, run full flow (capture → distill → specify hand-off → Obsidian-mirror verification).

### Phase 5 — PR (audit-pr)

**Owner**: `audit-pr`. Standard build-prd label, PR template references this spec + PRD.

## Deployment Readiness

### Blocker dependency

This feature has ONE upstream blocker that MUST close before merging:

- **Issue**: `2026-04-23-write-issue-note-ignores-shelf-config` — the existing shelf workflows (`shelf-write-issue-note`, and by extension our new `shelf-write-roadmap-note`) currently fall back to discovery instead of strictly using `.shelf-config` even when present. The new roadmap mirror MUST NOT ship until `.shelf-config` is the canonical path source (PRD FR-004, Absolute Must #2).
- **Why this blocks**: shipping the new workflow on top of the broken helper would silently route roadmap notes to discovery-derived paths, contaminating the Obsidian vault layout for new users.
- **What we do in the meantime**: development against the new workflow proceeds; tests pin path-source to `.shelf-config (base_path + slug)` so a regression in the helper is caught at PR time.
- **Pre-merge gate**: PR description MUST link the closed blocker issue. If the blocker is not closed when audit-compliance runs, audit-compliance MUST fail with a documented blocker in `specs/structured-roadmap/blockers.md`.

### Migration safety

- Migration (FR-028) is one-shot and idempotent — guarded by a check for `.kiln/roadmap.legacy.md` existence (file present → skip). The legacy file is RENAMED, never deleted, so rollback is `mv .kiln/roadmap.legacy.md .kiln/roadmap.md` + `rm -rf .kiln/roadmap/`.
- Seed critiques (FR-029) only fire when `.kiln/roadmap/items/` is empty — re-running the bootstrap on a populated dir is a no-op.

### Rollback

- All artifacts are version-controlled; `git revert` of the merge commit reverts cleanly.
- `.kiln/roadmap/` and `.kiln/vision.md` are gitignored on consumer projects (per existing kiln conventions for `.kiln/` work products) so consumer-side state is unaffected by plugin upgrade/downgrade.

## Complexity Tracking

> No constitution violations. This section is intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| (none) | — | — |

## Verification

- **Schema validators rejection rate**: 100% on a fixture set including `human_time`, `t_shirt_size`, `effort_days`, and arbitrary unknown frontmatter keys (per FR-008 + SC-006).
- **Capture latency**: `--quick` path ≤2s wall-clock; full interview ≤90s (per SC-005).
- **Obsidian mirror parity**: `find .kiln/vision.md .kiln/roadmap/ -type f | wc -l` equals the count of files under `<base_path>/<slug>/` matching the same shape (per SC-004).
- **Distill three-stream end-to-end**: a single `/kiln:kiln-distill --phase current` run with one feedback + one item + one issue produces a PRD whose `derived_from:` lists all three (per FR-024 + SC-002).
- **Cross-surface hand-off**: `/kiln:kiln-roadmap the build is broken` followed by user-pick `(a)` invokes `/kiln:kiln-report-issue` with the original description (per FR-014b + FR-036).
- **Coverage**: `bashcov`-equivalent reports ≥80% on `plugin-kiln/scripts/roadmap/*.sh`.
- **PRD audit pass**: `kiln:audit` reports 100% PRD-FR coverage with no documented blockers (besides the upstream `.shelf-config` fix).
