---
title: "trim-push should build full page compositions, not just isolated components"
type: friction
severity: high
category: skills
source: manual
github_issue: null
status: completed
prd: docs/features/2026-04-09-plugin-polish-and-skill-ux/PRD.md
completed_date: 2026-04-09
pr: "#82"
date: 2026-04-09
---

## Description

The trim-push workflow instruction says "creates/updates Penpot components via MCP from code analysis" — which agents interpret too literally as pushing isolated component library entries only. Pages (ChoreHomePage.tsx, MembersPage.tsx, auth pages, layouts) are components too and should be pushed as full-screen Penpot frames that compose the smaller components.

The agent reads every page file, understands the full app structure, has the route map from flow discovery — but only creates individual component definitions instead of full composed page designs. The flow discovery step is a hint: why discover flows if there aren't full pages to connect them?

## Impact

The Penpot file ends up with a component library but no page designs. You can't visualize the actual app — just disconnected building blocks. This makes /trim-verify, /trim-diff, and flow-based testing useless because there are no full pages to screenshot or compare.

## Suggested Fix

1. Update the trim-push workflow agent instruction to explicitly distinguish between:
   - **Component-level push**: individual reusable components → Components page (bento grid)
   - **Page-level push**: full page/route compositions → separate Penpot pages, each as a full-screen frame composing the component library
2. The scan-components command step should classify files as "component" vs "page" based on:
   - Directory (components/ vs pages/ vs app/ routes)
   - Whether the file is referenced in the router
   - Whether it imports layout components
3. Update the wording from "push code components to Penpot" to "push code components AND pages to Penpot — components go to the Components page, pages go to their own Penpot pages as full composed designs"
