---
name: clay-create-repo
description: Create a new GitHub repository and scaffold it with clay. Seeds PRD artifacts from products/<slug>/ if available. Use after /clay:clay-new-product to turn a PRD into a live project, or standalone to scaffold a new repo.
---

# Create Repo — Scaffold a New Project with Clay

Create a new GitHub repository, scaffold it with the clay plugin infrastructure, and optionally seed it with PRD artifacts from the product collection.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Step 1: Gather Information

<!-- FR-010: Detect sub-idea status by reading parent: frontmatter from PRD.md or idea.md. -->
<!-- FR-011: When sub-idea + parent has ≥2 sub-ideas, offer shared-repo as default. -->
<!-- Contracts §3, §4, §5: is_parent_product / list_sub_ideas / read_frontmatter_field inlined. -->

### Step 1a: Detect Sub-idea Status

After resolving the product slug (from `$ARGUMENTS` or detection), read `parent:` frontmatter from `products/$SLUG/PRD.md` (or `idea.md` if PRD is absent). If `parent:` is non-empty, this slug is a sub-idea.

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

# list_sub_ideas — immediate sub-folders with idea.md or PRD.md
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

# The argument may be either a flat slug ("my-product") or a nested path ("parent/child").
# Normalize: if the argument contains a slash, treat the last segment as SUB_SLUG and the
# first as the effective parent (but still honor what's in frontmatter authoritatively).
IS_SUB_IDEA=false
PARENT_SLUG=""
SUB_SLUG=""
PARENT_HAS_SIBLINGS=false

PRODUCT_ROOT="products/$SLUG"
# Locate a file with frontmatter (PRD.md preferred, else idea.md)
FRONTMATTER_FILE=""
if [ -f "$PRODUCT_ROOT/PRD.md" ]; then
  FRONTMATTER_FILE="$PRODUCT_ROOT/PRD.md"
elif [ -f "$PRODUCT_ROOT/idea.md" ]; then
  FRONTMATTER_FILE="$PRODUCT_ROOT/idea.md"
fi

if [ -n "$FRONTMATTER_FILE" ]; then
  PARENT_FROM_FM=$(read_frontmatter_field "$FRONTMATTER_FILE" parent)
  if [ -n "$PARENT_FROM_FM" ]; then
    IS_SUB_IDEA=true
    PARENT_SLUG="$PARENT_FROM_FM"
    # Derive sub-slug from the path: products/<parent>/<sub>/...
    SUB_SLUG=$(basename "$PRODUCT_ROOT")
    # Count siblings under the parent
    SIBLING_COUNT=$(list_sub_ideas "$PARENT_SLUG" | wc -l | tr -d '[:space:]')
    if [ "${SIBLING_COUNT:-0}" -ge 2 ]; then
      PARENT_HAS_SIBLINGS=true
    fi
  fi
