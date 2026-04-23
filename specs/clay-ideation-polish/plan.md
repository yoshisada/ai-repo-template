# Plan: Clay Ideation Polish

**Spec**: [spec.md](./spec.md)
**Date**: 2026-04-22

## Approach

This feature is entirely skill-body edits + frontmatter conventions — no new runtime, no scaffold changes, no new wheel workflow. All five affected skills already exist; the work is surgical insertions and small new branches inside them, plus one new helper convention (parent-detection predicate) that lives in `contracts/interfaces.md`.

The work splits cleanly along the two PRD themes:

- **Theme 1 (intent classification)** — touches `clay-idea` (prompt + write), `clay-idea-research` (read + bias), `clay-new-product` (read + simplified mode for `internal`).
- **Theme 2 (nesting)** — touches `clay-idea` (parent detection + offer sub-idea), `clay-new-product` (`--parent` flag + frontmatter write), `clay-list` (display hierarchy), `clay-create-repo` (sub-idea detection + shared-repo default + feature-PRD scaffold).

Both themes share the same frontmatter substrate (`intent:`, `parent:`) so the contracts file is the single point of coordination.

## Tech Stack

Inherited — no additions.

- Markdown (skill definitions in `plugin-clay/skills/<name>/SKILL.md`)
- Bash 5.x for inline filesystem reads/writes inside skills
- `awk`/`sed`/`grep` for frontmatter parsing (same idioms used in existing kiln/clay skills)
- No `jq` required (frontmatter is YAML-style, not JSON)

## Phases

### Phase A — Intent classification (FR-001..FR-005)

Surgical insertions in three skills.

