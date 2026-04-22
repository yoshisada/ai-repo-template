---
name: "kiln-next"
description: "Analyze full project state and produce prioritized next steps mapped to kiln commands. Replaces /kiln:kiln-resume. Run at session start or after /kiln:kiln-build-prd."
---

# Next — Prioritized Next Steps

Analyze the full project state and produce a prioritized list of actionable next steps, each mapped to a concrete kiln command. Run this at the start of every session or after `/kiln:kiln-build-prd`.

```text
$ARGUMENTS
```

## Flag Parsing

Check if `--brief` was passed in `$ARGUMENTS`:
- If `--brief` is present: set BRIEF_MODE=true (top 5 only, no report file, no backlog updates)
- Otherwise: set BRIEF_MODE=false (full output, save report, create backlog issues)

## Step 1: Read Project Context

<!-- FR-001: Review all available project state sources -->

```bash
# Project identity
PROJECT_NAME=$(basename "$(pwd)")
REMOTE=$(git remote get-url origin 2>/dev/null || echo "no remote")
echo "Project: $PROJECT_NAME"
echo "Remote: $REMOTE"

# Current branch
BRANCH=$(git branch --show-current)
echo "Branch: $BRANCH"

# Version
VERSION=$(cat VERSION 2>/dev/null || echo "no version")
echo "Version: $VERSION"
```

Read:
- `.specify/memory/constitution.md` — governing principles (quick skim)

## Step 2: Gather State from Local Sources

<!-- FR-001: Review specs, tasks, blockers, retrospectives, QA, issues, spec FRs -->

### Incomplete tasks from all features

```bash
echo "=== INCOMPLETE TASKS ==="
for tasks_file in specs/*/tasks.md; do
  [ -f "$tasks_file" ] || continue
  FEATURE=$(basename "$(dirname "$tasks_file")")
  INCOMPLETE=$(grep -n '^\s*- \[ \]' "$tasks_file" 2>/dev/null || true)
  TOTAL=$(grep -c '^\s*- \[' "$tasks_file" 2>/dev/null || echo 0)
  DONE=$(grep -c '^\s*- \[[xX]\]' "$tasks_file" 2>/dev/null || echo 0)
  if [ -n "$INCOMPLETE" ]; then
    echo "--- $FEATURE ($DONE/$TOTAL done) ---"
    echo "$INCOMPLETE"
  fi
done
```

### Blockers

```bash
echo "=== BLOCKERS ==="
for blockers_file in specs/*/blockers.md; do
  [ -f "$blockers_file" ] || continue
  FEATURE=$(basename "$(dirname "$blockers_file")")
  echo "--- $FEATURE ---"
  cat "$blockers_file"
done
if ! ls specs/*/blockers.md 1>/dev/null 2>&1; then
  echo "No blockers found."
fi
```

### Retrospective action items

```bash
echo "=== RETROSPECTIVE ACTION ITEMS ==="
for retro_file in specs/*/retrospective.md; do
  [ -f "$retro_file" ] || continue
  FEATURE=$(basename "$(dirname "$retro_file")")
  echo "--- $FEATURE ---"
  cat "$retro_file"
done
if ! ls specs/*/retrospective.md 1>/dev/null 2>&1; then
  echo "No retrospectives found."
fi
```

### QA reports

```bash
echo "=== QA REPORTS ==="
for report in .kiln/qa/results/QA-REPORT.md .kiln/qa/results/QA-PASS-REPORT.md .kiln/qa/results/UX-REPORT.md; do
  if [ -f "$report" ]; then
    echo "--- $report ---"
    head -50 "$report"
    echo "..."
  fi
done
if ! ls .kiln/qa/results/*.md 1>/dev/null 2>&1; then
  echo "No QA reports found."
fi
```

### Backlog issues

