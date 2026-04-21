---
name: idea
description: Primary entrypoint for the clay plugin. Takes a raw idea, checks products/ and clay.config for overlap with existing products and repos, then routes to the right next step. Use as the starting point for any new idea.
---

# Idea — Clay Entrypoint

Take a raw product idea and figure out the best next step: create something new, add to an existing product, or work in an existing repo.

## User Input

```text
$ARGUMENTS
```

<!-- FR-001: Accept idea description as input, prompt if empty -->
If `$ARGUMENTS` is not empty, use it as the idea description.

If `$ARGUMENTS` is empty, ask the user:

> Describe your idea in 1-5 sentences. What does it do? Who is it for?

Wait for their response before proceeding. Store the idea description for use in subsequent steps.

## Step 1: Gather Context

Collect information about existing products and tracked repos so we can check for overlap.

<!-- FR-002: Read all products from products/ directory -->
### 1a. Scan products/ directory

If the `products/` directory exists, read each subdirectory under it. For each product slug:

1. Read `products/<slug>/research.md` if it exists — extract the product name and description
2. Read `products/<slug>/naming.md` if it exists — extract the chosen name and tagline
3. Read `products/<slug>/PRD.md` if it exists — extract the product summary / elevator pitch

Build a list of existing products with their key attributes (slug, name, description, summary). If a product has none of these files, just record the slug.

If `products/` does not exist or is empty, note that there are no existing products and move on.

<!-- FR-003, FR-010: Read clay.config for tracked repos -->
<!-- FR-012: Gracefully skip if clay.config doesn't exist -->
### 1b. Read clay.config

If `clay.config` exists at the project root, read it line by line:

- **Format**: `<product-slug> <repo-url> <local-path> <created-date>`
- Each line has exactly 4 space-separated fields
- Lines starting with `#` are comments — skip them
- Lines that don't have exactly 4 fields are **malformed** — skip them and note a warning (e.g., "Skipping malformed clay.config line: ...")
- Build a list of tracked repos with their slug, URL, local path, and creation date

If `clay.config` does not exist, skip this step entirely. Do not warn — this is expected for new setups.

## Step 2: Overlap Analysis

<!-- FR-004: Compare input idea against existing products and tracked repos -->
Compare the user's idea description against:

1. **Existing products** from the `products/` scan (Step 1a)
2. **Tracked repos** from `clay.config` (Step 1b)

For each existing product or tracked repo, assess whether the user's idea has **semantic overlap** — meaning it covers similar functionality, targets the same users, or solves the same problem.

This is **LLM reasoning**, not string matching. Consider:
- Does the idea solve the same core problem?
- Does it target the same audience?
- Would it duplicate functionality that already exists?
- Is it a feature that belongs in an existing product rather than a new one?

For each match found, explain **why** it overlaps (e.g., "Your idea for a 'task list with reminders' overlaps with todo-app because both manage tasks and deadlines").

If no overlap is found with any existing product or tracked repo, note that the idea appears to be new.

## Step 3: Present Routing Options

<!-- FR-005: Present findings with exactly 4 routing options -->
Present the overlap analysis findings to the user, then offer exactly these routing options:

### If no overlap found:

> **No overlap detected** with your existing products or tracked repos.
>
> **Recommended**: Start a new product pipeline.
>
> Choose a route:
> 1. **New product** — Start the full pipeline: research → naming → PRD
> 2. **Similar but distinct** — I think it's related to something existing but want to proceed as new anyway

### If overlap with a product in products/:

> **Overlap detected** with **<product-name>** (`products/<slug>/`):
> <explain why it overlaps>
>
> Choose a route:
> 1. **New product** — Start fresh despite the overlap
> 2. **Add to existing product** — Add this as a feature to **<product-name>**
> 3. **Similar but distinct** — Acknowledge the overlap but create a separate product

### If overlap with a tracked repo in clay.config:

> **Overlap detected** with tracked repo **<slug>**:
> - URL: <repo-url>
> - Local path: <local-path>
> <explain why it overlaps>
>
> Choose a route:
> 1. **New product** — Start fresh despite the overlap
> 2. **Work in existing repo** — Open that repo and work there
> 3. **Similar but distinct** — Acknowledge the overlap but create a separate product

### If multiple overlaps (products and/or repos):

Present ALL matches with individual reasoning, then offer all applicable routes:

> 1. **New product** — Start fresh despite the overlaps
> 2. **Add to existing product** — Add to **<product-name>** (if product overlap)
> 3. **Work in existing repo** — Open **<repo-slug>** (if repo overlap)
> 4. **Similar but distinct** — Acknowledge overlaps but create a separate product

**Always ask the user to confirm their choice before proceeding. NEVER auto-execute a route.**

## Step 4: Route to Downstream Skill

<!-- FR-006: Chain to appropriate skill after user confirmation -->
<!-- NEVER auto-execute without user confirmation -->

Based on the user's confirmed choice:

<!-- FR-007: "New product" route chains sequentially with confirmation at each step -->
### Route: "New product"

Run the full new-product pipeline in sequence. Ask for confirmation before each step:

1. **Run `/clay:idea-research`** with the user's idea description
   - After research completes, ask: "Research complete. Ready to move on to naming? (yes/no)"
2. **Run `/clay:project-naming`** if user confirms
   - After naming completes, ask: "Naming complete. Ready to create the PRD? (yes/no)"
3. **Run `/clay:new-product`** if user confirms

The user can stop at any point. Each step is optional after the first.

### Route: "Add to existing product"

Run `/clay:new-product` targeting the matched product:

> Adding a feature to **<product-name>** (`products/<slug>/`).

Run `/clay:new-product` in Mode C (feature addition) for the matched product slug. This creates a feature PRD under `products/<slug>/features/`.

### Route: "Work in existing repo"

Suggest the user open the existing repo:

> The repo **<slug>** looks like a good fit.
>
> To work there:
> ```bash
> cd <local-path>
> ```
>
> Once in the repo, you can:
> - Run `/kiln:build-prd` to start a full build from a PRD
> - Run `/clay:idea` there to explore sub-ideas within that project
>
> Repo URL: <repo-url>

Do NOT automatically `cd` or run commands in the other repo. Just suggest.

### Route: "Similar but distinct"

Proceed as "New product" — the user has acknowledged the overlap and wants a separate product anyway. Follow the same pipeline: `/clay:idea-research` → `/clay:project-naming` → `/clay:new-product`.
