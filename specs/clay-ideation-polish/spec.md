# Spec: Clay Ideation Polish

**Feature branch**: `build/clay-ideation-polish-20260422`
**PRD**: [docs/features/2026-04-22-clay-ideation-polish/PRD.md](../../docs/features/2026-04-22-clay-ideation-polish/PRD.md)
**Status**: Draft
**Date**: 2026-04-22

## Summary

Add two coherent affordances to the clay ideation pipeline:

1. **Market intent classification** — `/clay:clay-idea` always asks the user (no flag) whether the idea is `internal`, `marketable`, or `pmf-exploration`, records that as `intent:` frontmatter on `products/<slug>/idea.md`, and downstream skills route on it (skip research for `internal`, bias toward demand-validation for `pmf-exploration`).
2. **Nested product folders** — `products/<parent>/about.md` plus `products/<parent>/<child>/idea.md|PRD.md` defines a parent/sub-idea relationship. Sub-ideas carry `parent: <parent-slug>` frontmatter. `/clay:clay-idea` detects parent collisions and offers nesting; `/clay:clay-list` displays the hierarchy; `/clay:clay-create-repo` defaults sub-ideas to a shared parent repo (feature PRD layout); `/clay:clay-new-product` accepts `--parent=<slug>`.

Affected skills (5): `clay-idea`, `clay-idea-research`, `clay-new-product`, `clay-list`, `clay-create-repo`.

## User Stories

- **US-001 — Internal automation skips research.** As a maintainer brainstorming an internal automation tool, I want `/clay:clay-idea` to recognize it's internal and skip the market-research phase, so I don't pay research costs for an idea that won't leave my machine.
  - **Given** I run `/clay:clay-idea "<idea>"` **When** I answer `internal` at the intent prompt **Then** the skill writes `intent: internal` to `products/<slug>/idea.md` and routes directly to the simplified PRD path with no `research.md` produced and no `/clay:clay-idea-research` invocation. (FR-001, FR-002, FR-003)

- **US-002 — PMF-exploration biases research toward demand validation.** As a maintainer validating a new SaaS idea, I want `/clay:clay-idea` to bias research toward demand validation rather than competitor mapping.
  - **Given** I run `/clay:clay-idea "<idea>"` **When** I answer `pmf-exploration` at the intent prompt and confirm research **Then** `/clay:clay-idea-research` reads `intent: pmf-exploration` from `idea.md` and produces a research brief whose primary section is demand validation (customer discovery questions, signals of existing pain, willingness-to-pay proxies); competitor enumeration is secondary. (FR-001, FR-002, FR-004)

- **US-003 — Nested sub-idea creation under an existing parent.** As a maintainer with `products/personal-automations/about.md` and `products/personal-automations/email-digest/idea.md`, I want to add `morning-briefing` as another sub-idea and have the relationship visible everywhere.
  - **Given** a parent product folder exists per FR-007 **When** I run `/clay:clay-idea "<new sub-idea>"` and the slug nests under the parent **Then** the skill prompts me to create the sub-idea (under the parent), a sibling parent product, or abort; choosing sub-idea writes `parent: personal-automations` frontmatter into the new sub-idea's `idea.md`. (FR-006, FR-007, FR-008)
  - **And** `/clay:clay-list` displays parents on top with sub-ideas indented or tree-prefixed beneath. (FR-009)

- **US-004 — Shared repo for multiple sub-ideas.** As a maintainer with 2+ sub-ideas under `personal-automations`, I want `/clay:clay-create-repo` to default to creating one shared repo rather than three separate repos.
  - **Given** a parent product with ≥2 sub-ideas **When** I run `/clay:clay-create-repo` against any sub-idea **Then** the skill detects the sub-idea (via `parent:` frontmatter), confirms the parent has siblings, and offers the shared-repo option as the default; choosing shared-repo scaffolds the sub-idea as `docs/features/<YYYY-MM-DD>-<sub-slug>/PRD.md` inside the shared repo. (FR-010, FR-011)

- **US-005 — Programmatic sub-idea creation.** As a script or future automation, I need `/clay:clay-new-product --parent=<parent-slug>` to create a sub-idea folder under the named parent without going through `/clay:clay-idea`.
  - **Given** a `--parent=<slug>` flag **When** I invoke `/clay:clay-new-product` **Then** the skill creates `products/<parent>/<sub-slug>/PRD.md` (or the equivalent feature path) and writes `parent: <parent-slug>` frontmatter. (FR-012)

## Functional Requirements

### Market intent classification

