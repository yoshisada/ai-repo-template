---
name: clay-idea
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

<!-- FR-001: Always prompt for market intent after overlap analysis, before routing. -->
<!-- NFR-003: One round-trip; no CLI flag, no env var, no remembered preference. -->
## Step 2.5: Classify Market Intent

Ask the user exactly this question (no flag bypass — always prompt):

> What's the market intent for this idea?
>
> 1. **internal** — Tool/automation for yourself; no market
> 2. **marketable** — Standalone product intended for an external market
> 3. **pmf-exploration** — Product-market fit is the primary unknown

Accept only one of the literal strings `internal`, `marketable`, or `pmf-exploration` (case-insensitive accepted but normalize to lowercase). Reject anything else and re-prompt. Store the chosen value as shell variable `INTENT` for use in later steps.

```bash
# Read the answer (normalize to lowercase, trim whitespace)
INTENT=$(printf '%s' "$USER_INTENT_ANSWER" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
case "$INTENT" in
  internal|marketable|pmf-exploration) ;;
  *) echo "Invalid intent. Please answer exactly: internal, marketable, or pmf-exploration."; # re-prompt
     ;;
esac
```

<!-- FR-002: Write intent to products/<slug>/idea.md frontmatter. -->
### Step 2.6: Record Intent to idea.md

Derive the product slug from the idea description (or reuse the slug determined during overlap analysis). If `products/<slug>/idea.md` does not yet exist, create it with this minimal frontmatter:

```yaml
---
title: <human-readable title>
slug: <slug>
date: <YYYY-MM-DD>
intent: <INTENT>
---
```

If `products/<slug>/idea.md` already exists, update the `intent:` field idempotently. Helper idiom (contracts §5):

```bash
# read_frontmatter_field — extract a YAML frontmatter key's value
read_frontmatter_field() {
  local file="$1"
  local key="$2"
  awk -v k="$key" '
    BEGIN { in_fm=0 }
    /^---[[:space:]]*$/ { in_fm = !in_fm; if (!in_fm) exit; next }
    in_fm && $1 == k":" { sub(/^[^:]+:[[:space:]]*/, ""); print; exit }
  ' "$file"
}

IDEA_FILE="products/$SLUG/idea.md"
mkdir -p "products/$SLUG"
if [ ! -f "$IDEA_FILE" ]; then
  cat > "$IDEA_FILE" <<EOF
---
title: $TITLE
slug: $SLUG
date: $(date +%Y-%m-%d)
intent: $INTENT
---
EOF
elif [ -z "$(read_frontmatter_field "$IDEA_FILE" intent)" ]; then
  # Insert intent after the opening '---' if missing
  awk -v v="$INTENT" '
    BEGIN { inserted=0 }
    /^---[[:space:]]*$/ && !inserted { print; print "intent: " v; inserted=1; next }
    { print }
  ' "$IDEA_FILE" > "$IDEA_FILE.tmp" && mv "$IDEA_FILE.tmp" "$IDEA_FILE"
else
  # Replace existing intent line
  awk -v v="$INTENT" '
    BEGIN { in_fm=0 }
    /^---[[:space:]]*$/ { in_fm = !in_fm }
    in_fm && /^intent:/ { print "intent: " v; next }
    { print }
  ' "$IDEA_FILE" > "$IDEA_FILE.tmp" && mv "$IDEA_FILE.tmp" "$IDEA_FILE"
fi
```

<!-- FR-006, FR-007: Parent collision detection (filesystem-only rule, Decision 1). -->
## Step 2.7: Parent Collision Check

After recording intent, check whether the derived `$SLUG` collides with an existing parent product. A parent product is defined purely by filesystem shape (contracts §3):

```bash
# is_parent_product — returns 0 (true) if slug is a parent product per FR-007
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
```

If `is_parent_product "$SLUG"` returns truthy, present these three options (do NOT silently overwrite):

