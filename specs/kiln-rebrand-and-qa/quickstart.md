# Quickstart: Kiln Rebrand, Infrastructure & QA Reliability

## Overview

This feature renames the plugin from "speckit-harness" to "kiln", establishes the `.kiln/` directory as the central artifact store, adds a doctor/migration tool, and fixes QA stale-build testing.

## Implementation Order

1. **Rename** (Phase 1): Package name, plugin manifest, skill directories, all cross-references, documentation
2. **.kiln/ Infrastructure** (Phase 2): Directory structure, init.mjs updates, gitignore, artifact routing in skills
3. **Kiln Doctor** (Phase 3): Manifest template, new skill, diagnose + fix modes
4. **QA Version Check** (Phase 4): Pre-flight instructions in qa-engineer agent, qa-pass skill, ux-evaluate skill

## Key Files

| File | What Changes |
|------|-------------|
| `plugin/package.json` | Package name, bin entry |
| `plugin/.claude-plugin/plugin.json` | Plugin name |
| `plugin/bin/init.mjs` | Branding, .kiln/ scaffold |
| `plugin/skills/speckit-*` | Directory renames (drop prefix) |
| All SKILL.md files | Cross-reference updates |
| `plugin/scaffold/gitignore` | .kiln/ exclusions |
| `plugin/agents/qa-engineer.md` | Version pre-flight |
| `CLAUDE.md` | All branding |
| `plugin/scaffold/CLAUDE.md` | All branding |

## New Files

| File | Purpose |
|------|---------|
| `plugin/skills/kiln-doctor/SKILL.md` | Doctor skill definition |
| `plugin/templates/kiln-manifest.json` | Expected project structure manifest |
| `plugin/templates/workflow-format.md` | Workflow format specification |

## Validation

- Grep entire plugin directory for "speckit-harness" — must return zero matches
- Run init.mjs on a test project — `.kiln/` directory created with all subdirectories
- Verify all skill directories renamed and discoverable
- Check qa-engineer.md contains version verification pre-flight
