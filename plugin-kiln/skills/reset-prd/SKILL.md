---
name: reset-prd
description: Check out the base branch this feature branch was started from, abandoning the current feature branch.
compatibility: Requires a git repository
metadata:
  author: github-spec-kit
  source: custom
---

# Kiln Reset — Return to Base Branch

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Overview

Check out the branch this feature branch was started from (its merge-base branch), effectively abandoning the current feature branch. The feature branch is not deleted — it stays in git history and can be returned to with `git checkout <branch-name>`.

## Step 1: Detect Current State

1. Get the current branch:
   ```bash
   git branch --show-current
   ```

2. Find the base branch by checking common candidates in order:
   ```bash
   # Try main first, then master, then any other branch
   for base in main master develop; do
     if git show-ref --verify --quiet refs/heads/$base; then
       MERGE_BASE=$(git merge-base $base HEAD)
       # Check if this branch diverged from $base (i.e., merge-base == tip of $base)
       BASE_TIP=$(git rev-parse $base)
       if [ "$MERGE_BASE" = "$BASE_TIP" ]; then
         BASE_BRANCH=$base
         break
       fi
     fi
   done
   # If no exact match, use whichever branch has the most recent common ancestor
   ```

3. Show the user what will happen:
   ```
   ## Kiln Reset: {current-branch}

   This will check out `{base-branch}` — the branch `{current-branch}` was started from.

   Your feature branch `{current-branch}` will NOT be deleted. You can return to it with:
     git checkout {current-branch}

   Current branch has {N} commits ahead of {base-branch}:
   {git log --oneline output}

   Proceed? (y/n)
   ```

   - If `$ARGUMENTS` contains `--yes` or `-y`, skip the confirmation prompt.
   - If `$ARGUMENTS` contains `--dry-run`, show the above but do not switch branches.

## Step 2: Check Out Base Branch

1. Ensure there are no uncommitted changes to tracked files that would revert:
   ```bash
   git status --porcelain
   ```
   Only warn about **modified tracked files** (lines starting with `M` or `D`). Untracked files (`??`) carry over across checkouts and do not need a warning.

   If there are modified tracked files, warn:
   ```
   ⚠️  You have uncommitted changes to tracked files. These will revert to {base-branch}'s version after checkout:
   {list of M/D files}
   Stash them first? (y/n)
   ```
   If they say yes: `git stash push -m "reset-prd stash from {current-branch}"`

2. Check out the base branch:
   ```bash
   git checkout {base-branch}
   ```

## Step 3: Sync Latest ai-repo-template

After checking out the base branch, update the project with the latest skills, templates, and configuration from the `ai-repo-template` repository.

1. Check if `ai-repo-template/` exists in the working directory:
   ```bash
   ls ai-repo-template/
   ```
   If it doesn't exist, skip this step and note it in the report.

2. Pull the latest from `ai-repo-template`:
   ```bash
   cd ai-repo-template && git pull && cd ..
   ```

3. Sync skills, templates, and config into the project:
   ```bash
   # Skills
   rsync -a --delete ai-repo-template/.claude/skills/ .claude/skills/

   # Specify templates and memory
   rsync -a --delete ai-repo-template/.specify/templates/ .specify/templates/
   rsync -a ai-repo-template/.specify/memory/constitution.md .specify/memory/constitution.md

   # Hooks and agents (if present)
   rsync -a ai-repo-template/.claude/settings.json .claude/settings.json 2>/dev/null || true
   rsync -a --delete ai-repo-template/.claude/agents/ .claude/agents/ 2>/dev/null || true
   ```

4. Check if anything changed:
   ```bash
   git status --porcelain
   ```
   If there are changes, commit them:
   ```bash
   git add .claude/ .specify/
   git commit -m "chore: sync latest ai-repo-template skills and templates"
   ```
   If nothing changed, report "Already up to date."

## Step 4: Report

```
## Reset Complete

Checked out: `{base-branch}`
Previous branch: `{feature-branch}` (still exists, not deleted)
Template sync: {up to date | N files updated — committed as {hash}}

To return to your feature branch:
  git checkout {feature-branch}

To delete the feature branch (if you're done with it):
  git branch -d {feature-branch}

To start a new pipeline:
  /build-prd
```
