# Smoke Tests — Clay Ideation Polish

**Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Tasks**: [tasks.md](./tasks.md)

Manual verification for Success Criteria SC-001..SC-006. Each command references a fixture under `specs/clay-ideation-polish/fixtures/`. Run from the repo root; copy the relevant fixture tree into a scratch `products/` directory when the skill writes real files.

---

## SC-001 — Intent classification round-trip

**Fixture**: none required (exercises the live prompt)

**Command**:
```
/clay:clay-idea "a CLI that watches my inbox and emails me a daily digest"
```

**Verify**:
- The skill prompts for intent (Step 2.5) with three options — `internal`, `marketable`, `pmf-exploration`.
- After answering `internal`, check: `grep '^intent:' products/<slug>/idea.md` → `intent: internal`
- Subsequent `/clay:clay-new-product` against the same slug does not re-prompt for intent.

**Passes**: FR-001, FR-002.

---

## SC-002 — Internal-intent skips research + naming

**Fixture**: none required

**Command**:
```
/clay:clay-idea "a local script to rotate my home folder backups"
# answer: internal at the intent prompt
# confirm "New product" route
```

**Verify**:
- `ls products/<slug>/` shows `idea.md` and `PRD.md`/`PRD-MVP.md`/`PRD-Phases.md`, but **no `research.md`** and **no `naming.md`**.
- The generated PRD does NOT contain sections titled "Competitive Landscape", "Market Research", or "Naming / Branding".

**Passes**: FR-003.

---

## SC-003 — Parent detection offers sub-idea option

**Fixture**: `fixtures/parent-with-one-sub/`

**Setup**:
```bash
cp -r specs/clay-ideation-polish/fixtures/parent-with-one-sub/products/* products/
```

**Command**:
```
/clay:clay-idea "a script that summarizes my morning calendar"
# the slug derived should nest under "personal-automations"
```

**Verify**:
- After overlap analysis, the skill presents the 3-way collision prompt (sub-idea / sibling parent / abort — see Step 2.7 of `clay-idea/SKILL.md`).
- Choosing "sub-idea" writes `products/personal-automations/<sub-slug>/idea.md` with `parent: personal-automations` frontmatter.

**Passes**: FR-006, FR-007, FR-008.

---

## SC-004 — Nested listing in `/clay:clay-list`

**Fixture**: `fixtures/parent-with-two-subs/`

**Setup**:
```bash
cp -r specs/clay-ideation-polish/fixtures/parent-with-two-subs/products/* products/
```

**Command**:
```
/clay:clay-list
```

**Verify**:
- `personal-automations` renders as a parent row first.
- `email-digest` and `morning-briefing` render beneath it, each indented two spaces in the Product column.
- Any other flat top-level products in `products/` render after the parent group, at zero indentation (backwards compat).

**Passes**: FR-009.

---

## SC-005 — Shared-repo default for multi-sub-idea parent

**Fixture**: `fixtures/parent-with-two-subs/`

**Setup**: same as SC-004.

**Command**:
```
/clay:clay-create-repo personal-automations/email-digest
```

**Verify**:
- Step 1a reads `parent: personal-automations` from `products/personal-automations/email-digest/PRD.md` (or idea.md if PRD absent). `IS_SUB_IDEA=true`.
- Step 1a counts siblings via `list_sub_ideas personal-automations` → 2 (email-digest + morning-briefing). `PARENT_HAS_SIBLINGS=true`.
- Step 1b presents the 2-option prompt with shared-repo as default (option 1).
- Choosing shared-repo: Step 3 creates `gh repo create <owner>/personal-automations` (named after the parent, not the sub).
- Step 5 scaffolds the sub-idea PRD at `<local-path>/docs/features/<YYYY-MM-DD>-email-digest/PRD.md` — NOT at `<local-path>/docs/PRD.md`.
- Step 7.5 appends `personal-automations` (not `email-digest`) to `clay.config`.
- Step 8 writes BOTH `products/personal-automations/.repo-url` and `products/personal-automations/email-digest/.repo-url` pointing at the shared repo URL.

Then run:
```
/clay:clay-create-repo personal-automations/morning-briefing
```

- Step 1c detects `products/personal-automations/.repo-url` already exists → reuses the URL.
- Step 3 CLONES (does not create) the shared repo.
- Step 5 scaffolds `docs/features/<YYYY-MM-DD>-morning-briefing/PRD.md` alongside the earlier feature directory.
- Step 7.5 does NOT append a duplicate `personal-automations` row to `clay.config`.
- Step 8 writes `products/personal-automations/morning-briefing/.repo-url` only (parent marker already exists).

**Passes**: FR-010, FR-011.

---

## SC-006 — Backwards compat on flat products

**Fixture**: `fixtures/flat-product/`

**Setup**:
```bash
cp -r specs/clay-ideation-polish/fixtures/flat-product/products/* products/
```

**Commands** (each should behave identically to pre-PRD output):

1. `/clay:clay-list` — `standalone-tool` renders as a flat row, zero indentation.
2. `/clay:clay-idea "some unrelated idea"` — no parent collision (standalone-tool has no `about.md` + sub-folders). The intent prompt still fires (FR-001 always prompts) — this is the only user-visible change and is per NFR-003.
3. `/clay:clay-new-product standalone-tool` — no `--parent` flag, so flow is identical to today. Missing `intent:` on `standalone-tool/idea.md` is treated as `marketable` (Decision 2), so the full PRD template is used.
4. `/clay:clay-create-repo standalone-tool` — no `parent:` frontmatter, so `IS_SUB_IDEA=false`. No shared-repo prompt. Flow is identical to today.

**Passes**: NFR-002, FR-005.

---

## Notes for reviewers

- Each fixture is a read-only shape reference. Copy it into a scratch `products/` directory to exercise the skill.
- Every success criterion above was traced through the skill bodies during implementation — see `specs/clay-ideation-polish/smoke-results.md` for the static code-path walkthrough.
- Full slash-command live runs require a clean working tree and the clay plugin installed; this SMOKE.md is the runbook for the human operator doing the pre-merge check.
