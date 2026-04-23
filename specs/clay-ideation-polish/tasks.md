# Tasks: Clay Ideation Polish

**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Contracts**: [contracts/interfaces.md](./contracts/interfaces.md)
**Branch**: `build/clay-ideation-polish-20260422`
**Date**: 2026-04-22

Mark each task `[X]` immediately after completion. Commit after each phase.

---

## Phase A — Intent classification (FR-001..FR-005)

- [X] **A1.** Edit `plugin-clay/skills/clay-idea/SKILL.md`: insert a new **Step 2.5: Classify Market Intent** between current Step 2 (Overlap Analysis) and Step 3 (Present Routing Options). Always prompt the user with the three options (`internal`, `marketable`, `pmf-exploration`); reject any other input and re-prompt. Store the chosen value as a shell variable for use later in the skill body. Reference FR-001, NFR-003 in inline comments. *(One file edit; no other skills touched.)*
- [X] **A2.** Edit `plugin-clay/skills/clay-idea/SKILL.md`: in the same Step 2.5 (or a new Step 2.6 immediately after), write `intent: <value>` plus minimal frontmatter (`title`, `slug`, `date`, `intent`) into `products/<slug>/idea.md`. If `idea.md` already exists, update or insert the `intent:` field idempotently using the `read_frontmatter_field` idiom from contracts. Reference FR-002. *(One file edit.)*
- [X] **A3.** Edit `plugin-clay/skills/clay-idea/SKILL.md`: modify Step 4 ("Route to Downstream Skill") to branch on `intent`. When `intent=internal`, skip `/clay:clay-idea-research` and `/clay:clay-project-naming` entirely and route directly to `/clay:clay-new-product` in simplified mode (pass through a flag or context note that triggers Phase A's `clay-new-product` simplified-PRD branch). When `intent=marketable` or `intent=pmf-exploration`, behavior is unchanged from today. Reference FR-003, FR-005. *(One file edit.)*
- [X] **A4.** Edit `plugin-clay/skills/clay-idea-research/SKILL.md`: at the top of Step 1, read `intent:` from `products/<slug>/idea.md` (using the `read_frontmatter_field` idiom). If `intent=pmf-exploration`, reorganize the report template (Step 5) so the primary "Findings" section is **Demand Validation Signals** (customer discovery questions, pain signals, willingness-to-pay proxies); competitor enumeration moves to a secondary "Competitive Landscape" section. If `intent` is empty or unknown, behavior is unchanged. Reference FR-004, NFR-002. *(One file edit.)*
- [X] **A5.** Edit `plugin-clay/skills/clay-new-product/SKILL.md`: at the top of Step 1, read `intent:` from `products/<slug>/idea.md` (if it exists). If `intent=internal`, switch to a "simplified PRD" sub-mode that (a) skips reading `naming.md` and `research.md`, (b) drops the "Competitive Landscape", "Naming/Branding", and "Market Research" sections from the generated PRD, (c) keeps Problem Statement, Users (single-user: the maintainer), Requirements, and Tech Stack. Reference FR-003. *(One file edit.)*
- [X] **A6.** Commit Phase A: `git add plugin-clay/skills/clay-idea plugin-clay/skills/clay-idea-research plugin-clay/skills/clay-new-product specs/clay-ideation-polish && git commit -m "feat(clay-ideation-polish): Phase A — intent classification (FR-001..FR-005)"`. Mark A1-A5 `[X]` in this file, then this task `[X]`.

## Phase B — Parent detection + sub-idea creation (FR-006..FR-008, FR-012)

- [X] **B1.** Edit `plugin-clay/skills/clay-idea/SKILL.md`: insert **Step 2.6: Parent Collision Check** immediately after Step 2.5 (intent). Inline the `is_parent_product()` predicate from contracts. If the derived target slug matches a parent product, present the three options (a) sub-idea under parent, (b) sibling parent (different top-level slug), (c) abort. Wait for user choice. Reference FR-006, FR-007. *(One file edit.)* *(Note: implemented as Step 2.7 in Phase A edit; content matches B1 requirements.)*
- [X] **B2.** Edit `plugin-clay/skills/clay-idea/SKILL.md`: when the user selects "sub-idea" in B1, prompt for the sub-slug, create `products/<parent>/<sub-slug>/idea.md` with the full sub-idea frontmatter from contracts §2 (`title`, `slug`, `date`, `status: idea`, `parent: <parent-slug>`, `intent: <chosen>`). Then continue to Step 3 (routing), targeting the sub-idea's path. Reference FR-008. *(Same file as B1 — separate task to keep the diff small.)* *(Note: implemented as Step 2.8 in Phase A edit.)*
- [X] **B3.** Edit `plugin-clay/skills/clay-new-product/SKILL.md`: add Step 0a "Parse `--parent=<slug>` flag" before Step 0 (Detect Mode), using the parser snippet from contracts §8. If `--parent` is provided: validate `products/<parent>/about.md` exists (else stop with the exact error message from contracts); set `OUTPUT_BASE="products/<parent>/<sub-slug>"`. Reference FR-012. *(One file edit.)*
- [X] **B4.** Edit `plugin-clay/skills/clay-new-product/SKILL.md`: in Step 4 (Generate PRD Artifacts), when `OUTPUT_BASE` is a nested path (per B3), inject `parent: <parent-slug>` into the frontmatter of every generated file (`PRD.md`, `PRD-MVP.md`, `PRD-Phases.md`, or feature `PRD.md`). Reference FR-008, FR-012. *(Same file as B3.)*
- [X] **B5.** Commit Phase B: `git add plugin-clay/skills/clay-idea plugin-clay/skills/clay-new-product specs/clay-ideation-polish && git commit -m "feat(clay-ideation-polish): Phase B — parent detection + sub-idea (FR-006..FR-008, FR-012)"`. Mark B1-B4 `[X]`, then this task `[X]`.

## Phase C — Nested display in clay-list (FR-009)

- [X] **C1.** Edit `plugin-clay/skills/clay-list/SKILL.md`: in Step 1 (after listing subdirectories), classify each top-level slug as **parent** (per `is_parent_product()`), **flat** (no `about.md` / no qualifying sub-folders), or **sub-idea** (has `parent:` frontmatter — but sub-ideas are nested under parents, not at top level, so this branch only fires if a misplaced sub-idea exists). Inline the `is_parent_product()` and `list_sub_ideas()` helpers from contracts. *(One file edit.)*
- [X] **C2.** Edit `plugin-clay/skills/clay-list/SKILL.md`: in Step 4 (Display table), render parents first with their sub-ideas indented two spaces beneath. The status/artifacts columns for sub-ideas use the same status-derivation logic as flat products (operating on the `products/<parent>/<sub-slug>/...` path). Flat products render unchanged. Update the example table in the skill body to show the nested format. Reference FR-009, NFR-002. *(Same file as C1.)*
- [X] **C3.** Commit Phase C: `git add plugin-clay/skills/clay-list specs/clay-ideation-polish && git commit -m "feat(clay-ideation-polish): Phase C — nested display in clay-list (FR-009)"`. Mark C1-C2 `[X]`, then this task `[X]`.

## Phase D — Shared-repo default + feature-PRD scaffold (FR-010, FR-011)

- [ ] **D1.** Edit `plugin-clay/skills/clay-create-repo/SKILL.md`: in Step 1 (after resolving the product slug), read `parent:` frontmatter from `products/<slug>/PRD.md` (or `idea.md` if PRD absent). Set `IS_SUB_IDEA=true` if `parent:` is non-empty. If `IS_SUB_IDEA`, run `list_sub_ideas(parent)` (inlined from contracts §4); set `PARENT_HAS_SIBLINGS=true` if the count is ≥2. Reference FR-010. *(One file edit.)*
- [ ] **D2.** Edit `plugin-clay/skills/clay-create-repo/SKILL.md`: when `IS_SUB_IDEA && PARENT_HAS_SIBLINGS`, present a 2-option prompt with **shared repo** as default (option a): (a) shared repo for the parent containing this sub-idea as a feature PRD, (b) separate repo for just this sub-idea. If shared-repo chosen, check whether `products/<parent>/.repo-url` already exists; if yes, reuse the URL; if no, create the shared repo named after the parent (`gh repo create ... <parent-slug>`). Reference FR-010, FR-011. *(Same file as D1.)*
- [ ] **D3.** Edit `plugin-clay/skills/clay-create-repo/SKILL.md`: in Step 5 (Seed PRD Artifacts), when shared-repo path is active, scaffold the sub-idea at `<local-path>/docs/features/<YYYY-MM-DD>-<sub-slug>/PRD.md` (NOT at `<local-path>/docs/PRD.md`). Copy from `products/<parent>/<sub-slug>/PRD.md`. Update Step 7.5 (clay.config) to record the shared repo under the parent slug, and write `products/<parent>/<sub-slug>/.repo-url` pointing at the shared repo URL (so `/clay:clay-list` shows status `repo-created` for the sub-idea). Reference FR-011. *(Same file as D1, D2.)*
- [ ] **D4.** Commit Phase D: `git add plugin-clay/skills/clay-create-repo specs/clay-ideation-polish && git commit -m "feat(clay-ideation-polish): Phase D — shared-repo default + feature-PRD (FR-010, FR-011)"`. Mark D1-D3 `[X]`, then this task `[X]`.

## Phase E — Smoke fixtures + docs (SC-002, SC-003, SC-005, SC-006)

- [ ] **E1.** Create three fixture directories under `specs/clay-ideation-polish/fixtures/`:
  - `flat-product/products/standalone-tool/idea.md` (flat, intent absent — backwards-compat)
  - `parent-with-one-sub/products/personal-automations/about.md` + `.../email-digest/idea.md` (parent + one sub for parent-detection smoke)
  - `parent-with-two-subs/products/personal-automations/about.md` + `.../email-digest/idea.md` + `.../morning-briefing/idea.md` (parent + two subs for shared-repo smoke)

  Each `idea.md` carries the full frontmatter per contracts §1 and §2. The fixtures are README-style — they are NOT real products, just shape examples.
- [ ] **E2.** Create `specs/clay-ideation-polish/SMOKE.md` documenting the 6 manual commands that verify SC-001..SC-006, each pointing at the relevant fixture. Commit Phase E: `git add specs/clay-ideation-polish && git commit -m "docs(clay-ideation-polish): Phase E — smoke fixtures + SMOKE.md"`. Mark E1 `[X]`, then this task `[X]`.

---

## Definition of Done

- [ ] All 5 affected skills updated; each FR (FR-001..FR-012) traceable to a specific edit.
- [ ] All 3 NFRs verified (no new deps, backwards-compat preserved on existing flat products, intent prompt is one round-trip).
- [ ] All 6 SCs have a corresponding smoke command in `SMOKE.md`.
- [ ] Each phase committed separately per CLAUDE.md "incremental progress" rule.
- [ ] PRD audit run after Phase E (auditor task #3).

## Notes for Implementer

- No `src/` files exist in this plugin repo, so the 4-gate require-spec hooks do not fire on these edits. You will be editing skill bodies (Markdown), templates, and spec artifacts only.
- Inline the `is_parent_product()` / `list_sub_ideas()` / `read_frontmatter_field` helpers in each skill that needs them. Do NOT create a shared helper file — clay skills are self-contained.
- The `intent:` and `parent:` field semantics are locked in `contracts/interfaces.md`. If you find a need to change them, update contracts FIRST, then propagate.
- The PRD's two implementation-time judgment calls (incompatible tech stacks for shared-repo; `--parent` flag parsing) are documented in plan.md "Open Questions Carried Into Implement". Resolve both inline per the guidance there.