- **FR-001** `/clay:clay-idea` MUST prompt the user for market intent BEFORE routing to a downstream skill, AFTER overlap detection (current Step 2). Accepted values are exactly `internal`, `marketable`, `pmf-exploration`. The prompt MUST run on every invocation — there is no CLI flag, env var, or config shortcut. *(Source: PRD FR-001, NFR-003.)*
- **FR-002** `/clay:clay-idea` MUST write the user's selected intent into `products/<slug>/idea.md` as a frontmatter field `intent: <value>`. If `idea.md` does not yet exist, `/clay:clay-idea` MUST create it with at minimum the slug, date, and intent fields before invoking any downstream skill. *(Source: PRD FR-002.)*
- **FR-003** When `intent=internal`, `/clay:clay-idea` MUST NOT call `/clay:clay-idea-research`, MUST NOT call `/clay:clay-project-naming`, and MUST route directly to `/clay:clay-new-product` in a simplified mode. The simplified PRD MUST omit market-research sections, competitive landscape, and naming/branding sections; it MUST keep problem statement, user (the maintainer), requirements, and tech stack. *(Source: PRD FR-003.)*
- **FR-004** When `intent=pmf-exploration`, `/clay:clay-idea-research` MUST read the intent from `products/<slug>/idea.md` frontmatter and bias the research brief toward demand validation: customer discovery questions, signals of existing pain, willingness-to-pay proxies appear as the primary "Findings" section; competitor enumeration is secondary. *(Source: PRD FR-004.)*
- **FR-005** When `intent=marketable`, all downstream skill behavior MUST remain identical to current behavior — this is the baseline pipeline. *(Source: PRD FR-005.)*

### Nested product folders

- **FR-006** `/clay:clay-idea` MUST detect when the target `products/<slug>/` folder already exists AND is a parent per FR-007. When detected, it MUST present three options before any write: (a) create a sub-idea under that parent, (b) create a sibling parent product (different top-level slug), (c) abort. No silent overwrite of the existing folder. *(Source: PRD FR-006.)*
- **FR-007** A folder `products/<parent-slug>/` is identified as a **parent product** if and only if BOTH conditions hold:
  - `products/<parent-slug>/about.md` exists, AND
  - At least one immediate sub-folder `products/<parent-slug>/<child-slug>/` contains either `idea.md` or `PRD.md`.

  This check is purely filesystem-based (no frontmatter marker required). *(Source: PRD FR-007; locked by Decision 1 in plan.md.)*
- **FR-008** When `/clay:clay-idea` (or `/clay:clay-new-product --parent=<parent-slug>`) creates a sub-idea, the resulting `products/<parent>/<sub-slug>/idea.md` (and any `PRD.md` derived from it) MUST carry a `parent: <parent-slug>` frontmatter field. The `parent:` field is the authoritative source of truth for the relationship; filesystem layout follows it but the field is what downstream skills read. *(Source: PRD FR-008.)*
- **FR-009** `/clay:clay-list` MUST display parent products with their sub-ideas indented two spaces (or tree-prefixed with `├──` / `└──`) directly beneath the parent row in the output table. Parents without sub-ideas display unchanged from today (no extra indent on the parent row, no synthetic sub-rows). Top-level (flat) products without `parent:` frontmatter and without parent status display as today. *(Source: PRD FR-009.)*
- **FR-010** `/clay:clay-create-repo` MUST detect sub-ideas by reading `parent:` frontmatter from `products/<slug>/PRD.md` (or `idea.md` if PRD does not yet exist). When a sub-idea is detected AND its parent has ≥2 sub-ideas (i.e., the current sub-idea has at least one sibling), the skill MUST offer two options with shared-repo as the default: (a) **shared repo** for the parent containing this sub-idea as a feature PRD, (b) **separate repo** for just this sub-idea. *(Source: PRD FR-010.)*
- **FR-011** When the user selects shared-repo in FR-010, `/clay:clay-create-repo` MUST scaffold the sub-idea inside the shared repo at `docs/features/<YYYY-MM-DD>-<sub-slug>/PRD.md` (matching the kiln feature-PRD pattern documented in `clay-new-product` Mode C). It MUST NOT scaffold the sub-idea as the shared repo's top-level `docs/PRD.md`. If the shared repo already exists (i.e., a previous sub-idea created it), the skill reuses it instead of creating a new one. *(Source: PRD FR-011.)*
- **FR-012** `/clay:clay-new-product` MUST accept a `--parent=<parent-slug>` flag. When provided, it creates `products/<parent>/<sub-slug>/PRD.md` (Mode A nested) or `products/<parent>/<sub-slug>/features/<YYYY-MM-DD>-<feature-slug>/PRD.md` (Mode C nested), and writes `parent: <parent-slug>` frontmatter. The flag value MUST be validated: if `products/<parent-slug>/about.md` does not exist, the skill MUST stop and report the missing parent. *(Source: PRD FR-012.)*

