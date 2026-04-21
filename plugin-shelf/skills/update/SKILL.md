---
name: update
description: Push a progress update to Obsidian. Records session summary, status change, next steps, decisions, and human-needed items — all appended to the project dashboard via MCP.
---

# shelf:update — Push Progress Update

Record your session's work in Obsidian. Appends a timestamped progress entry, updates dashboard frontmatter (status, next step), optionally creates a decision record, and manages the Human Needed checklist.

## User Input

```text
$ARGUMENTS
```

Parse these optional flags from the arguments:
- `--summary "text"` — session summary
- `--status "text"` — project status (e.g., "in-progress", "blocked", "done")
- `--next-step "text"` — what to do next
- `--decision "text"` — a decision made this session
- `--human-needed "item1, item2"` — items requiring human attention

## Step 1: Resolve Project Identity (FR-005, FR-006)

Determine the project slug and base path. Priority order: explicit argument > `.shelf-config` > git remote defaults.

1. If `.shelf-config` exists in the repo root:
   a. Parse it: skip lines starting with `#` (comments) and blank lines; split each remaining line on the first `=` to get key and value; trim whitespace from both
   b. Extract `base_path` and `slug` values
   c. If both are present and non-empty: use them as `$BASE_PATH` and `$SLUG` — do NOT derive from git remote or prompt the user (FR-006). Skip to substep 4
   d. If either is missing or empty: warn ".shelf-config is malformed — missing {key}. Falling back to defaults." and continue to substep 2
2. If no valid `.shelf-config`:
   a. If the user provided a project name as an argument: use it as `$SLUG`
   b. Otherwise: run `git remote get-url origin` and extract the repo name (last path segment, strip `.git` suffix) as `$SLUG`
   c. Set `$BASE_PATH = "projects"` (default)
3. All vault paths use: `{$BASE_PATH}/{$SLUG}/...`

## Step 2: Read Current Dashboard State (FR-012)

Read the existing dashboard before making any changes:

```
mcp__obsidian-projects__read_file({ path: "{base_path}/{slug}/{slug}.md" })
```

- If not found: suggest "No project found — run `/shelf:create` first" and STOP
- Parse the YAML frontmatter to get current `status`, `next_step`, `last_updated`
- Parse the `## Human Needed` section to preserve existing `- [x]` items (FR-010)
- Parse the `## Feedback` and `## Feedback Log` sections to preserve them

**If MCP fails**: warn "MCP server unavailable — cannot update project" and STOP. (NFR-004)

## Step 3: Resolve Inputs (FR-011)

If `--summary` was not provided:
1. Run `git log --oneline -10` to see recent commits
2. Analyze the conversation context for what was accomplished
3. Ask the user: "What did you work on this session?" and wait for a response

If `--status` was not provided: keep the current status from dashboard frontmatter.

If `--next-step` was not provided: ask "What's the next step?" or infer from context.

## Step 4: Ensure Monthly Progress File Exists (FR-008, FR-003, FR-004)

Determine the current month: `YYYY-MM` (e.g., `2026-04`).

**Template resolution** (FR-004): Read the progress template. First check if `.shelf/templates/progress.md` exists in the repo. If it does, use that. Otherwise, use `plugin-shelf/templates/progress.md`. The template includes `project: "[[{slug}]]"` as a backlink (FR-005) and `tags: status/in-progress`.

```
mcp__obsidian-projects__read_file({ path: "{base_path}/{slug}/progress/{YYYY-MM}.md" })
```

- If not found, create it using the progress template header (frontmatter + month heading):
  ```
  mcp__obsidian-projects__create_file({
    path: "{base_path}/{slug}/progress/{YYYY-MM}.md",
    content: "{rendered progress template header with frontmatter}"
  })
  ```
- If found, store existing content for appending

**If MCP fails**: warn and continue — progress entry will be skipped. (NFR-004)

## Step 5: Append Progress Entry (FR-007, FR-003, FR-005)