> **`$SLUG`** is already a parent product (it has `about.md` plus sub-ideas). How should I proceed?
>
> 1. **Sub-idea under `$SLUG`** — Create this idea as a new child under the existing parent
> 2. **Sibling parent** — Create a different top-level slug (I'll ask you for one)
> 3. **Abort** — Cancel this run

Wait for the user's choice before any further write.

<!-- FR-008: On sub-idea selection, write sub-idea with parent: frontmatter. -->
### Step 2.8: Handle Sub-idea Selection

If the user chose option 1 (sub-idea):

1. Prompt for the sub-slug (kebab-case). Validate against `/^[a-z0-9][a-z0-9-]*$/`.
2. Create `products/<parent>/<sub-slug>/idea.md` with the full sub-idea frontmatter per contracts §2:

```bash
PARENT_SLUG="$SLUG"
SUB_SLUG="$USER_SUB_SLUG"
SUB_DIR="products/$PARENT_SLUG/$SUB_SLUG"
mkdir -p "$SUB_DIR"
cat > "$SUB_DIR/idea.md" <<EOF
---
title: $SUB_TITLE
slug: $SUB_SLUG
date: $(date +%Y-%m-%d)
status: idea
parent: $PARENT_SLUG
intent: $INTENT
---
EOF
# Re-point SLUG so downstream routing targets the sub-idea's path
SLUG="$PARENT_SLUG/$SUB_SLUG"
IDEA_FILE="$SUB_DIR/idea.md"
```

Then continue to Step 3 (routing) with `$SLUG` now targeting the sub-idea's nested path.

If the user chose option 2 (sibling parent): prompt for a different top-level slug, then treat it as a brand-new flat product (re-run the slug derivation with the new name and continue to Step 3 with the new `$SLUG`).

If the user chose option 3 (abort): stop. Do not write anything further.

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
<!-- FR-003, FR-005: Branch routing on $INTENT set in Step 2.5 -->

Based on the user's confirmed choice AND the `$INTENT` recorded in Step 2.5/2.6:

<!-- FR-003: intent=internal skips research and naming entirely. -->
### Route: "New product" when `$INTENT = internal`

Skip `/clay:clay-idea-research` and `/clay:clay-project-naming` entirely. Route directly to `/clay:clay-new-product` in simplified mode:

1. Tell the user:
   > Intent is **internal** — skipping market research and naming. Going straight to a simplified PRD.
2. **Run `/clay:clay-new-product`** with the idea description and `$SLUG`. The skill reads `intent: internal` from `products/$SLUG/idea.md` (FR-003) and generates a simplified PRD that drops Competitive Landscape / Market Research / Naming-Branding sections.

Do not produce `research.md` or `naming.md` for internal intent.

<!-- FR-005: intent=marketable keeps current full pipeline behavior. -->
### Route: "New product" when `$INTENT = marketable`

Run the full new-product pipeline in sequence. Ask for confirmation before each step:

1. **Run `/clay:clay-idea-research`** with the user's idea description
   - After research completes, ask: "Research complete. Ready to move on to naming? (yes/no)"
2. **Run `/clay:clay-project-naming`** if user confirms
   - After naming completes, ask: "Naming complete. Ready to create the PRD? (yes/no)"
3. **Run `/clay:clay-new-product`** if user confirms

The user can stop at any point. Each step is optional after the first.

<!-- FR-004: intent=pmf-exploration still runs full pipeline; clay-idea-research biases toward demand-validation via its own intent read. -->
### Route: "New product" when `$INTENT = pmf-exploration`

Same pipeline as `marketable` (research → naming → PRD). `/clay:clay-idea-research` reads `intent: pmf-exploration` from `products/$SLUG/idea.md` and biases its report toward demand validation (FR-004) — no change required here beyond invoking the standard pipeline.

### Route: "Add to existing product"

Run `/clay:clay-new-product` targeting the matched product:

> Adding a feature to **<product-name>** (`products/<slug>/`).

Run `/clay:clay-new-product` in Mode C (feature addition) for the matched product slug. This creates a feature PRD under `products/<slug>/features/`.

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
> - Run `/kiln:kiln-build-prd` to start a full build from a PRD
> - Run `/clay:clay-idea` there to explore sub-ideas within that project
>
> Repo URL: <repo-url>

Do NOT automatically `cd` or run commands in the other repo. Just suggest.

### Route: "Similar but distinct"

Proceed as "New product" — the user has acknowledged the overlap and wants a separate product anyway. Follow the same pipeline: `/clay:clay-idea-research` → `/clay:clay-project-naming` → `/clay:clay-new-product`.
