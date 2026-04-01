# Data Model: QA Agent Optimization, Kiln Doctor Enhancements & Template Improvements

**Date**: 2026-04-01

## Entities

### Agent Note

A markdown file written by each pipeline agent before shutdown.

- **Location**: `specs/<feature>/agent-notes/<agent-name>.md`
- **Fields**:
  - Agent name (derived from filename)
  - What was confusing (free text)
  - Where the agent got stuck (free text)
  - What could be improved (free text)
  - Timestamp
- **Lifecycle**: Created once per pipeline run, per agent. Read by retrospective agent. Never deleted.

### Version Sync Config

Optional JSON configuration declaring which files track the canonical `VERSION` file.

- **Location**: `.kiln/version-sync.json`
- **Fields**:
  - `include`: Array of file paths (relative to repo root) that should match `VERSION`
  - `exclude`: Array of file paths to skip even if they contain version strings
- **Defaults**: If file doesn't exist, scan `package.json` and `plugin/package.json` only.

### Retention Rules

Extension to the kiln manifest defining cleanup policies.

- **Location**: Within `plugin/templates/kiln-manifest.json`, as a `retention` property on directory entries
- **Fields**:
  - `keep_last`: Integer — number of most recent files to keep
  - `archive_completed`: Boolean — move completed items to `completed/` subdirectory
  - `max_age_days`: Integer — delete files older than N days (optional, future)
- **Lifecycle**: Read by `/kiln-doctor --cleanup` and `/kiln-cleanup`. Applied only when explicitly invoked.

### Issue Template

Markdown template used by `/report-issue` to structure new issues.

- **Location (source)**: `plugin/templates/issue.md`
- **Location (consumer)**: `.kiln/templates/issue.md` (scaffolded by `init.mjs`)
- **Fields**: Title, type, severity, category, source, description, impact, suggested fix
- **Lifecycle**: Created once during scaffold. Customizable by consumer projects.

## Relationships

```
kiln-manifest.json
  └── retention rules → read by /kiln-doctor --cleanup
  └── retention rules → read by /kiln-cleanup

VERSION file
  └── compared against → version-sync targets (package.json, etc.)
  └── configured by → .kiln/version-sync.json

agent-notes/
  └── written by → pipeline agents (implementer, qa-engineer, etc.)
  └── read by → retrospective agent

issue template
  └── source → plugin/templates/issue.md
  └── scaffolded to → .kiln/templates/issue.md
  └── read by → /report-issue skill

.kiln/issues/
  └── active issues → top-level files
  └── archived issues → completed/ subdirectory
  └── scanned by → /report-issue, /issue-to-prd (top-level only)
```
