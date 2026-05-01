---
title: "Double back arrow in 'back to steps' button"
type: bug
severity: medium
category: ui
source: manual
github_issue: null
status: open
date: 2026-04-28
repo: https://github.com/yoshisada/ai-repo-template
---

## Description

The "Back to steps" button shows a double arrow (←←) because CSS adds a `::before { content: '←' }` pseudo-element while the button text already contains "← Back to steps".

## Impact

Visual bug that makes the UI look broken.

## Suggested Fix

Remove the arrow from button text since CSS adds it via ::before pseudo-element.

.kiln/issues/007-double-back-arrow.md
