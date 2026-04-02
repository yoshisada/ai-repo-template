# Research: Pipeline Workflow Polish

**Date**: 2026-04-01

## Summary

No external dependencies or unknowns require resolution. All 16 FRs target existing plugin infrastructure (markdown skills, bash hooks, Node.js scaffold) with well-understood patterns.

## Decisions

### Bash Syntax Validation Depth (FR-001)

**Decision**: Use `bash -n` only (syntax check, not semantic validation)
**Rationale**: The PRD explicitly scopes this to structural validation, not behavioral testing. `bash -n` catches syntax errors (unclosed quotes, missing `fi`, bad redirections) without requiring referenced commands to exist on the system. This is fast and portable.
**Alternatives considered**: ShellCheck (`shellcheck`) — more thorough but adds an external dependency and may flag style issues that aren't errors.

### Version Hook Staging Strategy (FR-011)

**Decision**: Add `git add` calls at the end of `version-increment.sh` to stage VERSION and package.json changes
**Rationale**: The hook already writes files in-place. Adding `git add` at the end stages the changes for inclusion in whatever commit the agent creates next. This eliminates the need for separate "chore: version bump" commits.
**Alternatives considered**: Using a marker file to signal the implementing agent — rejected as unnecessarily complex. The hook's current in-place write behavior is already correct; we just need to stage the result.

### Roadmap File Format (FR-014)

**Decision**: Simple markdown list grouped by theme headings, no frontmatter, no status tracking
**Rationale**: The PRD explicitly states the roadmap is intentionally lightweight. Adding structure beyond grouped lists would overlap with `.kiln/issues/` functionality.
**Alternatives considered**: YAML-based tracking with priorities and dates — rejected per PRD non-goals.

### Issue Archival Location (FR-007, FR-008, FR-009)

**Decision**: Archive to `.kiln/issues/completed/` subdirectory
**Rationale**: Consistent with the existing kiln-doctor retention behavior that already references this path. Keeps archived issues accessible for audit trail while removing them from the active backlog scan.
**Alternatives considered**: Deleting completed issues — rejected because audit trail is valuable.