Build the progress entry using the body section of the progress template from `plugin-shelf/templates/progress.md` (FR-003). Replace placeholders:
- `{date}` — today `YYYY-MM-DD`
- `{summary}` — session summary
- `{outcomes}` — bulleted key outcomes
- `{links}` — PR links, commit SHAs, or issue references
- `{decision_link}` — if a decision was made, link to the decision file

```markdown
## {YYYY-MM-DD}

**Summary**: {summary}

**Key outcomes**:
- {outcome_1}
- {outcome_2}

**Links**: {any PR links, commit SHAs, or issue references from the session}
{if decision: "**Decision**: [{decision_title}](../decisions/{decision_file})"}
```

Append to the monthly progress file:

```
mcp__obsidian-projects__update_file({
  path: "{base_path}/{slug}/progress/{YYYY-MM}.md",
  content: "{existing_content}\n\n{new_entry}"
})
```

**If MCP fails**: warn "Could not append progress entry" and continue. (NFR-004)

## Step 6: Create Decision Record (FR-031, FR-032, FR-033, FR-003, FR-004, FR-005)

If `--decision` was provided OR a decision was detected from conversation context:

1. Generate a decision slug from the decision text (lowercase, hyphens, max 50 chars)
2. **Template resolution** (FR-004): Read the decision template. First check if `.shelf/templates/decision.md` exists in the repo. If it does, use that. Otherwise, use `plugin-shelf/templates/decision.md`.
3. Replace placeholders in the template:
   - `{title}` — decision title
   - `{date}` — today `YYYY-MM-DD`
   - `{slug}` — project slug (for `project: "[[{slug}]]"` backlink, FR-005)
   - `{context}` — context from conversation
   - `{options}` — options considered, or "Documented post-decision"
   - `{decision}` — decision text
   - `{rationale}` — reasoning, or inferred from context
4. Create the decision record:

```
mcp__obsidian-projects__create_file({
  path: "{base_path}/{slug}/decisions/{YYYY-MM-DD}-{decision_slug}.md",
  content: "{rendered decision template}"
})
```

**If MCP fails**: warn "Could not create decision record" and continue. (NFR-004)

## Step 7: Update Dashboard (FR-009, FR-010)

Rebuild the dashboard content:

1. **Update frontmatter**: set `status`, `next_step`, `last_updated` to new values (FR-009)
2. **Update Human Needed section** (FR-010):
   - Preserve existing `- [x]` (completed) items
   - Add new `- [ ]` items from `--human-needed` argument
   - Remove duplicates
3. **Preserve** all other sections (`## Feedback`, `## Feedback Log`) unchanged

```
mcp__obsidian-projects__update_file({
  path: "{base_path}/{slug}/{slug}.md",
  content: "{rebuilt dashboard content}"
})
```

**If MCP fails**: warn "Could not update dashboard" and report partial completion. (NFR-004)

## Step 8: Report Results

Print a confirmation:

```
Project '{slug}' updated in Obsidian.

  Status:     {status}
  Next step:  {next_step}
  Progress:   Appended to progress/{YYYY-MM}.md
  {if decision: "Decision:   decisions/{YYYY-MM-DD}-{decision_slug}.md"}
  {if human_needed: "Human Needed: {N} items added"}

Updated: {YYYY-MM-DD}
```

If any steps had partial failures, include a warnings section.

## Status Label Validation (FR-013)

Before setting or displaying a project status, read the canonical status list from `plugin-shelf/status-labels.md`.

- If the status is in the canonical list: use it as-is
- If the status matches a non-canonical equivalent: normalize to the canonical value and warn the user
- If the status is unrecognized: warn "Unknown status '{value}' — canonical values are: idea, active, paused, blocked, completed, archived"

## Rules

- **Read before write** — always read the current dashboard state before updating (FR-012)
- **All writes go through MCP** — never write directly to the filesystem (NFR-001)
- **No hardcoded vault paths** — always use the resolved base path (NFR-002, NFR-003)
- **Graceful degradation** — if MCP is unavailable, warn and exit cleanly (NFR-004)
- **No secrets in notes** — do not include API keys, tokens, or credentials (NFR-005)
- **Preserve existing content** — never clobber completed Human Needed items or other sections (FR-010, FR-012)
