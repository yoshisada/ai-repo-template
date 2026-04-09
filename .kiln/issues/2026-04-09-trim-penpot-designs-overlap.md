---
title: "Trim designs on Penpot overlap heavily — needs proper spacing and layout"
type: bug
severity: high
category: skills
source: manual
github_issue: null
status: prd-created
prd: docs/features/2026-04-09-trim-penpot-layout/PRD.md
date: 2026-04-09
---

## Description

When trim creates or pushes designs to Penpot, the generated frames and components overlap each other on the canvas. There's no proper spacing, positioning, or auto-layout between elements, resulting in a cluttered, unusable Penpot file where everything is stacked on top of each other.

## Impact

The Penpot file is unusable for visual editing — you can't see individual components or pages without manually dragging them apart. This defeats the purpose of having designs in Penpot.

## Suggested Fix

1. When creating frames/components in Penpot, calculate proper bounding boxes and add padding between elements
2. Use a grid or flow layout to position top-level frames on the canvas (e.g., pages arranged horizontally with gaps, components arranged in a bento grid)
3. Each page design should be on its own Penpot page or in a clearly separated area of the canvas
4. Components should be organized on a dedicated "Components" page with the bento layout (see related issue: trim-component-page-bento-layout)
