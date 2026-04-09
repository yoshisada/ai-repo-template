# Quickstart: Shelf Skills Polish

## What Changed

- `shelf-create` is now a wheel workflow (deterministic steps, resumable, observable)
- `shelf-repair` is a new wheel workflow for re-templating existing projects
- All shelf skills use canonical status labels from `plugin-shelf/status-labels.md`
- `shelf-full-sync` produces a summary at the end

## How to Test

### shelf-create workflow
```bash
# In a consumer project with .shelf-config:
/shelf-create

# Verify outputs:
cat .wheel/outputs/detect-repo-progress.txt    # progress signals detected
cat .wheel/outputs/create-project-result.md     # MCP operations performed
```

### shelf-repair workflow
```bash
# On a project with an existing Obsidian dashboard:
/shelf-repair

# Review the diff before changes:
cat .wheel/outputs/shelf-repair-diff.md
# Verify repairs:
cat .wheel/outputs/shelf-repair-result.md
```

### Status labels
```bash
# Check the canonical list:
cat plugin-shelf/status-labels.md

# Try a non-canonical status in shelf-update:
/shelf-update --status "in-progress"
# Expected: warning + normalization to "active"
```

### shelf-full-sync summary
```bash
# Run full sync:
/wheel-run shelf:shelf-full-sync

# Check summary:
cat .wheel/outputs/shelf-full-sync-summary.md
```

## File Map

| File | Purpose |
|------|---------|
| `plugin-shelf/workflows/shelf-create.json` | New workflow definition |
| `plugin-shelf/workflows/shelf-repair.json` | New workflow definition |
| `plugin-shelf/workflows/shelf-full-sync.json` | Updated with summary step |
| `plugin-shelf/status-labels.md` | Canonical status label definitions |
| `plugin-shelf/skills/shelf-create/SKILL.md` | Rewritten as thin wrapper |
| `plugin-shelf/skills/shelf-repair/SKILL.md` | New skill (thin wrapper) |
| `plugin-shelf/skills/shelf-update/SKILL.md` | Updated with status label ref |
| `plugin-shelf/skills/shelf-status/SKILL.md` | Updated with status label ref |
| `plugin-shelf/skills/shelf-sync/SKILL.md` | Updated with status label ref |
