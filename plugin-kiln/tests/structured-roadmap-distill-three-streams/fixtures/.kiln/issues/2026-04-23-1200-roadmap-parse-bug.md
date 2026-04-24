---
title: "Roadmap bullets with colons lose their second half on parse"
type: bug
severity: medium
category: ergonomics
status: open
date: 2026-04-23T12:00:00Z
---

# Roadmap bullets with colons lose their second half on parse

The legacy `/kiln:kiln-roadmap` append path splits on `:` when the user writes
"Add: OAuth flow" and only the first half survives in `.kiln/roadmap.md`.

## Concrete acceptance

- `/kiln:kiln-roadmap "Add: OAuth flow"` preserves the full bullet text.
