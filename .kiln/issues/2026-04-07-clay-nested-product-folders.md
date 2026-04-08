---
title: "Support nested product folders in clay (sub-ideas under parent products)"
type: feature-request
severity: medium
category: scaffold
source: manual
github_issue: null
status: open
date: 2026-04-07
---

## Description

Clay's `products/` directory currently assumes a flat structure — one folder per idea. But some ideas are sub-products of a larger product. For example, a "personal-automations" product folder might contain several distinct automation ideas that each go through their own pipeline (idea → research → name → PRD → repo) but share a parent context.

This nesting could also serve as a signal that sub-products share a repo — if multiple ideas live under the same parent folder, they're likely features/modules of the same project rather than standalone products.

Example structure:
```
products/
├── personal-automations/
│   ├── about.md              # Parent product context
│   ├── email-digest/         # Sub-idea with its own pipeline
│   │   ├── idea.md
│   │   └── PRD.md
│   ├── morning-briefing/     # Another sub-idea
│   │   ├── idea.md
│   │   └── research.md
│   └── calendar-sync/
│       └── idea.md
```

## Impact

Without this, users either flatten unrelated ideas into the same folder (losing the parent relationship) or create separate top-level products that should logically be grouped. The `/clay-list`, `/idea`, and `/create-prd` skills would need to understand nested structures and the shared-repo implication.

## Suggested Fix

1. Update `/idea` to detect when a product folder already has sub-folders and offer to create a sub-idea
2. Update `/clay-list` to display nested products with indentation or grouping
3. When multiple sub-ideas exist under a parent, `/create-repo` could suggest (or default to) a single shared repo with the sub-ideas as features/modules
4. Add a `parent` or `group` field to idea metadata to track the relationship
