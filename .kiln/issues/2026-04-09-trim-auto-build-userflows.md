---
title: "Trim should auto-build user flows in .trim/flows.json during push and other commands"
type: improvement
severity: medium
category: skills
source: manual
github_issue: null
status: prd-created
prd: docs/features/2026-04-09-trim-penpot-layout/PRD.md
date: 2026-04-09
---

## Description

When trim runs `/trim-push`, `/trim-pull`, `/trim-design`, or other commands that scan or create components, it should automatically build and update `.trim/flows.json` with discovered user flows. Currently flows are only managed via the separate `/trim-flows` skill, meaning users have to manually define flows even though trim already has enough context to infer them from the code structure (routes, page components, navigation) and Penpot page/frame organization.

## Impact

Without auto-building flows, the user flow tracking feature requires extra manual setup that most users will skip. This means `/trim-verify` has nothing to walk, and QA test generation from flows won't work out of the box.

## Suggested Fix

1. During `/trim-push`: scan code for routes, page-level components, and navigation patterns → auto-populate `.trim/flows.json` with discovered flows
2. During `/trim-pull`: read Penpot page/frame organization → infer flows from page ordering and linked frames
3. During `/trim-design`: the design generation already knows the user journeys from the PRD → write them to `.trim/flows.json` as part of design creation
4. All commands should merge with existing flows (don't overwrite manual entries), flagging auto-discovered ones with `"source": "auto-discovered"`
