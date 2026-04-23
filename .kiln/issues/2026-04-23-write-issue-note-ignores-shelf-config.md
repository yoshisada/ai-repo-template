---
id: 2026-04-23-write-issue-note-ignores-shelf-config
title: shelf-write-issue-note guesses the Obsidian path instead of reading .shelf-config
type: issue
date: 2026-04-23
status: prd-created
prd: docs/features/2026-04-23-pipeline-input-completeness/PRD.md
severity: medium
area: shelf
repo: https://github.com/yoshisada/ai-repo-template
files:
  - .shelf-config
  - plugin-shelf/skills/shelf-write-issue-note
  - plugin-kiln/workflows/kiln-report-issue.json
---

write to obsidian workflow does not look at the shelf.config file it guesses path still.  that is a waste, it should be able to automatically detect the path from the shelf.config.

## Context

`.shelf-config` already contains exactly the values needed to compose the issue note path:

```
base_path = @second-brain/projects
slug = ai-repo-template
dashboard_path = @second-brain/projects/ai-repo-template/ai-repo-template.md
```

The issue-note path should deterministically be `${base_path}/${slug}/issues/<issue-id>.md`. Instead, the write-issue-note step currently infers the path by listing vault directories / guessing, which wastes tool calls, pays the latency cost on every `/kiln:kiln-report-issue` run, and can drift if the guess diverges from what `.shelf-config` says.

## Proposal

In `shelf:shelf-write-issue-note` (and any other shelf write skill that targets a project subdirectory), read `.shelf-config` first and compose the target path from `base_path` + `slug` + the subfolder (`issues/`, `fixes/`, `progress/`, etc.). Fall back to discovery only if `.shelf-config` is missing.

## Acceptance

- `/kiln:kiln-report-issue` → write-issue-note step no longer calls `list_files` to find the project folder.
- The Obsidian path is composed from `.shelf-config` values.
- If `.shelf-config` is missing, the step falls back to the current discovery behavior and warns.
