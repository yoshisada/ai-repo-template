# Smoke Results — Clay Ideation Polish

**Date**: 2026-04-22
**Implementer**: team implementer (Opus 4.7)
**Branch**: `build/clay-ideation-polish-20260422`

## Scope of this check

The clay plugin has no automated test suite (see `CLAUDE.md`: "There is no test suite for the plugin itself"). Verification is manual. Slash-command invocation is not available from this implementer agent session, so this document records a **static code-path walkthrough**: for each of SC-001..SC-006, trace through the updated SKILL.md bodies against the fixtures under `specs/clay-ideation-polish/fixtures/` and confirm the inline bash/reasoning would produce the expected outcome.

Full live slash-command runs are the user's pre-merge check (runbook in `SMOKE.md`).

## Pre-existing flat-product spot-check

`ls products/` at implementation time returned no directory (`NO_PRODUCTS_DIR`). There are no existing flat products in this plugin source repo, so backwards-compat verification relies entirely on the `fixtures/flat-product/` fixture. If the branch is later merged and a consumer project holds flat `products/<slug>/` folders created before this PR, the skill bodies are unchanged for the flat code paths (see SC-006 walkthrough).

---

## SC-001 — Intent classification round-trip

**Expected**: `/clay:clay-idea` prompts for intent, records `intent:` in `products/<slug>/idea.md`, downstream reads.

**Walkthrough** against `plugin-clay/skills/clay-idea/SKILL.md`:

1. Step 2.5 (new) prompts the user with three literal options. The bash normalization block rejects unknown values and re-prompts.
2. Step 2.6 (new) creates `products/$SLUG/idea.md` with the 4-field minimal frontmatter when the file is absent. When it exists without `intent:`, the `awk` idempotent insert fires. When it exists with `intent:`, the replace branch updates in-place. Verified by reading the three code paths: first `if [ ! -f "$IDEA_FILE" ]` → create; `elif [ -z "$(read_frontmatter_field ...)" ]` → insert; `else` → replace.
3. `plugin-clay/skills/clay-idea-research/SKILL.md` Step 1.0 (new) reads the same field via the `read_frontmatter_field` helper. Missing → defaults to `marketable` per Decision 2.
4. `plugin-clay/skills/clay-new-product/SKILL.md` Step 1.0 (new) reads the same field. Missing → `marketable`.

**Result**: PASS (static walkthrough). The intent value round-trips via a shared frontmatter substrate and shared helper idiom.

---

## SC-002 — Internal-intent skips research and naming

**Expected**: `intent=internal` → no `research.md`, no `naming.md`, no competitive-landscape / naming sections in the PRD.

**Walkthrough**:

1. `clay-idea/SKILL.md` Step 4 (modified) has three branches on `$INTENT`. The `internal` branch explicitly skips `/clay:clay-idea-research` and `/clay:clay-project-naming` and routes directly to `/clay:clay-new-product`.
2. `clay-new-product/SKILL.md` Step 1.0 (new) detects `$INTENT=internal` and switches to simplified PRD mode: skips reading `research.md`/`naming.md`, drops the three listed sections, keeps problem / users / requirements / tech stack.

**Result**: PASS (static walkthrough). No `research.md` or `naming.md` are written because the invoking skill routes around them; the simplified PRD mode blocks the sections at template-fill time.

---

## SC-003 — Parent detection offers sub-idea option

**Fixture**: `parent-with-one-sub/`.

**Walkthrough** against `clay-idea/SKILL.md` Step 2.7:

1. `is_parent_product("personal-automations")` against the fixture: `about.md` exists → condition 1 passes. Loop over `products/personal-automations/*/`: `email-digest/` contains `idea.md` → condition 2 passes → returns true.
2. Step 2.7 fires the 3-option prompt. Choosing option 1 proceeds to Step 2.8.
3. Step 2.8 creates `products/personal-automations/<sub-slug>/idea.md` with full frontmatter per contracts §2 (`title`, `slug`, `date`, `status: idea`, `parent: personal-automations`, `intent: <chosen>`).

**Result**: PASS. Parent detection predicate matches the fixture shape; sub-idea frontmatter matches contracts §2.

---

