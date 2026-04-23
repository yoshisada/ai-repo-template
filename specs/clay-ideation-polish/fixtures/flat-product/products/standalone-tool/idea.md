---
title: Standalone Tool
slug: standalone-tool
date: 2026-04-22
---

This fixture represents a legacy flat product created before the ideation-polish
PRD. It has no `intent:` frontmatter (tests NFR-002 missing-intent default) and
no `parent:` frontmatter.

Expected behavior:
- `/clay:clay-list` renders it as a flat row with no indentation.
- `/clay:clay-idea-research`, `/clay:clay-new-product` treat its intent as `marketable`.
- `/clay:clay-create-repo` treats it as a flat product (no shared-repo prompt).
