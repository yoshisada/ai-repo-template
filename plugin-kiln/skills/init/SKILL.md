---
name: "init"
description: "Initialize an existing repo with kiln. Installs the plugin, scaffolds project structure, and configures hooks — without creating a new GitHub repo. For repos that already exist."
---

# Init — Add Kiln to an Existing Repo

Install kiln into an existing project. Unlike `/clay:create-repo` (which creates a brand new GitHub repo), this is for projects that already exist and want to adopt spec-first development.

```text
$ARGUMENTS
```

## When to Use

- You cloned a repo and want to add kiln to it
- You have an existing project and want to adopt spec-first development
- Someone shared a repo with you that should have kiln but doesn't
- You're setting up a local project that was created outside the kiln workflow

## Step 1: Check Current State

Survey what already exists:

```bash
# Check if kiln is already installed
ls CLAUDE.md .specify/memory/constitution.md specs/ 2>/dev/null

# Check for existing code
ls src/ tests/ 2>/dev/null
find . -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" | head -20

# Check for existing package.json
cat package.json 2>/dev/null | head -5

# Check git status
git status --short 2>/dev/null
git log --oneline -5 2>/dev/null
```

Report what you find:
- Is this a fresh repo or does it have existing code?
- Is there already a package.json?
- Is there any kiln infrastructure already?
- Is there a git history?

## Step 2: Install the Plugin

```bash
# Install the kiln-harness plugin (if not already installed)
claude plugin add @yoshisada/kiln-harness 2>/dev/null || echo "Plugin may already be installed"
```

If the plugin is already installed, skip to Step 3.

## Step 3: Run the Scaffold

```bash
# Run init.mjs to scaffold project structure
# This is idempotent — won't overwrite existing files
npx @yoshisada/kiln-harness init
```

This creates (if missing):
- `CLAUDE.md` — workflow rules and hook enforcement
- `.specify/memory/constitution.md` — governing principles
- `.specify/templates/` — spec, plan, tasks templates
- `docs/PRD.md` — product requirements placeholder
- `docs/session-prompt.md` — onboarding prompt
- `specs/` — feature specifications directory
- `src/` and `tests/` — code directories with `.gitkeep`
- `.gitignore` — standard ignores

## Step 4: Handle Existing Code

If the repo already has code in `src/` (or equivalent):

### Option A: Code has no specs (most common)

The existing code was written without kiln. The hooks will block future edits to `src/` until specs exist. You need to retroactively create specs:

1. Ask the user: "This repo has existing code but no specs. Would you like me to:"
   - **Generate specs from existing code** — I'll read the code and create spec.md, plan.md, and tasks.md (all marked `[X]`) to describe what's already built. This satisfies the hooks.
   - **Start fresh** — Treat the existing code as a starting point and only require specs for NEW changes. (Note: hooks will still block edits to existing files until specs exist.)
   - **Skip spec enforcement** — Remove the require-spec hook. Not recommended but your choice.

2. If generating specs: Read the existing code, create `specs/<feature>/spec.md` with FRs describing what exists, create `plan.md` with the current architecture, create `tasks.md` with all tasks marked `[X]`, and create `contracts/interfaces.md` with current function signatures.

### Option B: Code already has specs

The repo already went through kiln. Verify the specs are current:
```bash
ls specs/*/spec.md specs/*/plan.md specs/*/tasks.md 2>/dev/null
grep -c '\[X\]\|\[x\]' specs/*/tasks.md 2>/dev/null
```

## Step 5: Configure for the Project

### Detect Project Type

```bash
# Check framework
cat package.json 2>/dev/null | grep -E "next|vite|react|vue|angular|express|fastify"
# Check language
ls tsconfig.json 2>/dev/null && echo "TypeScript"
ls pyproject.toml setup.py 2>/dev/null && echo "Python"
```

### Update Constitution

Read `.specify/memory/constitution.md` and update it with project-specific constraints:
- Tech stack (from package.json / pyproject.toml)
- Testing framework (vitest, jest, pytest, etc.)
- Any existing conventions (from existing code patterns)

Ask the user if they have specific principles to add.

### Update PRD

If `docs/PRD.md` is still the template placeholder, ask:
- "Do you have a product requirements document? If so, paste it or point me to it."
- "If not, would you like me to generate one from the existing codebase?"

## Step 6: Initialize Version Tracking

```bash
# Create VERSION file if it doesn't exist
if [ ! -f VERSION ]; then
  echo "000.000.000.000" > VERSION
  echo "Version tracking initialized at 000.000.000.000"
fi
```

## Step 7: Initial Commit

If there are changes to commit:

```bash
git add CLAUDE.md .specify/ docs/ specs/ VERSION .gitignore
git commit -m "chore: initialize kiln harness

Adds spec-first development infrastructure:
- CLAUDE.md with workflow rules and hook enforcement
- Constitution with governing principles
- PRD template
- Spec templates and directory structure
- Version tracking (000.000.000.000)"
```

## Step 8: Report

```
## Kiln Initialized

**Project**: [repo name]
**Existing code**: [yes/no — X files in src/]
**Specs created**: [yes/no — retroactive or fresh]
**Version**: 000.000.000.000

### What's set up:
- [x] CLAUDE.md (workflow rules)
- [x] Constitution (.specify/memory/constitution.md)
- [x] PRD (docs/PRD.md)
- [x] Spec templates (.specify/templates/)
- [x] Directory structure (specs/, docs/)
- [x] Version tracking (VERSION)
- [x] Git hooks (require-spec, block-env-commit, version-increment)

### Next steps:
1. Edit `docs/PRD.md` with your product requirements
2. Edit `.specify/memory/constitution.md` with project-specific principles
3. Run `/build-prd` to start building, or `/resume` to see current state
```

## Rules

- NEVER overwrite existing files without asking — the scaffold is idempotent but user files are sacred
- If the repo has existing code, ALWAYS ask how to handle specs (don't silently generate them)
- Detect the tech stack and update the constitution accordingly
- The plugin install is user-scoped — it works across all projects, not just this one
- If git isn't initialized, run `git init` first
