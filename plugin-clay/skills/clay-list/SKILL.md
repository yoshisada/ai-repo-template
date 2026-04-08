---
name: clay-list
description: List all products under products/ with their pipeline status (idea, researched, named, PRD-created, repo-created).
---

# Clay List — Product Portfolio Overview

Show all products under `products/` with their current pipeline status.

## Steps

### Step 1: Scan products directory

Check if the `products/` directory exists. If it does not exist, tell the user:

> No products found. Run `/clay:idea-research` to start your first product idea.

If it exists, list all subdirectories under `products/`.

### Step 2: Derive status for each product

For each product directory under `products/`, derive its status using this logic (check in this order — first match wins):

<!-- FR-036: clay_derive_status logic — keep identical with clay-sync workflow -->
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

Output a formatted table to the user:

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
- **named** → "Run `/clay:create-prd` to create a PRD"
- **prd-created** → "Run `/clay:create-repo` to create a GitHub repo"
- **repo-created** → "Run `/build-prd` in the repo to start building"