```bash
echo "=== BACKLOG ISSUES ==="
if [ -d ".kiln/issues" ]; then
  for issue_file in .kiln/issues/*.md; do
    [ -f "$issue_file" ] || continue
    TITLE=$(head -1 "$issue_file")
    echo "- $(basename "$issue_file"): $TITLE"
  done
else
  echo "No .kiln/issues/ directory."
fi
```

### Unimplemented FRs (cross-reference specs against tasks)

```bash
echo "=== UNIMPLEMENTED FRs ==="
for spec_file in specs/*/spec.md; do
  [ -f "$spec_file" ] || continue
  FEATURE=$(basename "$(dirname "$spec_file")")
  TASKS_FILE="specs/$FEATURE/tasks.md"

  # Extract FR IDs from spec
  FRS=$(grep -oE 'FR-[0-9]+' "$spec_file" 2>/dev/null | sort -u || true)

  if [ -f "$TASKS_FILE" ]; then
    # Check which FRs have no corresponding completed task
    for FR in $FRS; do
      # Check if any completed task references this FR
      REFERENCED=$(grep -l "$FR" "$TASKS_FILE" 2>/dev/null || true)
      COMPLETED=$(grep "\[X\].*$FR\|\[x\].*$FR" "$TASKS_FILE" 2>/dev/null || true)
      if [ -z "$COMPLETED" ] && [ -n "$REFERENCED" ]; then
        echo "- $FEATURE: $FR (task exists but not completed)"
      elif [ -z "$REFERENCED" ]; then
        echo "- $FEATURE: $FR (no task references this FR)"
      fi
    done
  else
    echo "- $FEATURE: No tasks.md — all FRs unimplemented"
  fi
done
```

## Step 3: Gather State from GitHub Sources

<!-- FR-014: Skip GitHub sources gracefully when gh unavailable -->

```bash
echo "=== GITHUB AVAILABILITY ==="
if command -v gh >/dev/null 2>&1; then
  if gh auth status 2>&1 | grep -q "Logged in"; then
    echo "GitHub CLI: available and authenticated"
    GH_AVAILABLE=true
  else
    echo "GitHub CLI: installed but not authenticated — skipping GitHub sources"
    GH_AVAILABLE=false
  fi
else
  echo "GitHub CLI: not installed — skipping GitHub sources"
  GH_AVAILABLE=false
fi
```

If GitHub CLI is available and authenticated:

```bash
# Only run if GH_AVAILABLE=true (check output from previous command)
echo "=== GITHUB ISSUES ==="
gh issue list --state open --json number,title,labels --limit 25 2>/dev/null || echo "Failed to fetch GitHub issues"

echo "=== GITHUB PR COMMENTS ==="
gh pr list --state open --json number,title,comments --limit 10 2>/dev/null || echo "Failed to fetch PR data"
```

If GitHub CLI is NOT available, note the skipped sources:
```
Skipped sources (GitHub CLI unavailable):
- GitHub issues
- GitHub PR comments
```

## Step 4: Classification and Prioritization

<!-- FR-002: Prioritized recommendation list -->
<!-- FR-003: Each recommendation includes description, command, priority, source -->
<!-- FR-012: Every recommendation maps to a valid kiln command -->

Now analyze ALL gathered data and classify each finding. For each item found:

### Classification Rules

| Finding Source | Category | Priority |
|---------------|----------|----------|
| `specs/*/blockers.md` entries | blocker | critical |
| Failing tests that block progress | blocker | critical |
| Unchecked tasks in `specs/*/tasks.md` | incomplete-work | high |
| QA failures from `.kiln/qa/` reports | qa-audit-gap | medium |
| Audit compliance gaps | qa-audit-gap | medium |
| Open issues in `.kiln/issues/` | backlog | low |
| Open GitHub issues | backlog | low |
| Retrospective action items | improvement | low |
| Unimplemented FRs (no spec) | incomplete-work | high |
| Unimplemented FRs (spec exists) | incomplete-work | high |

### Command Mapping Rules

