---
title: "SKILL.md template — add a --minimal variant"
type: improvement
severity: medium
category: templates
status: open
date: 2026-04-21T14:30:00Z
---

# SKILL.md template — add a --minimal variant

## What

`/kiln:kiln-init` should accept `--minimal` (or similar flag) and emit a 30-line skeleton for simple wrapper skills, instead of the full 14-section scaffold that fits multi-step workflows.

## Concrete acceptance

- Running `kiln-init --minimal` in an empty repo produces a SKILL.md that:
  - Has frontmatter (name, description)
  - Has ONE section: "What this does"
  - Has an invocation example
  - No Edge Cases / Step 1-N / Contracts scaffold.
- Running `kiln-init` without `--minimal` produces the current full template.

## Related

Tracks the same underlying issue as `.kiln/feedback/2026-04-20-0900-template-ergonomics.md` (one theme: "template ergonomics / minimal variant").
