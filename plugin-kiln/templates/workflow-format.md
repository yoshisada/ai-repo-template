# Workflow Format Specification

Workflows are markdown files stored in `.kiln/workflows/`.

## File Structure

- **Filename**: `{workflow-name}.md`
- **Location**: `.kiln/workflows/`

## Required Sections

### Name
Human-readable workflow name.

### Trigger
When this workflow should run. One of:
- `manual` — invoked by the user
- `on-commit` — runs on every commit
- `on-pr` — runs when a PR is created or updated

### Steps
Ordered list of actions. Each step is either:
- A skill invocation (e.g., `/specify`, `/plan`)
- A shell command (e.g., `npm test`)

### Inputs
Required inputs and their types. Each input has:
- `name` — parameter name
- `type` — `string`, `number`, `boolean`, `path`
- `required` — whether the input is mandatory
- `default` — default value (if optional)

### Outputs
Expected outputs and their locations. Each output has:
- `name` — output name
- `path` — file path relative to project root
- `format` — `markdown`, `json`, `text`

## Example

```markdown
# Build and Test

## Trigger
manual

## Steps
1. `/implement` — Execute implementation tasks
2. `npm test` — Run test suite
3. `/audit` — Run PRD compliance audit

## Inputs
- `feature` (string, required) — Feature directory name in specs/

## Outputs
- `audit-report` — `specs/{feature}/audit-report.md` (markdown)
- `test-results` — `.kiln/qa/test-results.json` (json)
```