- `clay-idea`: insert "Step 2.5: Classify Market Intent" between current Step 2 (Overlap Analysis) and Step 3 (Present Routing Options). Always prompt; write `intent:` to `products/<slug>/idea.md` (creating `idea.md` if absent). Branch routing on `intent`: `internal` → simplified `/clay:clay-new-product` only; `marketable`/`pmf-exploration` → existing pipeline.
- `clay-idea-research`: at start of Step 1, read `products/<slug>/idea.md` frontmatter and extract `intent`. If `intent=pmf-exploration`, swap the report template's primary "Findings" section to demand-validation orientation; competitor enumeration becomes secondary. If `intent` absent, treat as `marketable` (NFR-002).
- `clay-new-product`: at start of Step 1, read `intent:` from `products/<slug>/idea.md` (if present). If `intent=internal`, switch to a "simplified PRD" sub-mode that drops competitive-landscape and naming-related sections from the PRD template output and skips reading `naming.md` / `research.md` (which won't exist anyway).

### Phase B — Parent detection + sub-idea creation (FR-006..FR-008, FR-012)

- `clay-idea`: insert "Step 2.6: Parent Collision Check" right after intent classification. Predicate: `is_parent(slug)` per FR-007 (filesystem rule from Decision 1). On match, present the 3-way choice (sub-idea / sibling parent / abort). On sub-idea selection, derive sub-slug, create `products/<parent>/<sub-slug>/idea.md` with `parent: <parent-slug>` + `intent: <chosen>` frontmatter, then route downstream as normal.
- `clay-new-product`: parse a `--parent=<slug>` flag from `$ARGUMENTS`. If present: validate `products/<parent-slug>/about.md` exists (else stop with error); compute output paths under `products/<parent>/<sub-slug>/...`; inject `parent: <parent-slug>` frontmatter into every generated PRD file.

### Phase C — Nested display in clay-list (FR-009)

- `clay-list`: in Step 1, after listing subdirectories, classify each as **parent**, **sub-idea**, or **flat** using the same `is_parent` predicate plus a `parent:` frontmatter scan. In Step 4, render parents first with their sub-ideas indented two spaces beneath. Flat products render as today.

### Phase D — Shared-repo default + feature-PRD scaffold (FR-010, FR-011)

- `clay-create-repo`: in Step 1, after resolving the product slug, detect sub-idea status by reading `parent:` frontmatter from `products/<slug>/PRD.md` (or `idea.md`). If sub-idea AND parent has ≥2 sub-ideas: prompt with shared-repo as default (option a). If shared-repo chosen: check whether parent has `.repo-url` (shared repo already exists); if yes, clone/use it; if no, create the shared repo named after the parent. In either case, scaffold the sub-idea inside the shared repo at `docs/features/<YYYY-MM-DD>-<sub-slug>/PRD.md` (Step 5 modified). Step 7.5 (`clay.config` registry) records the shared repo under the parent slug, not the sub-slug; sub-slugs get `.repo-url` symlinks/markers pointing at the shared repo URL.

### Phase E — Smoke fixtures + docs (covers SC-002, SC-003, SC-005, SC-006)

- Add a `specs/clay-ideation-polish/fixtures/` directory with three minimal fixture trees: (1) flat product (backwards-compat), (2) parent + 1 sub-idea (parent-detection), (3) parent + 2 sub-ideas (shared-repo). These are read-only fixtures used by manual smoke runs; they document expected directory shapes.
- Add a smoke-test section to spec.md's verification notes (already present in SC-001..SC-006) and a `SMOKE.md` next to the fixtures with the 6 commands to run.

## File List

Files modified:

- `plugin-clay/skills/clay-idea/SKILL.md` (Phases A + B)
- `plugin-clay/skills/clay-idea-research/SKILL.md` (Phase A)
- `plugin-clay/skills/clay-new-product/SKILL.md` (Phases A + B)
- `plugin-clay/skills/clay-list/SKILL.md` (Phase C)
- `plugin-clay/skills/clay-create-repo/SKILL.md` (Phase D)

Files created:

- `specs/clay-ideation-polish/spec.md` (this work)
- `specs/clay-ideation-polish/plan.md` (this work)
- `specs/clay-ideation-polish/tasks.md` (this work)
- `specs/clay-ideation-polish/contracts/interfaces.md` (this work)
- `specs/clay-ideation-polish/fixtures/flat-product/...` (Phase E)
- `specs/clay-ideation-polish/fixtures/parent-with-one-sub/...` (Phase E)
- `specs/clay-ideation-polish/fixtures/parent-with-two-subs/...` (Phase E)
- `specs/clay-ideation-polish/SMOKE.md` (Phase E)
- `specs/clay-ideation-polish/agent-notes/specifier.md` (this work)

No `src/` files exist for this plugin (the skills are the implementation), so no Bash hook gates trigger here. The 4-gate require-spec hook only fires on `src/` edits.

## Locked Decisions

### Decision 1 — Parent-detection rule (FR-007)

**Locked**: Filesystem-only rule per PRD default. A folder `products/<parent-slug>/` is a parent iff `about.md` exists AND ≥1 immediate sub-folder contains `idea.md` or `PRD.md`. No `kind: parent` frontmatter marker required.

**Rationale**: zero schema changes for existing `about.md` files. Backwards-compatible with every product folder created before this PRD. The false-positive risk (a flat product with `about.md` plus a stray sub-folder containing `idea.md`) is real but extremely narrow — no existing flat product in the repo today has both shapes simultaneously. If false positives surface in the wild, the upgrade path is to add `kind: parent` to the parent's `about.md` frontmatter and tighten the predicate; that's a follow-on PRD, not a blocker.

**Implementation note**: the predicate lives as a small bash function `is_parent_product()` documented in `contracts/interfaces.md` and inlined in each skill that needs it (no shared helper file — clay skills are self-contained Markdown).

### Decision 2 — Missing-intent default

**Locked**: Option (a) — treat missing `intent:` as `intent: marketable` for routing purposes. No backfill prompt, no skip.

**Rationale**: zero regression for every existing `products/<slug>/idea.md` and `PRD.md`. The current `clay-idea` → `clay-idea-research` → `clay-project-naming` → `clay-new-product` pipeline IS the marketable path — treating missing intent as marketable means existing products continue to flow through it untouched. Option (b) (prompt-and-backfill) is documented as an opt-in upgrade in a follow-on PRD; users who want it can manually add `intent:` to existing files. Option (c) (skip — only new products get intent) was rejected because it forces downstream skills to handle two distinct "no intent" cases (legacy product vs intent-less new product) instead of one.

### Decision 3 — Sub-idea frontmatter schema

**Locked**: Sub-idea `idea.md` carries the following frontmatter (PRD names `parent:`; this plan confirms + extends):

```yaml
---
title: <human-readable title>
slug: <sub-slug>
date: <YYYY-MM-DD>
status: idea | researched | named | prd-created | repo-created
parent: <parent-slug>          # REQUIRED for sub-ideas; omitted for flat/parent products
intent: internal | marketable | pmf-exploration   # REQUIRED — prompted fresh per sub-idea
---
```

**Rationale on `intent:` for sub-ideas — prompted fresh, not inherited.** Each sub-idea may have a distinct intent: a parent `personal-automations` might host one `internal` sub-idea (a script for personal use) and one `marketable` sub-idea (a SaaS extracted from the same domain). Inheriting `intent:` from the parent's `about.md` would silently force one classification on every sibling. Prompting fresh costs one round-trip per sub-idea (NFR-003 already accepts this for `/clay:clay-idea`) and yields correct routing.

The `parent:` field is the single source of truth for the relationship per FR-008. Filesystem layout follows but `parent:` is what `/clay:clay-list` and `/clay:clay-create-repo` read.

## Open Questions Carried Into Implement

None blocking. PRD's "Risks & Open Questions" section flags two implementation-time judgment calls that the implementer can resolve inline:

- **Shared-repo with incompatible tech stacks (PRD risk #3).** The shared-repo path assumes compatible stacks. If sub-ideas have meaningfully different tech stacks, the implementer should note this in the prompt text — e.g., "Sub-ideas under <parent> appear to use different tech stacks; shared-repo may not be a clean fit" — and let the user choose. No code change beyond the warning text.
- **`/clay:clay-new-product --parent` flag parsing (PRD risk #4).** Verified: `clay-new-product` currently accepts free-form `$ARGUMENTS`. The `--parent=<slug>` flag parses cleanly via `case` statement / `awk` extraction at the top of Step 0. The implementer should add an explicit parser block at the top of Step 0 that pulls `--parent=<slug>` out of `$ARGUMENTS` and leaves the rest untouched.

## Test Strategy

There is no test suite for clay skills (see CLAUDE.md: "There is no test suite for the plugin itself"). Verification is via manual smoke runs against the Phase E fixtures, mapped to SC-001..SC-006.

## Risks

- **Parent-detection false positives** (Decision 1) — narrow, documented escape hatch.
- **Existing user expectations of `clay-idea` flow** — adding the intent prompt before routing is a UX change. Mitigation: the prompt is one line with three labeled options; no breaking change to the routing options themselves.
- **Sub-idea slug collisions** (e.g., two parents both have a `web` sub-idea) — namespacing under the parent folder avoids this on disk, but `/clay:clay-list` should display the parent prefix when a sub-slug is shown bare. Implementer handles in Phase C.
