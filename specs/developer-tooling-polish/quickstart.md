# Quickstart: Developer Tooling Polish

## Prerequisites

- Claude Code with kiln and wheel plugins installed
- `jq` available on PATH
- Bash 5.x

## Usage

### List Workflows

```bash
# Run in any project with a workflows/ directory
/wheel-list
```

### Audit Tests

```bash
# Run in any project with test files
/qa-audit
```

The audit report will be written to `.kiln/qa/test-audit-report.md`.

## Development

Both skills are Markdown files with embedded Bash:

- `/wheel-list`: `plugin-wheel/skills/wheel-list/SKILL.md`
- `/qa-audit`: `plugin-kiln/skills/qa-audit/SKILL.md`

Edit the SKILL.md files directly. No build step required.
