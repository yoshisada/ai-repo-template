---
name: "resume"
description: "Pick up where you left off. Auto-detects in-progress work, summarizes current state, and tells you exactly what to do next. Run this at the start of every new session."
---

# Resume — Pick Up Where You Left Off

Auto-detect the current state of the project and tell you exactly where you are and what to do next. Run this at the start of every new Claude Code session instead of manually reading docs/session-prompt.md.

```text
$ARGUMENTS
```

## Step 1: Read Project Context

```bash
# Project identity
basename "$(pwd)"
git remote get-url origin 2>/dev/null

# Current branch
git branch --show-current

# Version
cat VERSION 2>/dev/null || echo "No VERSION file"
```

Read:
- `CLAUDE.md` — workflow rules (quick skim, not full read)
- `.specify/memory/constitution.md` — governing principles

## Step 2: Detect In-Progress Work

### Check for active feature branches

```bash
# Current branch — are we on a feature branch?
BRANCH=$(git branch --show-current)
echo "Current branch: $BRANCH"

# Recent branches (last 10)
git branch --sort=-committerdate | head -10

# Any build/* branches from pipeline runs?
git branch --list 'build/*'
```

### Check spec artifacts for active features

```bash
# Find all feature specs
ls specs/*/spec.md 2>/dev/null

# For each feature, check completion status
for dir in specs/*/; do
  FEATURE=$(basename "$dir")
  echo "=== $FEATURE ==="

  # Spec exists?
  [ -f "$dir/spec.md" ] && echo "  spec.md: YES" || echo "  spec.md: NO"

  # Plan exists?
  [ -f "$dir/plan.md" ] && echo "  plan.md: YES" || echo "  plan.md: NO"

  # Tasks exist? How many done?
  if [ -f "$dir/tasks.md" ]; then
    TOTAL=$(grep -c '^\s*- \[' "$dir/tasks.md" 2>/dev/null || echo 0)
    DONE=$(grep -c '^\s*- \[[xX]\]' "$dir/tasks.md" 2>/dev/null || echo 0)
    echo "  tasks.md: $DONE/$TOTAL done"
  else
    echo "  tasks.md: NO"
  fi

  # Contracts exist?
  [ -f "$dir/contracts/interfaces.md" ] && echo "  contracts: YES" || echo "  contracts: NO"

  # Blockers?
  [ -f "$dir/blockers.md" ] && echo "  blockers: YES — review needed" || echo "  blockers: none"
done
```

### Check for uncommitted work

```bash
# Staged and unstaged changes
git status --short

# Stashed work
git stash list
```

### Check recent activity

```bash
# Last 10 commits on current branch
git log --oneline -10

# What changed recently?
git log --oneline --since="24 hours ago" 2>/dev/null
```

### Check QA state

```bash
# Any QA results from a previous pass?
ls qa-results/latest/QA-REPORT.md 2>/dev/null && echo "QA report exists"
ls qa-results/latest/QA-PASS-REPORT.md 2>/dev/null && echo "QA pass report exists"
ls qa-results/latest/UX-REPORT.md 2>/dev/null && echo "UX report exists"
cat qa-results/checkpoints.md 2>/dev/null | tail -20
```

### Check debug state

```bash
# Any active debug sessions?
cat debug-log.md 2>/dev/null | tail -20
```

### Check for pipeline artifacts

```bash
# Any PRD?
ls docs/PRD.md docs/features/*/PRD.md 2>/dev/null

# Any build-prd pipeline branches?
git branch --list 'build/*' 2>/dev/null
```

## Step 3: Determine Project Phase

Based on what you found, classify the project into one of these phases:

| Phase | Signals | Next Action |
|-------|---------|------------|
| **Fresh** | No specs, no PRD, no code | "Start by writing your PRD: `docs/PRD.md`" |
| **PRD exists, no specs** | PRD exists, specs/ is empty | "Run `/build-prd` to start the pipeline" |
| **Specifying** | spec.md exists, no plan | "Run `/speckit.plan` to create the implementation plan" |
| **Planning** | plan.md exists, no tasks | "Run `/speckit.tasks` to break down the work" |
| **Implementing** | tasks.md exists, some `[X]` some `[ ]` | "Continue implementation — N/M tasks done. Next: [task name]" |
| **Implementing (stalled)** | tasks.md exists, no recent commits | "Implementation appears stalled. Last commit was [date]. Resume with `/speckit.implement`" |
| **Auditing** | All tasks `[X]`, no PR yet | "Implementation complete. Run audit and create PR" |
| **QA** | PR exists, QA reports present | "QA in progress. [X/Y flows passing]. Run `/qa-pass` for live review" |
| **Debugging** | debug-log.md has active entries | "Debugging in progress for [issue]. Run `/debug` to continue" |
| **Complete** | PR merged, all tasks done | "This feature is complete. Start a new feature with a new PRD." |
| **Multiple features** | Multiple spec dirs | List each with its phase, ask which to resume |

## Step 4: Summarize Current State

Present a concise status report:

```markdown
## Session Resume

**Project**: [name]
**Branch**: [current branch]
**Version**: [from VERSION file]

### Current State: [phase name]

[One sentence describing where things are]

### In-Progress Features

| Feature | Phase | Progress | Next Step |
|---------|-------|----------|-----------|
| [name] | Implementing | 12/18 tasks | Task 13: "Add validation to signup form" |
| [name] | Planning | spec done | Run `/speckit.plan` |

### Uncommitted Work
[list or "Working directory clean"]

### Stashed Work
[list or "No stashes"]

### Recent Activity (last 24h)
- [commit messages]

### QA Status
[Latest QA results or "No QA runs yet"]

### Debug Status
[Active debug sessions or "No active debug sessions"]

### What to Do Next
1. [Specific, actionable next step]
2. [Second step if applicable]
```

## Step 5: Offer Quick Actions

Based on the detected state, suggest the most relevant commands:

```
### Quick Actions

Based on your current state, here's what makes sense:

- `/speckit.implement` — Continue implementing [feature] (12/18 tasks done)
- `/qa-pass` — Run a live QA walkthrough of what's built so far
- `/debug [issue]` — Fix a bug without creating a new spec
- `/build-prd` — Start a new feature from a PRD
```

## Rules

- This skill is READ-ONLY — it surveys the project state, it does not change anything
- Be concise — the user wants to know where they are, not read a novel
- Be specific about next steps — "continue implementing" is bad; "run `/speckit.implement` — next task is 'Add validation to signup form' (task 13 of 18)" is good
- If there's uncommitted or stashed work, ALWAYS mention it prominently — it's easy to forget
- If multiple features are in progress, list ALL of them and ask which to resume
- If the project looks fresh (no specs, no code), suggest starting with a PRD
- Check for debug-log.md and QA results — they provide context about recent issues
- Always show the VERSION — it helps the user know which state they're looking at
