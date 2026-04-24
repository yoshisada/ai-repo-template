---
last_updated: 2026-04-24
---

# Product Vision

## What we are building

A coach-driven capture substrate for small product teams: four surfaces that
propose evidence-cited defaults instead of interrogating the user.

## What it is not

Not a general-purpose project management platform, not a replacement for git.

## How we'll know we're winning

Users accept the suggested answer on ≥60% of interview questions; first-run
`/kiln:kiln-roadmap --vision` produces a complete draft on the first pass in
≥90% of populated repos.

## Guiding constraints

- Propose-don't-apply stays load-bearing across every surface.
- Offline-safe — only `/kiln:kiln-claude-audit` may touch the network, and
  always with a cached-fallback path.
- Backward compatibility: `--quick` and single-theme paths stay byte-identical.
