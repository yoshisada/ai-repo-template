---
id: 2026-04-24-install-smoke-ci
title: "install-smoke-ci — fresh-environment install smoke test in CI"
kind: feature
date: 2026-04-24
status: open
phase: 90-queued
state: planned
blast_radius: feature
review_cost: moderate
context_cost: ~1 session
---

# install-smoke-ci — fresh-environment install smoke test in CI

## Intent

Make the vision commitment "install must not be clunky" verifiable. Today it's a promise; CI doesn't actually confirm the install works in a clean environment, so a transitive dependency bump, a node-version mismatch, or a shell-compat regression would only be discovered by a frustrated adopter.

## Hardest part

Keeping the smoke test honest — it has to run in an environment genuinely representative of "fresh adopter on their machine," not one that's been incrementally stabilized to pass. Easy to accidentally bake repo-specific assumptions in.

## Assumptions

- CI (GitHub Actions) is acceptable as the substrate — no need for a separate test harness.
- A thin container image (e.g., `node:20-alpine` or similar) is close enough to "fresh adopter" for the smoke test to be meaningful.
- Core install paths worth covering: `npx @yoshisada/kiln init` (published npm), `/kiln:kiln-init` skill invocation, and the plugin-via-marketplace install path.

## Architecture

- Scheduled nightly + triggered on PRs that touch `plugin-kiln/bin/init.mjs`, `scaffold/`, `package.json`, or the marketplace manifest.
- Steps:
  1. Spin up a clean container with only node + claude CLI.
  2. Create an empty git repo.
  3. Run `npx @yoshisada/kiln init` (or equivalent).
  4. Verify expected artifacts: `.kiln/`, `.specify/`, hooks registered in `.claude/settings.json`, plugin workflows resolvable.
  5. Run a known-good smoke command (e.g., `/kiln:kiln-next`) and assert it returns without error.
  6. Tear down container.
- Output: pass/fail + artifact archive of the scaffolded directory on failure (so debugging doesn't require local repro).
- Optional: health badge in top-level README fed from the nightly run.

## Dependencies

- Noted as a follow-on to `kiln-docs` — together they make onboarding a first-class commitment rather than aspirational. `kiln-docs` surfaces *how* to install; this item verifies the install *works*.

## Failure modes to avoid

- **Smoke test that passes in CI but fails on real machines** — avoid overly-specific CI-only fixtures; use standard images.
- **Smoke test that flakes on transitive-dep network fetches** — pin or cache dependencies in the CI image so flakiness doesn't erode trust in the signal.
- **Smoke test that drifts from real consumer experience** — if a consumer's workflow is "install + run `/kiln:kiln-init` + run one skill," the smoke test's verification step should match that flow, not a synthetic assertion that doesn't prove the consumer is productive.

## Success signal

- A regression in install (node version break, missing scaffold file, hook path rot) is caught by CI before an adopter files an issue.
- Over time, the install-smoke pass-rate becomes a proxy metric for the vision's "onboarding is a commitment" claim.
