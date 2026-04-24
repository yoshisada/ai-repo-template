---
id: 2026-04-24-language-agnostic-research
title: "language-agnostic-templates — research what shape the template/lint/audit/test stack takes across Python, Rust, Go"
kind: research
date: 2026-04-24
status: open
phase: 90-queued
state: planned
blast_radius: cross-cutting
review_cost: moderate
context_cost: ~1-2 sessions
---

# language-agnostic-templates — research what shape the template/lint/audit/test stack takes across Python, Rust, Go

## The decision this unblocks

Whether to invest in a language-agnostic porting PRD now, defer it with a documented rationale, or confirm JS/TS-first as a principled opinion and update the vision accordingly. Today the vision commits to language-agnostic as the direction, but the repo has zero evidence of work toward it — all templates, hooks, lint, coverage, and audit tooling are JS/TS-shaped.

## Scope

Walk every JS/TS-specific surface and classify each as one of:

- **Portable as-is** — nothing language-specific, just markdown/shell/JSON.
- **Portable with refactor** — language-specific but isolated to a small surface that could be abstracted behind a language-plugin interface.
- **Principled JS/TS coupling** — would require a fundamentally different design to support another language, and the JS/TS fit is load-bearing.

Surfaces to inspect:

- `plugin-kiln/templates/` — spec / plan / tasks / contracts templates
- `plugin-kiln/bin/init.mjs` — scaffolder (Node-specific)
- Hooks that invoke `npm`, `vitest`, or other JS/TS tooling (`hooks/version-increment.sh`, coverage gate skills)
- PRD audit compliance queries (do they assume JS/TS import syntax?)
- `/kiln:kiln-qa-setup` and the Playwright dependency
- Coverage threshold enforcement (currently `vitest`/`c8`-shaped)
- Any scripts under `plugin-kiln/scripts/` that `grep` or `sed` JS/TS-specific patterns

## Cross-language testing surface (follow-on)

This research is the upstream input to a more intense cross-language testing suite. Output should include: what test fixtures would be needed to verify the system actually works against a Python consumer, a Rust consumer, and a Go consumer — not just that the plugin *installs* (the install-smoke item covers that) but that the full pipeline (specify → plan → tasks → implement → audit → QA → PR) produces a merge-ready PR in each language.

Concretely, the cross-language test suite would:
- Spin up a fresh consumer repo in each target language.
- Run a minimal feature through `/kiln:kiln-build-prd` end-to-end.
- Verify the PR meets the senior-merge-bar (see `2026-04-24-code-review-team-with-static-analysis`) using language-appropriate static analyzers (pylint/ruff, clippy, govet alongside eslint/SonarQube).
- Pass/fail feeds a per-language support matrix — which languages are "production-grade," which are "works but rough," which are "not yet."

This testing suite is a separate feature item (not captured yet — worth a follow-on roadmap entry once this research concludes).

## Time-box

1-2 sessions. This is a classification exercise plus a decision doc, not an implementation.

## What "done" looks like

A decision doc in `.kiln/roadmap/` or `docs/research/` naming:
1. The minimum refactor to unblock a non-JS consumer (if any).
2. What stays JS/TS-first out of genuine principle (if any).
3. Which language to port to first as proof-of-concept (recommendation + rationale).
4. What the cross-language test suite would need to look like to verify porting actually works (shape + approximate scope, not detailed design).
5. Go/no-go recommendation on whether to promote language-agnostic from "vision direction" to "active phase."

## Audience for the conclusion

You. This is pure strategic input — the output informs whether the next phase is about language-agnostic porting or something else entirely.

## Cheapest directional answer first

If the full walk is too expensive, do a 30-minute scan of just the top 5 most JS/TS-coupled surfaces (init.mjs + coverage gate + audit queries + Playwright + one template) and extrapolate from there. Often the answer to "is this a big refactor?" is visible from three or four representative samples.

## Dependencies

- No blocking dependencies — this research is purely a classification + decision exercise.
- Nice-to-have: the cross-language testing suite it points toward would naturally compose with `2026-04-24-code-review-team-with-static-analysis` (which already commits to pluggable static analyzer integration per-language).
