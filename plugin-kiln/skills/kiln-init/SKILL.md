---
name: "kiln-init"
description: "Initialize an existing repo with kiln. Installs the plugin, scaffolds project structure, and configures hooks — without creating a new GitHub repo. For repos that already exist."
---

# Init — Add Kiln to an Existing Repo

Install kiln into an existing project. Unlike `/clay:clay-create-repo` (which creates a brand new GitHub repo), this is for projects that already exist and want to adopt spec-first development.

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

Prefer the bundled `bin/init.mjs` from this plugin install (so a locally-loaded or
`--plugin-dir` plugin scaffolds with ITS code, not a stale published package). Fall
back to the published package only when the bundled script isn't resolvable.

```bash
# Run init.mjs to scaffold project structure. Idempotent — won't overwrite existing files.
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -f "${CLAUDE_PLUGIN_ROOT}/bin/init.mjs" ]]; then
  node "${CLAUDE_PLUGIN_ROOT}/bin/init.mjs" init
else
  npx @yoshisada/kiln init
fi
```

This creates (if missing):
- `CLAUDE.md` — workflow rules and hook enforcement
- `.specify/memory/constitution.md` — governing principles
- `.specify/templates/` — spec, plan, tasks templates
- `.kiln/config.json` — review mode, checkpoints, branching, model tiers (Phase 0)
- `.kiln/standards.md` — coding standards injected into plan/implement prompts
- `.kiln/test-strategy.json` — coverage gate + smoke config
- `docs/PRD.md` — product requirements placeholder
- `docs/session-prompt.md` — onboarding prompt
- `specs/` — feature specifications directory
- `.gitignore` — standard ignores

## Step 3b: Vision Interview

Vision is best captured at setup, when the idea is freshest. It's the filter
`kiln-distill` uses to decline off-vision captures, so it pays for itself fast.

```bash
# Skip if vision already exists (e.g. clay-create-repo already wrote it).
test -f .kiln/vision.md && echo "vision-exists" || echo "vision-missing"
```

- If `.kiln/vision.md` **exists** → skip with: "Vision already defined — edit with
  `/kiln:kiln-roadmap --vision`."
- If **missing** → run a short interview, asking the four prompts in **two pairs** (never
  dump all four at once), each with a strong default the user can accept or tweak:
  1. **What are we building?** (one paragraph — product, user, the unfair shortcut)
  2. **What is it NOT?** (the deliberate boundary)
  — then —
  3. **How will we know we're winning?** (the 6-month signals)
  4. **Guiding constraints?** (≤5 bullets)

  Write the answers into `.kiln/vision.md` using `templates/vision-template.md` as the
  shape (resolve via `${CLAUDE_PLUGIN_ROOT}/templates/vision-template.md`), stamping
  `last_updated` with today's date.

This step is **skippable** — if the user presses enter / declines, print "Vision
deferred — define it any time with `/kiln:kiln-roadmap --vision`." and continue. Do not
block init on it.

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

### Step 5b: Design-First Mode

Ask **one** question with a default:

> "Is this a design-first project — do you drive UI from Penpot designs, with code
> following the design? (default: no)"

If **yes**, set `design_first: true` in `.kiln/config.json`. When enabled, `kiln-distill`
pulls the latest Penpot artifacts (via `trim-pull`) before drafting PRDs, and
`smoke-review` can verify rendered code against the design mockup. Leave `false` for
code-first projects.

```bash
# Apply the answer (DESIGN_FIRST is "true" or "false")
jq --argjson v "$DESIGN_FIRST" '.design_first = $v' .kiln/config.json > .kiln/config.json.tmp \
  && mv .kiln/config.json.tmp .kiln/config.json
```

### Step 5c: Branching Style

Ask **one** question with a default, offering the three styles:

> "How should kiln branch and PR? (default: github-flow)"

| Style | Flow | When |
|---|---|---|
| `github-flow` | feature branch → PR → `main` | Solo / small team; main always deployable |
| `gitflow` | feature branch → PR → `integration_branch` (default `dev`) → PR → `main` | Keep `main` clean until milestone-ready |
| `trunk` | commit directly to `main` | Strong CI, fastest loop, no branches |

Write the choice into `.kiln/config.json` under `branching.style`. If `gitflow`, also set
`branching.integration_branch` (default `dev`) and create it if it doesn't exist:

```bash
jq --arg s "$BRANCHING_STYLE" '.branching.style = $s' .kiln/config.json > .kiln/config.json.tmp \
  && mv .kiln/config.json.tmp .kiln/config.json
if [ "$BRANCHING_STYLE" = "gitflow" ]; then
  INT_BRANCH=$(jq -r '.branching.integration_branch // "dev"' .kiln/config.json)
  git rev-parse --verify "$INT_BRANCH" >/dev/null 2>&1 || git branch "$INT_BRANCH"
fi
```

`require-feature-branch.sh` reads `branching.per_feature`; `create-pr` reads
`branching.style` to choose the PR base. No workflow JSON edits needed to switch styles.

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
git add CLAUDE.md .specify/ docs/ specs/ .kiln/ VERSION .gitignore
git commit -m "chore: initialize kiln harness

Adds spec-first development infrastructure:
- CLAUDE.md with workflow rules and hook enforcement
- Constitution with governing principles
- PRD template
- Spec templates and directory structure
- .kiln/config.json, standards.md, test-strategy.json (review + standards config)
- Vision (.kiln/vision.md) if defined
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
- [x] Config (.kiln/config.json — review_mode: [mode], branching: [style])
- [x] Standards (.kiln/standards.md)
- [x] Test strategy (.kiln/test-strategy.json)
- [x] Vision (.kiln/vision.md) [if defined — else "deferred"]
- [x] Directory structure (specs/, docs/)
- [x] Version tracking (VERSION)
- [x] Git hooks (require-spec, block-env-commit, version-increment)

### Next steps:
1. Edit `docs/PRD.md` with your product requirements
2. Review `.kiln/config.json` (review_mode, branching, model tiers) and `.kiln/standards.md`
3. Edit `.specify/memory/constitution.md` with project-specific principles
4. Run `/kiln:kiln-build-prd` to start building, or `/kiln:kiln-resume` to see current state
```

## Rules

- NEVER overwrite existing files without asking — the scaffold is idempotent but user files are sacred
- If the repo has existing code, ALWAYS ask how to handle specs (don't silently generate them)
- Detect the tech stack and update the constitution accordingly
- The plugin install is user-scoped — it works across all projects, not just this one
- If git isn't initialized, run `git init` first