<!-- FR-012: Every recommendation maps to a valid kiln command -->
<!-- FR-009: Only whitelisted high-level commands in output -->
<!-- FR-010: Internal pipeline commands must not appear -->

For each finding, assign the most specific applicable kiln command:

| Finding Type | Command |
|-------------|---------|
| Incomplete task | `/kiln:kiln-build-prd` |
| Failing test | `/kiln:kiln-fix <brief description of the failure>` |
| QA finding (specific bug) | `/kiln:kiln-fix <brief description of the issue>` |
| QA finding (needs re-test) | `/kiln:kiln-qa-pass` |
| Audit gap (missing implementation) | `/kiln:kiln-build-prd` |
| Audit gap (missing test) | `/kiln:kiln-fix <add test for ...>` |
| Unimplemented FR (no spec exists) | `/kiln:kiln-build-prd` |
| Unimplemented FR (spec exists) | `/kiln:kiln-build-prd` |
| Backlog item (bug report) | `/kiln:kiln-fix <description>` |
| Backlog item (feature request) | `/kiln:kiln-build-prd` |
| Retrospective action (process) | `/kiln:kiln-build-prd` or `/kiln:kiln-report-issue` |
| Retrospective action (bug) | `/kiln:kiln-fix <description>` |
| No PRD exists | `/kiln:kiln-create-prd` |
| No specs exist but PRD exists | `/kiln:kiln-build-prd` |
| No repo exists yet | `/clay:clay-create-repo` |

### Command Filtering (FR-009, FR-010)

After mapping findings to commands, filter ALL recommendations through these rules:

**Allowed commands** (whitelist — only these may appear in output):
`/kiln:kiln-build-prd`, `/kiln:kiln-fix`, `/kiln:kiln-qa-pass`, `/kiln:kiln-create-prd`, `/clay:clay-create-repo`, `/kiln:kiln-init`,
`/kiln:kiln-analyze-issues`, `/kiln:kiln-report-issue`, `/kiln:kiln-ux-evaluate`, `/kiln:kiln-issue-to-prd`,
`/kiln:kiln-next`, `/kiln:kiln-todo`, `/kiln:kiln-roadmap`

**Blocked commands** (NEVER show these in output):
`/specify`, `/plan`, `/tasks`, `/implement`, `/audit`

**Replacement rules** — if a blocked command would be recommended, replace it:
- `/specify` -> `/kiln:kiln-build-prd`
- `/plan` -> `/kiln:kiln-build-prd`
- `/tasks` -> `/kiln:kiln-build-prd`
- `/implement` -> `/kiln:kiln-build-prd`
- `/audit` -> `/kiln:kiln-build-prd`

If after filtering a recommendation has no valid command, drop it entirely.

**Prohibited**: Vague suggestions like "review the code" or "look into this". Every recommendation MUST include a specific, executable kiln command from the whitelist above.

### Priority Ordering

<!-- FR-002: Ordered by blockers first, then incomplete work, then QA/audit, then backlog, then improvements -->

Sort all recommendations by:
1. **critical** — blockers (must resolve before anything else)
2. **high** — incomplete work (active tasks from current or recent builds)
3. **medium** — QA/audit gaps (quality issues that need attention)
4. **low** — backlog items and improvements (can wait)

Within each priority level, sort by recency (most recent first).

## Step 5: Terminal Summary Output

<!-- FR-004: Terminal summary of at most 15 items grouped by priority -->
<!-- FR-006: --brief flag outputs top 5 only -->
<!-- FR-013: Idempotent -->
<!-- FR-015: Do not auto-execute suggested commands -->

If **BRIEF_MODE=true**: Show only the top 5 recommendations and STOP here (no report, no backlog updates).

If **BRIEF_MODE=false**: Show up to 15 recommendations.

### Detect Project State

