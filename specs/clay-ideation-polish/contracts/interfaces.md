# Contracts: Clay Ideation Polish

**Spec**: [../spec.md](../spec.md)
**Plan**: [../plan.md](../plan.md)
**Date**: 2026-04-22

This file is the single source of truth for the data shapes and shared predicates introduced by this feature. All five affected skills MUST conform exactly. If any of these change, update this file FIRST and propagate to skills.

## 1. `intent:` frontmatter field

**Field name**: `intent`
**File**: `products/<slug>/idea.md` (and `products/<slug>/PRD.md` if generated downstream)
**Required on**: every NEW idea created by `/clay:clay-idea` after this PR
**Optional on**: pre-existing files (treated as `intent: marketable` per NFR-002 / Decision 2)

**Allowed values** (exact strings, lowercase):

| Value | Meaning | Downstream routing |
|-------|---------|--------------------|
| `internal` | Tool/automation for the maintainer themselves; no market | Skip research + naming; route directly to simplified `/clay:clay-new-product` |
| `marketable` | Standalone product intended for an external market (current default) | Full pipeline: research → naming → PRD (no behavior change) |
| `pmf-exploration` | Idea where product-market fit is the primary unknown | Research biased toward demand validation (FR-004); standard naming + PRD |

**Validation**: `/clay:clay-idea` MUST reject any other string and re-prompt. Skill bodies MUST treat unknown values as `marketable` for safety (no crash, no silent skip of research).

**Example frontmatter**:

```yaml
---
title: Email Digest
slug: email-digest
date: 2026-04-22
intent: pmf-exploration
---
```

## 2. `parent:` frontmatter field (sub-idea relationship)

**Field name**: `parent`
**File**: `products/<parent-slug>/<sub-slug>/idea.md` (and `products/<parent-slug>/<sub-slug>/PRD.md` if generated)
**Required on**: every sub-idea created by `/clay:clay-idea` (when nested) or `/clay:clay-new-product --parent=<slug>`
**Forbidden on**: parent products and flat top-level products

**Value**: the parent's slug — i.e., the directory name of the parent under `products/`.

**Validation rule** (for any skill writing this field): the value MUST equal the immediate-parent directory name on disk. `parent: foo` MUST live at `products/foo/<sub-slug>/idea.md`. If those disagree, the skill MUST stop and report the inconsistency rather than silently fix one or the other.

**Example sub-idea frontmatter** (full):

```yaml
---
title: Morning Briefing
slug: morning-briefing
date: 2026-04-22
status: idea
parent: personal-automations
intent: internal
---
```

## 3. Parent-detection predicate

**Name**: `is_parent_product(slug)`
**Inputs**: a top-level slug under `products/`
**Returns**: boolean (truthy if `slug` is a parent product per FR-007)

**Definition** (deterministic filesystem check; bash pseudocode authoritative):

```bash
is_parent_product() {
  local slug="$1"
  local parent_dir="products/$slug"

  # Condition 1: about.md must exist
  [ -f "$parent_dir/about.md" ] || return 1

  # Condition 2: at least one immediate sub-folder with idea.md or PRD.md
  for sub in "$parent_dir"/*/; do
    [ -d "$sub" ] || continue
    if [ -f "$sub/idea.md" ] || [ -f "$sub/PRD.md" ]; then
      return 0
    fi
  done

  return 1
}
```

**Notes**:

- Uses immediate sub-folders only; no recursion. PRD explicitly disallows multi-level nesting.
- Hidden directories (e.g., `.git`) do not match `*/` glob with default shell options — safe by default.
- The predicate is duplicated inline in each skill that needs it. There is no shared `lib/` for clay skills (skills are self-contained Markdown).
- Decision 1 (plan.md) locks this rule. The `kind: parent` frontmatter alternative is documented in plan.md as a follow-on, NOT implemented here.

## 4. Sub-idea-of-parent enumeration

**Name**: `list_sub_ideas(parent_slug)`
**Inputs**: a parent slug
**Returns**: list of sub-slugs (one per immediate sub-folder containing `idea.md` or `PRD.md`)

**Definition**:

```bash
list_sub_ideas() {
  local parent_slug="$1"
  local parent_dir="products/$parent_slug"
  for sub in "$parent_dir"/*/; do
    [ -d "$sub" ] || continue
    if [ -f "$sub/idea.md" ] || [ -f "$sub/PRD.md" ]; then
      basename "$sub"
    fi
  done
}
```

**Used by**:

- `/clay:clay-list` (Phase C) — to render sub-rows under each parent.
- `/clay:clay-create-repo` (Phase D, FR-010) — to detect "parent has ≥2 sub-ideas" before defaulting to shared-repo.

## 5. Frontmatter read helper (reference shape)

Every skill that reads `intent:` or `parent:` from a file uses the same idiom — extract the value of a key from a YAML frontmatter block delimited by `---` lines at the top of a Markdown file.

```bash
read_frontmatter_field() {
  local file="$1"
  local key="$2"
  awk -v k="$key" '
    BEGIN { in_fm=0 }
    /^---[[:space:]]*$/ { in_fm = !in_fm; if (!in_fm) exit; next }
    in_fm && $1 == k":" { sub(/^[^:]+:[[:space:]]*/, ""); print; exit }
  ' "$file"
}
```

Returns the bare value (no surrounding quotes, no trailing whitespace). Empty output if the key is absent or the file has no frontmatter.

## 6. Feature-PRD directory convention (shared-repo path)

When `/clay:clay-create-repo` scaffolds a sub-idea inside a shared parent repo (FR-011), the file MUST land at:

```
docs/features/<YYYY-MM-DD>-<sub-slug>/PRD.md
```

This matches the kiln feature-PRD convention used elsewhere (see `clay-new-product` Mode C; `kiln-create-prd` Mode C; `docs/features/2026-04-22-clay-ideation-polish/PRD.md` itself). Multiple sub-ideas in the same shared repo each get their own dated directory under `docs/features/`.

The shared repo's top-level `docs/PRD.md` MUST NOT be the sub-idea's PRD; it is reserved for the parent product's overall PRD (which may be derived from `products/<parent>/about.md` or left as a placeholder).

## 7. Status field for sub-ideas (clay-list interaction)

`/clay:clay-list`'s status derivation (currently in Step 2 of `clay-list/SKILL.md`) MUST work unchanged for sub-ideas. The check order (`.repo-url` → all 3 PRD files → `naming.md` → `research.md` → `idea`) operates on `products/<parent>/<sub-slug>/...` paths the same way it operates on `products/<slug>/...` paths today. No new status values introduced.

## 8. CLI flag parsing for `/clay:clay-new-product`

`/clay:clay-new-product` accepts a free-form `$ARGUMENTS` string today. The `--parent=<slug>` flag MUST be parsed as follows at the top of Step 0:

```bash
PARENT_SLUG=""
REMAINING_ARGS=""
for arg in $ARGUMENTS; do
  case "$arg" in
    --parent=*) PARENT_SLUG="${arg#--parent=}" ;;
    *) REMAINING_ARGS="$REMAINING_ARGS $arg" ;;
  esac
done
REMAINING_ARGS="${REMAINING_ARGS# }"  # trim leading space
```

If `PARENT_SLUG` is non-empty, validate `products/$PARENT_SLUG/about.md` exists; if not, stop with: `"--parent=$PARENT_SLUG provided but products/$PARENT_SLUG/about.md does not exist."`

The remaining args are then used as the original `$ARGUMENTS` would be (e.g., as the slug or feature description).
