# Data Model: Kiln Rebrand, Infrastructure & QA Reliability

**Date**: 2026-03-31
**Feature**: [spec.md](./spec.md)

## Entities

### Plugin Manifest (`plugin.json`)

Identifies the plugin to the Claude Code platform.

| Field | Type | Description |
|-------|------|-------------|
| name | string | Plugin name: "kiln" (was "speckit-harness") |
| version | string | Semver format: "000.000.000.NNN" |
| description | string | Human-readable plugin description |
| author | object | Author info (name field) |
| homepage | string | GitHub repository URL |

### npm Package (`package.json`)

npm distribution configuration.

| Field | Type | Description |
|-------|------|-------------|
| name | string | Scoped package: "@yoshisada/kiln" |
| bin | object | CLI entry point: `{ "kiln": "./bin/init.mjs" }` |
| keywords | array | Discovery tags, updated from "speckit" to "kiln" |

### Doctor Manifest (`kiln-manifest.json`)

Defines expected project structure for validation and migration.

| Field | Type | Description |
|-------|------|-------------|
| version | string | Manifest schema version |
| directories | object | Map of directory path to config (`{ tracked: boolean }`) |
| migrations | object | Map of legacy path to new path for auto-migration |

### .kiln/ Directory Structure

Standardized directory in consumer projects.

| Subdirectory | Git Tracked | Contents |
|--------------|-------------|----------|
| workflows/ | Yes | Reusable workflow definition files |
| agents/ | No | Per-run agent output directories |
| issues/ | Yes | Issue/backlog tracking files (migrated from docs/backlog/) |
| qa/ | No | QA test artifacts, screenshots, reports |
| logs/ | No | Pipeline and build log files |

### Legacy Path Mappings

Known old paths and their .kiln/ equivalents.

| Legacy Path | New Path | Migration Action |
|-------------|----------|-----------------|
| docs/backlog/ | .kiln/issues/ | Move files, preserve content |
| qa-results/ | .kiln/qa/ | Move files, preserve content |

## State Transitions

### Doctor Workflow

```
Project State: Unknown
  → Doctor Diagnose → Issues Identified (list of findings)
  → Doctor Fix (per issue) → Fix Proposed → User Confirms → Fix Applied
  → All Issues Resolved → Project State: Healthy
```

### QA Version Check

```
Pre-flight Start
  → Read VERSION file
  → Check app version
  → Match? → Proceed with testing
  → Mismatch? → Trigger rebuild → Re-check
    → Match? → Proceed with testing
    → Still mismatch? → Warn team lead → Proceed with disclaimer
```
