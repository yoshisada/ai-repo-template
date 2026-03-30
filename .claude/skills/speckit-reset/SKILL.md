---
name: speckit-reset
description: Check out the base branch this feature branch was started from, abandoning the current feature branch.
compatibility: Requires a git repository
metadata:
  author: github-spec-kit
  source: custom
---

# Speckit Reset — Return to Base Branch

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
   ## Speckit Reset: {current-branch}

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
   If they say yes: `git stash push -m "speckit-reset stash from {current-branch}"`

2. Check out the base branch:
   ```bash
   git checkout {base-branch}
   ```

## Step 3: Report

```
## Reset Complete

Checked out: `{base-branch}`
Previous branch: `{feature-branch}` (still exists, not deleted)

To return to your feature branch:
  git checkout {feature-branch}

To delete the feature branch (if you're done with it):
  git branch -d {feature-branch}
```
