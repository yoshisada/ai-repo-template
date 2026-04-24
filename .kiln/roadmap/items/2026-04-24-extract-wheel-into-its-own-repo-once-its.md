---
id: 2026-04-24-extract-wheel-into-its-own-repo-once-its
title: "Extract wheel into its own repo once its API is stable"
kind: feature
date: 2026-04-24
status: open
phase: 90-queued
state: planned
blast_radius: infra
review_cost: expert
context_cost: 3+ sessions
---

# Extract wheel into its own repo once its API is stable

need to separate wheel workflow from this repo as its becoming its own product.

Timing framing: late but definite. Happens after we're confident wheel is in a good place — do not attempt before the API is demonstrably stable.

## Hardest part

Cross-plugin path resolution. Today, kiln/shelf/clay/trim workflows reference `plugin-wheel/scripts/...` as repo-relative paths. Post-extraction, wheel lives at a separate plugin cache path (e.g., `~/.claude/plugins/cache/yoshisada-speckit/wheel/<ver>/`). Every consumer reference needs to resolve wheel's install dir dynamically — a `${WHEEL_PLUGIN_DIR}` equivalent to the existing `${WORKFLOW_PLUGIN_DIR}`. Until that resolver exists, separation silently breaks every workflow in every consumer plugin (the symptom CLAUDE.md already warns about in its Plugin Workflow Portability section). Local dev loop is a solvable follow-up once the resolver lands — worst case, symlink the plugin cache entry to a local checkout.

## Assumptions

Wheel's API is stable enough to freeze at separation time — the consumer surface (workflow JSON schema, state-file shape, hook contract) won't need breaking changes for a while. If it does, post-extraction churn means coordinated releases across 4+ plugins every time. Also assuming: Claude Code's plugin runtime gains a `${WHEEL_PLUGIN_DIR}`-style cross-plugin resolver before we pull the trigger.

If API changes do happen post-separation, target backwards-compat. Alternative: build a version-upgrade feedback loop (wheel detects consumer running on older API, suggests migration or auto-rewrites) — this is potentially its own future roadmap item.

## Dependencies

No hard item-level dependencies in the current roadmap — this is a timing constraint ("after wheel's API is confident"), not a link to another captured item. The real gate is external: a cross-plugin path-resolution primitive in Claude Code's workflow engine needs to exist before extraction.

## Cheaper 80% version

Soft separation first. Freeze wheel's public API contract and document it as if already separated. Publish a read-only mirror at `github.com/yoshisada/wheel` via `git subrepo` for external discoverability. Zero migration risk, exposes contract violations as they happen, keeps dev ergonomics unchanged. Full physical extraction becomes mechanical once the contract has been stable for N months with no breaking changes.

The extraction also needs a folder restructure — the current `plugin-wheel/` layout is optimized for in-repo living, not standalone. Separate-repo layout needs its own top-level organization (`scripts/`, `workflows/`, `tests/`, `docs/`) rather than inheriting kiln's nested shape.

## What breaks if the cross-plugin resolver isn't ready

Every workflow referencing `plugin-wheel/scripts/...` silently fails after extraction — the exact symptom CLAUDE.md's Plugin Portability section warns about: "No such file or directory," downstream steps continue with empty input, produces plausible-looking but wrong output. Discovery is painful — consumer repos won't notice until a specific workflow fires, often in production. Mitigation: gate the separation PR on the cross-plugin resolver primitive landing in Claude Code first.
