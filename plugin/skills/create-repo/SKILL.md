---
name: create-repo
description: Create a new GitHub repository and scaffold it with the speckit-harness plugin. Installs the full spec-first workflow (hooks, skills, agents, constitution, templates) via npm. Use after /create-prd to turn a PRD into a live project, or standalone to scaffold a new module/subproject.
---

# Create Repo — Scaffold a New Project with speckit-harness

Create a new GitHub repository and install the speckit-harness plugin to get the full spec-first development infrastructure.

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
   - If no PRDs exist: skip this — user can run `/create-prd` in the new repo later
6. **Local path**: Where to clone locally? (default: sibling directory `../<repo-name>`)

## Step 2: Create the GitHub Repository

```bash
gh repo create <owner>/<repo-name> --<visibility> --description "<description>" --clone
cd <repo-name>
```

If the repo already exists, stop and ask the user how to proceed. Do NOT overwrite.

## Step 3: Install the Plugin and Scaffold

```bash
# Initialize the project
npm init -y

# Install the speckit-harness plugin
npm install @yoshisada/speckit-harness

# Run the init script — scaffolds CLAUDE.md, hooks, templates, constitution, etc.
npx speckit-harness init
```

This single command handles everything:
- Creates `CLAUDE.md` with the mandatory workflow
- Creates `.claude/settings.json` with hook configuration
- Creates `.claude/hooks/` with enforcement scripts
- Creates `.specify/templates/` with all spec/plan/task templates
- Creates `.specify/memory/constitution.md` with governing principles
- Creates `docs/PRD.md` (placeholder), `docs/session-prompt.md`
- Creates `specs/README.md`, `src/.gitkeep`, `tests/.gitkeep`
- Creates `.gitignore`

## Step 4: Seed PRD Artifacts (if requested)

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

## Step 5: Initial Commit and Push

```bash
git add -A
git commit -m "Initial scaffold via speckit-harness

Includes: speckit workflow, 4-gate hooks, skills, agents, constitution,
templates, and setup infrastructure.

Scaffolded with: @yoshisada/speckit-harness"
git push -u origin main
```

## Step 6: Report

```
## New Repo: <owner>/<repo-name>

| Item | Status |
|------|--------|
| GitHub repo | Created (<visibility>) |
| speckit-harness | Installed |
| PRD seeded | Yes/No |
| Init checks | Passed/Failed |
| Initial commit | Pushed |

**Local path**: <path>
**GitHub**: https://github.com/<owner>/<repo-name>

**Next steps**:
1. `cd <path>`
2. Edit `docs/PRD.md` with your product requirements (or run `/create-prd`)
3. Run `/build-prd` to start building

**Updating**: Run `npm update @yoshisada/speckit-harness && npx speckit-harness update`
```

## Submodule / Monorepo Mode

If the user says "create a submodule", "add a module", or the target path is inside an existing repo:

1. Do NOT create a new GitHub repo
2. Instead, scaffold into a subdirectory of the current repo
3. Run `npx speckit-harness init` from within that subdirectory
4. The subdirectory gets its own `CLAUDE.md`, hooks, and speckit config

Ask the user: "Should this module be a git submodule (independent repo linked here) or a subdirectory (part of this repo)?"

### Git submodule path
```bash
# Create the repo first (Steps 2-5 above), then:
cd <parent-repo>
git submodule add https://github.com/<owner>/<repo-name> <path>
git commit -m "Add <repo-name> as submodule at <path>"
```

### Subdirectory path
```bash
mkdir -p <path>
cd <path>
npm init -y
npm install @yoshisada/speckit-harness
npx speckit-harness init
# Commit as part of parent repo
```

## Updating Existing Projects

To update an existing project to the latest speckit-harness:

```bash
npm update @yoshisada/speckit-harness
npx speckit-harness update
```

The `update` command re-syncs shared infrastructure (templates, hooks) without touching project-specific files (CLAUDE.md, constitution, PRD).
