---
id: 2026-04-24-kiln-needs-an-executable-skill-test-harness
title: Executable skill-test harness — invoke skills against /tmp scratch, stop simulating output
type: feedback
date: 2026-04-24
status: prd-created
severity: high
area: architecture
repo: https://github.com/yoshisada/ai-repo-template
prd: docs/features/2026-04-24-plugin-skill-test-harness/PRD.md
---

Kiln needs an executable skill-test harness that actually invokes skills (e.g. /kiln:kiln-distill, /kiln:kiln-build-prd Step 4b, /kiln:kiln-hygiene) against a /tmp scratch project and captures real output — today's SMOKE.md fixtures simulate expected output by hand-composing PRDs and diagnostic lines, which silently misses body-template drift and regressions the simulation can't see. This is now the 4th consecutive retrospective to flag it (pipelines #142, #145, #147, prd-derived-from-frontmatter 2026-04-24). Evidence this run: the implementer caveat on SC-007 ("live end-to-end /kiln:kiln-build-prd run against a consumer repo was not performed from this sandbox"), the POSIX-awk bug (D-1) only caught during Phase E fixture-run on macOS, and 40 LEGACY PRDs under docs/features/ that the backfill subcommand has never been exercised against. Area: architecture (test-infra for our own plugins, not consumer projects). Severity: medium-to-high — every pipeline ships with caveats that a real harness would close, and the risk of latent regressions is growing as the plugin surface grows.
