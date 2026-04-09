# Data Model: Shelf Skills Polish

## Entities

### Workflow (shelf-create.json, shelf-repair.json)

JSON file in `plugin-shelf/workflows/` with this structure:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Workflow identifier (e.g., `shelf-create`) |
| `version` | string | Semver version of the workflow definition |
| `steps` | array | Ordered list of step objects |

Each **step** object:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Unique step identifier |
| `type` | string | yes | `command` or `agent` |
| `command` | string | if command | Bash command to execute |
| `instruction` | string | if agent | Agent prompt/instruction |
| `context_from` | string[] | no | Step IDs whose outputs feed into this step |
| `output` | string | yes | Output file path (relative to repo root) |
| `terminal` | boolean | no | If true, this is the final step |

### Status Label

Defined in `plugin-shelf/status-labels.md`:

| Status | Description | Maps From |
|--------|-------------|-----------|
| `idea` | Not yet started, concept only | `concept`, `planned`, `not started` |
| `active` | Currently being worked on | `in-progress`, `in progress`, `wip`, `doing` |
| `paused` | Temporarily halted | `on hold`, `hold`, `waiting` |
| `blocked` | Cannot proceed, external dependency | `stuck`, `needs help` |
| `completed` | All work done | `done`, `finished`, `shipped` |
| `archived` | No longer maintained | `deprecated`, `abandoned`, `inactive` |

### Progress Signal

Detected by the `detect-repo-progress` command step:

| Signal | Detection Method | Status Implication |
|--------|------------------|--------------------|
| `specs/` directory | `ls specs/*/spec.md 2>/dev/null \| wc -l` | If specs exist but no code: `idea` |
| Code directories | `ls -d src/ lib/ plugin-* 2>/dev/null` | If code exists: `active` |
| Test files | `find . -name '*.test.*' -o -name '*.spec.*' \| wc -l` | Strengthens `active` signal |
| VERSION file | `cat VERSION 2>/dev/null` | Confirms established project |
| Git commit count | `git rev-list --count HEAD 2>/dev/null` | High count (50+) = mature project |
| Open issues | `gh issue list --state open --json number \| jq length` | Active development indicator |
| `.kiln/` artifacts | `ls .kiln/ 2>/dev/null` | Confirms kiln-managed project |
| PRD files | `ls docs/features/*/PRD.md 2>/dev/null \| wc -l` | Planning activity |

### Dashboard Sections (preserved by shelf-repair)

| Section | Preservable | Notes |
|---------|-------------|-------|
| YAML frontmatter | Partially | Status normalized, tags/dates updated, structure refreshed |
| `## Human Needed` | Yes | All items preserved (both `- [ ]` and `- [x]`) |
| `## Feedback` | Yes | User-written content preserved verbatim |
| `## Feedback Log` | Yes | Historical entries preserved verbatim |
| Template structure | No | Updated to match current template |

## State Transitions

### Project Status Lifecycle

```
idea → active → completed → archived
         ↕
       paused
         ↕
       blocked
```

- `idea` → `active`: When implementation begins (code detected or user sets status)
- `active` → `paused`: User manually pauses
- `active` → `blocked`: External dependency prevents progress
- `paused`/`blocked` → `active`: Blocker resolved or work resumes
- `active` → `completed`: All work done
- `completed` → `archived`: Project no longer maintained
