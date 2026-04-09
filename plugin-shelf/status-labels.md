# Canonical Project Status Labels

These are the only valid project status values for shelf-managed projects. All shelf skills MUST use values from this list when setting or displaying project status.

| Status | Description | Non-Canonical Equivalents |
|--------|-------------|--------------------------|
| idea | Project is conceptual — no implementation has started | concept, planned, not started |
| active | Project is under active development | in-progress, in progress, wip, doing |
| paused | Work is temporarily on hold | on hold, hold, waiting |
| blocked | Progress is blocked by an external dependency or issue | stuck, needs help |
| completed | All planned work is finished and shipped | done, finished, shipped |
| archived | Project is no longer maintained or relevant | deprecated, abandoned, inactive |

## Usage

Skills that set or display status MUST:

1. Accept only canonical values from the table above
2. If a non-canonical equivalent is provided, normalize it to the canonical value and warn the user
3. If an unrecognized value is provided, warn: "Unknown status '{value}' — canonical values are: idea, active, paused, blocked, completed, archived"

## Status Inference from Repo Signals

When auto-detecting initial status (e.g., during `shelf-create`):

| Signal | Inferred Status |
|--------|----------------|
| No code directories, no specs, only a PRD or nothing | idea |
| Code directories exist, or 10+ commits, or VERSION file present | active |
| Specs + code + tests all present | active |
| Only PRDs and specs, no code | idea |
