# Project CLAUDE.md (fixture — classification test)

## Product

This is a spec-first development harness. The product helps maintainers turn ideas, feedback, and friction into spec'd, tested, audited features. Primary user: solo developers shipping product. Key differentiator: capture-to-PRD feedback loop.

## Capture loop

Friction logged today becomes structured input that `/kiln:kiln-distill` later bundles into a feature PRD, which `/kiln:kiln-build-prd` ships. Capture is the canonical way to keep the system improving.

## Mandatory workflow

Every code change MUST follow spec → plan → tasks → implement, because skipping steps silently breaks downstream automation. Without this gate, hooks would have nothing to enforce.

## Available Commands

- `/kiln:kiln-roadmap` — capture a roadmap idea
- `/kiln:kiln-distill` — bundle items into a PRD
- `/kiln:kiln-build-prd` — run the full pipeline
- `/kiln:kiln-fix` — fix a bug
- `/shelf:shelf-sync` — sync to Obsidian

## Custom Preference

I prefer commit messages in past tense. This is a maintainer preference unrelated to drift.
