# Benchmark Reference Repo

**Repo**: `yoshisada/ai-repo-template`
**URL**: https://github.com/yoshisada/ai-repo-template.git
**Branch at measurement**: `build/shelf-sync-efficiency-20260410`
**Commit SHA at measurement**: `2973dedb4a0b3cfa8f8235bc30b369830af73e07`
**Obsidian project slug (target vault)**: `ai-repo-template`
**Vault base_path**: `projects`
**Date pinned**: 2026-04-10

## Rationale

This is the same repo where the v3 baseline of 64.5k tokens was recorded on
2026-04-07 for `report-issue-and-sync` (which composes `shelf-full-sync`).
Using the same repo for v4 measurement isolates the workflow change from any
repo-content differences. See `project_workflow_token_usage` memory for the
v3 baseline context.

## Reproduction

1. `cd` into a checkout of this repo at the SHA above.
2. Ensure `.shelf-config` resolves to slug `ai-repo-template`, base_path `projects`.
3. Run `/wheel-run shelf-full-sync` under a wheel-runner agent.
4. Record token cost from the wheel-runner telemetry (per-agent total).

SC-001 gate: v4 MUST come in at ≤30k tokens vs v3's ~64.5k baseline.
