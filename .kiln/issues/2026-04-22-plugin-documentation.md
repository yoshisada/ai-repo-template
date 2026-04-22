---
title: Write user-facing documentation for the plugins (kiln, shelf, clay, trim, wheel)
type: improvement
severity: medium
category: documentation
status: open
repo: https://github.com/yoshisada/ai-repo-template
date: 2026-04-22
---

# Write user-facing documentation for the plugins (kiln, shelf, clay, trim, wheel)

## Description

We need to work on documentation for the plugins. The source repo has CLAUDE.md and in-skill SKILL.md bodies, but there is no polished, user-facing docs surface for someone installing kiln/shelf/clay/trim/wheel from the marketplace. A new user installing the plugin has to reverse-engineer how the pieces fit together from skill descriptions and commit history.

## What's missing

- Per-plugin README with a 60-second "what this plugin does + how to start" on-ramp
- Canonical command index for each plugin (what every `/<plugin>:*` command does, in one table)
- Concept pages for the cross-plugin patterns that tie it together: spec-first pipeline (kiln), workflow engine (wheel), Obsidian sync (shelf), product ideation (clay), design-code drift (trim)
- Worked examples: "scaffold a new repo end-to-end", "add a feature to an existing product", "file a bug and watch the background sync"
- Decision docs: when to use `/kiln:kiln-fix` vs `/kiln:kiln-build-prd`; when to run `/shelf:shelf-sync` directly vs let `/kiln:kiln-report-issue` drive it

## Suggested next step

- Decide where the docs live: in-repo `docs/` + published via GitHub Pages, or a separate docs site? Probably in-repo for now.
- Start with per-plugin READMEs (5 files) since those are the shallowest entrypoint.
- Once READMEs settle, promote them into published pages.