fi
```

### Step 1b: Shared-repo Prompt (when sub-idea + parent has siblings)

If `$IS_SUB_IDEA=true` AND `$PARENT_HAS_SIBLINGS=true`, present a 2-option prompt with shared-repo as the default:

> **`$SUB_SLUG`** is a sub-idea under **`$PARENT_SLUG`**, which has ≥2 sub-ideas. Would you like to use a shared repo?
>
> 1. **Shared repo** *(default)* — One repo named `$PARENT_SLUG` that contains every sub-idea as a feature PRD under `docs/features/`.
> 2. **Separate repo** — A repo just for `$SUB_SLUG`.

Default choice if the user presses enter without typing: option 1 (shared repo).

**Incompatible tech stack warning**: before finalizing shared-repo, spot-check the tech stacks declared in `products/$PARENT_SLUG/*/PRD.md`. If the stacks differ meaningfully (e.g., one is TypeScript/Next.js and another is Python/FastAPI with no shared runtime), warn the user inline:

> Sub-ideas under `$PARENT_SLUG` appear to use different tech stacks. Shared-repo may not be a clean fit — you may want option 2 (separate repo) instead.

Do not force the choice; let the user decide.

Set `SHARED_REPO_CHOSEN=true` if option 1 selected, else `false`. If `$IS_SUB_IDEA=false` or `$PARENT_HAS_SIBLINGS=false`, skip this prompt entirely (no behavior change for flat products or sub-ideas with no siblings).

### Step 1c: Resolve Shared-repo URL (reuse if parent already has one)

When `$SHARED_REPO_CHOSEN=true`:

```bash
SHARED_REPO_URL=""
if [ -f "products/$PARENT_SLUG/.repo-url" ]; then
  SHARED_REPO_URL=$(cat "products/$PARENT_SLUG/.repo-url")
  echo "Reusing existing shared repo: $SHARED_REPO_URL"
fi
```

If `$SHARED_REPO_URL` is set, Step 3 reuses it instead of creating a new repo. If empty, Step 3 creates a new GitHub repo named `$PARENT_SLUG` (not `$SUB_SLUG`) and records the URL at `products/$PARENT_SLUG/.repo-url` after Step 7.

---

If the user provided a `<product-slug>` as an argument, check if `products/<product-slug>/PRD.md` exists. If it does, use it as the PRD seed source and infer defaults from the PRD content.

If not provided in user input, ask these questions **one at a time**:

1. **Repo name**: What should the repository be called? (e.g., `my-saas-app`, `billing-service`)
   - If a product slug was given, default to the slug name
2. **GitHub org or user**: Where should it live? (default: current authenticated user via `gh api user --jq .login`)
3. **Visibility**: Public or private? (default: private)
4. **Description**: One-line repo description
   - If seeding from a PRD, extract the product pitch as the default
5. **PRD seeding**: Should we copy PRD artifacts into the new repo?
   - If `products/<slug>/PRD.md` exists (from argument or detection): offer to seed from it (default: yes)
   - If `products/` contains multiple products: list them and ask which to seed from
   - If no PRDs exist: skip — user can run `/clay:clay-new-product` in the new repo later
6. **Local path**: Where to clone locally? (default: sibling directory `../<repo-name>`)

## Step 2: Validate Prerequisites

Before proceeding, confirm:
- `git` is available
- `gh` is available and authenticated (`gh auth status`)

If GitHub auth is missing, stop and tell the user: "GitHub CLI is not authenticated. Run `gh auth login` to fix this."

## Step 3: Create the GitHub Repository

<!-- FR-011: Shared-repo path — if parent already has .repo-url, reuse that repo (clone, don't create). -->

### Shared-repo branch (SHARED_REPO_CHOSEN=true)

If `$SHARED_REPO_URL` was set in Step 1c (i.e., a previous sub-idea already created the shared repo), CLONE it instead of creating:

```bash
git clone "$SHARED_REPO_URL" <local-path>
cd <local-path>
```

Otherwise (first sub-idea to use the shared repo), create the repo named after the **parent**:

```bash
gh repo create <owner>/$PARENT_SLUG --<visibility> --description "Shared repo for $PARENT_SLUG and its sub-ideas" --clone
cd <local-path>
```

### Flat / separate-repo branch (default)

```bash
gh repo create <owner>/<repo-name> --<visibility> --description "<description>" --clone
cd <local-path>
```

If the repo already exists, stop and ask the user how to proceed. Do NOT overwrite.

## Step 4: Scaffold the Project

Initialize the project structure:

```bash
# Create standard directories
mkdir -p docs/features specs src tests

# Create placeholder files
touch src/.gitkeep tests/.gitkeep

# Create .gitignore
cat > .gitignore << 'GITIGNORE'
node_modules/
.env
.env.*
!.env.example
.DS_Store
*.log
dist/
build/
coverage/
.wheel/
.version.lock/
GITIGNORE
```

Create a `CLAUDE.md` with the project's workflow instructions. This should reference clay as the plugin and include the mandatory workflow steps (specify, plan, tasks, implement, audit).

Create `docs/session-prompt.md` with onboarding instructions.

## Step 5: Seed PRD Artifacts (if requested)

<!-- FR-011: When shared-repo path active, write sub-idea as feature PRD (NOT docs/PRD.md). -->
<!-- Contracts §6: docs/features/<YYYY-MM-DD>-<sub-slug>/PRD.md convention. -->

### Branch: shared-repo path (SHARED_REPO_CHOSEN=true)

When `$SHARED_REPO_CHOSEN=true`, do NOT copy the sub-idea's PRD to `docs/PRD.md`. Instead, scaffold it at the kiln feature-PRD path:

```bash
TODAY=$(date +%Y-%m-%d)
FEATURE_DIR="<local-path>/docs/features/${TODAY}-${SUB_SLUG}"
mkdir -p "$FEATURE_DIR"
cp "products/${PARENT_SLUG}/${SUB_SLUG}/PRD.md" "$FEATURE_DIR/PRD.md"
# Copy sibling feature PRDs if present under the sub-idea
if [ -d "products/${PARENT_SLUG}/${SUB_SLUG}/features" ]; then
  cp -r "products/${PARENT_SLUG}/${SUB_SLUG}/features/." "<local-path>/docs/features/"
fi
```

The shared repo's top-level `docs/PRD.md` MUST NOT be the sub-idea's PRD. Leave it as a placeholder (or, if the parent `about.md` exists, seed it from there as a parent overview — not the sub-idea).

### Branch: flat product or separate-repo path (default / SHARED_REPO_CHOSEN=false)

If the user chose to seed PRD artifacts from `products/<slug>/` (flat product OR sub-idea with separate repo):

#### Copy the PRD set
```bash
# Copy from the source repo's products/ directory
cp products/<slug>/PRD.md <local-path>/docs/PRD.md
cp products/<slug>/PRD-MVP.md <local-path>/docs/PRD-MVP.md 2>/dev/null || true
cp products/<slug>/PRD-Phases.md <local-path>/docs/PRD-Phases.md 2>/dev/null || true
```

#### Copy feature PRDs (if any)
```bash
if [ -d "products/<slug>/features" ]; then
  cp -r products/<slug>/features/ <local-path>/docs/features/
fi
```

If no PRD seed was selected, leave `docs/PRD.md` as a placeholder template.

## Step 6: Install Plugins

Ensure the user has the required plugins installed. These are user-scoped — they work across all projects once installed.

```bash
# Install kiln (spec-first workflow engine)
claude plugin install kiln 2>/dev/null || true

# Install wheel (workflow execution engine)
claude plugin install wheel 2>/dev/null || true

# Install shelf (Obsidian integration)
claude plugin install shelf 2>/dev/null || true

# Install clay (idea-to-project pipeline)
claude plugin install clay 2>/dev/null || true
```

If the user already has any of these plugins installed, skip those. Report which were newly installed vs already present.

## Step 7: Initial Commit and Push

```bash
cd <local-path>
git add -A
git commit -m "Initial scaffold via clay

Includes: project structure, CLAUDE.md workflow, and templates.
$(if [ -f docs/PRD.md ] && ! grep -q 'placeholder' docs/PRD.md 2>/dev/null; then echo "PRD seeded from products/<slug>/."; fi)

Source: clay plugin"
git push -u origin main
```

## Step 7.5: Update Clay Config Registry

<!-- FR-009, FR-013: Append repo entry to clay.config after successful creation -->
<!-- FR-011: For shared-repo path, register under the PARENT slug (not sub-slug) and reuse existing entry if present. -->

After the initial commit and push succeeds (Step 7), record this repo in `clay.config` so `/clay:clay-idea` and `/clay:clay-list` can track it.

### Shared-repo branch (SHARED_REPO_CHOSEN=true)

Register the repo under the **parent** slug, not the sub-slug. If a row for `$PARENT_SLUG` already exists (the shared repo was created by a previous sub-idea), do NOT append a duplicate — the existing entry remains authoritative.

```bash
if [ -n "$PARENT_SLUG" ] && ! grep -q "^$PARENT_SLUG " clay.config 2>/dev/null; then
  echo "$PARENT_SLUG <repo-url> <local-path> $(date +%Y-%m-%d)" >> clay.config
  git add clay.config
  git commit -m "Track $PARENT_SLUG in clay.config (shared repo)"
fi
```

### Flat / separate-repo branch (default)

```bash
# Append to clay.config (create if it doesn't exist)
# Format: <product-slug> <repo-url> <local-path> <created-date>
echo "<slug> https://github.com/<owner>/<repo-name> <local-path> $(date +%Y-%m-%d)" >> clay.config
git add clay.config
git commit -m "Track <slug> in clay.config"
```

Rules:

- Use `>>` (append) — **never** `>` (overwrite)
- If `clay.config` does not exist yet, `>>` will create it
- Only write this entry if Step 7 completed successfully (repo was actually created and pushed)
- For flat/separate-repo: `<slug>` is the product slug from Step 1
- For shared-repo: `<slug>` is the **parent** slug (sub-ideas do not get their own clay.config rows — they get `.repo-url` pointers in Step 8 instead)
- `<local-path>` is the path from Step 1 (e.g., `../<repo-name>`)

## Step 8: Write Status Marker

<!-- FR-011: Shared-repo path writes .repo-url under parent AND under each sub-idea so /clay:clay-list shows repo-created for all. -->

### Shared-repo branch (SHARED_REPO_CHOSEN=true)

Write the shared repo URL at TWO locations so `/clay:clay-list` can render status correctly for both the parent and the sub-idea:

```bash
# Parent-level marker (only created on the first sub-idea to use the shared repo)
if [ ! -f "products/$PARENT_SLUG/.repo-url" ]; then
  echo "https://github.com/<owner>/$PARENT_SLUG" > "products/$PARENT_SLUG/.repo-url"
fi

# Sub-idea-level marker — points at the same shared repo URL
echo "https://github.com/<owner>/$PARENT_SLUG" > "products/$PARENT_SLUG/$SUB_SLUG/.repo-url"

git add "products/$PARENT_SLUG/.repo-url" "products/$PARENT_SLUG/$SUB_SLUG/.repo-url"
git commit -m "Track shared repo URL for $PARENT_SLUG/$SUB_SLUG"
```

This makes `/clay:clay-list` report `repo-created` for the sub-idea as well as the parent.

### Flat / separate-repo branch (default)

Write the repo URL back to the source product directory so `/clay:clay-list` and `clay:sync` can track the status as "repo-created":

```bash
echo "https://github.com/<owner>/<repo-name>" > products/<slug>/.repo-url
git add products/<slug>/.repo-url
git commit -m "Track repo URL for <slug>"
```

This marker file is read by `clay_derive_status()` to set the product status to "repo-created".

## Step 9: Report

```
## New Repo: <owner>/<repo-name>

| Item | Status |
|------|--------|
| GitHub repo | Created (<visibility>) |
| Project scaffold | Done |
| Plugins installed | kiln, wheel, shelf, clay (Yes / Already installed) |
| PRD seeded | Yes (from products/<slug>/) / No |
| Initial commit | Pushed |

**Local path**: <local-path>
**GitHub**: https://github.com/<owner>/<repo-name>

**Next steps**:
1. `cd <local-path>`
2. Edit `docs/PRD.md` with your product requirements (or run `/clay:clay-new-product`)
3. Run `/kiln:kiln-build-prd` to start building
```

## Submodule / Monorepo Mode

If the user says "create a submodule", "add a module", or the target path is inside an existing repo:

1. Do NOT create a new GitHub repo
2. Instead, scaffold into a subdirectory of the current repo
3. The subdirectory gets its own project structure

Ask: "Should this module be a git submodule (independent repo linked here) or a subdirectory (part of this repo)?"

### Git submodule path
```bash
# Create the repo first (Steps 3-7 above), then:
cd <parent-repo>
git submodule add https://github.com/<owner>/<repo-name> <path>
git commit -m "Add <repo-name> as submodule at <path>"
```

### Subdirectory path
```bash
mkdir -p <path>
# Run scaffold steps (Step 4) targeting <path>
# Commit as part of parent repo
```

## Do Not Overwrite

If the target local path already contains a git repo or project files, stop and ask the user how to proceed. Do NOT overwrite existing work.