Before outputting recommendations, detect if the project is in a "fresh" or "clean" state:
- **No PRD, no specs, no code**: Report "Fresh project" and recommend starting with `/kiln:kiln-create-prd`
- **All tasks done, no open issues, no QA failures**: Report "Project is in good shape" and suggest only low-priority improvements or checking the backlog

### Output Format

Present the recommendations in this exact format:

```markdown
## What's Next

**Project**: [name] | **Branch**: [branch] | **Version**: [version]

[One-sentence project state summary — e.g., "3 blockers need attention, 5 tasks remain incomplete across 2 features."]

### Critical
- [ ] [description] — `/command` _(source: path/to/artifact)_

### High
- [ ] [description] — `/command` _(source: path/to/artifact)_

### Medium
- [ ] [description] — `/command` _(source: path/to/artifact)_

### Low
- [ ] [description] — `/command` _(source: path/to/artifact)_
```

If a priority level has no items, omit that section entirely.

### Suggested Next Command

<!-- FR-001: Single prominent "Suggested next" line -->
<!-- FR-002: Include brief reason for the suggestion -->
<!-- FR-003: "Nothing urgent" fallback for clean projects -->

After the recommendations list (or after the project state summary if no recommendations exist), append:

```markdown
---

> **Suggested next**: `/command` — reason
```

**Rules for the suggested command:**
- Pick the **first item** from the priority-sorted recommendation list (Step 4) — this is the single highest-priority command.
- The `reason` is the description from that same recommendation item (keep it to one sentence).
- If **no actionable recommendations** exist (project is clean, all tasks done, no issues), output:

```markdown
---

> **Suggested next**: Nothing urgent — check the backlog with `/kiln:kiln-issue-to-prd`
```

- The "Suggested next" line MUST appear in **both** normal and `--brief` modes — it is never suppressed.

### Roadmap Suggestions (when idle) — FR-016

If **no actionable recommendations exist** (no critical, high, or medium items — the project is clean), check for roadmap items:

```bash
echo "=== ROADMAP ITEMS ==="
if [ -f ".kiln/roadmap.md" ]; then
  # Extract up to 5 bullet items from the roadmap
  grep -E '^\s*- ' .kiln/roadmap.md 2>/dev/null | head -5
else
  echo "No roadmap file found."
fi
```

If roadmap items are found and there is no urgent work, append after the "Suggested next" line:

```markdown
### Ideas from Your Roadmap

Nothing pressing. Here are some ideas from your roadmap:

- [item 1]
- [item 2]
- [item 3]

_Add more with `/kiln:kiln-roadmap <idea>`. Pick one and run `/specify` to start._
```

If urgent work exists (any critical, high, or medium priority items), do NOT show roadmap items — urgent work takes priority.

If **BRIEF_MODE=false**, append after the "Suggested next" line:
```markdown
Full report: `.kiln/logs/next-<timestamp>.md`
[N] new backlog items created in `.kiln/issues/`
```

If **BRIEF_MODE=true**, append after the "Suggested next" line:
```markdown
_Showing top 5 only. Run `/kiln:kiln-next` (without --brief) for the full analysis._
```

## Step 6: Persistent Report

<!-- FR-005: Save detailed report to .kiln/logs/next-<YYYY-MM-DD-HHmmss>.md -->

**Skip this step if BRIEF_MODE=true.**

Generate a timestamp and save a detailed markdown report:

```bash
# Create logs directory if it doesn't exist
mkdir -p .kiln/logs

# Generate timestamp for filename
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
REPORT_PATH=".kiln/logs/next-${TIMESTAMP}.md"
echo "Report will be saved to: $REPORT_PATH"
```

Write the report to `$REPORT_PATH` in this exact format:

