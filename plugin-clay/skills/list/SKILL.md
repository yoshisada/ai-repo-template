---
name: list
description: List all products under products/ with their pipeline status (idea, researched, named, PRD-created, repo-created).
---

# Clay List — Product Portfolio Overview

Show all products under `products/` with their current pipeline status.

## Steps

### Step 1: Scan products directory

Check if the `products/` directory exists. If it does not exist, tell the user:

> No products found. Run `/clay:idea-research` to start your first product idea.

If it exists, list all subdirectories under `products/`.

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

Output a formatted table to the user. The table format depends on whether `clay.config` was found in Step 1.5.

**When `HAS_CLAY_CONFIG` is true** — include Repo URL and Local Path columns:

```
Product Portfolio
=================

| Product        | Status       | Artifacts | Repo URL                              | Local Path     |
|----------------|--------------|-----------|---------------------------------------|----------------|
| my-product     | repo-created | 5/6       | https://github.com/user/my-product    | ../my-product  |
| another-idea   | researched   | 1/6       | —                                     | —              |
| quick-thought  | idea         | 0/6       | —                                     | —              |

Total: 3 products
```

For each product, look up its slug in the clay.config map from Step 1.5. If found, show the repo URL and local path. If not found, show "—" in both columns.

**When `HAS_CLAY_CONFIG` is false** — render the table without repo columns:

```
Product Portfolio
=================

| Product        | Status       | Artifacts |
|----------------|--------------|-----------|
| my-product     | prd-created  | 4/6       |
| another-idea   | researched   | 1/6       |
| quick-thought  | idea         | 0/6       |

Total: 3 products
```

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

- **idea** → "Run `/clay:idea-research` to research the market"
- **researched** → "Run `/clay:project-naming` to find a name"
- **named** → "Run `/clay:new-product` to create a PRD"
- **prd-created** → "Run `/clay:create-repo` to create a GitHub repo"
- **repo-created** → "Run `/kiln:build-prd` in the repo to start building"
