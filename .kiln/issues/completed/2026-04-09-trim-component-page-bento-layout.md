---
title: "Trim should create a bento-style component page in Penpot, not a descending list"
type: improvement
severity: medium
category: skills
source: manual
github_issue: null
status: completed
prd: docs/features/2026-04-09-trim-penpot-layout/PRD.md
date: 2026-04-09
completed_date: 2026-04-09
pr: "#80"---

## Description

When trim pushes components to Penpot or generates a design, it should create a dedicated "Components" page that displays all components in a bento grid layout — organized by category, with each component shown at its natural size in a card-like frame. Currently there's no defined layout strategy, which would likely result in a long vertical list of components stacked on top of each other.

## Impact

A flat descending list makes the Penpot component page hard to browse and visually noisy. A bento grid layout lets developers and designers quickly scan the component library, compare sizes, and find what they need.

## Suggested Fix

1. When `/trim-push` or `/trim-design` creates components in Penpot, organize them into a "Components" page with a bento grid layout
2. Group components by category (buttons, inputs, cards, layout, etc.)
3. Each component gets a labeled card/frame at its natural size
4. Auto-arrange to fill the page width, wrapping to new rows
5. Add section headers for each category group