```markdown
# Continuance Report

**Generated**: <YYYY-MM-DD HH:mm:ss>
**Branch**: [branch]
**Version**: [version]

## Project State Summary

[Paragraph summarizing overall project health — how many features are in progress, how many tasks remain, any blockers, QA status, etc.]

## Sources Analyzed

- [x] specs/*/tasks.md — [N] incomplete tasks found
- [x] specs/*/blockers.md — [N] blockers found
- [x] specs/*/retrospective.md — [N] action items found
- [x] .kiln/qa/ — [N] QA findings
- [x] .kiln/issues/ — [N] open items
- [x] specs/*/spec.md — [N] unimplemented FRs
- [x] GitHub issues — [N] open issues
- [ ] GitHub PR comments — skipped (gh not available)
```

(Mark sources as `[x]` if analyzed, `[ ]` if skipped. Include the reason for skipping.)

```markdown
## Recommendations

| # | Priority | Description | Command | Source |
|---|----------|-------------|---------|--------|
| 1 | critical | [desc] | `/kiln:kiln-fix ...` | specs/auth/blockers.md |
| 2 | high | [desc] | `/implement` | specs/auth/tasks.md:L42 |
| ... | ... | ... | ... | ... |
```

(Include ALL recommendations, not just the top 15 from the terminal summary.)

```markdown
## Suggested Next

> **Suggested next**: `/command` — reason
```

(Same logic as the terminal summary: first item from the priority-sorted list, or "Nothing urgent" if clean.)

```markdown
## Backlog Updates

- Created: `.kiln/issues/YYYY-MM-DD-slug.md` [auto:continuance]
- Skipped (already tracked): "Title" matches `.kiln/issues/existing-file.md`
```

(List all created and skipped backlog items. If no backlog updates were made, write "No new backlog items created.")

Save the report file using the Write tool.

## Step 7: Backlog Issue Creation

<!-- FR-007: Create new issue files for discovered gaps -->
<!-- FR-008: Do not create duplicate issues -->

**Skip this step if BRIEF_MODE=true.**

For each discovered gap that is NOT already tracked in `.kiln/issues/`:

1. Read existing `.kiln/issues/` filenames and first-line titles:

```bash
# List existing issues for deduplication
mkdir -p .kiln/issues
echo "=== EXISTING ISSUES ==="
for f in .kiln/issues/*.md; do
  [ -f "$f" ] || continue
  TITLE=$(head -1 "$f" | sed 's/^#\s*//')
  echo "$(basename "$f"): $TITLE"
done
```

2. For each discovered gap, compare its description against existing issue titles. If no match is found (by title/description similarity), create a new issue file:

File naming: `.kiln/issues/<YYYY-MM-DD>-<slug>.md`

File format:
```markdown
# [Title describing the gap]

**Source**: [path to artifact that surfaced this gap]
**Priority**: [critical/high/medium/low]
**Suggested command**: `/command`
**Tags**: [auto:continuance]

## Description

[Brief description of the gap and why it matters]
```

3. If a match IS found, skip it and note: "Skipped (already tracked): [title] matches [existing file]"

4. Log all created and skipped items in the terminal output:
```
[N] new backlog items created in `.kiln/issues/`
[M] gaps already tracked (skipped)
```

## Rules

<!-- FR-009: /kiln:kiln-next replaces /kiln:kiln-resume as primary session-start command -->
<!-- FR-013: Idempotent -->
<!-- FR-015: Do not auto-execute any suggested commands -->

- This skill is **READ-ONLY during analysis** — it surveys the project state, it does not modify code files
- It MAY create files in `.kiln/logs/` (reports) and `.kiln/issues/` (backlog items) — these are metadata, not code
- **Idempotent**: Running `/kiln:kiln-next` twice on the same project state produces the same recommendations
- **Advisory only**: NEVER auto-execute any suggested command. Recommend only; the user decides what to act on.
- Be concise — the user wants to know what to do, not read a novel
- Be specific — "/implement" is acceptable; "look into the code" is not
- If multiple features are in progress, analyze ALL of them and report on each
- If the project looks fresh (no specs, no code), suggest starting with `/kiln:kiln-create-prd` or writing `docs/PRD.md`
