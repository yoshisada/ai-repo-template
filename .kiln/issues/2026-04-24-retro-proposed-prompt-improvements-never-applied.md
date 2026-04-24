---
title: Retrospective-proposed prompt improvements (PI-1..PI-N) never get pulled back into the source tree
type: improvement
severity: medium
category: workflow
status: open
date: 2026-04-24
repo: https://github.com/yoshisada/ai-repo-template
files:
  - plugin-kiln/skills/kiln-build-prd/SKILL.md
---

# Retrospective-proposed prompt improvements never get pulled back into the source tree

## Description

Retrospectives propose specific prompt rewrites in `File/Current/Proposed/Why` format inside GitHub issues (e.g. `#147`, `#149`, `#152` each contain multiple PIs), but there is no mechanism that pulls those rewrites back into `plugin-kiln/skills/**/SKILL.md` or `plugin-kiln/agents/**.md`. They sit in issue bodies forever, and each new auditor / implementer / specifier re-discovers the same friction.

Net result: retrospective work documents drift rather than driving improvement. Every pipeline repeats the same prompt-clarity bugs that prior retros already diagnosed.

## Concrete recurring examples

- **PI-1** (retros #147, #149, #152): add R-1 "strict behavioral superset" blessing to the auditor brief with the five enumerated precedents. Proposed three times. Never applied. Auditors keep re-discovering R-1 by reading prior friction notes.
- **PI-2** (retro #149): disambiguate the "FR-005" collision in `plugin-kiln/skills/kiln-build-prd/SKILL.md` — it currently refers to BOTH the spec-dir-naming rule (build-prd internal) AND to whatever FR-005 happens to be in a given feature spec. Specifiers hit this collision again in the plugin-skill-test-harness pipeline.
- **Version-bump drift** (retro #152): `SKILL.md` says "bump pr segment" but auditors have been bumping feature segment when the work is substantial. The instruction is out of sync with practice.
- **Task-#2-reopen pattern undocumented**: happens when downstream audits (e.g. BLOCKER-002 in the test-harness pipeline) reveal a real bug in "completed" implementer work. `SKILL.md` doesn't describe the reopen flow, so it feels ad-hoc every time.

## Reproduction

100% repro: open any recent retro issue (#147, #149, #152), diff the proposed SKILL.md rewrites against current `plugin-kiln/skills/kiln-build-prd/SKILL.md`. Every proposal still unapplied.

## Expected

Some mechanism — skill, workflow, or periodic distill filter — that takes retro-issue proposals and either applies them (with human review) or explicitly rejects them, so the proposals don't accumulate forever.

## Actual

Proposals accumulate in GitHub issue bodies. No lifecycle. No mechanism to pull them into the source tree.

## Suggested fix vectors

1. **`/kiln:kiln-pi-apply` skill**: reads open retrospective issues (label: `retrospective`), extracts `File/Current/Proposed/Why` blocks, produces a propose-don't-apply diff preview under `.kiln/logs/pi-apply-<timestamp>.md`. Same discipline as `/kiln:kiln-claude-audit` / `/kiln:kiln-hygiene` / hygiene backfill — writes a diff, does not apply. Maintainer reviews and applies manually. Fits the existing "propose-don't-apply" pattern family (PP-6 from retro #149).
2. **Distill filter**: `/kiln:kiln-distill --retros` that groups PIs from retrospective issues into a dedicated PRD on some cadence (monthly?), so the prompt rewrites flow through the full build-prd pipeline.
3. **Short-term manual triage**: go through retro issues #147, #149, #152 and apply obviously-stable PIs directly (PI-1 especially — R-1 is now at 5 stable occurrences; zero risk to codify).

Recommendation: start with (3) for the most-established PIs, then build (1) to close the lifecycle gap.

## Priority

Medium. Not blocking individual pipelines. But the cost grows every pipeline — each retro adds more PIs and the backlog is purely accumulative.
