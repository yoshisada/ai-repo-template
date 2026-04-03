# Quickstart: Shelf Config Artifact

## What This Feature Does

After running `/shelf-create`, a `.shelf-config` file is written to your repo root. All shelf skills (`/shelf-sync`, `/shelf-update`, `/shelf-status`, `/shelf-feedback`, `/shelf-release`) read this file to automatically resolve your Obsidian project path — no more passing the project name every time.

## How to Use

1. Run `/shelf-create my-project` (or let it derive from git remote)
2. Confirm the slug and base path when prompted
3. A `.shelf-config` file appears in your repo root
4. All subsequent shelf commands work without arguments

## Example `.shelf-config`

```ini
# Shelf configuration — maps this repo to its Obsidian project
base_path = @second-brain/projects
slug = plugin-shelf
dashboard_path = @second-brain/projects/plugin-shelf/plugin-shelf.md
```

## Manual Setup

If you set up your project before this feature existed, create `.shelf-config` manually:

```ini
base_path = @second-brain/projects
slug = your-project-name
dashboard_path = @second-brain/projects/your-project-name/your-project-name.md
```

Commit it to share with collaborators.
