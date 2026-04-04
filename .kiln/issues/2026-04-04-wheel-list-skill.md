---
title: "Add wheel-list skill to view all available workflows"
type: feature-request
severity: medium
category: skills
source: manual
github_issue: null
status: open
date: 2026-04-04
---

## Description

Create a `/wheel-list` skill that scans the `workflows/` directory and displays all available workflow files with their names, descriptions, and step counts. This gives users a quick overview of what workflows are available to run with `/wheel-run`.

## Impact

Users currently have no built-in way to discover which workflows exist or what they do without manually browsing the `workflows/` directory and reading each JSON file. A list command is a standard UX expectation for any workflow/task runner.

## Suggested Fix

Create `plugin-wheel/skills/wheel-list/` with a skill that:
1. Globs for `workflows/*.json` in the project root
2. Reads each file and extracts the `name`, `description`, and step count
3. Formats a table or list showing: workflow name, description, number of steps
