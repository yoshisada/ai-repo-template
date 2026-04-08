---
title: "Init script should not create src/ and tests/ directories"
type: improvement
severity: medium
category: scaffold
source: manual
github_issue: null
status: open
date: 2026-04-08
---

## Description

The `kiln init` script (`plugin-kiln/bin/init.mjs`) creates `src/` and `tests/` directories during project scaffolding. However, many repos have different structures (e.g., `lib/`, `app/`, monorepo layouts) and don't use a `src/` convention. Creating these directories adds clutter and implies a structure that may not match the project.

## Impact

Users running `/init` on existing repos with non-standard layouts get unnecessary empty directories that they have to clean up. It can also be confusing about whether kiln expects code to live in `src/`.

## Suggested Fix

Remove the `src/` and `tests/` directory creation from `init.mjs`. The scaffold should only create kiln-specific directories (`.kiln/`, `specs/`, etc.) and leave project structure decisions to the user.
