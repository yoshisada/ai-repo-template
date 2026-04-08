# Implementation Plan: Clay Idea Entrypoint

**Branch**: `build/clay-idea-entrypoint-20260407` | **Date**: 2026-04-07 | **Spec**: `specs/clay-idea-entrypoint/spec.md`
**Input**: Feature specification from `specs/clay-idea-entrypoint/spec.md`

## Summary

Add `/clay:idea` as the single entrypoint to the clay plugin that takes a raw idea, scans `products/` and `clay.config` for semantic overlap, presents routing options (new product / existing product / existing repo / similar but distinct), and chains to the correct downstream skill with user confirmation. Also introduce `clay.config` as a plain-text repo registry and update `/clay:create-repo` and `/clay:clay-list` to read/write it.

## Technical Context

**Language/Version**: Markdown skills + Bash (inline shell in SKILL.md files)
**Primary Dependencies**: Claude Code plugin system, existing clay skills
**Storage**: `clay.config` plain-text file at project root (one line per tracked repo)
**Testing**: Manual validation via skill invocation (no automated test suite for plugins)
**Target Platform**: Claude Code CLI / desktop / web
**Project Type**: Claude Code plugin (Markdown skill definitions with embedded Bash)
**Constraints**: No JSON/YAML for clay.config — must be plain-text, human-readable
**Scale/Scope**: 1 new skill file, 2 modified skill files, 1 new config format

## Constitution Check

| Gate | Status | Notes |
|------|--------|-------|
| Spec-first | PASS | spec.md written with 5 user stories, 14 FRs |
| Interface contracts | PASS | contracts/interfaces.md defines skill file structures |
| 80% test coverage | N/A | Plugin skills are Markdown — no automated test suite |
| E2E testing | N/A | Validated via manual skill invocation |
| Small focused changes | PASS | 3 files total (1 new, 2 modified) |

## Project Structure

### Documentation (this feature)

```text
specs/clay-idea-entrypoint/
├── spec.md
├── plan.md              # This file
├── contracts/
│   └── interfaces.md    # Skill file contracts
└── tasks.md             # Task breakdown
```

### Source Code (plugin files)

```text
plugin-clay/skills/
├── idea/
│   └── SKILL.md           # NEW — /clay:idea entrypoint (FR-001 through FR-007)
├── create-repo/
│   └── SKILL.md           # MODIFIED — append to clay.config (FR-009, FR-013)
└── clay-list/
    └── SKILL.md           # MODIFIED — read clay.config (FR-011, FR-014)

# Project root
clay.config                # NEW format — created by create-repo, read by idea + clay-list
```

**Structure Decision**: Plugin skill files live under `plugin-clay/skills/<skill-name>/SKILL.md`. No new directories beyond `idea/`. The `clay.config` file lives at the consumer project root (not in the plugin source).

## Design Decisions

### 1. Overlap Detection is LLM Reasoning (not Bash)

The idea skill compares the user's idea against product descriptions and repo entries using the LLM's semantic understanding. There is no `grep` or `diff` heuristic — the skill instructions tell Claude to read the artifacts and reason about overlap. This is the right approach because:
- Ideas are fuzzy natural language
- Product descriptions vary in format
- Similarity is subjective and context-dependent

### 2. clay.config Format

```
<product-slug> <repo-url> <local-path> <created-date>
```

Example:
```
habit-tracker https://github.com/yoshisada/habit-tracker ../habit-tracker 2026-04-07
notes-app https://github.com/yoshisada/notes-app ../notes-app 2026-04-05
```

Rules:
- One entry per line
- Fields separated by spaces
- No header line (pure data)
- Lines starting with `#` are comments (future-proofing)
- Malformed lines are skipped with a warning

### 3. Routing Options

The idea skill presents exactly these options after overlap analysis:

| Route | When | Chains to |
|-------|------|-----------|
| New product | No overlap found | `/idea-research` → `/project-naming` → `/create-prd` |
| Add to existing product | Overlap with product in `products/` | `/create-prd` Mode C targeting matched product |
| Work in existing repo | Overlap with tracked repo in `clay.config` | Suggest `cd <local-path> && /build-prd` or `/clay:idea` |
| Similar but distinct | Partial overlap — ambiguous | Let user decide which route |

### 4. create-repo Integration Point

The clay.config append happens after Step 7 (initial commit and push succeeds) and before Step 8 (write status marker). This ensures we only track repos that were actually created. The append uses `>>` (not `>`) to avoid overwriting existing entries.

### 5. clay-list Integration Point

The clay-list skill gains two new columns in its output table: "Repo URL" and "Local Path". These are populated by reading clay.config and matching entries by product slug. If clay.config doesn't exist, these columns are omitted entirely (not shown as empty).

## Phases

### Phase 1: Create `/clay:idea` skill (FR-001 through FR-007, FR-010, FR-012)
- New file: `plugin-clay/skills/idea/SKILL.md`
- Reads products/ for existing products
- Reads clay.config for tracked repos
- Performs semantic overlap analysis
- Presents routing options
- Chains to downstream skills with user confirmation

### Phase 2: Update `/clay:create-repo` (FR-009, FR-013)
- Modify: `plugin-clay/skills/create-repo/SKILL.md`
- Add step between Step 7 and Step 8 to append to clay.config
- Create clay.config if it doesn't exist

### Phase 3: Update `/clay:clay-list` (FR-011, FR-014)
- Modify: `plugin-clay/skills/clay-list/SKILL.md`
- Read clay.config and match entries by slug
- Add Repo URL and Local Path columns to output table

### Phase 4: Polish
- Verify all three skills work together
- Check that existing clay skills are unaffected