## Non-Functional Requirements

- **NFR-001** No new runtime dependencies beyond what the clay plugin already uses (Markdown skills, Bash 5.x, `awk`/`sed` for frontmatter parsing). *(Source: PRD NFR-001.)*
- **NFR-002** Backwards compatibility: every existing flat `products/<slug>/` folder MUST continue to work unchanged across all 5 affected skills. Nesting behavior activates only when (a) `/clay:clay-idea` detects a parent collision, or (b) `/clay:clay-new-product --parent=<slug>` is invoked, or (c) a folder satisfies the FR-007 parent predicate. Existing `idea.md`/`PRD.md` files without `intent:` frontmatter MUST be treated as `intent: marketable` for routing purposes. *(Source: PRD NFR-002; backfill rule locked by Decision 2 in plan.md.)*
- **NFR-003** The intent classification prompt adds exactly one round-trip to `/clay:clay-idea` — the prompt is always asked, no flag shortcut, no remembered preference. *(Source: PRD NFR-003.)*

## Success Criteria

- **SC-001 — Intent classification round-trip.** Running `/clay:clay-idea "<idea>"` prompts for intent, records the selection in `products/<slug>/idea.md` as `intent: <value>`, and a subsequent `/clay:clay-idea-research` or `/clay:clay-new-product` reads that field without re-prompting.
  - **Verifies**: FR-001, FR-002.
  - **Method**: Manual run + `grep '^intent:' products/<slug>/idea.md`.

- **SC-002 — Internal-intent skips research.** Running `/clay:clay-idea "<idea>"` and answering `internal` produces a PRD without any market-research artifact (no `research.md`, no competitive-landscape section in the generated PRD).
  - **Verifies**: FR-003.
  - **Method**: Post-run `ls products/<slug>/` confirms no `research.md`; section-scan of generated PRD confirms no "Competitive Landscape" / "Market Research" / "Naming" sections.

- **SC-003 — Parent detection works.** Given a fixture `products/parent/about.md` plus `products/parent/child/idea.md`, running `/clay:clay-idea "<new sub-idea>"` with a slug that nests under `parent` offers the sub-idea option (a/b/c per FR-006).
  - **Verifies**: FR-006, FR-007.
  - **Method**: Scripted fixture + capture of the prompt text.

- **SC-004 — Nested listing displays hierarchy.** When a parent with ≥1 sub-idea exists, `/clay:clay-list` output shows the parent row first and each sub-idea indented (two spaces) or tree-prefixed (`├──` / `└──`) beneath it.
  - **Verifies**: FR-009.
  - **Method**: Eyeball + regex match on the listing output.

- **SC-005 — Shared repo for sub-ideas.** Running `/clay:clay-create-repo` against a parent with 2+ sub-ideas defaults to offering shared-repo creation; choosing shared-repo scaffolds each sub-idea as `docs/features/<YYYY-MM-DD>-<sub-slug>/PRD.md` inside the shared repo.
  - **Verifies**: FR-010, FR-011.
  - **Method**: Scripted fixture with 2 sub-ideas + post-run check of `docs/features/*/PRD.md` in the created repo.

- **SC-006 — Backwards compat.** Every existing flat `products/<slug>/` folder keeps working: `/clay:clay-list`, `/clay:clay-idea` (no parent collision), `/clay:clay-new-product` (no `--parent` flag), `/clay:clay-create-repo` (no `parent:` frontmatter) produce their pre-merge output unchanged.
  - **Verifies**: NFR-002, FR-005.
  - **Method**: Spot-check on an existing flat product (pre-merge output captured, post-merge output diffed).

## Out of Scope

- NLP-based auto-detection of market intent. The classification step always asks the user.
- Migration of existing flat `products/<slug>/` folders into nested structures.
- Multi-level nesting (sub-sub-ideas).
- Sub-ideas with incompatible tech stacks sharing a repo (falls back to separate repos manually).
- Changes to other plugins (kiln, shelf, trim, wheel) or the clay-project-naming / clay-idea-research skill bodies beyond the FR-004 demand-validation bias.

## Acceptance Notes

All FRs trace to PRD FR-001..FR-012 and NFR-001..NFR-003. All SCs trace to PRD SC-001..SC-006. The 3 plan-phase decisions (parent detection rule, missing-intent default, sub-idea frontmatter schema) are locked in `plan.md` per the team-lead brief.