## SC-004 — Nested listing

**Fixture**: `parent-with-two-subs/`.

**Walkthrough** against `clay-list/SKILL.md`:

1. Step 1 (modified) classifies `personal-automations` via `is_parent_product`. With `about.md` + two qualifying sub-folders present, returns true → classified as parent.
2. Step 4 (modified) renders parent row first, then emits sub-rows with two-space indent. Both `email-digest` and `morning-briefing` appear indented beneath.
3. If any other flat products exist at top level, they render after the parent group at zero indentation.

**Result**: PASS.

---

## SC-005 — Shared-repo default

**Fixture**: `parent-with-two-subs/`.

**Walkthrough** against `clay-create-repo/SKILL.md`:

1. Step 1a reads `parent:` from `products/personal-automations/email-digest/PRD.md` (or `idea.md`). Fixture has idea.md with `parent: personal-automations` → `IS_SUB_IDEA=true`, `PARENT_SLUG=personal-automations`, `SUB_SLUG=email-digest`.
2. `list_sub_ideas("personal-automations")` enumerates both sub-folders → `SIBLING_COUNT=2` → `PARENT_HAS_SIBLINGS=true`.
3. Step 1b fires the 2-option prompt with shared-repo as default.
4. Step 1c checks `products/personal-automations/.repo-url` → absent on first run → `SHARED_REPO_URL=""`. Step 3 creates a new repo named `personal-automations`.
5. Step 5 (shared-repo branch) writes sub-idea PRD to `<local-path>/docs/features/<date>-email-digest/PRD.md`. Does NOT overwrite `docs/PRD.md`.
6. Step 7.5 (shared-repo branch) appends `personal-automations` to `clay.config` IF no existing row. Skips duplicate on second run.
7. Step 8 (shared-repo branch) writes both parent-level and sub-level `.repo-url` markers.

Second run against `morning-briefing`:

8. Step 1c finds `products/personal-automations/.repo-url` → reuses URL. Step 3 clones instead of creating. Step 7.5 detects existing row and skips append. Step 8 writes sub-level marker only (parent marker already exists).

**Result**: PASS.

---

## SC-006 — Backwards compat

**Fixture**: `flat-product/standalone-tool/`.

**Walkthrough**:

1. `/clay:clay-list`: Step 1 classifies `standalone-tool` via `is_parent_product` → `about.md` absent → returns false. Not a parent. Check for `parent:` frontmatter on its `idea.md` — absent. Classified as flat. Renders at zero indentation per Step 4 flat-product path.
2. `/clay:clay-idea`: Step 2.7 collision check calls `is_parent_product(derived_slug)`. If the derived slug does not match `standalone-tool`, no collision. If the derived slug DOES match `standalone-tool`, the predicate returns false (no `about.md`), so no sub-idea prompt. The intent prompt itself still fires (FR-001 always prompts) — this is the only user-visible behavior change.
3. `/clay:clay-new-product standalone-tool`: Step 0a sees no `--parent=` flag → `IS_SUB_IDEA=false`. Step 1.0 reads `intent:` from `standalone-tool/idea.md` → absent → defaults to `marketable`. Full pipeline runs as today.
4. `/clay:clay-create-repo standalone-tool`: Step 1a reads `parent:` from `standalone-tool/PRD.md` or `idea.md` → absent → `IS_SUB_IDEA=false`. Step 1b skipped entirely. Step 3 flat-product branch fires. Step 5 flat-product branch fires. Step 7.5 flat-product branch fires. Step 8 flat-product branch fires.

**Result**: PASS. Every flat code path is gated on `IS_SUB_IDEA=false` or negative-detection checks; no behavior change when the sub-idea signal is absent.

---

## Deferred items (require live slash-command invocation)

The following are DEFERRED to the user's pre-merge check because they depend on real slash-command dispatch and external state that this agent session cannot reach:

- Actual `gh repo create` against GitHub (network + auth).
- Actual Claude Code prompt rendering (the skill prompt blocks are Markdown, not live UI).
- Real WebSearch calls from `clay-idea-research` to verify the demand-validation report template fills correctly with live data.

The runbook in `SMOKE.md` lists each of these for the human operator.
