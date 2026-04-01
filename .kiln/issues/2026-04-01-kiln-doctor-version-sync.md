---
title: "Add version file sync check to kiln-doctor"
type: feature-request
severity: medium
category: skills
source: manual
github_issue: null
status: prd-created
prd: docs/features/2026-04-01-qa-tooling-templates/PRD.md
date: 2026-04-01
---

## Description

Extend `/kiln-doctor` to scan the project for all files that contain version strings (e.g., `package.json`, `plugin.json`, `pyproject.toml`, `Cargo.toml`, `setup.cfg`, etc.) and verify they are in sync with the canonical `VERSION` file. Currently the version-increment hook updates `VERSION` and `plugin/package.json`, but consumer projects may have additional version references that drift out of sync.

## Impact

- Version mismatches between `VERSION` and other package manifests cause confusing releases
- The current hook only knows about `VERSION` and `plugin/package.json` — any other version-bearing file is invisible
- Manual version bumps via `version-bump.sh` may miss project-specific files

## Suggested Fix

1. Add a version-sync check to `/kiln-doctor` that scans for common version-bearing files (`package.json`, `*.toml`, `*.cfg`, `*.yaml`, etc.)
2. Compare each discovered version against the canonical `VERSION` file
3. In fix mode, offer to update mismatched files
4. Allow a `.kiln/version-sync.json` config to declare which files should track the VERSION (so projects can opt in additional files or exclude false positives)
