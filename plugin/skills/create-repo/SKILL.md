---
name: create-repo
description: Create a new GitHub repository and scaffold it with the speckit-harness plugin. Clones the template, runs the init script, and installs the Claude Code plugin. Use after /create-prd to turn a PRD into a live project, or standalone to scaffold a new module/subproject.
---

# Create Repo — Scaffold a New Project with speckit-harness

Create a new GitHub repository and scaffold it with the full spec-first development infrastructure from the speckit-harness plugin.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Step 1: Gather Information

If not provided in user input, ask these questions in **one message**:

1. **Repo name**: What should the repository be called? (e.g., `my-saas-app`, `billing-service`)
2. **GitHub org or user**: Where should it live? (default: current authenticated user via `gh api user --jq .login`)
3. **Visibility**: Public or private? (default: private)
4. **Description**: One-line repo description
5. **PRD seeding**: Should we copy PRD artifacts into the new repo?
   - If `docs/PRD.md` has real content (not the placeholder template): offer to copy it
   - If `docs/features/*/PRD.md` exists: offer to copy a specific feature PRD
   - If `products/*/PRD.md` exists (PRD-only repo): offer to copy a specific product PRD
   - If no PRDs exist: skip this — user can run `/create-prd` in the new repo later
6. **Local path**: Where to clone locally? (default: sibling directory `../<repo-name>`)

## Step 2: Create the GitHub Repository

```bash
gh repo create <owner>/<repo-name> --<visibility> --description "<description>" --clone
cd <repo-name>
```

If the repo already exists, stop and ask the user how to proceed. Do NOT overwrite.

## Step 3: Scaffold the Project

Clone the template infrastructure and run the init script:

```bash
# Clone the plugin source to a temp location
git clone --depth 1 https://github.com/yoshisada/ai-repo-template.git /tmp/speckit-harness-src

# Run the init script from the cloned plugin
node /tmp/speckit-harness-src/plugin/bin/init.mjs init

# Clean up
rm -rf /tmp/speckit-harness-src
```

This creates:
- `CLAUDE.md` with the mandatory workflow
- `.specify/templates/` with all spec/plan/task templates
- `.specify/memory/constitution.md` with governing principles
- `.specify/scripts/` with helper scripts
- `docs/PRD.md` (placeholder), `docs/session-prompt.md`
- `specs/README.md`, `src/.gitkeep`, `tests/.gitkeep`
- `.gitignore`

## Step 4: Install the Claude Code Plugin

Ensure the user has the speckit-harness plugin installed so skills, agents, and hooks are available:

```bash
# Check if marketplace is already added (non-destructive)
claude plugin marketplace add yoshisada/ai-repo-template 2>/dev/null || true

# Install the plugin if not already installed
claude plugin install speckit-harness@speckit-harness 2>/dev/null || true
```

If the user already has the plugin installed (e.g., from a previous project), skip this step. The plugin is user-scoped — it works across all projects once installed.

## Step 5: Seed PRD Artifacts (if requested)

If the user chose to seed PRD artifacts in Step 1:

### Seeding a product PRD
Copy from the source repo to the new repo:
- `docs/PRD.md` (overwriting the placeholder)
- `docs/PRD-MVP.md` (if exists)
- `docs/PRD-Phases.md` (if exists)

### Seeding a feature PRD
Copy from the source repo:
- `docs/features/<selected-feature>/PRD.md` → `docs/PRD.md` (promote to product PRD)

OR keep as a feature PRD:
- `docs/features/<selected-feature>/` → `docs/features/<selected-feature>/`

Ask the user which approach they prefer.

## Step 6: Initial Commit and Push

```bash
git add -A
git commit -m "Initial scaffold via speckit-harness

Includes: speckit workflow, templates, constitution, and project structure.
Plugin provides skills, agents, and hooks.

Source: yoshisada/ai-repo-template"
git push -u origin main
```

## Step 7: Report

```
## New Repo: <owner>/<repo-name>

| Item | Status |
|------|--------|
| GitHub repo | Created (<visibility>) |
| Project scaffold | Created |
| Plugin installed | Yes/Already installed |
| PRD seeded | Yes/No |
| Initial commit | Pushed |

**Local path**: <path>
**GitHub**: https://github.com/<owner>/<repo-name>

**Next steps**:
1. `cd <path>`
2. Edit `docs/PRD.md` with your product requirements (or run `/create-prd`)
3. Run `/build-prd` to start building
```

## Submodule / Monorepo Mode

If the user says "create a submodule", "add a module", or the target path is inside an existing repo:

1. Do NOT create a new GitHub repo
2. Instead, scaffold into a subdirectory of the current repo
3. Run the init script targeting that subdirectory
4. The subdirectory gets its own `CLAUDE.md` and speckit config

Ask the user: "Should this module be a git submodule (independent repo linked here) or a subdirectory (part of this repo)?"

### Git submodule path
```bash
# Create the repo first (Steps 2-6 above), then:
cd <parent-repo>
git submodule add https://github.com/<owner>/<repo-name> <path>
git commit -m "Add <repo-name> as submodule at <path>"
```

### Subdirectory path
```bash
mkdir -p <path>
cd <path>
git clone --depth 1 https://github.com/yoshisada/ai-repo-template.git /tmp/speckit-harness-src
node /tmp/speckit-harness-src/plugin/bin/init.mjs init
rm -rf /tmp/speckit-harness-src
# Commit as part of parent repo
```

## Updating Existing Projects

To update templates and scripts to the latest version:

```bash
git clone --depth 1 https://github.com/yoshisada/ai-repo-template.git /tmp/speckit-harness-src
node /tmp/speckit-harness-src/plugin/bin/init.mjs update
rm -rf /tmp/speckit-harness-src
```

To update the plugin (skills, agents, hooks):
```bash
/plugin marketplace update speckit-harness
/plugin update speckit-harness@speckit-harness
```
