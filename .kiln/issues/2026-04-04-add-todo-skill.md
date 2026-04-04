---
title: "Add /todo skill to kiln"
type: feature-request
severity: medium
category: skills
source: manual
github_issue: null
status: prd-created
prd: docs/features/2026-04-04-kiln-wheel-polish/PRD.md
date: 2026-04-04
---

## Description

Add a `/todo` skill to the kiln plugin. This would provide a user-invocable command for managing TODOs directly within the kiln workflow.

## Impact

Users currently have no kiln-native way to track quick TODOs or ad-hoc items outside of the formal spec/plan/tasks pipeline. A `/todo` skill would fill that gap.

## Suggested Fix

Create a new skill at `plugin-kiln/skills/todo/` with a prompt.md defining the behavior. Scope and exact functionality TBD — needs clarification on what the user envisions (e.g., file-based TODO list, integration with tasks.md, standalone tracking).
