---
name: clay-list
description: List all products under products/ with their pipeline status (idea, researched, named, PRD-created, repo-created).
---

# Clay List — Product Portfolio Overview

Show all products under `products/` with their current pipeline status.

## Steps

### Step 1: Scan products directory

Check if the `products/` directory exists. If it does not exist, tell the user:

> No products found. Run `/clay:clay-idea-research` to start your first product idea.

If it exists, list all subdirectories under `products/`.

<!-- FR-009: Classify each top-level slug as parent / flat / sub-idea for nested rendering. -->
<!-- NFR-002: Flat products without parent/sub markers render unchanged. -->
<!-- Contracts §3, §4: is_parent_product() + list_sub_ideas() inlined here. -->

For each top-level slug, classify it:

```bash
# is_parent_product — slug has about.md AND ≥1 sub-folder with idea.md or PRD.md
is_parent_product() {
  local slug="$1"
  local parent_dir="products/$slug"
  [ -f "$parent_dir/about.md" ] || return 1
  for sub in "$parent_dir"/*/; do
    [ -d "$sub" ] || continue
    if [ -f "$sub/idea.md" ] || [ -f "$sub/PRD.md" ]; then
      return 0
    fi
  done
  return 1
}

# list_sub_ideas — enumerate immediate sub-folders that contain idea.md or PRD.md
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

# read_frontmatter_field — used to detect misplaced sub-ideas at top level
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

Classification rules:

- **parent** — `is_parent_product "$slug"` returns true. Render the parent row; then render each sub-idea from `list_sub_ideas "$slug"` indented two spaces beneath.
- **sub-idea (misplaced)** — `products/$slug/idea.md` or `PRD.md` has `parent:` frontmatter non-empty. Sub-ideas are normally nested under parents, so hitting this branch at the top level means a misplaced file; render it with a warning marker (e.g., `(orphaned sub-idea, parent: <parent>)`).
- **flat** — everything else (no `about.md`, or `about.md` but no qualifying sub-folders, and no `parent:` frontmatter). Renders exactly as today (NFR-002).

### Step 1.5: Read Clay Config

<!-- FR-011, FR-014: Read clay.config for repo URLs and local paths -->
<!-- FR-012: Gracefully skip if clay.config doesn't exist -->
If `clay.config` exists at the project root, read it line by line and build a lookup map:

- **Format**: `<product-slug> <repo-url> <local-path> <created-date>`
- Each line has exactly 4 space-separated fields
- Lines starting with `#` are comments — skip them
- Lines that don't have exactly 4 fields are malformed — skip them silently
- Build a map: `slug → { url, local_path, date }`

If `clay.config` does not exist, skip this step. The output table will not include repo columns.

Set a flag `HAS_CLAY_CONFIG` to true/false based on whether the file was found and parsed.

### Step 2: Derive status for each product

For each product directory under `products/`, derive its status using this logic (check in this order — first match wins):

<!-- FR-036: clay_derive_status logic — keep identical with clay:sync workflow -->
1. If `products/<slug>/.repo-url` exists → status is **repo-created**
2. If `products/<slug>/PRD.md` AND `products/<slug>/PRD-MVP.md` AND `products/<slug>/PRD-Phases.md` all exist → status is **prd-created**
3. If `products/<slug>/naming.md` exists → status is **named**
4. If `products/<slug>/research.md` exists → status is **researched**
5. Otherwise → status is **idea**

### Step 3: Count artifacts

For each product, count how many of these artifacts exist:
- `research.md`
- `naming.md`
- `PRD.md`
- `PRD-MVP.md`
- `PRD-Phases.md`
- `.repo-url`

### Step 4: Display table

<!-- FR-009: Render parents first with sub-ideas indented two spaces. Flat products unchanged. -->
<!-- NFR-002: Flat products (pre-nesting layout) render identically to pre-PRD behavior. -->

Output a formatted table to the user. The table format depends on whether `clay.config` was found in Step 1.5.

**Rendering order**:

1. Group top-level slugs into **parents** (with sub-ideas) and **flat** products (no nesting).
2. Render parents first. For each parent: emit the parent row, then for each sub-idea from `list_sub_ideas "<parent>"`, emit a row where the Product column is prefixed with two spaces (`  <sub-slug>`).
3. Render flat products after all parents. Flat rows have no indentation — identical to today.
4. Sub-idea status/artifact derivation uses the same logic as flat products (Step 2/3), operating on the path `products/<parent>/<sub-slug>/...`.
5. If a misplaced top-level sub-idea exists (top-level slug with `parent:` frontmatter), render it as a flat row with a trailing marker `(orphaned sub-idea, parent: <parent>)` in the Status column.

**When `HAS_CLAY_CONFIG` is true** — include Repo URL and Local Path columns:

```
Product Portfolio
=================

| Product                 | Status       | Artifacts | Repo URL                                       | Local Path              |
|-------------------------|--------------|-----------|------------------------------------------------|-------------------------|
| personal-automations    | —            | —         | https://github.com/user/personal-automations   | ../personal-automations |
|   email-digest          | prd-created  | 4/6       | (shared: personal-automations)                 | (shared)                |
|   morning-briefing      | idea         | 1/6       | (shared: personal-automations)                 | (shared)                |
| standalone-tool         | researched   | 1/6       | —                                              | —                       |
| my-product              | repo-created | 5/6       | https://github.com/user/my-product             | ../my-product           |

Total: 4 products (1 parent with 2 sub-ideas, 2 flat)
```

For parent rows: if the parent itself has no repo yet, show `—` in the repo columns; if there is a shared repo for the parent (set in Phase D when `/clay:clay-create-repo` creates one), show its URL on the parent row. Sub-idea rows show `(shared: <parent>)` when their `.repo-url` points at the parent's shared repo; otherwise they show their own repo URL.

For each non-nested product, look up its slug in the clay.config map from Step 1.5. If found, show the repo URL and local path. If not found, show "—" in both columns.

**When `HAS_CLAY_CONFIG` is false** — render the table without repo columns:

```
Product Portfolio
=================

| Product                 | Status       | Artifacts |
|-------------------------|--------------|-----------|
| personal-automations    | —            | —         |
|   email-digest          | prd-created  | 4/6       |
|   morning-briefing      | idea         | 1/6       |
| standalone-tool         | researched   | 1/6       |
| my-product              | prd-created  | 4/6       |

Total: 4 products (1 parent with 2 sub-ideas, 2 flat)
```

Parent rows without their own artifacts show `—` in Status and Artifacts (the parent's status is derived from its children, not from direct PRD files at `products/<parent>/`).

<!-- FR-037: directory structure convention -->
Each product directory follows the structure:
- `products/<slug>/research.md`
- `products/<slug>/naming.md`
- `products/<slug>/PRD.md`
- `products/<slug>/PRD-MVP.md`
- `products/<slug>/PRD-Phases.md`
- `products/<slug>/.repo-url`

### Step 5: Suggest next actions

For each product, suggest the next pipeline step based on its status:

- **idea** → "Run `/clay:clay-idea-research` to research the market"
- **researched** → "Run `/clay:clay-project-naming` to find a name"
- **named** → "Run `/clay:clay-new-product` to create a PRD"
- **prd-created** → "Run `/clay:clay-create-repo` to create a GitHub repo"
- **repo-created** → "Run `/kiln:kiln-build-prd` in the repo to start building"
