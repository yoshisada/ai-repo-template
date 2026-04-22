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

If the user chose to seed PRD artifacts from `products/<slug>/`:

### Copy the PRD set
```bash
# Copy from the source repo's products/ directory
cp products/<slug>/PRD.md <local-path>/docs/PRD.md
cp products/<slug>/PRD-MVP.md <local-path>/docs/PRD-MVP.md 2>/dev/null || true
cp products/<slug>/PRD-Phases.md <local-path>/docs/PRD-Phases.md 2>/dev/null || true
```

### Copy feature PRDs (if any)
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
After the initial commit and push succeeds (Step 7), record this repo in `clay.config` so `/clay:clay-idea` and `/clay:clay-list` can track it.

```bash
# Append to clay.config (create if it doesn't exist)
# Format: <product-slug> <repo-url> <local-path> <created-date>
echo "<slug> https://github.com/<owner>/<repo-name> <local-path> $(date +%Y-%m-%d)" >> clay.config
```

- Use `>>` (append) — **never** `>` (overwrite)
- If `clay.config` does not exist yet, `>>` will create it
- Only write this entry if Step 7 completed successfully (repo was actually created and pushed)
- The `<slug>` is the product slug from Step 1 (or the repo name if no product slug)
- The `<local-path>` is the path from Step 1 (e.g., `../<repo-name>`)

After appending, commit the updated clay.config:

```bash
git add clay.config
git commit -m "Track <slug> in clay.config"
```

## Step 8: Write Status Marker

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
